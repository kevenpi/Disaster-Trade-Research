# Country-level heterogeneity: which countries are hit hardest by each
# disaster type? One PPML per country x type x outcome, using the same
# within-country identification as the pooled model (exposed vs unexposed
# chapters, chapter + year FE). Only countries with enough events AND
# enough disaster-free years to form a contrast are estimated.
#
# Inference (July 2026 audit): within one country the disaster dummy
# varies only across YEARS, so clustering by chapter is anticonservative
# (it treats 90+ chapters as independent evidence about ~24 years).
# SEs cluster by year here. Because ~24 year-clusters is itself modest,
# every estimate with a year-clustered p < .10 also gets a permutation
# p-value: event-year labels are shuffled within the country (200
# draws), the model is re-fit, and perm_p = share of draws with |b| at
# least as large as observed. Downstream tables should quote perm_p
# where available.
#
# Eligibility disclosure (for any table built from this): >= 6 event
# years and >= 6 clean years excludes both the never-hit and the
# ALWAYS-hit - CHN, USA, IND, BRA, PAK, BGD, PHL fail the clean-years
# side for floods, one-hurricane islands fail the event side - and
# larger exporters are ~3.5x likelier to be eligible.
# Saves a compact results table: output/models/country_effects.rds

library(data.table)
library(arrow)
library(fixest)

panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))
panel <- panel[year >= 2001]

types <- c("flood", "drought", "earthquake", "storm")
N_PERM <- 200
set.seed(20260725)

res <- list()
for (d in types) {
  dm  <- paste0(d, "_dummy")
  dml <- paste0(d, "_dummy_lag1")
  ex  <- paste0(d, "_exposed")
  cy  <- unique(panel[, .(iso3, year, ev = get(dm), sev = get(paste0(d, "_severe_dummy")))])
  cnt <- cy[, .(n_ev = sum(ev), n_no = sum(1 - ev), n_sev = sum(sev)), by = iso3]
  elig <- cnt[n_ev >= 6 & n_no >= 6, iso3]
  message(d, ": ", length(elig), " eligible countries")
  for (cc in elig) {
    sub <- panel[iso3 == cc]
    if (sub[, sum(export_value > 0)] < 500) next
    for (out in c("val", "qty")) {
      y <- if (out == "val") "export_value" else "export_qty"
      f <- as.formula(sprintf("%s ~ %s:%s + %s:%s | chapter + year",
                              y, dm, ex, dml, ex))
      m <- tryCatch(
        fepois(f, data = sub, cluster = ~year, notes = FALSE),
        error = function(e) NULL)
      if (is.null(m)) next
      ct <- tryCatch(coeftable(m), error = function(e) NULL)
      if (is.null(ct)) next
      g <- function(tok, tab = ct) {
        hit <- vapply(rownames(tab),
                      function(r) tok %in% strsplit(r, ":", fixed = TRUE)[[1]],
                      logical(1))
        if (sum(hit) != 1) return(c(NA_real_, NA_real_, NA_real_))
        c(tab[hit, 1], tab[hit, 2], tab[hit, 4])
      }
      r0 <- g(dm); r1 <- g(dml)

      # Permutation p for anything that looks significant
      pp0 <- NA_real_; pp1 <- NA_real_
      if (isTRUE(min(r0[3], r1[3], na.rm = TRUE) < 0.1)) {
        yrs    <- sort(unique(sub$year))
        ev_obs <- cy[iso3 == cc][order(year), ev]
        hits0 <- 0L; hits1 <- 0L; valid <- 0L
        for (k in seq_len(N_PERM)) {
          ev_p  <- sample(ev_obs)
          map   <- data.table(year = yrs, dm_p = ev_p,
                              dml_p = shift(ev_p, 1, fill = 0))
          subp  <- merge(sub, map, by = "year")
          fp <- as.formula(sprintf("%s ~ dm_p:%s + dml_p:%s | chapter + year",
                                   y, ex, ex))
          mp <- tryCatch(
            fepois(fp, data = subp, cluster = ~year, notes = FALSE),
            error = function(e) NULL)
          if (is.null(mp)) next
          ctp <- tryCatch(coeftable(mp), error = function(e) NULL)
          if (is.null(ctp)) next
          b0p <- g("dm_p", ctp)[1]; b1p <- g("dml_p", ctp)[1]
          if (is.na(b0p) || is.na(b1p)) next
          valid <- valid + 1L
          if (!is.na(r0[1]) && abs(b0p) >= abs(r0[1])) hits0 <- hits0 + 1L
          if (!is.na(r1[1]) && abs(b1p) >= abs(r1[1])) hits1 <- hits1 + 1L
        }
        if (valid >= 100) {
          pp0 <- (hits0 + 1) / (valid + 1)
          pp1 <- (hits1 + 1) / (valid + 1)
        }
        message(sprintf("  perm %s %s %s: p0 %.3g -> perm %.3g | p1 %.3g -> perm %.3g (%d draws)",
                        d, cc, out, r0[3], pp0, r1[3], pp1, valid))
      }

      res[[length(res) + 1]] <- data.table(
        type = d, iso3 = cc, outcome = out,
        b0 = r0[1], se0 = r0[2], p0 = r0[3],
        b1 = r1[1], se1 = r1[2], p1 = r1[3],
        perm_p0 = pp0, perm_p1 = pp1,
        n_ev = cnt[iso3 == cc, n_ev], n_sev = cnt[iso3 == cc, n_sev])
    }
  }
}

res <- rbindlist(res)
res[, name := countrycode::countrycode(iso3, "iso3c", "country.name",
                                       warn = FALSE)]
res[is.na(name), name := iso3]

dir.create("output/models", showWarnings = FALSE)
saveRDS(res, "output/models/country_effects.rds")
message("Done. ", nrow(res), " country-type-outcome estimates saved.")
