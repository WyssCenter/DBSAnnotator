import 'package:flutter/material.dart';

/// Per-cathode amplitude split, a port of `ui/amplitude_split_widget.py`.
///
/// Shown only when at least two cathodes are active. Each gets an editable
/// percentage, and the last row is the auto-computed remainder so the values
/// always sum to 100. [onChanged] reports the percentages aligned to
/// [cathodes]; the parent serialises them at insert.
class AmplitudeSplit extends StatefulWidget {
  const AmplitudeSplit({
    super.key,
    required this.cathodes,
    required this.total,
    required this.decimals,
    required this.onChanged,
    this.initial = const [],
  });

  final List<String> cathodes;
  final List<double> initial;
  final double total;
  final int decimals;
  final ValueChanged<List<double>> onChanged;

  @override
  State<AmplitudeSplit> createState() => _AmplitudeSplitState();
}

/// Percentage step for the spin arrows.
const double _pctStep = 5;

class _AmplitudeSplitState extends State<AmplitudeSplit> {
  late List<double> _pct;
  late List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _reset(seed: widget.initial);
    _notifyLater();
  }

  @override
  void didUpdateWidget(AmplitudeSplit old) {
    super.didUpdateWidget(old);
    if (!_sameCathodes(old.cathodes, widget.cathodes)) {
      for (final c in _ctrls) {
        c.dispose();
      }
      _reset();
      _notifyLater();
    } else if (old.total != widget.total) {
      setState(() {}); // recompute the mA labels
    }
  }

  bool _sameCathodes(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// A step change remounts this widget, so the stored split is restored
  /// rather than replaced by an equal one. A new cathode set starts equal.
  void _reset({List<double> seed = const []}) {
    final n = widget.cathodes.length;
    final valid =
        seed.length == n && (seed.fold(0.0, (a, b) => a + b) - 100).abs() < 0.5;
    _pct = valid
        ? List<double>.of(seed)
        : List<double>.filled(n, n == 0 ? 0 : 100 / n);
    _ctrls = [
      for (var i = 0; i < n; i++) TextEditingController(text: _fmtPct(_pct[i])),
    ];
  }

  /// Report the current split after the frame, so a call from initState or
  /// didUpdateWidget cannot setState during build.
  void _notifyLater() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) widget.onChanged(List<double>.of(_pct));
  });

  String _fmtPct(double v) {
    var s = v.toStringAsFixed(1);
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }

  /// Row [i] edited to [text]: clamp to 0..100, scale the other rows down if
  /// they would exceed 100, and give the last row the remainder.
  void _edit(int i, String text) {
    final n = _pct.length;
    _pct[i] = (double.tryParse(text.trim()) ?? 0).clamp(0.0, 100.0).toDouble();
    if (i != n - 1) {
      var head = 0.0;
      for (var k = 0; k < n - 1; k++) {
        head += _pct[k];
      }
      if (head > 100) {
        final slack = head - _pct[i];
        final target = (100 - _pct[i]).clamp(0.0, 100.0);
        final scale = slack == 0 ? 0.0 : target / slack;
        for (var k = 0; k < n - 1; k++) {
          if (k != i) _pct[k] = _pct[k] * scale;
        }
      }
      var sumHead = 0.0;
      for (var k = 0; k < n - 1; k++) {
        sumHead += _pct[k];
      }
      _pct[n - 1] = (100 - sumHead).clamp(0.0, 100.0).toDouble();
    }
    for (var k = 0; k < n; k++) {
      if (k != i) _ctrls[k].text = _fmtPct(_pct[k]);
    }
    setState(() {});
    widget.onChanged(List<double>.of(_pct));
  }

  void _bump(int i, int direction) {
    final next = (_pct[i] + direction * _pctStep).clamp(0.0, 100.0).toDouble();
    _ctrls[i].text = _fmtPct(next);
    _edit(i, _ctrls[i].text);
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  /// Stacked spin arrows, matching the stimulation parameter fields.
  Widget _arrow(IconData icon, String tooltip, VoidCallback onTap) => Tooltip(
    message: tooltip,
    child: InkResponse(
      onTap: onTap,
      radius: 16,
      child: SizedBox(width: 22, height: 15, child: Icon(icon, size: 16)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.cathodes.length < 2) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final last = widget.cathodes.length - 1;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Amplitude split',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: muted),
          ),
          for (var i = 0; i < widget.cathodes.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      widget.cathodes[i],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _ctrls[i],
                      // The last row is the read-only remainder.
                      enabled: i != last,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: '%',
                      ),
                      onChanged: (t) => _edit(i, t),
                    ),
                  ),
                  // The last row is the remainder, so it has nothing to step.
                  if (i == last)
                    const SizedBox(width: 22)
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _arrow(
                          Icons.keyboard_arrow_up,
                          'Increase ${widget.cathodes[i]} share',
                          () => _bump(i, 1),
                        ),
                        _arrow(
                          Icons.keyboard_arrow_down,
                          'Decrease ${widget.cathodes[i]} share',
                          () => _bump(i, -1),
                        ),
                      ],
                    ),
                  const SizedBox(width: 8),
                  Text(
                    '→ ${(widget.total * _pct[i] / 100).toStringAsFixed(widget.decimals)} mA',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
