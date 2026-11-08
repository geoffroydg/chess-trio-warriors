import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

import '../models/protocol.dart';
import 'piece_component.dart';
import 'warrior_art.dart';

/// Guerrier animé : dessiné procéduralement (chemins vectoriels mis en cache),
/// aura en flammes, lévitation à la sélection, traînée de déplacement, gel en pierre.
class WarriorPiece extends PieceComponent {
  WarriorPiece({required super.type, required super.owner, required super.cellId})
      : _phase = (owner * 1.7 + cellId.hashCode % 97 * 0.37);

  final double _phase;
  double _time = 0;
  double _aura = 1;
  double _lift = 0;
  double _flash = 0;
  double _attackT = -1;
  double _attackClock = 0;
  final Vector2 _attackDir = Vector2(1, 0);
  bool _wasFrozen = false;

  @override
  double get moveDuration => type == PieceType.knight ? 0.45 : 0.38;

  // Traînée lumineuse : tampon circulaire préalloué.
  static const _trailN = 16;
  final Float32List _trail = Float32List(_trailN * 2);
  final Float32List _trailAge = Float32List(_trailN);
  int _trailHead = 0;

  final ui.Paint _fill = ui.Paint();
  final ui.Paint _line = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeCap = ui.StrokeCap.round;
  final ui.Paint _fx = ui.Paint();
  final ui.Path _dyn = ui.Path();
  final ui.Paint _glowPaint = ui.Paint();

  double get attackProgress => _attackT;
  double get flash => _flash;
  double get auraLevel => _aura;

  @override
  void startAttack(Vector2 dir) {
    _attackT = 0;
    _attackClock = 0;
    _attackDir.setFrom(dir.length2 < 1e-6 ? Vector2(1, 0) : dir.normalized());
  }

  @override
  void endAttack() => _attackT = -1;

  @override
  void hit() => _flash = 1;

  @override
  void onMoveStart() {
    _trailAge.fillRange(0, _trailN, 9);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (frozen != _wasFrozen) {
      _wasFrozen = frozen;
      _trailAge.fillRange(0, _trailN, 9);
    }
    final targetAura = frozen
        ? 0.0
        : inCheck
            ? 2.0
            : _attackT >= 0
                ? 2.6
                : selected
                    ? 2.2
                    : 1.0;
    _aura += (targetAura - _aura) * math.min(1, dt * 9);
    final targetLift = selected && !frozen ? 1.0 : 0.0;
    _lift += (targetLift - _lift) * math.min(1, dt * 12);
    if (_flash > 0) _flash = math.max(0, _flash - dt / 0.18);
    if (_attackT >= 0) {
      _attackClock += dt;
      _attackT = math.min(1, _attackClock / 0.9);
    }
    // Traînée
    for (var i = 0; i < _trailN; i++) {
      _trailAge[i] += dt;
    }
    if (isMoving) {
      _trailHead = (_trailHead + 1) % _trailN;
      _trail[_trailHead * 2] = position.x;
      _trail[_trailHead * 2 + 1] = position.y;
      _trailAge[_trailHead] = 0;
    }
  }

  double get _hop {
    if (!isMoving) return 0;
    final k = math.sin(math.pi * moveProgress);
    return switch (type) {
      PieceType.knight => k * 1.5,
      PieceType.bishop || PieceType.queen => k * 0.45,
      _ => k * 0.12,
    };
  }

