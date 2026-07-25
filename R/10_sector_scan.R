# By-sector scan for every disaster type (the M2 spec from R/05,
# generalized). Instead of imposing an exposure map, let each type's
# effect vary freely by sector group. Purpose: evidence for revising the
# storm map) — divergence from
# the theory map is a finding.
# Value AND tons per sector: the tons scan separates physical supply
# effects from price movements at the product level.

library(data.table)
library(arrow)
library(fixest)

panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))
panel <- panel[year >= 2001]

fe <- "iso3^year + chapter^year + iso3^chapter"
types <- c("flood", "drought", "earthquake", "storm")

models <- list()
for (d in types) {
  for (out in c("val", "qty")) {
    y <- if (out == "val") "export_value" else "export_qty"
    f <- as.formula(sprintf(
      "%s ~ i(sector_group, %s_dummy, ref = 'machinery_electrical') +
         i(sector_group, %s_dummy_lag1, ref = 'machinery_electrical') | %s",
      y, d, d, fe))
    models[[paste0(d, "_", out)]] <- fepois(f, data = panel, cluster = ~iso3)
    message("sector scan estimated: ", d, " ", out)
  }
}

dir.create("output/models", showWarnings = FALSE)
saveRDS(models, "output/models/sector_scan_models.rds")

etable(models, headers = as.list(names(models)),
       file = "output/tables/sector_scan_all_types.tex", replace = TRUE)
print(etable(models))
message("Done. Table: output/tables/sector_scan_all_types.tex")
