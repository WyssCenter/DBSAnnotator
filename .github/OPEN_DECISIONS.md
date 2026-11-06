# Open decisions

Six behaviour questions left open by the full review in PR 199. Each lists what the app does
today, what the docs claim, who is affected, the options and a recommendation. Once a question
is decided, record the decision in the table and implement it in the follow-up PR.

D and E change what is written into a patient record today, so they matter most.

| | Question | Recommendation | Decision |
|---|---|---|---|
| A | Rank a setting rated twice once? | Rank settings, within a visit | open |
| B | Report date when none is recorded | Say "date not recorded" | open |
| C | Legacy rows with a date but no time | Keep the date only | open |
| D | A side switched off | Write amplitude 0 | open |
| E | What New resets | Clear visit data, keep protocol | open |
| F | Must clinical scores be numbers? | Validate on entry, show old values | open |

Line references are to branch `fix/full-review` at commit `b430e00`.

## A. Ranking a setting rated twice

**Today.** Ranking is per block. `buildScalesChartSpec` (`lib/report/report_data.dart` ~847-914)
takes a `settingOf` map but never uses it; `computeAggregateIndex` and `rankBlocks`
(`lib/core/session/scale_scoring.dart`) score and rank each block on its own. The live charts
(`lib/report/entry_charts.dart`) and the longitudinal report (`lib/report/longitudinal_data.dart`)
do the same. In the bundled example, blocks 6 and 7 have identical settings: block 7 is banded
best and block 6 second best, so the second-best band repeats the best setting and the best
other setting (block 2) gets no band.

**Docs claim.** Code comments say "a configuration rated twice scores once and is banded once"
(`report_data.dart` ~1211) and "Blocks sharing a key are the SAME configuration rated more than
once, so they rank together" (~851). `docs/reports.rst` and `docs/screens/complete_workflow.rst`
speak of the best and second-best "settings" or "configurations".

**Affects.** Every ranked session report (PDF and Word), the live charts and table, and the
longitudinal report, whenever a setting is rated more than once. It changes what a filed report
shows (bands and the rank in the Index cell). The TSV contract is unchanged.

**Options.**

1. Rank settings: one score per setting (the mean of its repeats), every block of that setting
   shares its rank and band, and second best is a different setting. Group only within a visit
   (file and setting), since a repeat on another day is not a replicate. Needs a choice for the
   Index cell: the setting's mean, or the block's own value beside a shared rank. Touches
   `scale_scoring.dart`, `report_data.dart`, `entry_charts.dart`, `longitudinal_data.dart`, the
   docs legend and `report_graphics_test.dart`.
2. Keep ranking per block: delete the unused `settingOf`, fix the comments and say "blocks" in
   the docs. Small, but second best can still be the best setting again.
3. Rank per block, but take second best from a different setting. Small, harder to explain in
   the legend.

**Recommendation.** Option 1, by mean, within a visit. It is what the docs, the chart painter and
the already-computed `settingOf` intend, and today's second-best band tells the clinician nothing.

## B. Report date when no date is recorded

**Today.** When no row's `acq_time` parses, `sessionDate` falls back to the export date
(`report_data.dart` ~1121-1124). That date then appears as the session date in the PDF and Word
header, footer and title, identical to "Generated on", and it decides which notes count as part
of the session, so notes from the export day are pulled in. The notes report does the same
(`annotations_report.dart` ~99-103). The longitudinal report prints an empty date in its headings
and period line, and sorts undated visits first. A date-only `acq_time` (`2026-02-03`) or one
without seconds is also not read as a date.

**When.** Only for uploaded or opened files without a readable time stamp: hand-edited legacy
rows, external files with `n/a`. Rows the app writes are always stamped.

**Docs claim.** A comment at `report_data.dart` ~615 says taking the date from the export clock
made a report produced a fortnight later claim the session happened that day; the fallback
brings that back. The user docs say nothing about a missing date.

**Affects.** Session, notes and longitudinal reports made from such files. Rare, but the filed
report states a false date.

**Options.**

1. Print "date not recorded" wherever the session date appears, attach no notes by date, use the
   same wording in the longitudinal headings, and read date-only `acq_time` values. About five
   report files plus a test per report.
2. Fall back to a `ses-YYYYMMDD` label from the file name, marked as such. Only works when the
   label is a date.
3. Refuse to build the report. Too strict for an analyst who only needs the table.

**Recommendation.** Option 1. Never invent a date in a filed report.

## C. Legacy rows with a date but no time

**Today.** When a 0.4 `_events` row has a date but an empty or `n/a` time, the time becomes
`00:00:00` (`lib/core/session/timestamps.dart` ~38). A test pins it
(`test/timestamps_test.dart`, "a missing time defaults to midnight rather than failing"). A time
of `NaN` instead drops the date, which is inconsistent. The invented midnight then spreads:
the Time column shows 00:00:00, the row sorts first, the session span and gaps grow by hours,
and the value is written as if recorded into new `_beh.tsv` files on export or merge, into
`scans.tsv` and into the combined table.

**Docs claim.** The schema and `docs/output_format.rst` say the old date and time cells are read
into one `acq_time`; neither mentions midnight.

