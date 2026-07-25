# Joint specification: all four disaster types in ONE regression.
# Robustness for co-occurrence — storms cause floods and EM-DAT codes the
# proximate type, so the one-type-at-a-time matrix (R/08) partly double
# counts shared years. Here each type's dose terms compete for the same
# variation; coefficients are conditional on the other three types.

library(data.table)
library(arrow)
library(fixest)

panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))
panel <- panel[year >= 2001]

fe <- "iso3^year + chapter^year + iso3^chapter"
types <- c("flood", "drought", "earthquake", "storm")

rhs <- paste(unlist(lapply(types, function(d) sprintf(
  c("%s_dummy:%s_exposed", "%s_dummy_lag1:%s_exposed",
    "%s_severe_dummy:%s_exposed", "%s_severe_dummy_lag1:%s_exposed"),
  d, d))), collapse = " + ")

models <- list(
  joint_val = fepois(as.formula(paste("export_value ~", rhs, "|", fe)),
                     data = panel, cluster = ~iso3),
  joint_qty = fepois(as.formula(paste("export_qty ~", rhs, "|", fe)),
                     data = panel, cluster = ~iso3)
)
message("joint models estimated")

dir.create("output/models", showWarnings = FALSE)
saveRDS(models, "output/models/joint_models.rds")

sig <- c("***" = 0.001, "**" = 0.01, "*" = 0.05, "+" = 0.1)
etable(models, headers = c("$ value", "tons"), signif.code = sig,
       file = "output/tables/joint_all_types.tex", replace = TRUE)
print(etable(models))
message("Done. Table: output/tables/joint_all_types.tex")
