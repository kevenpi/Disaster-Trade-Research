# Natural Disasters and the Composition of Exports

Phase 1 of a research project on external shocks and trade; the longer
run goal is to study armed conflict with UCDP data. This phase asks how
four disaster types (floods, droughts, earthquakes, storms) change the
composition of exports, using PPML on a completed exporter x HS-chapter
x year panel covering 2001-2024. 

## Data (not included)

1. BACI (CEPII): download the HS92 release (files named BACI_HS92_Y*)
   from www.cepii.fr/CEPII/en/bdd_modele/bdd_modele_item.asp?id=37
   into data/raw/baci/.
2. EM-DAT: register at public.emdat.be, export Natural disasters,
   all countries, as .xlsx into data/raw/emdat/ (our extract spans
   2000-2026; R/03 filters to events starting 2000-2024 before
   computing severity cutoffs).
3. CEPII Gravity V202211 (Gravity_V202211.rds) into data/raw/gravity/
   (used only by R/02; kept for phase 2).
4. World Bank GFDD.DI.10 (insurance company assets to GDP) csv into
   data/raw/worldbank/ for the R/07 heterogeneity split.

## Pipeline 
| Script | Purpose |
|---|---|
| R/00_install_packages.R | dependencies |
| R/01_build_baci_panel.R | BACI -> exporter x chapter x year flows |
| R/02_prepare_gravity.R | gravity covariates (early phase) |
| R/03_clean_emdat.R | EM-DAT -> country x year x type; severe = top quartile within type by deaths or affected |
| R/04_build_estimation_panel.R | merge; complete panel with true zeros; lags |
| R/05-07 | flood-only models, severity robustness, insurance heterogeneity |
| R/08_all_disasters.R | main matrix: 4 types x value/tons, dose spec |
| R/09_event_studies.R | leads/lags: anticipation test |
| R/10_sector_scan.R | effects free by sector (exposure-map audit) |
| R/11_joint_dose.R | all four types jointly (co-occurrence robustness) |
| R/12_results_report.R | auto-generated technical report |
| R/13_export_explorer_data.R | JSON for the interactive appendix |
| R/14_explorer_figures.R | APA figures (PNG) from saved models |
| R/15_country_effects.R | per-country models (heterogeneity) |
| R/16_price_leaders.R | world unit-value models; market-share leaders |

Specification (pooled models): fepois(y ~ dose terms x exposure |
iso3^year + chapter^year + iso3^chapter), with standard errors
clustered by exporter. Per-country models (R/15) use chapter + year FE
with year-clustered SEs plus a permutation test; world price models
(R/16) are OLS on log unit values. The exposure maps live in
config/exposure_map.csv and were fixed before estimation. Every fitted
model is saved to output/models/ as .rds, and the tables, figures, and
web pages produced by R/12-14 regenerate from those objects, so the
numbers in those outputs are computed, not typed (prose framing around
them is still written by hand).

## Outputs

- output/explorer.html - interactive results appendix (serve output/
  with any static server, e.g. python3 -m http.server 8787)
- output/results_auto.html - technical report
- output/tables/*.tex - LaTeX tables
