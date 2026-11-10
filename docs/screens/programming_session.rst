Annotate programming session
============================

Every time it starts, the app shows that it is not a medical device and asks
you to confirm you have read it. The same line stays under every step,
in the bar with **Back** and **Next**, and every report carries it.

The app opens on this screen. A programming session is recorded in five steps,
Session, Indication and devices, Initial assessment, Programming and Finish,
with **Back** and **Next** at the bottom of the screen. The menu button at the top left opens the
:ref:`settings menu <settings-menu>`.

.. raw:: html

   <video controls muted playsinline preload="metadata" width="100%"
          poster="../_static/videos/record_block.png">
     <source src="../_static/videos/record_block.mp4" type="video/mp4">
   </video>

A visit: a new file, the stimulation parameters, the
lead, the clinical scales, then three configurations rated and inserted, with
the charts and table below.

.. _setup-step:

Step 1: Session
---------------

Session is where a visit starts and where every file goes in or out.

**BIDS folder.** Every visit is saved inside a BIDS folder, chosen in the bar
across the top of the step. You can keep several, for example one per cohort, and pick the
default in the settings menu. The folder must be a BIDS folder this app or
another tool wrote, or an empty folder to start one in (see
:ref:`what counts as a BIDS folder <bids-folder-requirements>`).

**Patient.** Pick a patient already in that folder, or type a new patient ID.
For a known patient the app fills in the DBS indication, the anatomical target,
the leads and the IPGs from the patient's last visit, and says so on the next
step. Check each
value: a reimplantation changes the target, the leads or the IPG, and every
field stays editable.

Enter the **session** label, the **task** and the **run number**. The session is
the visit date unless you type another label such as ``preop`` or ``3mo``. The
task is ``programming`` unless you name another; whatever you type becomes the
``task-`` part of the :doc:`BIDS filename <../output_format>`. Like every BIDS
label they keep letters and digits only.

**New session** starts the visit in the chosen folder. When that name is
already taken, the visit is saved under the next free run (``run-02``,
``run-03``) and the **Run** field changes to match. Nothing is overwritten. The
visit is written into the folder at the first entry and kept up to date at
every entry after that: its ``beh/`` file, its row in the patient's
``sessions.tsv``, the patient's row in ``participants.tsv`` and the session's
``scans.tsv`` (see :ref:`where-values-live`).

**Open saved session** continues a visit already in a BIDS folder, or opens a
session file from an earlier version, which is saved in the current form from
the next entry.

**Other sessions**, beside this session, reads session files or a whole BIDS
folder and produces reports across visits, the combined table and BIDS
folders; see :doc:`import_export`. Once this visit has entries, **Export this
session** offers its own report and its BIDS folder (zip), as Finish does.

**Every entry is also written to a working copy inside the
app** as you record, so a crash or a closed window loses nothing. When you leave
the workflow, or close the app window on Windows, macOS or Linux, the app asks
whether to **keep** that copy or **discard** it. Kept, it is offered back the next
time you open this workflow; discarded, it is gone and nothing is offered. It is
never deleted without that answer: after a crash, or when a tablet or phone app is
swiped away, the copy is always kept.

.. figure:: ../_static/screenshots/dialog_keep_recovery.png
   :alt: The question on leaving: keep or discard the recovery copy
   :width: 42%
   :align: center

   Asked when you leave the workflow or close the window.

When a copy was kept, the next time you open the workflow it is offered back:

.. figure:: ../_static/screenshots/dialog_reopen_unfinished.png
   :alt: The offer to reopen an unfinished session, with Discard and Reopen
   :width: 42%
   :align: center

   Reopen continues the session; Discard deletes the copy. Closing the dialog any other way keeps it for next time.

**Open existing TSV** loads a session recorded earlier, and appends to it. The
status line under the buttons reports what was found: the row count, the next
block number, and the append number (``append_id`` in the file: how many times
it has been reopened to add blocks), so an append is never a guess. Opening a
file also adopts the **electrode models named in that file**, one per side, so
the lead diagrams show the patient's actual hardware rather than whatever the
dropdown last held. If the file names a model that is not in the catalogue, the
app says so rather than drawing the wrong lead.

A file that is not a programming session, an annotations file for instance, is
refused with an explanation rather than loading as empty rows.

