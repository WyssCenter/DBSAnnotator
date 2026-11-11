/// The four stacked panels reviewing what has been inserted: session scales,
/// amplitude, pulse width and frequency, sharing one horizontally scrollable
/// x axis.
///
/// There is no `Scrollable` here. The panels must stay in x-alignment, and
/// four `SingleChildScrollView`s with synchronised controllers can drift,
/// since each runs its own physics simulation. A single [_offset] in state
/// feeds every painter instead, so alignment holds by construction.
///
/// Panning is therefore explicit: a horizontal drag on the plot area, plus
/// wheel and trackpad via `PointerSignalEvent`. Reordering uses explicit drag
/// handles, so a pan and a reorder cannot contend for the same gesture.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';

import '../../core/brand_palette.dart';
import '../../report/entry_charts.dart';
import '../chart_primitives.dart';

/// Width of the fixed left gutter at text scale 1. It holds only the y tick
/// labels; the title and series key live in a full-width header above each
/// panel, because a narrow gutter silently clips every series past the third.
const double _gutterWidth = 52;

/// Height of one panel's plot area at text scale 1.
const double _panelHeight = 116;

/// Vertical inset inside a plot, so markers do not touch the frame.
const double _plotPadY = 8;

/// The x-axis strip's two lines: the clock time, then the block number.
const double _axisTimeSize = 14;
const double _axisBlockSize = 12;

/// Horizontal room one axis label needs, per point of its font size.
const double _labelPitch = 5.2;

/// Measured rather than assumed, because a [TextScaler] need not be linear.
double _boxFactor(TextScaler scaler) =>
    scaler.scale(_axisTimeSize) / _axisTimeSize;

/// Height of the shared x-axis strip under the last panel.
double _axisHeight(TextScaler scaler) =>
    5 + scaler.scale(_axisTimeSize) + 2 + scaler.scale(_axisBlockSize) + 3;

/// How many configurations fill the viewport by default, and the zoom bounds.
const int kDefaultVisibleConfigs = 10;
const int _minVisible = 3;
const int _maxVisible = 60;

class EntryChartsView extends StatefulWidget {
  const EntryChartsView({
    super.key,
    required this.data,
    this.order,
    this.onOrderChanged,
    this.visibleConfigs = kDefaultVisibleConfigs,
    this.onVisibleConfigsChanged,
    this.bestXs = const [],
    this.secondXs = const [],
  });

  final EntryChartData data;

  /// Persisted panel order by id; null uses the default order.
  final List<String>? order;
  final ValueChanged<List<String>>? onOrderChanged;

  /// How many configurations fill the viewport (the zoom level), persisted.
  final int visibleConfigs;
  final ValueChanged<int>? onVisibleConfigsChanged;

  /// Blocks to mark with a green band, from the same ranking the report uses.
  final List<int> bestXs;
  final List<int> secondXs;

  @override
  State<EntryChartsView> createState() => _EntryChartsViewState();
}

class _EntryChartsViewState extends State<EntryChartsView> {
  /// Horizontal pan, in pixels from the left edge of the content.
  ///
  /// Starts at infinity, which the first layout clamps to the right-hand end,
  /// so a long session opens on its newest configurations rather than its
  /// oldest.
  double _offset = double.infinity;

  /// While true, new configurations keep the view on the most recent ones, as
  /// wanted during a session. Panning left releases it.
  bool _followLatest = true;

  int _lastXCount = 0;

  @override
  void didUpdateWidget(EntryChartsView old) {
    super.didUpdateWidget(old);
    if (widget.data.xs.length != _lastXCount) {
      _lastXCount = widget.data.xs.length;
      if (_followLatest) _offset = double.infinity; // clamped on next layout
    }
  }

  /// The A+/A- setting. The widgets follow it already; the painted axis does
  /// not, because a `TextPainter` defaults to no scaling.
  TextScaler get _scaler => MediaQuery.textScalerOf(context);

  /// Pixels per configuration.
  ///
  /// Divides by the smaller of the zoom window and the number of
  /// configurations recorded, so a session with fewer blocks than the window
  /// still fills the width instead of stopping short and looking broken.
  double _pxPerStep(double viewport) {
    final window = widget.visibleConfigs.clamp(_minVisible, _maxVisible);
    final steps = math.max(1, math.min(window, widget.data.xs.length));
    return viewport / steps;
  }

  double _contentWidth(double viewport) =>
      math.max(viewport, widget.data.xs.length * _pxPerStep(viewport));

  double _maxOffset(double viewport) =>
      math.max(0, _contentWidth(viewport) - viewport);