**Affects.** Only legacy files with a missing time, most likely hand-edited. Rare, but the
invented time reaches new files and reports.

**Options.**

1. Keep the date only: `acq_time` becomes `2026-02-03`, reports show no time and leave the row out
   of span and gaps, and `scans.tsv` writes `n/a` there because BIDS needs a full time. Treat a
   `NaN` time the same way. Touches `timestamps.dart`, `session_row.dart`, `annotation.dart`,
   `bids_export.dart`, the schema text and the tests.
2. Write no `acq_time` when the time is missing. Loses the recorded date.
3. Keep midnight and warn on load. The invented time still spreads into exports.

**Recommendation.** Option 1. It keeps exactly what was recorded and never invents a time.

## D. A side switched off

**Today.** Each side has an on/off checkbox in the session screen
(`lib/ui/session_screen.dart`, `_SideInputs.enabled`). It only changes the display: the card
says "(off)", the lead drawing is dimmed and stops taking taps. `_stimCells` ignores it, so an
off side still writes its frequency, contacts, amplitude and pulse width as if it were on. The
TSV has no "off" marker, so reports, charts, ranking, the combined table and the setting key all
treat that side as stimulating. Two blocks that differ only by one side being off count as the
same setting.

**Docs claim.** Nothing; the checkbox is not documented.

**Affects.** Every block recorded with a side switched off, which is common when testing one
side at a time. The filed report states stimulation that was not delivered.

**Options.**

1. For an off side, write amplitude `0` and keep the contacts, frequency and pulse width: the
   program stays, the output is 0 mA, and reports can show it as off. The setting key then
   differs, as it should. No column change. Touches `session_screen.dart`, the schema's amplitude
   text, `docs/screens/complete_workflow.rst`, a report wording change and a widget test.
2. Write `n/a` in all five cells. Simple, but "off" then looks like "not recorded" and the side
   disappears from the report.
3. Keep writing the values and document the checkbox as a display aid. Leaves the record wrong.

**Recommendation.** Option 1. It records what was delivered and stays distinct from missing data.

## E. What New resets

**Today.** In the session screen, New clears the recorded rows, the file and working-copy paths
and the save flags, and goes back to the first step. It keeps the task, the electrode models,
both sides' stimulation (contacts, values, split, on/off), the program, the clinical scale names
and scores, the session scales with their bounds and slider values, the baseline and recording
notes, and the "patient leaves on" choice. Because the recording step is not seeded again,
inserting a baseline right after New writes the previous patient's scores, notes and stimulation
into the new file. The notes screen keeps the task and the unsent note text. Leaving the screen
and coming back starts fresh. The docs describe only the file choice, and no test pins what
carries over.

**Affects.** Anyone pressing New for the next patient without leaving the screen. Risk of one
patient's data in another's record.

**Options.**

1. Clear what belongs to the visit, keep what belongs to the protocol. Clear: clinical scores
   (keep the scale names), both notes, both sides' stimulation, the seeding flag, the "leaves on"
   choice, the program, the session-scale slider values and omitted flags, and the unsent note
   text. Keep: task, session-scale definitions and targets, electrode models. One helper per
   screen and a widget test that inserts a baseline after New and finds nothing carried over.
2. Clear only measured values (scores, notes, "leaves on") and keep the stimulation, for
   continuity within one patient's day.
3. Ask at New whether to carry over the previous settings.

**Recommendation.** Option 1. Carrying data into another patient's record is the worse failure,
and a second run for the same patient is usually started with Open.

## F. Must clinical scores be numbers?

**Today.** The baseline clinical score is a text field with a numeric keyboard hint but no
validation; the value is written as typed (trimmed) into `scale_value`, and a comma decimal is
not converted, unlike the session scales. A blank score drops the scale from the baseline. The
session report prints the value as typed. The longitudinal report parses it as a number and
silently skips anything else, so `12,5`, `ca. 20` or `-` vanish from the clinical figure and the
Visits table. Ranking never uses clinical scores. The combined table passes the value through.

**Docs claim.** The schema types `scale_value` as a string, "or `n/a` when the scale was not
assessed". `docs/output_format.rst` shows an analysis that assumes numbers. Nothing says the
value must be numeric.

**Affects.** New baseline entries (especially with comma decimals or free notes such as
"20 (on meds)"), uploaded and legacy files, and the longitudinal report, which can omit a
recorded score without saying so.

**Options.**

1. On entry: read a comma as a decimal point, refuse to insert a baseline with a non-numeric
   score (as out-of-range stimulation is refused), optionally warn outside the scale's range. For
   existing files: the longitudinal report prints a non-numeric value as written and notes that
   it is not plotted. The schema type stays string (legacy cells and `n/a`), with "a number, or
   `n/a`" in the description. Consider writing a blank score as `n/a`, as session scales do.
2. Allow free text on purpose: every report shows the value as written and plots numbers only.
   Needs a schema and docs statement; analysts' numeric pivots break.
3. Validate on entry only; the longitudinal report keeps dropping old non-numeric values.

**Recommendation.** Option 1. Scores are totals of validated instruments and analysts need
numbers, while values already recorded must be shown, never dropped.
