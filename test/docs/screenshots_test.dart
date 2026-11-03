/// Generates the screenshots used in `docs/`.
///
/// Opt-in: a plain `flutter test` skips this. From the repo root:
///
/// ```powershell
/// $env:DOCS_SCREENSHOT_DIR = "docs/_static/screenshots"
/// flutter test test/docs/screenshots_test.dart
/// ```
///
/// `RenderRepaintBoundary.toImage` needs no display, so this runs headless in
/// CI with no device, emulator or `flutter_driver`. The output is committed,
/// because Read the Docs cannot run Flutter.
///
/// Three traps, each producing a plausible-looking wrong result: `toImage()`
/// never completes under the widget-test fake clock, so it and `toByteData`
/// must run inside `tester.runAsync`; `flutter_tester` ships no fonts, so
/// every glyph renders as a filled box unless real ones are registered with
/// [FontLoader]; and the binding sets `debugDisableShadows = true` for golden
/// determinism, so Material elevation renders flat.
///
/// Two rules: never hand-pick a height ([_shootFitted] and [_shootRegion]
/// measure the laid-out content instead of cutting through it), and never
/// photograph an empty form (every capture is seeded by a `_seed*` helper).
library;

import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/electrode/geometry.dart';
import 'package:dbs_annotator/core/electrode/stimulation_rule.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_row.dart'
    show electrodeModelIn;
import 'package:dbs_annotator/report/longitudinal_data.dart';
import 'package:dbs_annotator/report/annotations_report.dart';
import 'package:dbs_annotator/report/longitudinal_pdf.dart';
import 'package:dbs_annotator/report/longitudinal_sections.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/report_sections.dart';
import 'package:dbs_annotator/report/session_pdf.dart';
import 'package:dbs_annotator/ui/report_images.dart';
import 'package:dbs_annotator/ui/scales_chart_painter.dart';
import 'package:dbs_annotator/ui/annotations_screen.dart';
import 'package:dbs_annotator/ui/bids_merge_ui.dart';
import 'package:dbs_annotator/ui/close_guard.dart';
import 'package:dbs_annotator/ui/electrode_view.dart';
import 'package:dbs_annotator/ui/home_screen.dart';
import 'package:dbs_annotator/ui/painter_font.dart';
import 'package:dbs_annotator/ui/report_sections_dialog.dart';
import 'package:dbs_annotator/ui/save_target.dart' show debugSaveDir;
import 'package:dbs_annotator/ui/scale_slider.dart';
import 'package:dbs_annotator/ui/session/entry_charts_view.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/ui/reports_screen.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:dbs_annotator/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show FontLoader, MethodChannel, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'example_visits.dart';

/// Where PNGs are written; unset means the default `flutter test` does nothing.
final String? _outDir = Platform.environment['DOCS_SCREENSHOT_DIR'];

const _boundary = ValueKey('docs-screenshot');

/// Resolved once in `setUpAll`; applied to every capture's theme.
String? _textFont;

/// The two canvas widths every capture uses. One number per layout rather
/// than one per screenshot: mixed widths render at different apparent scales
/// on the same documentation page. [_wide] is above the 900 px breakpoint in
/// `session_screen.dart`, so the two-row layout the docs describe is what gets
/// drawn; [_narrow] is below it, and is also the width for screens whose own
/// content is capped (the home screen's card column is 600 px).
const double _wide = 1440;
const double _narrow = 900;

/// The window a dialog is measured in. A dialog that is only a paragraph
/// grows with the window, in the app as here, so those are measured in
/// [_textDialogWidth] instead, which Material's 40 px insets turn into a
/// 460 px card: a readable line in the docs, with the app left unbounded.
const double _dialogWidth = 1100;
const double _textDialogWidth = 540;
const _textDialogs = {
  'dialog_save_location',
  'dialog_record_into',
  'dialog_bids_start',
  'dialog_bids_not_dataset',
  'dialog_keep_recovery',
  'dialog_reopen_unfinished',
};

/// The tallest window a capture may use before it has to become a region.
/// Anything taller renders as an illegible sliver at documentation width; the
/// recording step is ~4800 px with its charts and entries table laid out.
const double _maxHeight = 3000;

/// Device pixels of background kept below the last painted row of a trimmed
/// capture. 32 device pixels is 16 logical, which reads as a margin.
const int _trimMargin = 32;

// One consistent patient across every capture, so the screenshots read as one
// session rather than as unrelated fragments: sub-01, run 01, an OCD scale
// set, a segmented Medtronic lead with current steered across two segments.

const _fixture = exampleFixture;
const _defaultModel = 'Medtronic SenSight B33005';
const _subjectId = '01';
const _runId = '01';
const _preset = 'PD';
const _frequency = '125';
const _amplitude = '5.5';
const _pulseWidth = '90';
const _initialNotes =
    'Baseline on admission settings. Medication unchanged since last visit.';
