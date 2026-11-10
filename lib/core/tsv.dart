import 'package:csv/csv.dart';

/// Tab-separated I/O matching Python's `csv` with `delimiter='\t'`; the `csv`
/// package keeps quoting compatible with the desktop app's embedded newlines.

/// Parse a TSV document into rows of string cells, detecting `\r\n` vs `\n`
/// from the FIRST line ending only, the one line a quoted cell cannot hide in:
/// a `notes` cell may contain `\r\n`, and scanning the whole document then
/// takes that for the terminator, collapsing an LF file to a single row.
List<List<String>> parseTsv(String content) {
  if (content.isEmpty) return <List<String>>[];
  final firstLf = content.indexOf('\n');
  final eol = firstLf > 0 && content[firstLf - 1] == '\r' ? '\r\n' : '\n';
  final rows = CsvToListConverter(
    fieldDelimiter: '\t',
    textDelimiter: '"',
    eol: eol,
    shouldParseNumbers: false,
  ).convert(content);
  return rows
      .map((row) => row.map((cell) => cell?.toString() ?? '').toList())
      .toList();
}

/// Serialize rows to a TSV document: LF, not CRLF (a stray `\r` would land in
/// the last field for readers that split on `\n`), and newline-terminated.
String writeTsv(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  return '${const ListToCsvConverter(fieldDelimiter: '\t', textDelimiter: '"', eol: '\n').convert(rows)}\n';
}

/// What BIDS requires in a cell with no value: "Missing and non-applicable
/// values MUST be coded as `n/a`". An empty cell is not allowed, nor is `NaN`.
const String naCell = 'n/a';

/// Parse a TSV with a header row into maps, reading [naCell] back as empty.
List<Map<String, String>> parseTsvRecords(String content) {
  final rows = parseTsv(content);
  if (rows.isEmpty) return <Map<String, String>>[];
  final header = [for (final c in rows.first) c.trim()];
  final dataRows = rows.skip(1).where((r) => r.any((c) => c.trim().isNotEmpty));
  return dataRows.map((row) {
    final record = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      final cell = i < row.length ? row[i] : '';
      record[header[i]] = cell.trim() == naCell ? '' : cell;
    }
    return record;
  }).toList();
}

/// Serialize records in the given column order; empty values become [naCell].
String writeTsvRecords(
  List<String> columns,
  List<Map<String, String>> records,
) {
  final rows = <List<String>>[columns];
  for (final record in records) {
    rows.add(
      columns.map((col) {
        final value = record[col] ?? '';
        return value.isEmpty ? naCell : value;
      }).toList(),
    );
  }
  return writeTsv(rows);
}
