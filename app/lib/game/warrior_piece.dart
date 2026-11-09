import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

import '../models/protocol.dart';
import 'fx.dart';
import 'piece_component.dart';
import 'rig/anim.dart';
import 'rig/skeleton.dart';
import 'rig/warrior_rig.dart';
import 'warrior_art.dart';

export 'rig/anim.dart' show AnimState;

/// Guerrier animé par squelette procédural (voir rig/) : machine à états IDLE, MOVE, JUMP,
/// ATTACK, HIT, KO, VICTORY, PETRIFIED ; aura et traînées en sprites texturés (atlas CC0) ;
/// statue mise en cache (Picture) une fois pétrifiée ; niveau de détail selon la taille.
class WarriorPiece extends PieceComponent {
  WarriorPiece({required super.type, required super.owner, required super.cellId})
      : _phase = (owner * 1.7 + cellId.hashCode % 97 * 0.37) {
    rig = WarriorRig(type, phase: _phase);
  }

  final double _phase;
  late WarriorRig rig;
  double _time = 0;
  double _aura = 1;
  double _lift = 0;
  double _flash = 0;
  double _moveDur = 0.38;
  double _arc = 0;
  bool _flying = false;
  bool _wasFrozen = false;
  bool _facingSet = false;
  final Vector2 _lastPos = Vector2.zero();
  bool _hasLastPos = false;

  /// Orientation horizontale (1 : vers la droite de l'écran, -1 : vers la gauche).
  double facing = 1;

  // KO / dissolution.
  bool _ko = false;
  bool _dissolve = true;
  double _koT = 0;
  double alpha = 1;

  /// Retirer la pièce du jeu une fois dissoute (faux dans la galerie).
  bool removeAfterKo = true;

  // Traînée lumineuse : tampon circulaire préalloué.
  static const _trailN = 16;
  final Float32List _trail = Float32List(_trailN * 2);
  final Float32List _trailAge = Float32List(_trailN);
  int _trailHead = 0;

  final SpriteBatch _sprites = SpriteBatch(48);
  final ui.Paint _fill = ui.Paint();
  final ui.Paint _line = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round;
  final ui.Paint _layer = ui.Paint();
  final math.Random _rng = math.Random();

  // Statue (pièce pétrifiée immobile) enregistrée une fois en Picture.
  ui.Picture? _statue;
  int _statueKey = 0;

  AnimState get animState => rig.state;
  double get flash => _flash;
  double get auraLevel => _aura;

  @override
  double get moveDuration => _moveDur;

  static int lodFor(double radius) => radius >= 26 ? 2 : (radius >= 13 ? 1 : 0);

  // ------------------------------------------------------------- commandes

  @override
  void onMoveStart() {
    _trailAge.fillRange(0, _trailN, 9);
    final to = moveTarget;
    final d = to == null ? 0.0 : to.distanceTo(position) / math.max(1, radius);
    if (to != null && (to.x - position.x).abs() > radius * 0.3) facing = to.x >= position.x ? 1 : -1;
    // Cavalier et pièces lointaines : saut (vol) ; sinon marche / course rapide.
    _flying = type == PieceType.knight || d > 6.5;
    if (_flying) {
      _moveDur = (0.42 + d * 0.012).clamp(0.45, 0.75);
      _arc = radius * (0.5 + d * 0.06).clamp(0.6, 2.4);
      rig.play(AnimState.jump, duration: _moveDur, blend: 0.08);
    } else {
      _moveDur = (0.3 + d * 0.025).clamp(0.32, 0.55);
      _arc = 0;
      rig.play(AnimState.move, duration: null, blend: 0.12, restart: rig.state != AnimState.move);
      rig.sm.speed = (0.5 / _moveDur * 0.9).clamp(0.9, 2.2);
    }
  }

  @override
  void onMoveEnd() {
    if (rig.state == AnimState.move) rig.play(AnimState.idle, blend: 0.18);
    _flying = false;
  }

  @override
  void startAttack(Vector2 dir) {
    if (dir.x.abs() > 1e-3) facing = dir.x >= 0 ? 1 : -1;
    rig.play(AnimState.attack, blend: 0.1);
  }

  @override
  void endAttack() {}

  @override
  void hit() {
    _flash = 1;
    if (!_ko) rig.play(AnimState.hit, blend: 0.05);
  }

  @override
  void faceTowards(Vector2 p) {
    if ((p.x - position.x).abs() > 1e-3) facing = p.x >= position.x ? 1 : -1;
    _facingSet = true;
  }

