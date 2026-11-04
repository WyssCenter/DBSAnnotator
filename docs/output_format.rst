Data files (TSV and BIDS)
=========================

Everything the app records is written as **tab-separated text**, with a JSON
sidecar beside it describing every column. There is no proprietary container, no
binary blob and no export step that can silently drop a field: what you see in
the file is what was recorded.

Filenames
---------

Filenames follow the `BIDS <https://bids.neuroimaging.io/>`_ entity convention:

.. code-block:: text

   sub-<subject>_ses-<session>_task-<task>_run-<NN>_beh.tsv
   sub-<subject>_ses-<session>_task-<task>_run-<NN>_beh.json

The session label is the visit date (``YYYYMMDD``) unless you give another one,
such as ``preop`` or ``3mo``, when recording into a dataset.

with two task values:

``task-programming``
   A full session: stimulation parameters and scale ratings per configuration.

``task-notes``
   An annotations-only session: timestamped free text, nothing else.

For example:

.. code-block:: text

   sub-01_ses-20260203_task-programming_run-01_beh.tsv
   sub-01_ses-20260203_task-notes_run-01_beh.tsv

``run`` distinguishes several sessions on the same day and defaults to ``01``. It
is an *index*, so it is reduced to digits and zero-padded. The subject label is
sanitised to alphanumerics, so a typed ``/`` or ``..`` cannot escape into the
path.

.. note::

   Files written by version 0.4 (the earlier desktop application) end in
   ``_events.tsv`` and spell three columns ``block_ID``, ``session_ID`` and
   ``program_ID``. They open as they are.

Row shape
---------

The session file is in **long form: one row per (block, scale)**.

A *block* is one stimulation configuration. If five scales are rated at a
configuration, that block contributes five rows, and each of them repeats that
block's stimulation values. This is deliberate, and it is the single most
important thing to understand about the format:

.. include:: _generated/example_rows.inc.rst

.. _why-long-not-wide:

Why long and not wide
~~~~~~~~~~~~~~~~~~~~~

One row per block with a column per scale looks tidier and is worse. The column
set becomes indication-specific, because an OCD session and a Parkinson's
session rate different things, so pooling the two needs an outer join on
mismatched headers, and adding a scale mid-study changes the header of every
file written from then on.

In long form, a site using different scales simply writes different *rows*, and
everything pools with a concatenation. It is also the shape that pivots without
reshaping:

.. code-block:: python

   import pandas as pd

   df = pd.read_csv(path, sep="\t", na_values=["n/a"])
   wide = df.pivot_table(
       index=["append_id", "block_id"],
       columns="scale_name",
       values="scale_value",
   )

Which rows are which
~~~~~~~~~~~~~~~~~~~~

``is_initial`` separates the two kinds of entry:

``is_initial = 1``
   The **baseline** block: the clinical assessment and the settings the patient
   arrived on, recorded before any configuration is tried. Excluded from
   "configurations tested" and from the tested-parameter ranges in reports.

``is_initial = 0``
   A **recording** block: one configuration that was tried and rated.

``is_final = 1`` marks the rows of the recording block the patient was left on
at the end of the visit, as the clinician marked it; every other row is ``0``.
At most one block carries it, and none does when the clinician did not say.
Files written before the column existed leave it empty, and read as unmarked.

Each lead has its own model column, ``left_electrode_model`` and
``right_electrode_model``, filled with the same name when both leads are the
same model. Older files have one ``electrode_model`` column, which is read as
the model of both.

.. warning::

   Read ``is_initial`` numerically, not as a truthy string. Some files write
   ``0.0``/``1.0``, and ``df.is_initial.astype(bool)`` is ``True`` for the
   *string* ``"0.0"``, which silently moves the baseline into the tested set.
   Use ``df.is_initial.astype(float).eq(1)``.

Omitted ratings
~~~~~~~~~~~~~~~

A scale that was not assessed at a block is written as ``n/a``, which is what
BIDS requires for a missing or non-applicable value. Read it with:

.. code-block:: python

   df = pd.read_csv(path, sep="\t", na_values=["n/a", "NaN"])

Files written by version 0.4 use ``NaN`` instead.

Timestamps
----------

Every row carries **one** time cell:

.. code-block:: python

   df["when"] = pd.to_datetime(df.acq_time)   # tz-aware, ISO-8601, one line

``acq_time`` is the whole instant with its UTC offset
(``2026-02-03T09:00:00+00:00``), and it is BIDS' own name for a timestamp
column, used in ``scans.tsv`` and ``sessions.tsv``.

