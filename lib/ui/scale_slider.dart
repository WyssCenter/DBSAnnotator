import 'package:flutter/material.dart';

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
    this.quality,
  });

  final double value;
  final double min;
  final double max;
  final bool omitted;
  final ValueChanged<double> onChanged;
  final VoidCallback onOmitToggle;
  final double step;

  /// How good the value is for this scale's target, 0 worst to 1 best; the
  /// bar shades from red to green. Null when the scale is not ranked.
  final double? quality;

  /// Darker than any track, so a scale not assessed reads apart at a glance.
  static const omittedTrack = Color(0xFF5F5F5F);

  bool get _discrete => step >= 1;

  double _snap(double v) =>
      ((v / step).roundToDouble() * step).clamp(min, max).toDouble();

  void _bump(double delta) => onChanged(_snap(value + delta));

  Widget _chevron(IconData icon, String tip, VoidCallback onTap) => IconButton(
    icon: Icon(icon),
    tooltip: tip,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    onPressed: onTap,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
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
                      scheme: scheme,
                      fill: switch (quality) {
                        null => scheme.primaryContainer,
                        final q => HSVColor.fromAHSV(
                          1,
                          120 * q.clamp(0.0, 1.0),
                          0.55,
                          0.92,
                        ).toColor(),
                      },
                      fillInk: quality == null
                          ? scheme.onPrimaryContainer
                          : const Color(0xFF1B1B1B),
                      segments: _discrete ? ((max - min) / step).round() : 0,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _chevron(Icons.keyboard_arrow_right, '+$step', () => _bump(step)),
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
    required this.scheme,
    required this.fill,
    required this.fillInk,
    required this.segments,
  });

  final double fraction;
  final String label;
  final bool omitted;
  final ColorScheme scheme;
  final Color fill;
  final Color fillInk;
  final int segments;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = omitted
            ? ScaleSlider.omittedTrack
            : scheme.surfaceContainerHighest,
    );

    if (!omitted && fraction > 0) {
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * fraction, size.height),
        Paint()..color = fill,
      );
      canvas.restore();
    }

    final tick = Paint()
      ..strokeWidth = 1
      ..color = scheme.outlineVariant;
    for (var i = 1; i < segments; i++) {
      final x = size.width * i / segments;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tick);
    }

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = scheme.outlineVariant,
    );

    if (label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: debugPainterFontFamily,
            color: fraction >= 0.5 ? fillInk : scheme.onSurface,
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
      o.scheme != scheme ||
      o.fill != fill ||
      o.fillInk != fillInk ||
      o.segments != segments;
}
