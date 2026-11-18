/// Parts of the visit preview: the figures of the report across visits, each
/// with zoom, the clinical ranges they are drawn on, and the full-window view.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../core/prefs/user_prefs.dart';
import '../core/session/scale_presets.dart';
import '../report/longitudinal_data.dart';
import '../report/report_data.dart' show ScalesChartSpec;
import 'scales_chart_painter.dart';

const _maxZoom = 8;

/// The declared range of each clinical scale, from the presets and [prefs];
/// empty when the presets cannot be read.
Future<Map<String, (double, double)>> clinicalRanges(UserPrefs prefs) async {
  try {
    return numericRanges(
      mergeScalePresets(await loadScalePresets(), prefs).clinicalRanges,
    );
  } catch (e) {
    debugPrint('Clinical scale ranges unavailable: $e');
    return const {};
  }
}

/// [body] over the whole window under [title], until Close.
Future<void> showEnlarged(
  BuildContext context, {
  required String title,
  required WidgetBuilder body,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Builder(builder: body),
      ),
    ),
  ),
);

/// The clinical scales by visit, then the symptom and side effect ratings by
/// visit and configuration, as the report across visits draws them.
class AcrossVisitsCharts extends StatelessWidget {
  const AcrossVisitsCharts({
    super.key,
    required this.data,
    this.enlarged = false,
  });

  final LongitudinalReportData data;

  /// Shares the window's height between the two figures.
  final bool enlarged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = enlarged
        ? math.max(360.0, (MediaQuery.sizeOf(context).height - 240) / 2)
        : 360.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!data.clinicalChart.isEmpty) ...[
          _ZoomableChart(
            title: 'Clinical scales by visit',
            spec: data.clinicalChart,
            height: height,
          ),
          const SizedBox(height: 16),
        ],
        if (data.sessionChart.isEmpty)
          Text(
            'No session scale values in the chosen files.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          )
        else
          _ZoomableChart(
            title: 'Symptom and side effect ratings by visit and configuration',
            spec: data.sessionChart,
            height: height,
          ),
      ],
    );
  }
}

class _ZoomableChart extends StatefulWidget {
  const _ZoomableChart({
    required this.title,
    required this.spec,
    required this.height,
  });

  final String title;
  final ScalesChartSpec spec;
  final double height;

  @override
  State<_ZoomableChart> createState() => _ZoomableChartState();
}

class _ZoomableChartState extends State<_ZoomableChart> {
  var _zoom = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.title, style: theme.textTheme.titleSmall),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Zoom in',
              onPressed: _zoom < _maxZoom
                  ? () => setState(() => _zoom *= 2)
                  : null,
              icon: const Icon(Icons.zoom_in),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Zoom out',
              onPressed: _zoom > 1 ? () => setState(() => _zoom ~/= 2) : null,
              icon: const Icon(Icons.zoom_out),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, c) => ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: c.maxWidth * _zoom,
                height: widget.height,
                child: CustomPaint(
                  painter: ScalesChartPainter(
                    spec: widget.spec,
                    background: theme.colorScheme.surface,
                    ink: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