.. note::

   Files written by version 0.4 store the timestamp in three cells,
   ``date``, ``time`` and ``timezone`` (for example
   ``W. Europe Daylight Time +0200``). The app reads them as one ``acq_time``.
   Reading such a file directly with pandas:

   .. code-block:: python

      when = pd.to_datetime(df.date + " " + df.time)
      offset = df.timezone.str.extract(r"([+-]\d{4})")[0]

.. warning::

   ``acq_time`` is an *instant*, and rendering an instant picks a timezone. A
   block recorded at ``09:00:00+01:00`` in Geneva is ``03:00`` in Chicago: the
   same moment on a different clock. If you want the time the event happened
   **at the clinic**, read the wall clock out of the string rather than
   localising it:

   .. code-block:: python

      # the clinic's own clock, whatever timezone you are reading in
      clinic_time = df.acq_time.str.slice(11, 19)

      # the instant, for ordering and for measuring intervals
      when = pd.to_datetime(df.acq_time)

   The app makes the same distinction internally: reports and tables print the
   recorded wall clock, while sorting and interval arithmetic use the instant.

Amplitudes and current steering
-------------------------------

``left_amplitude`` and ``right_amplitude`` hold either a single value
(``4.5``) or, when current is shared across several cathodes, the per-contact
values joined by an underscore in cathode order:

.. code-block:: text

   left_cathode     E2b_E2c
   left_amplitude   3.3_2.2      -> 5.5 mA total, 60 % / 40 %

The split is part of the configuration, not a detail: ``3.3_2.2`` and
``2.2_3.3`` across the same two contacts stimulate different tissue. To recover
the delivered dose:

.. code-block:: python

   total = df.left_amplitude.astype(str).str.split("_").apply(
       lambda parts: sum(float(p) for p in parts if p)
   )

Contacts are written in the app's token grammar: ``case`` for the can, ``E2``
for a ring contact, ``E2b`` for one segment of a segmented level, and ``_`` to
join several. ``E2b_E2c`` therefore means two segments of level 2 are active.

This grammar is documented in the JSON sidecar as well as here, because the
sidecar is where a downstream tool will look.

Session columns
---------------

.. include:: _generated/session_columns.inc.rst

Annotations columns
-------------------

.. include:: _generated/annotation_columns.inc.rst

The JSON sidecar
----------------

Every TSV is written with a ``_beh.json`` beside it, carrying one entry per
column with a ``LongName``, a ``Description`` and, where the column has a
physical unit, ``Units``. It is generated from the same contract as the tables
above, so the two cannot disagree.

.. include:: _generated/sidecar_example.inc.rst

The full sidecar carries one such entry per column in the tables above.

.. _bids-relationship:

Relationship to BIDS
--------------------

These files are BIDS files, not only BIDS-*named*: the entities in the
filename, the datatype directory, the suffix and the sidecar are all what the
specification asks for.

.. _bids-naming:

Naming
~~~~~~

The suffix is ``_beh`` and the files sit in a ``beh/`` datatype directory: the
BIDS suffix for behavioural data recorded without an accompanying imaging or
electrophysiology recording.

Columns are in snake_case, as BIDS recommends (``block_id``, ``append_id``,
``program_id``), a missing value is ``n/a``, the timestamp is one ``acq_time``
cell, and lines end in LF.

``append_id`` counts **data-entry episodes within one file**: it goes up each
time that file is reopened to add rows. It is file-scoped, so ``append_id`` 1 in
two different files are unrelated. It is not ``session_id``, which BIDS uses for
the ``ses-`` label.

.. note::

   Files written by version 0.4 open without conversion. Files written by this
   version cannot be read by version 0.4.

.. _bids-dataset-export:

Exporting a dataset
~~~~~~~~~~~~~~~~~~~

A single file with BIDS entities in its name is still not a BIDS *dataset*. The
specification wants a tree, and **Export → BIDS dataset** produces one as a zip,
from any of the three screens that hold session data:

.. code-block:: text

   dataset_description.json
   README
   participants.tsv
   participants.json
   sub-01/
     ses-20260203/
       sub-01_ses-20260203_scans.tsv
       beh/
         sub-01_ses-20260203_task-programming_run-01_beh.tsv
         sub-01_ses-20260203_task-programming_run-01_beh.json

The reports screen is the useful place to do this: it holds several visits of
one patient, which is what the ``sub-``/``ses-`` hierarchy is for.

Reports are derived documents, so they belong under ``derivatives/`` rather than
beside the raw data, and are written there with their own
``dataset_description.json`` rather than being given invented raw-data
filenames.

