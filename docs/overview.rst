Overview
========

Why this exists
---------------

Implanting the electrodes is the start of the treatment, not the end of it. The
patient returns to a neurologist or psychiatrist, who moves through a series of
stimulation configurations (contacts, amplitude, pulse width, frequency) and at
each one records how the patient is doing: tremor, rigidity, mood, side effects.
Finding a setting that works can take one visit or many, and it is revisited over
months and years as the patient's response changes.

Each of those visits is an experiment, and its useful output is the
*relationship* between what was delivered and what happened, rather than the
setting the visit ended on.

That relationship is the part that usually gets lost.

Vendor programming devices record what the device needs in order to stimulate.
They are not built to export research-usable data, and what they do export is
neither consistent between manufacturers nor easy to pool across patients. So
the clinical detail (the ratings, the order things were tried in, the side
effect that appeared at 4.5 mA and went away at 3.0) ends up on paper, in a
free-text note, or in someone's memory. None of those survive analysis.

The result is that sessions get documented twice, inconsistently, and the
scientifically interesting content is the content that gets dropped.

What it records
---------------

Wyss DBS Annotator sits alongside the programming device and records the session as
it happens:

**Stimulation, per configuration.**
   Active contacts and their polarity on each lead, amplitude (including
   current-steered splits across segmented contacts), pulse width, frequency,
   and the stimulation program. Every configuration is numbered, so the sequence
   is preserved.

**Ratings, per configuration.**
   Symptom and side effect ratings at each configuration, the same ratings
   throughout so that they stay comparable, plus an initial clinical assessment
   taken before stimulation changes begin.

**Observations.**
   Free-text notes attached to the configuration they were written at, not to
   the session as a whole.

**Time.**
   Every saved configuration is timestamped with its UTC offset. This is what makes it
   possible, afterwards, to tell a rating taken seconds after a parameter change
   from one taken after several minutes, a distinction that changes how the
   number should be read.

Design commitments
------------------

**Offline by default.** Clinical environments cannot be assumed to have network
access, and patient data should not require it. The app has no server component
and makes no outbound connections.

**One format, openly documented.** Output is tab-separated text with
:doc:`BIDS <output_format>` filenames and layout. It opens in a spreadsheet, in
pandas, in R, in a text editor. There is no proprietary container and no export
step that can silently lose a field.

**Analysis-ready shape.** Each visit is saved in a BIDS folder: one row per
configuration tried, one column per scale, and the values that belong to the
visit or the patient in BIDS' own ``sessions.tsv`` and ``participants.tsv``.
Files pool with a plain concatenation.

**Say only what the data supports.** Reports call a configuration the one the
patient was left on only when the clinician marked it so; otherwise they state
"last recorded configuration", because nothing else in the record shows that a
clinician confirmed a choice. Where the app ranks configurations, it refuses to
do so until someone has said what "better" means for each scale. See
:ref:`what-the-reports-do-not-say`.

Who it is for
-------------

Neurologists, psychiatrists and researchers who run DBS programming visits and
want each one documented once, in a form that is both readable in a patient
record and usable in an analysis six months later, including when the question
is how this visit compares with the last four.
