Annotations only
================

Timestamped free-text notes and nothing else. Use it when there is no
stimulation data to capture, as in a clinic conversation or a follow-up call,
but the timing and the wording still matter.

Step 1: File
------------

.. figure:: ../_static/screenshots/annotations_file.png
   :alt: The Annotations workflow on its File step, with a patient ID and run
         entered
   :width: 100%

   The same File step as the complete workflow, minus everything that only a
   programming session needs.

Enter the patient ID, the task and the run number, then choose where to save.
The task is ``notes`` unless you name another, so the filename reads:

.. code-block:: text

   sub-01_ses-20260203_task-notes_run-01_beh.tsv

**New** offers the same two places as the
:doc:`complete workflow <complete_workflow>`: a **loose TSV**, or **into a
dataset**, with the same folder check, session label and confirmation. Filed
into a dataset, the notes land beside the visit's programming file in
``sub-<participant>/ses-<session>/beh/``, at the first note rather than when the
file is created, and get their own row in that session's ``scans.tsv``. A
programming session and its notes can therefore share one dataset, told apart by
their ``task-`` labels.

**Open existing TSV** loads a notes file. A notes file that has columns this app
does not keep, such as one a colleague added by hand, is handled as a session
file is: the app names the columns, never writes to that file, and saves your new
notes in its own recovery copy until you use **Export**, which writes the notes
without those columns under a name you choose. On the desktop, **Export** and
**New** refuse the file you opened as a target; on Android and iOS the opened
file is the app's own copy, so there is nothing to refuse. See
:doc:`complete_workflow` for the details.

Step 2: Notes
-------------

.. figure:: ../_static/screenshots/annotations_notes.png
   :alt: The Notes step with three inserted notes listed newest-first in a table
         of date, time and text
   :width: 100%

   Three notes inserted. The list is newest-first, which is right for typing.

Type an observation and insert it. Each insert is stamped with the instant you
pressed the button, offset included, and not with the moment the file is later
saved or exported.

Inserted notes are listed below the field so you can check what has been
recorded rather than trusting a confirmation message. Every insert is written to
the file immediately.

Output
------

Two columns, ``acq_time`` and ``notes``, with one row per note. The on-screen
list splits that single timestamp into a date and a clock time for reading; the
file keeps it whole. See :doc:`../output_format` for the column reference.

Both of those column names also appear in a programming session file, so the
notes format is a strict subset of the session format and the same tooling
reads either.

Reports
-------

**Export** produces a PDF or Word report, the raw TSV, or a
:ref:`BIDS dataset <bids-dataset-export>`.

The report is deliberately plain: a patient header, the session date taken from
the notes themselves rather than from the export clock, the notes in a
time-and-text table in the order they happened, and an attestation block with
**Recorded by**, which the export asks for and which may be left empty to sign
by hand. Page
footers carry the patient ID, session date and page number, so a page separated
from the rest is still attributable.

The on-screen list shows newest first, which is right for typing, while the
report is oldest first, which is right for reading a session back.
