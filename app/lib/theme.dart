import 'package:flutter/material.dart';

/// Colours from the mockup (`karaoke_app_mockup 3.html`).
class EzColors extends ThemeExtension<EzColors> {
  const EzColors({
    required this.bg,
    required this.panel,
    required this.raised,
    required this.text,
    required this.textDim,
    required this.border,
  });

  static const brass = Color(0xFFE8B34A);
  static const brassDim = Color(0xFF8A6A2C);
  static const cyan = Color(0xFF3DDBD6);
  static const red = Color(0xFFFF4757);
  static const mp3 = Color(0xFF8FD694);
  static const onBrass = Color(0xFF1A1508);
  static const vfdBg = Color(0xFF05070A);
  static const vfdSub = Color(0xFF6EE8E4);

  static const dark = EzColors(
    bg: Color(0xFF14151C),
    panel: Color(0xFF1C1E28),
    raised: Color(0xFF23252F),
    text: Color(0xFFE9E8E2),
    textDim: Color(0xFF8B8D9A),
    border: Color(0xFF2F3140),
  );

  static const light = EzColors(
    bg: Color(0xFFF2EDE1),
    panel: Color(0xFFFFFFFF),
    raised: Color(0xFFE9E2D0),
    text: Color(0xFF201D16),
    textDim: Color(0xFF7A7364),
    border: Color(0xFFDDD3BA),
  );

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

ThemeData buildTheme(bool dark) {
  final c = dark ? EzColors.dark : EzColors.light;
  final base = dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.panel,
    dividerColor: c.border,
    colorScheme: base.colorScheme.copyWith(primary: EzColors.brass, secondary: EzColors.cyan, surface: c.panel),
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text, fontFamily: 'Segoe UI'),
    extensions: [c],
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
  );
}

extension EzTheme on BuildContext {
  EzColors get ez => Theme.of(this).extension<EzColors>()!;
}

const vfdFont = 'Courier New';
