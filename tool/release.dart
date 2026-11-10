// Guides a release in two steps, asking before each one.
//
//   dart run tool/release.dart [version]   bump the version and open the release PR
//   dart run tool/release.dart tag         tag the merged release commit and push it
//
// A version is X.Y.Z for a release or X.Y.Z-alpha.N, -beta.N or -rc.N for a
// pre-release. Pre-releases leave the newsfragments in place, so the final
// release's CHANGELOG.md section lists everything since the last final release.
// .github/RELEASING.md section 5 describes the whole process.

import 'dart:io';

const stages = ['alpha', 'beta', 'rc'];
const towncrierSpec = 'towncrier@26.9.0';
const repoUrl = 'https://github.com/neuromodulation/DBSAnnotator';
const releasesUrl = '$repoUrl/releases';
const actionsUrl = '$repoUrl/actions';

final _versionPattern = RegExp(
  r'^(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.([1-9]\d*))?$',
);

class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch, [this.stage, this.number]);

  final int major;
  final int minor;
  final int patch;
  final String? stage;
  final int? number;

  static Version? tryParse(String text) {
    final match = _versionPattern.firstMatch(text.trim());
    if (match == null) return null;
    return Version(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      match[4],
      match[5] == null ? null : int.parse(match[5]!),
    );
  }

  bool get isPrerelease => stage != null;

  Version get core => Version(major, minor, patch);

  /// Microsoft reserves the fourth component and has no room for a stage, so
  /// a pre-release shares its MSIX version with the final release.
  String get msixVersion => '$major.$minor.$patch.0';

  @override
  int compareTo(Version other) {
    for (final difference in [
      major - other.major,
      minor - other.minor,
      patch - other.patch,
    ]) {
      if (difference != 0) return difference;
    }
    if (stage == other.stage) return (number ?? 0) - (other.number ?? 0);
    if (stage == null) return 1;
    if (other.stage == null) return -1;
    return stages.indexOf(stage!) - stages.indexOf(other.stage!);
  }

  bool operator >(Version other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode => toString().hashCode;

  @override
  String toString() => stage == null
      ? '$major.$minor.$patch'
      : '$major.$minor.$patch-$stage.$number';
}

/// The versions of tags of the form vX.Y.Z[-stage.N]. Older tags in other
/// forms, such as the Qt app's v0.4.0b2, are ignored.
Set<Version> taggedVersions(Iterable<String> tags) => {
  for (final tag in tags)
    if (tag.startsWith('v')) Version.tryParse(tag.substring(1)),
}.whereType<Version>().toSet();

Version? latestTagged(Iterable<String> tags) {
  final versions = taggedVersions(tags);
  return versions.isEmpty ? null : versions.reduce((a, b) => a > b ? a : b);
}

/// The versions a release can take next: the current core version when it is
/// not yet released as final, then the patch, minor and major bumps.
List<Version> nextCores(Version current, Set<Version> tagged) {
  final cores = <Version>[
    if (!tagged.contains(current.core)) current.core,
    Version(current.major, current.minor, current.patch + 1),
    Version(current.major, current.minor + 1, 0),
    Version(current.major + 1, 0, 0),
  ];
  return cores.toSet().toList();
}

/// The final release and each pre-release stage of [core], numbered one past
/// the highest tag of that stage, keeping only what is newer than [latest].
List<Version> stageOptions(Version core, Set<Version> tagged, Version? latest) {
  int nextNumber(String stage) {
    var number = 1;
    for (final version in tagged) {
      if (version.core == core && version.stage == stage) {
        if (version.number! >= number) number = version.number! + 1;
      }
    }
    return number;
  }

  final options = [
    core,
    for (final stage in stages.reversed)
      Version(core.major, core.minor, core.patch, stage, nextNumber(stage)),
  ];
  return [
    for (final option in options)
      if (latest == null || option > latest) option,
  ];
}

String _replaceOnce(String text, String pattern, String replacement) {
  final regex = RegExp(pattern, multiLine: true);
  if (regex.allMatches(text).length != 1) {
    throw StateError('expected exactly one match for $pattern');
  }
  return text.replaceFirstMapped(regex, (m) => '${m[1]}$replacement');
}

