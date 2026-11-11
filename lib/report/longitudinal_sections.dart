/// Sections of the longitudinal report, mirroring the desktop's chooser.
///
/// Separate from [ReportSection] because none of that enum's values names a
/// longitudinal construct: they describe one visit, these describe a set of
/// them. Defaults follow the desktop, where the overview and the session-scale
/// figure are checked and the heavier sections are not.
library;

enum LongitudinalSection {
  clinicalChart(
    'Clinical scales by visit',
    'One assessment per visit, so the x axis is the visit itself.',
  ),
  visits(
    'Visits table',
    'Date, program in force at the end of the visit, configurations '
        'tested, and every clinical scale annotated at the visit.',
  ),
  sessionChart(
    'Symptom and side effect ratings by visit and configuration',
    'Every configuration of every visit, with the two best configurations '
        'across all visits banded when scale targets are set.',
  ),
  sessionTable(
    'Combined session data table',
    'Every recorded configuration across all visits, grouped by visit.',
  ),
  electrodes(
    'Electrode configuration',
    'Lead diagrams for the initial and last recorded settings of each visit. '
        'Four images per visit, so this is the section that adds pages.',
  ),
  summary(
    'Programming summary',
    'Per visit: configurations tested and the range of each parameter.',
  ),
  sources('Source files', 'The filenames the report was built from.');

  const LongitudinalSection(this.label, this.description);

  final String label;
  final String description;
}

/// The desktop's defaults: the overview and the session-scale figure, plus the
/// source list, which is one cheap appendix.
const Set<LongitudinalSection> kDefaultLongitudinalSections = {
  LongitudinalSection.clinicalChart,
  LongitudinalSection.visits,
  LongitudinalSection.sessionChart,
  LongitudinalSection.sources,
};

const Set<LongitudinalSection> kAllLongitudinalSections = {
  LongitudinalSection.clinicalChart,
  LongitudinalSection.visits,
  LongitudinalSection.sessionChart,
  LongitudinalSection.sessionTable,
  LongitudinalSection.electrodes,
  LongitudinalSection.summary,
  LongitudinalSection.sources,
};
