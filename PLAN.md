# Disaster–Trade Project: Infrastructure & Plan

Research question: how do environmental disasters, as supply shocks, affect
trade flows across product categories — a disaster-type × product-category
heterogeneity matrix. Supervised by Prof. Kleinman [spelling TBC].

## Repository layout

```
disaster-trade/
├── PLAN.md                  ← this file
├── config/
│   └── exposure_map.csv     ← theory-driven chapter → sector / exposure map (EDIT ME)
├── R/
│   ├── 00_install_packages.R
│   ├── 01_build_baci_panel.R      BACI 11 GB → exporter×chapter×year panel
│   ├── 02_prepare_gravity.R       slim Gravity to parquet
│   ├── 03_clean_emdat.R           EM-DAT xlsx → country×year×type panel   [blocked: registration]
│   ├── 04_build_estimation_panel.R  merge + zero-fill + lags
│   ├── 05_estimation.R            PPML: headline, data-driven, event study (floods)
│   ├── 06_robustness_severity.R   severity cutoffs p50/p75/p90 (floods)
│   ├── 07_insurance_heterogeneity.R  WB insurance-depth split (floods)
│   ├── 08_all_disasters.R         the 6-type x value/tons dose matrix
│   └── 09_event_studies.R         event studies (lead + 2 lags), all 6 types
├── data/
│   ├── raw/        baci/ ✅  gravity/ ✅  emdat/ ⏳
│   └── processed/  parquet outputs of each stage
└── output/         tables/ figures/
```

Scripts run in order, each reads the previous stage's parquet. Any stage can
be re-run alone — nothing recomputes the 11 GB read unless script 01 changes.

## Pipeline design decisions (made — ask me to explain any)

| Decision | Choice | Why |
|---|---|---|
| Unit of analysis | exporter × HS2 chapter × year | 230 × 97 × 30 ≈ 670k rows — rich but laptop-friendly; HS-4 kept for robustness later |
| Trade data format | year-by-year `fread`, aggregate, discard | peak RAM ~1 GB instead of 11 |
| HS codes | read as **character** | chapters 01–09 have leading zeros; integer parsing corrupts them |
| Zeros | panel completed via cross-join, missing = 0 | PPML must see zero-trade cells or the sample selects on the outcome |
| Storage | parquet (arrow) | fast, compact, language-agnostic |
| Disaster measure | event dummies first; damage/GDP later | EM-DAT damage data is missing non-randomly — dummies are the honest baseline |
| Main estimator | `fepois`, cluster by exporter | zeros + heteroskedasticity; disasters vary at exporter level |

## The three specifications (R/05)

- **M1 (headline):** `flood × exposed` with exporter-year + chapter-year +
  exporter-chapter FE. β = *relative* fall of exposed vs non-exposed products
  within a flooded country-year. Tests hypotheses 2–3.
- **M2 (data-driven):** flood effect estimated separately per sector group;
  compare against the theory map in `config/exposure_map.csv` — divergence is
  a *finding*, not a failure.
- **M3 (overall):** drops exporter-year FE to recover the total export effect
  (hypothesis 1). Weaker identification — report with caveats.
- **Event study:** lead + two lags of the flood dummy → pre-trends check and
  dynamics (tests the year-of vs year-after timing, hypothesis 4 rebound).

## Decisions I need from Kev

1. **Exposure map defaults** (`config/exposure_map.csv`): I set floods/
   droughts/storms → chapters 01–24 (agriculture + food chain), earthquakes →
   72–92 (metals through instruments). Defensible but crude — review with
   your advisor, edit the CSV, pipeline picks it up automatically.
2. **Sample window:** trade runs 1995–2024; Gravity controls stop at 2020.
   Main spec doesn't need Gravity, so I default to the full window. OK?
3. **Storms** include hurricanes hitting ports/factories, not just crops —
   the agriculture-only exposure default is most debatable there.
4. **Unit values** (the literal commodity-pricing angle) are only meaningful
   at HS6 level (chapter-level $/ton mixes wheat with watches). Plan: add a
   separate HS6-level unit-value analysis for the top flood-affected
   chapters in the robustness phase. Confirm you want it.

## Status & critical path

