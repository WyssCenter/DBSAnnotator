/// Which sections a generated report contains, mirroring the desktop export
/// dialog's section checkboxes (`export_dialog.py`). A pure enum with no
/// Flutter import, so both output formats are gated on the same selection.
///
/// Flat on purpose: graph and table are siblings rather than children of a
/// tri-state parent, at no cost in expressive power.
library;

enum ReportSection {
  baseline(
    'Initial assessment',
    'Clinical scale scores, medications and notes recorded before '
        'stimulation was changed.',
  ),
  chart(
    'Session scales figure',
    'Every rated scale plotted against configuration, with the aggregate '
        'index and the best / second-best bands.',
  ),
  table(
    'Session data table',
    'One row per configuration and side: contacts, parameters, scale '
        'ratings and notes.',
  ),
  electrodes(
    'Electrode configuration',
    'Rendered lead diagrams for the initial and last recorded settings, '
        'left and right.',
  ),
  summary(
    'Programming summary',
    'Configurations tested, the range of each parameter, and the span of '
        'the annotation.',
  );

  const ReportSection(this.label, this.description);

  final String label;

  /// Shown under the checkbox, so the choice can be made without exporting.
  final String description;
}

/// Default selection: everything on.
const Set<ReportSection> kAllReportSections = {
  ReportSection.baseline,
  ReportSection.chart,
  ReportSection.table,
  ReportSection.electrodes,
  ReportSection.summary,
};