.. _combined-table:

The combined table
~~~~~~~~~~~~~~~~~~

One file per visit is right for recording and awkward for analysis: pooling a
patient's visits, or several patients for a study, means concatenating a folder
of files and losing the one thing that told their rows apart, the filename.

**Combined table (TSV)**, on the reports screen, writes the
imported files as one long table with four identity columns prepended, and
its ``.json`` sidecar beside it (see :doc:`screens/reports` for where both are
saved):

.. code-block:: text

   participant_id  session_id     run_id  source_file                       ...
   sub-01          ses-20260203   01      sub-01_ses-20260203_..._beh.tsv   ...
   sub-07          ses-20260401   01      sub-07_ses-20260401_..._beh.tsv   ...

The twenty-one session columns follow unchanged, which makes twenty-five in
all. A notes file contributes one row per note, with only ``acq_time`` and
``notes`` filled and every other session column ``n/a``, so its rows are the
ones with no ``block_id``. So:

.. code-block:: python

   df = pd.read_csv(path, sep="\t", na_values=["n/a"])
   df.groupby(["participant_id", "session_id"]).size()

``participant_id`` uses the BIDS spelling and the BIDS value shape deliberately,
so the table joins onto ``participants.tsv`` with no transformation.

A block is unique across the table on ``(source_file, block_id)``, and a note
row has no ``block_id``, so it belongs to no block. ``source_file`` is a key
column rather than a convenience: ``run`` defaults to ``01`` and does not
auto-increment, so two visits on the same day can share all three entities
above, and the filename is then the only thing that separates their rows.

.. note::

   ``session_id`` here is the **BIDS session label**, as ``sessions.tsv`` means
   it. The per-file counter is in the table too, under its own name
   ``append_id``: it counts data-entry episodes within one source file, so
   equal values under different ``source_file`` entries are unrelated.

Inside a BIDS dataset the same table is a **derivative**, because a table
spanning sessions cannot sit in a tree defined as one file per session:

.. code-block:: text

   derivatives/dbs-annotator-aggregate/
     dataset_description.json     DatasetType: derivative
     desc-aggregate_beh.tsv
     desc-aggregate_beh.json      every column documented

Two things it will not do, and says so rather than doing them quietly: a file
whose name carries no ``sub-`` or ``ses-`` entity is left out and named, because
guessing entities would put a wrong subject label on clinical data; and the same
filename twice is refused rather than concatenated, because duplicate rows
double every count derived from the table with nothing on the face of it to show
why.

A combined table saved into a dataset for chosen files is replaced by the next
merge from the Reports screen, which rebuilds it from every session and notes
file the dataset holds. Recording a visit straight into a dataset does not touch
the table, so it stays as it was until that merge. The previous copy is kept
beside it with a ``.bak-`` suffix when the dataset is a folder.

Notes files join this table one row per note, with only ``acq_time`` and
``notes`` filled. Grouping by ``block_id`` therefore leaves them out, since their
``block_id`` is ``n/a``; select them with ``df.block_id.isna()`` when you want
them.

What is still not standard
~~~~~~~~~~~~~~~~~~~~~~~~~~

The columns themselves. Of the twenty-one in a session file, only ``notes`` and
``acq_time`` resemble anything BIDS defines; ``block_id``, ``left_cathode``,
``left_amplitude`` and the rest are this application's own. That is permitted,
since BIDS allows additional columns and asks that they be documented in a
sidecar, which is what the ``_beh.json`` is for, but it does mean no generic
BIDS tool will understand what a *block* is. Read this page, or the sidecar.

The placement of the combined table is the part with the least precedent: a
``desc-``-only filename at a derivative root has no ``sub-`` entity, because the
table deliberately spans subjects. ``desc-`` is the entity BIDS provides for
naming a derivative variant, and dataset-level files do exist, so the shape is
idiomatic, and it passes the BIDS validator.

Worked example
--------------

The file used throughout this documentation, and in the app's own test suite, is
**synthetic**. Every rating, stimulation parameter and timestamp in it is
invented, and no recorded session went into it, which is why it can be
published here at all. It is generated by ``tool/generate_fixtures.dart``, whose
comments explain the structure the tests depend on. It describes a visit with a
baseline block, seven configurations tried after it, and five session scales
rated at each:

:download:`sub-01_ses-20260203_task-programming_run-01_beh.tsv
<_generated/sub-01_ses-20260203_task-programming_run-01_beh.tsv>`
