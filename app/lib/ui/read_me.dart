import '../licence.dart';

import 'package:flutter/material.dart';

import '../edition.dart';
import '../platform.dart';
import '../theme.dart';
import 'common.dart';

final _scroll = ScrollController();

/// "Read me": a short how-to, opened from the button at the top.
Future<void> showReadMe(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(touchUi ? '$editionName for Android · Read me' : '$editionName · Read me'),
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
              if (isPro && !touchUi) const _ShortcutsMenu(),
              for (final (head, lines)
                  in touchUi
                      ? [
                          _tablet,
                          if (isPro) (_pro.$1, _pro.$2.where(_onTablet).toList()),
                          ..._sections.where((x) => x != _secondScreen),
                        ]
                      : [if (isPro) _pro, ..._sections]) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: HeadText(queueWords(head), color: EzColors.brass),
                ),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ', style: TextStyle(fontSize: 13)),
                        Expanded(child: Text(queueWords(l), style: const TextStyle(fontSize: 13, height: 1.3))),
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

/// Every keyboard shortcut, folded away at the top of the Read me (Windows Pro).
const _shortcuts = <(String, List<(String, String)>)>[
  (
    'Playing',
    [
      ('Space', 'Play / pause'),
      ('R', 'Back to the start of the song'),
      ('N  or  Ctrl+→', 'Next song'),
      ('X', 'Mix into the next deck now (2 decks)'),
      ('Z', 'Back 5 seconds'),
      ('C', 'Forward 5 seconds'),
    ],
  ),
  (
    'Sound',
    [
      ('U', 'Volume up'),
      ('D', 'Volume down'),
      ('M', 'Mute on / off'),
      ('K', 'Key up a semitone'),
      ('L', 'Key down a semitone'),
      ('0', "Back to the song's own key"),
    ],
  ),
  (
    'Songs',
    [
      ('/', 'Jump to the search box'),
      ('Q  or  Enter', "Add the selected songs to Tonight's playlist"),
      ('Shift+Q', 'Make the selected song the next one'),
      ('Ctrl+A', 'Select all songs in the list'),
      ('Ctrl+C', 'Copy the selected songs as a text list'),
      ('Ctrl+V', 'Paste a song list into the open playlist'),
      ('Delete', 'Take the selected songs off the open playlist'),
      ('Esc', 'Clear the selection'),
    ],
  ),
  (
    'Screen',
    [
      ('S', 'Stage view on / off'),
      ('F11', 'Full screen on / off (Esc leaves it)'),
      ('B', 'Lock the screen 🔒 (press and hold the lock to unlock)'),
      ('F1', 'This Read me'),
    ],
  ),
];

