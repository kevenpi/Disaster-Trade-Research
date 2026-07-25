# Clean EM-DAT into a country x year x disaster-type panel.
#
# Input: the public EM-DAT export (register at public.emdat.be, Access
# Data tab -> Natural disasters, all countries -> .xlsx into
# data/raw/emdat/). The current extract spans 2000-2026; this script
# filters to 2000-2024 (2000 is kept only to feed 2001's lag) BEFORE
# computing severity cutoffs, so partial recent years cannot shift the
# quantiles.
#
# Events are assigned to their START year. 164/424 droughts span more
# than one year, so continuing-drought years sit in the control group;
# a start-year assignment is conservative for slow-onset types. (Ledger
# item: an all-years robustness assignment is a possible extension.)
#
# Column names below match the current public EM-DAT export format;
# the stopifnot() will catch it immediately if their format changed.

library(data.table)
library(readxl)
library(janitor)
library(arrow)

emdat_file <- list.files("data/raw/emdat", pattern = "\\.xlsx$", full.names = TRUE)
stopifnot("Put the EM-DAT .xlsx export in data/raw/emdat/ first" = length(emdat_file) == 1)

ed <- setDT(clean_names(read_excel(emdat_file)))

needed <- c("iso", "start_year", "end_year", "disaster_group", "disaster_type",
            "total_deaths", "total_affected",
            "total_damage_adjusted_000_us")
missing_cols <- setdiff(needed, names(ed))
stopifnot("EM-DAT column names changed - inspect and update this script" =
            length(missing_cols) == 0)

ed <- ed[disaster_group == "Natural"]

# Sanity: drop corrupt rows (e.g. 1988-0424-VEN has start_year=2026,
# end_year=1988), then restrict to the analysis window BEFORE severity
# quantiles are computed. 2025-26 are partial years; 2000 stays only so
# 2001 gets a lag.
ed <- ed[is.na(end_year) | end_year >= start_year]
ed <- ed[start_year >= 2000 & start_year <= 2024]

# Taiwan: EM-DAT codes it TWN, but BACI reports its trade under the
# pseudo-ISO S19 ("Other Asia, nes"). Without this recode all Taiwanese
# disasters silently drop in the merge and the #11 exporter shows zero
# events. Not recoded (documented limitation): PRI/VIR trade folds under
# USA, REU/GLP/MTQ/GUF/MAF under FRA, Canary Is. under ESP, so ~11
# EM-DAT territory codes never merge to trade.
ed[iso == "TWN", iso := "S19"]

# The four types we study, matching the exposure-map columns
type_map <- c("Flood" = "flood", "Drought" = "drought",
              "Earthquake" = "earthquake", "Storm" = "storm",
              "Wildfire" = "wildfire", "Extreme temperature" = "extreme_temp")
ed <- ed[disaster_type %in% names(type_map)]
ed[, dtype := type_map[disaster_type]]

# Severity flags. The any-event dummy mixes catastrophes with minor events
# (EM-DAT's entry bar is only 10 deaths / 100 affected), which attenuates
# the estimates. "Severe" = top quartile of events within disaster type,
# by deaths or by people affected. Dollar damages deliberately not used:
# 74% missing, non-randomly (insured rich countries report them).
ed[, sev_deaths_cut   := quantile(total_deaths,   0.75, na.rm = TRUE), by = dtype]
ed[, sev_affected_cut := quantile(total_affected, 0.75, na.rm = TRUE), by = dtype]
ed[, severe := as.integer(
      (!is.na(total_deaths)   & total_deaths   >= sev_deaths_cut) |
      (!is.na(total_affected) & total_affected >= sev_affected_cut))]
print(unique(ed[, .(dtype, sev_deaths_cut, sev_affected_cut)])[order(dtype)])
message("Share of events flagged severe, by type:")
print(ed[, .(share_severe = round(mean(severe), 2)), by = dtype][order(dtype)])

# Collapse to country x year x type
ctyt <- ed[, .(
  n_events       = .N,
  n_severe       = sum(severe),
  deaths         = sum(total_deaths, na.rm = TRUE),
  affected       = sum(total_affected, na.rm = TRUE),
  damage_adj_kusd = sum(total_damage_adjusted_000_us, na.rm = TRUE),
  damage_missing = mean(is.na(total_damage_adjusted_000_us))  # track EM-DAT's damage-underreporting problem
), by = .(iso3 = iso, year = start_year, dtype)]

# Wide: one row per country-year, columns like flood_n, flood_deaths, ...
disasters <- dcast(ctyt, iso3 + year ~ dtype,
                   value.var = c("n_events", "n_severe", "deaths", "affected",
                                 "damage_adj_kusd", "damage_missing"),
                   fill = 0)
# dcast names them n_events_flood etc.; flip to flood_n_events style
setnames(disasters, names(disasters),
         sub("^(n_events|n_severe|deaths|affected|damage_adj_kusd|damage_missing)_(\\w+)$",
             "\\2_\\1", names(disasters)))

for (d in unname(type_map)) {
  disasters[, paste0(d, "_dummy")        := as.integer(get(paste0(d, "_n_events")) > 0)]
  disasters[, paste0(d, "_severe_dummy") := as.integer(get(paste0(d, "_n_severe")) > 0)]
}

write_parquet(disasters, "data/processed/disasters_country_year.parquet")
message("Wrote ", nrow(disasters), " country-years, ",
        min(disasters$year), "-", max(disasters$year), ".")
message("Share of flood events with missing damage data: ",
        round(mean(ctyt[dtype == "flood", damage_missing]), 2))
