# Export all fitted-model results to JSON for the lay-reader explorer
# (output/explorer.html). Reads the .rds model objects saved by R/08-11,
# so the app can never disagree with the estimates.

library(data.table)
library(arrow)
library(fixest)
library(jsonlite)

types <- c("flood", "drought", "earthquake", "storm")

matrix_models <- readRDS("output/models/matrix_models.rds")
es_models     <- readRDS("output/models/event_study_models.rds")
sector_models <- readRDS("output/models/sector_scan_models.rds")
joint_models  <- readRDS("output/models/joint_models.rds")

get_row <- function(m, token) {
  ct <- coeftable(m)
  hit <- vapply(rownames(ct),
                function(r) token %in% strsplit(r, ":", fixed = TRUE)[[1]],
                logical(1))
  if (sum(hit) != 1) return(NULL)
  list(b = unname(ct[hit, 1]), se = unname(ct[hit, 2]),
       p = unname(ct[hit, 4]))
}

# Treated country-year counts
panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))
panel <- panel[year >= 2001]
cy <- unique(panel[, c("iso3", "year", paste0(types, "_dummy"),
                       paste0(types, "_severe_dummy")), with = FALSE])
counts <- lapply(setNames(types, types), function(d)
  list(any    = cy[, sum(get(paste0(d, "_dummy")))],
       severe = cy[, sum(get(paste0(d, "_severe_dummy")))]))

# Matrix: type x outcome x term
mat <- lapply(setNames(types, types), function(d) {
  lapply(list(val = "_val", qty = "_qty"), function(sfx) {
    m <- matrix_models[[paste0(d, sfx)]]
    list(t0 = get_row(m, paste0(d, "_dummy")),
         t1 = get_row(m, paste0(d, "_dummy_lag1")),
         s0 = get_row(m, paste0(d, "_severe_dummy")),
         s1 = get_row(m, paste0(d, "_severe_dummy_lag1")))
  })
})

# Joint spec (all four types at once): same shape as `matrix`
jmat <- lapply(setNames(types, types), function(d) {
  lapply(list(val = "joint_val", qty = "joint_qty"), function(nm) {
    m <- joint_models[[nm]]
    list(t0 = get_row(m, paste0(d, "_dummy")),
         t1 = get_row(m, paste0(d, "_dummy_lag1")),
         s0 = get_row(m, paste0(d, "_severe_dummy")),
         s1 = get_row(m, paste0(d, "_severe_dummy_lag1")))
  })
})

# Event studies: type x any/sev, time -1..2, value and tons
es_block <- function(model_suffix) {
  lapply(setNames(types, types), function(d) {
    lapply(list(any = "_dummy", sev = "_severe_dummy"), function(sfx) {
      nm <- paste0(d, if (sfx == "_dummy") "_any" else "_sev", model_suffix)
      m <- es_models[[nm]]
      v <- paste0(d, sfx)
      toks <- c(paste0(v, "_lead1"), v, paste0(v, "_lag1"), paste0(v, "_lag2"))
      Map(function(tk, t) c(list(t = t), get_row(m, tk)), toks, c(-1, 0, 1, 2))
    })
  })
}
es     <- es_block("")        # export value
es_qty <- es_block("_qty")    # tons: the headline outcome needs its own leads

# Sector scan: type x outcome x sector x (t0, t1). Each cell carries the
# raw p AND a Benjamini-Hochberg p adjusted within its own scan (all
# sector x term cells of one type x outcome model) - the site stars on
# p_bh so 60+ simultaneous cells don't manufacture discoveries.
sectors <- sort(unique(panel$sector_group))
sectors <- setdiff(sectors, "chemicals")   # reference category (R/10)
sec <- lapply(setNames(types, types), function(d) {
  lapply(list(val = "_val", qty = "_qty"), function(sfx) {
    ct <- coeftable(sector_models[[paste0(d, sfx)]])
    scan_rows <- rownames(ct)[grepl("^sector_group::", rownames(ct))]
    bh <- setNames(p.adjust(ct[scan_rows, 4], method = "BH"), scan_rows)
    out <- lapply(setNames(sectors, sectors), function(s) {
      r0 <- sprintf("sector_group::%s:%s_dummy", s, d)
      r1 <- sprintf("sector_group::%s:%s_dummy_lag1", s, d)
      g <- function(rn) if (rn %in% rownames(ct))
        list(b = unname(ct[rn, 1]), se = unname(ct[rn, 2]),
             p = unname(ct[rn, 4]), p_bh = unname(bh[rn])) else NULL
      list(t0 = g(r0), t1 = g(r1))
    })
    out[!vapply(out, function(x) is.null(x$t0), logical(1))]
  })
})