String setPubspecVersion(String text, Version version, int build) {
  final bumped = _replaceOnce(text, r'^(version:\s*)\S+', '$version+$build');
  return _replaceOnce(
    bumped,
    r'^(\s+msix_version:\s*)\S+',
    version.msixVersion,
  );
}

String setAppInfoVersion(String text, Version version) =>
    _replaceOnce(text, r"^(const String appVersion = )'[^']+';", "'$version';");

String setCitationVersion(String text, Version version) =>
    _replaceOnce(text, r'^(version:\s*)\S+', '$version');

final _pubspecVersion = RegExp(
  r'^version:\s*([^\s+#]+)\+(\d+)',
  multiLine: true,
);

Future<void> main(List<String> args) async {
  try {
    if (args.length == 1 && args.first == 'tag') {
      await _tag();
    } else if (args.length <= 1) {
      await _prepare(args.isEmpty ? null : args.first);
    } else {
      throw const _Abort('usage: dart run tool/release.dart [version | tag]');
    }
  } on _Abort catch (abort) {
    stderr.writeln(abort.message);
    exitCode = 1;
  }
}

class _Abort implements Exception {
  const _Abort(this.message);
  final String message;
}

Future<void> _prepare(String? requested) async {
  final tags = _syncWithOrigin();
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = _pubspecVersion.firstMatch(pubspec);
  final current = match == null ? null : Version.tryParse(match[1]!);
  if (match == null || current == null) {
    throw const _Abort(
      'pubspec.yaml has no version of the form X.Y.Z[-stage.N]+BUILD.',
    );
  }
  final build = int.parse(match[2]!) + 1;
  final tagged = taggedVersions(tags);
  final latest = latestTagged(tags);
  stdout.writeln('pubspec.yaml version: ${match[1]}+${match[2]}');
  stdout.writeln(
    'Latest release tag:   ${latest == null ? 'none' : 'v$latest'}',
  );

  final Version version;
  if (requested != null) {
    version =
        Version.tryParse(requested) ??
        (throw _Abort(
          'Invalid version $requested. Expected X.Y.Z or X.Y.Z-alpha.N, '
          '-beta.N or -rc.N.',
        ));
  } else {
    final core = _choose('Release line', nextCores(current, tagged));
    final options = stageOptions(core, tagged, latest);
    if (options.isEmpty) {
      throw _Abort('Every stage of $core is older than v$latest.');
    }
    version = _choose('Release', options);
  }
  if (tagged.contains(version)) throw _Abort('Tag v$version already exists.');
  if (latest != null && !(version > latest)) {
    throw _Abort('v$version is not newer than the latest release v$latest.');
  }
  if (current.isPrerelease ? current > version : current.core > version.core) {
    throw _Abort('v$version is older than pubspec.yaml version $current.');
  }
  final branch = 'release/v$version';
  final title = 'chore(release): v$version';
  if (_git(['branch', '--list', branch]).isNotEmpty ||
      _git(['ls-remote', '--heads', 'origin', branch]).isNotEmpty) {
    throw _Abort(
      'Branch $branch already exists. Delete it first: '
      'git branch -D $branch, git push origin --delete $branch',
    );
  }

  final kind = version.isPrerelease ? 'pre-release' : 'release';
  stdout.writeln('\nPreparing $kind v$version (build $build).');
  final fragments = Directory('newsfragments')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'^\d+\..+\.md$').hasMatch(f.uri.pathSegments.last))
      .length;
  stdout.writeln(
    '\nRelease notes from $fragments newsfragments '
    '(the GitHub draft lists the merged PRs as well):\n',
  );
  await _check('uvx', [
    towncrierSpec,
    'build',
    '--draft',
    '--version',
    '$version',
  ]);
  if (fragments == 0 && !_confirm('No newsfragments. Continue anyway?')) {
    stdout.writeln('Stopped. Nothing was changed.');
    return;
  }

  if (!_confirm(
    '\nWrite v$version+$build to pubspec.yaml, lib/app_info.dart and CITATION.cff?',
  )) {
    stdout.writeln('Stopped. Nothing was changed.');
    return;
  }
  const undo =
      'Review with git diff HEAD; undo with '
      'git restore --source=HEAD --staged --worktree .';
  try {
    _rewrite('pubspec.yaml', (t) => setPubspecVersion(t, version, build));
    _rewrite('lib/app_info.dart', (t) => setAppInfoVersion(t, version));
    _rewrite('CITATION.cff', (t) => setCitationVersion(t, version));

    if (version.isPrerelease) {
      stdout.writeln(
        'Pre-release: CHANGELOG.md is left alone and the newsfragments stay '
        'for the final release.',
      );
    } else {
      if (!_confirm(
        'Move the newsfragments into CHANGELOG.md under $version?',
      )) {
        stdout.writeln('Stopped. The version files are changed. $undo');
        return;
      }
      await _check('uvx', [
        towncrierSpec,
        'build',
        '--version',
        '$version',
        '--yes',
      ]);
    }

    await _check('flutter', ['test', 'test/version_parity_test.dart']);
    if (_confirm('Run flutter analyze and the full flutter test suite now?')) {
      await _check('flutter', ['analyze', '--fatal-infos']);
      await _check('flutter', ['test']);
    }
  } catch (error) {
    final message = error is _Abort ? error.message : '$error';
    throw _Abort('$message\n$undo');
  }

  if (!_confirm(
    '\nCommit to a new branch $branch, push it and open a pull request?',
  )) {
    stdout.writeln(
      'Stopped. The files are changed, nothing is committed. $undo',
    );
    return;
  }
  _git(['switch', '-c', branch]);
  try {
    _git([
      'add',
      '-A',
      'pubspec.yaml',
      'lib/app_info.dart',
      'CITATION.cff',
      'CHANGELOG.md',
      'newsfragments',
    ]);
    _git(['commit', '-m', title]);
    _git(['push', '-u', 'origin', branch]);
    _git(['switch', 'main']);
  } on _Abort catch (abort) {
    throw _Abort(
      '${abort.message}\nYou are on $branch. Retry the failed step, or start '
      'over with git switch -f main, git branch -D $branch',
    );
  }

  final notes = version.isPrerelease
      ? 'Pre-release: the newsfragments stay in place for the final release, '
            'and CHANGELOG.md is unchanged.'
      : 'Moves the newsfragments into the $version section of CHANGELOG.md. '
            'That section is what clinicians read: check it reads well.';
  final code = await _run('gh', [
    'pr',
    'create',
    '--base',
    'main',
    '--head',
    branch,
    '--title',
    title,
    '--label',
    'skip-changelog',
    '--body',
    '## What this changes\n\n'
        'Sets the version to $version (build $build) in pubspec.yaml, '
        'msix_version, lib/app_info.dart and CITATION.cff. $notes\n\n'
        'After merging, tag the merge commit with `dart run tool/release.dart tag`.',
  ]);
  if (code != 0) {
    throw _Abort(
      '$branch is pushed, but gh could not open the pull request. Open it at '
      '$repoUrl/compare/main...$branch?expand=1 with the label skip-changelog.',
    );
  }
  stdout.writeln(
    '\nOnce the pull request is merged, run: dart run tool/release.dart tag',
  );
}

