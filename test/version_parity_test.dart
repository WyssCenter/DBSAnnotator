import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The version number is written in four places. This fails if they disagree.
///
/// `pubspec.yaml`'s `version:` is the source of truth; the platform builds
/// and `docs/conf.py` derive from it. Three places restate it because they
/// cannot read it: `lib/app_info.dart` (no pubspec at runtime, and its value
/// is printed on every report), `CITATION.cff` (GitHub and Zenodo read it)
/// and `msix_version` (needs a fourth component, which Microsoft reserves
/// for Store use and requires to be 0).
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  /// Regexes rather than a YAML parser: these are all top-level scalars.
  String? firstMatch(String text, String pattern) =>
      RegExp(pattern, multiLine: true).firstMatch(text)?.group(1);

  test('pubspec declares a parseable version', () {
    expect(
      firstMatch(pubspec, r'^version:\s*([0-9][^\s+#]*)'),
      isNotNull,
      reason:
          'pubspec.yaml must declare `version: <major.minor.patch>+<build>`.',
    );
  });

  final version = firstMatch(pubspec, r'^version:\s*([0-9][^\s+#]*)')!;

  test('lib/app_info.dart appVersion matches the pubspec', () {
    final appInfo = File('lib/app_info.dart').readAsStringSync();
    expect(
      firstMatch(appInfo, r"""^const String appVersion = '([^']+)';"""),
      version,
      reason:
          'appVersion in lib/app_info.dart must equal `version:` in '
          'pubspec.yaml ($version). It is printed on every report.',
    );
  });

  test('CITATION.cff version matches the pubspec', () {
    final citation = File('CITATION.cff').readAsStringSync();
    // Anchored: `cff-version:` also matches a bare `version:` search.
    expect(
      firstMatch(citation, r'^version:\s*(\S+)'),
      version,
      reason:
          'version: in CITATION.cff must equal `version:` in '
          'pubspec.yaml ($version).',
    );
  });

  test(
    'msix_version matches the pubspec, with the Store-reserved 0 revision',
    () {
      final msixVersion = firstMatch(pubspec, r'^\s+msix_version:\s*(\S+)');
      expect(
        msixVersion,
        isNotNull,
        reason: 'msix_config in pubspec.yaml must declare msix_version.',
      );
      // MSIX has no room for a pre-release stage such as -beta.1.
      final expected = '${version.split('-').first}.0';
      expect(
        msixVersion,
        expected,
        reason:
            'msix_version must be `<pubspec major.minor.patch>.0`: four '
            'components, with the fourth left 0 because Microsoft reserves '
            'the revision field for Store use. Expected $expected.',
      );
    },
  );

  // Deliberately not asserted: Microsoft says the non-first version sections
  // must be 0..65535 (making a 0.x msix_version invalid), but that text sits
  // in a UWP section and may not apply to a packaged Win32 MSIX.
}
