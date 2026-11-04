/// The scales-timeline chart, drawn once and embedded in both reports.
///
/// Port of the desktop's matplotlib chart
/// (`dbs_annotator/utils/report_chart_utils.py::build_scales_chart`). One
/// painter rasterised once into both formats is why the PDF and Word reports
/// cannot drift apart, and it is the only way to draw the two features
/// `pw.Chart` cannot: a second y-axis and shaded vertical bands.
///
/// Deliberately matched to the desktop: the Dark2 colour cycle with a dash
/// cycle on top, a missing x breaking the line rather than interpolating, the
/// aggregate-index line on its own 0..1 axis, and the green best and
/// second-best bands spanning +/- 0.35 of an x step.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/brand_palette.dart';
import '../report/report_data.dart';
import 'chart_primitives.dart';

/// Layout constants, in logical px at the painter's nominal size.
///
/// There is deliberately no `_padTop`: the top band holds a title and a legend
/// of unknown height, so hard-coding it overlaps the two. [ChartTopBand]
/// measures it instead, and each element reserves its own space.
const _padBottom = 52.0; // x tick labels + axis label
const _padLeft = 62.0; // y tick labels + axis label

/// Title font size; the band reserves its measured height.
const _titleSize = 15.0;

/// Space between a legend entry's sample line and its label.
const _legendGapAfterSample = 5.0;

/// Vertical gap between stacked panels, in logical px.
const _panelGap = 8.0;

/// One stacked panel of the figure.
class _PanelSpec {
  const _PanelSpec({
    required this.weight,
    required this.yMin,
    required this.yMax,
    required this.label,
    required this.series,
    required this.ticks,
    this.mono = false,
  }) : note = null;

  /// A parameter that never changed, stated in a thin panel instead of
  /// plotted as a flat line: "130 Hz, unchanged (both sides)".
  const _PanelSpec.note(this.label, String this.note)
    : weight = 0,
      yMin = 0,
      yMax = 1,
      series = const {},
      ticks = 1,
      mono = false;

  /// Share of the available height, relative to the other panels.
  final double weight;
  final double yMin, yMax;
  final String label;
  final Map<String, Map<int, double>> series;

  /// Horizontal guides and y ticks to draw, 0 and max inclusive.
  final int ticks;

  /// Draw as one heavy black line with diamond markers, for the index panel.
  final bool mono;

  final String? note;
}

/// Height of a stated-parameter panel, in logical px.
const _notePanelHeight = 16.0;

/// Extra raster height per parameter panel, so adding them does not squeeze
/// the scales panel.
const _plottedPanelExtra = 64.0;

/// A frequency or pulse-width panel: stated when constant, plotted otherwise,
/// absent when nothing was recorded.
_PanelSpec? _parameterPanel(Map<String, Map<int, double>> raw, String unit) {
  final series = {
    for (final e in raw.entries)
      if (e.value.isNotEmpty) e.key: e.value,
  };
  if (series.isEmpty) return null;
  final values = {for (final m in series.values) ...m.values};
  if (values.length == 1) {
    final v = values.single;
    final text = v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    return _PanelSpec.note(
      unit,
      '$text $unit, unchanged${series.length > 1 ? ' (both sides)' : ''}',
    );
  }
  return _PanelSpec(
    weight: 1.0,
    yMin: 0,
    yMax: ScalesChartPainter._niceMax(series),
    label: unit,
    series: series,
    ticks: 2,
  );
}

/// Logical width of a report figure. It is printed across the full text width,
/// about 523 pt on A4, so 1 px prints at about 0.82 pt and the 10 px text floor
/// prints at 8 pt.
const kReportChartWidth = 640.0;

/// The raster size the report embeds: the base figure, plus room for each
/// plotted parameter panel. A stated one is thin enough to share the base
/// height. The stacked base is the least that keeps the index and dose panels
/// legible with 8 pt text; it fits under the baseline table on an A4 page 1.
Size reportChartSize(ScalesChartSpec spec) {
  var extra = 0.0;
  for (final raw in [spec.frequency, spec.pulseWidth]) {
    final panel = _parameterPanel(raw, '');
    if (panel != null && panel.note == null) {
      extra += _plottedPanelExtra + _panelGap;
    }
  }
  // A lone scales panel, as in both longitudinal figures, needs less height
  // than one stacked over the index and dose; the shorter base is what lets
  // two of them share page 1 on US Letter.
  final stacked =
      spec.aggregateIndex.isNotEmpty ||
      spec.amplitude.values.any((m) => m.isNotEmpty);
  return Size(kReportChartWidth, (stacked ? 288 : 212) + extra);
}