Future<void> _tag() async {
  final tags = _syncWithOrigin();
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = _pubspecVersion.firstMatch(pubspec);
  final version = match == null ? null : Version.tryParse(match[1]!);
  if (version == null) {
    throw const _Abort(
      'pubspec.yaml has no version of the form X.Y.Z[-stage.N]+BUILD.',
    );
  }
  if (tags.contains('v$version')) {
    throw _Abort(
      'v$version is already tagged. Prepare the next version first: '
      'dart run tool/release.dart',
    );
  }
  final latest = latestTagged(tags);
  if (latest != null && !(version > latest)) {
    throw _Abort('v$version is not newer than the latest release v$latest.');
  }

  final before = _pubspecVersion.firstMatch(
    _git(['show', 'HEAD~1:pubspec.yaml']),
  );
  if (before == null || before[1] == '$version') {
    throw _Abort(
      'The last commit on main does not set the version to $version, so it '
      'is not the release commit. Find that with '
      'git log --first-parent -- pubspec.yaml and tag it by hand: '
      'git tag -a v$version <commit> -m "Wyss DBS Annotator v$version"',
    );
  }

  final head = _git(['log', '-1', '--format=%h %s']);
  stdout.writeln('main is at $head');
  if (!_confirm('Create the annotated tag v$version on this commit?')) {
    stdout.writeln('Stopped. Nothing was tagged.');
    return;
  }
  _git(['tag', '-a', 'v$version', '-m', 'Wyss DBS Annotator v$version']);
  if (!_confirm('Push v$version to origin? This starts the release build.')) {
    stdout.writeln(
      'Tagged locally only. Push with: git push origin v$version\n'
      'or delete with: git tag -d v$version',
    );
    return;
  }
  try {
    _git(['push', 'origin', 'v$version']);
  } on _Abort catch (abort) {
    _git(['tag', '-d', 'v$version']);
    throw _Abort('${abort.message}\nThe local tag v$version is deleted again.');
  }

  final kind = version.isPrerelease ? 'pre-release' : 'release';
  stdout.writeln('''

Pushed. CI builds every platform and, if all of it passes, creates a draft
$kind at $releasesUrl
Follow the run at $actionsUrl

Then, by hand:
  1. Check the draft's assets and notes.
  2. Publish it.''');
  if (version.isPrerelease) {
    stdout.writeln(
      '  3. Do not submit its MSIX to the Store: it carries the final '
      "release's version, ${version.msixVersion}.",
    );
  } else {
    stdout.writeln(
      "  3. Use the CHANGELOG.md section as the Store's What's new text.",
    );
  }
}

