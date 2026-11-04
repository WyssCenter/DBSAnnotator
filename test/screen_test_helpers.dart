/// Shared by the widget tests that drive the session and notes screens against
/// real files.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/ui/annotations_screen.dart';
import 'package:dbs_annotator/ui/bids_merge_ui.dart';
import 'package:dbs_annotator/ui/close_guard.dart';
import 'package:dbs_annotator/ui/save_target.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settleUntil(
  WidgetTester tester,
  Directory working,
  bool Function() done, {
  Duration cap = const Duration(seconds: 10),
  Duration step = Duration.zero,
}) async {
  bool finished() {
    try {
      return done();
    } catch (_) {
      return false;
    }
  }

  bool idle() {
    try {
      return !working
          .listSync(recursive: true)
          .any((e) => e.path.endsWith('.tmp'));
    } catch (_) {
      return false;
    }
  }

  final end = DateTime.now().add(cap);
  while (!(finished() && idle())) {
    if (!DateTime.now().isBefore(end)) fail('timed out waiting for $done');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(step);
  }
  for (var round = 0; round < 2; round++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

/// Waits for the queued dataset writes to finish and fails when they never do,
/// so a test that leaves work queued ends only once that work has drained.
Future<void> drainDatasetQueue(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!datasetQueueIdle) {
    if (!DateTime.now().isBefore(end)) fail('the dataset queue never emptied');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// [drainDatasetQueue] for a test outside the fake-async zone.
Future<void> expectDatasetQueueIdle() async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!datasetQueueIdle) {
    if (!DateTime.now().isBefore(end)) fail('the dataset queue never emptied');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (finder.evaluate().isEmpty) {
    if (!DateTime.now().isBefore(end)) fail('timed out waiting for $finder');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpUntilGone(WidgetTester tester, Finder finder) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (finder.evaluate().isNotEmpty) {
    if (!DateTime.now().isBefore(end)) fail('timed out waiting for no $finder');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void removeQuietly(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // Windows may still hold a folder open.
  }
}

Future<void> openNotesStep(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const AnnotationsScreen()),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Notes'));
  await tester.pumpAndSettle();
}

String workingText(Directory root) => root
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => !f.path.endsWith('.tmp'))
    .map((f) => f.readAsStringSync())
    .join();

/// Pushes [screen] on top of a home route, so popping it behaves as it does in
/// the app.
Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => screen),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> jsonAt(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

SessionScreen sessionScreen() => SessionScreen(
  catalog: ElectrodeCatalog.fromJson(jsonAt('schema/electrode_models.json')),
  limits: StimLimits.fromJson(jsonAt('schema/limits.json')),
  scalePresets: ScalePresets.fromJson(jsonAt('schema/scale_presets.json')),
);

/// Lets the screen's start-up look for unfinished work run to its end, which
/// needs the real event loop.
Future<void> awaitRecoveryCheck(WidgetTester tester) async {
  for (var round = 0; round < 5; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

/// A working folder and a save folder standing in for app storage and for the
/// place a Save-As dialog would put files, all removed after the test.
({Directory working, Directory saved}) useTempDirs() {
  final working = Directory.systemTemp.createTempSync('dbs_work');
  final saved = Directory.systemTemp.createTempSync('dbs_saved');
  // A future cached from an earlier test's fake-async zone delivers to that
  // zone, so the listeners of later tests never run.
  rootBundle.evict('schema/tsv_schema.json');
  debugWorkingDir = working;
  debugSaveDir = saved;
  activeSessionGuard = null;
  resetDatasetQueue();
  addTearDown(() {
    debugWorkingDir = null;
    debugSaveDir = null;
    activeSessionGuard = null;
    removeQuietly(working);
    removeQuietly(saved);
  });
  return (working: working, saved: saved);
}

/// Answers the folder and file pickers without a platform dialog.
final class FakePicker extends FilePickerPlatform {
  String? directory;
  PlatformFile? file;
  Object? failure;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => directory;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    if (failure case final error?) throw error;
    return file;
  }
}

FakePicker useFakePicker() {
  final previous = FilePickerPlatform.instance;
  final picker = FakePicker();
  FilePickerPlatform.instance = picker;
  addTearDown(() => FilePickerPlatform.instance = previous);
  return picker;
}

/// Answers the desktop Save-As dialog with a path and, like the real one,
/// writes nothing.
final class FakeFileSelector extends FileSelectorPlatform {
  /// The path the dialog answers with; null cancels.
  String? savePath;
  String? lastSuggestedName;
  List<XTypeGroup>? lastTypeGroups;

  /// Thrown instead of answering, as when no dialog can be shown.
  Object? failure;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    lastSuggestedName = options.suggestedName;
    lastTypeGroups = acceptedTypeGroups;
    if (failure case final error?) throw error;
    final path = savePath;
    return path == null ? null : FileSaveLocation(path);
  }
}

FakeFileSelector useFakeFileSelector() {
  final previous = FileSelectorPlatform.instance;
  final selector = FakeFileSelector();
  FileSelectorPlatform.instance = selector;
  addTearDown(() => FileSelectorPlatform.instance = previous);
  return selector;
}

/// A replace question that fails the test when it is asked.
Future<bool> mustNotAsk(String fileName) async =>
    throw TestFailure('asked to replace $fileName');

/// Stands in for the cache folder an export builds in, so a test can tell when
/// the export has finished.
Directory useExportCache(WidgetTester tester) {
  final cache = Directory.systemTemp.createTempSync('dbs_cache');
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (call) async => cache.path,
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
    removeQuietly(cache);
  });
  return cache;
}