class ScalesChartPainter extends CustomPainter {
  const ScalesChartPainter({
    required this.spec,
    this.background = const Color(0xFFFFFFFF),
    this.ink = const Color(0xFF000000),
  });

  final ScalesChartSpec spec;
  final Color background;
  final Color ink;

  bool get _hasIndex => spec.aggregateIndex.isNotEmpty;

  Rect? _plotArea(Size size, ChartTopBand band) {
    final area = Rect.fromLTRB(
      _padLeft,
      band.padTop,
      size.width - 20,
      size.height - _bottomPad(size.width),
    );
    return area.width <= 10 || area.height <= 40 ? null : area;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    if (spec.isEmpty) return;

    final band = ChartTopBand.measure(this, size);
    final area = _plotArea(size, band);
    if (area == null) return;

    // Half a step of margin at each end, as the desktop's `set_xlim` does: it
    // keeps the end markers and the bands clear of the axes, and makes a
    // single-x chart well defined instead of dividing by zero.
    final xLo = spec.xs.first.toDouble() - 0.5;
    final xHi = spec.xs.last.toDouble() + 0.5;
    double xPos(num x) =>
        area.left + (xHi == xLo ? 0.5 : (x - xLo) / (xHi - xLo)) * area.width;

    // Panels share the x mapping but each has its own y axis. That separation
    // is the point: on a shared axis an index of 0.43 would be drawn at the
    // height of 4.3 on a 0..10 rating scale.
    final panels = <_PanelSpec>[
      _PanelSpec(
        weight: 3.0,
        yMin: spec.yMin,
        yMax: spec.yMax,
        label: spec.yLabel,
        series: spec.series,
        ticks: 4,
      ),
      if (_hasIndex)
        _PanelSpec(
          weight: 1.0,
          yMin: 0,
          yMax: 1,
          // The short panels cannot fit a long rotated label without it
          // running into the next panel's; the caption names them in full.
          label: 'Index',
          series: {'Aggregate Index': spec.aggregateIndex},
          ticks: 2,
          mono: true,
        ),
      if (spec.amplitude.values.any((m) => m.isNotEmpty))
        _PanelSpec(
          weight: 1.0,
          // Dose is a magnitude; a non-zero-based axis exaggerates a change.
          yMin: 0,
          yMax: _niceMax(spec.amplitude),
          label: 'mA',
          series: spec.amplitude,
          ticks: 2,
        ),
      ?_parameterPanel(spec.frequency, 'Hz'),
      ?_parameterPanel(spec.pulseWidth, 'µs'),
    ];

    final totalWeight = panels.fold<double>(0, (a, p) => a + p.weight);
    final gaps = _panelGap * (panels.length - 1);
    final fixed = panels.where((p) => p.note != null).length * _notePanelHeight;
    final usable = area.height - gaps - fixed;
    var top = area.top;
    final rects = <Rect>[];
    for (final p in panels) {
      final h = p.note != null
          ? _notePanelHeight
          : usable * p.weight / totalWeight;
      rects.add(Rect.fromLTRB(area.left, top, area.right, top + h));
      top += h + _panelGap;
    }

    // Title and legend first: their fills are opaque, so painting them last
    // would erase whatever they overlap.
    if (band.titleHeight > 0) {
      drawChartText(
        canvas,
        spec.title,
        Offset(area.center.dx, band.titleTop),
        align: TextAlign.center,
        size: _titleSize,
        color: ink,
      );
    }
    _paintLegend(canvas, size, band);

    // One band spanning every panel, so a scale dip can be read against the
    // dose that caused it.
    final stack = Rect.fromLTRB(
      area.left,
      rects.first.top,
      area.right,
      rects.last.bottom,
    );
    _paintBands(canvas, stack, xPos);
    _paintGroupSeparators(canvas, stack, xPos);

    for (var i = 0; i < panels.length; i++) {
      _paintPanel(canvas, rects[i], panels[i], xPos);
    }
    _paintXAxis(canvas, rects.last, size, xPos);
  }

  /// A round number at or above the largest value, so the dose axis gets a
  /// legible top tick.
  static double _niceMax(Map<String, Map<int, double>> series) {
    var hi = 0.0;
    for (final m in series.values) {
      for (final v in m.values) {
        if (v > hi) hi = v;
      }
    }
    if (hi <= 0) return 1;
    for (final step in [0.5, 1.0, 2.0, 2.5, 5.0]) {
      final top = (hi / step).ceil() * step;
      if (top / step <= 8) return top;
    }
    return (hi / 5).ceil() * 5;
  }

