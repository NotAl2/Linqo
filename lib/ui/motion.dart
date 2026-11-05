import 'package:flutter/material.dart';

/// Brief native navigation; no animation controllers in library rows.
class LinqoTransitions extends PageTransitionsBuilder {
  const LinqoTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: eased.drive(
          Tween(begin: const Offset(.035, 0), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}
