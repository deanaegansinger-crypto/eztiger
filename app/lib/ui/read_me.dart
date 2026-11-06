import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import 'common.dart';

final _scroll = ScrollController();

/// "Read me": a short how-to, opened from the button at the top.
Future<void> showReadMe(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(touchUi ? 'EZTiger for Android · Read me' : 'EZTiger Basic · Read me'),
    content: SizedBox(
      width: 600,
      // Tall enough to show it all on most screens, and scrolls (with a
      // visible bar) when it isn't.
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.only(right: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'THANKS for using my first ever Claude created App - ENJOY!!',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: EzColors.brass),
                ),
              ),
              for (final (head, lines)
                  in touchUi ? [_tablet, ..._sections.where((x) => x != _secondScreen)] : _sections) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: HeadText(head, color: EzColors.brass),
                ),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ', style: TextStyle(fontSize: 13)),
                        Expanded(child: Text(l, style: const TextStyle(fontSize: 13, height: 1.3))),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
  ),
);

const _sections = <(String, List<String>)>[
  (
    'Getting started',
    [
      'Library tab: click Add folder and pick your karaoke folder. EZtiger scans it, and rescans it each time it starts.',
      'Type in the search box to find songs by title or artist. Use the type filter (CDG, MP4…) and the A–Z sort above the list.',
    ],
  ),
  (
    'Playing',
    [
      'Double-click a song in the list to load it into the player, paused. Or drag it onto the player.',
      'Space plays and pauses. ⏮ goes back to the start, ⏭ (or Ctrl+→) moves on to the next song in the queue.',
      'Drag the bar under the player to skip through a song.',
    ],
  ),
  (
    'The queue',
    [
      'Drag songs onto the queue, or select them and press Enter. Drop between rows to put them exactly where you want.',
      'Right-click a queued song to set the singer, play it now, or remove it.',
      'Sung songs stay in the queue with a ✓, the time they were played and the singer. "Clear played" takes them off.',
    ],
  ),
  (
    'Mode, Crossfade and Autocue',
    [
      'Single stops after each song. Autoplay goes straight on to the next one in the queue.',
      'Autocue loads the next song ready to go, and starts it at its first note, past the silence at the start.',
      'Crossfade fades out before the silence at the end of a song (over 4 s, 2 s or 0.2 s, down to a third of the volume) and brings the next song in at its first note.',
    ],
  ),
  (
    'Playlists',
    [
      'Select songs (click, Shift+click for a block, Ctrl+click to pick, Ctrl+A for all) and drag them onto a playlist or onto + Create.',
      'Ctrl+C copies the selected songs as a text list; Ctrl+V pastes a song list (from Notepad or an email) into an open playlist.',
      'To sing a saved playlist: press "📂 Load playlist" above the queue and pick it. Its songs go to the end of the queue.',
      'To keep the songs in the queue: press "★ Save as playlist" above the queue and give it a name, or add them to a playlist you already have. You can also drag that button onto a playlist.',
      'Single songs in the queue: drag one onto a playlist, or right-click it for "★ Add to …".',
      'Right-click a playlist to open it, paste into it, save the queue to it, or send it all to the queue.',
    ],
  ),
  _secondScreen,
  (
    'Your settings',
    [
      '🎤 Stage, top right: the view for performing, with the tablet on the mic stand. Lyrics large on the left; the song, time left, big Restart / Play / Next buttons, the volume and the next songs on the right. Double-tap a song in Up next to play it now, or the lyrics for full screen. The ⇄ button (or the Menu) swaps the lyrics to the other side. Library goes back. EZtiger opens in the view you used last.',
      '☰ Menu, top right: the Read me, Dark or Light screen, and Text size, which makes the song lists larger (Normal, Large or Extra large). The player and lyrics stay as they are.',
      'EZtiger remembers your settings, volume and the loaded song for next time.',
    ],
  ),
];

const _secondScreen = (
  'Second screen',
  [
    'Double-click the karaoke output panel to show the lyrics full screen; double-click again or press Esc to come back.',
    'Click "2nd screen" on the output panel to open the lyrics window. With two monitors it goes full screen on the other one.',
    'In that window, double-click or press F11 to switch full screen on or off; Esc leaves full screen.',
  ],
);

const _tablet = (
  'On the tablet',
  [
    'Add folder: allow EZtiger to "manage all files" when Android asks (it needs that to read CDG and lyric files), then pick SD card and your karaoke folder.',
    'Double-tap a song to load it into the player. Press and hold a song, then move your finger to drag it onto the queue, the player or a playlist.',
    'Press and hold and let go without moving for the menu (what right-click does on Windows): add to queue, set the singer, playlists and more.',
    'Double-tap the karaoke output panel for full screen lyrics; double-tap again or press Back to come out of it. The screen stays on while EZtiger is open.',
  ],
);
