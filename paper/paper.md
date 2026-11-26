---
title: 'DBS Annotator: recording deep brain stimulation programming visits in an analysis-ready format'
tags:
  - deep brain stimulation
  - neuromodulation
  - clinical data capture
  - BIDS
  - Dart
  - Flutter
authors:
  - name: Lucia Poma
    orcid: 0000-0000-0000-0000   # TODO: real ORCID; a placeholder fails editorialbot
    corresponding: true
    affiliation: 1
  - name: Richard M. Kohler
    orcid: 0000-0000-0000-0000   # TODO: real ORCID
    affiliation: 1
affiliations:
  - name: Wyss Center for Bio and Neuroengineering, Geneva, Switzerland
    index: 1
date: 31 August 2026
bibliography: paper.bib
---

# Summary

Deep brain stimulation (DBS) therapy depends on *programming*. Once the electrodes
are implanted, the patient attends appointments with a neurologist or psychiatrist at
which the clinician iterates through stimulation configurations - active contacts,
amplitude, pulse width, frequency - and records how the patient responds to each.
Reaching a good setting takes one visit or many, and the parameters go on being
adapted over months or years. The scientific content of such a visit is the
relationship between what was delivered and what was observed.
In routine practice that relationship is largely lost. Clinical programming devices
are built to configure hardware, not to export research-usable records, and the
ratings, ordering and adverse events that give the parameters their meaning end up in
free text or on paper.

`DBS Annotator` is an offline, cross-platform application for recording a DBS
programming visit as it happens, and writing it to a documented, tab-separated,
BIDS-compliant [@Gorgolewski2016] `_beh.tsv` file, with a JSON sidecar documenting
every column, that is directly usable for analysis. It captures
per-configuration stimulation parameters, including current-steered splits across
segmented contacts; the clinical and session scale ratings taken at each
configuration; notes attached to the configuration that was active when they were
written; and
timestamps with UTC offsets. It also generates clinician-readable PDF and Word reports
for the patient record, so a session is documented once rather than twice.

# Statement of need

Options for documenting a DBS programming session fall into three groups, none of
which produces analysable data.

1. **Vendor clinician programmers** record the device state needed to stimulate. Their
   exports are proprietary, differ between manufacturers, and do not include the
   clinical ratings that make a parameter setting interpretable.
2. **Generic clinical documentation** - a note in the health record, or a spreadsheet -
   is free-form, so it is neither comparable between clinicians nor machine-readable.
3. **Purpose-built research capture** is usually a local script or spreadsheet
   template, unshared and unmaintained.

The consequence is that multi-site or longitudinal analysis of DBS programming
requires reconstructing sessions from notes, and that the temporal structure - which
configuration preceded which, how long after a change a rating was taken - is
generally unrecoverable.

`DBS Annotator` addresses this by making the analysis-ready file the *primary*
artefact rather than an export: it is written incrementally as the session proceeds,
and the clinical report is generated from it. Three design decisions follow from the
clinical setting.

**Offline and self-contained.** The application makes no network connection and
requires no account or server. Clinical environments cannot be assumed to have usable
network access, and patient data should not require it.

**One long-format file, openly documented.** Data is written with one row per
(configuration, scale), so the column set does not change when a site rates a
different set of scales. A wide format would make the columns indication-specific and
obstruct pooling across cohorts. The complete column contract is published with the
software and is the same machine-readable file the application loads at runtime, so
the documentation, the application and the test suite cannot disagree.

**Explicit about what the data does not support.** The reports label the final
recorded block as the "last recorded configuration" rather than the chosen one,
because nothing in the record establishes that a clinician confirmed a choice. The
optional ranking of configurations refuses to run until the user has declared, per
scale, what direction constitutes improvement; an earlier version defaulted to "lower
is better" for every scale and thereby scored falling mood as improvement. The
generated reports state that the ranking uses recorded scale values only, and that no
scale anchors or rater identity are stored. They also surface the record's own
ambiguities - repeated ratings of an unchanged setting, and identical ratings under
different settings - rather than ranking through them.

# Implementation

`DBS Annotator` is written in Dart using the Flutter framework, giving a single
codebase for iPadOS, Android, Linux, Windows and macOS. Reports are generated in
process - PDF via the `pdf` package and Word by writing Office Open XML directly - so
no office software and no network service is required on the device.

The domain contract - TSV columns, filename grammar, stimulation limits, and the
geometry of 17 commercially available DBS leads - is held as machine-readable JSON that
is both loaded at runtime and asserted against by the tests.

The software was developed against, and validated by comparison with, an earlier
PySide6 implementation of the same file format, which is retained as a tagged
reference. Correctness-critical numerical output is pinned rather than smoke-tested:
the configuration-ranking index is asserted to specific values over a committed
synthetic example session, so a changed weight, bound or clipping rule fails a test
instead of
silently shifting a clinical ranking.

# Acknowledgements

<!-- TODO: funding sources, grant numbers, and contributors who are not authors. -->

# References
