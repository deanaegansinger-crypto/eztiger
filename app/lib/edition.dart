/// Which edition this build is: EZTiger Basic or EZTiger Pro. Both are built
/// from the same code, so every fix reaches both; Pro switches on the extra
/// features. Build Pro with `--dart-define=EZ_EDITION=pro`.
const bool _builtAsPro = String.fromEnvironment('EZ_EDITION') == 'pro';

/// True in EZTiger Pro. (Tests switch it on to try the Pro features.)
bool isPro = _builtAsPro;

/// The app's name, as shown in the title bar and the Read me.
String get editionName => isPro ? 'EZTiger Pro' : 'EZTiger Basic';

/// What the list of songs to sing tonight is called: "the queue" in Basic,
/// "Tonight's playlist" in Pro (Dean's word for it).
String get queueTitle => isPro ? "Tonight's playlist" : 'Queue';

/// The same, inside a sentence: "add to the queue" / "add to Tonight's playlist".
String get theQueue => isPro ? "Tonight's playlist" : 'the queue';

/// Rewrites a Basic sentence about the queue for Pro.
String queueWords(String s) => !isPro
    ? s
    : s
          .replaceAll('the queue', theQueue)
          .replaceAll('The queue', queueTitle)
          .replaceAll('queued song', "song in Tonight's playlist")
          .replaceAll('Add to queue', "Add to Tonight's playlist")
          .replaceAll('queue', theQueue);
