Wyss DBS Annotator
==================

.. image:: _static/logo.png
   :alt: Wyss Center
   :width: 340px
   :align: center

|

.. important::

   Wyss DBS Annotator is not a medical device. It is for annotating and documenting what happens during deep brain stimulation programming visits. It does not diagnose or decide stimulation settings: clinical decisions remain with the clinical team.

**Annotate deep brain stimulation programming visits, and get analysis-ready
data out.**

Once the electrodes are implanted, the patient comes back to see a neurologist or
psychiatrist, who tries stimulation configurations and settles on one that works.
That takes a visit or several, and the parameters go on being adapted over months
or years.

Wyss DBS Annotator documents those visits: the stimulation parameters tried on each
contact, the clinical and session scale ratings at every configuration, side
effects, and free-text notes. They are written to tab-separated files laid out
to :doc:`BIDS <output_format>` (the Brain Imaging Data Structure, a community
standard for organising neuroscience data), so they go straight into analysis. It also produces
clinician-readable :doc:`PDF and Word reports <reports>` for the patient
record. New to the terms? See :doc:`glossary`.

It runs **fully offline**: no account, no server, no telemetry. It is available
for iPadOS, Android, Windows, macOS and Linux, published by the Wyss Center for
Bio and Neuroengineering in the app stores and, for Linux, on GitHub. See
:doc:`installation`.

.. note::

   This is research software. It documents what was recorded; it does not
   recommend stimulation settings. See :ref:`what-the-reports-do-not-say`.

At a glance
-----------


.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - Aspect
     - Detail
   * - Platforms
     - iPadOS, Android, Windows, macOS, Linux, from each platform's app store
   * - Data files
     - A BIDS folder: ``_beh.tsv`` with one row per configuration, the visit in
       ``sessions.tsv``, the patient in ``participants.tsv``, each with a JSON
       sidecar
   * - Reports
     - PDF and Word, both built from the same numbers
   * - Connectivity
     - None required, ever
   * - Licence
     - MIT

.. toctree::
   :maxdepth: 2
   :caption: Getting started

   overview
   installation
   quickstart
   glossary

.. toctree::
   :maxdepth: 2
   :caption: Screens

   screens/programming_session
   screens/import_export

.. toctree::
   :maxdepth: 2
   :caption: Outputs

   output_format
   reports

.. toctree::
   :maxdepth: 2
   :caption: Reference

   faq
   privacy
   changelog

What changed in each version is in the :doc:`changelog`; the downloads for each
release are on `GitHub <https://github.com/neuromodulation/DBSAnnotator/releases>`_.