  /// One panel: grid, its own y axis with ticks and label, then its series.
  void _paintPanel(
    Canvas canvas,
    Rect plot,
    _PanelSpec panel,
    double Function(num) xPos,
  ) {
    if (plot.height <= 6) return;
    if (panel.note case final note?) {
      drawChartText(
        canvas,
        note,
        Offset(plot.left + 6, plot.center.dy),
        anchorY: 0.5,
        size: 10,
        color: ink,
      );
      drawChartText(
        canvas,
        panel.label,
        Offset(plot.left - 7, plot.center.dy),
        align: TextAlign.right,
        anchorY: 0.5,
        size: 10,
        color: ink,
      );
      return;
    }
    final span = math.max(panel.yMax - panel.yMin, 1e-9);
    double yPos(double v) =>
        plot.bottom - ((v - panel.yMin) / span) * plot.height;

    final grid = Paint()
      ..color = ink.withValues(alpha: 0.3)
      ..strokeWidth = 0.6;
    for (var i = 0; i <= panel.ticks; i++) {
      final y = plot.bottom - plot.height * i / panel.ticks;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }
    for (final x in spec.xs) {
      final px = xPos(x);
      canvas.drawLine(Offset(px, plot.top), Offset(px, plot.bottom), grid);
    }

    _paintPanelSeries(canvas, plot, panel, xPos, yPos);

    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.2;
    canvas
      ..drawLine(plot.bottomLeft, plot.bottomRight, axis)
      ..drawLine(plot.topLeft, plot.bottomLeft, axis);
    for (var i = 0; i <= panel.ticks; i++) {
      final v = panel.yMin + span * i / panel.ticks;
      final y = plot.bottom - plot.height * i / panel.ticks;
      canvas.drawLine(Offset(plot.left - 4, y), Offset(plot.left, y), axis);
      drawChartText(
        canvas,
        tickLabel(v),
        Offset(plot.left - 7, y),
        align: TextAlign.right,
        anchorY: 0.5,
        size: 10,
        color: ink,
      );
    }
    drawRotatedChartText(
      canvas,
      panel.label,
      Offset(16, plot.center.dy),
      size: 11,
      color: ink,
    );
  }

  /// A panel's series, in the Dark2 colour and dash cycle unless
  /// [_PanelSpec.mono] is set.
  void _paintPanelSeries(
    Canvas canvas,
    Rect plot,
    _PanelSpec panel,
    double Function(num) xPos,
    double Function(double) yPos,
  ) {
    var i = 0;
    for (final entry in panel.series.entries) {
      final color = panel.mono ? ink : seriesColor(i);
      final dash = panel.mono ? null : seriesDash(i);
      i++;
      drawSeriesRuns(
        canvas,
        seriesRuns(spec.xs, entry.value, xPos, yPos),
        color: color,
        dash: dash,
        strokeWidth: panel.mono ? 3 : 2,
        markerRadius: panel.mono ? 0 : 3,
        marker: seriesMarker(i - 1),
      );
      if (!panel.mono) continue;
      for (final x in spec.xs) {
        final v = entry.value[x];
        if (v == null) continue;
        canvas.drawPath(
          diamondPath(Offset(xPos(x), yPos(v)), 4.5),
          Paint()..color = color,
        );
      }
    }
  }

  /// The widest tick label, at the size it is drawn horizontally.
  double get _longestTick => spec.xTickLabels.values
      .map((l) => (chartTextPainter(l, color: ink, size: 10)..layout()).width)
      .fold(0.0, math.max);

  /// Labels are rotated only when they would overlap side by side on a canvas
  /// [width] wide: two visit dates fit flat, a dozen do not.
  bool _rotateTicks(double width) {
    if (spec.xTickLabels.isEmpty || spec.xs.isEmpty) return false;
    final step = (width - _padLeft - 20) / spec.xs.length;
    return _longestTick + 8 > step;
  }

  /// Room under the plot. Slanted tick labels hang down by their own length
  /// times sin 45, so the margin grows with the longest one rather than
  /// clipping it into the axis title.
  double _bottomPad(double width) {
    if (!_rotateTicks(width)) return _padBottom + _groupRowHeight;
    return math.max(_padBottom, 8 + _longestTick * math.sqrt1_2 + 34) +
        _groupRowHeight;
  }

