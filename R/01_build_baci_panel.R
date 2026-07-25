# Build the main analysis panel from raw BACI:
#   exporter (ISO3) x HS2 chapter x year, 1995-2024.
# Sums over importers and HS6 products. Processes one year at a time so
# memory stays bounded (~1 GB peak instead of 11 GB).
#
# BACI columns: t = year, i = exporter code, j = importer code,
#               k = HS6 product, v = value (thousand USD), q = quantity (tons)

library(data.table)
library(arrow)

raw_dir <- "data/raw/baci"
out_dir <- "data/processed"

files <- list.files(raw_dir, pattern = "^BACI_HS92_Y\\d{4}_V\\d+\\.csv$", full.names = TRUE)
stopifnot(length(files) == 30)

# k must be read as character: chapters 01-09 have leading zeros that
# integer parsing would destroy ("010111" -> 10111 -> wrong chapter).
read_one_year <- function(f) {
  dt <- fread(f, select = c("t", "i", "j", "k", "v", "q"),
              colClasses = list(character = "k"))
  dt[, chapter := substr(k, 1, 2)]
  dt[, .(
    export_value  = sum(v),                    # thousand current USD
    export_qty    = sum(q, na.rm = TRUE),      # metric tons (NA for some products)
    n_products    = uniqueN(k),                # extensive margin: distinct HS6 exported
    n_destinations = uniqueN(j)                # extensive margin: distinct importers
  ), by = .(year = t, exporter_code = i, chapter)]
}

panel <- rbindlist(lapply(files, function(f) {
  message("Processing ", basename(f))
  read_one_year(f)
}))

# Attach ISO3 codes
countries <- fread(file.path(raw_dir, "country_codes_V202601.csv"))
panel <- merge(panel,
               countries[, .(exporter_code = country_code, iso3 = country_iso3)],
               by = "exporter_code", all.x = TRUE)
stopifnot(!anyNA(panel$iso3))

setcolorder(panel, c("iso3", "chapter", "year"))
setkey(panel, iso3, chapter, year)

write_parquet(panel, file.path(out_dir, "trade_exporter_chapter_year.parquet"))
message("Wrote ", nrow(panel), " rows: ",
        uniqueN(panel$iso3), " exporters x ",
        uniqueN(panel$chapter), " chapters x ",
        uniqueN(panel$year), " years.")
