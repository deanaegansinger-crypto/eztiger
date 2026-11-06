/// Which edition this build is: EZTiger Basic or EZTiger Pro. Both are built
/// from the same code, so every fix reaches both; Pro switches on the extra
/// features. Build Pro with `--dart-define=EZ_EDITION=pro`.
const bool _builtAsPro = String.fromEnvironment('EZ_EDITION') == 'pro';

/// True in EZTiger Pro. (Tests switch it on to try the Pro features.)
bool isPro = _builtAsPro;

/// The app's name, as shown in the title bar and the Read me.
String get editionName => isPro ? 'EZTiger Pro' : 'EZTiger Basic';
