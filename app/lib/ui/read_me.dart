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
    title: Text(
      singerApp
          ? 'EZTiger for singers · Read me'
          : (touchUi ? '$editionName for Android · Read me' : '$editionName · Read me'),
    ),
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
              // On the tablet too: a Bluetooth keyboard, footswitch or remote.
              if (isPro) const _ShortcutsMenu(),
              for (final (head, lines)
                  in singerApp
                      ? _singer
                      : touchUi
                      ? [
                          _tablet,
                          if (isPro) (singerApp ? 'Singing' : _pro.$1, _pro.$2.where(_onTablet).toList()),
                          ..._sections.where((x) => x != _secondScreen && !(singerApp && _hostOnly.contains(x))),
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
    'Footswitch or Bluetooth remote',
    [
      ('Page Down', 'Next song'),
      ('Page Up', 'Back to the start of the song'),
      ('Media ⏯ ⏭ ⏮', 'Play / pause, next song, back to the start'),
      ('Any key above', 'Set the footswitch to send it: Space, N, R, K, L…'),
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
        'Single keys, one hand, on a keyboard, footswitch or Bluetooth remote (on the tablet too). They wait while you type in the search box. With the screen locked, only the playing keys work (Space, R, N, X, Z, C, U, D, M, K, L, 0 and the footswitch keys), so a footswitch still works on the mic stand.',
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

/// The Android app's Read me: for singers, in the order a first-time user
/// meets things, from adding songs to singing in the Stage view.
const _singer = <(String, List<String>)>[
  (
    'Welcome',
    [
      'EZTiger for singers plays your karaoke backing tracks (MP3 + CDG lyrics, or MP4 karaoke videos) on a tablet or phone, with the words big on screen, for singing at a gig or at home.',
      'Plan the night on the PC with EZTiger Pro, send the playlist across, then sing from the Stage view with the tablet on the mic stand.',
      'Everything you change is remembered: the songs, playlists, keys, volume and settings are there next time.',
    ],
  ),
  (
    '1. Add your songs',
    [
      'Library tab → Add folder. The first time, Android asks to let EZTiger "manage all files": switch it on and come back. It needs this to read the CDG lyric files, which Android doesn\'t count as music.',
      'Pick where your karaoke folder is (SD card, internal storage or a USB stick), then the folder itself. EZTiger reads every song in it.',
      'Added, removed or renamed songs later? ☰ Menu → Rescan library. Or tick Rescan at start-up to have it done each time EZTiger opens.',
      '☰ Menu → Song names: Tags (the usual) uses each song\'s own title and artist tags, and the file name only where a tag is blank; File names reads them from the file names. Switch any time.',
    ],
  ),
  (
    '2. Bring a playlist from the PC',
    [
      'On the PC, in EZTiger Pro: right-click the playlist → 📶 Send to the tablet. It shows the PC\'s address and a 4-figure code.',
      'On the tablet or phone, on the same Wi-Fi: ☰ Menu → Receive from PC…, type the address (it\'s remembered) and the code, then Receive. The keyboard\'s Next goes to the code; its ✓ starts.',
      'No Wi-Fi? On the PC choose 📤 Export to USB, SD card or Dropbox instead, then on the tablet ☰ Menu → Import playlist… and pick it.',
      'The songs, with their CDG lyrics, are copied into the EZTiger imports folder, and the playlist arrives with its running order and keys. "Transfer successful" shows when it\'s in, with Receive another (or Import another) for the next one.',
      'Sent the same playlist again? Choose Update to bring it in line with the PC: only new or changed songs are copied, and songs taken off the list are removed. Or Keep both: the new one comes in beside the old, with the date on, such as ★ Friday Night (16 Nov).',
    ],
  ),
  (
    '3. Find and play a song',
    [
      'Type in the search box to find a song by title or artist. While you search, everything under the player folds away to give the results room; ✕ in the search box brings it back.',
      'View, above the list: Songbook (the usual) shows each song once on a bigger row, with a tile for each collection that has it. Tap a tile to put that disc in: ☰ Menu → Versions (×5) sets whether it goes on Now, Next or at the Bottom of Tonight\'s playlist. Tap the song to see all its discs. List fits more songs on the screen.',
      'Double-tap a song to load it into the player, paused, ready to go. Press ▶ to start, ⏸ to pause, ⏮ to go back to the start and ⏭ for the next song. Drag the bar under the player to skip through the song.',
      'Press and hold a song, then move your finger, to drag it onto the player, Tonight\'s playlist or a playlist. Press and hold and let go without moving for its menu: add to Tonight\'s playlist, set the singer, playlists and more.',
      'Drag a whole folder: tap a folder in the Library box, then press and hold it and drag it into Tonight\'s playlist. All its songs go in.',
    ],
  ),
  (
    '4. Tonight\'s playlist',
    [
      'Tonight\'s playlist is the list of songs for the gig. 📂 Load playlist puts a saved playlist (such as one from the PC) into it.',
      '📖 Songbook (top of the lyrics box) opens every song on the tablet in the lyrics\' place: by Artist, by Folder (your genres or sets) or A–Z by title, with a look-up box and an A–Z strip down the side to jump. Tap a song to add it to the bottom of Tonight\'s playlist (✓ shows it\'s in); press and hold to make it the next song. ✕ closes it, and it steps aside by itself when a song starts playing.',
      'Add songs by dragging them in, or ☰ Menu → Double-click → Tonight, so a double-tap adds a song to the end instead of loading it.',
      'Drag songs up and down to change the order. Sung songs stay in the list with a ✓; Clear played takes them off.',
      'Changed the order during the night? 💾 Save to <playlist> keeps it. ★ Save as playlist makes a new one.',
      'Single stops after each song; Autoplay goes straight on to the next. ☰ Menu → Autocue gets the next song ready to start at its first note; Crossfade fades one song into the next.',
    ],
  ),
  (
    '5. Change the key',
    [
      'KEY − and +, under the volume, move the song down or up a semitone, as far as 3 either way. Tap the number to go back to the song\'s own key.',
      'EZTiger remembers the key for each song. When a song loads in a changed key, "KEY +2" (or −) flashes red on the player, so it never catches you out. Keys set on the PC come across with the playlist.',
      'With 2 decks on, each deck has its own − KEY +, so you can set the key of the next song before it comes in.',
    ],
  ),
  (
    '6. 2 decks and the crossfade',
    [
      '☰ Menu → 2 decks: deck A and deck B sit side by side. The deck marked ON AIR is playing; the other has the next song waiting, ready to start straight away. Its ⇄ button mixes into it now.',
      'X-fade, under the decks, sets the crossfade from 0 (a straight cut) to 6 seconds. Overlap brings the next song in under the last one; In turn fades one out, then the next in.',
    ],
  ),
  (
    '7. Sing from the Stage view',
    [
      '🎤 Stage, at the top, is the view for performing: the lyrics large, the song and time left in big type, big Restart / Play / Next buttons, the volume and Up next. Library takes you back. EZTiger opens in the view you used last.',
      'Up next: double-tap a song to sing it now; its ↑ ↓ arrows move it and ✕ takes it off. When it\'s down to the last 2 songs a warning shows, orange at 2 and red at 1 and on the last song, so you can load more in time.',
      'Portrait: ☰ Menu → Stage tablet → Portrait, or the ⟳ button in the Stage view. The tablet turns upright, with the decks and Up next at the top and the lyrics filling the bottom half. ⟳ again for landscape.',
      'Double-tap the lyrics for full screen lyrics; double-tap again or press Back to come out. The ⇄ button swaps the lyrics to the other side in landscape.',
      'When nothing is playing, the lyrics screen shows the spinning logo and what\'s up next instead of frozen words. The screen stays on while EZTiger is open.',
    ],
  ),
  (
    '8. Lock the screen',
    [
      'Press 🔒 (top bar, or in the Stage view) and every tap is ignored, so a bump on the mic stand can\'t stop or skip a song; the song plays on.',
      'Press and hold the lock for a moment to unlock. ☰ Menu → Screen lock button hides the 🔒 if you don\'t want it.',
    ],
  ),
  (
    '9. Sound over Bluetooth: the lyrics delay',
    [
      'Sound sent over Bluetooth to a mixer or speaker reaches the room late, so the words run ahead of the music. ⏱ Delay, by the volume (and in the Stage view), holds the lyrics and video back to match.',
      'Tap it to switch it on (it shows the time, such as +0.20s); tap again to switch it off. Press and hold it to set the time, from 0 to 1 second: play a song and move it until the words change with the singing. EZTiger remembers it.',
    ],
  ),
  (
    '10. Make it yours',
    [
      '☰ Menu → Skin: six looks for the whole app. Screen: Dark or Light, on the skins that have both.',
      '☰ Menu → Text size makes the song lists larger (Normal, Large or Extra large) for reading at a glance.',
      'The arrow at the right of the Library / Playlists tabs folds that box away for more room for the songs; tap a tab to bring it back.',
      'Columns: press and hold a column heading to show or hide columns; drag the line at its right to make it wider or narrower.',
    ],
  ),
  (
    'Your playlists in other music apps',
    [
      'Every playlist that comes from the PC also gets a playlist file (such as Friday Night.m3u) in the EZTiger playlists folder, beside EZTiger imports. Open it in VLC, Poweramp or another player to play the songs in order.',
      'Other players play the sound of a CDG song without its lyrics, and in its own key: the lyrics and keys are EZTiger\'s.',
    ],
  ),
];

const _pro = (
  'Keys, sound and 2 decks',
  [
    'KEY, under the volume: − and + move the song down or up a semitone, as far as 3 either way. The 0 in the middle puts it back. EZTiger remembers the key for each song, and when a song loads in a changed key, "KEY +2" (or −) flashes red on the player and the Stage view.',
    'Level, under the volume: evens out the loudness, so quiet and loud MP3s and videos play at about the same level. It takes a moment to settle at the start of a song.',
    'Vocal cut, under the volume: takes out the lead vocal on most stereo tracks. It finds what sits in the middle, frequency by frequency, and takes just that out, keeping the rest of the mix, its stereo spread and the bass. It works best on studio recordings; an instrument in the middle with the singer comes down a little too, and reverb and backing vocals can still come through. A song with an AI instrumental (below) plays that instead.',
    'Remove vocals (AI): right-click a song, or a block of songs, → 🎤 Remove vocals (AI). The Demucs AI model splits the song into its parts and mixes everything but the vocals into an instrumental, saved in your Music folder in EZVocalremoved, named like the original with EZVocrem on the end (EZVocrem is on the end of its title tag too), with its CDG lyrics beside it. It takes a minute or two a song (longer without a suitable graphics card); the bar at the bottom shows how it\'s going, and you can carry on meanwhile. The first time, the model (84 MB) downloads. After that, Vocal cut on that song plays the instrumental, and the EZVocalremoved folder is in your library to search.',
    '2 decks (☰ Menu, under Playback): deck A and deck B sit side by side across the top and share Tonight\'s playlist. The deck marked ON AIR is playing; the other shows the song waiting to come in, ready to start straight away. Its ⇄ button mixes into it now.',
    'Stage view with 2 decks: both decks run across the top of the screen, with Restart / Play / Next on the deck ON AIR and ⇄ on the next one, so the lyrics and Up next get the room below.',
    'Each deck has its own − KEY +: set the key of the song waiting on the other deck before it comes in, in the library or the Stage view. EZTiger remembers it for that song.',
    'With 2 decks on, double-click a song (or drop it on the deck that is not playing) to make it the next song. Whatever was waiting moves back to second in the queue, where you can leave it or take it off. Drop a song on the ON AIR deck to play it now.',
    'X-fade, under the decks: the slider sets the crossfade from 0 (a straight cut) to 6 seconds. Overlap brings the next song in under the last one; In turn fades one out, then the next in. Smooth fades sound even all the way through; Linear is the plain fade.',
    "Tonight's playlist is the list of songs to sing tonight. Save changes to a playlist: after Load playlist, change Tonight's playlist as you go (add, move or take songs off), then press 💾 Save to <playlist> above it. The Save menu can also replace any playlist with Tonight's playlist.",
    if (trialEnabled) 'Trial: the Pro installer gives every Pro feature for 14 days (the days left show by the PRO badge). After that those features pause, with everything kept, until a licence key is entered in ☰ Menu → Enter licence key. The key is checked online once; after that it works without the internet.',
    'Screen lock: press 🔒 (top bar, or by Library in the Stage view) and every tap is ignored, so a bump on the mic stand can\'t stop or skip a song; the song plays on. Press and hold the lock at the top for a moment to unlock. ☰ Menu → Screen lock button switches the 🔒 off if you don\'t want it.',
    'Searching: click (or tap) the search box and everything under the player folds away, so the results get the room. Press ✕ in the search box to bring it all back.',
    'Drag a whole folder: click a folder in the Library box to highlight it, then drag it into Tonight\'s playlist, a playlist or the player. All its songs, as listed, go in.',
    'Double-click (☰ Menu): Player loads a double-clicked song into the player (or the next deck); Tonight adds it to the end of Tonight\'s playlist instead.',
    'When nothing is playing (cued, paused or stopped) the lyrics screen, the Stage view and the second screen show the spinning logo and what is up next, instead of frozen lyrics.',
    'Skins (☰ Menu → Skin): six looks for the whole app.',
    'Sync file (☰ Menu): Save sync file writes your playlists and song keys to EZtiger-sync.json; Load sync file on another PC brings them in. Songs are matched by where they sit in the library folder, or by file name. For the tablet or phone, send the playlist with its songs instead (below).',
    'A playlist with its songs, PC to tablet: right-click a playlist on the PC → 📤 Export to USB, SD card or Dropbox (as a folder, or one zip) or 📶 Send to the tablet over Wi-Fi (it shows the PC\'s address and a code). On the tablet, ☰ Menu → Import playlist… or Receive from PC…. The songs, with their CDG and lyrics, are copied into the tablet\'s EZTiger imports folder, and the playlist comes back with its keys. If the tablet already has a playlist of that name it asks: Update (the playlist takes the new order and keys, only new or changed songs are copied, and songs taken off the list are removed from its folder) or Keep both (the new one comes in beside it with the date on, such as ★ Friday Night (16 Nov)). The PC\'s window says "Transfer successful" when the tablet has it all; the tablet offers Receive another. The tablet also writes a playlist file (Friday Night.m3u) in its EZTiger playlists folder, for other music apps.',
  ],
);

/// The Pro lines that apply on the tablet: no Level or Vocal cut (the
/// tablet's sound engine doesn't have them).
bool _onTablet(String line) =>
    !['Level', 'Vocal cut', 'Remove vocals', if (singerApp) 'Sync PC'].any(line.startsWith);

/// The host's sections, left out of the singer app's Read me.
const _hostOnly = [_songbook, _requests];

const _songbook = (
  'Audience songbook',
  [
    '☰ Menu → Songbook: a web page of your songs (titles and artists only) that people search on their phones by scanning a QR code.',
    'Give it a heading, press Save songbook page and upload the file (index.html) to a free web page such as GitHub Pages. Put that web address in the box, then Show QR code puts the code on screen; it\'s also a button in the stage view.',
    'After adding songs or correcting titles, the Menu says the songbook "needs updating": save it again and upload the new file over the old one.',
  ],
);

const _requests = (
  'Song requests from phones',
  [
    '☰ Menu → Start song requests: EZTiger makes a request page of your songs and starts the request list on this PC, over the venue Wi-Fi, with no internet needed. The first time, Windows asks whether PowerShell may use the network: tick Private networks and Allow (and set the venue Wi-Fi to Private in Windows settings).',
    'Singers join the Wi-Fi and scan the QR code (☰ Menu → Songbook → Show QR code, now pointing at the request page), pick their name and a song, and press Send. The DJ list opens in your browser: new requests wait there until you press ✓ Add to queue, or ✕ Reject. 🔒 Close requests stops new ones; Print poster makes an A4 poster with the QR code.',
    'Each song you add to the singing queue comes into Tonight\'s playlist here by itself, with the singer\'s name, while EZTiger is open (☰ Menu → Song requests says "connected"). The DJ list shows "✓ In EZTiger" beside it, or "Not found in EZTiger" if the song isn\'t in your library.',
    'Next time, Start song requests on the desktop (or in ☰ Menu) starts it again. Stop it with ⏻ Stop the request list at the bottom of the DJ list. The list is kept until you press Clear whole list. Added songs? Start song requests in the Menu again to update the page.',
  ],
);

const _sections = <(String, List<String>)>[
  (
    'Getting started',
    [
      'Library tab: click Add folder and pick your karaoke folder. EZtiger scans it. When you add, remove or rename songs later, press 🔄 Rescan (next to Add folder, or in the ☰ Menu). To rescan every time EZtiger starts, tick "Rescan at start-up" in the Menu.',
      'The arrow at the right of the Library / Playlists tabs folds that box away, for more room for the song list. Tap a tab to bring it back.',
      'Type in the search box to find songs by title or artist. Above the list: Type (CDG, MP4…), Sort (best match or A–Z) and View.',
      'Song names (☰ Menu): Tags (the usual) takes each song\'s title and artist from its own tags (ID3 in MP3s, the title and artist in MP4s), and the file name only where a tag is blank. File names reads them from the file names. Switching is instant; after updating new builds, Rescan once so every song\'s tags are read.',
      'View: Songbook (the usual) shows each song once on a bigger row, the title over the artist, with a tile for each collection that has it, such as Sunfly ×2 · Zoom · +1. List shows one line a song, so more fit on the screen. EZTiger remembers which you chose.',
    ],
  ),
  (
    'Songs on more than one disc',
    [
      'A song you have on several discs shows a tile for each collection (Songbook view), or ×5 after its title (List view).',
      'Click a tile to put that collection\'s disc in. ☰ Menu → Versions (×5) sets what a click does: Now loads it on the player, paused; Next makes it the next song in Tonight\'s playlist (cued on the other deck with 2 decks); Bottom adds it to the end of Tonight\'s playlist. With All (or Off), the tile asks which.',
      'Click the song itself and all its discs open underneath it: the collection, disc and file name, with Now, Next and Bottom (or just the one you chose in Versions). Off keeps them closed. Right-click → 🎚 Other versions… lists them too.',
    ],
  ),
  (
    'Playing',
    [
      'Double-click a song in the list to load it into the player, paused. Or drag it onto the player.',
      'Space plays and pauses. ⏮ goes back to the start, ⏭ (or Ctrl+→) moves on to the next song in the queue.',
      'Drag the bar under the player to skip through a song.',
      '⏱ Delay, by the volume (and in the Stage view): when the sound goes over Bluetooth to a mixer or speaker it can reach the room late, so the lyrics run ahead. Tap it to hold the lyrics and video back (it shows the time, such as +0.20s); tap again to switch it off. Press and hold it (or right-click) to set the time, from 0 to 1 second: play a song and move it until the words change with the singing. EZTiger remembers it.',
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
      'Drag the line at the right of a column heading to make that column wider or narrower (in the song list and the queue). The Songbook and List views keep their own widths.',
      'Right-click a column heading (press and hold on the tablet) to show or hide columns, or Reset columns to put them back.',
    ],
  ),
  _songbook,
  _requests,
  (
    'Your settings',
    [
      '🎤 Stage, top right: the view for performing, with the tablet on the mic stand. Lyrics large on the left; the song, time left, big Restart / Play / Next buttons, the volume and the next songs on the right. Double-tap a song in Up next to play it now; its ↑ ↓ arrows move it up or down and ✕ takes it out of the queue. Single / Autoplay sits by the volume. Double-tap the lyrics for full screen. The ⇄ button (or the Menu) swaps the lyrics to the other side. Library goes back. EZtiger opens in the view you used last. When Up next is down to its last 2 songs a warning shows (orange at 2, red at 1 and on the last song), so you can load more in time.',
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
    'Playlists from the PC (☰ Menu): Import playlist… from a USB stick, SD card or Dropbox, or Receive from PC… over the Wi-Fi. When it\'s in, "Transfer successful" shows, with Receive another (or Import another) for the next one.',
    'Other music players: the songs come into the EZTiger imports folder, and each playlist also gets a playlist file (such as Friday Late.m3u) in the EZTiger playlists folder beside it. Open that in VLC, Poweramp or another player to play the songs in order. Other players play the sound of a CDG song without its lyrics, and in its own key.',
    'Portrait Stage view (☰ Menu → Stage tablet → Portrait): in the Stage view the tablet turns upright. The decks sit side by side at the top with the next songs scrolling under them, and the lyrics fill the bottom half. The ⟳ button in the Stage view switches between Portrait and Landscape.',
    'Running out: when Up next is down to the last 2 songs, the Stage view says so: orange at 2 songs left, red at 1 and on the last song, so you can load more in time.',
  ],
);