  /// Room for the row of group labels under the ticks, when there is one.
  double get _groupRowHeight => spec.xGroups.isEmpty ? 0 : 16;

  /// The shared x axis, under the bottom panel.
  void _paintXAxis(
    Canvas canvas,
    Rect plot,
    Size size,
    double Function(num) xPos,
  ) {
    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.2;
    final rotate = _rotateTicks(size.width);
    for (final x in spec.xs) {
      final px = xPos(x);
      canvas.drawLine(
        Offset(px, plot.bottom),
        Offset(px, plot.bottom + 4),
        axis,
      );
      final label = spec.xTickLabels[x] ?? '$x';
      if (rotate) {
        // At 45 degrees, reading left to right and ending at its tick.
        drawRotatedChartText(
          canvas,
          label,
          Offset(px, plot.bottom + 8),
          size: 10,
          color: ink,
          angle: -math.pi / 4,
          anchorEnd: true,
        );
      } else {
        drawChartText(
          canvas,
          label,
          Offset(px, plot.bottom + 7),
          align: TextAlign.center,
          size: 10,
          color: ink,
        );
      }
    }
    // The group row sits between the ticks and the axis title.
    for (final g in spec.xGroups) {
      drawChartText(
        canvas,
        g.label,
        Offset((xPos(g.from) + xPos(g.to)) / 2, size.height - 38),
        align: TextAlign.center,
        size: 10,
        color: ink,
      );
    }
    drawChartText(
      canvas,
      spec.xLabel,
      Offset(plot.center.dx, size.height - 22),
      align: TextAlign.center,
      size: 12,
      color: ink,
    );
  }