/// Requires a clean checkout of main equal to origin/main, and returns every
/// tag after fetching them.
Set<String> _syncWithOrigin() {
  if (_git(['status', '--porcelain']).isNotEmpty) {
    throw const _Abort(
      'The working tree has changes. Commit or stash them first.',
    );
  }
  if (_git(['branch', '--show-current']) != 'main') {
    throw const _Abort('Switch to main first.');
  }
  _git(['fetch', '--tags', 'origin', 'main']);
  if (_git(['rev-parse', 'HEAD']) != _git(['rev-parse', 'origin/main'])) {
    throw const _Abort(
      'main differs from origin/main. Run git pull --ff-only first.',
    );
  }
  return _git(['tag', '--list', 'v*']).split('\n').toSet();
}

Version _choose(String label, List<Version> options) {
  stdout.writeln('\n$label:');
  for (var i = 0; i < options.length; i++) {
    final kind = options[i].isPrerelease ? 'pre-release' : 'release';
    stdout.writeln('  ${i + 1}) ${options[i]}  ($kind)');
  }
  while (true) {
    stdout.write('Choose 1-${options.length} [1]: ');
    final answer = stdin.readLineSync()?.trim() ?? '';
    if (answer.isEmpty) return options.first;
    final index = int.tryParse(answer);
    if (index != null && index >= 1 && index <= options.length) {
      return options[index - 1];
    }
  }
}

bool _confirm(String question) {
  stdout.write('$question [y/N] ');
  final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
  return answer == 'y' || answer == 'yes';
}

void _rewrite(String path, String Function(String) change) {
  final file = File(path);
  file.writeAsStringSync(change(file.readAsStringSync()));
}

String _git(List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) {
    throw _Abort('git ${args.join(' ')} failed:\n${result.stderr}');
  }
  return (result.stdout as String).trim();
}

/// Runs a command with its output on this terminal and returns its exit code.
/// Only flutter needs a shell on Windows, where it is a .bat; a shell would
/// cut the multi-line PR body passed to gh at its first line break.
Future<int> _run(String command, List<String> args) async {
  final process = await Process.start(
    command,
    args,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows && command == 'flutter',
  );
  return process.exitCode;
}

Future<void> _check(String command, List<String> args) async {
  final code = await _run(command, args);
  if (code != 0) {
    throw _Abort('$command ${args.join(' ')} failed with exit code $code.');
  }
}
