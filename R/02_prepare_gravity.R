# Slim the CEPII Gravity dataset (V202211; the slimmed parquet spans
# 1995-2021) down to the variables we may use, saved as parquet.
# Main spec doesn't need gravity (the FEs absorb it) and NO current
# script consumes gravity.parquet - kept for possible descriptive work
# and the phase-2 bilateral design.

library(data.table)
library(arrow)

grav <- readRDS("data/raw/gravity/Gravity_V202211.rds")
setDT(grav)

wanted <- c("year", "iso3_o", "iso3_d",
            "dist", "distw_harmonic", "contig", "comlang_off", "comcol",
            "gdp_o", "gdp_d", "gdpcap_o", "gdpcap_d", "pop_o", "pop_d",
            "rta", "rta_type", "wto_o", "wto_d")

available <- intersect(wanted, names(grav))
if (length(setdiff(wanted, available))) {
  message("Not in this Gravity version (skipped): ",
          paste(setdiff(wanted, available), collapse = ", "))
}

grav <- grav[year >= 1995, ..available]
write_parquet(grav, "data/processed/gravity.parquet")
message("Wrote ", nrow(grav), " rows, years ",
        min(grav$year), "-", max(grav$year), ".")