  @override
  void knockOut({bool dissolve = true}) {
    _ko = true;
    _dissolve = dissolve;
    _koT = 0;
    rig.play(AnimState.ko, blend: 0.08);
  }

  @override
  void celebrate() {
    if (!frozen && !_ko) rig.play(AnimState.victory, blend: 0.2);
  }

  /// Joue un état sur place (galerie).
  void playState(AnimState s) {
    _ko = false;
    alpha = 1;
    rig.physics = true;
    if (s != AnimState.petrified && frozen) frozen = false;
    switch (s) {
      case AnimState.ko:
        knockOut();
      case AnimState.petrified:
        frozen = true;
      case AnimState.hit:
        hit();
      case AnimState.jump:
        rig.play(s, duration: 0.7);
      default:
        rig.play(s);
    }
  }

  // ------------------------------------------------------------- mise à jour

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (type != rig.type) rig = WarriorRig(type, phase: _phase); // promotion
    if (!_facingSet) {
      final g = findGame();
      if (g != null && g.size.x > 0) {
        facing = position.x <= g.size.x / 2 ? 1 : -1;
        _facingSet = true;
      }
    }
    if (frozen != _wasFrozen) {
      _wasFrozen = frozen;
      _trailAge.fillRange(0, _trailN, 9);
      if (frozen) {
        rig.play(AnimState.petrified, blend: 0.25);
      } else {
        rig.physics = true;
        if (rig.state == AnimState.petrified) rig.play(AnimState.idle, blend: 0.3);
      }
      _statue = null;
    }
    if (frozen && rig.stateTime > 0.9) rig.physics = false;

    // Inertie des chaînes : déplacement de la pièce converti en unités d'art.
    final s = radius * 0.72;
    var sx = 0.0, sy = 0.0;
    if (_hasLastPos && s > 0) {
      sx = (position.x - _lastPos.x) / s * facing;
      sy = (position.y - _lastPos.y) / s;
    }
    _lastPos.setFrom(position);
    _hasLastPos = true;
    if (!(frozen && _statue != null)) rig.update(dt, shiftX: sx, shiftY: sy);

    final attacking = rig.state == AnimState.attack;
    final targetAura = frozen || _ko
        ? 0.0
        : inCheck
            ? 2.0
            : attacking
                ? 2.6
                : selected
                    ? 2.2
                    : 1.0;
    _aura += (targetAura - _aura) * math.min(1, dt * 9);
    final targetLift = selected && !frozen ? 1.0 : 0.0;
    _lift += (targetLift - _lift) * math.min(1, dt * 12);
    if (_flash > 0) _flash = math.max(0, _flash - dt / 0.18);

    if (_ko) _updateKo(dt);

