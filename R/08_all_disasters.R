# The heterogeneity matrix: all four disaster types x exposed products.
# Same dose template as the flood analysis (R/05-06): ordinary + severe
# dummies interacted with the type's own exposure map, value AND tons.
#
# Exposure maps (config/exposure_map.csv):
#   flood / drought / storm -> chapters 01-24 (agri + food chain)
#
# Scope: the analysis covers these four types. Wildfire and extreme
# temperature exist in the data (03/04 build their columns) but are
# excluded here because their exposure maps were never settled.
#   earthquake              -> chapters 72-92 (heavy manufacturing)
#
# Known limitation, note in the paper: disaster types co-occur (storms
# cause floods; EM-DAT codes the proximate type), so type-specific
# estimates are not fully independent. A joint all-types spec is a
# robustness check for later.

library(data.table)
library(arrow)
library(fixest)

panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))
panel <- panel[year >= 2001]

fe <- "iso3^year + chapter^year + iso3^chapter"
types <- c("flood", "drought", "earthquake", "storm")

# Treated country-year counts (context for precision differences)
cy <- unique(panel[, c("iso3", "year", paste0(types, "_dummy"),
                       paste0(types, "_severe_dummy")), with = FALSE])
for (d in types) {
  message(sprintf("%-11s country-years: any %4d | severe %4d", d,
                  cy[, sum(get(paste0(d, "_dummy")))],
                  cy[, sum(get(paste0(d, "_severe_dummy")))]))
}

run_type <- function(d, outcome) {
  f <- as.formula(sprintf(
    "%s ~ %s_dummy:%s_exposed + %s_dummy_lag1:%s_exposed +
          %s_severe_dummy:%s_exposed + %s_severe_dummy_lag1:%s_exposed | %s",
    outcome, d, d, d, d, d, d, d, d, fe))
  fepois(f, data = panel, cluster = ~iso3)
}

models <- list()
for (d in types) {
  models[[paste0(d, "_val")]] <- run_type(d, "export_value")
  models[[paste0(d, "_qty")]] <- run_type(d, "export_qty")
  message("estimated: ", d)
}

dir.create("output/models", showWarnings = FALSE)
saveRDS(models, "output/models/matrix_models.rds")

hdr <- as.vector(outer(c("$ ", "tons "), types, function(a, b) paste0(b, " ", a)))
ord <- as.vector(rbind(paste0(types, "_val"), paste0(types, "_qty")))

etable(models[ord],
       headers = as.list(hdr),
       file = "output/tables/all_disasters_ppml.tex", replace = TRUE)
print(etable(models[ord]))

message("Done. Table: output/tables/all_disasters_ppml.tex")
