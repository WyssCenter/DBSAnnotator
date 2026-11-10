Frequently asked questions
==========================

General
-------

**Does it need an internet connection?**
   No, at any point. There is no server component, no account, and no outbound
   connection. It is designed for clinical environments where network access
   cannot be assumed and patient data should not travel.

**Does it send any data anywhere?**
   No. No telemetry, no crash reporting, no analytics. Files go where you save
   them.

**Which leads are supported?**
   Medtronic (3387, 3389, 3391, SenSight B33005/B33015), Boston Scientific
   (Vercise, Vercise Directed, Cartesia HX, Cartesia X), Abbott (ActiveTip,
   Infinity), PINS Medical (L301-L303) and ALEVA directSTIM, including the
   segmented models, whose levels are drawn and tapped as three separate
   segments plus a whole-level ring.

**Can I use it on a phone?**
   Yes. On a narrow screen the two-row steps stack into one column, with more
   scrolling.

Files and data
--------------

**Where are the files saved?**
   Wherever you choose in the platform's file picker or share sheet. While a
   session is open, the app also keeps a working copy in its own storage, for
   crash recovery. When you leave the session you choose whether to keep it or
   discard it. See
   :doc:`privacy`.

**Can I open the TSV in Excel?**
   Yes. It is tab-separated text. Be aware that Excel will try to reinterpret
   some values (a scale name that looks like a date, for instance), so for
   analysis prefer pandas or R, and see :doc:`output_format`.

**Can it open files written by the earlier desktop application (version 0.4)?**
   Yes, with no conversion. Files written by this version are not readable by
   version 0.4. See :ref:`the naming rules <bids-naming>`.

**What happens if the app crashes mid-session?**
   Every insert is written to your file and to the working copy as it happens,
   and an interrupted write leaves the previous version intact rather than a
   truncated file. Reopen the workflow and the app offers the unfinished session
   back. You lose at most the entry you were typing.

**Why do two session files have different columns?**
   Each rated scale is a ``scale_<name>`` column, and the scales depend on the
   indication. ``pandas.concat`` lines files up by column name. See
   :ref:`where-values-live`.

Reports
-------

**Why is nothing highlighted green in my report?**
   Because no scale targets have been set, so nothing has been ranked. Set them
   at export, or from the Recording step. This is the session report; the
   longitudinal report ranks against default targets when none are set and
   prints the targets it used. See :ref:`scale-targets`.

**Why does the report say "last recorded configuration" rather than "left on"?**
   Because no block was marked as the one the patient was left on. Mark it with
   **Patient leaves on this** on the recording step, or in the question asked at
   each export; an unmarked file records only which block came last,
   not that a clinician confirmed a choice. See
   :ref:`what-the-reports-do-not-say`.

**Can I get the report as a Word file I can edit?**
   Yes. Both formats come from the same numbers, so the ``.docx`` says exactly
   what the PDF does.

Troubleshooting
---------------

**The file picker does not open on Linux.**
   Desktop Linux opens files through the XDG desktop portal, which a normal
   GNOME or KDE session provides. Saving uses GTK directly and needs nothing
   extra. If a save dialog cannot open, exports fall back to saving in a
   well-known directory and the confirmation message names the exact path
   used.

**Opening a file says it is the wrong kind.**
   The app checks a file's columns before opening it, so a notes file from an
   earlier version cannot be opened as a session. Import it on the Session step
   instead, where it joins the report across visits and the combined table.

**The lead diagram does not match the patient's implant.**
   Check the electrode model of each side. When a file is opened, the app
   adopts the models named inside it and tells you if a name is not in the
   catalogue.