    for (var i = 0; i < _trailN; i++) {
      _trailAge[i] += dt;
    }
    if (isMoving) {
      _trailHead = (_trailHead + 1) % _trailN;
      _trail[_trailHead * 2] = position.x;
      _trail[_trailHead * 2 + 1] = position.y - radius * 0.6;
      _trailAge[_trailHead] = 0;
    }
  }

  void _updateKo(double dt) {
    _koT += dt;
    if (!_dissolve || _koT < 0.75) return;
    final k = ((_koT - 0.75) / 0.65).clamp(0.0, 1.0);
    alpha = 1 - Curves.easeIn.transform(k);
    // Dissolution : la silhouette s'efface en fumée et en étincelles.
    final g = findGame();
    if (g is FxHost && k < 1) {
      final host = g;
      final pal = WarriorPalette.of(owner);
      final s = radius * 0.72;
      final n = (dt * 70).ceil();
      for (var i = 0; i < n; i++) {
        final u = _rng.nextDouble();
        final b = u < 0.5 ? B.torso : (u < 0.75 ? B.head : B.pelvis);
        final p = rig.bonepoint(b, (_rng.nextDouble() - 0.5) * 0.5, -_rng.nextDouble() * 0.6);
        final x = position.x + p.dx * s * facing;
        final y = position.y + radius * 0.6 + p.dy * s;
        if (i.isEven) {
          host.pool.emit(x, y, (_rng.nextDouble() - 0.5) * radius * 2, -radius * (1 + _rng.nextDouble() * 2), 0.8,
              radius * 0.22, pal.dark.withAlpha(150), glow: false, fx: Fx.smokeB);
        } else {
          host.pool.emit(x, y, (_rng.nextDouble() - 0.5) * radius * 3, -radius * (2 + _rng.nextDouble() * 3), 0.6,
              radius * 0.12, pal.aura, fx: Fx.spark);
        }
      }
    }
    if (k >= 1 && removeAfterKo) removeFromParent();
  }

  // ------------------------------------------------------------- rendu

  static ui.Image? _shadowImg;
  static ui.Image get _shadow {
    final img = _shadowImg;
    if (img != null) return img;
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.drawOval(
        const ui.Rect.fromLTWH(16, 12, 96, 40),
        ui.Paint()
          ..color = const ui.Color(0xFF000000)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7));
    return _shadowImg = rec.endRecording().toImageSync(128, 64);
  }

  static const _shadowSrc = ui.Rect.fromLTWH(0, 0, 128, 64);

  @override
  void renderPiece(ui.Canvas canvas, Vector2 size) {
    if (alpha <= 0) return;
    final r = radius;
    final s = r * 0.72; // pixels par unité d'art
    final cx = size.x / 2;
    final feetY = size.y / 2 + r * 0.6;
    final pal = frozen ? WarriorPalette.stone : WarriorPalette.of(owner);
    final auraPal = inCheck && !frozen ? WarriorPalette.alert : pal;
    final hop = isMoving && _flying ? math.sin(math.pi * moveProgress) * _arc : 0.0;
    final lift = _lift * r * 0.5 + hop;
    final lod = lodFor(r);
    // Hauteur du bassin au-dessus de sa position de repos (sauts du clip) -> ombre.
    final airborne = math.max(0.0, -rig.skeleton.world[5]) * s + lift;

    _renderTrail(canvas, size, auraPal);

    // Socle + ombre douce (image floutée partagée, mise à l'échelle).
    final shrink = 1 / (1 + airborne / (r * 3));
    _fill
      ..color = ui.Color.fromARGB((150 * shrink * alpha).round(), 255, 255, 255)
      ..blendMode = ui.BlendMode.srcOver;
    canvas.drawImageRect(
        _shadow,
        _shadowSrc,
        ui.Rect.fromCenter(center: ui.Offset(cx, feetY + r * 0.1), width: r * 3.4 * shrink, height: r * 1.6 * shrink),
        _fill);
    _fill.color = frozen ? const ui.Color(0xFF3A3C44) : pal.dark;
    canvas.drawOval(ui.Rect.fromCenter(center: ui.Offset(cx, feetY + r * 0.1), width: r * 2.1, height: r * 0.8), _fill);
    _fill.color = frozen ? const ui.Color(0xFF5A5C66) : ui.Color.lerp(pal.dark, pal.outfit, 0.55)!;
    canvas.drawOval(ui.Rect.fromCenter(center: ui.Offset(cx, feetY), width: r * 2.1, height: r * 0.78), _fill);
    _line
      ..strokeWidth = math.max(1, r * 0.09)
      ..color = frozen ? const ui.Color(0xFF8C8F99) : pal.light;
    canvas.drawOval(ui.Rect.fromCenter(center: ui.Offset(cx, feetY), width: r * 1.9, height: r * 0.68), _line);

    if (_aura > 0.03) _renderAura(canvas, cx, feetY - lift, r, auraPal);

    var dx = 0.0, dy = 0.0;
    if (inCheck && !frozen) {
      dx += math.sin(_time * 70) * r * 0.06;
      dy += math.cos(_time * 90) * r * 0.03;
    }
    canvas.save();
    canvas.translate(cx + dx, feetY - lift + dy);
    canvas.scale(s * facing, s);
    final fading = alpha < 1;
    if (fading) {
      _layer.color = ui.Color.fromARGB((alpha * 255).round(), 255, 255, 255);
      canvas.saveLayer(null, _layer);
    }
    if (frozen && rig.state == AnimState.petrified && rig.stateTime > 0.9) {
      final key = lod * 100000 + (s * 8).round();
      if (_statue == null || _statueKey != key) {
        final rec = ui.PictureRecorder();
        rig.render(ui.Canvas(rec), pal, pxPerUnit: s, lod: lod);
        _statue = rec.endRecording();
        _statueKey = key;
      }
      canvas.drawPicture(_statue!);
    } else {
      rig.render(canvas, pal, pxPerUnit: s, lod: lod, flash: _flash);
      if (!frozen) _renderHeldFx(canvas, pal);
    }
    if (fading) canvas.restore();
    canvas.restore();
  }

  /// Lueurs accrochées aux os (orbe du bâton, charge d'énergie dans les mains).
  void _renderHeldFx(ui.Canvas canvas, WarriorPalette pal) {
    final pulse = 0.85 + 0.15 * math.sin(_time * 5 + _phase);
    final atk = rig.state == AnimState.attack ? rig.sm.progress : -1.0;
    if (type == PieceType.bishop) {
      final o = rig.bonepoint(B.prop, 0, -2.02);
      final k = atk >= 0 ? 1.0 + 1.2 * math.sin(math.pi * atk) : 1.0;
      _sprites.addColor(Fx.glow, o.dx, o.dy, 1.3 * pulse * k, pal.aura, alpha: 0.9);
      _sprites.addColor(Fx.flare, o.dx, o.dy, 0.9 * k, const ui.Color(0xFFFFFFFF), rot: _time * 1.5, alpha: 0.6);
    }
    if (atk >= 0 && atk < 0.55 && (type == PieceType.queen || type == PieceType.king || type == PieceType.pawn)) {
      final k = math.sin(math.pi * atk / 0.55);
      final col = type == PieceType.king ? const ui.Color(0xFFFFD34D) : pal.aura;
      for (final b in [B.armFrontL, B.armBackL]) {
        final o = rig.bonepoint(b, 0, 0.45);
        _sprites.addColor(Fx.glow, o.dx, o.dy, 1.1 * k, col);
        _sprites.addColor(Fx.spark, o.dx, o.dy, 0.9 * k, const ui.Color(0xFFFFFFFF), rot: _time * 6);
      }
    }
    _sprites.flush(canvas);
  }

  void _renderTrail(ui.Canvas canvas, Vector2 size, WarriorPalette pal) {
    if (frozen) return;
    for (var i = 0; i < _trailN; i++) {
      final age = _trailAge[i];
      if (age > 0.35) continue;
      final k = 1 - age / 0.35;
      final px = _trail[i * 2] - position.x + size.x / 2;
      final py = _trail[i * 2 + 1] - position.y + size.y / 2 + radius * 0.2;
      _sprites.addColor(Fx.glow, px, py, radius * (0.8 + 1.6 * k), pal.aura, alpha: 0.55 * k);
      _sprites.addColor(Fx.smokeA, px, py, radius * (1.2 + 1.2 * (1 - k)), pal.aura, rot: i * 0.7, alpha: 0.35 * k);
      _sprites.addColor(Fx.spark, px, py, radius * 0.9 * k, const ui.Color(0xFFFFFFFF), rot: i * 1.3, alpha: 0.7 * k);
    }
    _sprites.flush(canvas);
  }

  void _renderAura(ui.Canvas canvas, double cx, double feetY, double r, WarriorPalette pal) {
    final lvl = _aura;
    final blink = inCheck ? (math.sin(_time * 14) > 0 ? 1.0 : 0.3) : 1.0;
    final pulse = 0.85 + 0.15 * math.sin(_time * 3.2 + _phase);
    final h = rig.def.height * r * 0.72;
    // Halo.
    _sprites.addColor(Fx.glow, cx, feetY - h * 0.45, h * 1.5 * math.sqrt(lvl) * pulse, pal.aura,
        alpha: (0.32 * lvl * blink).clamp(0.0, 0.8));
    // Flammes montantes (sprites « flame » teintés, mélange additif).
    const n = 10;
    for (var i = 0; i < n; i++) {
      final ph = (_time * (0.55 + 0.1 * (i % 3)) + i / n + _phase) % 1.0;
      final side = math.sin(i * 2.399 + _phase);
      final x = cx + side * r * (0.95 - 0.35 * ph) + math.sin(_time * 5 + i) * r * 0.08;
      final y = feetY - ph * h * (0.9 + 0.12 * lvl);
      final sz = r * (0.9 + 0.35 * lvl) * (1 - ph * 0.7);
      final a = (1 - ph) * math.min(1.0, lvl * 0.7) * blink;
      _sprites.addColor(Fx.flame, x, y, sz, pal.aura, rot: side * 0.25, alpha: a);
      if (i % 3 == 0) _sprites.addColor(Fx.glow, x, y, sz * 0.45, const ui.Color(0xFFFFFFFF), alpha: a * 0.5);
    }
    _sprites.flush(canvas);
  }
}

/// Fabrique par défaut du jeu : guerriers animés.
PieceComponent warriorFactory(PieceType type, int owner, String cellId) =>
    WarriorPiece(type: type, owner: owner, cellId: cellId);

/// Position approximative du torse (pour les attaques et explosions).
Vector2 chestOf(PieceComponent p) => p.position + Vector2(0, -p.radius * 0.28);

// Courbe d'easing exposée pour les tests/effets.
double easeOutQuad(double t) => Curves.easeOut.transform(t.clamp(0.0, 1.0));
