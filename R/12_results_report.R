# Auto-generated phase-1 results report.
# Reads the fitted model objects saved by R/08-11 and writes
# output/results_auto.html + event-study figures. Every number flows from
# coeftable(), so the report cannot disagree with the estimates.
# Open with: open output/results_auto.html   (figures use relative paths)

library(data.table)
library(fixest)

types  <- c("flood", "drought", "earthquake", "storm")
labels <- c(flood = "Flood", drought = "Drought", earthquake = "Earthquake",
            storm = "Storm")

matrix_models <- readRDS("output/models/matrix_models.rds")
es_models     <- readRDS("output/models/event_study_models.rds")
sector_models <- readRDS("output/models/sector_scan_models.rds")
joint_models  <- readRDS("output/models/joint_models.rds")

# --- coefficient helpers ----------------------------------------------------
stars <- function(p) ifelse(p < 0.001, "***", ifelse(p < 0.01, "**",
                    ifelse(p < 0.05, "*", ifelse(p < 0.1, "&dagger;", ""))))

# Find the row whose interaction parts (split on ":") contain `token`.
get_row <- function(m, token) {
  ct <- coeftable(m)
  hit <- vapply(rownames(ct),
                function(r) token %in% strsplit(r, ":", fixed = TRUE)[[1]],
                logical(1))
  if (sum(hit) != 1) return(NULL)
  ct[hit, , drop = FALSE]
}

cell <- function(m, token) {
  r <- get_row(m, token)
  if (is.null(r)) return("&mdash;")
  sprintf("%.4f%s<br><span class='se'>(%.4f)</span>",
          r[1, 1], stars(r[1, 4]), r[1, 2])
}

# --- event-study figures ----------------------------------------------------
dir.create("output/figures", showWarnings = FALSE)
es_tokens <- function(v) c(paste0(v, "_lead1"), v, paste0(v, "_lag1"),
                           paste0(v, "_lag2"))

for (d in types) {
  png(sprintf("output/figures/es_%s.png", d),
      width = 720, height = 440, res = 108)
  par(mar = c(4, 4.5, 2.5, 1))
  xs <- c(-1, 0, 1, 2)
  series <- list(
    any    = list(m = es_models[[paste0(d, "_any")]],
                  v = paste0(d, "_dummy"),        col = "#2c5f8a", off = -0.07),
    severe = list(m = es_models[[paste0(d, "_sev")]],
                  v = paste0(d, "_severe_dummy"), col = "#b0413e", off = 0.07))
  est <- lapply(series, function(s) {
    rows <- lapply(es_tokens(s$v), function(tk) get_row(s$m, tk))
    list(b  = vapply(rows, function(r) if (is.null(r)) NA_real_ else r[1, 1],
                     numeric(1)),
         se = vapply(rows, function(r) if (is.null(r)) NA_real_ else r[1, 2],
                     numeric(1)))
  })
  ylim <- range(unlist(lapply(est, function(e)
    c(e$b - 1.96 * e$se, e$b + 1.96 * e$se))), 0, na.rm = TRUE)
  plot(NA, xlim = c(-1.4, 2.4), ylim = ylim, xaxt = "n",
       xlab = "Years since disaster", ylab = "Coefficient (exposed x event)",
       main = paste0(labels[d], ": event study (export value)"))
  axis(1, at = xs, labels = c("-1 (lead)", "0", "+1", "+2"))
  abline(h = 0, lty = 2, col = "grey55")
  for (nm in names(series)) {
    s <- series[[nm]]; e <- est[[nm]]
    segments(xs + s$off, e$b - 1.96 * e$se, xs + s$off, e$b + 1.96 * e$se,
             col = s$col, lwd = 1.6)
    points(xs + s$off, e$b, pch = 19, col = s$col, cex = 1.1)
  }
  legend("topright", c("any event", "severe"), col = c("#2c5f8a", "#b0413e"),
         pch = 19, bty = "n")
  dev.off()
}
message("event-study figures written")

# --- HTML tables ------------------------------------------------------------
tok4 <- function(d) paste0(d, c("_dummy", "_dummy_lag1",
                                "_severe_dummy", "_severe_dummy_lag1"))
