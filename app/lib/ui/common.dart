import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../platform.dart';
import '../second_screen.dart';
import '../theme.dart';

/// Gives every widget below it the [AppState], and rebuilds them when it
/// changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child, this.videoBuilder, this.secondScreen})
    : super(notifier: state);

  /// Builds the video surface for video tracks (null in tests).
  final WidgetBuilder? videoBuilder;

  /// Opens the output on a second screen (null in tests).
  final SecondScreen? secondScreen;

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static WidgetBuilder? videoOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.videoBuilder;
  static SecondScreen? secondScreenOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.secondScreen;
}

/// The rounded "raised" box used all over the mockup.
class RaisedBox extends StatelessWidget {
  const RaisedBox({super.key, required this.child, this.padding = const EdgeInsets.all(6), this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? context.ez.raised,
      border: Border.all(color: context.ez.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );
}

class EzSwitch extends StatelessWidget {
  const EzSwitch({super.key, required this.value, required this.onChanged, required this.label});
  final bool value;
  final VoidCallback onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onChanged,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: touchUi ? 10 : 0, horizontal: touchUi ? 4 : 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 30,
            height: 16,
            padding: const EdgeInsets.all(1),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? EzColors.cyan : const Color(0xFF3A3D4D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.ez.border),
            ),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? const Color(0xFF06231F) : const Color(0xFFCFD0D8),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.accent = EzColors.cyan,
  });
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: context.ez.raised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.ez.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in options.entries)
          InkWell(
            onTap: () => onChanged(e.key),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: touchUi ? 14 : 9, vertical: touchUi ? 9 : 3),
              decoration: BoxDecoration(
                color: e.key == value ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                e.value,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: e.key == value ? FontWeight.w700 : FontWeight.normal,
                  color: e.key == value ? EzColors.onBrass : context.ez.textDim,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Small uppercase heading text, like the table headers in the mockup.
class HeadText extends StatelessWidget {
  const HeadText(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: color ?? context.ez.textDim),
  );
}

String fmt(Duration d) {
  final m = d.inMinutes.remainder(100).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Where a track lives, shown in the Location column.
String locationOf(Track t) => t.folderPath ?? '';

Future<T?> showMenuAt<T>(BuildContext context, Offset position, List<PopupMenuEntry<T>> items) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
    items: items,
  );
}

/// What is being dragged: songs, and where they came from so a drop in the
/// same list moves them instead of copying.
class SongDrag {
  const SongDrag(this.tracks, {this.playlistId, this.positions = const [], this.queueIds = const []});
  final List<Track> tracks;

  /// Set when dragged out of an open playlist, with their positions in it.
  final int? playlistId;
  final List<int> positions;

  /// Set when dragged out of the queue.
  final List<int> queueIds;
}

/// The drag "chip" that follows the pointer.
Widget dragChip(SongDrag d) => Material(
  color: Colors.transparent,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: EzColors.brass, borderRadius: BorderRadius.circular(6)),
    child: Text(
      d.tracks.length == 1 ? d.tracks.first.title : '${d.tracks.length} songs',
      style: const TextStyle(color: EzColors.onBrass, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  ),
);

/// A list row that songs can be dropped on: the top half drops them before
/// the row, the bottom half after it. A cyan line shows where they'll go.
class InsertTarget extends StatefulWidget {
  const InsertTarget({super.key, required this.index, required this.onDrop, required this.child});
  final int index;
  final void Function(SongDrag drag, int at) onDrop;
  final Widget child;
  @override
  State<InsertTarget> createState() => _InsertTargetState();
}

class _InsertTargetState extends State<InsertTarget> {
  bool? _after; // null: not hovering

  void _track(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final after = box.globalToLocal(global).dy > box.size.height / 2;
    if (after != _after) setState(() => _after = after);
  }

  @override
  Widget build(BuildContext context) => DragTarget<SongDrag>(
    onMove: (d) => _track(d.offset),
    onLeave: (_) => setState(() => _after = null),
    onAcceptWithDetails: (d) {
      if (heldStill[d.data] == true) return setState(() => _after = null);
      final at = widget.index + ((_after ?? false) ? 1 : 0);
      setState(() => _after = null);
      widget.onDrop(d.data, at);
    },
    builder: (context, _, _) => Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _after == false ? EzColors.cyan : Colors.transparent, width: 2),
          bottom: BorderSide(color: _after == true ? EzColors.cyan : Colors.transparent, width: 2),
        ),
      ),
      child: widget.child,
    ),
  );
}

