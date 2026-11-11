import 'package:flutter/material.dart';

import '../core/brand_palette.dart';

/// The Wyss Center brand palette. The screens take their accent from the
/// Material scheme seeded with [green]; the raw colours are for charts and
/// clinical states.
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

  // Electrode contact states: base + border. The ochre anode and the blue
  // cathode differ by 0.15 in luminance, so they stay apart on a monochrome
  // printout, and both are nameable, which the printed key relies on.
  static const offBase = greyMid;
  static const offBorder = greyDark;
  static const anodicBase = Color(0xFFE9C46A);
  static const anodicBorder = Color(0xFF9A6B0A);
  static const cathodicBase = blueLight;
  static const cathodicBorder = Color(0xFF2F6FC4);

  // Validation.
  //
  // Deliberately NOT brand colours: both are label text, and the brand has no
  // accessible green or red for text. Brand green would be 1.64:1 here.
  static const invalid = Color(0xFFCC0000);
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

/// App-wide light/dark selection, restored from the user's preferences.
final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);

/// App-wide text-scale factor, applied in [main] via MediaQuery's textScaler
/// and restored from the user's preferences.
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

/// App theme: Material's tonal scheme seeded with the brand green.
ThemeData dbsTheme(Brightness brightness) {
  const fields = InputDecorationTheme(
    border: OutlineInputBorder(),
    isDense: true,
    floatingLabelBehavior: FloatingLabelBehavior.always,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: DbsColors.green,
      brightness: brightness,
    ),
    inputDecorationTheme: fields,
    dropdownMenuTheme: const DropdownMenuThemeData(
      inputDecorationTheme: fields,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dialogTheme: const DialogThemeData(
      constraints: BoxConstraints(minWidth: 280, maxWidth: 600),
    ),
  );
}

/// A titled group of controls: a heading, an optional action, then [child].
class TitledSection extends StatelessWidget {
  const TitledSection({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?action,
            ],
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
