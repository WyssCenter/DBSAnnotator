import 'package:flutter/material.dart';

import 'theme.dart';
import 'painter_font.dart';

/// Tablet port of the desktop `ScaleProgressWidget` (ui/widgets.py): a
/// green-gradient progress bar with the value drawn on it at **0.25**
/// granularity, ±0.25 (single-chevron) / ±0.5 (double-chevron) buttons on each
/// side, and an "X" that toggles the scale to *not assessed* (omitted).
///
/// Stateless: the parent owns [value]/[omitted] and updates them from
/// [onChanged] (any move re-includes an omitted scale, like the desktop) and
/// [onOmitToggle].
class ScaleSlider extends StatelessWidget {
  const ScaleSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.omitted,
    required this.onChanged,
    required this.onOmitToggle,
  });

  final double value;
  final double min;
  final double max;
  final bool omitted;
  final ValueChanged<double> onChanged;
  final VoidCallback onOmitToggle;

  /// Snap to 0.25 and clamp to [min, max] (desktop internal unit = value*4).
  double _snap(double v) =>
      ((v * 4).roundToDouble() / 4).clamp(min, max).toDouble();

  void _bump(double delta) => onChanged(_snap(value + delta));

  Widget _chevron(IconData icon, String tip, VoidCallback onTap) => Tooltip(
    message: tip,
    child: InkResponse(
      onTap: onTap,
      radius: 18,
      child: SizedBox(width: 26, height: 24, child: Icon(icon, size: 18)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        _chevron(Icons.keyboard_double_arrow_left, '-0.5', () => _bump(-0.5)),
        _chevron(Icons.keyboard_arrow_left, '-0.25', () => _bump(-0.25)),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              void setFromDx(double dx) {
                if (c.maxWidth <= 0) return;
                final frac = (dx / c.maxWidth).clamp(0.0, 1.0);
                onChanged(_snap(min + frac * (max - min)));
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => setFromDx(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => setFromDx(d.localPosition.dx),
                child: SizedBox(
                  height: 28,
                  child: CustomPaint(
                    painter: _BarPainter(
                      fraction: (max > min)
                          ? ((value - min) / (max - min)).clamp(0.0, 1.0)
                          : 0.0,
                      label: omitted ? '' : value.toStringAsFixed(2),
                      omitted: omitted,
                      dark: dark,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _chevron(Icons.keyboard_arrow_right, '+0.25', () => _bump(0.25)),
        _chevron(Icons.keyboard_double_arrow_right, '+0.5', () => _bump(0.5)),
        Tooltip(
          message: omitted ? 'Include (assessed)' : 'Omit (not assessed)',
          child: IconButton(
            icon: Icon(omitted ? Icons.block : Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: onOmitToggle,
          ),
        ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.fraction,
    required this.label,
    required this.omitted,
    required this.dark,
  });

  final double fraction;
  final String label;
  final bool omitted;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );

    // Track (flat gray when omitted, else the theme surface).
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = omitted
            ? const Color(0xFFF5F5F5)
            : (dark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
    );

    // Green gradient fill up to the value.
    if (!omitted && fraction > 0) {
      final fillRect = Rect.fromLTWH(0, 0, size.width * fraction, size.height);
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        fillRect,
        Paint()
          ..shader = LinearGradient(colors: DbsColors.scaleFill(dark))
              .createShader(fillRect),
      );
      canvas.restore();
    }

    // Border.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = omitted
            ? const Color(0xFFCCCCCC)
            : (dark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
    );

    // Value text centred on the bar.
    if (label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: debugPainterFontFamily,
            color: dark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.fraction != fraction ||
      o.label != label ||
      o.omitted != omitted ||
      o.dark != dark;
}
