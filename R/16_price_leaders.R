# Which countries can move world prices of each product?
# Two parts:
#   1. Market shares: each country's share of world export value, pooled
#      2001-2024, by sector group (for the UI) -> output/models/price_leaders.rds
#   2. Price-impact models: for each disaster type, does a severe event in
#      exporting countries raise the WORLD unit value (dollars per ton) of
#      exposed product chapters, in proportion to those countries' market
#      share? OLS on log world unit value at chapter-year level with
#      chapter + year FE; regressor D = sum over countries of
#      (pooled share of chapter) x (severe event dummy), plus its lag.
#      -> output/models/price_models.rds

library(data.table)
library(arrow)
library(fixest)

panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))
panel <- panel[year >= 2001]

types <- c("flood", "drought", "earthquake", "storm")

# --- 1. market-share leaders by sector group -------------------------------
lead <- panel[, .(v = sum(export_value)), by = .(iso3, sector_group)]
lead[, share := v / sum(v), by = sector_group]

cy <- unique(panel[, c("iso3", "year",
                       paste0(types, "_severe_dummy")), with = FALSE])
sev_tot <- cy[, .(n_sev = sum(Reduce(`+`, .SD) > 0)),
              by = iso3,
              .SDcols = paste0(types, "_severe_dummy")]
lead <- merge(lead, sev_tot, by = "iso3", all.x = TRUE)
lead[is.na(n_sev), n_sev := 0]
setorder(lead, sector_group, -share)
lead <- lead[, head(.SD, 5), by = sector_group]
lead[, name := countrycode::countrycode(iso3, "iso3c", "country.name",
                                        warn = FALSE)]
lead[is.na(name), name := iso3]

dir.create("output/models", showWarnings = FALSE)
saveRDS(lead, "output/models/price_leaders.rds")
message("leaders saved: top 5 exporters x ", uniqueN(lead$sector_group),
        " sectors")

# --- 2. world unit-value models --------------------------------------------
uv <- panel[export_value > 0 & export_qty > 0,
            .(v = sum(export_value), q = sum(export_qty)),
            by = .(chapter, year)]
uv[, luv := log(v / q)]

sh_ch <- panel[, .(v = sum(export_value)), by = .(iso3, chapter)]
sh_ch[, share := v / sum(v), by = chapter]

price_models <- list()
for (d in types) {
  expo_ch <- unique(panel[get(paste0(d, "_exposed")) == 1, chapter])
  sev <- unique(panel[, .(iso3, year, s = get(paste0(d, "_severe_dummy")))])
  D <- merge(sh_ch[chapter %in% expo_ch, .(iso3, chapter, share)],
             sev, by = "iso3", allow.cartesian = TRUE)
  Dk <- D[, .(D = sum(share * s)), by = .(chapter, year)]
  dat <- merge(uv[chapter %in% expo_ch], Dk, by = c("chapter", "year"))
  setkey(dat, chapter, year)
  dat[, D_lag := shift(D), by = chapter]
  price_models[[d]] <- feols(luv ~ D + D_lag | chapter + year,
                             data = dat, cluster = ~chapter)
  message("price model estimated: ", d, " (", nrow(dat), " chapter-years)")
}
saveRDS(price_models, "output/models/price_models.rds")
print(etable(price_models, headers = as.list(types)))
message("Done.")
