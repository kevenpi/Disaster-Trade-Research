# Event studies for every disaster type in the matrix (R/08).
# Same spec as the flood event study in R/05: lead 1 (pre-trend /
# anticipation check), year of, lags 1-2, interacted with the type's own
# exposure map; any-event and severe-event versions, export value.
# The lead is the point: disasters should show nothing before the shock.

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

run_es <- function(d, sev = FALSE) {
  v <- if (sev) paste0(d, "_severe_dummy") else paste0(d, "_dummy")
  f <- as.formula(sprintf(
    "export_value ~ %s_lead1:%s_exposed + %s:%s_exposed +
       %s_lag1:%s_exposed + %s_lag2:%s_exposed | %s",
    v, d, v, d, v, d, v, d, fe))
  fepois(f, data = panel, cluster = ~iso3)
}

models <- list()
for (d in types) {
  models[[paste0(d, "_any")]] <- run_es(d, sev = FALSE)
  models[[paste0(d, "_sev")]] <- run_es(d, sev = TRUE)
  message("event study estimated: ", d)
}

dir.create("output/models", showWarnings = FALSE)
saveRDS(models, "output/models/event_study_models.rds")

hdr <- as.vector(outer(c("any ", "severe "), types, function(a, b) paste0(a, b)))
ord <- as.vector(rbind(paste0(types, "_any"), paste0(types, "_sev")))

etable(models[ord],
       headers = as.list(hdr),
       file = "output/tables/event_studies_all_types.tex", replace = TRUE)
print(etable(models[ord]))

message("Done. Table: output/tables/event_studies_all_types.tex")