# Country effects. SEs are year-clustered; rows that looked significant
# also carry a permutation p (R/15). Selection for the headline list is
# disclosed on the site: value effect negative with permutation p < .10
# in year t or t+1, ranked by the worse coefficient - a rule that picks
# extremes, so displayed magnitudes are biased outward (winner's curse;
# said in the table note). The full set of estimated countries ships as
# `country_all`, signed, unselected.
ce <- readRDS("output/models/country_effects.rds")
cw <- dcast(ce, type + iso3 + name + n_ev + n_sev ~ outcome,
            value.var = c("b0", "se0", "p0", "b1", "se1", "p1",
                          "perm_p0", "perm_p1"))
cw[, worst := pmin(ifelse(!is.na(perm_p0_val) & perm_p0_val < 0.1, b0_val, Inf),
                   ifelse(!is.na(perm_p1_val) & perm_p1_val < 0.1, b1_val, Inf))]
cellval <- function(b, se, p, pp)
  if (is.na(b)) NULL else {
    x <- list(b = b, se = se, p = p)
    if (!is.na(pp)) x$perm_p <- pp
    x
  }
country <- lapply(setNames(types, types), function(d) {
  rows <- cw[type == d & worst < 0]
  setorder(rows, worst)
  rows <- head(rows, 10)
  lapply(seq_len(nrow(rows)), function(i) {
    r <- rows[i]
    list(iso3 = r$iso3, name = r$name, n_ev = r$n_ev, n_sev = r$n_sev,
         val = list(t0 = cellval(r$b0_val, r$se0_val, r$p0_val, r$perm_p0_val),
                    t1 = cellval(r$b1_val, r$se1_val, r$p1_val, r$perm_p1_val)),
         qty = list(t0 = cellval(r$b0_qty, r$se0_qty, r$p0_qty, r$perm_p0_qty),
                    t1 = cellval(r$b1_qty, r$se1_qty, r$p1_qty, r$perm_p1_qty)))
  })
})
country_all <- lapply(setNames(types, types), function(d) {
  rows <- cw[type == d]
  setorder(rows, name)
  lapply(seq_len(nrow(rows)), function(i) {
    r <- rows[i]
    list(iso3 = r$iso3, name = r$name, n_ev = r$n_ev,
         val = list(t0 = cellval(r$b0_val, r$se0_val, r$p0_val, r$perm_p0_val),
                    t1 = cellval(r$b1_val, r$se1_val, r$p1_val, r$perm_p1_val)))
  })
})

# Market-share leaders per sector (top 5 exporters)
lead <- readRDS("output/models/price_leaders.rds")
leaders <- lapply(split(lead, by = "sector_group"), function(g)
  lapply(seq_len(nrow(g)), function(i)
    list(iso3 = g$iso3[i], name = g$name[i],
         share = round(100 * g$share[i], 1), n_sev = g$n_sev[i])))

# World unit-value models: effect of share-weighted severe events
pm <- readRDS("output/models/price_models.rds")
price <- lapply(setNames(types, types), function(d) {
  ct <- coeftable(pm[[d]])
  g <- function(rn) list(b = unname(ct[rn, 1]), se = unname(ct[rn, 2]),
                         p = unname(ct[rn, 4]))
  list(t0 = g("D"), t1 = g("D_lag"))
})

# n_cells is the completed cube (pre-estimation); estimation nobs are
# slightly smaller after fixest drops separated/absorbed cells.
data <- list(counts = counts, matrix = mat, joint = jmat,
             es = es, es_qty = es_qty,
             sectors = sec,
             country = country, country_all = country_all,
             leaders = leaders, price = price,
             n_cells = nrow(panel), n_countries = uniqueN(panel$iso3),
             n_chapters = uniqueN(panel$chapter),
             years = "2001-2024")
writeLines(paste0("window.DATA = ",
                  toJSON(data, auto_unbox = TRUE, digits = 6), ";"),
           "output/explorer_data.js")
message("Done. Data: output/explorer_data.js")
