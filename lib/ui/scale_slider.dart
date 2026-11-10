import 'package:flutter/material.dart';

import 'theme.dart';
import 'painter_font.dart';

/// A rating bar snapping to [step], with chevrons and an X that marks the scale
/// not assessed. A [step] of 1 or more draws one segment per whole value.
class ScaleSlider extends StatelessWidget {
  const ScaleSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.omitted,
    required this.onChanged,
    required this.onOmitToggle,
    this.step = 0.25,
  });

  final double value;
  final double min;
  final double max;
  final bool omitted;
  final ValueChanged<double> onChanged;
  final VoidCallback onOmitToggle;
  final double step;

  bool get _discrete => step >= 1;

  double _snap(double v) =>
      ((v / step).roundToDouble() * step).clamp(min, max).toDouble();

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
        if (!_discrete)
          _chevron(
            Icons.keyboard_double_arrow_left,
            '-${step * 2}',
            () => _bump(-step * 2),
          ),
        _chevron(Icons.keyboard_arrow_left, '-$step', () => _bump(-step)),
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
                      label: omitted
                          ? ''
                          : value.toStringAsFixed(_discrete ? 0 : 2),
                      omitted: omitted,
                      dark: dark,
                      segments: _discrete ? ((max - min) / step).round() : 0,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _chevron(Icons.keyboard_arrow_right, '+$step', () => _bump(step)),
        if (!_discrete)
          _chevron(
            Icons.keyboard_double_arrow_right,
            '+${step * 2}',
            () => _bump(step * 2),
          ),
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
    required this.segments,
  });

  final double fraction;
  final String label;
  final bool omitted;
  final bool dark;
  final int segments;

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

    final tick = Paint()
      ..strokeWidth = 1
      ..color = dark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
    for (var i = 1; i < segments; i++) {
      final x = size.width * i / segments;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tick);
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
      o.dark != dark ||
      o.segments != segments;
}
