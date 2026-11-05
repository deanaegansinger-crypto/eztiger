import 'dart:io';

/// True on the Android tablet: one screen, and a finger instead of a mouse.
/// Songs are dragged with press-and-hold, and the right-click menus open
/// with press-and-hold too.
/// (Tests switch it on to try the tablet behaviour.)
bool touchUi = Platform.isAndroid;