class _ShortcutsMenu extends StatelessWidget {
  const _ShortcutsMenu();

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      key: const Key('read-me-shortcuts'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 4, bottom: 6),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(
        '⌨  Keyboard shortcuts',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: EzColors.brass),
      ),
      subtitle: const Text(
        'Single keys, one hand. They wait while you type in the search box, and while the screen is locked.',
        style: TextStyle(fontSize: 12),
      ),
      children: [
        for (final (group, keys) in _shortcuts) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(group, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          for (final (key, what) in keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: Text(queueWords(what), style: const TextStyle(fontSize: 13, height: 1.3))),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

const _pro = (
  'EZTiger Pro',
  [
    'KEY, under the volume: − and + move the song down or up a semitone, as far as 3 either way. The 0 in the middle puts it back. EZTiger remembers the key for each song, and when a song loads in a changed key, "KEY +2" (or −) flashes red on the player and the Stage view.',
    'Level, under the volume: evens out the loudness, so quiet and loud MP3s and videos play at about the same level. It takes a moment to settle at the start of a song.',
    'Vocal cut, under the volume: takes out the lead vocal on most stereo tracks. It finds what sits in the middle, frequency by frequency, and takes just that out, keeping the rest of the mix, its stereo spread and the bass. It works best on studio recordings; an instrument in the middle with the singer comes down a little too, and reverb and backing vocals can still come through.',
    '2 decks (☰ Menu, under Playback): deck A and deck B sit side by side across the top and share Tonight\'s playlist. The deck marked ON AIR is playing; the other shows the song waiting to come in, ready to start straight away. Its ⇄ button mixes into it now.',
    'Stage view with 2 decks: both decks run across the top of the screen, with Restart / Play / Next on the deck ON AIR and ⇄ on the next one, so the lyrics and Up next get the room below.',
    'Each deck has its own − KEY +: set the key of the song waiting on the other deck before it comes in, in the library or the Stage view. EZTiger remembers it for that song.',
    'With 2 decks on, double-click a song (or drop it on the deck that is not playing) to make it the next song. Whatever was waiting moves back to second in the queue, where you can leave it or take it off. Drop a song on the ON AIR deck to play it now.',
    'X-fade, under the decks: the slider sets the crossfade from 0 (a straight cut) to 6 seconds. Overlap brings the next song in under the last one; In turn fades one out, then the next in. Smooth fades sound even all the way through; Linear is the plain fade.',
    "Tonight's playlist is the list of songs to sing (Basic calls it the queue). Save changes to a playlist: after Load playlist, change Tonight's playlist as you go (add, move or take songs off), then press 💾 Save to <playlist> above it. The Save menu can also replace any playlist with Tonight's playlist.",
    if (trialEnabled) 'Trial: the Pro installer gives every Pro feature for 14 days (the days left show by the PRO badge). After that EZTiger carries on as Basic, with everything kept, until a licence key is entered in ☰ Menu → Enter licence key. The key is checked online once; after that it works without the internet.',
    'Screen lock: press 🔒 (top bar, or by Library in the Stage view) and every tap is ignored, so a bump on the mic stand can\'t stop or skip a song; the song plays on. Press and hold the lock at the top for a moment to unlock. ☰ Menu → Screen lock button switches the 🔒 off if you don\'t want it.',
    'Searching: click (or tap) the search box and everything under the player folds away, so the results get the room. Press ✕ in the search box to bring it all back.',
    'Drag a whole folder: click a folder in the Library box to highlight it, then drag it into Tonight\'s playlist, a playlist or the player. All its songs, as listed, go in.',
    'Double-click (☰ Menu): Player loads a double-clicked song into the player (or the next deck); Tonight adds it to the end of Tonight\'s playlist instead.',
    'When nothing is playing (cued, paused or stopped) the lyrics screen, the Stage view and the second screen show the spinning logo and what is up next, instead of frozen lyrics.',
    'Skins (☰ Menu → Skin): six looks for the whole app.',
    'Sync PC ⇄ tablet (☰ Menu): Save sync file writes your playlists and song keys to EZtiger-sync.json. Copy it to the tablet (or put it in the library folder before you copy that), then Load sync file there. It works the other way round too. Songs are matched by where they sit in the library folder, or by file name.',
  ],
);

/// The Pro lines that apply on the tablet: no Level or Vocal cut (the
/// tablet's sound engine doesn't have them).
bool _onTablet(String line) => !['Level', 'Vocal cut'].any(line.startsWith);

const _sections = <(String, List<String>)>[
  (
    'Getting started',
    [
      'Library tab: click Add folder and pick your karaoke folder. EZtiger scans it. When you add, remove or rename songs later, press 🔄 Rescan (next to Add folder, or in the ☰ Menu). To rescan every time EZtiger starts, tick "Rescan at start-up" in the Menu.',
      'The arrow at the right of the Library / Playlists tabs folds that box away, for more room for the song list. Tap a tab to bring it back.',
      'Type in the search box to find songs by title or artist. Use the type filter (CDG, MP4…) and the A–Z sort above the list.',
    ],
  ),
  (
    'Playing',
    [
      'Double-click a song in the list to load it into the player, paused. Or drag it onto the player.',
      'Space plays and pauses. ⏮ goes back to the start, ⏭ (or Ctrl+→) moves on to the next song in the queue.',
      'Drag the bar under the player to skip through a song.',
      'KEY and BPM, top right of the player: the song\'s musical key (C, C#, D … and Am, F#m … for minor keys) and its tempo in beats a minute. EZTiger works them out the first time a song loads (about a second; "KEY … BPM …" shows meanwhile) and remembers them, so after that they show straight away. With the key moved in Pro, it shows the key the song plays in now, with its own key after it: KEY E (D+2). They are worked out by ear, so the odd song can come out at half or double its tempo, or in its relative minor or major.',
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
      'Single / Autoplay is next to the volume. Single stops after each song. Autoplay goes straight on to the next one in the queue.',
      'Autocue and Crossfade are in the ☰ Menu, under Playback.',
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
    'Columns',
    [
      'Drag the line at the right of a column heading to make that column wider or narrower (in the song list and the queue).',
      'Right-click a column heading (press and hold on the tablet) to show or hide columns, or Reset columns to put them back.',
    ],
  ),
  (
    'Audience songbook',
    [
      '☰ Menu → Songbook: a web page of your songs (titles and artists only) that people search on their phones by scanning a QR code.',
      'Give it a heading, press Save songbook page and upload the file (index.html) to a free web page such as GitHub Pages. Put that web address in the box, then Show QR code puts the code on screen; it\'s also a button in the stage view.',
      'After adding songs or correcting titles, the Menu says the songbook "needs updating": save it again and upload the new file over the old one.',
    ],
  ),
  (
    'Song requests from phones',
    [
      'Singers send requests from their phones over the venue Wi-Fi to the song-request list ("Start song requests" on the PC), which needs no internet. New requests wait there until you add them to its singing queue, or reject them.',
      'Each song you add to that singing queue comes into Tonight\'s playlist here by itself, with the singer\'s name, while EZTiger is open. The request list shows "✓ In EZTiger" beside it, or "Not found in EZTiger" if the song isn\'t in your library.',
      '☰ Menu → Song requests: on the PC that runs the request list the link is localhost:8080 (already set). On a tablet, type the DJ link from the request list\'s window, the one ending ?key=…, and press Connect. The Menu says "connected" while it works.',
    ],
  ),
  (
    'Your settings',
    [
      '🎤 Stage, top right: the view for performing, with the tablet on the mic stand. Lyrics large on the left; the song, time left, big Restart / Play / Next buttons, the volume and the next songs on the right. Double-tap a song in Up next to play it now; its ↑ ↓ arrows move it up or down and ✕ takes it out of the queue. Single / Autoplay sits by the volume. Double-tap the lyrics for full screen. The ⇄ button (or the Menu) swaps the lyrics to the other side. Library goes back. EZtiger opens in the view you used last.',
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
    'Sync with the PC (☰ Menu): Load sync file brings in the playlists and song keys saved by EZTiger Pro on the PC; Save sync file sends yours back.',
  ],
);
