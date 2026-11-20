import 'package:flutter/material.dart';

import '../../core/tournament/round_robin.dart';
import '../theme.dart';

/// Rangliste / Gruppentabelle.
class StandingsTable extends StatelessWidget {
  final List<StandingsRow> rows;
  final Map<String, String> names;
  final String? highlightPlayerId;
  final bool showBuchholz;
  final int? qualifyCount;
  const StandingsTable({
    super.key,
    required this.rows,
    required this.names,
    this.highlightPlayerId,
    this.showBuchholz = false,
    this.qualifyCount,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 44,
        columns: [
          const DataColumn(label: Text('#')),
          const DataColumn(label: Text('Spieler')),
          const DataColumn(label: Text('Sp'), numeric: true),
          const DataColumn(label: Text('S'), numeric: true),
          const DataColumn(label: Text('N'), numeric: true),
          const DataColumn(label: Text('Legs'), numeric: true),
          const DataColumn(label: Text('Diff'), numeric: true),
          if (showBuchholz) const DataColumn(label: Text('Buchholz'), numeric: true),
          const DataColumn(label: Text('Pkt'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              color: WidgetStatePropertyAll(r.playerId == highlightPlayerId
                  ? AppColors.accentDim.withValues(alpha: 0.35)
                  : (qualifyCount != null && r.rank <= qualifyCount!
                      ? AppColors.accent.withValues(alpha: 0.08)
                      : null)),
              cells: [
                DataCell(Text('${r.rank}')),
                DataCell(Text(names[r.playerId] ?? r.playerId,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text('${r.played}')),
                DataCell(Text('${r.wins}')),
                DataCell(Text('${r.losses}')),
                DataCell(Text('${r.legsFor}:${r.legsAgainst}')),
                DataCell(Text(r.legDiff > 0 ? '+${r.legDiff}' : '${r.legDiff}')),
                if (showBuchholz) DataCell(Text('${r.buchholz}')),
                DataCell(Text('${r.points}', style: const TextStyle(fontWeight: FontWeight.w800))),
              ],
            ),
        ],
      ),
    );
  }
}
