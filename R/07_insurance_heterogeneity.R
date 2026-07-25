# Insurance heterogeneity: does financial protection buffer the flood shock?
# (Kev's hypothesis.)
#
# Measure: World Bank GFDD.DI.10 - non-life insurance premiums / GDP
# (source: Swiss Re sigma), country-year; the series ends in 2020.
# Disclosures for the writeup: the inner merge drops countries without
# insurance data (incl. S19/Taiwan and IRQ, ~2.75% of export value);
# severe-flood treatment is 503 low-ins vs 186 high-ins country-years;
# "low insurance" includes CHN/IND/MEX/VNM, so this is an
# insurance-depth split, not a poor-country split.
# Countries are split at the cross-country median of their AVERAGE
# penetration over the sample - a fixed grouping, so no country switches
# groups mid-sample and the split can't respond to disasters themselves.
#
# Interpretation caveat (report alongside results): insurance depth is
# strongly correlated with income and infrastructure quality. This is a
# heterogeneity ("effect is concentrated in...") result, NOT proof that
# insurance causally buffers. Adverse selection (flood-prone countries
# insure more) biases AGAINST finding a buffer - discuss in the paper.

library(data.table)
library(arrow)
library(fixest)

panel <- setDT(read_parquet("data/processed/estimation_panel.parquet"))
panel <- panel[year >= 2001]
panel[, flood        := flood_dummy]
panel[, flood_l1     := flood_dummy_lag1]
panel[, flood_sev    := flood_severe_dummy]
panel[, flood_sev_l1 := flood_severe_dummy_lag1]
panel[, exposed      := flood_exposed]

# --- Insurance data: wide WB csv -> country average penetration ------------
ins_file <- list.files("data/raw/insurance", pattern = "^API_.*\\.csv$",
                       full.names = TRUE)
stopifnot(length(ins_file) == 1)
ins <- fread(ins_file, skip = 4, header = TRUE)
yr_cols <- grep("^(19|20)\\d{2}$", names(ins), value = TRUE)
ins <- melt(ins[, c("Country Code", yr_cols), with = FALSE],
            id.vars = "Country Code",
            variable.name = "year", value.name = "nonlife_gdp",
            variable.factor = FALSE)
setnames(ins, "Country Code", "iso3")
ins <- ins[!is.na(nonlife_gdp) & year >= 2001]

ins_avg <- ins[, .(ins_depth = mean(nonlife_gdp)), by = iso3]

# Median split among countries actually in the trade panel
ins_avg <- ins_avg[iso3 %in% unique(panel$iso3)]
med <- median(ins_avg$ins_depth)
ins_avg[, high_ins := as.integer(ins_depth > med)]
message(sprintf("Insurance data: %d panel countries (of %d) | median depth %.2f%% of GDP",
                nrow(ins_avg), uniqueN(panel$iso3), med))

panel <- merge(panel, ins_avg, by = "iso3")   # drops countries w/o data
message(sprintf("Estimation sample: %d rows | high-ins countries: %d | low: %d",
                nrow(panel), uniqueN(panel[high_ins == 1, iso3]),
                uniqueN(panel[high_ins == 0, iso3])))

fe <- "iso3^year + chapter^year + iso3^chapter"
dose <- function(outcome) as.formula(sprintf(
  "%s ~ flood:exposed + flood_l1:exposed + flood_sev:exposed + flood_sev_l1:exposed | %s",
  outcome, fe))

# --- Split-sample: the readable version -------------------------------------
v_low  <- fepois(dose("export_value"), panel[high_ins == 0], cluster = ~iso3)
v_high <- fepois(dose("export_value"), panel[high_ins == 1], cluster = ~iso3)
q_low  <- fepois(dose("export_qty"),   panel[high_ins == 0], cluster = ~iso3)
q_high <- fepois(dose("export_qty"),   panel[high_ins == 1], cluster = ~iso3)

# --- Pooled triple interaction: the formal difference test ------------------
# (exposed x high_ins base terms absorbed by iso3^chapter FE)
v_pool <- fepois(as.formula(paste(
  "export_value ~ flood:exposed + flood:exposed:high_ins +",
  "flood_l1:exposed + flood_l1:exposed:high_ins +",
  "flood_sev:exposed + flood_sev:exposed:high_ins +",
  "flood_sev_l1:exposed + flood_sev_l1:exposed:high_ins |", fe)),
  panel, cluster = ~iso3)
q_pool <- fepois(as.formula(paste(
  "export_qty ~ flood:exposed + flood:exposed:high_ins +",
  "flood_l1:exposed + flood_l1:exposed:high_ins +",
  "flood_sev:exposed + flood_sev:exposed:high_ins +",
  "flood_sev_l1:exposed + flood_sev_l1:exposed:high_ins |", fe)),
  panel, cluster = ~iso3)

sig <- c("***" = 0.001, "**" = 0.01, "*" = 0.05, "+" = 0.1)
etable(v_low, v_high, v_pool, q_low, q_high, q_pool,
       headers = c("Val LowIns", "Val HighIns", "Val pooled",
                   "Tons LowIns", "Tons HighIns", "Tons pooled"),
       signif.code = sig,
       file = "output/tables/insurance_heterogeneity.tex", replace = TRUE)
saveRDS(list(v_low = v_low, v_high = v_high, v_pool = v_pool,
             q_low = q_low, q_high = q_high, q_pool = q_pool),
        "output/models/insurance_models.rds")
print(etable(v_low, v_high, v_pool, q_low, q_high, q_pool,
             headers = c("Val Low", "Val High", "Val pool",
                         "Ton Low", "Ton High", "Ton pool")))

message("Done. Table: output/tables/insurance_heterogeneity.tex")
