import 'package:flutter/material.dart';

import '../core/electrode/contact_state.dart';
import '../core/electrode/electrode_model.dart';
import '../core/electrode/geometry.dart';
import '../core/electrode/stimulation_rule.dart';
import 'electrode_painter.dart';
import 'theme.dart';

/// Fired after every applied change with the full new configuration. OFF
/// contacts are absent from the map, as in the desktop representation.
typedef ElectrodeChanged = void Function(
  Map<ContactKey, ContactState> states,
  ContactState caseState,
);

/// Fired after every applied change with the `validateConfiguration` result.
/// Changes are applied even when invalid, as on the desktop, so the parent
/// surfaces the error rather than the edit being refused.
typedef ElectrodeValidation = void Function(bool valid, String error);

/// Interactive electrode viewer, a port of the desktop `ElectrodeCanvas`
/// (`dbs_annotator/models/electrode_viewer.py`).
///
/// Tap behaviour and rendering mirror the desktop; hover is dropped, since
/// touch has none.
class ElectrodeView extends StatefulWidget {
  const ElectrodeView({
    super.key,
    required this.model,
    this.initialStates = const {},
    this.initialCaseState = ContactState.off,
    this.onChanged,
    this.onValidation,
  });

  final ElectrodeModel model;

  /// Initial contact states; OFF is represented by key absence.
  final Map<ContactKey, ContactState> initialStates;

  final ContactState initialCaseState;

  final ElectrodeChanged? onChanged;

  final ElectrodeValidation? onValidation;

  @override
  State<ElectrodeView> createState() => _ElectrodeViewState();
}

class _ElectrodeViewState extends State<ElectrodeView> {
  late Map<ContactKey, ContactState> _states;
  late ContactState _caseState;

  @override
  void initState() {
    super.initState();
    _resetToInitial();
  }

  @override
  void didUpdateWidget(ElectrodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mirror the desktop set_model(): switching models resets all states.
    if (oldWidget.model.name != widget.model.name) {
      setState(_resetToInitial);
    }
  }

  void _resetToInitial() {
    _states = Map.of(widget.initialStates);
    _caseState = widget.initialCaseState;
  }

  /// OFF -> ANODIC -> CATHODIC -> OFF.
  static ContactState _next(ContactState state) => switch (state) {
    ContactState.off => ContactState.anodic,
    ContactState.anodic => ContactState.cathodic,
    ContactState.cathodic => ContactState.off,
  };

  /// Applies the change unconditionally and reports the validation outcome,
  /// matching the desktop `_apply_change_if_valid`.
  void _apply(Map<ContactKey, ContactState> newStates, ContactState newCase) {
    final result = validateConfiguration(newStates, newCase);
    setState(() {
      _states = newStates;
      _caseState = newCase;
    });
    widget.onValidation?.call(result.valid, result.error);
    widget.onChanged?.call(Map.unmodifiable(newStates), newCase);
  }

  void _cycleContact(ContactKey key) {
    final newStates = Map.of(_states);
    final next = _next(newStates[key] ?? ContactState.off);
    if (next == ContactState.off) {
      newStates.remove(key);
    } else {
      newStates[key] = next;
    }
    _apply(newStates, _caseState);
  }

  void _cycleCase() => _apply(Map.of(_states), _next(_caseState));

  void _cycleRing(int levelIdx) {
    final segStates = [
      for (var seg = 0; seg < 3; seg++)
        _states[ContactKey(levelIdx, seg)] ?? ContactState.off,
    ];

    // Desktop ring logic: all OFF becomes ANODIC, all ANODIC becomes
    // CATHODIC, and any mixed ring goes to OFF.
    final ContactState newState;
    if (segStates.every((s) => s == ContactState.off)) {
      newState = ContactState.anodic;
    } else if (segStates.every((s) => s == ContactState.anodic)) {
      newState = ContactState.cathodic;
    } else {
      newState = ContactState.off;
    }

    final newStates = Map.of(_states);
    for (var seg = 0; seg < 3; seg++) {
      final key = ContactKey(levelIdx, seg);
      if (newState == ContactState.off) {
        newStates.remove(key);
      } else {
        newStates[key] = newState;
      }
    }
    _apply(newStates, _caseState);
  }

  void _handleTapDown(ElectrodeLayout layout, TapDownDetails details) {
    final hit = hitTest(layout, details.localPosition);
    switch (hit) {
      case ContactHit(:final key):
        _cycleContact(key);
      case RingCapHit(:final levelIdx):
        _cycleRing(levelIdx);
      case CaseHit():
        _cycleCase();
      case null:
        break;
    }
  }

  // Cached layout, keyed on the only two things it depends on. Recomputing it
  // every build yields a new ElectrodeLayout, and that class has no value
  // equality, so `shouldRepaint` would see a change on every setState in the
  // host screen and fully repaint the canvas, slider ticks included.
  ElectrodeLayout? _layout;
  String? _layoutModel;
  Size? _layoutSize;

  ElectrodeLayout _layoutFor(ElectrodeModel model, Size size) {
    if (_layout != null && _layoutModel == model.name && _layoutSize == size) {
      return _layout!;
    }
    _layoutModel = model.name;
    _layoutSize = size;
    return _layout = computeLayout(model, size);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ElectrodePalette.of(Theme.of(context).brightness);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 320.0,
          constraints.hasBoundedHeight ? constraints.maxHeight : 480.0,
        );
        final layout = _layoutFor(widget.model, size);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _handleTapDown(layout, details),
          child: CustomPaint(
            size: size,
            painter: ElectrodePainter(
              layout: layout,
              states: _states,
              caseState: _caseState,
              labelColor: palette.label,
              palette: palette,
            ),
          ),
        );
      },
    );
  }
}