A session file can carry columns this app does not keep: one added by hand or by
another tool, a header name that appears twice, a value under a blank header, or a
row with more cells than the header. The app writes only the columns of the
format, so saving over such a file would delete that data. When **Open existing
TSV** finds any, the message names them (for example *The app does not keep these
columns: lab_flag. Your file is left unchanged.*) and the app never writes to
that file. You can still add blocks: every insert is saved in the app's own
recovery copy, as for a new session that has not been exported yet, so leaving
the screen asks whether to keep that copy. A line beside **Export** repeats the
names of the unkept columns for as long as the file is open. **Export**
then saves the session without them, under a name you choose, and on the
desktop refuses the file you opened as a target, as does **New**. On Android
and iOS the opened file is the app's own copy of your file, so there is nothing
to refuse. Opening another file, or starting
or reopening a session, ends this mode. Older files that spell a column the way
earlier versions did, such as ``block_ID`` or a separate ``date``, ``time`` and
``timezone``, are read as before and do not count as unkept.

.. _settings-menu:

Settings menu
-------------

The menu button at the top left opens the settings that apply to every
session: the BIDS folders, the DBS indications and anatomical targets offered
in Indication and devices, the leads and IPGs, the stimulation defaults and programs, the
clinical scales and session ratings presets, the scale targets, the report
sections, the theme and text size, and help. The theme and text size are kept
for the next time the app opens.

Step 2: Indication and devices
------------------------------

The patient's **DBS indication** and **anatomical target**, and the implanted
devices. The indication chooses the clinical scales and session ratings that
the next steps start from.

**Leads.** Choose the implanted lead. The catalogue covers Medtronic,
Boston Scientific, Abbott, PINS and ALEVA leads, including segmented
(directional) models. The diagrams are drawn to each lead's real contact heights
and spacings, so two different leads look different. **Same lead on both
sides** is ticked by default; untick it when the two leads differ, and a second
menu sets the right lead. Each side's model is written to its own column.

**Implanted pulse generator (IPG).** The same choice for the IPG, one per side
when they differ.

Once the visit has entries, these values are fixed for that visit.

Step 3: Initial configuration
-----------------------------

The state the patient arrived in, before anything is changed.

.. figure:: ../_static/screenshots/session_step1_config.png
   :alt: Initial configuration: electrode model, program, per-side parameters
         and amplitude split on the left, lead diagrams on the right, clinical
         scales and notes below
   :width: 100%

   Step 3 with a baseline configuration entered: current steered across two
   segments of level 2 on the left lead, and the OCD clinical scale set.

**Parameters, per side.** Frequency, amplitude and pulse width, with quick-pick
presets. When more than one cathode is active, an amplitude split appears so you
can set the percentage per contact. Those are the ``E2b`` and ``E2c`` rows in
the screenshot above, each showing the milliamps its share works out to.

**Clinical scales.** The baseline assessment: disease-specific scores such as
Y-BOCS or UPDRS-III. Disease presets fill the list in with a tap.

**Notes.** Free text. Unlike the recording step, these persist after inserting,
so you can keep refining the baseline description.

It is saved as the visit's row in ``sessions.tsv`` when you move on.

Several cards have a gear that edits the choices they offer. These are
**presets**: they apply to every future session and live in the app's own
preferences, never in a session file, so editing one changes nothing already
recorded. The dialogs below are the ones you meet in this step.

.. _dialog-programs:

Programs
~~~~~~~~

.. figure:: ../_static/screenshots/dialog_programs.png
   :alt: The Programs dialog, a simple editable list of program labels
   :width: 36%
   :align: center

Opened by the gear beside the **Program** card in steps 3 and 4.

The program labels offered by the dropdown: ``A``, ``B``, ``C``
and so on, or whatever your centre uses. Stored as a preset, so the list you
build is there next session.

.. _dialog-parameter-presets:

Parameter presets
~~~~~~~~~~~~~~~~~

.. figure:: ../_static/screenshots/dialog_parameter_presets.png
   :alt: The parameter presets dialog with tabs for Frequency, Amplitude and
         Pulse width
   :width: 40%
   :align: center

Opened by the gear beside **Parameters** in steps 3 and 4.

The quick-pick chips under each stimulation field, one tab per parameter. These
are shortcuts, not limits: each field accepts any value within the permitted
range for that parameter, whether or not it is in this list.

A value that is not a number, or that falls outside the permitted range, is
refused with the reason shown in the dialog rather than being silently dropped.

.. _dialog-clinical-scales:

Clinical scales settings
~~~~~~~~~~~~~~~~~~~~~~~~

