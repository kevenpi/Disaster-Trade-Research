# Event studies for every disaster type in the matrix (R/08).
# Same spec as the flood event study in R/05: lead 1, year of, lags 1-2,
# interacted with the type's own exposure map; any-event and severe-event
# versions, for BOTH outcomes (export value and tons - the headline is a
# tons number, so it needs a pre-trend check on its own outcome).
#
# Reading the lead honestly (July 2026 audit): for frequent, serially
# correlated types (floods, storms) the "lead" year often falls shortly
# AFTER another event of the same type - 51% of flood-treated
# country-years have lead1 = lag1 = 1 - so the lead is NOT a clean
# anticipation test there. Read these as distributed-lag profiles; a
# near-zero lead still bounds pre-trends, but a nonzero lead (severe
# storms) is only suggestive: anticipation, serial-storm echo, and
# EM-DAT misdating are observationally equivalent.

library(data.table)
library(arrow)
library(fixest)

panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))
panel <- panel[year >= 2001]

fe <- "iso3^year + chapter^year + iso3^chapter"
types <- c("flood", "drought", "earthquake", "storm")

setkey(panel, iso3, chapter, year)
for (d in types) {
  for (v in c("_dummy", "_severe_dummy")) {
    panel[, paste0(d, v, "_lead1") := shift(get(paste0(d, v)), -1),
          by = .(iso3, chapter)]
    panel[, paste0(d, v, "_lag2")  := shift(get(paste0(d, v)),  2),
          by = .(iso3, chapter)]
  }
}

run_es <- function(d, sev = FALSE, outcome = "export_value") {
  v <- if (sev) paste0(d, "_severe_dummy") else paste0(d, "_dummy")
  f <- as.formula(sprintf(
    "%s ~ %s_lead1:%s_exposed + %s:%s_exposed +
       %s_lag1:%s_exposed + %s_lag2:%s_exposed | %s",
    outcome, v, d, v, d, v, d, v, d, fe))
  fepois(f, data = panel, cluster = ~iso3)
}

# Value models keep their legacy names (flood_any, flood_sev, ...) so
# downstream consumers (R/13, R/14) stay compatible; tons models get a
# _qty suffix.
models <- list()
for (d in types) {
  models[[paste0(d, "_any")]]     <- run_es(d, sev = FALSE)
  models[[paste0(d, "_sev")]]     <- run_es(d, sev = TRUE)
  models[[paste0(d, "_any_qty")]] <- run_es(d, sev = FALSE, outcome = "export_qty")
  models[[paste0(d, "_sev_qty")]] <- run_es(d, sev = TRUE,  outcome = "export_qty")
  message("event studies estimated: ", d)
}

dir.create("output/models", showWarnings = FALSE)
saveRDS(models, "output/models/event_study_models.rds")

sig <- c("***" = 0.001, "**" = 0.01, "*" = 0.05, "+" = 0.1)
hdr <- as.vector(outer(c("any ", "severe "), types, function(a, b) paste0(a, b)))

ord_val <- as.vector(rbind(paste0(types, "_any"), paste0(types, "_sev")))
etable(models[ord_val],
       headers = hdr, signif.code = sig,
       file = "output/tables/event_studies_all_types.tex", replace = TRUE)

ord_qty <- paste0(ord_val, "_qty")
etable(models[ord_qty],
       headers = hdr, signif.code = sig,
       file = "output/tables/event_studies_all_types_qty.tex", replace = TRUE)

print(etable(models[ord_val]))
print(etable(models[ord_qty]))

message("Done. Tables: output/tables/event_studies_all_types{,_qty}.tex")
