Default lists
=============

The app comes with a list of choices for each picklist: the DBS indications, the anatomical
targets, the leads and IPGs, the stimulation defaults, the programs, the clinical scales, and the
symptom and side effect ratings. This page shows each of them as it comes with the app, in the
order a programming session meets them. The tables are built from the same files the app reads,
so they match the version of the app this guide describes.

Each list can be edited from the :ref:`settings menu <settings-menu>`, or with the button beside it
on the step that uses it. Your edits apply to every future session on this device and are never
saved in a session file, so editing a list changes nothing already recorded. There are two ways
back to the lists on this page:

* **Restore defaults** in a list's dialog fills the dialog with the list as it comes with the app.
  Nothing is kept until you press **Save**, so **Cancel** leaves your own list as it was.
* **Restore default lists** in the settings menu, after asking, puts every list back at once and
  removes your own additions.

The question mark at the top of each dialog opens the matching section of this page.

DBS indications
---------------

Offered in Indication and devices. The indication chosen decides which stimulation defaults,
clinical scales and ratings below a session starts from, and is saved, written in full, in the
``dbs_indication`` column of ``participants.tsv``.

.. include:: _generated/defaults_indications.inc.rst

Anatomical targets
------------------

Offered beside the indication in Indication and devices.

.. include:: _generated/defaults_targets.inc.rst

Leads and IPGs
--------------

The lead and implanted pulse generator (IPG) models offered in Indication and devices, grouped by
manufacturer. Each lead also carries its contact layout, drawn in the contact diagrams.

.. include:: _generated/defaults_devices.inc.rst

Stimulation defaults
--------------------

Filled in on both sides when the initial assessment starts, for an indication listed here. Every
other indication starts with empty fields.

.. include:: _generated/defaults_stimulation.inc.rst

Programs
--------

The active program, which manufacturers call the group, offered in Initial assessment and
Programming:

* Not specified
* A
* B
* C
* D

Clinical scales
---------------

The clinical scales offered in Initial assessment, one group per DBS indication. The range only
sets the axis of the longitudinal report's clinical figure and is never printed. *Not set* marks a
name that stands for more than one instrument, such as HAM-D, or UPDRS, which can mean the total
or the motor part: fill in the range of the one you use.

.. include:: _generated/defaults_clinical.inc.rst

Symptom and side effect ratings
-------------------------------

Rated at every configuration in Programming, one group per DBS indication. *Whole points* moves
the slider in whole steps, as for a 0 to 4 item; *Any value* takes any value on the bar. *Better
when* is how the configurations are compared: edit it in the ratings settings, or change it for
one session or report under :ref:`scale-targets`.

.. include:: _generated/defaults_ratings.inc.rst

Other settings
--------------

The other settings, and the layout the app remembers between visits, start as follows:

* Scale targets: each rating's target from the table above.
* Report sections: every section included.
* Page size of the reports, under Reports and exports: A4.
* Dark theme: off.
* Text size: the normal size, which the two text size buttons make smaller or larger.
* Stimulation settings in Initial assessment and Programming: unfolded.
* Comparison charts in Programming: folded.
* All configurations, the table under them: unfolded.

Restore default lists leaves these as they are.
