import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' hide Gradient;
import 'package:flutter/foundation.dart' show protected;

import '../models/protocol.dart';

/// Couleurs des trois camps (Blanc, Rouge, Noir).
const playerColors = <ui.Color>[ui.Color(0xFFEAF1FF), ui.Color(0xFFFF5A3C), ui.Color(0xFF2B3358)];
const playerAccents = <ui.Color>[ui.Color(0xFF7FB2FF), ui.Color(0xFFFFB199), ui.Color(0xFF35E0FF)];

/// Fabrique de pièces : à remplacer à l'étape 4 par les guerriers animés.
typedef PieceFactory = PieceComponent Function(PieceType type, int owner, String cellId);

/// Pièce posée sur le plateau. Classe abstraite : le déplacement (interpolation 300 ms),
/// le gel, la sélection et la profondeur sont gérés ici ; le rendu et les animations
/// de personnage (attaque, mort, idle...) sont délégués aux sous-classes.
abstract class PieceComponent extends PositionComponent {
  PieceComponent({required this.type, required this.owner, required this.cellId})
      : super(anchor: Anchor.center);

  PieceType type;
  final int owner;
  String cellId;

  /// Pièce d'un joueur éliminé (grisée, immobile).
  bool frozen = false;
  bool selected = false;

  /// Roi en échec (aura rouge clignotante + vibration).
  bool inCheck = false;

  /// Rayon de base (pixels) du pion à l'endroit où il se trouve (tient compte de la perspective).
  double radius = 10;

  /// Durée du déplacement (s) ; surchargée par les guerriers (350-450 ms).
  double get moveDuration => 0.3;
  Vector2? _from;
  Vector2? _to;
  double _fromRadius = 10;
  double _toRadius = 10;
  double _t = 0;

  bool get isMoving => _to != null;

  /// Destination du déplacement en cours (null à l'arrêt).
  @protected
  Vector2? get moveTarget => _to;

  /// Progression du déplacement (0..1).
  double get moveProgress => _t;

  /// Place la pièce sans animation.
  void placeAt(Vector2 p, double r) {
    _to = null;
    position = p.clone();
    radius = r;
    size = Vector2.all(r * 3);
    priority = p.y.round();
  }

  /// Déplacement animé vers [p] (300 ms).
  void moveTo(Vector2 p, double r) {
    _from = position.clone();
    _fromRadius = radius;
    _to = p.clone();
    _toRadius = r;
    _t = 0;
    onMoveStart();
  }

  void setSelected(bool v) {
    if (selected == v) return;
    selected = v;
    onSelectedChanged(v);
  }

  /// Crochets pour les animations de l'étape 4.
  @protected
  void onMoveStart() {}
  @protected
  void onMoveEnd() {}
  @protected
  void onSelectedChanged(bool selected) {}

  /// Appelé quand la pièce est prise (avant son retrait).
  void onCaptured() {}

  /// Déroule l'attaque spéciale de la pièce (pose) vers la direction [dir] ; ignoré par défaut.
  void startAttack(Vector2 dir) {}
  void endAttack() {}

  /// Impact subi (flash blanc).
  void hit() {}

  /// Mise hors de combat. [dissolve] : la pièce se dissout puis se retire du jeu ;
  /// sinon elle reste à terre (fin de partie). Par défaut : retrait immédiat.
  void knockOut({bool dissolve = true}) {
    if (dissolve) removeFromParent();
  }

  /// Animation de victoire (fin de partie).
  void celebrate() {}

  /// Oriente la pièce vers un point (attaquant, cible).
  void faceTowards(Vector2 p) {}

  /// Dessin de la pièce dans un carré [size] centré sur la case.
  void renderPiece(ui.Canvas canvas, Vector2 size);

  @override
  void render(ui.Canvas canvas) => renderPiece(canvas, size);

