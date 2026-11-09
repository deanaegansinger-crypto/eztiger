import 'package:flutter/material.dart';

/// One look for the whole app, picked in ☰ Menu → Skin.
///
/// Classic Brass is the original look from the mockup
/// (`karaoke_app_mockup 3.html`) and the only one with a light screen too.
/// The others are fixed looks.
class EzSkin {
  const EzSkin({
    required this.id,
    required this.name,
    required this.colors,
    required this.brass,
    required this.brassDim,
    required this.cyan,
    required this.red,
    required this.mp3,
    required this.onBrass,
    required this.vfdBg,
    required this.vfdSub,
    required this.vfdTitle,
    required this.vfdText,
    required this.vfdEdge,
    this.lightColors,
    this.glow,
    this.vfdFont = 'Courier New',
    this.brandFont = 'Segoe UI',
    this.uiFont = 'Segoe UI',
  });

  final String id, name;

  /// The background, panel, text and border colours (dark screen).
  final EzColors colors;

  /// The same for the light screen; null when the skin has only one screen.
  final EzColors? lightColors;

  /// The main accent (titles, play button) and its dim version.
  final Color brass, brassDim;

  /// The second accent (menu, links, CDG chips).
  final Color cyan;
  final Color red, mp3, onBrass;

  /// The song display ("VFD") colours.
  final Color vfdBg, vfdSub, vfdTitle, vfdText, vfdEdge;

  /// A soft glow behind the song display and the EZTIGER name, or none.
  final Color? glow;
  final String vfdFont, brandFont, uiFont;

  bool get hasLightScreen => lightColors != null;

  static const classic = EzSkin(
    id: 'classic',
    name: 'Classic Brass',
    colors: EzColors(
      bg: Color(0xFF14151C),
      panel: Color(0xFF1C1E28),
      raised: Color(0xFF23252F),
      text: Color(0xFFE9E8E2),
      textDim: Color(0xFF8B8D9A),
      border: Color(0xFF2F3140),
    ),
    lightColors: EzColors(
      bg: Color(0xFFF2EDE1),
      panel: Color(0xFFFFFFFF),
      raised: Color(0xFFE9E2D0),
      text: Color(0xFF201D16),
      textDim: Color(0xFF7A7364),
      border: Color(0xFFDDD3BA),
    ),
    brass: Color(0xFFE8B34A),
    brassDim: Color(0xFF8A6A2C),
    cyan: Color(0xFF3DDBD6),
    red: Color(0xFFFF4757),
    mp3: Color(0xFF8FD694),
    onBrass: Color(0xFF1A1508),
    vfdBg: Color(0xFF05070A),
    vfdSub: Color(0xFF6EE8E4),
    vfdTitle: Color(0xFFE8B34A),
    vfdText: Color(0xFF3DDBD6),
    vfdEdge: Color(0xFF0E2A2A),
  );

  /// Neon green on black, like a sci-fi lab terminal.
  static const reactor = EzSkin(
    id: 'reactor',
    name: 'Reactor',
    colors: EzColors(
      bg: Color(0xFF020604),
      panel: Color(0xFF04110A),
      raised: Color(0xFF06180E),
      text: Color(0xFFB8FFC9),
      textDim: Color(0xFF4FA066),
      border: Color(0xFF1F6B35),
    ),
    brass: Color(0xFF39FF6A),
    brassDim: Color(0xFF0E5A24),
    cyan: Color(0xFFA8FF3E),
    red: Color(0xFFFF3B3B),
    mp3: Color(0xFF39FF6A),
    onBrass: Color(0xFF011006),
    vfdBg: Color(0xFF010402),
    vfdSub: Color(0xFF7DFFA0),
    vfdTitle: Color(0xFF39FF6A),
    vfdText: Color(0xFFC8FF7A),
    vfdEdge: Color(0xFF2AFF5F),
    glow: Color(0xFF39FF6A),
    vfdFont: 'Consolas',
    brandFont: 'Bahnschrift',
    uiFont: 'Consolas',
  );

  /// Dark gunmetal, amber and a green LED readout.
  static const foundry = EzSkin(
    id: 'foundry',
    name: 'Foundry',
    colors: EzColors(
      bg: Color(0xFF1B1D1F),
      panel: Color(0xFF2B2E31),
      raised: Color(0xFF202325),
      text: Color(0xFFD4D7D2),
      textDim: Color(0xFF8A9094),
      border: Color(0xFF0F1011),
    ),
    brass: Color(0xFFF2A531),
    brassDim: Color(0xFF6B4A14),
    cyan: Color(0xFF7EE05A),
    red: Color(0xFFFF5A36),
    mp3: Color(0xFF7EE05A),
    onBrass: Color(0xFF1B1D1F),
    vfdBg: Color(0xFF071007),
    vfdSub: Color(0xFF5AB845),
    vfdTitle: Color(0xFF9CF56F),
    vfdText: Color(0xFFC7F2A4),
    vfdEdge: Color(0xFF000000),
    vfdFont: 'Lucida Console',
    brandFont: 'Bahnschrift',
  );

