# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.0] - 2026-11-14

### Added

- Combined table: several session TSVs in one BIDS derivative table with its JSON sidecar, and CI checks the BIDS output against the official BIDS validator. ([#175](https://github.com/neuromodulation/DBSAnnotator/pull/175))
- The Wyss Center logo and palette in the app and the docs, and the links in About open in the browser. ([#181](https://github.com/neuromodulation/DBSAnnotator/pull/181))
- Every entry is written to app storage as it is recorded, and a session interrupted by a crash or a closed window is offered back. One Reports and datasets screen, with each action enabled only when the uploaded files support it. Uploaded TSVs merge into an existing BIDS dataset, in place or as a merged zip, and a visit can be recorded straight into a dataset. ([#183](https://github.com/neuromodulation/DBSAnnotator/pull/183))
- Leaving a session asks whether to keep or discard its recovery copy, and adding to a dataset first checks that the folder is a BIDS dataset or an empty folder. ([#185](https://github.com/neuromodulation/DBSAnnotator/pull/185))
- Notes can be recorded straight into a dataset, with a Task field that names the file; a file name already taken moves to the next free run. The Reports screen offers what the number of uploaded files supports, explains each export, and adds a session or its report to a dataset. The TSV gains `is_final` and per-side lead columns, and exporting asks, optionally, who recorded and who rated, for the report's attestation. ([#191](https://github.com/neuromodulation/DBSAnnotator/pull/191))
- Named BIDS folders, one per cohort if you like, and pre-filled indication, target, leads and IPGs from a patient's last visit, all still editable. ([#202](https://github.com/neuromodulation/DBSAnnotator/pull/202))
- Saved configurations can be edited or deleted from the table, unsaved changes are flagged next to Save configuration, and rating bars shade from red to green by how good the value is. ([#203](https://github.com/neuromodulation/DBSAnnotator/pull/203))
- Reports are saved by default in the patient's derivatives folder of the BIDS folder, or where the last report went, and the session report header shows the run when it is not the first. ([#203](https://github.com/neuromodulation/DBSAnnotator/pull/203))
- A not-a-medical-device notice under every step and in every report, and a Close button on Finish. ([#203](https://github.com/neuromodulation/DBSAnnotator/pull/203))
- Every patient written into a BIDS folder, including one added from Reports, gets a derivatives/sub-<id>/ folder for reports. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))
- One IPG is shown by default, with Add IPG for a second one, one per lead. Each IPG has a position (left or right chest, left or right abdomen), saved in the new left_ipg_position and right_ipg_position columns and printed in the session report. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))

### Changed

- The app is rewritten in Flutter: one offline app for Windows, macOS, Linux, Android and iOS, tablets included. The PySide6/Qt desktop app is retired after 0.4.0; its code is kept on the `qt-legacy` branch. ([#161](https://github.com/neuromodulation/DBSAnnotator/pull/161))
- TSV format: one timestamp column, `session_id` renamed `append_id`, and no units on the steered amplitude columns. ([#175](https://github.com/neuromodulation/DBSAnnotator/pull/175))
- Reports use the brand palette, review text grows with the text size, and the docs gain an Outputs section. ([#182](https://github.com/neuromodulation/DBSAnnotator/pull/182))
- Renamed Wyss DBS Annotator. The reports' layout is reworked. ([#185](https://github.com/neuromodulation/DBSAnnotator/pull/185))
- Longitudinal report: Visits sits between the two figures, a day with notes but no session gets its own row and table, Source files lists every uploaded file, the scale targets ranked by are printed, and the file name carries the date. Which configuration the patient leaves on is asked at each export rather than on close. Dialogs show all of their text at any window and text size. ([#191](https://github.com/neuromodulation/DBSAnnotator/pull/191))
- Releases are tagged `vX.Y.Z` again, so GitHub release names read "Wyss DBS Annotator v0.6.0" instead of carrying an `app-` prefix. ([#194](https://github.com/neuromodulation/DBSAnnotator/pull/194))
- New and Open first ask what to do with the current session's recovery copy and do not replace a session while a save is still running, and leaving says when the recovery copy is the only copy before offering to delete it. On Android, as on iOS, an opened or newly created file is edited as a copy inside the app, and Export saves the changes. ([#199](https://github.com/neuromodulation/DBSAnnotator/pull/199))
- Adding files to a BIDS dataset from the Reports screen rebuilds the combined table under derivatives/dbs-annotator-aggregate from every recording in the dataset and lists it as rebuilt; a visit recorded straight into a dataset is added to the table by the next such merge. When a merge keeps backup copies in a dataset folder, the dataset's .bidsignore lists them, so the BIDS validator passes. ([#199](https://github.com/neuromodulation/DBSAnnotator/pull/199))
- PDF reports shorten a note too long for its table cell and print it in full in a Full notes section; Word reports keep the whole note in the table. The recorded rating is the value the slider shows, kept within the scale's range. ([#199](https://github.com/neuromodulation/DBSAnnotator/pull/199))
- Save-As for New and Export on the desktop now asks before replacing an existing file on Linux as well, adds a missing file extension, and reports a file it could not write instead of saving it to another folder. ([#200](https://github.com/neuromodulation/DBSAnnotator/pull/200))
- A visit recorded straight into a BIDS dataset now updates the dataset's combined table when the recording ends: on leaving the screen, closing the window, or starting or opening another file. ([#200](https://github.com/neuromodulation/DBSAnnotator/pull/200))
- Sessions are saved in a BIDS folder: one row per configuration in beh/ with a column per scale, visit details in sessions.tsv and the DBS indication in participants.tsv. ([#202](https://github.com/neuromodulation/DBSAnnotator/pull/202))
- The app opens directly on the programming session, whose Setup step holds every import and export; settings, theme and text size are in a side menu. ([#202](https://github.com/neuromodulation/DBSAnnotator/pull/202))
- Each run of a visit keeps its own initial assessment, in its row of the session's scans.tsv; a second run on the same day is saved as run-02 and starts from the first run's assessment. ([#203](https://github.com/neuromodulation/DBSAnnotator/pull/203))
- The DBS indication, target, leads and IPGs stay editable after configurations are saved, and a change is written into every saved row of the visit. ([#203](https://github.com/neuromodulation/DBSAnnotator/pull/203))
- A calmer look with one accent colour and clinical wording throughout (configurations, contacts, anode and cathode, symptom and side effect ratings), larger stimulation controls, and five steps: Session, Indication and devices, Initial assessment, Programming, Finish. ([#203](https://github.com/neuromodulation/DBSAnnotator/pull/203))
- Deleting a configuration moves the later ones up by one, so their numbers always match the saved file. ([#204](https://github.com/neuromodulation/DBSAnnotator/pull/204))
- The final settings are shown as their values per side (frequency, amplitude, pulse width) on Finish and when confirming them, instead of a configuration number. ([#204](https://github.com/neuromodulation/DBSAnnotator/pull/204))
- The patient ID, session ID, file naming and BIDS folder stay editable after a session starts. Changing them once a session holds entries starts a new session file, and the first one stays as saved. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))
- On the Session step, Visit is now Session ID, and the file naming fields are Task ID, Acquisition ID and Run ID, with their labels no longer cut off. Import reads the BIDS folder chosen at the top of the step. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))
- Notes reach down to the last scale beside them and are never shorter than Medications. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))
- Reports use calmer greens. Page 1 no longer lists what changed, and its ratings table prints values as entered, with a note that these are ratings taken during the visit, not a measure of treatment response. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))
- The report across visits ranks configurations within each visit rather than across visits. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))
- Parkinson's ratings are named plainly (Rigidity, right arm, 0 to 4), the default Parkinson's clinical scale is CGI-S, and the scale settings say that some scales need a licence and that you are responsible for the scales you use. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))
- The notice now says the app is not a medical device and does not carry a CE mark. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))

### Removed

- The opening page, the notes-only workflow and its report, and the raw TSV export. ([#202](https://github.com/neuromodulation/DBSAnnotator/pull/202))
- The append_id column is no longer written to the beh/ files or the combined table. ([#204](https://github.com/neuromodulation/DBSAnnotator/pull/204))
- Importing single session files or a zip: sessions are imported only from a BIDS folder. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))
- The licensed scales MDS-UPDRS, MDS-UPDRS Part III, UDysRS, PDQ-39 and BDI-II are no longer bundled; they can still be added by hand. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))

### Fixed

- The amplitude split no longer resets to 50/50. ([#183](https://github.com/neuromodulation/DBSAnnotator/pull/183))
- A wider Help dialog with a link to the user guide, and the window closes faster. ([#186](https://github.com/neuromodulation/DBSAnnotator/pull/186))
- A note is placed by its date, so a note from another day no longer appears inside a visit, and reports made from the Reports screen now draw the lead diagrams. ([#191](https://github.com/neuromodulation/DBSAnnotator/pull/191))
- The Microsoft Store package now has a white lock-screen badge, as Windows requires, instead of the full-colour icon. ([#195](https://github.com/neuromodulation/DBSAnnotator/pull/195))
- Merging into a dataset zip keeps every file, a participants.tsv or scans.tsv the app cannot read is left as it is instead of being rewritten, and a recording already in the dataset is not filed a second time. The combined table in a BIDS export names each recording by the run it was filed under, and cancelling Save-As saves nothing. ([#199](https://github.com/neuromodulation/DBSAnnotator/pull/199))
- PDF export no longer hangs on a long note, a session running past midnight shows both dates and keeps the second day's notes, and the report charts and the review charts on screen widen to show values outside a scale's set range. The split-amplitude total is rounded to 0.1 mA, and a block without a time is plotted once. ([#199](https://github.com/neuromodulation/DBSAnnotator/pull/199))
- A TSV that starts with a byte order mark keeps its first column when opened or merged, so a session or notes file keeps its timestamps and a participants.tsv its participant IDs. In Annotations, notes are saved even when the File step is skipped; a recovered session keeps its electrode model, and two sessions on the same day keep separate recovery copies. ([#199](https://github.com/neuromodulation/DBSAnnotator/pull/199))
- Opening a session or notes TSV with columns the app does not keep no longer drops them on the next save: the app names those columns, records into its own copy instead of the opened file, and on the desktop New and Export refuse that file as a target. ([#200](https://github.com/neuromodulation/DBSAnnotator/pull/200))
- A patient chosen from a BIDS folder is now recognised: the DBS indication is filled in from the last visit and kept when a session is reopened. ([#203](https://github.com/neuromodulation/DBSAnnotator/pull/203))
- The Linux download keeps one name across releases (dbs-annotator-linux-x64.tar.gz), so the one-line terminal install always fetches the latest version. ([#204](https://github.com/neuromodulation/DBSAnnotator/pull/204))
- A reopened visit shows its own initial assessment, and changing it edits that assessment instead of adding a second one to the file. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))
- Editing a saved configuration shows its own contacts on the lead diagram, so a tap can no longer save the previous contacts into it. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))
- In the reports, a starred configuration that ranks first is shaded like any other first-ranked configuration. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))
- Programming always starts from the initial assessment: after you go back and change it, or change a lead, Programming shows the new settings instead of the old ones. ([#205](https://github.com/neuromodulation/DBSAnnotator/pull/205))

### Security

- Android no longer includes the app's recovery copies and preferences in backups or device transfers, iOS and iPadOS leave the recovery copies out of iCloud and device backups, and the app deletes its own temporary copy of an exported file when the export ends. ([#199](https://github.com/neuromodulation/DBSAnnotator/pull/199))

## Qt app, after 0.4.0 (never released)

Work on the PySide6/Qt desktop app after its last release. It never shipped: the app
was rewritten in Flutter, whose first release is 0.6.0 above. The Qt code is kept on
the `qt-legacy` branch.

### Added

- Step 1: preset combo boxes for frequency, amplitude, and pulse width on left and
  right stimulation rows; gear button edits preset lists (stored in
  ``setting_presets.json``).
- Documentation screenshots for **Edit Setting Presets** and **Edit Program Names**
  dialogs on Step 1.
- Read the Docs: **Help**, **Update available**, and **Release notes** dialog
  screenshots in ``quickstart.rst`` (Interface Overview).
- Read the Docs: single-session report walkthrough on ``output_format.rst``: per-section
  Word export screenshots (title, clinical scores, session scales chart/table,
  electrode diagrams, programming summary), downloadable example
  ``task-programming`` TSV under ``docs/_static/session_report_example/``, and a
  generated data table (``scripts/generate_session_report_example_docs.py``).
- Read the Docs: longitudinal report walkthrough on ``output_format.rst`` and
  ``longitudinal_report.rst``: per-section export screenshots (title, sessions
  overview chart/table, combined session-scale figure, programming summary); session
  data table and per-session electrode pages cross-reference the single-session
  examples where layouts match.
- Docs screenshot pipeline: capture Help, update-available, and release-notes
  dialogs (``WizardWindow._build_*`` helpers for non-blocking capture).

### Changed

- Read the Docs: standard sphinx-rtd-theme palette (dark grey sidebar frame,
  light content panel, default blue links/headings); explicit table/body text
  contrast on the light panel; browser tab favicon uses the app icon on an opaque
  white background (``scripts/generate_docs_favicon.py``); the landing-page logo
  keeps a transparent background; screenshots and figures
  capped at 65% width (centered) via ``docs/_static/custom.css``.
- Docs screenshot pipeline: wizard captures use 65% of the app's normal step window
  size (``WIZARD_SCREENSHOT_SIZE_RATIO`` in ``tests/docs/screenshot_helpers.py``)
  for denser, balanced full-window PNGs on RTD.
- ``output_format.rst``: session report sections illustrated step-by-step instead of
  a single composite screenshot.
- ``workflow_complete.rst`` and ``longitudinal_report.rst``: remove overview video
  links (media files were not shipped in the repository).
- Read the Docs: note on ``output_format.rst`` and ``longitudinal_report.rst`` that
  session and longitudinal report screenshots and example files are synthetic
  documentation only (not real clinical data).
- Read the Docs: new ``overview.rst`` (Getting Started): motivation and
  design; ``quickstart`` moved to User Guide; workflow-choice table shown
  without horizontal scroll.
- Read the Docs: ``faq`` contact section simplified; ``quickstart`` Help button
  label aligned with the UI; minor punctuation in ``output_format.rst``.

### Fixed

- Wizard window: top bar and native title bar no longer clip off-screen when the
  window is moved or resized on a smaller monitor; geometry clamping releases
  layout minimums so content scrolls inside the step area instead of forcing
  window height.
- Step 1: clinical scale scores are preserved when switching between clinical
  preset buttons and returning to a preset you already filled in.
- Read the Docs: replace removed Sphinx ``download`` directive (Sphinx 9) with a
  normal hyperlink for the example programming-session TSV download.
- In-app **Update now** on Windows: download ``install.ps1`` into a stable folder
  (``%TEMP%\dbs_annotator_update\``) instead of a short-lived temp file deleted
  immediately after launch, so PowerShell can run the script (fixes flash-and-close
  with no install when upgrading, e.g. from ``0.4.0b2`` to ``0.4.0``); pause the
  console when the installer fails so the error stays visible.
- Dependency audit: pin ``uv>=0.11.15`` (GHSA-4gg8-gxpx-9rph); upgrade ``pip`` to
  26.1.2 (PYSEC-2026-196, Briefcase transitive dep).
- Update checker: cache the certifi SSL context; unit tests stub SSL setup to
  avoid Windows CI timeouts in ``test_updater.py``.

## [0.4.0] - 2026-06-01

### Changed

- Step 1 clinical preset buttons scroll horizontally when they do not fit on one row.

### Fixed

- Wizard window: title-bar maximize and resize on steps 1+ (step 0 stays compact).
- Step 1 initial settings: vertical scrollbar in its own column; no overlap with electrode canvases.

## [0.4.0b2] - 2026-05-21

### Added

- In-app **Update now** on the update-available dialog: downloads and runs the
  platform install scripts (``install.ps1`` on Windows, ``install.sh`` on macOS /
  Linux) for the selected GitHub release tag, then prompts you to restart the
  app from the Start menu or applications launcher.
- **View release notes** on the same dialog opens full release notes (and a
  GitHub link) in a separate window.
- ``dbs_annotator.utils.auto_update`` with optional ``dry_run=True`` (PowerShell
  ``-WhatIf`` / ``install.sh --dry-run``) for maintainers to preview an install.
- Read the Docs: dark outer page background (matching the sidebar); browser tab
  favicon uses the application icon.
- Read the Docs screenshot pipeline: home screen (light and dark theme), clinical
  and session scales settings dialogs, and regenerated workflow captures at
  native resolution (HiDPI-aware screen grab, improved PNG settings).
- ``docs/_static/custom.css``: full-width RTD content; ``screenshot-full`` (wizard
  steps) and ``screenshot-native`` (home, dialogs) capped at each PNG's intrinsic
  width so dialogs are not upscaled on wide screens.
- ``COPYRIGHT_HOLDERS`` and ``APP_LICENSE_NAME`` in ``config.py`` (shared with
  documentation).
- ``APP_MAINTAINER`` in ``config.py``; **Help** dialog lists **Maintainer: Richard
  Köhler** under lead developer.

### Changed

- Clinical and session preset pill buttons grow to fit their full label (theme
  ``max-width`` cap removed).
- Step 1 and Step 2 scale name/value fields widen as needed to show the full text.
- **Help** dialog rewritten around the standard **Complete Workflow** programming
  pipeline, timestamped ``task-programming`` TSV output, and Word/PDF reports;
  notes that each stimulation configuration is saved and summarised in reports;
  copyright lists MGH, Wyss Center, and Charité; MIT license noted.
- Update-available dialog: removed the extra “don't notify automatically”
  checkbox (that preference stays under **Help** only); release notes are no
  longer inlined; use **View release notes**; **Open download page** removed in
  favour of **Update now**.
- Pre-release update notice: “If you encounter issues, please report them to …”.
- Annotations-only file step header title: **Clinical Annotations Setup** (was
  "Output File").
- Home screen buttons: **Complete Workflow** and **Annotations-only Workflow**.
- Annotations-only TSV column ``annotation`` renamed to ``notes`` (aligned with
  the Complete Workflow); legacy files with an ``annotation`` header remain
  readable and appendable.
- Read the Docs: ``workflow_session.rst`` renamed to ``workflow_complete.rst``;
  ``quickstart.rst`` documents launching the installed app (Start Menu / MSI /
  install script), all three workflows in home-screen order, and links to the
  full guides; ``index.rst`` Quick Overview matches the same order.
- ``workflow_complete.rst``: Step 0 file setup (**Open** / **New**, Session ID /
  Run ID); UI actions documented as **Insert** and **Close session**; only one
  overview video at the top of the page.
- ``workflow_annotations.rst``: dedicated ``task-notes`` schema (``date``, ``time``,
  ``timezone``, ``notes``); no merge of multiple TSV files; **Insert** /
  **Close Session**; overview video removed.
- ``longitudinal_report.rst``: single overview video at the top; **Create
  Longitudinal Report** button naming.
- ``output_format.rst``: ``task-programming`` vs ``task-notes`` / annotations
  workflow called out in filename convention; generated schema uses ``notes`` for
  annotations-only files.
- ``faq.rst``: TSV save path references Step 0 file setup.
- README **What It Does** aligned with RTD (four Complete Workflow steps, three
  workflows, link to ``workflow_complete.rst``); installation and Contributing
  sections unchanged.
- Documentation copyright: Massachusetts General Hospital, Wyss Center for Bio
  and Neuroengineering, and Charité Universitätsmedizin Berlin.
- Screenshot capture uses the app's responsive window geometry (step 0 compact,
  steps 1+ full workflow) instead of a fixed 1600×1000 frame.
- ``workflow_complete.rst``: drop standalone ``electrode_diagram.png`` (electrode
  UI is already visible in the Step 1 screenshot).

### Fixed

- Step 1 clinical preset buttons disappearing after adding a preset in settings
  (horizontal scroll strip sizing).
- Step 3 session settings: external vertical scrollbar column (same layout as Step 1;
  no overlap with electrode canvases).
- Dependency audit: pin ``idna>=3.15`` (GHSA-65pc-fj4g-8rjx); allow ``idna`` in
  ``exclude-newer-package`` so the fix is not blocked by the one-week cooldown.
- Dependency audit: pin ``uv>=0.11.15`` (GHSA-4gg8-gxpx-9rph).
- Update checker: HTTPS uses the ``certifi`` CA bundle (fixes failed or empty
  GitHub API responses in Briefcase MSI/ZIP on Windows); compares against
  ``APP_VERSION``; empty or invalid release data surfaces as errors instead of
  a misleading “no updates” dialog.
- Electrode diagram export: E0 to En labels no longer clipped on the left in PNG
  output (wider label box and export left padding in ``ElectrodeCanvas``).
- Docs screenshot pipeline: Windows ``QPixmap.save``/PNG compression; trim
  ``grabWindow`` shadow bar on wizard captures; remove duplicate
  ``electrode-canvas.png`` artifact.
- Read the Docs build: ``installation.rst`` SmartScreen cross-reference and
  label placement for Sphinx ``-W`` builds.

## [0.4.0b1] - 2026-05-08

### Changed

- Fixed Linux release raw-archive packaging in CI for Briefcase ``linux system`` builds by
  detecting package roots via ``usr/bin`` + ``usr/lib/dbs_annotator/app`` and archiving
  the ``usr/`` tree, ensuring the launcher is included in the uploaded raw tarball. ([#97](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/97))
- Windows install script is only `scripts/install.ps1`; removed `Install-DBSAnnotator.ps1` and updated references. ([#76](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/76))
- Persist deactivated Step 3 session scales as ``NaN`` in the session TSV and omit them from Word and PDF reports. ([#94](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/94))
- Refreshed ``uv.lock`` with upgraded dependencies (including security-related updates for
  ``pip`` and ``gitpython``). ([#95](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/95))

### Fixed

- Fix `install.ps1` when run with `iex`: move install into a nested function so `$PSCmdlet` binds; document `iex` vs script parameters (`& ([scriptblock]::Create((iwr …).Content))` or local `install.ps1`). ([#77](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/77))
- Simplify `install.ps1` and update README. ([#78](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/78))
- Fix `scripts/install.sh` for POSIX `sh` and Linux launcher paths (`bin/`, `dbs_annotator`). ([#79](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/79))
- Fix `scripts/install.sh` for POSIX `sh`, LF line endings, Linux launcher discovery (`bin/`, `dbs_annotator`), and clearer errors when a release raw `.tar.gz` lacks the Briefcase stub. Linux release workflow now selects the full `app/` tree (largest tree with `bin/`) for the raw archive. ([#80](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/80))

## [0.4.0a2] - 2026-04-22

### Added

- Add a Windows PowerShell installer (``scripts/install.ps1``) and README one-liner to install the portable release ``.zip`` from GitHub when the MSI is unsigned. ([#70](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/70))
- Add ``scripts/install.sh`` (curl/wget) to install from GitHub Releases on Linux x86_64 and macOS (raw ``.tar.gz`` when present, else ``.deb`` / ``.dmg``), with README and installation docs. ([#71](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/71))

## [0.4.0a1] - 2026-04-22

### Added

- Initial changelog scaffold following Keep a Changelog 1.1.0.

### Changed

- Deduplicate TSV schema docs by generating tables from code constants, add CI/pre-commit drift checks, and extend documentation automation with docs-touch/changelog gates, Release Drafter, and Read the Docs tag triggers. ([#51](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/51))
- Improve documentation automation and TSV schema generation. ([#52](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/52))
- Document PR-based releases (`scripts/release_prepare.py`, **CD - Prepare release PR** workflow), maintainer `docs/releasing.rst`, and Sphinx generated-dir guidance (`_autosummary`, `_generated`, `_static`, `_templates`). ([#55](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/55))
- Ship ``0.4.0a1`` alpha, space-free data/install paths (``WyssCenter`` / ``DBSAnnotator``), optional GitHub release update checks, upgrade-safe user config locations, and ``release_prepare.py --bump`` for prerelease and semver bumps. ([#62](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/62))
- Update checker compares all published GitHub releases for the highest applicable newer semver (including pre-releases), handles repos with no releases quietly, surfaces pre-release guidance with support links, and lets users turn off automatic update checks from Help or the notification. ([#63](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/63))
- Consolidate branding under `icons/logosimple/` for Briefcase and Qt, add `scripts/build_app_icons.py` to generate platform icon sizes from a single source PNG, and document Linux `linux system` icon requirements. ([#66](https://github.com/Brain-Modulation-Lab/DBSAnnotator/pull/66))