  @override
  void update(double dt) {
    super.update(dt);
    final to = _to;
    if (to != null) {
      _t = math.min(1, _t + dt / moveDuration);
      final k = Curves.easeInOut.transform(_t);
      position = _from! + (to - _from!) * k;
      radius = _fromRadius + (_toRadius - _fromRadius) * k;
      size = Vector2.all(radius * 3);
      priority = position.y.round() + 1000; // au-dessus des autres pendant le trajet
      if (_t >= 1) {
        _to = null;
        priority = position.y.round();
        onMoveEnd();
      }
    }
  }
}

/// Pièce placeholder : disque coloré avec la lettre française de la pièce.
class PlaceholderPieceComponent extends PieceComponent {
  PlaceholderPieceComponent({required super.type, required super.owner, required super.cellId});

  TextPainter? _tp;
  String? _tpKey;

  @override
  void renderPiece(ui.Canvas canvas, Vector2 size) {
    final r = radius;
    final c = ui.Offset(size.x / 2, size.y / 2);
    final base = frozen ? const ui.Color(0xFF6B7080) : playerColors[owner];
    final accent = frozen ? const ui.Color(0xFF8A8FA0) : playerAccents[owner];

    // Ombre au sol.
    canvas.drawOval(
      ui.Rect.fromCenter(center: c + ui.Offset(0, r * 0.55), width: r * 2.2, height: r * 0.9),
      ui.Paint()..color = const ui.Color(0x66000000),
    );
    // Socle (épaisseur) puis disque.
    final top = c + ui.Offset(0, -r * 0.1 - (selected ? r * 0.35 : 0));
    canvas.drawCircle(top + ui.Offset(0, r * 0.22), r, ui.Paint()..color = _dark(base));
    canvas.drawCircle(
      top,
      r,
      ui.Paint()
        ..shader = ui.Gradient.radial(top - ui.Offset(r * 0.3, r * 0.35), r * 1.5,
            [_light(base), base], [0, 1]),
    );
    canvas.drawCircle(
      top,
      r,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, r * 0.14)
        ..color = accent,
    );

    final key = '${pieceLetter(type)}-${r.round()}-$owner-$frozen';
    if (_tpKey != key) {
      _tpKey = key;
      _tp = TextPainter(
        text: TextSpan(
          text: pieceLetter(type),
          style: TextStyle(
            color: frozen
                ? const ui.Color(0xFF2A2D38)
                : (owner == 0 ? const ui.Color(0xFF1A2347) : const ui.Color(0xFFFFFFFF)),
            fontWeight: FontWeight.w800,
            fontSize: r * 1.15,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    final tp = _tp!;
    tp.paint(canvas, top - ui.Offset(tp.width / 2, tp.height / 2));
  }

  static ui.Color _dark(ui.Color c) => ui.Color.lerp(c, const ui.Color(0xFF000000), 0.45)!;
  static ui.Color _light(ui.Color c) => ui.Color.lerp(c, const ui.Color(0xFFFFFFFF), 0.3)!;
}

/// Éclat bref (prise de pièce) : anneau qui s'étend en s'estompant.
class FlashComponent extends PositionComponent {
  FlashComponent({required Vector2 center, required this.maxRadius, required this.color})
      : super(position: center, anchor: Anchor.center, priority: 100000);
  final double maxRadius;
  final ui.Color color;
  double _t = 0;
  static const duration = 0.4;

  @override
  void update(double dt) {
    _t += dt / duration;
    if (_t >= 1) removeFromParent();
  }

  @override
  void render(ui.Canvas canvas) {
    final k = Curves.easeOut.transform(_t.clamp(0, 1));
    final alpha = ((1 - k) * 255).round();
    final r = maxRadius * (0.4 + 1.6 * k);
    canvas.drawCircle(
      ui.Offset.zero,
      r,
      ui.Paint()..color = color.withAlpha((alpha * 0.45).round()),
    );
    canvas.drawCircle(
      ui.Offset.zero,
      r,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = maxRadius * 0.25 * (1 - k) + 1
        ..color = const ui.Color(0xFFFFFFFF).withAlpha(alpha),
    );
  }
}
