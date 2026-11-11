import 'package:dbs_annotator/ui/scale_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<double>> dragAcross(WidgetTester tester, double step) async {
    final seen = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ScaleSlider(
              value: 0,
              min: 0,
              max: 4,
              step: step,
              omitted: false,
              onChanged: seen.add,
              onOmitToggle: () {},
            ),
          ),
        ),
      ),
    );
    final bar = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onHorizontalDragUpdate != null,
    );
    final box = tester.getRect(bar);
    for (var i = 1; i < 20; i++) {
      await tester.tapAt(Offset(box.left + box.width * i / 20, box.center.dy));
    }
    return seen;
  }

  testWidgets('a whole step only ever reports whole values', (tester) async {
    final seen = await dragAcross(tester, 1);
    expect(seen, isNotEmpty);
    expect(seen.every((v) => v == v.roundToDouble()), isTrue);
    expect(find.byIcon(Icons.keyboard_double_arrow_left), findsNothing);
  });

  testWidgets('the default step keeps quarter values', (tester) async {
    final seen = await dragAcross(tester, 0.25);
    expect(seen.any((v) => v != v.roundToDouble()), isTrue);
    expect(seen.every((v) => (v * 4) == (v * 4).roundToDouble()), isTrue);
  });
}
