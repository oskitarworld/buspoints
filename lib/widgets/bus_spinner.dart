import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Small animated widget that renders a faint circle with a bus icon
/// orbiting around it. The animation is driven by the provided
/// [animation] (expects value in [0,1]).
class BusSpinner extends StatelessWidget {
  final Animation<double> animation;
  final double size;
  final Color? circleColor;
  final Color? busColor;

  const BusSpinner({
    super.key,
    required this.animation,
    this.size = 44.0,
    this.circleColor,
    this.busColor,
  });

  @override
  Widget build(BuildContext context) {
  final circleBase = Theme.of(context).colorScheme.primary;
  final circleClr = circleColor ?? circleBase.withAlpha((0.12 * 255).round());
    final busClr = busColor ?? Colors.white;
    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, child) {
        final angle = (animation.value * 2.0 * math.pi) - (math.pi / 2.0);
        final radius = (size * 0.38).clamp(8.0, size * 0.48);
        final dx = math.cos(angle) * radius;
        final dy = math.sin(angle) * radius;
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // faint circular track
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                  border: Border.all(color: circleClr, width: 2.0),
                ),
              ),
              // moving bus
              Transform.translate(
                offset: Offset(dx, dy),
                child: Container(
                  width: size * 0.42,
                  height: size * 0.28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha((0.12 * 255).round()), blurRadius: 3, offset: const Offset(0,1))],
                  ),
                  child: Icon(
                    Icons.directions_bus,
                    size: (size * 0.28).clamp(12.0, 24.0),
                    color: busClr,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
