# By-sector scan for every disaster type (the M2 spec from R/05,
# generalized). Instead of imposing an exposure map, let each type's
# effect vary freely by sector group; divergence from the theory map is
# a finding. Value AND tons per sector: the tons scan separates physical
# supply effects from price movements at the product level.
#
# Reference sector: chemicals (HS 28-38). It sits OUTSIDE every exposure
# map (agri/food 01-24; earthquake heavy manufacturing 72-92), which the
# scan requires - the earlier reference, machinery_electrical (84-85),
# was inside the earthquake map, so the scan could not test that map.
# All sector effects are relative to chemicals exports from the same
# country-year.
#
# What the scan can and cannot show (July 2026 audit): sector estimates
# are RELATIVE to the reference, so a sector can show a positive
# coefficient because the reference itself fell (droughts: most sectors
# positive relative to the reference). Interpret patterns across
# sectors, not single stars; the website applies a Benjamini-Hochberg
# correction within each scan before starring cells.

library(data.table)
library(arrow)
library(fixest)

panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))
panel <- panel[year >= 2001]

fe <- "iso3^year + chapter^year + iso3^chapter"
types <- c("flood", "drought", "earthquake", "storm")
ref_sector <- "chemicals"

models <- list()
for (d in types) {
  for (out in c("val", "qty")) {
    y <- if (out == "val") "export_value" else "export_qty"
    f <- as.formula(sprintf(
      "%s ~ i(sector_group, %s_dummy, ref = '%s') +
         i(sector_group, %s_dummy_lag1, ref = '%s') | %s",
      y, d, ref_sector, d, ref_sector, fe))
    models[[paste0(d, "_", out)]] <- fepois(f, data = panel, cluster = ~iso3)
    message("sector scan estimated: ", d, " ", out)
  }
}

dir.create("output/models", showWarnings = FALSE)
saveRDS(models, "output/models/sector_scan_models.rds")

sig <- c("***" = 0.001, "**" = 0.01, "*" = 0.05, "+" = 0.1)
etable(models, headers = names(models), signif.code = sig,
       file = "output/tables/sector_scan_all_types.tex", replace = TRUE)
print(etable(models))
message("Done. Table: output/tables/sector_scan_all_types.tex")
