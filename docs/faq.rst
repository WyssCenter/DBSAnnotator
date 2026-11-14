Frequently asked questions
==========================

General
-------

**Does it need an internet connection?**
   No, at any point. There is no server component, no account, and no outbound
   connection. It is designed for clinical environments where network access
   cannot be assumed and patient data should not travel.

**Does it send any data anywhere? Do the developers see what I enter?**
   No. Nothing you enter ever leaves your device, and the developers receive
   nothing at all: no patient data, no session content, no usage statistics, no
   crash reports, not even a record that the app was opened. The app makes no
   network connection of any kind.

   What the app keeps, it keeps on your own device and nowhere else: the files
   you save in the BIDS folder you choose, a working copy of the session in
   progress so that a crash loses nothing (you keep or discard it when you
   leave), and your settings and picklists. When a patient's indication, leads
   and IPG are filled in from the last visit, they are read from your own BIDS
   folder, not from anywhere else. See :doc:`privacy` for the full list.

**Which leads are supported?**
   Medtronic (3387, 3389, 3391, SenSight B33005/B33015), Boston Scientific
   (Vercise, Vercise Directed, Cartesia HX, Cartesia X), Abbott (ActiveTip,
   Infinity), PINS Medical (L301-L303) and ALEVA directSTIM, including the
   segmented models, whose levels are drawn and tapped as three separate
   segments plus a whole-level ring.

**Can I use it on a phone?**
   Yes. On a narrow screen the two-column steps stack into one column, with more
   scrolling.

**Is it a medical device?**
   No, and it does not carry a CE mark. The app says so under every step and in
   every report.

Files and data
--------------

**Where are the files saved?**
   In the BIDS folder chosen on the Session step, one of the storage folders
   listed under **Storage folders (BIDS)** in the settings menu. Reports and
   zip exports go wherever you choose in the platform's file picker or share
   sheet. While a session is open, the app also keeps a working copy in its own
   storage, for crash recovery. When you leave the session you choose whether
   to keep it or discard it. See :doc:`privacy`.

**Can I open the TSV in Excel?**
   Yes. It is tab-separated text. Be aware that Excel will try to reinterpret
   some values (a scale name that looks like a date, for instance), so for
   analysis prefer pandas or R, and see :doc:`output_format`.

**Can it open files written by the earlier desktop application (version 0.4)?**
   Yes, with no conversion. Files written by this version are not readable by
   version 0.4. See :ref:`the naming rules <bids-naming>`.

**What happens if the app crashes mid-session?**
   Every saved configuration is written to the BIDS folder and to the working
   copy as it happens, and an interrupted write leaves the previous version
   intact rather than a truncated file. Reopen the app and it offers the
   unfinished session back. You lose at most the configuration you were
   setting up.

**Why do two session files have different columns?**
   Each symptom and side effect rating is a ``scale_<name>`` column, and the
   ratings depend on the indication. ``pandas.concat`` lines files up by column name. See
   :ref:`where-values-live`.

Reports
-------

**Why is nothing highlighted green in my report?**
   Because no scale targets have been set, so nothing has been ranked. Set them
   at export, or from the Programming step. This is the session report; the
   longitudinal report ranks against default targets when none are set and
   prints the targets it used. See :ref:`scale-targets`.

**Why does the report say "last recorded configuration" rather than "left on"?**
   Because no configuration was confirmed as the final settings, the one the
   patient goes home on. Mark it with **Final settings (patient goes home on
   this)** on the Programming step, and confirm it in the question asked on the
   way to Finish; an unmarked file shows only which configuration came last,
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
   Check the lead model of each side on the Indication and devices step; it
   stays editable for the whole visit. When a saved session is opened, the app
   adopts the models named inside it and tells you if a name is not in the
   catalogue. A lead missing from the catalogue can be added under **Leads and
   IPGs** in the settings menu.
