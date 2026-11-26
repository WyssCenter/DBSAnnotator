/// Parts of the visit preview: the figures of the report across visits, each
/// with zoom, the clinical ranges they are drawn on, and the full-window view.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../core/prefs/user_prefs.dart';
import '../core/session/longitudinal.dart' show patientIdsMatch;
import '../core/session/scale_presets.dart';
import '../core/session/scale_scoring.dart';
import '../core/session/session_row.dart';
import '../core/session/tsv_kind.dart';
import '../report/longitudinal_data.dart';
import '../report/report_data.dart' show ScalesChartSpec, coerceInt;
import '../report/upload_actions.dart' show Uploaded;
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

/// The target and range of each symptom and side effect rating, from the
/// presets and [prefs], the first group listing a name deciding; empty when
/// the presets cannot be read.
Future<Map<String, ScalePref>> ratingTargets(UserPrefs prefs) async {
  try {
    final targets = <String, ScalePref>{};
    for (final rows in mergeScalePresets(
      await loadScalePresets(),
      prefs,
    ).session.values) {
      for (final r in rows) {
        targets.putIfAbsent(
          r.name,
          () => scalePrefFromStrings(
            name: r.name,
            min: r.min,
            max: r.max,
            mode: r.mode,
            custom: r.custom,
          ),
        );
      }
    }
    return targets;
  } catch (e) {
    debugPrint('Rating targets unavailable: $e');
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
        : 240.0;
    final ratings = data.sessionChart.isEmpty
        ? Text(
            'No session scale values in the chosen files.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          )
        : _ZoomableChart(
            title: 'Symptom and side effect ratings by visit and configuration',
            spec: data.sessionChart,
            height: enlarged ? height : 360,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!data.clinicalChart.isEmpty &&
            (enlarged || data.visits.length > 1)) ...[
          _ZoomableChart(
            title: 'Clinical scales by visit',
            spec: data.clinicalChart,
            height: height,
          ),
          const SizedBox(height: 16),
        ],
        if (enlarged)
          ratings
        else
          ExpansionTile(
            title: const Text(
              'Symptom and side effect ratings by visit and configuration',
            ),
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            children: [ratings],
          ),
        if (data.rankingTargets.isNotEmpty)
          targetsNote(context, data.rankingTargets),
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

/// What a clinician checks before a returning patient's visit, from the
/// latest of [visits]: the devices, the settings left on, the highest scores
/// and the clinical scales, against [ranges] and the targets [known] from the
/// ratings settings. [onOpen] shows a visit by its file name. Empty across
/// patients or with no session.
class LastVisitCard extends StatelessWidget {
  const LastVisitCard({
    super.key,
    required this.visits,
    required this.ranges,
    required this.known,
    required this.onOpen,
  });

  final List<Uploaded> visits;
  final Map<String, (double, double)> ranges;
  final Map<String, ScalePref> known;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = [
      for (final f in visits)
        if (f.kind == TsvKind.programming) f,
    ];
    if (all.isEmpty || !patientIdsMatch(all.map((f) => f.name).toList())) {
      return const SizedBox.shrink();
    }
    final data = buildLongitudinalReportData(
      clinicalRanges: ranges,
      files: {for (final f in all) f.name: f.rows},
      scalePrefs: defaultScalePrefsFor([
        for (final f in all)
          ...f.rows.where((r) => coerceInt(r.isInitial) != 1),
      ], known: known),
    );
    final summary = latestVisitSummary(data);
    if (summary == null) return const SizedBox.shrink();
    final last = data.visits.last;
    final rows = all.firstWhere((f) => f.name == last.filename).rows;
    String value(String Function(SessionRow) cell) =>
        sessionValueIn(rows, cell);
    String pair(String left, String right) =>
        right.isEmpty || right == left ? left : 'left $left, right $right';
    final highest = [...last.session.bestBlocks, ...last.session.secondBlocks];
    final table = data.visitTable;
    String scales(List<String> row) => row.last.split('\n').join(', ');
    final clinical = table.isEmpty ? '' : scales(table.last);
    final previous = table.length < 2 ? '' : scales(table[table.length - 2]);
    final label = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    Widget line(String name, String text) => text.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$name: ', style: label),
                  TextSpan(text: text),
                ],
              ),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(summary.heading, style: theme.textTheme.titleMedium),
              line('DBS indication', value((r) => r.pathology)),
              line('Anatomical target', value((r) => r.target)),
              line(
                'Leads',
                pair(
                  value((r) => r.leftElectrodeModel),
                  value((r) => r.rightElectrodeModel),
                ),
              ),
              line(
                'IPG',
                pair(
                  value((r) => r.leftIpgModel),
                  value((r) => r.rightIpgModel),
                ),
              ),
              for (final l in summary.lines)
                switch (l.indexOf(': ')) {
                  -1 => line('Settings', l),
                  final at => line(l.substring(0, at), l.substring(at + 2)),
                },
              line(
                'Highest scores',
                highest.isEmpty
                    ? ''
                    : '${highest.length == 1 ? 'configuration' : 'configurations'} '
                          '${highest.join(' and ')}. ${data.rankingTargets}',
              ),
              line(
                'Clinical scales',
                previous.isEmpty || previous == clinical
                    ? clinical
                    : '$clinical (previous visit: $previous)',
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () => onOpen(last.filename),
                  child: const Text('Open last visit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The scale targets a ranking used, printed under its figures.
Widget targetsNote(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  ),
);
