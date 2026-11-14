Quick start
===========

Opening the app
---------------

Launch Wyss DBS Annotator as you would any other app on the device. It opens on
:doc:`Annotate programming session <screens/programming_session>`, where a session is annotated in
five steps. Its first step, Session, is also where you import earlier sessions and export reports
and BIDS folders.

New to the vocabulary (configuration, initial assessment, clinical scales, symptom and side effect
ratings, BIDS)? See :doc:`glossary`.

The theme, text size and other settings are in the menu at the top left.

Your first session
------------------

The shortest useful path through
:doc:`Annotate programming session <screens/programming_session>`, moving between steps with
**Back** and **Next**:

1. **Session.** Choose the BIDS folder, pick or type the patient ID, and press **Next**. The app
   starts the visit, builds the BIDS file name for you and saves the visit into the folder from the
   first save onward.

2. **Indication and devices.** Choose the DBS indication, the anatomical target, the leads and the
   IPGs. A known patient's last visit fills them in; check them. They stay editable for the whole
   visit.

3. **Initial assessment.** Enter the state the patient arrived in: the clinical scales, the
   medications, the active program and the settings currently programmed, with their contacts.
   It is saved when you press **Next**, marked as the initial assessment, and is not counted
   among the configurations tested.

4. **Programming.** For each configuration: set the parameters, select contacts on the lead
   diagram, rate the symptoms and side effects, add any note, and press **Save configuration**.
   Repeat. Mark the configuration the patient goes home on with **Final settings**.

5. **Finish.** Confirm the final settings, export the report for the patient record and the BIDS
   folder for research, then **Close**.

Things worth knowing early
--------------------------

**Every configuration is saved immediately.** There is no separate save step at the end. Each
configuration is written to the BIDS folder and to a working copy inside the app, so a crash or a
closed window loses nothing: the next time you open the app, it offers the unfinished session
back.

**Notes belong to a configuration.** They are attached to the configuration they were typed for,
not to the session as a whole, which is what makes it possible afterwards to say *which* setting
caused the paraesthesia.

**Scale targets are yours to set.** If you want the app to highlight the best-scoring
configurations, you must first say what "better" means for each rating: lower, higher, or closest
to a value. Until you do, no configuration is ranked. This is deliberate; see
:ref:`what-the-reports-do-not-say`.

**Text size and theme** are in the settings menu at the top left.

Getting the report
------------------

On Finish, under **For the patient record**, choose **Report (PDF)** or **Report (Word)**; Session
offers the same under **Export this session**. For a session annotated earlier, import it on the
Session step (see :doc:`screens/import_export`) and choose *Single session report*. You will be
asked which sections to include and can set the scale targets at that point. See :doc:`reports`.