  /// A thin rule after each group but the last, from the top of the plot down
  /// through the tick labels, so where one visit ends reads at a glance.
  void _paintGroupSeparators(
    Canvas canvas,
    Rect plot,
    double Function(num) xPos,
  ) {
    final rule = Paint()
      ..color = ink.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 0; i + 1 < spec.xGroups.length; i++) {
      final x = xPos(spec.xGroups[i].to + 0.5);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom + 20), rule);
    }
  }

  /// Green vertical bands behind everything, marking the best and second-best
  /// block, the desktop's `axvspan(x +/- 0.35)`. Clipped to the plot, since a
  /// band on the first or last block would otherwise spill over the axis.
  void _paintBands(Canvas canvas, Rect plot, double Function(num) xPos) {
    canvas
      ..save()
      ..clipRect(plot);

    // Contiguous blocks of one setting are drawn as one band, because the unit
    // being marked is the configuration: two rectangles with a gap between
    // them would read as two settings rather than one rated twice.
    void bands(List<int> xs, int argb) {
      if (xs.isEmpty) return;
      final paint = Paint()..color = Color(argb);
      final hatch = Paint()
        ..color = ink.withValues(alpha: 0.16)
        ..strokeWidth = 0.9;
      // Denser for rank 1, so the order reads without colour.
      final step = argb == kBestFill ? 7.0 : 14.0;
      final sorted = xs.toList()..sort();
      var from = sorted.first;
      var to = sorted.first;
      void flush() {
        final r = Rect.fromLTRB(
          xPos(from - 0.35),
          plot.top,
          xPos(to + 0.35),
          plot.bottom,
        );
        canvas
          ..drawRect(r, paint)
          ..save()
          ..clipRect(r);
        drawChartText(
          canvas,
          argb == kBestFill ? '1' : '2',
          Offset(r.center.dx, r.top + 2),
          align: TextAlign.center,
          size: 10,
          color: ink,
        );
        for (var hx = r.left - r.height; hx < r.right + r.height; hx += step) {
          canvas.drawLine(
            Offset(hx, r.bottom),
            Offset(hx + r.height, r.top),
            hatch,
          );
        }
        canvas.restore();
      }

      for (final x in sorted.skip(1)) {
        if (x == to + 1) {
          to = x;
          continue;
        }
        flush();
        from = x;
        to = x;
      }
      flush();
    }

    // Second first, so a shared edge lets the stronger best colour win.
    bands(spec.secondXs, kSecondFill);
    bands(spec.bestXs, kBestFill);
    canvas.restore();
  }

  /// Single-row legend, boxed and centred in the space [band] reserved for it.
  void _paintLegend(Canvas canvas, Size size, ChartTopBand band) {
    final legend = band.legend;
    if (legend == null) return;

    final box = Rect.fromLTWH(
      math.max(2, (size.width - legend.total) / 2 - 8),
      band.legendTop,
      math.min(legend.total + 16, size.width - 4),
      legend.height,
    );
    canvas
      ..drawRect(box, Paint()..color = background)
      ..drawRect(
        box,
        Paint()
          ..color = ink.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      )
      // Clip the contents: a single label wider than the canvas can still
      // exceed the box, and a sample line spilling out of the frame looks
      // like a rendering fault.
      ..save()
      ..clipRect(box);

    for (final (row, indices) in legend.rows.indexed) {
      var x = box.left + 8;
      final y = box.top + 2.5 + legend.rowHeight * (row + 0.5);
      for (final i in indices) {
        x = _paintLegendEntry(canvas, legend, i, x, y);
      }
    }
    canvas.restore();
  }

  /// One legend sample and its label at [x], returning where the next starts.
  double _paintLegendEntry(
    Canvas canvas,
    ChartLegend legend,
    int i,
    double x,
    double y,
  ) {
    {
      final (_, color, dash, kind) = legend.entries[i];
      if (kind == ChartLegendKind.band) {
        // The two greens differ in lightness only, so on a mono printer the
        // hatch is what tells them apart.
        final swatch = Rect.fromLTWH(x, y - 5, legend.sample, 10);
        canvas
          ..drawRect(swatch, Paint()..color = color)
          ..drawRect(
            swatch,
            Paint()
              ..color = ink.withValues(alpha: 0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8,
          )
          ..save()
          ..clipRect(swatch);
        final hatch = Paint()
          ..color = ink.withValues(alpha: 0.45)
          ..strokeWidth = 0.8;
        // Rank 1 gets the denser hatch, so the order survives too.
        final step = color.toARGB32() == kBestFill ? 4.0 : 8.0;
        for (var hx = swatch.left - 10; hx < swatch.right + 10; hx += step) {
          canvas.drawLine(
            Offset(hx, swatch.bottom),
            Offset(hx + 10, swatch.top),
            hatch,
          );
        }
        canvas.restore();
      } else {
        final line = Path()
          ..moveTo(x, y)
          ..lineTo(x + legend.sample, y);
        canvas.drawPath(
          dash == null ? line : dashPath(line, dash),
          Paint()
            ..color = color
            ..strokeWidth = kind == ChartLegendKind.aggregate ? 3 : 2
            ..style = PaintingStyle.stroke,
        );
        final markerX = x + legend.sample / 2;
        if (kind == ChartLegendKind.aggregate) {
          canvas.drawPath(
            diamondPath(Offset(markerX, y), 4),
            Paint()..color = color,
          );
        } else {
          drawMarker(canvas, Offset(markerX, y), 2.8, color, seriesMarker(i));
        }
      }
      x += legend.sample + _legendGapAfterSample;
      final p = legend.painters[i];
      p.paint(canvas, Offset(x, y - p.height / 2));
      return x + p.width + legend.gapBetween;
    }
  }

  @override
  bool shouldRepaint(ScalesChartPainter old) =>
      old.spec != spec || old.background != background || old.ink != ink;
}

/// What kind of sample a legend entry draws.
enum ChartLegendKind {
  /// A dashed or solid line with a round marker: one session scale.
  series,

  /// A heavy line with a diamond: the aggregate index. Not named `index`,
  /// which every Dart enum already declares.
  aggregate,

  /// A filled, hatched swatch: a green ranking band.
  band,
}

/// The legend's shrink-to-fit result: what to draw, and how wide it came out.
typedef ChartLegend = ({
  List<(String, Color, List<double>?, ChartLegendKind)> entries,
  List<TextPainter> painters,

  /// Entry indices per legend row, top to bottom.
  List<List<int>> rows,
  double sample,
  double gapBetween,

  /// The widest row.
  double total,
  double rowHeight,
  double height,
});

/// "Rank 1", with the scope the rank was taken over when the spec names one.
String _rank(int n, ScalesChartSpec spec) =>
    spec.rankScope.isEmpty ? 'Rank $n' : 'Rank $n ${spec.rankScope}';

/// The measured top band: title, then legend, then the plot.
///
/// Each element reserves its own height, so a two-line title or a legend that
/// shrank to fit cannot collide with anything. Public only so
/// `scales_chart_layout_test.dart` can assert those non-overlap invariants
/// directly rather than by inspecting pixels.
class ChartTopBand {
  const ChartTopBand({
    required this.titleTop,
    required this.titleHeight,
    required this.legendTop,
    required this.padTop,
    required this.legend,
  });