.. figure:: ../_static/screenshots/dialog_clinical_scales.png
   :alt: The clinical scales settings dialog, a group list on the left and the
         selected group's scale names on the right
   :width: 50%
   :align: center

Opened by the gear on the **Clinical scales** card in step 3.

Edits the disease preset buttons for the baseline assessment: the group names
(OCD, MDD, PD, ET, Dystonia, TS), the scale names inside each, and each scale's
**Min** and **Max**. The range is optional and is used only to draw the
longitudinal report's clinical figure on the scale's own axis; it is never
printed. The bundled scales come with their published total ranges where a name
identifies one instrument (Y-BOCS 0 to 40, MADRS 0 to 60, and so on). Names that
stand for more than one, such as HAM-D, UPDRS-III or MDS-UPDRS, are left blank
for you to fill in.

Selecting contacts
~~~~~~~~~~~~~~~~~~

Tap a contact to cycle it from off, to anode, to cathode, and back to off. Tap
the case to use it as the return. Segmented levels show their three segments
plus a *Ring* strip that activates the whole level at once.

.. figure:: ../_static/screenshots/session_electrodes.png
   :alt: Both leads with a valid configuration, each pane reporting
         "Configuration valid" in green, above the polarity key
   :width: 100%

   A valid configuration: two segments of level 2 as cathodes on the left, a
   ring contact on the right, the case as the return on both.

Invalid combinations are applied anyway and flagged as you build them, so you can
work through a configuration in whatever order suits you rather than having edits
rejected mid-way:

.. figure:: ../_static/screenshots/session_electrodes_invalid.png
   :alt: The left pane showing a red "Invalid" box because the cathodes have no
         return path
   :width: 100%

   The same cathodes with no return path selected. The change is kept; the pane
   says why it will not stimulate.

Narrow screens
~~~~~~~~~~~~~~

Below about 900 logical pixels (a phone, or a tablet held in portrait) the two
rows stack into one column. Everything is present; there is simply more
scrolling.

.. figure:: ../_static/screenshots/session_step1_narrow.png
   :alt: The same step in a single stacked column on a narrow screen
   :width: 100%

   Step 3 in the single-column layout.

Session scales configuration
----------------------------

.. figure:: ../_static/screenshots/session_step2_scales.png
   :alt: Session scales configuration with the OCD preset applied, one row per
         scale with a name, minimum and maximum
   :width: 100%

   The scale set that will be rated at every configuration.

Name the scales to be rated at *every* configuration, with a minimum and maximum
for each. Keeping the set fixed for the whole session is what makes the ratings
comparable between configurations.

Choosing a disease preset here, or having chosen one in step 2, fills the list.
The gear icon edits :ref:`the presets themselves <dialog-session-scales>`, which
persist between sessions. Nothing on this step is written to the file; it defines
what step 4 will ask for.

.. _dialog-session-scales:

Session scales settings
~~~~~~~~~~~~~~~~~~~~~~~

.. figure:: ../_static/screenshots/dialog_session_scales.png
   :alt: The session scales settings dialog, whose rows carry a minimum and a
         maximum as well as a name
   :width: 50%
   :align: center

Opened by the gear on **Session scales configuration** in step 3.

The same shape as the clinical dialog, with one difference: each row here also
carries a **minimum and maximum**. Session scales are rated on a slider at every
configuration, so they need a range; clinical scales are typed once, so they do
not.

Step 4: Programming
-------------------

The loop, repeated once per configuration tried.

.. figure:: ../_static/screenshots/session_step3_recording.png
   :alt: The Recording step: program, parameters and lead diagrams above; scale
         ratings and notes below, with the Insert button
   :width: 100%

   One configuration rated and ready to insert. *Energy* is marked not assessed.

Set the parameters and contacts as in step 2, then rate each scale. A scale that
was not assessed can be marked omitted, which writes ``n/a`` rather than a
made-up number. That is the grey bar with the crossed-out icon in the
screenshot above.

Anything observed at that configuration, a side effect included, goes in the
block's **Notes**, which belong to the configuration active when they were typed.

Insert to record the block. The notes clear, ready for the next one;
the parameters stay, so a single amplitude change is one edit rather than a full
re-entry.

