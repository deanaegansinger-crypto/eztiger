import '../licence.dart';
import 'licence_dialog.dart';

import 'dart:convert';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../edition.dart';
import '../platform.dart';
import '../sync.dart';
import 'android_folders.dart';
import '../theme.dart';
import 'columns.dart';
import 'common.dart';
import 'lock.dart';
import 'dialogs.dart';
import 'logo.dart';
import 'key_tempo.dart';
import 'pro_sound.dart';
import 'twin_decks.dart';
import 'read_me.dart';
import 'requests_dialog.dart';
import '../song_requests.dart';
import 'songbook_dialog.dart';
import 'transfer_dialogs.dart';

/// The left column of the mockup: player, settings, library, search and
/// results.
class Rack extends StatelessWidget {
  const Rack({super.key});

  @override
  Widget build(BuildContext context) {
    // Pro with 2 decks: deck A and deck B side by side, slimmer.
    final s = AppScope.of(context);
    final twin = isPro && s.twoDecks;
    final folded = isPro && s.searching;
    return Container(
      color: context.ez.panel,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _BrandRow(),
          const SizedBox(height: 8),
          _PlayerFold(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (twin) const TwinDecks() else ...[const PlayerStrip(), const SizedBox(height: 6), const SeekBar()],
                // Pro: while searching, everything under the player folds
                // away so the results get the room.
                if (!folded) ...[
                  if (isPro) const CrossfadeRow(),
                  const _VolumeRow(),
                  if (isPro) const ProSoundRow(),
                  if (!twin) const _DeckLine(),
                ],
              ],
            ),
          ),
          if (!folded) ...[const SizedBox(height: 8), const ListText(child: LibraryTabs())],
          const SizedBox(height: 8),
          // Keyed, so the box (and what is typed in it) stays put when the
          // library tabs above fold away.
          const ListText(key: Key('search-box'), child: SearchBox()),
          const SizedBox(height: 6),
          const Expanded(child: ListText(child: ResultsTable())),
          const _StatusLine(),
        ],
      ),
    );
  }
}

/// On the tablet the on-screen keyboard takes the bottom of the screen, so
/// while typing a search the player folds away, to leave room for the
/// results. Touching a song (to pick it, or drag it to the player or the
/// queue) leaves the search box, and the player opens again; so does hiding
/// the keyboard.
class _PlayerFold extends StatefulWidget {
  const _PlayerFold({required this.child});
  final Widget child;
  @override
  State<_PlayerFold> createState() => _PlayerFoldState();
}

class _PlayerFoldState extends State<_PlayerFold> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The Scaffold hides the keyboard from the MediaQuery below it, so watch
  // the window itself.
  @override
  void didChangeMetrics() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focus = AppScope.of(context).searchFocus;
    return ListenableBuilder(
      listenable: focus,
      builder: (context, _) {
        final keyboardUp = View.of(context).viewInsets.bottom > 0;
        return ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: keyboardUp && focus.hasFocus
                ? const SizedBox(key: Key('player-folded'), width: double.infinity)
                : widget.child,
          ),
        );
      },
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow();
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AppScope.of(context).engine, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final s = AppScope.of(context);
    return Row(
      children: [
        const EzLogo(size: 30),
        const SizedBox(width: 8),
        // Shrinks a little rather than overflow when the top bar is full.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'EZTIGER',
              style: TextStyle(
                fontFamily: brandFont,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: EzColors.brass,
                letterSpacing: 2,
                shadows: [if (EzColors.glow case final g?) Shadow(color: g.withValues(alpha: 0.7), blurRadius: 8)],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Pro: a big gold PRO badge.
        if (isPro) ...[
          Container(
            key: const Key('pro-badge'),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFDE78), Color(0xFFC48A1E)],
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF7A5410)),
            ),
            child: const Text(
              'PRO',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1A1206), letterSpacing: 2),
            ),
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BY DEANO', style: TextStyle(fontSize: 8, color: context.ez.textDim, letterSpacing: 1.2)),
              if (licence != null) const _LicenceChip(),
            ],
          ),
        ] else
          // "BASIC" over "BY DEANO", stacked to save width.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: EzColors.cyan),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'BASIC',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: EzColors.cyan, letterSpacing: 1.5),
                ),
              ),
              const SizedBox(height: 1),
              Text('BY DEANO', style: TextStyle(fontSize: 8, color: context.ez.textDim, letterSpacing: 1.2)),
              if (licence != null) const _LicenceChip(),
            ],
          ),
        const Spacer(),
        if (isPro && s.lockEnabled) const LockButton(),
        TextButton.icon(
          key: const Key('stage-view'),
          style: TextButton.styleFrom(visualDensity: tapDensity, foregroundColor: EzColors.brass),
          onPressed: () => s.setStageView(true),
          icon: const Icon(Icons.mic_external_on, size: 18),
          label: const Text('Stage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const _MainMenu(),
      ],
    );
  }
}

