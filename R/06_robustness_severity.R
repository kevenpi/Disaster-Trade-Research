# Robustness checks for the severity split (the July finding:
# ordinary floods hit exposed/agriculture, severe floods hit the rest).
#
#   A. Price vs volume: rerun the dose spec with export QUANTITY (tons)
#      as the outcome. If severe-flood agriculture only looks flat in
#      VALUE because scarcity raises prices, the quantity regression
#      should show a drop that the value regression hides.
#   B. Threshold sensitivity: redefine "severe" at the median, top
#      quartile (baseline), and top decile of flood events, by deaths
#      or people affected. The story shouldn't hinge on one cutoff.

library(data.table)
library(readxl)
library(janitor)
library(arrow)
library(fixest)

panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))

# --- B: event-level severity flags at three cutoffs ------------------------
emdat_file <- list.files("data/raw/emdat", pattern = "\\.xlsx$", full.names = TRUE)
ed <- setDT(clean_names(read_excel(emdat_file)))
ed <- ed[disaster_group == "Natural" & disaster_type == "Flood"]
# Same filters as R/03, or the sev75 consistency check below fails:
ed <- ed[is.na(end_year) | end_year >= start_year]
ed <- ed[start_year >= 2000 & start_year <= 2024]
ed[iso == "TWN", iso := "S19"]

# Honest labels for these cutoffs: severity = deaths OR affected above
# the quantile, so "sev50" flags well over half of floods (either
# margin can trigger), sev75 roughly a third, sev90 the worst ~13%.
for (p in c(50, 75, 90)) {
  dcut <- quantile(ed$total_deaths,   p / 100, na.rm = TRUE)
  acut <- quantile(ed$total_affected, p / 100, na.rm = TRUE)
  ed[, paste0("sev", p) := as.integer(
        (!is.na(total_deaths)   & total_deaths   >= dcut) |
        (!is.na(total_affected) & total_affected >= acut))]
  message(sprintf("sev%d: deaths >= %.0f or affected >= %.0f", p, dcut, acut))
}

cy <- ed[, lapply(.SD, function(x) as.integer(sum(x) > 0)),
         .SDcols = paste0("sev", c(50, 75, 90)),
         by = .(iso3 = iso, year = start_year)]

sevcols <- paste0("sev", c(50, 75, 90))
panel <- merge(panel, cy, by = c("iso3", "year"), all.x = TRUE)
panel[, (sevcols) := lapply(.SD, nafill, fill = 0L), .SDcols = sevcols]

# Lags BEFORE the sample restriction, so 2001's lag sees observed 2000
setkey(panel, iso3, chapter, year)
for (s in sevcols) {
  panel[, paste0(s, "_l1") := shift(get(s), 1), by = .(iso3, chapter)]
}
panel <- panel[year >= 2001]

panel[, flood    := flood_dummy]
panel[, flood_l1 := flood_dummy_lag1]
panel[, exposed  := flood_exposed]

# Consistency check: sev75 must reproduce the pipeline's severe dummy
stopifnot(panel[, all(sev75 == flood_severe_dummy)])
message("Severe country-years by cutoff (2001-2024): ",
        paste(sevcols, unique(panel[, .(iso3, year, sev50, sev75, sev90)])[
          , sapply(.SD, sum), .SDcols = sevcols], sep = "=", collapse = ", "))

fe   <- "iso3^year + chapter^year + iso3^chapter"
dose <- function(outcome, s) as.formula(sprintf(
  "%s ~ flood:exposed + flood_l1:exposed + %s:exposed + %s_l1:exposed | %s",
  outcome, s, s, fe))

# --- B: value regressions across thresholds --------------------------------
m_thr <- lapply(sevcols, function(s)
  fepois(dose("export_value", s), data = panel, cluster = ~iso3))
names(m_thr) <- sevcols

# --- A: quantity (tons) at the baseline cutoff ------------------------------
m_qty <- fepois(dose("export_qty", "sev75"), data = panel, cluster = ~iso3)

sig <- c("***" = 0.001, "**" = 0.01, "*" = 0.05, "+" = 0.1)
etable(m_thr$sev50, m_thr$sev75, m_thr$sev90, m_qty,
       headers = c("Value, sev=p50", "Value, sev=p75", "Value, sev=p90",
                   "Tons, sev=p75"),
       signif.code = sig,
       file = "output/tables/robustness_severity.tex", replace = TRUE)
saveRDS(c(m_thr, list(qty_sev75 = m_qty)),
        "output/models/severity_models.rds")
print(etable(m_thr$sev50, m_thr$sev75, m_thr$sev90, m_qty,
             headers = c("Val p50", "Val p75", "Val p90", "Tons p75")))

message("Done. Table: output/tables/robustness_severity.tex")
