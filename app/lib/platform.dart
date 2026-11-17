import 'dart:io';

/// True on the Android tablet: one screen, and a finger instead of a mouse.
/// Songs are dragged with press-and-hold, and the right-click menus open
/// with press-and-hold too.
/// (Tests switch it on to try the tablet behaviour.)
bool touchUi = Platform.isAndroid;

/// The Android app is one app, for singers: every Pro feature for singing
/// (keys, 2 decks, skins, the Stage view and its portrait layout, playlists
/// from the PC), without the host's tools: no songbook QR, no song requests,
/// no vocal removal, no old sync file and no licence key.
/// (Tests switch it on to try the singer app.)
bool singerApp = Platform.isAndroid;

/// The sound engine has ffmpeg's audio filters, for Pro's Level and Vocal
/// cut. The Windows Pro build carries the full engine; the Android engine is
/// a slimmed-down one without them, so the tablet shows just the key change.
/// (Tests switch it off to try the tablet.)
bool audioFilters = !Platform.isAndroid;
