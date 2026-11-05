import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const range = (min: 0.0, max: 10.0);

  test('rangeError rejects NaN and infinity', () {
    expect(rangeError('NaN', range), 'Not a number');
    expect(rangeError('Infinity', range), 'Not a number');
  });

  test('rangeError accepts blank and in-range values', () {
    expect(rangeError('', range), isNull);
    expect(rangeError('3.5', range), isNull);
  });
}
