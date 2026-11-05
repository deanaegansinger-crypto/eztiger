import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

final _scroll = ScrollController();

/// "Read me": a short how-to, opened from the button at the top.
Future<void> showReadMe(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('EZTiger Basic · Read me'),
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
              for (final (head, lines) in _sections) ...[
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
      'Right-click a playlist to open it, paste into it, save the queue to it, or send it all to the queue.',
    ],
  ),
  (
    'Second screen',
    [
      'Click "2nd screen" on the output panel to open the lyrics window. With two monitors it goes full screen on the other one.',
      'In that window, double-click or press F11 to switch full screen on or off; Esc leaves full screen.',
    ],
  ),
  ('Your settings', ['EZtiger remembers your settings, volume and the loaded song for next time.']),
];