/// "☰ Menu" in the top bar: the Read me, and settings such as text size.
class _MainMenu extends StatelessWidget {
  const _MainMenu();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return PopupMenuButton<String>(
      key: const Key('main-menu'),
      tooltip: 'Menu',
      itemBuilder: (menu) => [
        const PopupMenuItem(
          key: Key('read-me'),
          value: 'readme',
          child: Row(children: [Icon(Icons.help_outline, size: 18), SizedBox(width: 10), Text('Read me')]),
        ),
        const PopupMenuItem(
          value: 'stage',
          child: Row(children: [Icon(Icons.mic_external_on, size: 18), SizedBox(width: 10), Text('Stage view')]),
        ),
        _menuRow(
          menu,
          'Stage lyrics',
          Segmented<bool>(
            key: const Key('menu-lyrics-side'),
            options: const {false: 'Left', true: 'Right'},
            value: s.stageLyricsRight,
            onChanged: s.setStageLyricsRight,
          ),
        ),
        if (isPro)
          _menuRow(
            menu,
            'Double-click',
            Segmented<bool>(
              key: const Key('menu-double-click'),
              options: const {false: 'Player', true: 'Tonight'},
              value: s.doubleClickToQueue,
              onChanged: s.setDoubleClickToQueue,
            ),
          ),
        if (isPro)
          CheckedPopupMenuItem(
            key: const Key('menu-lock-enabled'),
            value: 'lock-enabled',
            checked: s.lockEnabled,
            child: const Text('Screen lock button 🔒'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('menu-songbook'),
          value: 'songbook',
          child: Row(
            children: [
              const Icon(Icons.qr_code_2, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: 'Songbook…',
                    children: [
                      if (s.songbookOutOfDate)
                        TextSpan(
                          text: '  needs updating',
                          style: TextStyle(fontSize: 12, color: EzColors.brass),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          key: const Key('menu-rescan'),
          value: 'rescan',
          enabled: !s.scanning && s.roots.isNotEmpty,
          child: const Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 10),
              Flexible(child: Text('Rescan library')),
            ],
          ),
        ),
        CheckedPopupMenuItem(
          key: const Key('menu-rescan-on-start'),
          value: 'rescanOnStart',
          checked: s.rescanOnStart,
          child: const Text('Rescan at start-up'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text('PLAYBACK', style: TextStyle(fontSize: 11, letterSpacing: 1)),
        ),
        CheckedPopupMenuItem(
          key: const Key('menu-autocue'),
          value: 'autocue',
          checked: s.autocue,
          child: const Text('Autocue'),
        ),
        CheckedPopupMenuItem(
          key: const Key('menu-crossfade'),
          value: 'crossfade',
          checked: s.crossfade,
          child: const Text('Crossfade'),
        ),
        // Pro: two players fed by Tonight's playlist.
        if (s.canTwoDecks)
          CheckedPopupMenuItem(
            key: const Key('menu-two-decks'),
            value: 'two-decks',
            checked: s.twoDecks,
            child: const Text('2 decks'),
          ),
        // Pro sets the time with the crossfade slider under the player.
        if (!isPro)
          _menuRow(
            menu,
            'Fade over',
            Segmented<Duration>(
              key: const Key('fade-length'),
              options: {
                for (final d in AppState.fadeOutChoices)
                  d: d.inMilliseconds % 1000 == 0 ? '${d.inSeconds}s' : '${d.inMilliseconds / 1000}s',
              },
              value: s.fadeOutTime,
              onChanged: s.setFadeOut,
            ),
          ),
        if (s.canSync) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            enabled: false,
            height: 28,
            child: Text('SYNC PC ⇄ TABLET', style: TextStyle(fontSize: 11, letterSpacing: 1)),
          ),
          const PopupMenuItem(
            key: Key('sync-save'),
            value: 'sync-save',
            child: Row(children: [Icon(Icons.upload_file, size: 18), SizedBox(width: 10), Text('Save sync file…')]),
          ),
          const PopupMenuItem(
            key: Key('sync-load'),
            value: 'sync-load',
            child: Row(children: [Icon(Icons.download, size: 18), SizedBox(width: 10), Text('Load sync file…')]),
          ),
          // The tablet: a playlist and its songs, exported by EZTiger Pro.
          if (touchUi) ...[
            const PopupMenuItem(
              key: Key('import-playlist'),
              value: 'import-playlist',
              child: Row(
                children: [Icon(Icons.usb, size: 18), SizedBox(width: 10), Flexible(child: Text('Import playlist…'))],
              ),
            ),
            const PopupMenuItem(
              key: Key('receive-playlist'),
              value: 'receive-playlist',
              child: Row(
                children: [Icon(Icons.wifi, size: 18), SizedBox(width: 10), Flexible(child: Text('Receive from PC…'))],
              ),
            ),
          ],
        ],
        if (licence case final l?) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            key: const Key('menu-licence'),
            value: 'licence',
            child: Row(
              children: [
                const Icon(Icons.key, size: 18),
                const SizedBox(width: 10),
                Text(l.licensed ? 'Pro licence' : 'Enter licence key…'),
                const SizedBox(width: 12),
                if (!l.licensed)
                  Text(
                    l.onTrial ? '${l.trialDaysLeft} days left' : 'trial ended',
                    style: TextStyle(fontSize: 12, color: EzColors.cyan),
                  ),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(),
        if (isPro)
          PopupMenuItem(
            key: const Key('menu-skin'),
            value: 'skins',
            child: Row(
              children: [
                const Icon(Icons.palette_outlined, size: 18),
                const SizedBox(width: 10),
                const Text('Skin'),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    EzSkin.byId(s.skin).name,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: EzColors.cyan),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        if (EzSkin.byId(s.skin).hasLightScreen)
          _menuRow(
            menu,
            'Screen',
            Segmented<bool>(
              key: const Key('menu-theme'),
              options: const {true: 'Dark', false: 'Light'},
              value: s.dark,
              onChanged: (dark) {
                if (dark != s.dark) s.toggleDark();
              },
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text('TEXT SIZE · SONG LISTS', style: TextStyle(fontSize: 11, letterSpacing: 1)),
        ),
        for (final MapEntry(key: scale, value: label) in AppState.textScaleChoices.entries)
          CheckedPopupMenuItem(
            key: Key('text-size-$label'),
            value: 'scale:$scale',
            checked: s.textScale == scale,
            child: Text(label, style: TextStyle(fontSize: 14 * scale)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('menu-requests'),
          value: 'requests',
          child: Row(
            children: [
              const Icon(Icons.record_voice_over_outlined, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: 'Song requests…',
                    children: [
                      if (s.requestsState == RequestsState.connected)
                        TextSpan(text: '  connected', style: TextStyle(fontSize: 12, color: EzColors.green))
                      else if (s.requestsState == RequestsState.unreachable ||
                          s.requestsState == RequestsState.needsCode)
                        TextSpan(text: '  not connected', style: TextStyle(fontSize: 12, color: EzColors.brass)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      onSelected: (c) {
        if (c == 'skins') {
          _pickSkin(context, s);
        } else if (c == 'readme') {
          showReadMe(context);
        } else if (c == 'songbook') {
          showSongbook(context);
        } else if (c == 'requests') {
          showSongRequests(context);
        } else if (c == 'rescan') {
          s.rescan();
        } else if (c == 'rescanOnStart') {
          s.setRescanOnStart(!s.rescanOnStart);
        } else if (c == 'stage') {
          s.setStageView(true);
        } else if (c == 'autocue') {
          s.toggleAutocue();
        } else if (c == 'crossfade') {
          s.toggleCrossfade();
        } else if (c == 'sync-save') {
          saveSyncFile(context, s);
        } else if (c == 'sync-load') {
          loadSyncFile(context, s);
        } else if (c == 'import-playlist') {
          importPlaylist(context);
        } else if (c == 'receive-playlist') {
          receivePlaylist(context);
        } else if (c == 'licence') {
          showLicenceDialog(context, licence!);
        } else if (c == 'lock-enabled') {
          s.setLockEnabled(!s.lockEnabled);
        } else if (c == 'two-decks') {
          s.setTwoDecks(!s.twoDecks);
        } else if (c.startsWith('scale:')) {
          s.setTextScale(double.parse(c.substring(6)));
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: touchUi ? 12 : 8, vertical: touchUi ? 12 : 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu, size: 16, color: EzColors.cyan),
            SizedBox(width: 4),
            Text('Menu', style: TextStyle(fontSize: 11, color: EzColors.cyan)),
          ],
        ),
      ),
    );
  }
}

/// The Pro trial's days left (or "Trial ended · Enter key" in Basic); click
/// for the licence key box. Also says so once when the trial has ended.
class _LicenceChip extends StatefulWidget {
  const _LicenceChip();

  @override
  State<_LicenceChip> createState() => _LicenceChipState();
}

class _LicenceChipState extends State<_LicenceChip> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && licence != null) showTrialEndedOnce(context, licence!);
    });
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: licence!, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final l = licence!;
    if (l.licensed) return const SizedBox.shrink();
    final color = l.onTrial ? EzColors.cyan : EzColors.brass;
    return Tooltip(
      message: l.onTrial
          ? '${l.summary}. Every Pro feature is on during the trial. Click to enter a licence key.'
          : '${l.summary}. Click to enter a licence key.',
      child: InkWell(
        key: const Key('licence-chip'),
        onTap: () => showLicenceDialog(context, l),
        child: Text(
          l.onTrial ? 'TRIAL ${l.trialDaysLeft}d' : 'GET PRO',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
        ),
      ),
    );
  }
}

/// Pro: saves the playlists and keys to EZtiger-sync.json, to load on the
/// tablet (or the PC). It starts in the library folder, so a copy of the
/// library takes it along.
Future<void> saveSyncFile(BuildContext context, AppState s) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final json = await s.exportSync();
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save the sync file for the tablet or PC',
      fileName: LibrarySync.fileName,
      bytes: Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
      initialDirectory: s.roots.firstOrNull?.path,
    );
    if (uri != null) {
      messenger?.showSnackBar(const SnackBar(content: Text('Sync file saved. Load it on the other machine.')));
    }
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Could not save the sync file: $e')));
  }
}

/// Pro: loads a sync file saved on the other machine.
Future<void> loadSyncFile(BuildContext context, AppState s) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Load a sync file from the tablet or PC',
      type: FileType.custom,
      allowedExtensions: ['json'],
      initialDirectory: s.roots.firstOrNull?.path,
    );
    if (files.isEmpty) return;
    final result = await s.importSync(await files.first.xFile.readAsString());
    messenger?.showSnackBar(SnackBar(content: Text(result.summary), duration: const Duration(seconds: 6)));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Could not load the sync file: $e')));
  }
}

/// The list of skins, opened from ☰ Menu → Skin, below the Menu button.
Future<void> _pickSkin(BuildContext context, AppState s) async {
  final box = context.findRenderObject() as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final at = box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay);
  final id = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      const PopupMenuItem(
        enabled: false,
        height: 28,
        child: Text('SKIN', style: TextStyle(fontSize: 11, letterSpacing: 1)),
      ),
      for (final skin in EzSkin.all)
        CheckedPopupMenuItem(
          key: Key('skin-${skin.id}'),
          value: skin.id,
          checked: s.skin == skin.id,
          child: Row(
            children: [
              _SkinSwatch(skin),
              const SizedBox(width: 10),
              Flexible(child: Text(skin.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
    ],
  );
  if (id != null) s.setSkin(id);
}

/// Three little squares of a skin's colours, beside its name in the menu.
class _SkinSwatch extends StatelessWidget {
  const _SkinSwatch(this.skin);
  final EzSkin skin;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in [skin.colors.panel, skin.brass, skin.cyan]) Container(width: 10, height: 14, color: c),
      ],
    ),
  );
}