  /// Midnight blue and moonlight, with carved-letter headings.
  static const nightshade = EzSkin(
    id: 'nightshade',
    name: 'Nightshade',
    colors: EzColors(
      bg: Color(0xFF05070F),
      panel: Color(0xFF0A0F20),
      raised: Color(0xFF0D1430),
      text: Color(0xFFB9C7F0),
      textDim: Color(0xFF6273A0),
      border: Color(0xFF1D2A55),
    ),
    brass: Color(0xFF8FB4FF),
    brassDim: Color(0xFF2A3F80),
    cyan: Color(0xFF4FD3FF),
    red: Color(0xFFFF5C7A),
    mp3: Color(0xFF7FE3C4),
    onBrass: Color(0xFF050A1C),
    vfdBg: Color(0xFF02040B),
    vfdSub: Color(0xFF5D82D6),
    vfdTitle: Color(0xFFCFE0FF),
    vfdText: Color(0xFF4FD3FF),
    vfdEdge: Color(0xFF24356E),
    glow: Color(0xFF8FB4FF),
    vfdFont: 'Georgia',
    brandFont: 'Georgia',
  );

  /// Brushed aluminium like a home hi-fi, with a blue LCD.
  static const silver = EzSkin(
    id: 'silver',
    name: 'Studio Silver',
    colors: EzColors(
      bg: Color(0xFFB9BDC3),
      panel: Color(0xFFD5D8DC),
      raised: Color(0xFFECEEF0),
      text: Color(0xFF1D2127),
      textDim: Color(0xFF545A63),
      border: Color(0xFF9AA0A8),
    ),
    brass: Color(0xFF1A5FC8),
    brassDim: Color(0xFF7D838B),
    cyan: Color(0xFF1A5FC8),
    red: Color(0xFFD12C22),
    mp3: Color(0xFF23803F),
    onBrass: Color(0xFFFFFFFF),
    vfdBg: Color(0xFF0C1A2E),
    vfdSub: Color(0xFF6FC3FF),
    vfdTitle: Color(0xFFFF9A3C),
    vfdText: Color(0xFFCFE9FF),
    vfdEdge: Color(0xFF7D838B),
    glow: Color(0xFFFF9A3C),
    vfdFont: 'Consolas',
    brandFont: 'Bahnschrift',
  );

  /// Black gloss and electric blue, like a car stereo at night.
  static const nightDrive = EzSkin(
    id: 'nightdrive',
    name: 'Night Drive',
    colors: EzColors(
      bg: Color(0xFF030406),
      panel: Color(0xFF0A0C10),
      raised: Color(0xFF111419),
      text: Color(0xFFDBE6F5),
      textDim: Color(0xFF6A7B92),
      border: Color(0xFF1F2A3A),
    ),
    brass: Color(0xFF2F8BFF),
    brassDim: Color(0xFF0B3470),
    cyan: Color(0xFF38E1FF),
    red: Color(0xFFFF2D55),
    mp3: Color(0xFF38E1FF),
    onBrass: Color(0xFFFFFFFF),
    vfdBg: Color(0xFF000208),
    vfdSub: Color(0xFF2F8BFF),
    vfdTitle: Color(0xFF5FB0FF),
    vfdText: Color(0xFFA8D8FF),
    vfdEdge: Color(0xFF1B4FA0),
    glow: Color(0xFF2F8BFF),
    vfdFont: 'Consolas',
    brandFont: 'Bahnschrift',
  );

  static const all = [classic, reactor, foundry, nightshade, silver, nightDrive];

  static EzSkin byId(String? id) => all.firstWhere((s) => s.id == id, orElse: () => classic);

  /// The skin on screen now. The app sets it before it rebuilds.
  static EzSkin current = classic;
}

/// The colours of the current skin.
class EzColors extends ThemeExtension<EzColors> {
  const EzColors({
    required this.bg,
    required this.panel,
    required this.raised,
    required this.text,
    required this.textDim,
    required this.border,
  });

  static EzSkin get _s => EzSkin.current;
  static Color get brass => _s.brass;
  static Color get brassDim => _s.brassDim;
  static Color get cyan => _s.cyan;
  static Color get red => _s.red;
  static Color get mp3 => _s.mp3;
  static Color get green => _s.mp3;
  static Color get onBrass => _s.onBrass;
  static Color get vfdBg => _s.vfdBg;
  static Color get vfdSub => _s.vfdSub;
  static Color get vfdTitle => _s.vfdTitle;
  static Color get vfdText => _s.vfdText;
  static Color get vfdEdge => _s.vfdEdge;
  static Color? get glow => _s.glow;

  static EzColors get dark => _s.colors;
  static EzColors get light => _s.lightColors ?? _s.colors;

  final Color bg, panel, raised, text, textDim, border;

  static Color forType(String label) => switch (label) {
    'CDG' => cyan,
    'MP4' => brass,
    _ => mp3,
  };

  @override
  EzColors copyWith() => this;

  @override
  EzColors lerp(EzColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

ThemeData buildTheme(bool dark, [EzSkin? skin]) {
  if (skin != null) EzSkin.current = skin;
  final s = EzSkin.current;
  final c = dark ? EzColors.dark : EzColors.light;
  final isDark = s.hasLightScreen ? dark : s.colors.bg.computeLuminance() < 0.3;
  final base = isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.panel,
    dividerColor: c.border,
    colorScheme: base.colorScheme.copyWith(
      primary: s.brass,
      secondary: s.cyan,
      surface: c.panel,
      onSurface: c.text,
      surfaceContainer: c.raised,
    ),
    popupMenuTheme: PopupMenuThemeData(color: c.raised),
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text, fontFamily: s.uiFont),
    extensions: [c],
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
  );
}

extension EzTheme on BuildContext {
  EzColors get ez => Theme.of(this).extension<EzColors>()!;
}

/// The song display's font, which changes with the skin.
String get vfdFont => EzSkin.current.vfdFont;

/// The font of the EZTIGER name in the top bar.
String get brandFont => EzSkin.current.brandFont;
