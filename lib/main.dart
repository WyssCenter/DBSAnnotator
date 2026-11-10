import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app_info.dart' show appName;
import 'core/prefs/user_prefs.dart';
import 'ui/close_guard.dart';
import 'ui/session_screen.dart';
import 'ui/theme.dart';

/// Preferred desktop window size, used only when the display can spare it.
const Size _preferredWindowSize = Size(1500, 950);

/// Smallest window the layout still works in. Keep it modest: a minimum
/// larger than the display stops the window from ever fitting, which is how
/// the title bar ends up off-screen and unreachable.
const Size _minWindowSize = Size(640, 520);

/// Gap left around the window so the frame stays grabbable.
const double _screenMargin = 24.0;

/// The window rect that fits centred inside a display's work area: never
/// larger than that area, top-left always inside it so the title bar stays
/// reachable. [work] and [workOrigin] are LOGICAL pixels, as
/// `screen_retriever` reports and `windowManager.setBounds` expects.
Rect fitWindowRect({
  required Size work,
  Offset workOrigin = Offset.zero,
  Size preferred = _preferredWindowSize,
  double margin = _screenMargin,
}) {
  // Shrink the margin on a tiny display rather than letting it dominate.
  final m = math.min(margin, math.min(work.width, work.height) / 10);
  final width = math.min(preferred.width, math.max(1.0, work.width - m * 2));
  final height = math.min(preferred.height, math.max(1.0, work.height - m * 2));
  return Rect.fromLTWH(
    workOrigin.dx + (work.width - width) / 2,
    workOrigin.dy + (work.height - height) / 2,
    width,
    height,
  );
}

/// The minimum window size, clamped to what actually fits in [window]; a
/// minimum bigger than the screen makes the window impossible to shrink.
Size fitMinimumSize(Size window, {Size minimum = _minWindowSize}) => Size(
  math.min(minimum.width, window.width),
  math.min(minimum.height, window.height),
);

/// Size and position the window inside the current display's work area (the
/// screen minus the taskbar/dock/menu bar). Sets explicit bounds instead of
/// `WindowOptions.size` with `center: true`, which on small screens left the
/// window oversized and both the title bar and the taskbar off-screen.
Future<void> _fitWindowToWorkArea() async {
  Size work = const Size(1280, 800);
  Offset workOrigin = Offset.zero;
  try {
    final display = await screenRetriever.getPrimaryDisplay();
    // visibleSize excludes the taskbar/dock; size is the whole monitor.
    work = display.visibleSize ?? display.size;
    workOrigin = display.visiblePosition ?? Offset.zero;
  } catch (e) {
    // Better a conservative window than a giant one we cannot reach.
    debugPrint('Could not read display bounds, using a safe default: $e');
  }

  final bounds = fitWindowRect(work: work, workOrigin: workOrigin);
  await windowManager.setMinimumSize(fitMinimumSize(bounds.size));
  await windowManager.setBounds(bounds);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await loadUserPrefs();
  themeMode.value = prefs.darkTheme == true ? ThemeMode.dark : ThemeMode.light;
  textScale.value = prefs.textScale ?? 1.0;
  // Mobile platforms own the window; only desktop needs explicit sizing.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: appName,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setTitle(appName);
      await _fitWindowToWorkArea();
      await windowManager.show();
      await windowManager.focus();
      // Again after the window is mapped: some window managers override the
      // pre-show bounds with the native runner's default size.
      await _fitWindowToWorkArea();
    });
    // Closing the window with a session open asks about its recovery copy.
    await windowManager.setPreventClose(true);
    windowManager.addListener(_CloseListener());
  }
  runApp(const DbsAnnotatorApp());
}

class _CloseListener extends WindowListener {
  @override
  Future<void> onWindowClose() async {
    final guard = activeSessionGuard;
    if (guard != null && !await guard(closingWindow: true)) return;
    // Not destroy(): on Windows that only quits the message loop, leaving the
    // window on screen, apparently frozen, while the engine shuts down.
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}

class DbsAnnotatorApp extends StatelessWidget {
  const DbsAnnotatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => ValueListenableBuilder<double>(
        valueListenable: textScale,
        builder: (context, scale, _) => MaterialApp(
          title: appName,
          debugShowCheckedModeBanner: false,
          theme: dbsTheme(Brightness.light),
          darkTheme: dbsTheme(Brightness.dark),
          themeMode: mode,
          // Wraps the Navigator, so dialogs and all routes scale too.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const SessionScreen(),
        ),
      ),
    );
  }
}
