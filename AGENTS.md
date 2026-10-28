# Notes for coding agents

Conventions for any coding agent working in this repository. CONTRIBUTING.md is the full
version for people; this file is the compact one. When the two disagree, this file is
correct: fix CONTRIBUTING.md in the same change.

## Project

Wyss DBS Annotator is an offline Flutter app for documenting deep brain stimulation
programming sessions, built for Windows, macOS, Linux, Android and iOS. The TSV and BIDS
output format is a contract defined in `schema/`, which the app bundles and the docs render
from. User docs are Sphinx sources in `docs/`, published on Read the Docs.

Programming sessions are outpatient visits: the clinicians and the patient sit around a table while configurations are tested. Write "in clinic" or "during the visit", never "bedside".

## Setup

Flutter 3.38.4 or later (Dart 3.12+). Python tooling runs through `uv`, with nothing to
install.

```
flutter pub get
flutter run          # this computer, an emulator, or a connected device
```

## Layout

```
lib/core/            domain logic: sessions, TSV and BIDS, electrode geometry
lib/report/          PDF and Word reports, filed in a patient record
lib/ui/              screens and widgets
schema/              the output contract, bundled by the app
test/                unit and widget tests
test/fixtures/       synthetic sessions from tool/generate_fixtures.dart
test/docs/           generates the docs screenshots
integration_test/    docs video flows, desktop only
tool/                fixture, screenshot, video and brand-asset scripts
docs/                Sphinx sources for Read the Docs
.github/             CI, templates, release runbook
```

## Working rules

- Draft commit messages and pull request descriptions when asked, but never commit, push,
  tag or open a pull request yourself. The maintainer does.
- No assistant attribution anywhere: code, docs, commit messages, `Co-Authored-By` trailers.
- Check live state (git, gh, CI) before repeating a status from earlier notes.
- Parallel agents get disjoint sets of files. Stop any agent whose scope overlaps another's,
  since a broad writer silently reverts narrow ones, and re-verify their results yourself.

## Checks

```
dart format lib test integration_test tool
flutter analyze --fatal-infos
flutter test
uvx pre-commit run --all-files
sphinx-build -W docs docs/_build/html
```

- One file: `flutter test test/bids_test.dart`.
- After a format change, regenerate the fixtures: `dart run tool/generate_fixtures.dart`.
- `pre-commit run --all-files` sees only tracked files: `git add -N` new files first, and
  `git reset` them afterwards if the maintainer stages by hand.
- `integration_test/` needs a desktop build and is not part of the routine checks.
- Screenshots and docs videos are generated, never edited by hand; CONTRIBUTING.md has the
  commands.

## Commits and pull requests

- Commit subjects use conventional prefixes with an optional scope: `feat(reports):`,
  `fix(bids):`, `docs:`, `chore:`.
- Pull request descriptions follow `.github/PULL_REQUEST_TEMPLATE.md`.
- A PR that changes the app adds `newsfragments/<PR>.<type>.md` (Towncrier, see
  `newsfragments/README.md`); CI fails without it. The number comes from the PR, so ask
  the maintainer for it. Never edit `CHANGELOG.md` by hand: `towncrier build` writes it
  at release.

## Code style

Prefer the simplest solution that fully solves the problem. If your agent has the ponytail
skill or plugin available, apply it to every coding task here. Otherwise hold the code to the
same standard:

- Question whether the change is needed before writing it; build nothing for a hypothetical
  future case.
- Reach for the Dart and Flutter standard libraries, then an existing helper in `lib/`, before writing new code; add a dependency only when the platform cannot do the job.
- No abstraction without a second caller: no wrapper around a single call, no interface with
  one implementation, no parameter or setting for a value that never varies.
- Keep the diff to what the task needs. Delete dead code instead of commenting it out, and do not reshape unrelated code.

- No code comments. The only exception is doc comments on public API, one or two lines.
- When you edit code, bring the comments on and around the lines you change in line with
  these rules: delete plain comments and cut doc comments to one or two lines. Leave
  comments elsewhere in the file alone.
- No section headings inside files.
- No version history in code ("used to", "was named"). State the constraint, not the story.
- No em or en dashes anywhere, product strings included. The one exception is the dash key in the sanitiser map of `lib/report/report_text.dart`, which must stay. Fix dashes only in lines you are already editing.
- Docs prose (`docs/*.rst`) is fuller and explanatory, for a clinician or analyst meeting the format for the first time. Still no filler, scattered bold or rhetorical headings.

## Clinical care

Reports are filed in a patient record.

- Never assert what the data does not support.
- Never lose data silently.

## Security and privacy

- The app is offline by design. Add no network calls, analytics, crash reporting or
  telemetry, including through a dependency.
- No real patient data in code, tests, fixtures, screenshots or issue text. Use the synthetic data in `test/fixtures/`.
- Never commit signing material (keystores, `.pfx`, `key.properties`, `.p8`). `.gitignore`
  covers it, and `git add -f` bypasses that.

## Pitfalls

- Never run `sed -i` over `git ls-files`. With `core.autocrlf` it strips CR bytes from PNG and ICO files. Find files with `grep -l` first and check `git diff --numstat` afterwards.
- No `.gitignore` rule may match `lib/`: `git check-ignore -v lib/main.dart` must print
  nothing.
- The contract lives only in `schema/`. Changing a TSV column means changing
  `lib/core/schema_columns.dart` too; `test/schema_columns_test.dart` fails otherwise.
- The version is written in four places, pinned by `test/version_parity_test.dart`.
- `lib/report/` never imports `lib/ui/`.
- Fake-async widget tests cannot finish real file I/O; use `tester.runAsync`.
- Git Bash heredocs mangle `\n` and quotes. Write edit scripts to a file and run that.

## Pointers

- CONTRIBUTING.md: checks, screenshots, videos, review expectations.
- `.github/RELEASING.md`: signing, store submissions, cutting a release.
- `docs/`: user and format documentation.