  @override
  void renderPiece(ui.Canvas canvas, Vector2 size) {
    final r = radius;
    final s = r * 0.72; // taille d'une unité d'art
    final cx = size.x / 2;
    final feetY = size.y / 2 + r * 0.6;
    final pal = frozen ? WarriorPalette.stone : WarriorPalette.of(owner);
    final auraPal = inCheck && !frozen ? WarriorPalette.alert : pal;
    final lift = _lift * r * 0.5 + _hop * r;

    _renderTrail(canvas, size, auraPal);

    // Ombre + socle ombré.
    _fill.color = ui.Color.fromARGB((90 - (lift / r * 40)).clamp(30, 100).round(), 0, 0, 0);
    canvas.drawOval(
        ui.Rect.fromCenter(center: ui.Offset(cx, feetY + r * 0.08), width: r * 2.5, height: r * 0.95),
        _fill);
    _fill.color = frozen ? const ui.Color(0xFF3A3C44) : pal.dark;
    canvas.drawOval(
        ui.Rect.fromCenter(center: ui.Offset(cx, feetY + r * 0.1), width: r * 2.1, height: r * 0.8),
        _fill);
    _fill.color = frozen ? const ui.Color(0xFF5A5C66) : ui.Color.lerp(pal.dark, pal.outfit, 0.55)!;
    canvas.drawOval(
        ui.Rect.fromCenter(center: ui.Offset(cx, feetY), width: r * 2.1, height: r * 0.78), _fill);
    _line
      ..strokeWidth = math.max(1, r * 0.09)
      ..color = frozen ? const ui.Color(0xFF8C8F99) : pal.light;
    canvas.drawOval(
        ui.Rect.fromCenter(center: ui.Offset(cx, feetY), width: r * 1.9, height: r * 0.68), _line);

    // Aura : halo + flammes (particules analytiques, sans allocation).
    if (_aura > 0.03) _renderAura(canvas, cx, feetY, r, auraPal);

    // Corps.
    final breathe = frozen ? 0.0 : math.sin(_time * 2.4 + _phase) * 0.018;
    canvas.save();
    var dx = 0.0, dy = 0.0, lean = 0.0;
    if (inCheck && !frozen) {
      dx += math.sin(_time * 70) * r * 0.06;
      dy += math.cos(_time * 90) * r * 0.03;
    }
    var extraLift = 0.0;
    if (_attackT >= 0) {
      final a = _attackPose(_attackT);
      dx += _attackDir.x * a.$1 * r;
      dy += _attackDir.y * a.$1 * r * 0.6;
      extraLift = a.$2 * r;
      lean = a.$3 * (_attackDir.x >= 0 ? 1 : -1);
    }
    if (type == PieceType.knight && !frozen) {
      extraLift += (0.28 + math.sin(_time * 3 + _phase) * 0.08) * r;
    }
    canvas.translate(cx + dx, feetY - lift - extraLift + dy);
    canvas.rotate(lean + (type == PieceType.knight ? 0.12 : 0));
    canvas.scale(s * (1 - breathe * 0.6), s * (1 + breathe));
    final layers = WarriorArt.layers(type);
    final flashing = _flash > 0;
    if (!frozen) _renderBackDynamics(canvas);
    final outlineColor = frozen ? const ui.Color(0xFF22242B) : const ui.Color(0xE614101E);
    _line
      ..strokeWidth = 0.075
      ..color = outlineColor;
    for (final l in layers) {
      _fill.color = l.role >= 0 ? pal.roles[l.role] : (frozen ? l.stone! : l.color!);
      if (flashing) {
        _fill.color = ui.Color.lerp(_fill.color, const ui.Color(0xFFFFFFFF), _flash)!;
      }
      canvas.drawPath(l.path, _fill);
      if (l.outline) canvas.drawPath(l.path, _line);
    }
    if (frozen) {
      _line
        ..strokeWidth = 0.04
        ..color = const ui.Color(0xAA20222A);
      final h = WarriorArt.heightOf(type);
      canvas.drawLine(ui.Offset(-0.3, -h * 0.35), ui.Offset(0.05, -h * 0.5), _line);
      canvas.drawLine(ui.Offset(0.05, -h * 0.5), ui.Offset(0.35, -h * 0.62), _line);
      canvas.drawLine(ui.Offset(0.05, -h * 0.5), ui.Offset(-0.05, -h * 0.75), _line);
    } else {
      _renderFrontDynamics(canvas, pal);
    }
    canvas.restore();
  }

  /// (avance en unités de rayon, hauteur de saut, inclinaison) selon le type et la phase.
  (double, double, double) _attackPose(double t) {
    final env = math.sin(math.pi * t.clamp(0.0, 1.0));
    switch (type) {
      case PieceType.queen:
        final back = t < 0.35 ? -0.4 * math.sin(math.pi * t / 0.35) : 0.0;
        return (back + 0.35 * env, 0.1, 0.12 * env - (t < 0.35 ? 0.1 : 0));
      case PieceType.bishop:
        return (0, 0.7 * env, 0);
      case PieceType.knight:
        final k = t < 0.2 ? 0.0 : math.sin(math.pi * ((t - 0.2) / 0.5).clamp(0.0, 1.0));
        return (1.0 * k, 0.6 * k, 0.5 * k);
      case PieceType.rook:
        final up = t < 0.4 ? math.sin(math.pi / 2 * t / 0.4) : math.max(0.0, 1 - (t - 0.4) / 0.1);
        return (0.2 * up, 1.1 * up, 0.15 * (t > 0.4 ? 1 : 0));
      case PieceType.pawn:
        final k = (math.sin(t * 40) * 0.5 + 0.5) * (t < 0.7 ? 1 : 0);
        return (0.55 * k, 0.05, 0.12 * k);
      case PieceType.king:
        return (0.0, 0.5 * env, 0.0);
    }
  }

