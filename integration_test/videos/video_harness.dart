import 'dart:io';

import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:dbs_annotator/ui/save_target.dart';
import 'package:dbs_annotator/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

/// Repo root, passed by `tool/record_video.ps1`, for the committed fixtures.
const videoRoot = String.fromEnvironment('VIDEO_ROOT', defaultValue: '.');

/// The folder `tool/record_video.ps1` watches, and the Piper voice it passes.
const _marks = String.fromEnvironment('VIDEO_MARKS');
const _voice = String.fromEnvironment('VIDEO_VOICE');
const _uvx = String.fromEnvironment('VIDEO_UVX', defaultValue: 'uvx');

/// Each line of the script: its spoken WAV, empty without a voice, and how
/// long it takes to say.
final _spoken = <String, ({String wav, int ms})>{};
var _speechEnds = DateTime.now();

/// A fresh, empty folder whose path names no user: under the Windows public
/// profile, else the system temp folder.
Directory videoFolder(String name) {
  final base = Platform.environment['PUBLIC'] ?? Directory.systemTemp.path;
  final dir = Directory('$base${Platform.pathSeparator}$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  return dir..createSync(recursive: true);
}

/// Speak every line of [script] to a WAV file before the recording starts, so
/// the voice never stalls it. Without a voice each line gets its reading time.
Future<void> prepareScript(Iterable<String> script) async {
  final dir = _marks.isEmpty ? Directory.systemTemp.path : _marks;
  for (final (i, line) in script.indexed) {
    if (_voice.isEmpty) {
      _spoken[line] = (wav: '', ms: 800 + 60 * line.length);
      continue;
    }
    final wav = '$dir/say_$i.wav';
    final piper = await Process.start(_uvx, [
      '--from',
      'piper-tts',
      'piper',
      '-m',
      _voice,
      '-f',
      wav,
    ]);
    piper.stdin.writeln(line);
    await piper.stdin.close();
    if (await piper.exitCode != 0) throw StateError('Piper failed on: $line');
    _spoken[line] = (wav: wav, ms: _wavMs(File(wav).readAsBytesSync()));
  }
}

/// The length of a PCM WAV file: its data chunk over its byte rate.
int _wavMs(List<int> bytes) {
  int u32(int at) =>
      bytes[at] |
      bytes[at + 1] << 8 |
      bytes[at + 2] << 16 |
      bytes[at + 3] << 24;
  final byteRate = u32(28);
  for (var at = 12; at + 8 <= bytes.length; at += 8 + u32(at + 4)) {
    if (String.fromCharCodes(bytes.sublist(at, at + 4)) == 'data') {
      return u32(at + 4) * 1000 ~/ byteRate;
    }
  }
  throw StateError('No data chunk in the WAV file');
}

/// Caption and speak [line] of the script, once the previous line has
/// finished, and log when it starts and ends for the recorder.
Future<void> say(WidgetTester tester, String line) async {
  final spoken = _spoken[line];
  if (spoken == null) throw ArgumentError('Not in the script: $line');
  final wait = _speechEnds.difference(DateTime.now()).inMilliseconds;
  if (wait > 0) await pause(tester, wait);
  final start = DateTime.now();
  _speechEnds = start.add(Duration(milliseconds: spoken.ms + 400));
  if (_marks.isNotEmpty) {
    File('$_marks/captions.tsv').writeAsStringSync(
      '${start.millisecondsSinceEpoch}\t'
      '${_speechEnds.millisecondsSinceEpoch}\t${spoken.wav}\t$line\n',
      mode: FileMode.append,
    );
  }
}

final _tap = ValueNotifier<Offset?>(null);

void initVideoBinding() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
}

/// Shows [home] in the real window, with preferences and the working copy
/// in a temp folder so a recording never touches the user's own.
Future<void> startVideo(WidgetTester tester, Widget home) async {
  final tmp = Directory.systemTemp.createTempSync('dbs_video_');
  debugPrefsDir = tmp;
  debugWorkingDir = tmp;
  debugSaveDir = tmp;
  await windowManager.ensureInitialized();
  // Its own title, so ffmpeg never records another open copy of the app.
  await windowManager.setTitle('DBS Annotator video');
  await windowManager.setSize(const Size(1280, 800));
  await windowManager.center();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dbsTheme(Brightness.light),
      builder: (context, child) => Stack(
        children: [
          child!,
          IgnorePointer(
            child: ValueListenableBuilder<Offset?>(
              valueListenable: _tap,
              builder: (_, at, _) =>
                  CustomPaint(size: Size.infinite, painter: _TapPainter(at)),
            ),
          ),
        ],
      ),
      home: home,
    ),
  );
  await pause(tester, 500);
  _mark('ready');
  await pause(tester, 1000);
}

/// Lets the last line finish, tells the recorder to stop, then holds the last
/// frame briefly.
Future<void> endVideo(WidgetTester tester) async {
  final wait = _speechEnds.difference(DateTime.now()).inMilliseconds;
  await pause(tester, wait > 1500 ? wait : 1500);
  _mark('done');
  await pause(tester, 1000);
}

/// Marker files `tool/record_video.ps1` waits on to start and stop ffmpeg.
void _mark(String name) {
  if (_marks.isNotEmpty) File('$_marks/$name').writeAsStringSync('');
}

Future<void> pause(WidgetTester tester, [int ms = 700]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await tester.pumpAndSettle();
}

/// Scrolls [finder] to the middle of the window, so what it changes is in view.
Future<void> center(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder.first),
    alignment: 0.5,
    duration: const Duration(milliseconds: 400),
  );
  await tester.pumpAndSettle();
}

/// Taps [at] with a visible marker; [fast] for runs of taps in one place.
Future<void> tapAt(WidgetTester tester, Offset at, {bool fast = false}) async {
  _tap.value = at;
  await pause(tester, fast ? 100 : 250);
  await tester.tapAt(at);
  await pause(tester, fast ? 100 : 250);
  _tap.value = null;
  await pause(tester, fast ? 150 : 700);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await center(tester, finder);
  await tapAt(tester, tester.getCenter(finder.first));
}

Future<void> tapText(WidgetTester tester, String text) =>
    tap(tester, find.text(text));

/// Types [text] into the [at]th field labelled [label], one key at a time.
Future<void> typeInto(
  WidgetTester tester,
  String label,
  String text, {
  int at = 0,
}) async {
  final field = find.widgetWithText(TextField, label).at(at);
  await tap(tester, field);
  for (var i = 1; i <= text.length; i++) {
    await tester.enterText(field, text.substring(0, i));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
  }
  await pause(tester, 400);
}

class _TapPainter extends CustomPainter {
  const _TapPainter(this.at);
  final Offset? at;

  @override
  void paint(Canvas canvas, Size size) {
    if (at == null) return;
    canvas.drawCircle(at!, 18, Paint()..color = const Color(0x55F59E0B));
    canvas.drawCircle(
      at!,
      18,
      Paint()
        ..color = const Color(0xFFB45309)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TapPainter old) => old.at != at;
}
