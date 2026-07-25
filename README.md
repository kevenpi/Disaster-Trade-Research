# Natural Disasters and the Composition of Exports

Phase 1 of a research project on external shocks and trade (with the
longer-run goal of studying armed conflict via UCDP). Estimates how four
natural disaster types (floods, droughts, earthquakes, storms) affect
the composition of exports, using PPML on a completed exporter x
HS-chapter x year panel, 2001-2024. Wildfires and extreme temperature
events are present in the cleaned data but excluded from the analysis:
no defensible ex-ante exposure map was settled for them.

Author: Keven Pi. The pipeline was audited end to end (July 2026):
lag construction verified by independent recomputation, exposure maps
checked against spec, and all reported numbers confirmed to match the
saved model objects.

## Data (not included; ~11 GB)

1. BACI (CEPII): download the HS02 release from
   www.cepii.fr/CEPII/en/bdd_modele/bdd_modele_item.asp?id=37
   into data/raw/baci/.
2. EM-DAT: register at public.emdat.be, export Natural disasters
   1994-2024 (all countries) as .xlsx into data/raw/emdat/.

## Pipeline (run in order)

| Script | Purpose |
|---|---|
| R/00_install_packages.R | dependencies |
| R/01_build_baci_panel.R | BACI -> exporter x chapter x year flows |
| R/02_prepare_gravity.R | gravity covariates (early phase) |
| R/03_clean_emdat.R | EM-DAT -> country x year x type; severe = top quartile within type by deaths or affected |
| R/04_build_estimation_panel.R | merge; complete panel with true zeros; lags |
| R/05-07 | flood-only models, severity robustness, insurance heterogeneity |
| R/08_all_disasters.R | main matrix: 6 types x value/tons, dose spec |
| R/09_event_studies.R | leads/lags: anticipation test |
| R/10_sector_scan.R | effects free by sector (exposure-map audit) |
| R/11_joint_dose.R | all six types jointly (co-occurrence robustness) |
| R/12_results_report.R | auto-generated technical report |
| R/13_export_explorer_data.R | JSON for the interactive appendix |
| R/14_explorer_figures.R | APA figures (PNG) from saved models |
| R/15_country_effects.R | per-country models (heterogeneity) |
| R/16_price_leaders.R | world unit-value models; market-share leaders |

Specification: fepois(y ~ dose terms x exposure | iso3^year +
chapter^year + iso3^chapter), SEs clustered by exporter. Exposure maps
in config/exposure_map.csv (fixed ex ante; see PLAN.md for the two maps
still awaiting review). All fitted models are saved to output/models/
as .rds; every table, figure, and web page regenerates from those
objects, so no reported number is hand-transcribed.

## Outputs

- output/explorer.html - interactive results appendix (serve output/
  with any static server, e.g. python3 -m http.server 8787)
- output/results_auto.html - technical report
- output/tables/*.tex - LaTeX tables
- PLAN.md - running research log: findings, decisions, open items