  void _renderTrail(ui.Canvas canvas, Vector2 size, WarriorPalette pal) {
    if (frozen) return;
    for (var i = 0; i < _trailN; i++) {
      final age = _trailAge[i];
      if (age > 0.35) continue;
      final k = 1 - age / 0.35;
      final px = _trail[i * 2] - position.x + size.x / 2;
      final py = _trail[i * 2 + 1] - position.y + size.y / 2 + radius * 0.2;
      _fx
        ..blendMode = ui.BlendMode.plus
        ..color = pal.flames[(k * 12).round().clamp(0, 15)];
      canvas.drawCircle(ui.Offset(px, py), radius * (0.25 + 0.75 * k), _fx);
      _fx.color = ui.Color.fromARGB((k * 160).round(), 255, 255, 255);
      canvas.drawCircle(ui.Offset(px, py), radius * 0.18 * k, _fx);
    }
    _fx.blendMode = ui.BlendMode.srcOver;
  }

  void _renderAura(ui.Canvas canvas, double cx, double feetY, double r, WarriorPalette pal) {
    final lvl = _aura;
    final blink = inCheck ? (math.sin(_time * 14) > 0 ? 1.0 : 0.25) : 1.0;
    final pulse = 0.85 + 0.15 * math.sin(_time * 3.2 + _phase);
    final h = WarriorArt.heightOf(type) * r * 0.72;
    // Halo (shader unitaire mis en cache dans la palette, mis à l'échelle).
    canvas.save();
    canvas.translate(cx, feetY - h * 0.4);
    canvas.scale(r * 1.7 * math.sqrt(lvl) * pulse, h * 0.75 * math.sqrt(lvl) * pulse);
    final a = (80 * lvl * blink).clamp(0, 190).round();
    _glowPaint
      ..shader = pal.glow.shader
      ..color = ui.Color.fromARGB(a, 255, 255, 255)
      ..blendMode = ui.BlendMode.plus;
    canvas.drawCircle(ui.Offset.zero, 1, _glowPaint);
    canvas.restore();
    // Flammes montantes.
    _fx.blendMode = ui.BlendMode.plus;
    const n = 9;
    for (var i = 0; i < n; i++) {
      final ph = (_time * (0.55 + 0.1 * (i % 3)) + i / n + _phase) % 1.0;
      final side = math.sin(i * 2.399 + _phase);
      final x = cx + side * r * (0.95 - 0.35 * ph) + math.sin(_time * 5 + i) * r * 0.08;
      final y = feetY - ph * h * (0.95 + 0.12 * lvl);
      final rad = r * (0.2 + 0.1 * lvl) * (1 - ph * 0.85);
      final idx = ((1 - ph) * 11 * math.min(1.2, lvl) * blink).round().clamp(0, 15);
      _fx.color = pal.flames[idx];
      canvas.drawCircle(ui.Offset(x, y), rad, _fx);
      if (rad > r * 0.12) {
        _fx.color = pal.flames[(idx ~/ 2)];
        canvas.drawCircle(ui.Offset(x, y - rad * 0.4), rad * 0.5, _fx);
      }
    }
    _fx.blendMode = ui.BlendMode.srcOver;
  }