| Item | Status |
|---|---|
| BACI HS92 1995–2024 | ✅ downloaded, verified, unpacked |
| CEPII Gravity V202211 | ✅ downloaded, unpacked |
| Exposure map | ✅ generated (needs Kev's review — storms esp.) |
| Pipeline 00–05 | ✅ runs end-to-end (July 13) |
| EM-DAT export | ✅ 2000–2026; sample restricted to 2001–2024 (pre-2000 is officially "Historic"/low quality — cite doc.emdat.be Time Bias) |
| Severity measure | ✅ severe = top-quartile flood by deaths (≥31) or affected (≥60k); 31% of floods, 743 country-years |
| Comtrade API key | ⏳ optional, low priority |

## Findings so far (July 2026, sample 2001–2024)

> NOTE (audit, July 24): percent figures in this ledger are mostly raw
> PPML coefficients x100. For magnitudes above ~10 that overstates the
> effect; the correct conversion is (exp(b)-1)x100. Examples: flood tons
> b=-0.085 -> -8.2% (not -8.5%); drought tons lag b=-0.196 -> -17.8%
> (not -19.6%); severe earthquake tons b=-0.200 -> -18.2% (not -20.0%).
> The website tables/figures and results_auto.html always convert
> correctly (they compute from the models); when writing the paper, take
> numbers from those, not from this ledger. Full audit passed July 24:
> panel cube complete, lags verified by independent self-merge, severe
> implies any, exposure maps match spec (ch. 77 is HS-reserved, absent
> from trade data by construction), explorer JSON matches saved models
> in all 48 cells, flood headline reproduces exactly under a rewritten
> formula.

> SCOPE CHANGE (July 24, Kev's call): wildfire and extreme_temp REMOVED
> from the analysis. Reason: their exposure maps were drawn without
> human review (the old KEV TO REVIEW items) and Kev chose to drop the
> types rather than defend the maps. Data layer (03/04) still builds
> their columns for possible future use; analysis scripts (08-16),
> website, and report now cover flood/drought/earthquake/storm only.
> Joint model re-estimated with four types (flood tons -8.3%, was
> -8.4% with six). Findings 7-8 below that reference wildfire /
> extreme_temp results are historical record, no longer reported.

1. **Ordinary floods hit exposed products selectively**: flood×exposed
   −0.023 (5%) in the dose spec; no total-export effect.
2. **Severe floods look like a different shock**: severe×exposed is
   POSITIVE (+0.05 at 10% in the M3-style spec) while the severe main
   effect is negative (−0.03, n.s.) — catastrophic floods appear to hit
   *unexposed* (manufacturing) exports at least as hard as agriculture,
   consistent with an infrastructure/supply-chain channel (cf. Thailand
   2011 hard drives). Attenuation story rejected; severity heterogeneity
   is a potential headline finding, needs robustness.
3. **M2 by-sector**: negative for vegetable_products*, instruments,
   transport_equipment, misc_manufactures; positive for
   textiles_apparel**, leather_fur*, footwear_headgear* (vs
   machinery_electrical ref). Pattern worth understanding before
   finalizing the exposure map.
4. **Robustness (R/06, July 15)**: (a) QUANTITY result — ordinary
   floods cut exposed-product TONS by −8.5% (p<0.001) vs −2.3% in
   value: prices rise and mask ~3/4 of the physical supply shock.
   Classic supply-shock signature; strongest estimate in the project.
   (b) Severe×exposed stays positive at every cutoff and GROWS with
   severity (+0.02 at p50 → +0.07 at p90, 10% sig); quantity confirms
   no hidden agriculture drop in severe floods. Severity story robust.

5. **Insurance heterogeneity (R/07, July 15)** — Kev's hypothesis,
   World Bank GFDD.DI.10 median split (166 of 231 countries covered;
   83 high / 83 low). VALUE: flood×exposed = −9.5%* in low-insurance
   countries vs −0.9% (n.s.) in high-insurance; pooled difference +0.075
   (10%). TONS: physical losses in BOTH groups (−12%** low, −7%** high) —
   so the buffering shows up in value (price/composition recovery), not
   in physical output. Severe floods cut agricultural tons −11%*/−15%*
   (year of/after) in LOW-insurance countries only; the "severe floods
   spare agriculture" pattern is a rich-country phenomenon (qty triple
   +0.17*). Caveats: insurance depth proxies wealth; key diffs at 10%;
   65 mostly small/poor countries lack insurance data.

6. **The full matrix (R/08, July 15)** — all four types, dose spec,
   value + tons. Each type has a distinct signature:
   - Drought (agri): delayed physical hit — tons −8.8% year-of (n.s.),
     **−19.6%*** the year AFTER; value −3.6%†. Slow-onset confirmed.
   - Earthquake (heavy mfg): severity is everything — ordinary quakes
     POSITIVE (tons +9.5%**), severe quakes tons **−20.0%*** year-of and
     −15.3%*** year-after. Mirror-image validation of the exposure logic.
   - Storm (agri map): ordinary +2.2%* value, severe lag −4.7%** —
     incoherent under the agriculture-only map; map revision now the
     empirically urgent decision.
   - Severe-drought cell underpowered (77 country-years).
   Caveats: types co-occur (storm→flood); many cells → multiple-testing
   discipline needed in writing.

7. **Wildfire + extreme temperature added (July 22)** — matrix is now
   6 types (all climate-related EM-DAT types with usable samples; epidemic
   excluded for COVID contamination, volcanic for power). Exposure maps
   [KEV TO REVIEW/DEFEND]: wildfire = agri 01-24 + forestry 44-47;
   extreme_temp = agri 01-24. Wildfire (209/76 country-years): value nil;
   severe tons −10.3%* the year after — slow burn-scar channel, but one
   coefficient. Extreme temperature (473/146): NOTHING — value and tons
   flat everywhere (severe tons lag +12.2%* positive if anything).
   Either heatwaves don't move annual chapter-level exports or the
   agriculture map is wrong for them. Honest null; report as such.

8. **Event studies for all 6 types (R/09, July 22)** — the pre-trend
   check generalized. LEADS ARE ~ZERO EVERYWHERE (floods −0.011,
   droughts −0.024, quakes +0.021, wildfire +0.022, extreme temp −0.008,
   all n.s.) — disasters are unanticipated, validating the phase-1
   benchmark for the geopolitical comparison. One exception: SEVERE
   STORMS lead −3.6% (10%), with lags −5.3%*/−3.8%† — either mild
   anticipation (forecastable hurricane seasons?) or storm-map/
   co-occurrence trouble; strengthens the case for revising the storm
   exposure map. Also: severe-drought lag2 +13.3%** (rebound after the
   lag-1 physical trough); severe-wildfire lag2 −6.2%**.

9. **Joint all-six-types spec (R/11, July 22)** — every headline
   coefficient survives essentially unchanged with all types in one
   regression (flood tons −8.8%***, drought lag tons −20.0%***, severe
   quake tons −19.4%***/−16.1%***, severe-storm value lag −4.1%*).
   Co-occurrence robustness: PASSED. Kills the "your flood effect is
   really a storm effect" objection.

10. **Sector scan, all types (R/10, July 22)** — effects estimated
   freely by sector, no map imposed. Two big lessons:
   (a) STORMS: no sector shows a significant negative year-of value
   effect. The storm incoherence is NOT a mapping artifact — no
   exposure map would produce a clean negative value result. Report
   storms as: no relative value damage from ordinary storms; the real
   results are severe storms' delayed negative (−4.1%* joint) and the
   anticipation lead. [Kev/Kleinman: sign off on this reframing.]
   (b) THE TEXTILES PUZZLE (probably) SOLVED: leather/footwear/apparel
   are relatively POSITIVE across MULTIPLE types (storm +14%**/+12%**,
   flood +8.9%*/+5.2%*, extreme temp +17.6%**/+12.4%**) — a cross-
   disaster pattern, so not a flood story. All coefficients are
   relative to machinery_electrical, so the reading likely flips:
   complex manufacturing (fragile supply chains — cf. Thailand 2011)
   falls MORE than labor-intensive goods; apparel doesn't rise,
   machinery drops. Verify with an M3-style absolute spec before
   writing up. Wildfire is the exception (leather −9.7%**, footwear
   −8.4%**: tanneries/workshops burn?).

   Infrastructure: fitted models saved to output/models/*.rds;
   output/results_auto.html regenerated from them by R/12 (no
   hand-typed numbers; supersedes hand-built results_summary.html).

11. **Country-level heterogeneity (R/15, July 22)** — per-country PPML
   (exposed vs unexposed chapters, chapter+year FE), countries with
   >=6 event years and >=6 clean years; 442 estimates saved to
   output/models/country_effects.rds. Rankings are economically
   sensible: storms hit hurricane-belt small states hardest (Vanuatu
   −69%***, Belize −40%***), droughts the Sahel (Niger −67%†, Mali
   −15%**), earthquakes Peru (−21%**) and India (−15%*), floods
   Algeria/Ukraine/Uganda (−42 to −43%). Small-economy estimates are
   noisy; the UI note says to read them with caution.

12. **World price models (R/16, July 22)** — do severe disasters in
   exporting countries move WORLD prices? Outcome: log world unit
   value (USD/ton) per exposed chapter-year; regressor: severe-event
   dummies weighted by the country's pooled share of world exports in
   that chapter; chapter+year FE, clustered by chapter. DROUGHT is
   the clear positive: b=0.72* (≈+7.5% world price per 10 pp of
   market share hit); flood marginal b=0.23† (≈+2.3%); storms/others
   null. Closes the supply-shock loop: quantities fall at the origin
   (finding 6), prices rise on the world market. Models in
   output/models/price_models.rds; top-5 exporters per sector in
   price_leaders.rds. Explorer got a "Results by country" tab
   (Tables 2-3) and per-sector leading-exporter lines.

## Priorities

1. Probe the severity split (value vs. quantity — price effects in
   agriculture; alternative thresholds; event-study dynamics for severe).
2. Kev: exposure-map review informed by M2 table; storm mapping decision.
3. Insurance heterogeneity: World Bank GFDD.DI.10 (non-life premiums/GDP,
   from Swiss Re sigma) → flood × exposed × insurance-depth triple
   interaction. Mechanism/heterogeneity section; wealth-proxy caveat.
4. Other disaster types (drought/earthquake/storm) using the same template.
