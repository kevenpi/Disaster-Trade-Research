# Country-level heterogeneity: which countries are hit hardest by each
# disaster type? One PPML per country x type x outcome, using the same
# within-country identification as the pooled model (exposed vs unexposed
# chapters, chapter + year FE). Only countries with enough events AND
# enough disaster-free years to form a contrast are estimated.
# Saves a compact results table: output/models/country_effects.rds

library(data.table)
library(arrow)
library(fixest)

panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))
panel <- panel[year >= 2001]

types <- c("flood", "drought", "earthquake", "storm")

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
        fepois(f, data = sub, cluster = ~chapter, notes = FALSE),
        error = function(e) NULL)
      if (is.null(m)) next
      ct <- tryCatch(coeftable(m), error = function(e) NULL)
      if (is.null(ct)) next
      g <- function(tok) {
        hit <- vapply(rownames(ct),
                      function(r) tok %in% strsplit(r, ":", fixed = TRUE)[[1]],
                      logical(1))
        if (sum(hit) != 1) return(c(NA_real_, NA_real_, NA_real_))
        c(ct[hit, 1], ct[hit, 2], ct[hit, 4])
      }
      r0 <- g(dm); r1 <- g(dml)
      res[[length(res) + 1]] <- data.table(
        type = d, iso3 = cc, outcome = out,
        b0 = r0[1], se0 = r0[2], p0 = r0[3],
        b1 = r1[1], se1 = r1[2], p1 = r1[3],
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
