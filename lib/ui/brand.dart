import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

class LinqoMascot extends StatelessWidget {
  const LinqoMascot({super.key, this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/linqo-mascot.png',
    width: size,
    height: size,
    cacheWidth: math.min(
      512,
      (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
    ),
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );
}

class LinqoWordmark extends StatelessWidget {
  const LinqoWordmark({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Linqo',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LinqoMascot(size: 43),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'linqo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Fredoka',
              fontWeight: FontWeight.w700,
              fontSize: 30,
              letterSpacing: -.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The supplied complete lockup is reserved for the startup surface.
class LinqoSplash extends StatelessWidget {
  const LinqoSplash({super.key});
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: LinqoColors.canvas,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: LinqoColors.canvas,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: reduced ? 1 : .97, end: 1),
                      duration: reduced
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, child) =>
                          Transform.scale(scale: value, child: child),
                      child: Image.asset(
                        'assets/brand/linqo-full.png',
                        width: math.min(
                          260,
                          MediaQuery.sizeOf(context).width * .66,
                        ),
                        fit: BoxFit.contain,
                        semanticLabel: 'Linqo',
                        cacheWidth: 780,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'A little home for your discoveries.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF705E82),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
