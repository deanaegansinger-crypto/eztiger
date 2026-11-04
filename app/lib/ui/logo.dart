import 'package:flutter/material.dart';

/// The EZtiger badge: a tiger head in a gold ring that turns slowly, once
/// every 24 seconds. It holds still when Windows asks apps to reduce motion.
class EzLogo extends StatefulWidget {
  const EzLogo({super.key, this.size = 32, this.spin = true});

  final double size;
  final bool spin;

  static const asset = 'assets/eztiger-logo.png';
  static const turn = Duration(seconds: 24);

  @override
  State<EzLogo> createState() => _EzLogoState();
}

class _EzLogoState extends State<EzLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: EzLogo.turn);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(EzLogo old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final still = !widget.spin || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'EZtiger logo',
        image: true,
        child: RotationTransition(
          turns: _c,
          child: Image.asset(
            EzLogo.asset,
            width: widget.size,
            height: widget.size,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => SizedBox(width: widget.size, height: widget.size),
          ),
        ),
      );
}
