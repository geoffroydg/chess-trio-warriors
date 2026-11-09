import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';

import '../models/protocol.dart';
import 'piece_component.dart';
import 'warrior_art.dart';

/// Nom français d'une pièce de promotion (code du protocole).
String promotionLabel(String code) => switch (code) {
      'Q' => 'Dame',
      'R' => 'Tour',
      'B' => 'Fou',
      'N' => 'Cavalier',
      _ => code,
    };

/// Sélecteur de promotion : panneau lumineux avec les 4 guerriers (dame, tour, fou, cavalier)
/// de l'équipe ; un tap sur un guerrier choisit la pièce, un tap ailleurs annule.
class PromotionPicker extends PositionComponent {
  PromotionPicker({
    required this.from,
    required this.to,
    required this.owner,
    required this.options,
    required this.pieceFactory,
    required Vector2 screen,
  }) : super(priority: 1 << 20) {
    _layout(screen);
  }

  final String from;
  final String to;
  final int owner;

  /// Codes proposés ('Q', 'R', 'B', 'N'), dans l'ordre d'affichage.
  final List<String> options;
  final PieceFactory pieceFactory;

  final List<PieceComponent> pieces = [];
  final List<Rect> slots = [];
  Rect panel = Rect.zero;
  double _t = 0;

  static const appear = 0.18;

  void _layout(Vector2 screen) {
    final w = math.min(screen.x * 0.92, screen.y * 0.75);
    final slotW = w / options.length;
    final h = slotW * 1.55;
    panel = Rect.fromCenter(center: Offset(screen.x / 2, screen.y * 0.46), width: w, height: h + slotW * 0.35);
    slots
      ..clear()
      ..addAll([
        for (var i = 0; i < options.length; i++)
          Rect.fromLTWH(panel.left + i * slotW, panel.top + slotW * 0.32, slotW, h),
      ]);
  }

  @override
  Future<void> onLoad() async {
    for (var i = 0; i < options.length; i++) {
      final p = pieceFactory(pieceTypeFromCode(options[i]), owner, to);
      final slot = slots[i];
      final r = slot.width * 0.2;
      p.placeAt(Vector2(slot.center.dx, slot.top + slot.height * 0.58), r);
      pieces.add(p);
      await add(p);
    }
  }

  /// Code choisi sous le point (pixels), ou null.
  String? optionAt(Offset pos) {
    for (var i = 0; i < slots.length; i++) {
      if (slots[i].inflate(4).contains(pos)) return options[i];
    }
    return null;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  double get _k => Curves.easeOutBack.transform((_t / appear).clamp(0.0, 1.0));

  @override
  void renderTree(Canvas canvas) {
    // Apparition : léger zoom depuis le centre du panneau.
    final k = _k;
    canvas.save();
    final c = panel.center;
    canvas.translate(c.dx, c.dy);
    canvas.scale(0.7 + 0.3 * k);
    canvas.translate(-c.dx, -c.dy);
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void render(Canvas canvas) {
    final aura = WarriorPalette.of(owner).aura;
    final alpha = (_t / appear).clamp(0.0, 1.0);
    final rr = RRect.fromRectAndRadius(panel, Radius.circular(panel.height * 0.08));
    canvas.drawRRect(
        rr.inflate(panel.height * 0.04),
        Paint()
          ..color = aura.withValues(alpha: 0.35 * alpha)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, panel.height * 0.06));
    canvas.drawRRect(
        rr,
        Paint()
          ..shader = ui.Gradient.linear(panel.topCenter, panel.bottomCenter, [
            const Color(0xF0141A33),
            const Color(0xF0080B18),
          ]));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, panel.height * 0.012)
          ..color = const Color(0xFFE2C178).withValues(alpha: alpha));
    _text(canvas, 'PROMOTION !', Offset(panel.center.dx, panel.top + panel.height * 0.09), panel.height * 0.085,
        const Color(0xFFFFE08A));
    final pulse = 0.5 + 0.5 * math.sin(_t * 5);
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      final base = Offset(s.center.dx, s.top + s.height * 0.62);
      canvas.drawOval(
          Rect.fromCenter(center: base, width: s.width * 0.78, height: s.width * 0.3),
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(base, s.width * 0.4, [
              aura.withValues(alpha: 0.45 + 0.2 * pulse),
              aura.withValues(alpha: 0),
            ]));
      _text(canvas, promotionLabel(options[i]), Offset(s.center.dx, s.bottom - s.height * 0.12), s.width * 0.17,
          const Color(0xFFF2F2F2));
    }
  }

  void _text(Canvas canvas, String text, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              color: color,
              shadows: const [Shadow(color: Color(0xFF000000), blurRadius: 4)])),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }
}