/// A menu row with a label and a choice of buttons; picking one closes the menu.
PopupMenuItem<String> _menuRow<T>(BuildContext menu, String label, Segmented<T> choice) => PopupMenuItem<String>(
  child: Row(
    children: [
      Expanded(child: Text(label)),
      Segmented<T>(
        key: choice.key,
        options: choice.options,
        value: choice.value,
        onChanged: (v) {
          choice.onChanged(v);
          Navigator.pop(menu);
        },
      ),
    ],
  ),
);

/// The green-screen "VFD" display plus the transport buttons.
class PlayerStrip extends StatelessWidget {
  const PlayerStrip({super.key});

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AppScope.of(context).engine, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final s = AppScope.of(context);
    final e = s.engine;
    final t = e.current;
    final sub = [if (t?.artist != null) t!.artist!, if (e.singer != null) 'Singer: ${e.singer}'].join(' — ');
    return Row(
      children: [
        Expanded(
          child: DragTarget<SongDrag>(
            onAcceptWithDetails: (d) => s.dropOnPlayer(d.data),
            builder: (context, cand, _) => Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: EzColors.vfdBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: cand.isNotEmpty ? EzColors.cyan : EzColors.vfdEdge,
                  width: cand.isNotEmpty ? 2 : 1,
                ),
                boxShadow: [
                  if (EzColors.glow case final g?) BoxShadow(color: g.withValues(alpha: 0.25), blurRadius: 10),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        cand.isNotEmpty
                            ? 'DROP TO PLAY NOW'
                            : (t == null ? 'READY' : (e.playing ? 'NOW PLAYING' : 'CUED')),
                        style: TextStyle(fontFamily: vfdFont, fontSize: 9, color: EzColors.vfdSub, letterSpacing: 2),
                      ),
                      if (isPro) ...[const SizedBox(width: 8), KeyWarning(engine: e)],
                      Expanded(
                        child: Align(alignment: Alignment.centerRight, child: KeyTempo(engine: e)),
                      ),
                      if (t != null) const SizedBox(width: 12),
                      if (t != null)
                        Text(
                          '${fmt(e.position)} / ${fmt(e.duration)}',
                          style: TextStyle(fontFamily: vfdFont, fontSize: 10, color: EzColors.vfdSub),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.error ?? t?.title ?? 'Pick a song to begin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: vfdFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: e.error != null ? EzColors.red : EzColors.vfdTitle,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: vfdFont, fontSize: 11, color: EzColors.vfdText),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Transport(icon: Icons.skip_previous, tooltip: 'Back to the start', onTap: s.previous),
        _Transport(
          icon: e.playing ? Icons.pause : Icons.play_arrow,
          tooltip: e.playing ? 'Pause' : 'Play',
          big: true,
          onTap: s.playPause,
        ),
        _Transport(icon: Icons.skip_next, tooltip: 'Next singer', onTap: s.next),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.icon, required this.onTap, required this.tooltip, this.big = false});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool big;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: big ? EzColors.brass : context.ez.raised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: (big ? 44 : 34) * (touchUi ? 1.4 : 1),
            height: (big ? 44 : 34) * (touchUi ? 1.4 : 1),
            child: Icon(
              icon,
              size: (big ? 26 : 18) * (touchUi ? 1.4 : 1),
              color: big ? EzColors.onBrass : context.ez.text,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The song's progress under the player: click or drag it to skip to any
/// point in the song.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key});
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragMs; // while the thumb is being dragged

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AppScope.of(context).engine, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final e = AppScope.of(context).engine;
    final total = e.duration.inMilliseconds.toDouble();
    final ready = e.current != null && total > 0;
    final at = (_dragMs ?? e.position.inMilliseconds.toDouble()).clamp(0.0, ready ? total : 1.0);
    final style = TextStyle(fontSize: 10, fontFamily: vfdFont, color: context.ez.textDim);
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(fmt(Duration(milliseconds: at.round())), style: style),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: touchUi ? 10 : 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: touchUi ? 22 : 12),
              activeTrackColor: EzColors.cyan,
              thumbColor: EzColors.cyan,
              inactiveTrackColor: context.ez.border,
            ),
            child: Slider(
              key: const Key('seek'),
              value: ready ? at : 0,
              max: ready ? total : 1,
              onChangeStart: ready ? (v) => setState(() => _dragMs = v) : null,
              onChanged: ready ? (v) => setState(() => _dragMs = v) : null,
              onChangeEnd: ready
                  ? (v) async {
                      await e.seek(Duration(milliseconds: v.round()));
                      if (mounted) setState(() => _dragMs = null);
                    }
                  : null,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            ready ? '-${fmt(Duration(milliseconds: (total - at).round()))}' : '--:--',
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// Single / Autoplay, then a short volume bar.
class _VolumeRow extends StatelessWidget {
  const _VolumeRow();
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AppScope.of(context).engine, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final s = AppScope.of(context);
    final e = s.engine;
    return Row(
      children: [
        Segmented<PlayMode>(
          key: const Key('play-mode'),
          options: const {PlayMode.single: 'Single', PlayMode.autoplay: 'Autoplay'},
          value: s.mode,
          onChanged: s.setMode,
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: e.toggleMute,
          child: Padding(
            padding: EdgeInsets.all(touchUi ? 8 : 0),
            child: Icon(e.muted ? Icons.volume_off : Icons.volume_up, size: 18, color: context.ez.textDim),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context)
                .copyWith(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: touchUi ? 10 : 6)),
            child: Slider(value: e.muted ? 0 : e.volume, max: 100, activeColor: EzColors.brass, onChanged: e.setVolume),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${(e.muted ? 0 : e.volume).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: context.ez.textDim),
          ),
        ),
      ],
    );
  }
}

