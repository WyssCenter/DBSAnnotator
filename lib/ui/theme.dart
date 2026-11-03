import 'package:flutter/material.dart';

import '../core/brand_palette.dart';

/// The Wyss Center brand palette.
///
/// [green] is a FILL, never text or an outline. Measured against white it is
/// 1.64:1, which fails even the 3:1 bar for a UI component, so every label and
/// icon is [black] or [greyDark] and the green sits behind them, where black
/// reads at 12.8:1. The same rule retires the amber this replaced, which was
/// 2.15:1 and was being used for text.
class DbsColors {
  // Primary palette.
  static const greenLighter = Color(kGreenLighter);
  static const green = Color(kGreen);
  static const pink = Color(kPink);
  static const black = Color(kBlack);
  static const greyLighter = Color(kGreyLighter);

  // Secondary palette.
  static const yellowLime = Color(kYellowLime);
  static const pinkLight = Color(kPinkLight);
  static const blueLight = Color(kBlueLight);
  static const redLight = Color(kRedLight);
  static const greyDark = Color(kGreyDark);
  static const greyMid = Color(kGreyMid);
  static const grey = Color(kGrey);
  static const greyLight = Color(kGreyLight);

  /// What a filled, selected or active control is painted with. Always carries
  /// a black label.
  static const accent = green;

  // Electrode contact states: base + border.
  //
  // The pastel brand pair replaces a saturated red and blue that were 0.313 and
  // 0.317 in luminance: a separation of 0.004, so on a monochrome printer the
  // anode and the cathode were the same shade. These separate by 0.162, and
  // both are still nameable as red and blue, which the printed key relies on.
  static const offBase = greyMid;
  static const offBorder = greyDark;
  static const anodicBase = redLight;
  static const anodicBorder = Color(0xFFC96A3C);
  static const cathodicBase = blueLight;
  static const cathodicBorder = Color(0xFF2F6FC4);

  // Validation.
  //
  // Deliberately NOT brand colours: both are label text, and the brand has no
  // accessible green or red for text. Brand green would be 1.64:1 here.
  static const valid = Color(0xFF22C55E);
  static const invalid = Color(0xFFCC0000);

  // Session-scale progress fill, per brightness. The value is printed on the
  // bar, so this is decoration.
  static List<Color> scaleFill(bool dark) => dark
      ? const [green, greenLighter, green]
      : const [Color(0xFF0BB37C), green, Color(0xFF0BB37C)];

  /// Fill for the titled group cards: a translucent brand green over the
  /// scaffold, never the Material-3 blue surface tint, which callers suppress
  /// with `surfaceTintColor: Colors.transparent`.
  static Color cardFill(bool dark) =>
      greenLighter.withValues(alpha: dark ? 0.12 : 0.22);

  /// Background of the initial assessment, so it never reads as programming.
  static Color assessmentFill(bool dark) =>
      const Color(0xFF64748B).withValues(alpha: dark ? 0.18 : 0.10);
}

/// Non-state colours for the electrode canvas: the lead's insulating polymer
/// body and its outline.
///
/// Only the inert lead material follows the theme. The contact state colours
/// (off / anodic / cathodic in [DbsColors]) stay brightness-independent
/// because grey / red / blue are clinical semantics, not decoration, and must
/// read the same in both themes and in a printed report, which passes
/// [ElectrodePalette.light] explicitly.
class ElectrodePalette {
  const ElectrodePalette({
    required this.polymer,
    required this.outline,
    required this.label,
  });

  /// Mid-tone of the insulating lead body; the painter derives the whole
  /// cylinder shading from it.
  final Color polymer;

  /// Lead / dome outline.
  final Color outline;

  /// `E{idx}` labels in the gutter beside the lead.
  final Color label;

  static const light = ElectrodePalette(
    polymer: Color(0xFFEFEFEF),
    outline: Color(0xFF8A8A8A),
    label: Color(0xFF0F172A),
  );

  static const dark = ElectrodePalette(
    polymer: Color(0xFF9BA3AF),
    outline: Color(0xFF5A6472),
    label: Color(0xFFF1F5F9),
  );

  static ElectrodePalette of(Brightness b) =>
      b == Brightness.dark ? dark : light;
}

/// App-wide light/dark selection, defaulting to light. Not persisted, which
/// matches the desktop app.
final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);

/// AppBar action that flips light/dark, showing the icon of the theme it
/// switches to.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
      iconSize: 28,
      tooltip: 'Switch light/dark',
      onPressed: () =>
          themeMode.value = dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}

/// App-wide text-scale factor, applied in [main] via MediaQuery's textScaler.
/// Session-only, like [themeMode].
final ValueNotifier<double> textScale = ValueNotifier(1.0);

const double _kMinTextScale = 0.8;
const double _kMaxTextScale = 1.6;
const double _kTextScaleStep = 0.1;

/// Connected +/- pair that changes the app text size at runtime.
class TextSizeButtons extends StatelessWidget {
  const TextSizeButtons({super.key});

  void _bump(double delta) {
    final next = (textScale.value + delta).clamp(
      _kMinTextScale,
      _kMaxTextScale,
    );
    // Round to the step grid so repeated taps do not accumulate float noise.
    textScale.value = (next * 10).roundToDouble() / 10;
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    Widget btn(IconData icon, String tip, VoidCallback onTap) =>
        IconButton(icon: Icon(icon, size: 26), tooltip: tip, onPressed: onTap);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: divider),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(
              Icons.text_decrease,
              'Smaller text',
              () => _bump(-_kTextScaleStep),
            ),
            SizedBox(
              height: 28,
              child: VerticalDivider(width: 1, color: divider),
            ),
            btn(
              Icons.text_increase,
              'Larger text',
              () => _bump(_kTextScaleStep),
            ),
          ],
        ),
      ),
    );
  }
}

/// App theme in the brand palette: green fills, black text.
///
/// `onPrimary` is black rather than Material's computed white, because white on
/// the brand green is 1.4:1 and black is 12.8:1.
ThemeData dbsTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: DbsColors.green,
    brightness: brightness,
    primary: DbsColors.green,
    onPrimary: DbsColors.black,
    secondary: DbsColors.pink,
    surface: dark ? DbsColors.black : DbsColors.greyLighter,
    onSurface: dark ? DbsColors.greyLighter : DbsColors.black,
    outlineVariant: dark ? DbsColors.greyDark : DbsColors.grey,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    // Material paints a text button's label in `primary`, which here would put
    // 1.64:1 green text on the dialog actions. Filled buttons are unaffected:
    // they get the green as a background with `onPrimary` black on it.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
    ),
    // A dialog sizes to its widest line, and a long title is one line: capped,
    // the title wraps instead of stretching the dialog across a wide window.
    dialogTheme: const DialogThemeData(
      constraints: BoxConstraints(minWidth: 280, maxWidth: 600),
    ),
  );
}

/// A titled card, matching the desktop `QGroupBox`.
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;

  /// Shown at the end of the title row, such as a settings button.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      // A transparent surfaceTintColor (below) keeps Material 3 from tinting
      // the brand green blue.
      color: DbsColors.cardFill(
        Theme.of(context).brightness == Brightness.dark,
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              // The card's green wash carries the brand; the title carries the
              // text, so it takes the scheme's ink rather than the green, which
              // would be 1.64:1 here.
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