  void _pan(double dx, double viewport) {
    setState(() {
      // Clamp before applying the delta: _offset can be the infinity sentinel
      // meaning "the end", and infinity minus dx is still infinity, so the
      // first drag would do nothing.
      final max = _maxOffset(viewport);
      _offset = (_offset.clamp(0.0, max) - dx).clamp(0.0, max);
      // Panning back to the right edge re-arms follow-the-latest.
      _followLatest = _offset >= max - 0.5;
    });
  }

  void _zoom(int delta) {
    final next = (widget.visibleConfigs + delta).clamp(
      _minVisible,
      _maxVisible,
    );
    if (next == widget.visibleConfigs) return;
    widget.onVisibleConfigsChanged?.call(next);
  }

  void _reorderItem(int oldIndex, int newIndex, List<ParamPanel> panels) {
    final ids = panels.map((p) => p.id).toList();
    ids.insert(newIndex, ids.removeAt(oldIndex));
    widget.onOrderChanged?.call(ids);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panels = orderPanels(widget.data.panels, widget.order);
    final xs = widget.data.xs;

    if (xs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No configurations inserted yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.disabledColor,
            ),
          ),
        ),
      );
    }

    final scaler = _scaler;
    final factor = _boxFactor(scaler);
    final gutter = _gutterWidth * factor;
    // Half rate: the plot holds no text of its own, so it only has to keep
    // pace with its tick labels. Growing it in full would push the table a
    // screen further down at A+.
    final panelHeight = _panelHeight * (1 + (factor - 1) / 2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = math.max(80.0, constraints.maxWidth - gutter);
        final pxPerStep = _pxPerStep(viewport);
        // Clamp here rather than in setState: the viewport is only known now,
        // and `didUpdateWidget` parks the offset at infinity for "the end".
        final offset = _offset.clamp(0.0, _maxOffset(viewport));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(theme, xs.length, viewport, pxPerStep, offset),
            // Wheel and trackpad pan the whole figure, not one panel.
            Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  final d = e.scrollDelta;
                  _pan(-(d.dx.abs() > d.dy.abs() ? d.dx : d.dy), viewport);
                }
              },
              child: ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                // onReorderItem gives an index already adjusted for the
                // removal.
                onReorderItem: (o, n) => _reorderItem(o, n, panels),
                children: [
                  for (var i = 0; i < panels.length; i++)
                    _panelRow(
                      theme,
                      panels[i],
                      i,
                      xs,
                      pxPerStep,
                      offset,
                      viewport,
                      gutter,
                      panelHeight,
                    ),
                ],
              ),
            ),
            // The shared x axis, drawn once under the last panel.
            Row(
              children: [
                SizedBox(width: gutter),
                Expanded(
                  child: SizedBox(
                    height: _axisHeight(scaler),
                    child: CustomPaint(
                      painter: _XAxisPainter(
                        xs: xs,
                        labels: widget.data.xLabels,
                        pxPerStep: pxPerStep,
                        offset: offset,
                        ink: theme.colorScheme.onSurfaceVariant,
                        scaler: scaler,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            _scrollbar(theme, viewport, offset, gutter),
          ],
        );
      },
    );
  }

  /// A real, draggable scrollbar under the shared axis.
  ///
  /// The figure pans by drag and wheel, but with nothing on screen saying so a
  /// long session just looks truncated. Reduced to a thin spacer when
  /// everything already fits, so it never implies hidden data.
  Widget _scrollbar(
    ThemeData theme,
    double viewport,
    double offset,
    double gutter,
  ) {
    final maxOff = _maxOffset(viewport);
    if (maxOff <= 0.5) return const SizedBox(height: 6);
    final thumbWidth = (viewport * viewport / _contentWidth(viewport)).clamp(
      32.0,
      viewport,
    );
    final travel = math.max(1.0, viewport - thumbWidth);
    return Padding(
      padding: EdgeInsets.only(left: gutter, top: 6, bottom: 2),
      child: GestureDetector(
        // Thumb pixels to content pixels, so the thumb tracks the finger.
        onHorizontalDragUpdate: (d) =>
            _pan(-d.delta.dx * maxOff / travel, viewport),
        child: SizedBox(
          height: 10,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 3,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned(
                left: (offset / maxOff) * travel,
                top: 0,
                width: thumbWidth,
                height: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: .55,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    ThemeData theme,
    int total,
    double viewport,
    double pxPerStep,
    double offset,
  ) {
    final first = (offset / pxPerStep).floor() + 1;
    final last = math.min(total, (offset + viewport) / pxPerStep).ceil();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total <= widget.visibleConfigs
                  ? 'All $total configurations'
                  : 'Configurations $first-$last of $total',
              style: theme.textTheme.bodySmall,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Show fewer configurations (zoom in)',
            onPressed: widget.visibleConfigs > _minVisible
                ? () => _zoom(-2)
                : null,
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Show more configurations (zoom out)',
            onPressed: widget.visibleConfigs < _maxVisible
                ? () => _zoom(2)
                : null,
            icon: const Icon(Icons.zoom_out),
          ),
        ],
      ),
    );
  }

  Widget _panelRow(
    ThemeData theme,
    ParamPanel panel,
    int index,
    List<int> xs,
    double pxPerStep,
    double offset,
    double viewport,
    double gutter,
    double panelHeight,
  ) {
    final names = panel.series.keys.toList();
    return Container(
      key: ValueKey(panel.id),
      // Without a boundary, four stacked plots read as one figure.
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The series key sits at full width so it is never clipped, however
          // many scales are recorded.
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Tooltip(
                    message: 'Drag to reorder',
                    child: Icon(
                      Icons.drag_indicator,
                      size: 16,
                      color: theme.disabledColor,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  panel.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      for (var i = 0; i < names.length; i++)
                        _SeriesKey(
                          // Marked when the two sides are numerically
                          // identical: one line hides under the other, so the
                          // reader cannot otherwise tell a coincidence from a
                          // missing series.
                          name: panel.coincident.contains(names[i])
                              ? '${names[i]} (identical)'
                              : names[i],
                          color: seriesColor(i),
                          dash: seriesDash(i),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (panel.constantLabel != null)
            // An unchanged parameter gets a sentence, not a third of the
            // figure: plotted, it is a flat line mid-axis, which reads as a
            // measured mid-range value rather than as a constant.
            Padding(
              padding: EdgeInsets.only(left: gutter, bottom: 8),
              child: Text(
                panel.constantLabel!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Row(
              children: [
                SizedBox(
                  width: gutter,
                  height: panelHeight,
                  child: _YGutter(panel: panel, theme: theme),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) => _pan(d.delta.dx, viewport),
                    child: SizedBox(
                      height: panelHeight,
                      child: CustomPaint(
                        painter: _PanelPainter(
                          panel: panel,
                          xs: xs,
                          pxPerStep: pxPerStep,
                          offset: offset,
                          bestXs: widget.bestXs,
                          secondXs: widget.secondXs,
                          ink: theme.colorScheme.onSurfaceVariant,
                          grid: theme.dividerColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One legend entry: a short line in the series colour and dash, plus its name.
class _SeriesKey extends StatelessWidget {
  const _SeriesKey({required this.name, required this.color, this.dash});

  final String name;
  final Color color;
  final List<double>? dash;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 16,
        height: 8,
        child: CustomPaint(
          painter: _KeyLinePainter(color: color, dash: dash),
        ),
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}

class _KeyLinePainter extends CustomPainter {
  const _KeyLinePainter({required this.color, this.dash});

  final Color color;
  final List<double>? dash;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y);
    canvas
      ..drawPath(
        dash == null ? line : dashPath(line, dash!),
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      )
      ..drawCircle(Offset(size.width / 2, y), 2.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_KeyLinePainter old) =>
      old.color != color || old.dash != dash;
}

/// Fixed left cell: the y range, aligned with the plot's own vertical padding.
class _YGutter extends StatelessWidget {
  const _YGutter({required this.panel, required this.theme});

  final ParamPanel panel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final mid = (panel.yMin + panel.yMax) / 2;
    return Padding(
      padding: const EdgeInsets.only(
        right: 5,
        top: _plotPadY - 5,
        bottom: _plotPadY - 5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tickLabel(panel.yMax), style: theme.textTheme.bodySmall),
          Text(tickLabel(mid), style: theme.textTheme.bodySmall),
          Text(tickLabel(panel.yMin), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// One panel's plot: bands, grid and series, clipped to the viewport and
/// translated by the shared pan offset.
class _PanelPainter extends CustomPainter {
  const _PanelPainter({
    required this.panel,
    required this.xs,
    required this.pxPerStep,
    required this.offset,
    required this.ink,
    required this.grid,
    this.bestXs = const [],
    this.secondXs = const [],
  });

  final ParamPanel panel;
  final List<int> xs;
  final double pxPerStep;
  final double offset;
  final Color ink;
  final Color grid;
  final List<int> bestXs;
  final List<int> secondXs;

  @override
  void paint(Canvas canvas, Size size) {
    if (xs.isEmpty || size.width <= 0) return;
    canvas
      ..save()
      ..clipRect(Offset.zero & size);

    double xPos(num i) => (i.toDouble() + 0.5) * pxPerStep - offset;
    final span = math.max(panel.yMax - panel.yMin, 1e-9);
    double yPos(double v) =>
        size.height -
        _plotPadY -
        ((v - panel.yMin) / span) * (size.height - 2 * _plotPadY);

    // Bands first, so everything else draws over them.
    void bands(List<int> blocks, int argb) {
      for (final block in blocks) {
        final i = xs.indexOf(block);
        if (i < 0) continue;
        canvas.drawRect(
          Rect.fromLTRB(xPos(i - 0.42), 0, xPos(i + 0.42), size.height),
          Paint()..color = Color(argb).withValues(alpha: 0.25),
        );
      }
    }

    // The report's own constants, not copies: re-typing the two greens here is
    // how the screen and the printed table come to disagree about which block
    // won.
    bands(secondXs, kSecondFill);
    bands(bestXs, kBestFill);

    // Horizontal guides, and one vertical per configuration.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.6;
    for (var k = 0; k <= 2; k++) {
      final y = _plotPadY + (size.height - 2 * _plotPadY) * k / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var i = 0; i < xs.length; i++) {
      final x = xPos(i);
      if (x < -pxPerStep || x > size.width + pxPerStep) continue;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint..color = grid.withValues(alpha: 0.5),
      );
    }

    // Keyed by index so colour and dash match the header key.
    final indexOf = {for (var i = 0; i < xs.length; i++) xs[i]: i};
    var s = 0;
    for (final entry in panel.series.entries) {
      final byIndex = <int, double>{
        for (final e in entry.value.entries)
          if (indexOf[e.key] != null) indexOf[e.key]!: e.value,
      };
      drawSeriesRuns(
        canvas,
        seriesRuns(List.generate(xs.length, (i) => i), byIndex, xPos, yPos),
        color: seriesColor(s),
        dash: seriesDash(s),
        markerRadius: pxPerStep > 26 ? 2.6 : 1.8,
      );
      s++;
    }

    // Drawn last and heavier than the guides, so the frame of one panel is
    // distinguishable from the guides of the next.
    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    // Inset by half the stroke: a line on the clip edge draws at half width.
    final baseline = size.height - _plotPadY;
    canvas
      ..drawLine(const Offset(1, _plotPadY), Offset(1, baseline), axis)
      ..drawLine(Offset(1, baseline), Offset(size.width, baseline), axis)
      ..restore();
  }

  @override
  bool shouldRepaint(_PanelPainter old) =>
      old.panel != panel ||
      old.xs != xs ||
      old.pxPerStep != pxPerStep ||
      old.offset != offset ||
      old.bestXs != bestXs ||
      old.secondXs != secondXs ||
      old.ink != ink ||
      old.grid != grid;
}

/// The shared x axis: a tick per configuration, labelled with its clock time.
class _XAxisPainter extends CustomPainter {
  const _XAxisPainter({
    required this.xs,
    required this.labels,
    required this.pxPerStep,
    required this.offset,
    required this.ink,
    required this.scaler,
  });

  final List<int> xs;
  final Map<int, String> labels;
  final double pxPerStep;
  final double offset;
  final Color ink;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (xs.isEmpty) return;
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    final axis = Paint()
      ..color = ink
      ..strokeWidth = 1.6;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), axis);

    // Thin out labels when zoomed out, by the drawn size, so they cannot
    // overlap at any text scale.
    final timeSize = scaler.scale(_axisTimeSize);
    final every = math.max(1, (timeSize * _labelPitch / pxPerStep).ceil());
    for (var i = 0; i < xs.length; i++) {
      final x = (i + 0.5) * pxPerStep - offset;
      if (x < -20 || x > size.width + 20) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, 3), axis);
      if (i % every != 0) continue;
      final label = labels[xs[i]] ?? '${xs[i]}';
      drawChartText(
        canvas,
        label,
        Offset(x, 5),
        color: ink,
        align: TextAlign.center,
        size: _axisTimeSize,
        scaler: scaler,
      );
      drawChartText(
        canvas,
        '#${xs[i]}',
        Offset(x, 5 + timeSize + 2),
        color: ink,
        align: TextAlign.center,
        size: _axisBlockSize,
        scaler: scaler,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_XAxisPainter old) =>
      old.xs != xs ||
      old.labels != labels ||
      old.pxPerStep != pxPerStep ||
      old.offset != offset ||
      old.ink != ink ||
      old.scaler != scaler;
}