const _recordingNotes =
    'Noticeably less checking behaviour; patient reports a lighter mood.';

/// Ratings as a fraction of each scale's range, cycled across the rows.
const _ratings = <double>[0.62, 0.35, 0.48, 0.7, 0.25];

/// Register every font in the asset bundle, plus the Material icon font.
/// Walking `FontManifest.json` rather than hard-coding asset keys picks up
/// `MaterialIcons-Regular.otf` and every family `pubspec.yaml` declares.
Future<void> _loadFonts() async {
  final manifest = await rootBundle.loadString('FontManifest.json');
  for (final entry in json.decode(manifest) as List<dynamic>) {
    final family = (entry as Map<String, dynamic>)['family'] as String;
    final loader = FontLoader(family);
    for (final asset in entry['fonts'] as List<dynamic>) {
      final path = (asset as Map<String, dynamic>)['asset'] as String;
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

/// The text font to render captures with, or null when none could be found.
/// `flutter_tester` ships no fonts, and `FontManifest.json` holds only what
/// `pubspec.yaml` declares, so without an explicit text font every glyph
/// renders as a filled box while the capture still succeeds. The committed
/// `assets/fonts/IBMPlexSans-*.ttf` come first, because they make the
/// screenshots reproducible on any machine and in CI; a host system font is
/// the fallback should they ever be dropped from the bundle.
Future<String?> _loadTextFont() async {
  try {
    final loader = FontLoader('DocsText')
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Bold.ttf'));
    await loader.load();
    return 'DocsText';
  } catch (_) {
    // Not bundled in this checkout; fall through.
  }

  // A host font. Regular and bold go into one family so bold text is really
  // bold rather than synthesised.
  const candidates = <List<String>>[
    // seguisym carries the symbol glyphs: the validity tick is a literal
    // U+2713, and the test binding has no OS fallback chain to find it with.
    [
      'C:/Windows/Fonts/segoeui.ttf',
      'C:/Windows/Fonts/segoeuib.ttf',
      'C:/Windows/Fonts/seguisym.ttf',
    ],
    ['C:/Windows/Fonts/arial.ttf', 'C:/Windows/Fonts/arialbd.ttf'],
    [
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
    ],
    [
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    ],
  ];
  for (final pair in candidates) {
    if (!File(pair.first).existsSync()) continue;
    final loader = FontLoader('DocsText');
    for (final path in pair.where((p) => File(p).existsSync())) {
      loader.addFont(
        Future.value(ByteData.view(File(path).readAsBytesSync().buffer)),
      );
    }
    await loader.load();
    return 'DocsText';
  }
  return null;
}

/// The app's theme with [_textFont] applied to every text style.
ThemeData _withFont(ThemeData base) => _textFont == null
    ? base
    : base.copyWith(textTheme: base.textTheme.apply(fontFamily: _textFont));

/// Pump [home] inside the capture boundary, which wraps the `MaterialApp`'s
/// content through its `builder` rather than the home widget, so a dialog or a
/// `MenuAnchor`'s menu in the Navigator's overlay is captured along with the
/// screen behind it. `debugDisableShadows` is toggled here and restored in
/// [_shoot] rather than in setUp/tearDown, because the binding's check that
/// painting debug variables are back to their defaults runs inside the test
/// body.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Brightness brightness = Brightness.light,
  Size size = const Size(_wide, _maxHeight),
  double textScale = 1.0,
}) async {
  debugDisableShadows = false;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      // The real theme, with a text font substituted in; see [_loadTextFont]
      // for why one has to be supplied explicitly.
      theme: _withFont(dbsTheme(brightness)),
      builder: (context, child) => RepaintBoundary(
        key: _boundary,
        child: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

/// The last row of [image] with anything drawn on it, where "anything" means
/// "differs from the bottom-right pixel", the page background on every screen
/// here. Returns `image.height - 1` when there is nothing to trim.
int _lastPaintedRow(ByteData raw, int width, int height) {
  final px = raw.buffer.asUint8List();
  int at(int x, int y) => (y * width + x) * 4;
  final bg = at(width - 1, height - 1);
  bool isBackground(int i) =>
      px[i] == px[bg] &&
      px[i + 1] == px[bg + 1] &&
      px[i + 2] == px[bg + 2] &&
      px[i + 3] == px[bg + 3];

  for (var y = height - 1; y >= 0; y--) {
    for (var x = 0; x < width; x++) {
      if (!isBackground(at(x, y))) return y;
    }
  }
  return height - 1;
}

/// Capture the boundary, optionally cropping dead background off the bottom.
/// [trim] exists because a scroll view's `maxScrollExtent` measures the extent
/// it will scroll, which on the wizard steps runs well past the last thing
/// actually drawn: step 1 came out 44 % empty. The frame is cut to the last
/// painted row plus [_trimMargin], and only captures whose height came from a
/// scroll view use it. A region, a dialog or a deliberately-sized empty state
/// is already framed on purpose.
Future<void> _shoot(
  WidgetTester tester,
  String name, {
  bool trim = false,
}) async {
  // Image.asset decodes asynchronously and never completes under the fake
  // clock, so the AppBar logo would be missing from every capture.
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  final bytes = await tester.runAsync(() async {
    var image = await boundary.toImage(pixelRatio: 2);

    if (trim) {
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final keep = raw == null
          ? image.height
          : _lastPaintedRow(raw, image.width, image.height) + 1 + _trimMargin;
      if (keep < image.height) {
        final recorder = ui.PictureRecorder();
        final rect = Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          keep.toDouble(),
        );
        Canvas(recorder).drawImageRect(image, rect, rect, Paint());
        final cropped = await recorder.endRecording().toImage(
          image.width,
          keep,
        );
        image.dispose();
        image = cropped;
      }
    }

    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });

  final file = File('$_outDir/$name.png')..createSync(recursive: true);
  file.writeAsBytesSync(bytes!);

  // Restore before the test body ends; see [_pump].
  debugDisableShadows = true;
}

/// The screen's own vertical scroll view, or null when it has none. The first
/// vertical one in tree order is the page; a screen may also hold horizontal
/// scrollables (the entries table, the annotations `DataTable`), and measuring
/// one of those would size the window to a row height.
ScrollableState? _pageScroll(WidgetTester tester) {
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    if (state.position.axis == Axis.vertical &&
        state.position.hasContentDimensions) {
      return state;
    }
  }
  return null;
}

/// Capture [name] with the window sized to exactly the laid-out content: the
/// scroll view's own `viewportDimension + maxScrollExtent`, plus whatever
/// chrome sits outside it. [fallback] covers a screen with no scroll view,
/// such as an empty state that is one centred `Column` and so cannot be
/// measured. [height] skips the measurement for a body that fills the window
/// rather than flowing down it: the longitudinal review puts its chart in an
/// `Expanded`, so "fit to content" has no fixed point there.
Future<void> _shootFitted(
  WidgetTester tester,
  String name, {
  double width = _wide,
  double fallback = 420,
  double max = _maxHeight,
  double? height,
}) async {
  if (height != null) {
    await tester.binding.setSurfaceSize(Size(width, height));
    await tester.pumpAndSettle();
    await _shoot(tester, name);
    return;
  }
  // Measure from a deliberately short window. `maxScrollExtent` is how much
  // content overflows the viewport, so from a tall window it is 0 whether the
  // content fits exactly or with 2000 px to spare. From a short one the
  // overflow is real and the height is `viewportDimension + maxScrollExtent`.
  const probe = 400.0;
  await tester.binding.setSurfaceSize(Size(width, probe));
  await tester.pumpAndSettle();

  final scroll = _pageScroll(tester);
  final double fitted;
  if (scroll == null) {
    fitted = fallback;
  } else {
    final position = scroll.position;
    final chrome = probe - position.viewportDimension;
    fitted = (chrome + position.viewportDimension + position.maxScrollExtent)
        .ceilToDouble()
        .clamp(200.0, max);
  }

  await tester.binding.setSurfaceSize(Size(width, fitted));
  await tester.pumpAndSettle();
  await _shoot(tester, name, trim: scroll != null);
}

/// Capture the band from [from]'s top edge to [to]'s bottom, for steps too
/// tall to photograph whole. The page is scrolled so [from] sits flush under
/// the AppBar and the window is sized to the band, so both cuts land on a real
/// boundary rather than through a widget. [max] caps content that is
/// unboundedly long on purpose: the entries table grows a row per (block,
/// scale), reaching ~2900 px here, over this repo's 600 KB large-file gate.
Future<void> _shootRegion(
  WidgetTester tester,
  String name, {
  required Finder from,
  required Finder to,
  double width = _wide,
  double pad = 16,
  double max = _maxHeight,
}) async {
  Future<void> alignTop() async {
    if (_pageScroll(tester) == null) return;
    await Scrollable.ensureVisible(
      tester.element(from),
      alignment: 0,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
  }

  await tester.binding.setSurfaceSize(Size(width, _maxHeight));
  await tester.pumpAndSettle();
  await alignTop();

  // `from` is now at the top of the viewport, so its own offset is the chrome
  // height; the band below it is what the capture should show.
  final top = tester.getRect(from.first).top;
  final band = tester.getRect(to.last).bottom - top;
  final height = (top + band + pad).ceilToDouble().clamp(200.0, max);

  await tester.binding.setSurfaceSize(Size(width, height));
  await tester.pumpAndSettle();
  // Shrinking the viewport moves the scroll offset; realign before capturing.
  await alignTop();
  await _shoot(tester, name);
}

/// Capture the dialog that is currently open, framed by a thin band of the
/// screen behind it. The window is sized to the dialog rather than the other
/// way round: on a 1440 px canvas a dialog is a small box in a field of scrim.
/// The previous size is restored afterwards, so one test can capture several
/// dialogs in turn and still reach the controls that open them.
Future<void> _shootDialog(
  WidgetTester tester,
  String name, {
  double margin = 56,
}) async {
  final width = _textDialogs.contains(name) ? _textDialogWidth : _dialogWidth;
  final before = tester.view.physicalSize / tester.view.devicePixelRatio;
  // Measure from a modest window, as [_shootFitted] probes from a short one:
  // several of these dialogs size themselves to the space available, so on a
  // 3000 px canvas they report being 3000 px tall.
  await tester.binding.setSurfaceSize(Size(width, 900));
  await tester.pumpAndSettle();
  // The `Dialog` render box is the whole overlay, including the `Align` that
  // centres the surface, so measuring it returns the window size and the frame
  // grows by one margin per pass. The `Material` inside it is the card.
  final surface = find
      .descendant(of: find.byType(Dialog).last, matching: find.byType(Material))
      .first;
  // Two passes: resizing lets the dialog re-lay out, and the second
  // measurement is of the size it will actually be captured at.
  for (var pass = 0; pass < 2; pass++) {
    final rect = tester.getRect(surface);
    await tester.binding.setSurfaceSize(
      Size(
        (rect.width + margin * 2).ceilToDouble().clamp(320.0, _wide),
        (rect.height + margin * 2).ceilToDouble().clamp(240.0, _maxHeight),
      ),
    );
    await tester.pumpAndSettle();
  }
  await _shoot(tester, name);
  await tester.binding.setSurfaceSize(before);
  await tester.pumpAndSettle();
}

/// Contracts loaded from the committed schema, so the wizard renders with real
/// electrode models and limits instead of empty dropdowns.
Future<(ElectrodeCatalog, StimLimits, ScalePresets)> _contracts() async => (
  ElectrodeCatalog.fromJson(
    json.decode(File('schema/electrode_models.json').readAsStringSync())
        as Map<String, dynamic>,
  ),
  StimLimits.fromJson(
    json.decode(File('schema/limits.json').readAsStringSync())
        as Map<String, dynamic>,
  ),
  ScalePresets.fromJson(
    json.decode(File('schema/scale_presets.json').readAsStringSync())
        as Map<String, dynamic>,
  ),
);

/// The committed example, so the charts and tables have real content.
SessionAuthoring _seededAuthoring() =>
    SessionAuthoring()..loadExisting(File(_fixture).readAsStringSync());

/// Press New and keep a loose file, as a clinician would. The file is
/// written to a scratch folder, outside the fake clock that cannot finish it.
Future<void> _startNew(WidgetTester tester) async {
  await _tapText(tester, 'New');
  await tester.tap(find.text('Loose TSV'));
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// Choose the example's pathology in Setup, which loads its scales.
Future<void> _choosePathology(WidgetTester tester) async {
  await _tapFinder(
    tester,
    find.widgetWithText(DropdownMenu<String>, 'DBS indication'),
  );
  await tester.tap(find.text(_preset).last);
  await tester.pumpAndSettle();
}

/// Tap `Next` in the wizard's bottom bar.
Future<void> _next(WidgetTester tester) async => _tapText(tester, 'Next');

/// Scroll [finder] into view, let the scroll settle, then tap it. The settle
/// matters: `ensureVisible` starts an animation, and tapping before it ends
/// uses the pre-scroll position, reported as a tap outside the render tree.
Future<void> _tapFinder(WidgetTester tester, Finder finder) async {
  final target = finder.first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) =>
    _tapFinder(tester, find.text(text));

Future<void> _tapTooltip(WidgetTester tester, String tooltip) =>
    _tapFinder(tester, find.byTooltip(tooltip));

/// Fill a labelled text field, addressed by the label the user sees. Does
/// nothing when absent, so one helper serves steps without every field.
Future<void> _type(
  WidgetTester tester,
  String label,
  String text, {
  int at = 0,
}) async {
  final field = find.widgetWithText(TextField, label);
  if (field.evaluate().length <= at) return;
  await tester.ensureVisible(field.at(at));
  await tester.enterText(field.at(at), text);
  await tester.pumpAndSettle();
}

/// Pick a stimulation program, so the card reads a group rather than its
/// "Select program" hint. Addressed through the hint text, because the
/// electrode-model dropdown is built above this one and would be found first.
/// The dropdown renders its selected value and its menu items both as `Text`,
/// so the menu item is the last match, not the first.
Future<void> _selectProgram(WidgetTester tester, {String program = 'B'}) async {
  final dropdown = find.ancestor(
    of: find.text('Select program'),
    matching: find.byType(DropdownButton<String>),
  );
  if (dropdown.evaluate().isEmpty) return;
  await _tapFinder(tester, dropdown);
  final item = find.text(program);
  if (item.evaluate().isEmpty) {
    await tester.tapAt(const Offset(4, 4)); // dismiss
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(item.last);
  await tester.pumpAndSettle();
}

/// Step 0: a patient and a run, so the BIDS filename the app composes is real.
Future<void> _seedFileStep(WidgetTester tester) async {
  await _type(tester, 'Patient ID', _subjectId);
  await _type(tester, 'Run', _runId);
}

/// Tap a shape on the [index]th lead. The layout comes from the same pure
/// `computeLayout` the widget uses, so tap targets are exact rather than
/// guessed. One tap leaves a contact anodic, two cathodic.
Future<void> _tapElectrode(
  WidgetTester tester,
  ElectrodeModel model, {
  required int index,
  required Offset Function(ElectrodeLayout) target,
  int taps = 1,
}) async {
  final view = find.byType(ElectrodeView).at(index);
  if (view.evaluate().isEmpty) return;
  await tester.ensureVisible(view);
  final origin = tester.getTopLeft(view);
  final layout = computeLayout(model, tester.getSize(view));
  for (var i = 0; i < taps; i++) {
    await tester.tapAt(origin + target(layout));
    await tester.pumpAndSettle();
  }
}

Offset _contact(ElectrodeLayout layout, int level, int segment) => layout.levels
    .firstWhere((l) => l.levelIdx == level)
    .contactRects[ContactKey(level, segment)]!
    .center;

/// A full baseline configuration, with current steered across two segments of
/// one level: the case the documentation spends most of its words on, and the
/// one that makes the amplitude-split rows appear (hidden below two cathodes).
/// With [invalid] the case is left off, so the left lead has cathodes and no
/// return path: applied anyway, like the desktop, and reported invalid.
Future<void> _seedConfiguration(
  WidgetTester tester,
  ElectrodeModel model, {
  bool invalid = false,
}) async {
  await _selectProgram(tester);
  await _tapElectrode(
    tester,
    model,
    index: 0,
    taps: 2,
    target: (l) => _contact(l, 2, 1),
  );
  await _tapElectrode(
    tester,
    model,
    index: 0,
    taps: 2,
    target: (l) => _contact(l, 2, 2),
  );
  if (!invalid) {
    await _tapElectrode(
      tester,
      model,
      index: 0,
      target: (l) => l.caseRect.center,
    );
  }

  // Right lead: a plain ring cathode against the case.
  await _tapElectrode(
    tester,
    model,
    index: 1,
    taps: 2,
    target: (l) => _contact(l, 3, 0),
  );
  await _tapElectrode(
    tester,
    model,
    index: 1,
    target: (l) => l.caseRect.center,
  );

  for (var side = 0; side < 2; side++) {
    await _type(tester, 'Frequency', _frequency, at: side);
    await _type(tester, 'Amplitude', _amplitude, at: side);
    await _type(tester, 'Pulse width', _pulseWidth, at: side);
  }
}

/// Rate every session scale, leaving the last omitted so the "not assessed"
/// state is documented beside the normal one.
Future<void> _seedRatings(WidgetTester tester) async {
  final sliders = find.byType(ScaleSlider);
  final count = sliders.evaluate().length;
  for (var i = 0; i < count; i++) {
    if (i == count - 1) {
      final omit = find.descendant(
        of: sliders.at(i),
        matching: find.byTooltip('Omit (not assessed)'),
      );
      if (omit.evaluate().isEmpty) continue;
      await tester.ensureVisible(omit);
      await tester.tap(omit);
      await tester.pumpAndSettle();
      continue;
    }
    // Tapping the bar sets the value from the x fraction, as a clinician does.
    final bar = find.descendant(
      of: sliders.at(i),
      matching: find.byType(CustomPaint),
    );
    if (bar.evaluate().isEmpty) continue;
    await tester.ensureVisible(sliders.at(i));
    final rect = tester.getRect(bar.first);
    await tester.tapAt(
      Offset(
        rect.left + rect.width * _ratings[i % _ratings.length],
        rect.center.dy,
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (_outDir == null) {
    test(
      'docs screenshots',
      () {},
      skip: 'set DOCS_SCREENSHOT_DIR to generate',
    );
    return;
  }

  setUpAll(() async {
    final support = Directory.systemTemp.createTempSync('docs_support');
    debugSaveDir = Directory.systemTemp.createTempSync('docs_save');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => support.path,
        );
    await _loadFonts();
    _textFont = await _loadTextFont();
    // CustomPainters never see the theme, so electrode labels, slider values
    // and chart ticks need the font set separately or they render as boxes.
    debugPainterFontFamily = _textFont;
    if (_textFont == null) {
      // Failing beats emitting thirty files of black rectangles.
      fail(
        'No text font available, so every glyph would render as a filled '
        'box. Restore assets/fonts/IBMPlexSans-{Regular,Bold}.ttf or run on '
        'a host with system fonts.',
      );
    }
  });

  // ---- Home -------------------------------------------------------------

  testWidgets('home', (tester) async {
    await _pump(tester, const HomeScreen());
    await _shootFitted(tester, 'home', width: _narrow, fallback: 620);
  });

  testWidgets('home (dark)', (tester) async {
    await _pump(tester, const HomeScreen(), brightness: Brightness.dark);
    await _shootFitted(tester, 'home_dark', width: _narrow, fallback: 620);
  });

  testWidgets('home (large text)', (tester) async {
    // The in-app text-size control goes to 1.6; the docs point here when they
    // say the app stays legible scaled up on a tablet.
    await _pump(tester, const HomeScreen(), textScale: 1.4);
    await _shootFitted(
      tester,
      'home_large_text',
      width: _narrow,
      fallback: 800,
    );
  });

  // ---- Complete workflow ------------------------------------------------

  testWidgets('session: file step', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: _seededAuthoring(),
      ),
    );
    await _seedFileStep(tester);
    await _shootFitted(tester, 'session_step0_file');
  });

  testWidgets('session: initial configuration', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: SessionAuthoring(),
      ),
    );
    await _seedFileStep(tester);
    await _choosePathology(tester);
    await _next(tester);
    await _seedConfiguration(tester, catalog.models[_defaultModel]!);
    await _type(tester, 'Notes', _initialNotes);
    await _shootFitted(tester, 'session_step1_config');
  });

  testWidgets('session: initial configuration (narrow)', (tester) async {
    // Below the 900 px breakpoint the two rows stack into one column, which
    // is the layout a phone or a tablet in portrait actually gets.
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: SessionAuthoring(),
      ),
      size: const Size(_narrow, _maxHeight),
    );
    await _seedFileStep(tester);
    await _choosePathology(tester);
    await _next(tester);
    await _shootFitted(
      tester,
      'session_step1_narrow',
      width: _narrow,
      max: 4400,
    );
  });

  testWidgets('session: electrodes, valid and invalid', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    final model = catalog.models[_defaultModel]!;
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: SessionAuthoring(),
      ),
    );
    await _next(tester);

    await _seedConfiguration(tester, model, invalid: true);
    await _shootRegion(
      tester,
      'session_electrodes_invalid',
      from: find.text('Electrodes'),
      to: find.text('Cathodic (-)'),
    );

    // Completing the circuit with the case turns the pane green.
    await _tapElectrode(
      tester,
      model,
      index: 0,
      target: (l) => l.caseRect.center,
    );
    await _shootRegion(
      tester,
      'session_electrodes',
      from: find.text('Electrodes'),
      to: find.text('Cathodic (-)'),
    );
  });

  testWidgets('session: recording and charts', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: _seededAuthoring(),
      ),
    );
    await _seedFileStep(tester);
    await _next(tester);
    await _seedConfiguration(tester, catalog.models[_defaultModel]!);
    await _next(tester);

    await _seedRatings(tester);
    await _type(tester, 'Notes', _recordingNotes);

    // The step is ~4800 px tall, so it is documented in two parts.
    await _shootRegion(
      tester,
      'session_step3_recording',
      from: find.text('Program'),
      to: find.text('Save configuration'),
    );
    await _tapText(tester, 'Comparison charts');
    await _shootRegion(
      tester,
      'session_step3_charts',
      from: find.textContaining('Inserted entries'),
      to: find.byType(EntryChartsView),
    );
  });

  testWidgets('session: recording (dark)', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: _seededAuthoring(),
      ),
      brightness: Brightness.dark,
    );
    await _next(tester);
    await _seedConfiguration(tester, catalog.models[_defaultModel]!);
    await _next(tester);
    await _seedRatings(tester);
    await _shootRegion(
      tester,
      'session_step3_recording_dark',
      from: find.text('Program'),
      to: find.text('Save configuration'),
    );
  });

  // ---- Menus ------------------------------------------------------------

  testWidgets('session: finish', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: _seededAuthoring(),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await _next(tester);
    }
    await _tapText(tester, 'Confirm');
    await _shootFitted(tester, 'session_finish');
  });

  // ---- Dialogs ----------------------------------------------------------

  testWidgets('dialogs: programs, parameter presets, clinical scales', (
    tester,
  ) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: SessionAuthoring(),
      ),
    );
    await _choosePathology(tester);
    await _next(tester);

    for (final entry in const [
      ('Edit programs', 'dialog_programs'),
      ('Edit parameter presets', 'dialog_parameter_presets'),
      ('Settings clinical scales', 'dialog_clinical_scales'),
    ]) {
      await _tapTooltip(tester, entry.$1);
      await _shootDialog(tester, entry.$2);
      await _tapText(tester, 'Cancel');
    }
  });

  testWidgets('dialogs: session scales settings', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: SessionAuthoring(),
      ),
    );
    await _choosePathology(tester);
    await _next(tester);
    await _next(tester);
    await _tapTooltip(tester, 'Settings session scales');
    // Unlike the clinical variant, each row here carries a Min and a Max,
    // which is why both dialogs are documented rather than one.
    await _shootDialog(tester, 'dialog_session_scales');
  });

  testWidgets('dialogs: scale targets and report sections', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: _seededAuthoring(),
      ),
    );
    await _next(tester);
    await _next(tester);

    await _tapText(tester, 'Scale targets');
    await _shootDialog(tester, 'dialog_scale_targets');
    await _tapText(tester, 'Cancel');

    // Reached through Export in the app, which needs share and file-picker
    // channels a widget test cannot answer; the dialog is a plain function.
    unawaited(
      showReportSectionsDialog(
        tester.element(find.byType(SessionScreen)),
        kAllReportSections,
      ),
    );
    await tester.pumpAndSettle();
    await _shootDialog(tester, 'dialog_report_sections');
  });

  testWidgets('dialogs: saving, recovery and datasets', (tester) async {
    final (catalog, limits, presets) = await _contracts();
    await _pump(
      tester,
      SessionScreen(
        catalog: catalog,
        limits: limits,
        scalePresets: presets,
        authoring: SessionAuthoring(),
      ),
    );
    await _seedFileStep(tester);
    await _tapText(tester, 'New session');
    await _shootDialog(tester, 'dialog_save_location');
    await _tapText(tester, 'Cancel');

    const root = 'C:/Studies/OCD-DBS';
    const name = BidsName(
      subject: '01',
      session: '20260203',
      task: 'programming',
      run: '01',
    );
    const visit =
        'sub-01/ses-20260203/beh/'
        'sub-01_ses-20260203_task-programming_run-01_beh';
    final shots = <(String, Future<Object?> Function(BuildContext), String)>[
      (
        'dialog_record_into',
        (c) => confirmRecordInto(c, root, name, what: 'this visit'),
        'Cancel',
      ),
      (
        'dialog_bids_start',
        (c) => checkDatasetFolder(c, 'C:/Studies/new-study', const []),
        'Cancel',
      ),
      (
        'dialog_bids_not_dataset',
        (c) => checkDatasetFolder(c, 'C:/Users/clinic/Documents', const [
          (path: 'notes.txt', content: ''),
        ]),
        'Choose another folder',
      ),
      (
        'dialog_add_to_dataset',
        (c) => confirmMerge(c, (
          write: const [(path: '$visit.tsv', content: '')],
          added: const ['$visit.tsv', '$visit.json'],
          rowMerged: const [
            'participants.tsv',
            'sub-01/ses-20260203/sub-01_ses-20260203_scans.tsv',
          ],
          keptAsIs: const ['dataset_description.json', 'README'],
          refused: const [],
        ), root),
        'Cancel',
      ),
      ('dialog_keep_recovery', askKeepRecoveryCopy, 'Cancel'),
      (
        'dialog_reopen_unfinished',
        (c) => askReopenUnfinished(
          c,
          title: 'Unfinished session found',
          message:
              'sub-01_ses-20260203_task-programming_run-01_beh.tsv was left '
              'open with 7 blocks recorded. They were saved as you went, and '
              'can be reopened here.',
        ),
        'Reopen',
      ),
      (
        'dialog_longitudinal_sections',
        (c) => showLongitudinalSectionsDialog(c, kDefaultLongitudinalSections),
        'Cancel',
      ),
    ];
    for (final (file, open, close) in shots) {
      unawaited(open(tester.element(find.byType(SessionScreen))));
      await tester.pumpAndSettle();
      await _shootDialog(tester, file);
      await _tapText(tester, close);
    }
  });

  testWidgets('dialogs: help / about', (tester) async {
    await _pump(tester, const HomeScreen(), size: const Size(_narrow, 1200));
    await _tapTooltip(tester, 'Help / about');
    await _shootDialog(tester, 'dialog_about');
  });

  // ---- Annotations ------------------------------------------------------

  testWidgets('annotations: file step', (tester) async {
    await _pump(tester, const AnnotationsScreen());
    await _seedFileStep(tester);
    await _shootFitted(tester, 'annotations_file');
  });

  testWidgets('annotations: notes step', (tester) async {
    await _pump(tester, const AnnotationsScreen());
    await _seedFileStep(tester);
    await _startNew(tester);
    for (final note in const [
      'Session started; patient alert and oriented.',
      'Reports the paraesthesia has settled since the last change.',
      'Discussed raising the left amplitude at the next visit.',
    ]) {
      await _type(tester, 'Note', note);
      await _tapText(tester, 'Insert timestamped note');
    }
    await _shootFitted(tester, 'annotations_notes');
  });

  // ---- Reports and datasets ---------------------------------------------

  testWidgets('reports: nothing uploaded', (tester) async {
    final contracts = await _contracts();
    await _pump(
      tester,
      ReportsScreen(catalog: contracts.$1),
      size: const Size(_narrow, 1000),
    );
    await _shootFitted(tester, 'reports_empty', width: _narrow, height: 620);
  });

  testWidgets('reports: load from dataset', (tester) async {
    String beh(String sub, String ses) =>
        'sub-$sub/ses-$ses/beh/'
        'sub-${sub}_ses-${ses}_task-programming_run-01_beh.tsv';
    debugDataset = (
      root: 'C:/Studies/OCD-DBS',
      files: [
        for (final (sub, ses) in const [
          ('01', '20260203'),
          ('01', '20260401'),
          ('02', '20260210'),
          ('03', '20260215'),
        ])
          (path: beh(sub, ses), content: 'x'),
      ],
    );
    addTearDown(() => debugDataset = null);
    await _pump(tester, ReportsScreen(catalog: (await _contracts()).$1));
    await _tapText(tester, 'Load from dataset');
    await _shootDialog(tester, 'dialog_load_participants');
  });

  testWidgets('reports: one session', (tester) async {
    final contracts = await _contracts();
    await _pump(
      tester,
      ReportsScreen(
        catalog: contracts.$1,
        initialFiles: exampleVisits(count: 1),
      ),
    );
    await _shootFitted(tester, 'reports_one_session', height: 900);
  });

  testWidgets('reports: several visits', (tester) async {
    await _pump(tester, ReportsScreen(initialFiles: exampleVisits()));
    await _shootFitted(tester, 'reports_visits', height: 900);
  });

  testWidgets('reports: patient mismatch', (tester) async {
    // Combining two people into one longitudinal report is a safety problem,
    // not a formatting one, so the banner and the disabled action are worth
    // documenting on their own.
    await _pump(
      tester,
      ReportsScreen(initialFiles: exampleVisits(mismatchedPatients: true)),
    );
    await _shootFitted(tester, 'reports_mismatch', height: 900);
  });

  // ---- Reports ----------------------------------------------------------
  //
  // The PDFs are written to build/docs_reports/ and rasterised into
  // docs/_static/reports/ by tool/report_screenshots.py, which also crops each
  // section by its heading. Dart has no PDF rasteriser; PyMuPDF does.

  testWidgets('reports: session and longitudinal PDFs', (tester) async {
    final out = Directory('build/docs_reports')..createSync(recursive: true);
    final catalog = (await _contracts()).$1;
    final visits = exampleVisits();
    final prefs = defaultScalePrefsFor([
      for (final v in visits) ...v.rows.where((r) => r.isInitial.trim() != '1'),
    ]);

    final session = buildSessionReportData(
      rows: visits.first.rows,
      scalePrefs: prefs,
      sourceFile: visits.first.name,
    );
    final gfx = await tester.runAsync(
      () => renderReportGraphics(
        session,
        catalog.models[electrodeModelIn(visits.first.rows)],
        kAllReportSections,
      ),
    );
    final sessionPdf = await tester.runAsync(
      () => buildSessionPdf(
        data: session,
        subjectId: _subjectId,
        electrodeImages: gfx!.electrodes,
        chartPng: gfx.chart,
      ),
    );
    File('${out.path}/session_report.pdf').writeAsBytesSync(sessionPdf!.bytes);

    final longitudinal = buildLongitudinalReportData(
      files: {for (final v in visits) v.name: v.rows},
      scalePrefs: prefs,
    );
    final longitudinalPdf = await tester.runAsync(() async {
      return buildLongitudinalPdf(
        data: longitudinal,
        clinicalChartPng: await renderScalesChartPng(
          longitudinal.clinicalChart,
        ),
        sessionChartPng: await renderScalesChartPng(longitudinal.sessionChart),
      );
    });
    File(
      '${out.path}/longitudinal_report.pdf',
    ).writeAsBytesSync(longitudinalPdf!.bytes);

    final notes = buildAnnotationsReportData(
      entries: const [
        Annotation(
          acqTime: '2026-02-03T09:02:10+00:00',
          notes: 'Arrived calm; reports checking behaviour most evenings.',
        ),
        Annotation(
          acqTime: '2026-02-03T09:07:45+00:00',
          notes: 'Brief warmth on the right after the amplitude change.',
        ),
        Annotation(
          acqTime: '2026-02-03T09:13:30+00:00',
          notes: 'Leaves on the last configuration; review in six weeks.',
        ),
      ],
      subjectId: _subjectId,
      sourceFile: 'sub-01_ses-20260203_task-notes_run-01_beh.tsv',
    );
    final notesPdf = await tester.runAsync(() => buildAnnotationsPdf(notes));
    File(
      '${out.path}/annotations_report.pdf',
    ).writeAsBytesSync(notesPdf!.bytes);
  });
}