/// Drags that were picked up with press-and-hold and let go without moving:
/// those open the menu instead of dropping anywhere.
final heldStill = Expando<bool>();

/// A song row that can be dragged, with a menu.
///
/// With a mouse it drags straight away and the menu is on right-click. On
/// the tablet it's press-and-hold: move your finger to drag the song, or let
/// go without moving for the menu (a plain swipe still scrolls the list).
class SongDraggable extends StatefulWidget {
  const SongDraggable({super.key, required this.data, required this.onMenu, required this.child, this.onDragStarted});
  final SongDrag data;
  final void Function(Offset at) onMenu;
  final VoidCallback? onDragStarted;
  final Widget child;

  @override
  State<SongDraggable> createState() => _SongDraggableState();
}

class _SongDraggableState extends State<SongDraggable> {
  Offset? _down, _last;
  SongDrag? _active;

  @override
  Widget build(BuildContext context) {
    if (!touchUi) {
      return GestureDetector(
        onSecondaryTapDown: (d) => widget.onMenu(d.globalPosition),
        child: Draggable<SongDrag>(
          data: widget.data,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: widget.onDragStarted,
          feedback: dragChip(widget.data),
          child: widget.child,
        ),
      );
    }
    return Listener(
      onPointerDown: (e) => _down = _last = e.position,
      onPointerMove: (e) {
        _last = e.position;
        final a = _active, d = _down;
        if (a != null && d != null && (e.position - d).distance > 16) heldStill[a] = false;
      },
      child: LongPressDraggable<SongDrag>(
        data: widget.data,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedbackOffset: const Offset(0, -40),
        onDragStarted: () {
          _active = widget.data;
          heldStill[widget.data] = true;
          widget.onDragStarted?.call();
        },
        onDragEnd: (_) {
          final a = _active, at = _last;
          _active = null;
          // Open the menu after the drag has finished tidying up, or it closes
          // again straight away.
          if (a != null && heldStill[a] == true && at != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onMenu(at);
            });
          }
        },
        feedback: dragChip(widget.data),
        child: widget.child,
      ),
    );
  }
}

/// Right-click with a mouse, or press-and-hold on the tablet.
class MenuArea extends StatelessWidget {
  const MenuArea({super.key, required this.onMenu, required this.child});
  final void Function(Offset at) onMenu;
  final Widget child;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onSecondaryTapDown: (d) => onMenu(d.globalPosition),
    onLongPressStart: touchUi ? (d) => onMenu(d.globalPosition) : null,
    child: child,
  );
}

/// The song lists' text size (see [AppState.textScale]): text inside is
/// drawn larger, and [listSize] grows the fixed row heights and columns.
/// Buttons and filters inside keep their size with [ListControls].
class ListText extends StatelessWidget {
  const ListText({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scale = AppScope.of(context).textScale;
    if (scale == 1) return child;
    final outer = MediaQuery.textScalerOf(context);
    return _OuterTextScale(
      scaler: outer,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(outer.scale(14) / 14 * scale)),
        child: child,
      ),
    );
  }
}

/// Buttons and filters inside a [ListText]: they stay their normal size.
class ListControls extends StatelessWidget {
  const ListControls({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final outer = context.dependOnInheritedWidgetOfExactType<_OuterTextScale>();
    if (outer == null) return child;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: outer.scaler),
      child: child,
    );
  }
}

class _OuterTextScale extends InheritedWidget {
  const _OuterTextScale({required this.scaler, required super.child});
  final TextScaler scaler;
  @override
  bool updateShouldNotify(_OuterTextScale old) => old.scaler != scaler;
}

/// A row height or column width in the song lists, grown with the text size,
/// and taller on the tablet so a finger can hit one row.
double listSize(BuildContext context, double v) => v * AppScope.of(context).textScale * (touchUi ? 1.4 : 1);

/// Button padding: compact for a mouse, roomier for a finger on the tablet.
VisualDensity get tapDensity => touchUi ? VisualDensity.standard : VisualDensity.compact;
