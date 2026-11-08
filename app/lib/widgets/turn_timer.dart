import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Minuteur circulaire de 60 s basé sur `turnDeadline` (heure serveur).
class TurnTimer extends StatefulWidget {
  const TurnTimer({
    super.key,
    required this.deadlineMs,
    required this.nowMs,
    this.size = 56,
    this.totalMs = 60000,
    this.child,
  });
  final int? deadlineMs;
  final int Function() nowMs;
  final double size;
  final int totalMs;
  final Widget? child;

  @override
  State<TurnTimer> createState() => _TurnTimerState();
}

class _TurnTimerState extends State<TurnTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.deadlineMs;
    final remaining = d == null ? 0 : math.max(0, d - widget.nowMs());
    final frac = (remaining / widget.totalMs).clamp(0.0, 1.0);
    final secs = (remaining / 1000).ceil();
    final urgent = secs <= 10;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _RingPainter(frac, urgent ? const Color(0xFFFF4D4D) : kOrange),
        child: Center(
          child: widget.child ??
              Text('$secs',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: widget.size * 0.34,
                      color: urgent ? const Color(0xFFFF6B6B) : Colors.white)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac, this.color);
  final double frac;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.09;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
        r,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = Colors.white12);
    canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * frac,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke
          ..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.frac != frac || o.color != color;
}