matrix_table <- function(get_model) {
  rows <- sapply(types, function(d) {
    cs <- sapply(tok4(d), function(tk) cell(get_model(d), tk))
    sprintf("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
            labels[d], cs[1], cs[2], cs[3], cs[4])
  })
  paste0("<table><tr><th></th><th>any, year of</th><th>any, year after</th>",
         "<th>severe, year of</th><th>severe, year after</th></tr>",
         paste(rows, collapse = ""), "</table>")
}
tbl_val   <- matrix_table(function(d) matrix_models[[paste0(d, "_val")]])
tbl_qty   <- matrix_table(function(d) matrix_models[[paste0(d, "_qty")]])
tbl_j_val <- matrix_table(function(d) joint_models$joint_val)
tbl_j_qty <- matrix_table(function(d) joint_models$joint_qty)

# Sector scan: year-of coefficient per sector x type
sector_models <- sector_models[grep("_val$", names(sector_models))]
names(sector_models) <- sub("_val$", "", names(sector_models))
sec <- sort(unique(unlist(lapply(sector_models, function(m) {
  rn <- rownames(coeftable(m))
  rn <- rn[grepl("^sector_group::", rn) & !grepl("_lag1$", rn)]
  sub(":.*$", "", sub("^sector_group::", "", rn))
}))))
sec_rows <- sapply(sec, function(s) {
  cs <- sapply(types, function(d) {
    ct <- coeftable(sector_models[[d]])
    rn <- sprintf("sector_group::%s:%s_dummy", s, d)
    if (!rn %in% rownames(ct)) return("&mdash;")
    sprintf("%.3f%s", ct[rn, 1], stars(ct[rn, 4]))
  })
  sprintf("<tr><td>%s</td>%s</tr>", s,
          paste0("<td>", cs, "</td>", collapse = ""))
})
tbl_sec <- paste0("<table><tr><th>sector (vs machinery_electrical)</th>",
                  paste0("<th>", labels[types], "</th>", collapse = ""),
                  "</tr>", paste(sec_rows, collapse = ""), "</table>")

figs <- paste(sprintf(
  "<h3>%s</h3><img src='figures/es_%s.png' alt='%s event study'>",
  labels[types], types, labels[types]), collapse = "")

html <- sprintf("<!DOCTYPE html><html><head><meta charset='utf-8'>
<title>Disaster-trade: phase 1 results (auto-generated)</title>
<style>
 body{font-family:Georgia,serif;max-width:900px;margin:2rem auto;
      padding:0 1rem;line-height:1.5;color:#222}
 table{border-collapse:collapse;margin:1rem 0;font-size:0.92rem}
 td,th{border:1px solid #bbb;padding:0.35rem 0.6rem;text-align:center}
 th{background:#f0ede6}td:first-child{text-align:left}
 .se{color:#777;font-size:0.85em}
 img{max-width:100%%}
 .note{background:#f6f4ee;padding:0.6rem 0.9rem;border-left:3px solid #999}
</style></head><body>
<h1>Disaster&ndash;trade: phase 1 results</h1>
<p class='note'>Auto-generated by R/12_results_report.R from the fitted
model objects &mdash; no hand-transcribed numbers. Signif: *** 0.1%%,
** 1%%, * 5%%, &dagger; 10%%. PPML, three-way FE
(iso3&times;year, chapter&times;year, iso3&times;chapter), SEs clustered
by exporter. Sample 2001&ndash;2024. Coefficients &asymp; proportional
effects on exposed relative to unexposed products.</p>
<h2>1. The matrix &mdash; export value</h2>%s
<h2>2. The matrix &mdash; physical volume (tons)</h2>%s
<h2>3. Joint specification (all six types at once) &mdash; value</h2>
<p>Each type conditional on the other five; robustness for co-occurring
disasters (storms cause floods).</p>%s
<h2>4. Joint specification &mdash; tons</h2>%s
<h2>5. Event studies (value)</h2>
<p>Blue: any event. Red: severe. Whiskers: 95%% CI. The lead (-1) tests
for pre-trends/anticipation.</p>%s
<h2>6. Sector scan (year-of effect by sector, value)</h2>
<p>Effect estimated freely per sector group &mdash; no exposure map
imposed. Read this to judge the exposure maps, esp. storms.</p>%s
</body></html>",
  tbl_val, tbl_qty, tbl_j_val, tbl_j_qty, figs, tbl_sec)

writeLines(html, "output/results_auto.html")
message("Done. Report: output/results_auto.html")
