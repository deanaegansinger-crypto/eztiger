import 'package:flutter/material.dart';

import '../app_state.dart';
import '../platform.dart';
import '../theme.dart';
import 'common.dart';

/// One column of a song table. A column with [fixed] keeps that width
/// (grown with the text size); the others share the rest of the row by
/// [weight], and can be made wider or narrower by dragging their edge.
class TableCol {
  const TableCol(this.id, this.label, {this.weight = 1, this.fixed, this.canHide = true});
  final String id;
  final String label;
  final double weight;
  final double? fixed;
  final bool canHide;
}

/// The song list's columns.
const resultColumns = [
  TableCol('title', 'Title', weight: 5, canHide: false),
  TableCol('artist', 'Artist', weight: 4),
  TableCol('type', 'Type', fixed: 44),
  TableCol('location', 'Location', weight: 3),
];

/// The queue's columns.
const queueColumns = [
  TableCol('num', '#', fixed: 28, canHide: false),
  TableCol('title', 'Title', weight: 5, canHide: false),
  TableCol('artist', 'Artist — Singer', weight: 5),
  TableCol('type', 'Type', fixed: 44),
  TableCol('played', 'Played', weight: 2),
  TableCol('location', 'Location', weight: 2),
  TableCol('remove', '', fixed: 24, canHide: false),
];

double _weight(AppState s, String table, TableCol c) => s.columnWeights['$table.${c.id}'] ?? c.weight;

List<TableCol> _visible(AppState s, String table, List<TableCol> cols) => [
  for (final c in cols)
    if (!c.canHide || !s.hiddenColumns.contains('$table.${c.id}')) c,
];

/// A row of cells laid out in the table's columns (hidden ones left out).
class ColumnsRow extends StatelessWidget {
  const ColumnsRow({super.key, required this.table, required this.columns, required this.cells});
  final String table;
  final List<TableCol> columns;
  final Map<String, Widget> cells;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Row(
      children: [
        for (final c in _visible(s, table, columns))
          if (c.fixed != null)
            SizedBox(width: listSize(context, c.fixed!), child: cells[c.id])
          else
            Expanded(flex: (_weight(s, table, c) * 100).round(), child: cells[c.id] ?? const SizedBox()),
      ],
    );
  }
}

/// The column headings: drag the line at a heading's right edge to make it
/// wider or narrower; right-click (press and hold on the tablet) for a menu
/// to show or hide columns.
class ColumnsHeader extends StatelessWidget {
  const ColumnsHeader({super.key, required this.table, required this.columns, this.headings = const {}});
  final String table;
  final List<TableCol> columns;

  /// Headings that do more than show the label (e.g. sort on tap).
  final Map<String, Widget> headings;

  Future<void> _menu(BuildContext context, Offset at) async {
    final s = AppScope.of(context);
    final c = await showMenuAt<String>(context, at, [
      const PopupMenuItem(enabled: false, height: 28, child: Text('SHOW COLUMNS', style: TextStyle(fontSize: 11))),
      for (final col in columns)
        if (col.canHide)
          CheckedPopupMenuItem(
            key: Key('col-$table-${col.id}'),
            value: col.id,
            checked: !s.hiddenColumns.contains('$table.${col.id}'),
            child: Text(col.label),
          ),
      const PopupMenuDivider(),
      const PopupMenuItem(key: Key('col-reset'), value: '_reset', child: Text('Reset columns')),
    ]);
    if (c == '_reset') {
      s.resetColumns(table);
    } else if (c != null) {
      s.toggleColumn('$table.$c');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final shown = _visible(s, table, columns);
    final flexible = [
      for (final c in shown)
        if (c.fixed == null) c,
    ];
    return MenuArea(
      onMenu: (at) => _menu(context, at),
      child: LayoutBuilder(
        builder: (context, box) {
          final fixedWidth = shown.fold(0.0, (w, c) => w + (c.fixed == null ? 0 : listSize(context, c.fixed!)));
          final flexWidth = (box.maxWidth - fixedWidth).clamp(1.0, double.infinity);
          final totalWeight = flexible.fold(0.0, (w, c) => w + _weight(s, table, c));

          Widget heading(TableCol c) => headings[c.id] ?? HeadText(c.label);

          return Row(
            children: [
              for (final c in shown)
                if (c.fixed != null)
                  SizedBox(width: listSize(context, c.fixed!), child: heading(c))
                else
                  Expanded(
                    flex: (_weight(s, table, c) * 100).round(),
                    child: Row(
                      children: [
                        Expanded(child: heading(c)),
                        // The last flexible column has no right-hand neighbour to trade width with.
                        if (c != flexible.last)
                          _ResizeHandle(
                            key: Key('resize-$table-${c.id}'),
                            onDrag: (dx) {
                              final next = flexible[flexible.indexOf(c) + 1];
                              final dw = dx * totalWeight / flexWidth;
                              final a = _weight(s, table, c), b = _weight(s, table, next);
                              // Neither column gets narrower than a sliver.
                              final min = totalWeight * 0.06;
                              final move = dw.clamp(min - a, b - min);
                              s.setColumnWeights(table, {c.id: a + move, next.id: b - move});
                            },
                          ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({super.key, required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: SizedBox(
        width: touchUi ? 22 : 10,
        height: touchUi ? 30 : 16,
        child: Center(
          child: Container(width: 1, height: touchUi ? 18 : 12, color: context.ez.border),
        ),
      ),
    ),
  );
}
