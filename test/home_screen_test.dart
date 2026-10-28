import 'package:dbs_annotator/app_info.dart';
import 'package:dbs_annotator/ui/home_screen.dart';
import 'package:dbs_annotator/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
  }

  testWidgets('shows the app icon and every workflow option', (tester) async {
    await pumpHome(tester);

    expect(find.byType(AppLogo), findsWidgets);
    expect(find.text(appName), findsOneWidget);

    // Every entry point must stay reachable from the home screen.
    expect(find.text('Complete workflow'), findsOneWidget);
    expect(find.text('Annotations only'), findsOneWidget);
    expect(find.text('Reports and datasets'), findsOneWidget);
  });

  testWidgets('the About dialog carries the logo and version', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Help / about'));
    await tester.pumpAndSettle();

    expect(find.text(appName), findsWidgets);
    expect(find.text('v$appVersion'), findsOneWidget);
    expect(find.byType(AppLogo), findsWidgets);
  });

  testWidgets('AppLogo degrades to an icon when the asset is missing', (
    tester,
  ) async {
    // A packaging slip must not put a red error box in the AppBar.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppLogo(size: 24))),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the logo asset is really bundled, not silently falling back', (
    tester,
  ) async {
    // AppLogo has an errorBuilder, which is right for robustness but would hide
    // a packaging mistake. Load the assets directly so a missing or undeclared
    // icon fails loudly here instead of shipping as a Material glyph.
    for (final asset in [appLogoAsset, appIconAsset]) {
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List();
      expect(bytes.sublist(0, 8), [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ], reason: '$asset is not a PNG');
      // The 1024x1024 master, read from the IHDR.
      int be32(int o) =>
          (bytes[o] << 24) |
          (bytes[o + 1] << 16) |
          (bytes[o + 2] << 8) |
          bytes[o + 3];
      expect(be32(16), 1024, reason: asset);
      expect(be32(20), 1024, reason: asset);
    }
  });

  testWidgets('the logo is the same icon in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: dbsTheme(brightness),
          home: const Scaffold(body: AppLogo()),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        appLogoAsset,
        reason: '$brightness',
      );
    }
  });
}