  /// Éléments animés derrière le corps (cheveux de la dame, écharpe du cavalier).
  void _renderBackDynamics(ui.Canvas canvas) {
    final pal = WarriorPalette.of(owner);
    final w = math.sin(_time * 3 + _phase);
    switch (type) {
      case PieceType.queen:
        _dyn.reset();
        _dyn
          ..moveTo(-0.25, -2.85)
          ..cubicTo(-0.75, -2.7, -0.95 - 0.1 * w, -1.8, -0.8 - 0.25 * w, -1.0 + 0.05 * w)
          ..quadraticBezierTo(-0.6 - 0.1 * w, -1.5, -0.25, -1.9)
          ..lineTo(0.25, -1.9)
          ..quadraticBezierTo(0.6 + 0.1 * w, -1.5, 0.8 + 0.25 * w, -1.0 - 0.05 * w)
          ..cubicTo(0.95 + 0.1 * w, -1.8, 0.75, -2.7, 0.25, -2.85)
          ..close();
        _fill.color = pal.light;
        canvas.drawPath(_dyn, _fill);
        _line
          ..strokeWidth = 0.075
          ..color = const ui.Color(0xE614101E);
        canvas.drawPath(_dyn, _line);
      case PieceType.knight:
        _dyn.reset();
        _dyn.moveTo(-0.1, -1.72);
        for (var i = 1; i <= 8; i++) {
          final t = i / 8;
          _dyn.lineTo(-0.1 - t * 1.9, -1.72 - t * 0.2 + math.sin(_time * 7 - t * 6 + _phase) * 0.22 * t);
        }
        for (var i = 8; i >= 0; i--) {
          final t = i / 8;
          _dyn.lineTo(-0.1 - t * 1.9, -1.55 - t * 0.2 + math.sin(_time * 7 - t * 6 + _phase) * 0.22 * t + 0.1 * t);
        }
        _dyn.close();
        _fill.color = pal.light;
        canvas.drawPath(_dyn, _fill);
        _line
          ..strokeWidth = 0.06
          ..color = const ui.Color(0xE614101E);
        canvas.drawPath(_dyn, _line);
      default:
    }
  }

  /// Éléments animés devant le corps (cheveux du cavalier, orbe du bâton du fou).
  void _renderFrontDynamics(ui.Canvas canvas, WarriorPalette pal) {
    switch (type) {
      case PieceType.knight:
        _dyn.reset();
        final w = math.sin(_time * 6 + _phase) * 0.08;
        _dyn
          ..moveTo(-0.28, -2.05)
          ..lineTo(-0.5, -2.35 + w)
          ..lineTo(-0.2, -2.28)
          ..lineTo(-0.38, -2.62 + w)
          ..lineTo(-0.02, -2.38)
          ..lineTo(0.0, -2.72 + w)
          ..lineTo(0.2, -2.38)
          ..lineTo(0.42, -2.55 + w)
          ..lineTo(0.34, -2.08)
          ..lineTo(0.1, -2.18)
          ..close();
        _fill.color = const ui.Color(0xFF5A2E1A);
        canvas.drawPath(_dyn, _fill);
        _line
          ..strokeWidth = 0.06
          ..color = const ui.Color(0xE614101E);
        canvas.drawPath(_dyn, _line);
      case PieceType.bishop:
        final pulse = 0.8 + 0.2 * math.sin(_time * 5 + _phase);
        final charge = _attackT >= 0 ? 1.6 : 1.0;
        _fx.blendMode = ui.BlendMode.plus;
        _fx.color = pal.flames[(7 * pulse * charge).round().clamp(0, 15)];
        canvas.drawCircle(const ui.Offset(0.89, -3.5), 0.55 * pulse * charge, _fx);
        _fx.color = const ui.Color(0xFFFFFFFF);
        canvas.drawCircle(const ui.Offset(0.89, -3.5), 0.17, _fx);
        _fx.blendMode = ui.BlendMode.srcOver;
        _line
          ..strokeWidth = 0.07
          ..color = pal.accent;
        canvas.drawArc(ui.Rect.fromCenter(center: const ui.Offset(0.89, -3.5), width: 0.6, height: 0.6),
            math.pi * 0.9, math.pi * 1.2, false, _line);
      case PieceType.rook:
        final pulse = 0.5 + 0.5 * math.sin(_time * 4 + _phase);
        _fx.color = ui.Color.fromARGB((120 + 120 * pulse).round(), 255, 255, 255);
        canvas.drawCircle(const ui.Offset(0, -1.5), 0.07, _fx);
      default:
    }
  }
}

/// Fabrique par défaut du jeu : guerriers animés.
PieceComponent warriorFactory(PieceType type, int owner, String cellId) =>
    WarriorPiece(type: type, owner: owner, cellId: cellId);

/// Position approximative du torse (pour les attaques et explosions).
Vector2 chestOf(PieceComponent p) => p.position + Vector2(0, -p.radius * 0.28);

// Courbe d'easing exposée pour les tests/effets.
double easeOutQuad(double t) => Curves.easeOut.transform(t.clamp(0.0, 1.0));
