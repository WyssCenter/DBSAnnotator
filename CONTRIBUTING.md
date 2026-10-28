# Contributing to Wyss DBS Annotator

Contributions are welcome. This is research software for deep brain stimulation
programming, so correctness and honesty about what the data supports matter more
here than most places; see *Clinical care* below.

## Scope

Everything here is the Flutter app: `lib/` for source, `test/` for tests.

The TSV format lives in `schema/*.json`, which the app bundles and the docs render
from. Change it there, and `lib/core/schema_columns.dart` with it.

## Quick start

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
**3.38.4 or later** (Dart 3.12+), the floor `pubspec.lock` resolves against, so
an older SDK fails at `pub get`. From the repository root:

```bash
flutter pub get
flutter test
flutter analyze
```

Then:

1. Fork the repository and branch: `git switch -c feature/your-feature-name`
2. Make your change, with tests
3. These must all pass:

   ```bash
   dart format lib test integration_test tool
   flutter analyze --fatal-infos
   flutter test
   uvx pre-commit run --all-files
   sphinx-build -W docs docs/_build/html
   ```

4. Open a pull request, then add `newsfragments/<PR number>.<type>.md`, one or
   two sentences on what changed for the person using the app. CI asks for it
   whenever the app changes; [newsfragments/README.md](newsfragments/README.md)
   has the types and the exemptions.

[AGENTS.md](AGENTS.md) holds the same conventions in compact form for coding agents.
When the two disagree, AGENTS.md is correct; fix this file in the same change.

## Checks

`flutter analyze` does **not** check formatting, which is why formatting had
drifted across two thirds of the files before a gate existed. Both are enforced
now, along with a few things that are cheap to check and expensive to miss.

To run everything the way CI does:

```bash
uvx pre-commit run --all-files
```

To have it run on each commit:

```bash
uvx pre-commit install
```

`uvx` needs no virtualenv. Python is not the application (the app is Dart), but
Sphinx already needs it to build the docs, so this adds no new toolchain.

| Check | Why it is here |
|---|---|
| `dart format` | Not covered by `flutter analyze`. |
| `flutter analyze --fatal-infos` | Infos are already clean; keeping them clean is free. |
| `check-yaml` / `check-json` | `schema/*.json` is loaded at runtime, so a syntax error is a crash on launch. A bad regex once wrote a control character into `ci.yml`. Also covers `CITATION.cff`, which GitHub parses. |
| `detect-private-key` | `.gitignore` covers `*.pfx`, but `git add -f` bypasses ignore rules. |
| `check-added-large-files` | A stray build artifact is 19 MB. |
| `ruff`, `doc8` | The Sphinx config and the docs extension are the only Python here. |
| `codespell` | Typos in report prose end up in a patient record. |

Two more run in CI only: **`actionlint`**, which shellchecks the workflow's
`run:` blocks and validates its `${{ }}` expressions (it is a Go binary, so it
is not a local hook), and a **docs build with `-W`**, because Read the Docs
publishes with `fail_on_warning` and a warning there breaks publishing after
merge rather than before.

CI is the authority, since `git commit --no-verify` skips the hooks and CI
cannot be skipped, but it runs the checks by invoking **these same hooks**
(`uvx pre-commit run --all-files`), so there is one definition of each rule and
nothing to keep in step. `pyproject.toml` holds the ruff, doc8 and codespell
settings for the same reason. Change a rule in one place and both follow.

Not enforced, deliberately: `trailing-whitespace` and `end-of-file-fixer`. With
`core.autocrlf` on Windows and only `*.sh` pinned in `.gitattributes`, they
fight the line-ending filter and produce churn. Worth revisiting alongside a
`* text=auto` policy.

## What we look for

- **Tests that would have caught the bug.** A test asserting only that a
  function runs is worth little; one pinning the value it produces is worth a
  lot. Several tests in this repo exist because a reviewer computed the expected
  numbers independently and they disagreed with the code.
- **No code comments.** Names and structure carry the meaning. Doc comments on
  public API are the one exception, at one or two lines.
- **`flutter analyze` clean.** No new warnings, no `// ignore:`.

## Clinical care

This app produces documents that go into a patient record. Two rules follow from
that, and both have already caused real changes here:

- **Never assert what the data does not support.** The reports say "last recorded
  configuration", not "final settings", because nothing in the TSV records that a
  clinician confirmed a choice. The block ranking refuses to run at all when no
  scale targets have been set, rather than inventing them.
- **Never lose data silently.** If a character cannot be rendered, the export
  says so. If a file cannot be written, the write is atomic and the old file
  survives. A silent partial success is worse than a loud failure.

## Documentation

Documentation lives in `docs/` (Sphinx, reStructuredText) and is published to
Read the Docs. Pages under `docs/screens/` describe one screen each; the column
tables and the sidecar example in `output_format` are rendered from
`schema/tsv_schema.json` at build time, so edit the schema, not the page.

### Screenshots

The 28 images under `docs/_static/screenshots/` are generated from widget tests,
never edited by hand, and committed, because Read the Docs cannot run a Flutter
SDK inside its build limits. To regenerate after a UI change:

```powershell
$env:DOCS_SCREENSHOT_DIR = "docs/_static/screenshots"
flutter test test/docs/screenshots_test.dart
```

Without that variable a plain `flutter test` skips the whole file, so the working
tree is never dirtied by accident.

Two rules the harness enforces, both of which had regressed before it did:

- **Heights are measured, never chosen.** `_shootFitted` sizes the window to the
  page's own laid-out content; `_shootRegion` cuts a band on widget boundaries.
  Do not add a capture with a hard-coded `Size(...)`.
- **Nothing is photographed empty.** The `_seed*` helpers fill in stimulation
  parameters, contacts, scale ratings and notes first. A screenshot of a blank
  form documents nothing.

`.github/workflows/docs-screenshots.yml` re-renders them on PRs touching
`lib/ui/**` and uploads the result as an artifact. It deliberately does **not**
diff against the committed PNGs: Skia and text shaping differ enough between a
runner and a developer machine that a byte comparison fails on visually
identical renders. What it does catch is a capture that no longer *generates*:
a finder that stopped matching, or a dialog that moved.

### Videos

The clips under `docs/_static/videos/` are recorded from the real Windows app
while an integration test in `integration_test/videos/` drives it. Install
ffmpeg once (`winget install Gyan.FFmpeg`), then:

```powershell
powershell -File tool/record_video.ps1 -Flow record_block
powershell -File tool/record_video.ps1 -Flow reports
```

The tests use a temporary folder for preferences and the working copy, so
recording never changes your own. Windows only; on macOS or Linux the same
tests run, with ffmpeg's `avfoundation` or `x11grab` in place of `gdigrab`.

## Getting help

Open an issue, or start a discussion. For anything that looks like a clinical
safety concern, please say so explicitly in the issue title.

## License

By contributing you agree that your contribution is licensed under the MIT
license, as in [LICENSE](LICENSE).
