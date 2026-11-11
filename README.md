# Wyss DBS Annotator

[![CI](https://github.com/neuromodulation/DBSAnnotator/actions/workflows/ci.yml/badge.svg)](https://github.com/neuromodulation/DBSAnnotator/actions/workflows/ci.yml)
[![Docs](https://readthedocs.org/projects/dbs-annotator/badge/?version=latest)](https://dbs-annotator.readthedocs.io/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> [!IMPORTANT]
> Wyss DBS Annotator is not a medical device. It is for annotating and documenting what happens during deep brain stimulation programming visits. It does not diagnose or decide stimulation settings: clinical decisions remain with the clinical team.

Annotate deep brain stimulation programming visits, and get analysis-ready data
out.

Once the electrodes are implanted, the patient comes back to see a neurologist or
psychiatrist, who tries stimulation configurations and settles on one that works.
That takes a visit or several, and the parameters go on being adapted over months
or years.

Wyss DBS Annotator documents those visits: the stimulation parameters tried on each
contact, the clinical and session scale ratings at each configuration, side
effects, and free-text notes, written to **BIDS tab-separated files** that go
straight into analysis. It also produces clinician-readable **PDF and Word
reports** for the patient record.

It runs **fully offline**. No account, no server, no telemetry. It is available
for iPadOS, Android, Windows and macOS in each platform's app store, and for
Linux as a one-line terminal install from GitHub, published by the Wyss Center
for Bio and Neuroengineering.

## Why

Vendor programming devices record what the device needs, not what research
needs, and they do not export data anyone can pool across patients or sites.
The alternative in practice is paper notes, which do not survive analysis. So
sessions get documented twice, inconsistently, and the relationship between
what was delivered and what happened, which is the whole point of a programming
session, is the part that gets lost.

This tool records that relationship as it happens, in one format, with the
timestamps intact.

## Repository layout

```
lib/                 the Flutter application (Dart)
test/                automated tests
integration_test/    docs video flows, run on a desktop build
assets/              fonts and brand images bundled with the app
android/ ios/ linux/ macos/ windows/
schema/              the machine-readable domain contract (TSV columns,
                     BIDS naming, stimulation limits, electrode models)
docs/                documentation source (Read the Docs)
tool/                fixture, screenshot, video and brand-asset scripts
paper/               JOSS paper
.github/             CI, issue templates, release runbook (RELEASING.md)
```

## Getting started

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
**3.47 or later** (Dart 3.13+). From the repository root:

```bash
flutter pub get
flutter test        # no device needed
flutter analyze
flutter run         # on this computer, an emulator, or a connected device
```

Nothing needs generating first. The schema contract is committed, so a fresh
clone builds and tests immediately.

## What it does

The app opens on **Annotate programming session**: annotate a programming visit,
with stimulation parameters, contacts, clinical scales, symptom and side effect
ratings and notes, into a BIDS folder. Its Session step also imports earlier
sessions and exports a session report, a report across visits, a combined table
or a BIDS folder. A side menu holds the settings.

## Output

Every session is saved in a BIDS folder: a `_beh.tsv` with one row per
configuration and one `scale_<name>` column per scale, each run's initial
assessment in `scans.tsv`, the visit's target, leads and IPGs in
`sessions.tsv`, and the DBS indication in `participants.tsv`, each with a JSON
sidecar documenting every column. A synthetic example folder is in
[`test/fixtures/bids`](test/fixtures/bids):

```python
df = pd.read_csv(path, sep="\t", na_values=["n/a"])
```

**Export → BIDS dataset** lays a set of sessions out as a validator-ready
`sub-XX/ses-YYYYMMDD/beh/` tree.

Reports come out as PDF and Word, both built from the same numbers so they
cannot disagree. The full format reference is in the
[documentation](https://dbs-annotator.readthedocs.io/).

## Installing

Open the [installation page](https://dbs-annotator.readthedocs.io/en/latest/installation.html)
and click Download: it takes you to your platform's app store, or on Linux to a
one-line install command. To build it yourself,
see [Building from source](https://dbs-annotator.readthedocs.io/en/latest/installation.html#building-from-source).
Maintainers publishing a release: see [.github/RELEASING.md](.github/RELEASING.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Citing

If you use Wyss DBS Annotator in published work, please cite it; see
[CITATION.cff](CITATION.cff).

## License

MIT. See [LICENSE](LICENSE).
