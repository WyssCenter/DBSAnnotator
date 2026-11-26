import 'dart:io';

import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

/// The user guide's Default lists page, which every picklist dialog links to.
void main() {
  final page = File('docs/default_lists.rst').readAsLinesSync();

  test('every section a dialog links to is a heading of the page', () {
    final headings = {
      for (final (i, line) in page.indexed)
        if (i + 1 < page.length && RegExp(r'^-{3,}$').hasMatch(page[i + 1]))
          line.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-'),
    };
    final linked = {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          for (final m in RegExp(
            r"section: '([a-z-]+)'",
          ).allMatches(f.readAsStringSync()))
            m[1]!,
    };
    expect(linked, hasLength(7));
    expect(headings, containsAll(linked));
  });

  test('the page lists the programs the app comes with', () {
    expect(
      page,
      containsAllInOrder([for (final p in kDefaultPrograms) '* $p']),
    );
  });
}