/// "📁 Library" and "★ Playlists" tabs.
class LibraryTabs extends StatefulWidget {
  const LibraryTabs({super.key});
  @override
  State<LibraryTabs> createState() => _LibraryTabsState();
}

class _LibraryTabsState extends State<LibraryTabs> {
  int tab = 0;

  /// Picks a tab, and unfolds the box if it was folded away.
  void _show(AppState s, int t) {
    setState(() => tab = t);
    if (s.libraryCollapsed) s.setLibraryCollapsed(false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final collapsed = s.libraryCollapsed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListControls(
          child: Row(
            children: [
              _TabButton(label: '📁 Library', selected: tab == 0 && !collapsed, onTap: () => _show(s, 0)),
              const SizedBox(width: 6),
              DragTarget<SongDrag>(
                onWillAcceptWithDetails: (_) {
                  if (tab != 1 || collapsed) _show(s, 1);
                  return false;
                },
                builder: (context, _, _) =>
                    _TabButton(label: '★ Playlists', selected: tab == 1 && !collapsed, onTap: () => _show(s, 1)),
              ),
              const Spacer(),
              // Shrinks a little rather than spill over when space is tight.
              if (tab == 0 && !collapsed)
                const Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [_RescanButton(), _AddFolderButton()]),
                  ),
                ),
              IconButton(
                key: const Key('library-fold'),
                tooltip: collapsed ? 'Show folders and playlists' : 'Fold away, for more room for songs',
                visualDensity: tapDensity,
                onPressed: () => s.setLibraryCollapsed(!collapsed),
                icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less, size: 20, color: context.ez.textDim),
              ),
            ],
          ),
        ),
        if (!collapsed) ...[
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: listSize(context, 150), minHeight: 60),
            child: RaisedBox(
              padding: const EdgeInsets.all(4),
              child: tab == 0 ? const FolderTree() : const PlaylistsPanel(),
            ),
          ),
        ],
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: touchUi ? 14 : 10, vertical: touchUi ? 10 : 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: selected ? EzColors.brass : Colors.transparent, width: 2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          color: selected ? context.ez.text : context.ez.textDim,
        ),
      ),
    ),
  );
}