  final double titleTop;
  final double titleHeight;
  final double legendTop;

  /// Where the plot may start.
  final double padTop;

  /// Null when there is nothing to put in a legend.
  final ChartLegend? legend;

  static const _outerPad = 6.0;
  static const _gap = 6.0;

  static ChartTopBand measure(ScalesChartPainter p, Size size) {
    final titleHeight = p.spec.title.isEmpty
        ? 0.0
        : chartTextPainter(p.spec.title, color: p.ink, size: _titleSize).height;
    final legend = _measureLegend(p, size);
    final legendTop = _outerPad + (titleHeight > 0 ? titleHeight + _gap : 0.0);
    return ChartTopBand(
      titleTop: _outerPad,
      titleHeight: titleHeight,
      legendTop: legendTop,
      padTop: legendTop + (legend == null ? _gap : legend.height + _gap + 2),
      legend: legend,
    );
  }

  /// Shrink to fit rather than overflow: a session with many scales would
  /// otherwise push the legend off the canvas.
  static ChartLegend? _measureLegend(ScalesChartPainter p, Size size) {
    final entries = <(String, Color, List<double>?, ChartLegendKind)>[
      for (final (i, name) in p.spec.series.keys.indexed)
        (name, seriesColor(i), seriesDash(i), ChartLegendKind.series),
      if (p.spec.aggregateIndex.isNotEmpty)
        ('Aggregate Index', p.ink, null, ChartLegendKind.aggregate),
      if (p.spec.bestXs.isNotEmpty)
        (_rank(1, p.spec), const Color(kBestFill), null, ChartLegendKind.band),
      if (p.spec.secondXs.isNotEmpty)
        (
          _rank(2, p.spec),
          const Color(kSecondFill),
          null,
          ChartLegendKind.band,
        ),
    ];
    if (entries.isEmpty) return null;

    var font = 11.0;
    var sample = 22.0;
    var gapBetween = 14.0;
    final maxWidth = size.width - 20;
    var painters = <TextPainter>[];
    double widthOf(int i) => sample + _legendGapAfterSample + painters[i].width;
    double rowWidth(List<int> row) =>
        row.fold<double>(0, (sum, i) => sum + widthOf(i)) +
        gapBetween * (row.length - 1);
    while (true) {
      painters = [
        for (final e in entries)
          chartTextPainter(e.$1, color: p.ink, size: font),
      ];
      final all = [for (var i = 0; i < entries.length; i++) i];
      if (rowWidth(all) <= maxWidth || font <= 10) break;
      font -= 0.5;
      sample = math.max(16, sample - 1);
      gapBetween = math.max(8, gapBetween - 1);
    }
    final rows = <List<int>>[[]];
    for (var i = 0; i < entries.length; i++) {
      if (rows.last.isNotEmpty && rowWidth([...rows.last, i]) > maxWidth) {
        rows.add([]);
      }
      rows.last.add(i);
    }
    // Row height from the tallest label, so a larger font is never clipped.
    final textHeight = painters.fold<double>(
      0,
      (m, t) => math.max(m, t.height),
    );
    final rowHeight = math.max(14.0, textHeight + 3);
    return (
      entries: entries,
      painters: painters,
      rows: rows,
      sample: sample,
      gapBetween: gapBetween,
      total: rows.map(rowWidth).fold(0.0, math.max),
      rowHeight: rowHeight,
      height: rowHeight * rows.length + 5,
    );
  }
}

/// Rasterise the scales chart to PNG bytes for embedding in a report.
///
/// [size] is the logical chart size and [pixelRatio] multiplies it, so the
/// default is well above the desktop chart's resolution. Returns null when
/// there is nothing to plot or [size] leaves no room for the plot area, so
/// callers can fall back to a text line.
Future<Uint8List?> renderScalesChartPng(
  ScalesChartSpec spec, {
  Size? size,
  double pixelRatio = 4.0,
}) async {
  if (spec.isEmpty) return null;
  final canvasSize = size ?? reportChartSize(spec);
  final painter = ScalesChartPainter(spec: spec);
  if (painter._plotArea(
        canvasSize,
        ChartTopBand.measure(painter, canvasSize),
      ) ==
      null) {
    return null;
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  painter.paint(canvas, canvasSize);
  final image = await recorder.endRecording().toImage(
    (canvasSize.width * pixelRatio).round(),
    (canvasSize.height * pixelRatio).round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}
