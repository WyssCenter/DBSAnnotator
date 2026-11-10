/// Review table of every inserted TSV row, grouped by block.
///
/// Uses Flutter's `Table` rather than `DataTable` because `DataTable` cannot
/// draw a per-row border, and one row per scale means a block spans several
/// rows: without a heavy rule at each block boundary the eye cannot tell where
/// a configuration starts.
library;

import 'package:flutter/material.dart';

import '../../core/brand_palette.dart' show kBestFill, kSecondFill;
import '../../core/timestamps.dart';
import '../../core/session/session_row.dart';
import '../../report/report_data.dart'
    show amplitudeCell, coerceInt, lateralText, numCell, tokensOf;

/// Thickness of the rule between blocks.
const double _blockRule = 2.4;

/// Distinct blocks in [rows], which is what the user counts: one block writes
/// one row per scale, so a TSV row count reads several times too high.
int blockCount(List<SessionRow> rows) =>
    rows.map((r) => coerceInt(r.blockId)).toSet().length;

class SessionEntriesTable extends StatelessWidget {
  const SessionEntriesTable({
    super.key,
    required this.rows,
    this.bestBlocks = const [],
    this.secondBlocks = const [],
    this.onToggleStar,
  });

  final List<SessionRow> rows;

  /// Rank 1 and rank 2 blocks, shaded as the chart bands them.
  final List<int> bestBlocks;
  final List<int> secondBlocks;

  /// Called with a block id when its star is tapped; null shows stars only.
  final ValueChanged<String>? onToggleStar;

  static const _headers = [
    'Blk',
    'Type',
    'Time',
    'Prog',
    'Scale',
    'Value',
    'Left',
    'Right',
    'Notes',
  ];

  /// Relative column widths; Notes takes the largest share.
  static const _flex = <double>[5, 5, 8, 4, 9, 5, 15, 15, 12];

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('No entries inserted yet.')),
      );
    }
    final theme = Theme.of(context);
    final rule = theme.dividerColor;
    final tint = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: .5,
    );

    // Where the current goes over what it is, worded as in the report.
    String side(SessionRow r, {required bool left}) {
      final where = lateralText(tokensOf(r)!, left: left);
      String part(String v, String unit, String Function(String) fmt) =>
          v.trim().isEmpty ? '-' : '${fmt(v)} $unit';
      final dose = [
        part(left ? r.leftStimFreq : r.rightStimFreq, 'Hz', numCell),
        part(left ? r.leftAmplitude : r.rightAmplitude, 'mA', amplitudeCell),
        part(left ? r.leftPulseWidth : r.rightPulseWidth, 'µs', numCell),
      ].join(' / ');
      return '${where == 'not recorded' ? '-' : where}\n$dose';
    }

    // The date belongs to the session, not to a configuration, so the baseline
    // row carries it and recording blocks show only a clock time. A file with
    // no baseline keeps date and time on its first block, so the day is never
    // lost from the table.
    final hasInitial = rows.any((r) => coerceInt(r.isInitial) == 1);
    final starred = starredBlocksIn(rows);
    // Read as the wall clock recorded in `acq_time`, never converted: parsing
    // the instant would render it in this device's zone, so a block recorded
    // at 09:00 in Geneva would read 03:00 in Chicago. See `recordedDate`.
    String stamp(SessionRow r, bool initial, bool isFirstBlock) {
      final date = recordedDate(r.acqTime);
      final time = recordedTime(r.acqTime);
      if (date.isEmpty) return '';
      if (initial) return date;
      if (isFirstBlock && !hasInitial) return '$date $time';
      return time;
    }

    final tableRows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(bottom: BorderSide(color: rule, width: 1.2)),
        ),
        children: [for (final h in _headers) _cell(h, bold: true)],
      ),
    ];

    int? previousBlock;
    var blockIndex = -1;
    for (final r in rows) {
      final block = coerceInt(r.blockId);
      final isNewBlock = block != previousBlock;
      if (isNewBlock) {
        previousBlock = block;
        blockIndex++;
      }
      // Everything except Scale and Value is a property of the block, so it is
      // printed once on the block's first row and left blank on the rest,
      // leaving only the cells that differ. Blanking rather than merging keeps
      // every column aligned.
      final isInitial = coerceInt(r.isInitial) == 1;
      // Same fill and opacity as the chart bands above the table.
      final rankFill = bestBlocks.contains(block)
          ? kBestFill
          : secondBlocks.contains(block)
          ? kSecondFill
          : null;
      tableRows.add(
        TableRow(
          decoration: BoxDecoration(
            color: rankFill != null
                ? Color(rankFill).withValues(alpha: 0.45)
                : blockIndex.isOdd
                ? tint
                : null,
            border: isNewBlock && tableRows.length > 1
                ? Border(
                    top: BorderSide(color: rule, width: _blockRule),
                  )
                : null,
          ),
          children: [
            isNewBlock
                ? _blockCell(
                    r.blockId,
                    starrable: !isInitial,
                    starred: starred.contains(r.blockId),
                  )
                : _cell(''),
            _cell(isNewBlock ? (isInitial ? 'Initial' : 'Rec') : ''),
            _cell(isNewBlock ? stamp(r, isInitial, blockIndex == 0) : ''),
            _cell(isNewBlock ? r.programId : ''),
            _cell(r.scaleName),
            _cell(r.scaleValue),
            _cell(isNewBlock ? side(r, left: true) : ''),
            _cell(isNewBlock ? side(r, left: false) : ''),
            _cell(isNewBlock ? r.notes : '', maxLines: 4),
          ],
        ),
      );
    }

    // One style for the whole table, so the cells follow the A+/A- setting and
    // the body text size rather than a literal of their own.
    return DefaultTextStyle.merge(
      style: theme.textTheme.bodyMedium,
      child: Table(
        columnWidths: {
          for (var i = 0; i < _flex.length; i++) i: FlexColumnWidth(_flex[i]),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: tableRows,
      ),
    );
  }

  Widget _blockCell(
    String id, {
    required bool starrable,
    required bool starred,
  }) {
    final toggle = onToggleStar;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        children: [
          Text(id, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (starrable && (starred || toggle != null))
            Tooltip(
              message: starred ? 'Starred' : 'Star this configuration',
              child: InkWell(
                onTap: toggle == null ? null : () => toggle(id),
                child: Icon(
                  starred ? Icons.star : Icons.star_border,
                  size: 18,
                  semanticLabel: starred ? 'Starred' : 'Not starred',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool bold = false, int maxLines = 3}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: bold ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
    );
  }
}