class _AddFolderButton extends StatelessWidget {
  const _AddFolderButton();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return TextButton.icon(
      style: TextButton.styleFrom(visualDensity: tapDensity, foregroundColor: EzColors.brass),
      icon: const Icon(Icons.create_new_folder_outlined, size: 16),
      label: const Text('Add folder', style: TextStyle(fontSize: 11)),
      onPressed: s.scanning
          ? null
          : () async {
              final path = touchUi
                  ? await pickAndroidFolder(context)
                  : await FilePicker.getDirectoryPath(dialogTitle: 'Choose a karaoke folder');
              if (path != null) await s.addRootFolder(path);
            },
    );
  }
}

/// "🔄 Rescan": finds songs added, removed or renamed since the last scan.
class _RescanButton extends StatelessWidget {
  const _RescanButton();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return TextButton.icon(
      key: const Key('rescan'),
      style: TextButton.styleFrom(visualDensity: tapDensity, foregroundColor: EzColors.brass),
      icon: const Icon(Icons.refresh, size: 16),
      label: const Text('Rescan', style: TextStyle(fontSize: 11)),
      onPressed: s.scanning || s.roots.isEmpty ? null : s.rescan,
    );
  }
}

class FolderTree extends StatelessWidget {
  const FolderTree({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (s.roots.isEmpty) {
      return Center(
        child: Text(
          'No folders yet. Press "Add folder" and pick your backing tracks folder.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.ez.textDim),
        ),
      );
    }
    final rows = <(Folder, int)>[];
    void add(Folder f, int depth) {
      rows.add((f, depth));
      if (s.expanded.contains(f.id)) {
        for (final c in s.children[f.id] ?? const <Folder>[]) {
          add(c, depth + 1);
        }
      }
    }

    for (final r in s.roots) {
      add(r, 0);
    }
    return ListView(
      shrinkWrap: true,
      children: [
        _FolderRow(
          label: 'All folders',
          depth: 0,
          selected: s.selectedFolderId == null,
          onTap: () => s.selectFolder(null),
        ),
        for (final (f, d) in rows) _FolderTile(folder: f, depth: d),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.depth});
  final Folder folder;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final f = folder;
    Future<void> menu(Offset at) async {
      final choice = await showMenuAt<String>(context, at, [
        if (f.included)
          const PopupMenuItem(value: 'exclude', child: Text('✓ In searchable library — remove'))
        else
          const PopupMenuItem(value: 'include', child: Text('➕ Add to searchable library')),
        if (f.isRoot) const PopupMenuItem(value: 'rescan', child: Text('🔄 Rescan')),
        if (f.isRoot) const PopupMenuItem(value: 'forget', child: Text('🗑 Forget this folder')),
      ]);
      switch (choice) {
        case 'include':
          await s.setFolderIncluded(f, true);
        case 'exclude':
          await s.setFolderIncluded(f, false);
        case 'rescan':
          await s.rescan();
        case 'forget':
          await s.removeRootFolder(f);
      }
    }

    final selected = s.selectedFolderId == f.id;
    final row = _FolderRow(
      label: f.name,
      depth: depth,
      count: f.totalCount,
      included: f.included,
      expandable: f.hasChildren,
      expanded: s.expanded.contains(f.id),
      selected: selected,
      onTap: () => s.selectFolder(f.id),
      onToggle: () => s.toggleExpanded(f),
    );
    // Pro: the highlighted folder drags as a whole, all its songs (as listed
    // below), into Tonight's playlist, a playlist or the player.
    final songs = isPro && selected && s.view == ResultsView.search ? s.results.map((g) => g.primary).toList() : null;
    if (songs != null && songs.isNotEmpty) {
      return SongDraggable(key: Key('folder-drag-${f.id}'), data: SongDrag(songs), onMenu: menu, child: row);
    }
    return MenuArea(onMenu: menu, child: row);
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.label,
    required this.depth,
    required this.selected,
    required this.onTap,
    this.count,
    this.included = true,
    this.expandable = false,
    this.expanded = false,
    this.onToggle,
  });
  final String label;
  final int depth;
  final bool selected, included, expandable, expanded;
  final int? count;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    onDoubleTap: onToggle,
    child: Container(
      color: selected ? EzColors.brass.withValues(alpha: 0.18) : null,
      padding: EdgeInsets.only(left: 4.0 + depth * 14, right: 6, top: 2, bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: expandable
                ? InkWell(onTap: onToggle, child: Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 14))
                : null,
          ),
          Icon(
            expanded ? Icons.folder_open : Icons.folder,
            size: 14,
            color: included ? EzColors.brass : context.ez.textDim,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: included ? context.ez.text : context.ez.textDim),
            ),
          ),
          if (count != null) Text('$count', style: TextStyle(fontSize: 10, color: context.ez.textDim)),
          if (count != null && included)
            Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text('✓', style: TextStyle(fontSize: 10, color: EzColors.cyan)),
            ),
        ],
      ),
    ),
  );
}

