# Main PPML estimation.
#
# Identification note (the exporter-year FE question):
#   exporter-year FE absorbs EVERYTHING that hits a country in a year,
#   including the disaster's overall effect on its exports. So beta on
#   Disaster x Exposure is a RELATIVE effect: how much more exposed
#   products fall than non-exposed products in the same country-year.
#   Spec (M3) drops exporter-year FE to recover the overall effect -
#   less well identified (country-year shocks confound), report both.

library(data.table)
library(arrow)
library(fixest)

panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))

# EM-DAT export covers 2000+ only. Pre-2000 disaster values are filled-in
# zeros that would be FALSE zeros; and the 2000 lag looks into 1999.
# Restrict to years where both current and lagged disasters are observed.
panel <- panel[year >= 2001]

# Start with floods (most frequent, cleanest agriculture link)
panel[, flood        := flood_dummy]
panel[, flood_l1     := flood_dummy_lag1]
panel[, flood_sev    := flood_severe_dummy]
panel[, flood_sev_l1 := flood_severe_dummy_lag1]
panel[, exposed      := flood_exposed]

# --- M1: headline - theory-driven exposure, full FE ------------------------
m1 <- fepois(
  export_value ~ flood:exposed + flood_l1:exposed |
    iso3^year + chapter^year + iso3^chapter,
  data = panel, cluster = ~iso3
)

# --- M2: data-driven heterogeneity - effect by sector group ----------------
# Lets the data reveal which sectors floods actually hit; compare with
# the theory map, discuss divergences.
m2 <- fepois(
  export_value ~ i(sector_group, flood, ref = "machinery_electrical") +
    i(sector_group, flood_l1, ref = "machinery_electrical") |
    iso3^year + chapter^year + iso3^chapter,
  data = panel, cluster = ~iso3
)

# --- M3: overall effect (no exporter-year FE) -------------------------------
# Tests hypothesis 1 (disasters reduce total exports). Weaker
# identification; year FE + exporter-chapter FE only.
m3 <- fepois(
  export_value ~ flood + flood_l1 + flood:exposed + flood_l1:exposed |
    chapter^year + iso3^chapter,
  data = panel, cluster = ~iso3
)

# --- M1s / M1d: severity-thresholded treatment ------------------------------
# The any-flood dummy averages catastrophes with minor events -> attenuation.
# M1s: severe floods only (top-quartile by deaths or affected).
# M1d: both dummies together - the severe coefficient is then the EXTRA
#      effect of a severe flood on top of any-flood.
m1s <- fepois(
  export_value ~ flood_sev:exposed + flood_sev_l1:exposed |
    iso3^year + chapter^year + iso3^chapter,
  data = panel, cluster = ~iso3
)
m1d <- fepois(
  export_value ~ flood:exposed + flood_l1:exposed +
    flood_sev:exposed + flood_sev_l1:exposed |
    iso3^year + chapter^year + iso3^chapter,
  data = panel, cluster = ~iso3
)

etable(m1, m2, m3,
       headers = c("Relative (theory map)", "By sector (data-driven)", "Overall + relative"),
       file = "output/tables/main_flood_ppml.tex", replace = TRUE)
etable(m1, m1s, m1d,
       headers = c("Any flood", "Severe flood", "Both (dose)"),
       file = "output/tables/severity_flood_ppml.tex", replace = TRUE)
print(etable(m1, m1s, m1d, m3))
message("--- M2: flood effect by sector group (vs machinery_electrical) ---")
print(etable(m2))

# --- Event study around flood years (dynamics / pre-trends) -----------------
setkey(panel, iso3, chapter, year)
panel[, flood_lead1 := shift(flood, -1), by = .(iso3, chapter)]
panel[, flood_lag2  := shift(flood,  2), by = .(iso3, chapter)]
panel[, flood_sev_lead1 := shift(flood_sev, -1), by = .(iso3, chapter)]
panel[, flood_sev_lag2  := shift(flood_sev,  2), by = .(iso3, chapter)]
m_es <- fepois(
  export_value ~ flood_lead1:exposed + flood:exposed +
    flood_l1:exposed + flood_lag2:exposed |
    iso3^year + chapter^year + iso3^chapter,
  data = panel, cluster = ~iso3
)
m_es_sev <- fepois(
  export_value ~ flood_sev_lead1:exposed + flood_sev:exposed +
    flood_sev_l1:exposed + flood_sev_lag2:exposed |
    iso3^year + chapter^year + iso3^chapter,
  data = panel, cluster = ~iso3
)
etable(m_es, m_es_sev,
       headers = c("Any flood", "Severe flood"),
       file = "output/tables/event_study_flood.tex", replace = TRUE)
print(etable(m_es, m_es_sev))

message("Done. Tables in output/tables/.")
