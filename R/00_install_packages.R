# Install everything the pipeline needs. Run once after installing R.

pkgs <- c(
  "data.table",   # fast reading/aggregation of the 11 GB BACI files
  "arrow",        # parquet read/write for processed data
  "fixest",       # fepois (PPML) estimation
  "readxl",       # EM-DAT arrives as .xlsx
  "janitor",      # clean_names() for EM-DAT's messy headers
  "countrycode",  # ISO code reconciliation across datasets
  "ggplot2",      # figures
  "modelsummary", # regression tables
  "concordance"   # HS -> BEC / ISIC mappings (robustness)
)

missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) {
  install.packages(missing, repos = "https://cloud.r-project.org")
} else {
  message("All packages already installed.")
}

# Verify everything loads
for (p in pkgs) suppressPackageStartupMessages(library(p, character.only = TRUE))
message("OK: all ", length(pkgs), " packages load.")