class PlaylistsPanel extends StatelessWidget {
  const PlaylistsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListView(
      shrinkWrap: true,
      children: [
        Row(
          children: [
            DragTarget<SongDrag>(
              onAcceptWithDetails: (d) async {
                final name = await askText(
                  context,
                  title: 'New playlist with ${d.data.tracks.length} songs',
                  label: 'Name',
                );
                if (name != null) await s.createPlaylist(name, tracks: d.data.tracks);
              },
              builder: (context, cand, _) => Container(
                decoration: BoxDecoration(
                  color: cand.isNotEmpty ? EzColors.cyan.withValues(alpha: 0.25) : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: TextButton(
                  style: TextButton.styleFrom(visualDensity: tapDensity, foregroundColor: EzColors.brass),
                  onPressed: () async {
                    final name = await askText(context, title: 'New playlist', label: 'Name');
                    if (name != null) await s.createPlaylist(name);
                  },
                  child: Text(
                    cand.isNotEmpty ? '+ Drop here for a new playlist' : '+ Create',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(visualDensity: tapDensity),
              onPressed: s.openHistory,
              child: const Text('🕘 History', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        if (s.playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              queueWords(
                'Drag songs from the list or the queue onto "+ Create" to make a playlist, '
                'or press "★ Save as playlist" on the queue.',
              ),
              style: TextStyle(fontSize: 11, color: context.ez.textDim),
            ),
          ),
        for (final p in s.playlists)
          DragTarget<SongDrag>(
            onAcceptWithDetails: (d) => s.addToPlaylist(p.id, d.data.tracks),
            builder: (context, cand, _) => MenuArea(
              onMenu: (at) async {
                final c = await showMenuAt<String>(context, at, [
                  const PopupMenuItem(value: 'open', child: Text('Open')),
                  PopupMenuItem(
                    value: 'paste',
                    child: Text(
                      s.copied.isEmpty ? '📋 Paste songs or a song list' : '📋 Paste ${s.copied.length} copied songs',
                    ),
                  ),
                  PopupMenuItem(value: 'queue', child: Text('Save $theQueue into this playlist')),
                  PopupMenuItem(value: 'toqueue', child: Text('➕ Add the whole playlist to $theQueue')),
                  // Pro on the PC: the playlist and its songs to the tablet.
                  if (isPro && !touchUi) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      key: Key('playlist-export'),
                      value: 'export',
                      child: Text('📤 Export to USB, SD card or Dropbox…'),
                    ),
                    const PopupMenuItem(
                      key: Key('playlist-send'),
                      value: 'send',
                      child: Text('📶 Send to the tablet over Wi-Fi…'),
                    ),
                    const PopupMenuDivider(),
                  ],
                  const PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                ]);
                switch (c) {
                  case 'open':
                    await s.openPlaylist(p);
                  case 'paste':
                    await pasteInto(s, p.id);
                  case 'queue':
                    await s.saveQueueTo(p.id);
                  case 'toqueue':
                    await s.enqueueAll(await s.db.playlists.tracks(p.id));
                  case 'export':
                    if (context.mounted) await showExportPlaylist(context, p);
                  case 'send':
                    if (context.mounted) await showSendPlaylist(context, p);
                  case 'delete':
                    await s.deletePlaylist(p);
                }
              },
              child: InkWell(
                onTap: () => s.openPlaylist(p),
                child: Container(
                  color: cand.isNotEmpty
                      ? EzColors.cyan.withValues(alpha: 0.25)
                      : (s.view == ResultsView.playlist && s.selectedPlaylistId == p.id
                            ? EzColors.brass.withValues(alpha: 0.18)
                            : null),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Row(
                    children: [
                      Text('★ ', style: TextStyle(color: EzColors.brass, fontSize: 12)),
                      Expanded(
                        child: Text(p.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      ),
                      Text('${p.trackCount}', style: TextStyle(fontSize: 10, color: context.ez.textDim)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Pastes into a playlist: songs copied with Ctrl+C, or a song list copied
/// from Notepad, Word or Excel (one song per line).
Future<void> pasteInto(AppState s, int playlistId) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  await s.paste(playlistId, data?.text);
}

class SearchBox extends StatefulWidget {
  const SearchBox({super.key});
  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _c = TextEditingController();
  late final FocusNode _focus = AppScope.of(context).searchFocus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _focus.removeListener(_update);
    _focus.addListener(_update);
  }

  /// Pro folds the controls away while the box has the focus or a search in
  /// it; ✕ (or emptying the box and leaving it) brings them back.
  void _update() => AppScope.of(context).setSearching(_focus.hasFocus || _c.text.isNotEmpty);

  @override
  void dispose() {
    _focus.removeListener(_update);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return TextField(
      key: const Key('search'),
      controller: _c,
      focusNode: _focus,
      onChanged: (q) {
        s.setQuery(q);
        _update();
      },
      // Clicking elsewhere leaves the box, so Space goes back to play/pause.
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search title, artist or lyrics…',
        prefixIcon: const Padding(
          padding: EdgeInsets.all(8),
          child: Text('🔍', style: TextStyle(fontSize: 14)),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 32),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  _c.clear();
                  s.setQuery('');
                  _focus.unfocus();
                  _update();
                },
              ),
        filled: true,
        fillColor: context.ez.raised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: context.ez.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: context.ez.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: EzColors.brass),
        ),
      ),
    );
  }
}

class TypeChip extends StatelessWidget {
  const TypeChip(this.type, {super.key});
  final TrackType type;
  @override
  Widget build(BuildContext context) {
    final c = EzColors.forType(type.label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}

class ResultsTable extends StatefulWidget {
  const ResultsTable({super.key});
  @override
  State<ResultsTable> createState() => _ResultsTableState();
}

class _ResultsTableState extends State<ResultsTable> {
  final focus = FocusNode(debugLabel: 'results');

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(AppState s, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final k = e.logicalKey;
    if (ctrl && k == LogicalKeyboardKey.keyA) {
      s.selectAll();
    } else if (ctrl && k == LogicalKeyboardKey.keyC) {
      final tracks = s.selectedTracks();
      if (tracks.isNotEmpty) Clipboard.setData(ClipboardData(text: s.copy(tracks)));
    } else if (ctrl && k == LogicalKeyboardKey.keyV && s.view == ResultsView.playlist && s.selectedPlaylistId != null) {
      pasteInto(s, s.selectedPlaylistId!);
    } else if ((k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) &&
        s.view == ResultsView.playlist) {
      s.removeSelectedFromPlaylist();
    } else if (k == LogicalKeyboardKey.enter) {
      s.enqueueAll(s.selectedTracks());
    } else if (k == LogicalKeyboardKey.escape && s.selection.isNotEmpty) {
      s.clearSelection();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final groups = s.results;
    final label = switch (s.view) {
      ResultsView.search => s.query.isEmpty ? 'Browse' : 'Search results',
      ResultsView.playlist => 'Playlist (drag to reorder)',
      ResultsView.history => 'Sung',
    };
    final n = s.selection.length;
    return Focus(
      focusNode: focus,
      onKeyEvent: (_, e) => _onKey(s, e),
      // Short on room with the tablet's keyboard up: the filter bar steps
      // aside so the songs still show. (Rebuilt as the keyboard resizes it.)
      child: LayoutBuilder(
        builder: (context, c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$label · ${s.resultsTitle} · ${groups.length} ${groups.length == 1 ? 'match' : 'matches'}'
            '${n > 1 ? ' · $n selected (drag them, or Ctrl+C)' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: context.ez.textDim),
          ),
          const SizedBox(height: 4),
          if (s.scanning) const LoadingBanner(),
          if (View.of(context).viewInsets.bottom == 0 || c.maxHeight >= listSize(context, 220)) const _FilterBar(),
          const _ResultsHeader(),
          Expanded(
            child: groups.isEmpty
                ? DragTarget<SongDrag>(
                    onWillAcceptWithDetails: (_) => s.view == ResultsView.playlist && s.selectedPlaylistId != null,
                    onAcceptWithDetails: (d) => s.dropIntoPlaylist(s.selectedPlaylistId!, d.data, 0),
                    builder: (context, _, _) => Center(
                      child: Text(
                        s.view == ResultsView.playlist
                            ? 'Empty playlist. Drag songs here, or right-click it and paste.'
                            : s.roots.isEmpty
                            ? 'Add a folder to start.'
                            : (s.scanning ? 'Loading your songs… please wait.' : 'Nothing found.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.ez.textDim),
                      ),
                    ),
                  )
                : DragTarget<SongDrag>(
                    onWillAcceptWithDetails: (_) => s.view == ResultsView.playlist && s.selectedPlaylistId != null,
                    onAcceptWithDetails: (d) => s.dropIntoPlaylist(s.selectedPlaylistId!, d.data, groups.length),
                    builder: (context, _, _) => ListView.builder(
                      itemCount: groups.length,
                      itemExtent: listSize(context, 28),
                      itemBuilder: (context, i) => ResultRow(group: groups[i], index: i, focus: focus),
                    ),
                  ),
          ),
        ],
      ),
      ),
    );
  }
}

/// "Type: All CDG MP4 MP3" and "Sort: Best match / Title A–Z / Artist A–Z".
class _FilterBar extends StatelessWidget {
  const _FilterBar();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final label = TextStyle(fontSize: 11, color: context.ez.textDim);
    return ListControls(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Type ', style: label),
                Segmented<TrackType?>(
                  key: const Key('type-filter'),
                  options: {null: 'All', for (final t in TrackType.values) t: t.label},
                  value: s.typeFilter,
                  onChanged: s.setTypeFilter,
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Sort ', style: label),
                Segmented<SearchSort>(
                  key: const Key('sort'),
                  options: const {
                    SearchSort.relevance: 'Best match',
                    SearchSort.title: 'Title A–Z',
                    SearchSort.artist: 'Artist A–Z',
                  },
                  value: s.sort,
                  onChanged: s.setSort,
                  accent: EzColors.brass,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    Widget sortable(String text, SearchSort by) => InkWell(
      onTap: () => s.setSort(s.sort == by ? SearchSort.relevance : by),
      child: Row(
        children: [
          Flexible(child: HeadText(text, color: s.sort == by ? EzColors.brass : null)),
          if (s.sort == by) Icon(Icons.arrow_downward, size: 11, color: EzColors.brass),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.ez.border)),
      ),
      child: ColumnsHeader(
        table: 'results',
        columns: resultColumns,
        headings: {'title': sortable('Title', SearchSort.title), 'artist': sortable('Artist', SearchSort.artist)},
      ),
    );
  }
}

class ResultRow extends StatefulWidget {
  const ResultRow({super.key, required this.group, required this.index, this.focus});
  final SearchGroup group;
  final int index;
  final FocusNode? focus;
  @override
  State<ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<ResultRow> {
  bool _dragged = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final group = widget.group, index = widget.index;
    final t = group.primary;
    final selected = s.selection.contains(index);
    final row = InkWell(
      // Loads it, paused, like dropping it on the player. With 2 decks and a
      // song playing, it goes on the other deck as the next song.
      onDoubleTap: () => isPro && s.doubleClickToQueue
          ? s.enqueue(t)
          : isPro && s.twoDecks
          ? s.loadNext([t])
          : s.playNow(t, autostart: false),
      child: Container(
        color: selected
            ? EzColors.brass.withValues(alpha: 0.28)
            : (index.isOdd ? context.ez.raised.withValues(alpha: 0.4) : null),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: ColumnsRow(
          table: 'results',
          columns: resultColumns,
          cells: {
            'title': Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: t.title),
                  if (t.version != null)
                    TextSpan(
                      text: '  ${t.version}',
                      style: TextStyle(color: context.ez.textDim, fontSize: 10),
                    ),
                  if (group.versions.length > 1)
                    TextSpan(
                      text: '  ×${group.versions.length}',
                      style: TextStyle(color: EzColors.cyan, fontSize: 10),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            'artist': Text(
              t.artist ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: context.ez.textDim),
            ),
            'type': Align(alignment: Alignment.centerLeft, child: TypeChip(t.type)),
            'location': Text(
              locationOf(t),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontFamily: vfdFont, color: context.ez.textDim),
            ),
          },
        ),
      ),
    );
    final rows = s.selectedRows(orRow: index);
    final inPlaylist = s.view == ResultsView.playlist ? s.selectedPlaylistId : null;
    final dragging = SongDrag([for (final r in rows) s.results[r].primary], playlistId: inPlaylist, positions: rows);
    return Listener(
      onPointerDown: (e) {
        widget.focus?.requestFocus();
        _dragged = false;
        final keys = HardwareKeyboard.instance;
        final shift = keys.isShiftPressed, ctrl = keys.isControlPressed;
        if (e.buttons == kSecondaryMouseButton) {
          if (!selected) s.selectRow(index);
        } else if (shift || ctrl) {
          s.selectRow(index, shift: shift, ctrl: ctrl);
        } else if (!selected) {
          s.selectRow(index);
        }
      },
      onPointerUp: (e) {
        final keys = HardwareKeyboard.instance;
        // A plain click inside a block (without dragging) narrows it to one row.
        if (!_dragged &&
            selected &&
            s.selection.length > 1 &&
            !keys.isShiftPressed &&
            !keys.isControlPressed &&
            e.kind == PointerDeviceKind.mouse &&
            e.buttons == 0 &&
            e.down == false) {
          s.selectRow(index);
        }
      },
      child: SongDraggable(
        data: dragging,
        onMenu: (at) => trackMenu(context, at, group, tracks: s.selectedTracks(orRow: index)),
        onDragStarted: () => _dragged = true,
        child: inPlaylist == null
            ? row
            : InsertTarget(index: index, onDrop: (d, at) => s.dropIntoPlaylist(inPlaylist, d, at), child: row),
      ),
    );
  }
}

/// Right-click menu for one song or a block of selected songs.
Future<void> trackMenu(BuildContext context, Offset at, SearchGroup group, {required List<Track> tracks}) async {
  final s = AppScope.of(context);
  final t = group.primary;
  final many = tracks.length > 1;
  final n = '${tracks.length} songs';
  final inPlaylist = s.view == ResultsView.playlist;
  final choice = await showMenuAt<String>(context, at, [
    PopupMenuItem(value: 'queue', child: Text(many ? '➕ Add $n to $theQueue' : queueWords('➕ Add to queue'))),
    if (!many) PopupMenuItem(value: 'singer', child: Text(queueWords('🎤 Add to queue with singer…'))),
    if (!many) const PopupMenuItem(value: 'play', child: Text('▶ Play now')),
    if (!many && group.versions.length > 1) const PopupMenuItem(value: 'versions', child: Text('🎚 Other versions…')),
    const PopupMenuDivider(),
    PopupMenuItem(value: 'new', child: Text(many ? '★ New playlist from these $n…' : '★ New playlist with this song…')),
    for (final p in s.playlists) PopupMenuItem(value: 'pl:${p.id}', child: Text('★ Add to ${p.name}')),
    PopupMenuItem(value: 'copy', child: Text(many ? '📋 Copy $n   Ctrl+C' : '📋 Copy   Ctrl+C')),
    if (inPlaylist)
      PopupMenuItem(
        value: 'unlist',
        child: Text(many ? 'Remove $n from this playlist   Del' : 'Remove from this playlist   Del'),
      ),
    if (!many) const PopupMenuItem(value: 'edit', child: Text('✏️ Edit tags…')),
    // Pro on Windows: the AI instrumental, saved in Music\EZVocalremoved.
    if (isPro && s.vocalRemover != null) ...[
      const PopupMenuDivider(),
      PopupMenuItem(
        key: const Key('menu-remove-vocals'),
        value: 'vocals',
        child: Text(
          many
              ? '🎤 Remove vocals (AI) from $n'
              : s.hasInstrumental(t)
                  ? '🎤 Remove vocals (AI) again'
                  : '🎤 Remove vocals (AI)',
        ),
      ),
    ],
  ]);
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case 'queue':
      await s.enqueueAll(tracks);
    case 'singer':
      final name = await askText(context, title: 'Who is singing?', label: 'Singer');
      if (name != null) await s.enqueue(t, singer: name);
    case 'play':
      await s.playNow(t);
    case 'versions':
      final v = await pickVersion(context, group);
      if (v != null) await s.enqueue(v);
    case 'new':
      final name = await askText(context, title: 'New playlist', label: 'Name');
      if (name != null) await s.createPlaylist(name, tracks: tracks);
    case 'copy':
      await Clipboard.setData(ClipboardData(text: s.copy(tracks)));
    case 'unlist':
      await s.removeSelectedFromPlaylist();
    case 'edit':
      await showEditTags(context, t);
    case 'vocals':
      s.removeVocals(many ? tracks : [t]);
    default:
      if (choice.startsWith('pl:')) await s.addToPlaylist(int.parse(choice.substring(3)), tracks);
  }
}

/// Shown over the song list while the library is being read, so nobody
/// thinks the app has stopped working.
class LoadingBanner extends StatelessWidget {
  const LoadingBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListControls(
      child: Container(
        key: const Key('loading-banner'),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: EzColors.cyan.withValues(alpha: 0.15),
          border: Border.all(color: EzColors.cyan),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: EzColors.cyan)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Loading your song library… please wait',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: EzColors.cyan),
                  ),
                  Text(
                    'It\'s working: a big collection can take a minute. ${s.status}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.ez.textDim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          if (s.scanning) const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
          if (s.scanning) const SizedBox(width: 6),
          Expanded(
            child: Text(
              s.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: context.ez.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

/// In 2-deck mode: which deck is playing, and the song waiting on the other.
class _DeckLine extends StatelessWidget {
  const _DeckLine();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final sb = s.standby;
    if (sb == null) return const SizedBox.shrink();
    final live = s.liveDeck == 0 ? 'A' : 'B', other = s.liveDeck == 0 ? 'B' : 'A';
    final waiting = s.standbyQueueId != null ? sb.current?.title : null;
    return Padding(
      key: const Key('deck-line'),
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'On deck $live  ·  deck $other: ${waiting == null ? 'nothing cued' : 'next ready, $waiting'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: context.ez.textDim),
      ),
    );
  }
}
