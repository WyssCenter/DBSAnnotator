import 'package:flutter_test/flutter_test.dart';

import '../tool/release.dart';

Version v(String text) => Version.tryParse(text)!;

void main() {
  test('parses final and pre-release versions, rejects other forms', () {
    expect(v('0.6.0').isPrerelease, isFalse);
    expect(v('0.6.0-beta.2').stage, 'beta');
    expect(v('0.6.0-beta.2').number, 2);
    for (final bad in [
      '0.6',
      '0.6.0b2',
      '0.6.0-beta',
      '0.6.0-dev.1',
      '0.6.0-rc.0',
    ]) {
      expect(Version.tryParse(bad), isNull, reason: bad);
    }
  });

  test('orders alpha < beta < rc < final, numbers numerically', () {
    final sorted = [
      '0.7.0',
      '0.6.0-rc.1',
      '0.6.0',
      '0.6.0-beta.10',
      '0.6.0-alpha.1',
      '0.6.0-beta.2',
    ].map(v).toList()..sort();
    expect(sorted.map((x) => '$x'), [
      '0.6.0-alpha.1',
      '0.6.0-beta.2',
      '0.6.0-beta.10',
      '0.6.0-rc.1',
      '0.6.0',
      '0.7.0',
    ]);
  });

  test('a pre-release shares the final release MSIX version', () {
    expect(v('0.6.0-rc.1').msixVersion, '0.6.0.0');
  });

  test('latest tag ignores tags outside the vX.Y.Z[-stage.N] form', () {
    expect(
      latestTagged(['v0.4.0', 'v0.4.0b2', 'qt-final-v0.4.0', 'v0.6.0-beta.1']),
      v('0.6.0-beta.1'),
    );
    expect(latestTagged(['qt-final-v0.4.0']), isNull);
  });

  test('an untagged pubspec version is offered before the bumps', () {
    final tagged = {v('0.4.0')};
    expect(nextCores(v('0.6.0'), tagged).map((x) => '$x'), [
      '0.6.0',
      '0.6.1',
      '0.7.0',
      '1.0.0',
    ]);
    expect(stageOptions(v('0.6.0'), tagged, v('0.4.0')).map((x) => '$x'), [
      '0.6.0',
      '0.6.0-rc.1',
      '0.6.0-beta.1',
      '0.6.0-alpha.1',
    ]);
  });

  test('after a beta, offers the next beta and later stages only', () {
    final tagged = {v('0.4.0'), v('0.6.0-beta.1')};
    final latest = v('0.6.0-beta.1');
    expect(nextCores(v('0.6.0-beta.1'), tagged).first, v('0.6.0'));
    expect(stageOptions(v('0.6.0'), tagged, latest).map((x) => '$x'), [
      '0.6.0',
      '0.6.0-rc.1',
      '0.6.0-beta.2',
    ]);
  });

  test('after a final release, its version is no longer offered', () {
    final tagged = {v('0.6.0-rc.1'), v('0.6.0')};
    expect(nextCores(v('0.6.0'), tagged).map((x) => '$x'), [
      '0.6.1',
      '0.7.0',
      '1.0.0',
    ]);
  });

  test('rewrites every version literal and only those', () {
    const pubspec =
        '# version: 9.9.9 in a comment\n'
        'version: 0.6.0+2\n'
        'msix_config:\n'
        '  msix_version: 0.6.0.0\n';
    expect(
      setPubspecVersion(pubspec, v('0.7.0-beta.1'), 3),
      '# version: 9.9.9 in a comment\n'
      'version: 0.7.0-beta.1+3\n'
      'msix_config:\n'
      '  msix_version: 0.7.0.0\n',
    );
    expect(
      setAppInfoVersion("const String appVersion = '0.6.0';\n", v('0.7.0')),
      "const String appVersion = '0.7.0';\n",
    );
    expect(
      setCitationVersion(
        'cff-version: 1.2.0\nversion: 0.6.0\n',
        v('0.7.0-rc.2'),
      ),
      'cff-version: 1.2.0\nversion: 0.7.0-rc.2\n',
    );
  });

  test('refuses to rewrite when the literal is missing', () {
    expect(
      () => setAppInfoVersion('no version here', v('0.7.0')),
      throwsStateError,
    );
  });
}
