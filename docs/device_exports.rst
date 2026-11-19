Stimulation settings from the Percept export
============================================

A Medtronic Percept PC or RC records what it delivered. When the clinician
programmer saves its session report, the JSON file holds the groups the patient
arrived and left on and, while BrainSense streaming runs, the stimulation
amplitude on each side sampled throughout the stream, with the time in UTC. The
app can
read that file and fill in the stimulation of a session from it, so a clinician
who rates the patient in the app during the visit does not also have to type
every contact and amplitude.

The filled values are marked as read from the device, in the session file and in
the report, so a report filed in the patient record never presents a device value
as one a clinician entered.

The export is read the way `perceive <https://github.com/neuromodulation/perceive>`_
reads it, wherever perceive reads a field. perceive is the open research toolbox
for Percept recordings in MATLAB, founded by Wolf-Julian Neumann, Gerd Tinkhauser
and Tomas Sieger and maintained by Jojo Vanhoecke and colleagues at the Unit for
Movement Disorders, Charité. The app's reader is its own code and includes none of
perceive's.

Where the export goes
---------------------

Copy the programmer's JSON file into the ``ieeg/`` folder of the visit, next to
its ``beh/`` folder:

.. code-block:: text

   sub-01/
     ses-20260203/
       beh/
         sub-01_ses-20260203_task-programming_run-01_beh.tsv
       ieeg/
         Report_Json_Session_Report_20260203T090112.json

The file can keep the name the programmer gave it. The app recognises an export
by what it contains, not by its name, so other JSON files in ``ieeg/``, such as
BIDS sidecars, are left alone. When a visit was saved as several exports, for
example after the programmer reconnected, put them all in the folder: their
timelines are read together.

The export holds the patient's name, date of birth and medical record number.
The app never reads those parts, but the file itself keeps them, so a BIDS folder
holding exports needs the protection of the patient record, and the exports must
be removed or de-identified before the folder is shared. The app's own BIDS
export (:ref:`bids-dataset-export`) does not include them.

Filling a session
-----------------

Open the session, go to the Finish step and choose **Fill from Percept export**
under **From the device**. The session has to be saved in the BIDS folder that
holds the visit, since that is where the export is looked for.

A preview lists what would change before anything is written:

- each saved configuration whose values differ from the device's, with every
  change as *entered value → device value*, and a box to keep that configuration
  as entered;
- the configurations that already match the device, and those saved at a time
  the export has no setting for, which stay as they are;
- the settings the device held that nobody saved, which can be added as
  configurations of their own;
- **Swap sides**, for a patient whose sides are labelled the other way round in
  the stimulator, so that the device's left lead is read as the session's right.

Nothing is written until **Fill** is chosen. The session is then saved as usual.

How the values are matched
--------------------------

Every configuration saved in the app carries the moment Save was pressed
(``acq_time``). The app looks up what the device was delivering at that instant:

- **During streaming**, the group, frequency, pulse width and contacts of that
  streaming segment, and the amplitude on each side at that moment. If the
  amplitude had changed only seconds before, during a ramp, the preview says how
  long the device had held it.
- **The initial assessment** is matched to the group active when the programmer
  connected, the settings the patient arrived on.
- **A setting held for at least 10 seconds** with no configuration saved during
  it is offered as a new configuration without ratings, timed at the end of the
  hold. Brief steps on the way up a ramp are not.
- **The group active when the session ended** is added as the last configuration
  when it differs from the last one tested, for example when settings were
  changed after streaming stopped.

A configuration saved outside every streaming segment gets nothing from the
device, because the export does not say what was delivered then.

Values the clinician entered are only replaced where they differ from the
device. A value that already equals the device's stays recorded as entered.

What is filled, and what is not
-------------------------------

The device fills the group (``program_id``) and, per side, frequency, pulse
width, anode and cathode contacts, and amplitude. When the export gives each
cathode's share of the current, the amplitude is written split across the
cathodes as the app writes it (see :ref:`amplitudes and current steering
<output-amplitudes>`); without the shares, only the total is written.

A value is left as it was when the export cannot state it:

- the contacts, when a streaming segment does not list them or names an
  electrode the app does not recognise;
- a side running two programs in one group (interleaving), which one session row
  cannot hold;
- the amplitude of the settings at the start and the end of the visit when
  BrainSense was on in that group, because the export does not state it in a field
  whose meaning is confirmed; the contacts, frequency, pulse width and group are
  still filled;
- the start or end settings, when stimulation was off.

The preview names each of these.

The export is refused, with the reason, when its lead models differ from the
session's (check the leads, or **Swap sides**), or when it was recorded on
another day than the session.

How the source is recorded
--------------------------

The ``from_device`` column of the session file lists, for each configuration,
the columns whose values were read from the export, for example
``left_amplitude left_pulse_width program_id``; ``n/a`` means every value was
entered in the app. Editing a configuration afterwards removes from the list the
values that were changed, and keeps the rest.

In the :doc:`reports`, each value read from the device is followed by ¹, and a
footnote says what the mark means. A line of the page-one box whose values all
came from the device carries a single mark at its end.

Limits
------

**The clocks must agree.** The tablet or computer running the app and the
clinician programmer keep their own time. A difference of a few minutes moves
every match by that much. Compare the times in the preview with what you
remember of the visit before filling.

**Only streamed stretches are known in detail.** Without BrainSense streaming
the export holds the settings at the start and the end of the visit, and nothing
in between.

**Left and right are the stimulator's labels.** The export names each lead's
side as it is set in the stimulator, which can disagree with the patient's
sides. When the lead models do not tell them apart, nothing in the data can, so
check the preview against the visit and use **Swap sides** where needed.
