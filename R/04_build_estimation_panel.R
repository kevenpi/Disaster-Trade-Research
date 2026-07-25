# Assemble the estimation panel:
#   trade (01) + disasters (03) + exposure map (config/)
# Two structural steps that matter for PPML:
#   1. Complete the panel - a country-chapter-year with no trade is a
#      ZERO, not a missing row. PPML needs those zeros or the sample
#      selects on the outcome.
#   2. Lags built on the completed panel so year gaps can't misalign them.

library(data.table)
library(arrow)

trade     <- setDT(read_parquet("data/processed/trade_exporter_chapter_year.parquet"))
disasters <- setDT(read_parquet("data/processed/disasters_country_year.parquet"))
exposure  <- fread("config/exposure_map.csv", colClasses = list(character = "chapter"))

# --- 1. Complete panel: every exporter x chapter x year cell ---------------
# Only exporters that ever appear in BACI (real trading countries),
# only 2000-2024: EM-DAT coverage starts in 2000, so earlier years
# would carry fake-zero disaster dummies (2000 itself only feeds the
# 2001 lags; every estimation script filters to year >= 2001).
# ZA1 is the SACU aggregate, not a country: drop it. S19 ("Other Asia,
# nes") stays and carries Taiwan's trade and disasters (see R/03).
trade <- trade[year >= 2000 & iso3 != "ZA1"]
full <- CJ(iso3    = unique(trade$iso3),
           chapter = unique(trade$chapter),
           year    = unique(trade$year))
panel <- merge(full, trade[, -"exporter_code"],
               by = c("iso3", "chapter", "year"), all.x = TRUE)
# Rows absent from BACI are true zeros. Rows PRESENT in BACI with NA
# export_qty (positive value, every underlying quantity missing) must
# keep the NA: blanket nafill would turn them into fake zero-tons cells.
zero_cols <- c("export_value", "export_qty", "n_products", "n_destinations")
panel[is.na(export_value), (zero_cols) := 0]

# --- 2. Merge disasters (a country-year absent from EM-DAT had no event) ---
panel <- merge(panel, disasters, by = c("iso3", "year"), all.x = TRUE)
dis_cols <- setdiff(names(disasters), c("iso3", "year"))
panel[, (dis_cols) := lapply(.SD, nafill, fill = 0), .SDcols = dis_cols]

# --- 3. Exposure map --------------------------------------------------------
panel <- merge(panel, exposure, by = "chapter", all.x = TRUE)
stopifnot(!anyNA(panel$sector_group))

# --- 4. Lags (within exporter-chapter, panel is now gap-free by CJ) --------
setkey(panel, iso3, chapter, year)
for (d in c("flood", "drought", "earthquake", "storm",
            "wildfire", "extreme_temp")) {
  for (v in c("_dummy", "_severe_dummy")) {
    panel[, paste0(d, v, "_lag1") := shift(get(paste0(d, v)), 1),
          by = .(iso3, chapter)]
  }
}

write_parquet(panel, "data/processed/estimation_panel.parquet")
message("Wrote ", nrow(panel), " rows (",
        round(mean(panel$export_value == 0) * 100), "% zero-trade cells).")
