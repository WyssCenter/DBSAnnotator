Quick start
===========

Opening the app
---------------

Launch Wyss DBS Annotator as you would any other app on the device. It opens on
:doc:`Annotate programming session <screens/programming_session>`, where a
session is recorded in four steps. Its first step, Setup, is also where you
import earlier sessions and export reports and BIDS folders.

New to the vocabulary (configuration, initial assessment, clinical and session
scales, BIDS)? See :doc:`glossary`.

The theme, text size and other settings are in the menu at the top left.

Your first session
------------------

The shortest useful path through
:doc:`Annotate programming session <screens/programming_session>`:

1. **Setup.** Choose the BIDS folder, pick or type the patient, and press
   **New session**. The app builds the BIDS filename for you and saves every
   entry into the folder from the first one onward.

2. **Initial configuration.** Record the state the patient arrived in: the
   electrode model, the settings currently programmed, and the baseline clinical
   scores. Insert it. This block is marked as the baseline and is excluded from
   "configurations tested" later.

3. **Session scales configuration.** Name the scales you will rate at every
   configuration, with their range. Disease presets fill this in with a tap.

4. **Recording.** For each configuration: set the parameters, select contacts on
   the lead diagram, rate the scales, add any note, and insert. Repeat.

Things worth knowing early
--------------------------

**Every insert is saved immediately.** There is no separate save step. Each
entry is written to your file and to a working copy inside the app, so a crash
or a closed window loses nothing: the next time you open the workflow, the app
offers the unfinished session back.

**Notes belong to a block.** They are attached to the
configuration that was active when you typed them, not to the session as a
whole, which is what makes it possible afterwards to say *which* setting caused
the paraesthesia.

**Scale targets are yours to set.** If you want the app to highlight the
best-scoring configurations, you must first say what "better" means for each
scale: lower, higher, or closest to a value. Until you do, no configuration is
ranked. This is deliberate; see :ref:`what-the-reports-do-not-say`.

**Text size and theme** are in the settings menu at the top left.

Getting the report
------------------

From the Recording step choose **Export** and pick PDF or Word. For a file
recorded earlier, import it on the Setup step (see :doc:`screens/import_export`)
and choose *Single session report*. You will be asked which sections to
include and can set the scale targets at that point. See :doc:`reports`.
