Key terms
=========

The words the rest of this documentation uses, in the order you meet them.

**Visit (session)**
   One programming appointment. The app saves one visit per file.

**Storage folder (BIDS)**
   A BIDS folder the app saves visits into, chosen on the Session step and listed under
   **Storage folders (BIDS)** in the settings menu. You can keep several, for example one per
   cohort.

**Picklists**
   The choices the app offers in lists: DBS indications, anatomical targets, leads and IPGs,
   stimulation defaults, programs, clinical scales, and symptom and side effect ratings. They are
   edited in the settings menu or beside each list, apply to every future session, and are never
   saved in a session file.

**Contacts**
   The electrodes on a lead, numbered by level from the tip (``E0``, ``E1``...). On a segmented
   (directional) lead a level is split into three contacts, ``a``, ``b`` and ``c``. The case of
   the IPG can also take part.

**Anode and cathode**
   The two roles an active contact can take. The cathode (-) is where the current is delivered to
   the tissue; the anode (+) is where it returns, often the case. A contact that is neither is
   off.

**Configuration (setting)**
   One set of stimulation parameters on both leads, as saved: which contacts are anodes and
   cathodes, the amplitude, frequency and pulse width, the active program, the symptom and side
   effect ratings and the notes, stamped with the time it was saved. A visit is a series of
   configurations, numbered in order.

**Current fractionalization**
   How the current of one side is shared between its cathodes, as a percentage per contact, when
   more than one is active. The app shows the milliamps each share works out to.

**Active program (group)**
   The label of the stimulation program (A, B, C...) the configuration belongs to. Reports call it
   the *group*, the term the device manufacturers use.

**Initial assessment**
   The first configuration, entered in the *Initial assessment* step: the settings the patient
   arrived with and the clinical scale scores before anything was changed. It is not counted among
   the configurations tested.

**Clinical scales**
   Validated assessments typed once per visit in the initial assessment, such as Y-BOCS, MADRS or
   MDS-UPDRS Part III.

**Symptom and side effect ratings**
   Quick ratings taken at *every* configuration, each on a range you define (for example
   Obsessions 0 to 10, or an MDS-UPDRS Part III item such as rigidity of the right upper
   extremity, ``RUE``), so configurations can be compared within the visit. In the file and in
   some report headings they are called session scales.

**Discrete and continuous ratings**
   A discrete rating takes whole points only, as the MDS-UPDRS items do. A continuous rating takes
   any value on the slider. Each rating is set to one or the other in its settings.

**Final settings**
   The configuration the patient goes home on. It is marked while programming and confirmed on the
   way to Finish. Reports head it *Final settings (marked by the clinician)*; when none
   was confirmed, they show the last configuration saved and say so.

**Contact notation**
   How reports write a configuration: ``2b(60%) 2c(40%)- / case+`` means contacts 2b and 2c are
   cathodes (-) sharing the current 60/40, and the case is the anode (+).

**Scale targets**
   What "better" means for each symptom and side effect rating: lower, higher, or closest to a
   value. You set them; nothing is ranked until you do.

**Aggregate index**
   A score from 0 to 1 per configuration, computed from the ratings against the targets, where 1
   is best. It is what the green highlighting ranks by. See :ref:`scale-targets`.

**BIDS**
   The Brain Imaging Data Structure, a community standard for naming and organising neuroscience
   data. The app names and lays out its files to it, so they can be pooled and validated with
   standard tools. See :doc:`output_format`.

**TSV and sidecar**
   Each visit is a tab-separated text file (``.tsv``) with a JSON file of the same name beside
   it, the *sidecar*, which describes every column.

**Run**
   The number that tells apart two visits of the same patient on the same day (``run-01``,
   ``run-02``).

**append_id**
   A counter in the file that goes up each time a saved session is opened again to add more
   configurations, so a visit continued later can be told apart from one annotated in a single
   sitting.