final class _DiskFile extends PlatformFile {
  _DiskFile(this._file);

  final File _file;

  @override
  String get name => _file.uri.pathSegments.last;

  @override
  Uri get uri => _file.uri;

  @override
  XFile get xFile => XFile(_file.path);

  @override
  int? lengthSync() => _file.lengthSync();

  @override
  Future<int> length() => _file.length();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      _file.openRead().map(Uint8List.fromList);
}

PlatformFile pickedFile(File file) => _DiskFile(file);

/// A programming-session TSV with one baseline block, synthetic data.
String sessionTsv({
  String notes = 'planted visit',
  String model = 'Medtronic SenSight B33005',
}) {
  final authoring = SessionAuthoring()
    ..addInsert(
      isInitial: true,
      stim: const {
        'left_stim_freq': '130',
        'left_anode': 'case',
        'left_cathode': 'E1b',
        'left_amplitude': '2.0',
        'left_pulse_width': '60',
      },
      scales: [(name: 'Y-BOCS', value: '12')],
      leftElectrodeModel: model,
      rightElectrodeModel: model,
      notes: notes,
      at: DateTime.utc(2026, 2, 3, 9),
    );
  return authoring.serialize();
}

/// A notes TSV with one note, synthetic data.
String notesTsv({String note = 'planted note'}) => writeAnnotations([
  Annotation(acqTime: '2026-02-03T09:00:00+00:00', notes: note),
]);

/// Writes a recovery copy into the app's working folder under [working].
File plantWork(
  Directory working,
  String name,
  String content, {
  DateTime? modified,
}) {
  final dir = Directory('${working.path}/work')..createSync(recursive: true);
  final file = File('${dir.path}/$name')..writeAsStringSync(content);
  if (modified != null) file.setLastModifiedSync(modified);
  return file;
}

/// Inserts a baseline block whose notes are [text] and waits until the working
/// copy holds it. Works from any step of the session screen.
Future<void> addSessionEntry(
  WidgetTester tester,
  Directory working,
  String text,
) async {
  final insert = find.text('Insert baseline').hitTestable();
  if (insert.evaluate().isEmpty) {
    await tester.tap(find.text('Initial configuration'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.widgetWithText(TextField, 'Notes'), text);
  await tester.ensureVisible(insert);
  await tester.tap(insert);
  await settleUntil(tester, working, () => workingText(working).contains(text));
}
