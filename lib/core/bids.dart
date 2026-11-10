/// BIDS filename handling. Contract: schema/tsv_schema.json -> "bids".
///
/// The suffix is `_beh`, not `_events`: BIDS reserves `_events.tsv` for files
/// with `onset` and `duration` columns that accompany a recording, and
/// requires files without them to "be labeled `_beh.tsv`". Legacy files use
/// `_events.tsv`; `sniffTsvKind` classifies on the header, so they still open.
library;

class BidsName {
  const BidsName({
    required this.subject,
    required this.session,
    required this.task,
    required this.run,
    this.acquisition = '',
    this.suffix = behSuffix,
    this.extension = 'tsv',
  });

  static const String behSuffix = 'beh';

  /// Recognised by [parse] for older files, but never written again.
  static const String legacySuffix = 'events';

  static const String datatype = 'beh';

  final String subject;
  final String session;
  final String task; // "programming" or "notes" unless the user names another
  final String run;

  /// Optional `acq-` label, left out of the name when empty.
  final String acquisition;
  final String suffix;
  final String extension;

  /// Strip a BIDS entity label to the alphanumerics the spec allows. Subject
  /// and session are free text that ends up in a file path, where a typed `/`,
  /// `\` or a leading `..` would fail the write or escape the target directory.
  static String label(String raw) =>
      raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

  /// Reduce a run entity to the zero-padded index BIDS requires: [parse] reads
  /// runs back with a digits-only pattern, so `run-pre` would return as `01`.
  static String index(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final n = int.tryParse(digits);
    if (n == null) return '01';
    return n.toString().padLeft(2, '0');
  }

  /// The entity chain without suffix or extension; a safe path segment.
  String get stem =>
      'sub-${label(subject)}_ses-${label(session)}'
      '_task-${label(task)}'
      '${label(acquisition).isEmpty ? '' : '_acq-${label(acquisition)}'}'
      '_run-${index(run)}';

  String get filename => '${stem}_$suffix.$extension';

  String get sidecarFilename => '${stem}_$suffix.json';

  BidsName withSuffix(String suffix, {String extension = 'tsv'}) => BidsName(
    subject: subject,
    session: session,
    task: task,
    run: run,
    acquisition: acquisition,
    suffix: suffix,
    extension: extension,
  );

  String get relativeDir =>
      'sub-${label(subject)}/ses-${label(session)}/$datatype';

  static String? _group(String pattern, String source) =>
      RegExp(pattern).firstMatch(source)?.group(1);

  /// Parse a BIDS filename, or null if it carries no subject entity.
  static BidsName? parse(String filename) {
    final subject = _group(r'sub-([^_]+)', filename);
    if (subject == null) return null;
    return BidsName(
      subject: subject,
      session: _group(r'ses-([^_]+)', filename) ?? '',
      task: _group(r'task-([^_]+)', filename) ?? '',
      run: _group(r'run-([0-9]+)', filename) ?? '01',
      acquisition: _group(r'acq-([^_]+)', filename) ?? '',
      suffix: filename.contains('_$legacySuffix.') ? legacySuffix : behSuffix,
    );
  }

  /// Session stamp in the format used for `ses-`: `YYYYMMDD`.
  static String sessionStamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}';
  }
}
