import 'dart:math' as math;

import 'package:flutter/material.dart';

class JustStockLoader extends StatefulWidget {
  const JustStockLoader({
    super.key,
    this.size = 140,
    this.imagePath = 'assets/app_icon/logo.png',
    this.showRing = true,
    this.borderRadius,
  });

  final double size;
  final String imagePath;
  final bool showRing;
  final BorderRadius? borderRadius; // if set, renders rectangular logo with rounding

  @override
  State<JustStockLoader> createState() => _JustStockLoaderState();
}

class _JustStockLoaderState extends State<JustStockLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value; // 0..1
          final scale = 0.95 + 0.05 * math.sin(2 * math.pi * t);
          final ring = widget.showRing
              ? Transform.rotate(
                  angle: 2 * math.pi * t,
                  child: CustomPaint(
                    size: Size.square(size),
                    painter: _ArcPainter(
                      color1: cs.primary,
                      color2: cs.secondary,
                    ),
                  ),
                )
              : const SizedBox.shrink();

          final image = Transform.scale(
            scale: scale,
            child: ClipRRect(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(size),
              child: Image.asset(
                widget.imagePath,
                width: widget.borderRadius == null ? size * 0.44 : size,
                height: widget.borderRadius == null ? size * 0.44 : size,
                fit: BoxFit.contain,
              ),
            ),
          );

          return Stack(
            alignment: Alignment.center,
            children: [
              ring,
              if (widget.showRing)
                Container(
                  width: size * 0.7,
                  height: size * 0.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.15),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                ),
              image,
            ],
          );
        },
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final Color color1;
  final Color color2;

  _ArcPainter({required this.color1, required this.color2});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [color1, color2, color1],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);

    final start = -math.pi / 2;
    final sweep = math.pi * 1.4; // 252 degrees arc
    final pad = stroke.strokeWidth / 2 + size.width * 0.04;
    final r = Rect.fromLTWH(pad, pad, size.width - 2 * pad, size.height - 2 * pad);
    canvas.drawArc(r, start, sweep, false, stroke);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) {
    return oldDelegate.color1 != color1 || oldDelegate.color2 != color2;
  }
}