**Patient leaves on this**, above the Insert button, marks the block being
inserted as the configuration the patient goes home with (``is_final`` in the
file). Each export, as a report, the TSV or a BIDS dataset, asks which block
that is, defaulting to the one marked, else the last, with **Not recorded** as
a choice. Leaving the workflow or closing the window does not ask, so a session
that is closed without being exported records no choice. Reports call a
configuration "left on" only when it was marked this way, and "last recorded"
otherwise.

Exporting a report also asks, optionally, who recorded the session and who
rated the scales. The names are printed in the report's attestation block and
saved nowhere else.

The same step in the dark theme:

.. figure:: ../_static/screenshots/session_step3_recording_dark.png
   :alt: The Recording step in dark theme
   :width: 100%

   Dark theme. The contact polarity colours are deliberately identical in both
   themes, because they are the safety-relevant part of the drawing.

Reviewing as you go
~~~~~~~~~~~~~~~~~~~

Below the entry area, everything inserted so far is shown two ways.

.. figure:: ../_static/screenshots/session_step3_charts.png
   :alt: Four stacked charts sharing one time axis: session scales, amplitude,
         pulse width and frequency, with a series key
   :width: 100%

   **Four charts** sharing one time axis: session scales, amplitude, pulse width
   and frequency.

The panels are aligned vertically, so a dip in a scale can be read against the
amplitude that preceded it. They scroll horizontally, showing the most recent
configurations by default, with zoom controls and drag handles to reorder the
panels.

**A table** of every entry sits below them, grouped by block. Values that belong
to the block (time, program, parameters) are printed once rather than
repeated on every scale row, and a heavy rule marks each block boundary. Once
scale targets are set, the rows of the best and second-best blocks are shaded in
the same greens as the charts, and the shading moves as each block is inserted.

**Scale targets** sets what "better" means per scale (minimise, maximise, or
closest to a value). Once set, the best- and second-best-scoring configurations
are shaded green across all four charts. Until set, nothing is ranked; see
:ref:`scale-targets`.

.. _dialog-scale-targets:

Scale targets
~~~~~~~~~~~~~

.. figure:: ../_static/screenshots/dialog_scale_targets.png
   :alt: The scale targets dialog, one row per scale with a minimum, maximum and
         a target mode
   :width: 47%
   :align: center

Opened by **Scale targets** in step 3, from the settings menu, or from the
report sections dialog.

Says what "better" means for each scale, which is the input the ranking needs and
the one thing only you can supply. **Set all: Min / Max** fills the column in one
tap for a set of scales that all run the same way.

Each scale gets a mode: ``Min``, ``Max``, ``Custom`` (closest to a stated value,
which reveals a *Value* field), or ``Ignore``. Until targets are set, no
configuration is ranked anywhere: see :ref:`scale-targets` for the definition of
the aggregate index and :ref:`what-the-reports-do-not-say` for its limits.

Exporting
---------

**Export** offers a PDF or Word report, the raw TSV, or the whole session as a
:ref:`BIDS dataset <bids-dataset-export>`. Paper size applies to both document
formats and is remembered between exports.

.. figure:: ../_static/screenshots/session_paper_size_submenu.png
   :alt: The Export menu open, listing PDF and Word reports, the raw TSV and a
         BIDS dataset, with the paper-size submenu showing A4 selected
   :width: 100%

   The Export menu, with the paper-size submenu open.

Choosing a report opens the report sections dialog first. See
:doc:`../reports` for what each section contains.

.. _dialog-report-sections:

Report sections
~~~~~~~~~~~~~~~

.. figure:: ../_static/screenshots/dialog_report_sections.png
   :alt: The report sections dialog, a checkbox and one-line description per
         section
   :width: 44%
   :align: center

Appears when you export a report, before the save dialog. Each report kind has
its own list, and the dialog title says which one you are choosing for:

* **Session report sections**: baseline, session scales figure, session data
  table, electrode configuration and programming summary.
* **Longitudinal report sections**: clinical scales by visit, visits table,
  session scales by visit and block, combined session data table, electrode
  configuration, programming summary and source files. The session data table,
  the electrodes and the programming summary start unticked, because they are
  the sections that add pages; tick them to include them.

Each section has a one-line description of what it adds. **Export** is disabled
while nothing is checked, because a report of a title page alone is not a
document anyone wants. **Scale targets…** opens the dialog above without losing
the selection, since the ranking those targets drive is what several of these
sections show.

The session report remembers its selection for the next export. The
longitudinal report opens with its defaults every time, so a section that adds
pages, ticked once, is not carried into every later report.
