# Figures for the results explorer (output/explorer.html), APA style:
# black and white, serif, generated from the fitted model objects.
# Writes output/figures/apa/es_<type>.png            (6 event studies)
#        output/figures/apa/sec_<sector>_<out>.png   (sector x value/qty)

library(data.table)
library(fixest)

types  <- c("flood", "drought", "earthquake", "storm")
tlab   <- c(flood = "Floods", drought = "Droughts",
            earthquake = "Earthquakes", storm = "Storms")

es_models     <- readRDS("output/models/event_study_models.rds")
sector_models <- readRDS("output/models/sector_scan_models.rds")

dir.create("output/figures/apa", recursive = TRUE, showWarnings = FALSE)

pctf  <- function(b) (exp(b) - 1) * 100
starf <- function(p) ifelse(p < 0.001, "***", ifelse(p < 0.01, "**",
                    ifelse(p < 0.05, "*", ifelse(p < 0.1, "†", ""))))

get_row <- function(m, token) {
  ct <- coeftable(m)
  hit <- vapply(rownames(ct),
                function(r) token %in% strsplit(r, ":", fixed = TRUE)[[1]],
                logical(1))
  if (sum(hit) != 1) return(NULL)
  list(b = unname(ct[hit, 1]), se = unname(ct[hit, 2]),
       p = unname(ct[hit, 4]))
}

# --- event studies ----------------------------------------------------------
for (d in types) {
  rows <- list(
    any = lapply(c(paste0(d, "_dummy_lead1"), paste0(d, "_dummy"),
                   paste0(d, "_dummy_lag1"), paste0(d, "_dummy_lag2")),
                 function(tk) get_row(es_models[[paste0(d, "_any")]], tk)),
    sev = lapply(c(paste0(d, "_severe_dummy_lead1"), paste0(d, "_severe_dummy"),
                   paste0(d, "_severe_dummy_lag1"), paste0(d, "_severe_dummy_lag2")),
                 function(tk) get_row(es_models[[paste0(d, "_sev")]], tk)))
  b  <- lapply(rows, function(rr) sapply(rr, function(r) pctf(r$b)))
  lo <- lapply(rows, function(rr) sapply(rr, function(r) pctf(r$b - 1.96 * r$se)))
  hi <- lapply(rows, function(rr) sapply(rr, function(r) pctf(r$b + 1.96 * r$se)))

  png(sprintf("output/figures/apa/es_%s.png", d),
      width = 1500, height = 700, res = 160)
  par(mar = c(3.6, 4.4, 0.6, 0.6), family = "serif")
  x <- 0:3
  ylim <- range(0, unlist(lo), unlist(hi))
  ylim <- ylim + c(-1, 1) * diff(ylim) * 0.06
  plot(NA, xlim = c(-0.45, 3.45), ylim = ylim, axes = FALSE,
       xlab = "", ylab = "Percent change, exposed products")
  axis(1, at = x, labels = c("t - 1", "event year", "t + 1", "t + 2"),
       padj = -0.4)
  axis(2, las = 1)
  box(bty = "l")
  abline(h = 0, lty = 2, col = "grey40")
  off <- 0.08
  arrows(x - off, lo$any, x - off, hi$any, angle = 90, code = 3,
         length = 0.035)
  points(x - off, b$any, pch = 19, cex = 1.15)
  arrows(x + off, lo$sev, x + off, hi$sev, angle = 90, code = 3,
         length = 0.035)
  points(x + off, b$sev, pch = 21, bg = "white", cex = 1.15)
  legend("topright", c("Any event", "Severe event"), pch = c(19, 21),
         pt.bg = "white", bty = "n", cex = 0.95)
  dev.off()
}
message("event-study figures written")

# --- sector bar charts ------------------------------------------------------
sectors <- sort(unique(unlist(lapply(types, function(d) {
  rn <- rownames(coeftable(sector_models[[paste0(d, "_val")]]))
  rn <- rn[grepl("^sector_group::", rn) & !grepl("_lag1$", rn)]
  sub(":.*$", "", sub("^sector_group::", "", rn))
}))))

for (s in sectors) {
  for (out in c("val", "qty")) {
    cells <- lapply(types, function(d) {
      ct <- coeftable(sector_models[[paste0(d, "_", out)]])
      rn <- sprintf("sector_group::%s:%s_dummy", s, d)
      if (!rn %in% rownames(ct)) return(NULL)
      list(b = ct[rn, 1], se = ct[rn, 2], p = ct[rn, 4])
    })
    png(sprintf("output/figures/apa/sec_%s_%s.png", s, out),
        width = 1500, height = 760, res = 160)
    par(mar = c(3.8, 11, 0.6, 5.5), family = "serif")
    n  <- length(types)
    yc <- rev(seq_len(n))
    v  <- sapply(cells, function(c) if (is.null(c)) NA else pctf(c$b))
    l  <- sapply(cells, function(c) if (is.null(c)) NA else pctf(c$b - 1.96 * c$se))
    h  <- sapply(cells, function(c) if (is.null(c)) NA else pctf(c$b + 1.96 * c$se))
    p  <- sapply(cells, function(c) if (is.null(c)) NA else c$p)
    xlim <- range(0, l, h, na.rm = TRUE)
    xlim <- xlim + c(-1, 1) * diff(xlim) * 0.05
    plot(NA, xlim = xlim, ylim = c(0.4, n + 0.6), axes = FALSE,
         xlab = "Percent change relative to machinery and electronics",
         ylab = "", mgp = c(2.3, 0.7, 0))
    axis(1)
    abline(v = 0, lty = 2, col = "grey40")
    fill <- ifelse(is.na(p), NA,
            ifelse(p < 0.05, "black", ifelse(p < 0.1, "grey55", "grey85")))
    for (i in seq_len(n)) {
      if (is.na(v[i])) {
        text(0, yc[i], "no data", cex = 0.8, col = "grey40", pos = 4)
        next
      }
      rect(min(0, v[i]), yc[i] - 0.28, max(0, v[i]), yc[i] + 0.28,
           col = fill[i], border = "black", lwd = 0.6)
      arrows(l[i], yc[i], h[i], yc[i], angle = 90, code = 3,
             length = 0.03, lwd = 0.9)
      lab <- sprintf("%+.1f%%%s", v[i], starf(p[i]))
      if (v[i] < 0) text(l[i], yc[i], lab, pos = 2, cex = 0.82, xpd = NA)
      else          text(h[i], yc[i], lab, pos = 4, cex = 0.82, xpd = NA)
    }
    axis(2, at = yc, labels = tlab[types], las = 1, tick = FALSE,
         cex.axis = 0.95)
    dev.off()
  }
}
message("sector figures written: ", length(sectors) * 2)
message("Done. Figures in output/figures/apa/")
