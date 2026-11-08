import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

import '../models/protocol.dart';
import 'fx.dart';
import 'piece_component.dart';
import 'warrior_art.dart';
import 'warrior_piece.dart';

/// Nom français de l'attaque spéciale de chaque type.
String attackName(PieceType t) => switch (t) {
      PieceType.queen => 'Rayon d\'énergie',
      PieceType.bishop => 'Rafale de sphères',
      PieceType.knight => 'Coup de pied éclair',
      PieceType.rook => 'Séisme',
      PieceType.pawn => 'Combo de poings',
      PieceType.king => 'Vague de ki dorée',
    };

/// Instant de l'impact (en secondes depuis le début de l'attaque).
double impactTime(PieceType t) => switch (t) {
      PieceType.queen => 0.42,
      PieceType.bishop => 0.48,
      PieceType.knight => 0.34,
      PieceType.rook => 0.5,
      PieceType.pawn => 0.62,
      PieceType.king => 0.55,
    };

/// Rendu d'une attaque spéciale (≈ 900 ms) entre deux points écran.
class AttackEffect extends Component {
  AttackEffect({
    required this.type,
    required this.from,
    required this.to,
    required this.unit,
    required this.color,
    required this.pool,
  }) : super(priority: 99995);

  static const duration = 0.9;
  final PieceType type;
  final Vector2 from;
  final Vector2 to;

  /// Rayon d'un pion (échelle des effets).
  final double unit;
  final ui.Color color;
  final ParticlePool pool;
  double t = 0;
  final ui.Paint _p = ui.Paint()
    ..strokeCap = ui.StrokeCap.round
    ..style = ui.PaintingStyle.stroke;
  final ui.Paint _f = ui.Paint();
  final math.Random _rng = math.Random(3);

  static const _white = ui.Color(0xFFFFFFFF);
  static const _gold = ui.Color(0xFFFFD34D);

  @override
  void update(double dt) {
    t += dt;
    _emit(dt);
    if (t >= duration) removeFromParent();
  }

  double _k(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  void _emit(double dt) {
    final r = unit;
    switch (type) {
      case PieceType.queen:
        if (t > 0.3 && t < 0.8) {
          final k = _k(0.3, 0.42);
          final x = from.x + (to.x - from.x) * k;
          final y = from.y + (to.y - from.y) * k;
          pool.emit(x, y, (_rng.nextDouble() - 0.5) * 160, (_rng.nextDouble() - 0.5) * 160, 0.4,
              r * 0.22, color);
          pool.emit(to.x, to.y, (_rng.nextDouble() - 0.5) * 300, -_rng.nextDouble() * 220, 0.35,
              r * 0.25, _white);
        }
      case PieceType.bishop:
        for (var i = 0; i < 5; i++) {
          final s = 0.2 + i * 0.09;
          final k = (t - s) / 0.24;
          if (k > 0 && k < 1) {
            final o = _orb(i, k);
            pool.emit(o.dx, o.dy, 0, 0, 0.3, r * 0.2, color);
          }
        }
      case PieceType.rook:
        if (t > 0.4 && t < 0.62) {
          final k = _k(0.4, 0.5);
          pool.emit(from.x + (to.x - from.x) * k, from.y + r * 0.9, (_rng.nextDouble() - 0.5) * 140,
              -80 - _rng.nextDouble() * 200, 0.6, r * 0.18, const ui.Color(0xFF8A7A6A),
              g: 600, glow: false);
        }
      case PieceType.knight:
      case PieceType.pawn:
      case PieceType.king:
        if (type == PieceType.king && t > 0.3 && t < 0.8) {
          final k = _k(0.3, 0.55);
          pool.emit(from.x + (to.x - from.x) * k, from.y + (to.y - from.y) * k,
              (_rng.nextDouble() - 0.5) * 120, -_rng.nextDouble() * 120, 0.5, r * 0.2, _gold);
        }
    }
  }

  ui.Offset _orb(int i, double k) {
    final side = (i - 2) * 0.35 * unit;
    final dir = to - from;
    final len = dir.length;
    final nx = len < 1e-3 ? 0.0 : -dir.y / len;
    final ny = len < 1e-3 ? 1.0 : dir.x / len;
    final e = Curves.easeIn.transform(k);
    final arc = math.sin(math.pi * k) * side;
    return ui.Offset(from.x + dir.x * e + nx * arc, from.y + dir.y * e + ny * arc - unit * 0.5 * (i % 2));
  }

  @override
  void render(ui.Canvas canvas) {
    final r = unit;
    switch (type) {
      case PieceType.queen:
        _queen(canvas, r);
      case PieceType.bishop:
        _bishop(canvas, r);
      case PieceType.knight:
        _knight(canvas, r);
      case PieceType.rook:
        _rook(canvas, r);
      case PieceType.pawn:
        _pawn(canvas, r);
      case PieceType.king:
        _king(canvas, r);
    }
  }

  void _glowCircle(ui.Canvas c, ui.Offset o, double rad, ui.Color col) {
    _f
      ..blendMode = ui.BlendMode.plus
      ..color = col.withAlpha(110);
    c.drawCircle(o, rad * 1.7, _f);
    _f.color = col.withAlpha(220);
    c.drawCircle(o, rad, _f);
    _f
      ..color = _white
      ..blendMode = ui.BlendMode.srcOver;
    c.drawCircle(o, rad * 0.5, _f);
  }

  void _queen(ui.Canvas canvas, double r) {
    final a = ui.Offset(from.x, from.y);
    final charge = _k(0.0, 0.32);
    if (t < 0.34) {
      _glowCircle(canvas, a, r * (0.15 + 0.5 * Curves.easeIn.transform(charge)), color);
    }
    if (t > 0.3 && t < 0.85) {
      final reach = Curves.easeOut.transform(_k(0.3, 0.42));
      final end = ui.Offset(from.x + (to.x - from.x) * reach, from.y + (to.y - from.y) * reach);
      final env = math.sqrt(math.sin(math.pi * _k(0.3, 0.85)));
      final w = r * 0.9 * env * (1 + 0.12 * math.sin(t * 90));
      _p.blendMode = ui.BlendMode.plus;
      _p
        ..strokeWidth = w * 2.2
        ..color = color.withAlpha(80);
      canvas.drawLine(a, end, _p);
      _p
        ..strokeWidth = w * 1.3
        ..color = color.withAlpha(210);
      canvas.drawLine(a, end, _p);
      _p
        ..strokeWidth = w * 0.55
        ..color = _white;
      canvas.drawLine(a, end, _p);
      _p.blendMode = ui.BlendMode.srcOver;
      _glowCircle(canvas, end, r * 0.6 * env, color);
    }
  }

  void _bishop(ui.Canvas canvas, double r) {
    if (t < 0.45) {
      // Sphères en charge autour du bâton.
      for (var i = 0; i < 5; i++) {
        final s = 0.2 + i * 0.09;
        if (t < s) {
          final ang = i * 1.26 + t * 9;
          _glowCircle(
              canvas,
              ui.Offset(from.x + math.cos(ang) * r * 0.7, from.y - r * 0.4 + math.sin(ang) * r * 0.35),
              r * 0.13 * Curves.easeOut.transform(_k(0, s)),
              color);
        }
      }
    }
    for (var i = 0; i < 5; i++) {
      final k = (t - (0.2 + i * 0.09)) / 0.24;
      if (k <= 0 || k >= 1) continue;
      _glowCircle(canvas, _orb(i, k), r * 0.26, color);
    }
  }

  void _knight(ui.Canvas canvas, double r) {
    if (t < 0.18 || t > 0.8) return;
    final k = _k(0.18, 0.42);
    final dir = to - from;
    final len = dir.length;
    if (len < 1e-3) return;
    final nx = -dir.y / len, ny = dir.x / len;
    final end = ui.Offset(from.x + dir.x * k, from.y + dir.y * k);
    final fade = 1 - _k(0.45, 0.8);
    // Éclair en zigzag.
    final path = ui.Path()..moveTo(from.x, from.y);
    const seg = 7;
    for (var i = 1; i <= seg; i++) {
      final f = i / seg * k;
      final j = (i % 2 == 0 ? 1 : -1) * r * 0.35 * (i == seg ? 0 : 1);
      path.lineTo(from.x + dir.x * f + nx * j, from.y + dir.y * f + ny * j);
    }
    _p.blendMode = ui.BlendMode.plus;
    _p
      ..strokeWidth = r * 0.7
      ..color = color.withAlpha((120 * fade).round());
    canvas.drawPath(path, _p);
    _p
      ..strokeWidth = r * 0.22
      ..color = ui.Color.fromARGB((255 * fade).round(), 255, 255, 255);
    canvas.drawPath(path, _p);
    _p.blendMode = ui.BlendMode.srcOver;
    _glowCircle(canvas, end, r * 0.4 * fade, color);
    // Onde de choc à l'impact.
    final s = _k(0.34, 0.8);
    if (s > 0) {
      final rr = r * (0.5 + 2.8 * Curves.easeOut.transform(s));
      _p
        ..strokeWidth = r * 0.3 * (1 - s) + 1
        ..color = ui.Color.fromARGB(((1 - s) * 220).round(), 255, 255, 255);
      canvas.drawOval(ui.Rect.fromCenter(center: ui.Offset(to.x, to.y), width: rr * 2, height: rr * 1.2), _p);
    }
  }

  void _rook(ui.Canvas canvas, double r) {
    final g = ui.Offset(from.x, from.y + r * 0.9);
    final gt = ui.Offset(to.x, to.y + r * 0.9);
    if (t < 0.4) {
      _glowCircle(canvas, ui.Offset(from.x, from.y - r * 0.2), r * 0.5 * _k(0.1, 0.4), color);
      return;
    }
    final prog = Curves.easeOut.transform(_k(0.4, 0.52));
    final end = ui.Offset(g.dx + (gt.dx - g.dx) * prog, g.dy + (gt.dy - g.dy) * prog);
    final fade = 1 - _k(0.55, 0.9);
    // Fissure au sol en zigzag.
    final dir = gt - g;
    final nx = dir.distance < 1e-3 ? 0.0 : -dir.dy / dir.distance;
    final ny = dir.distance < 1e-3 ? 1.0 : dir.dx / dir.distance;
    final path = ui.Path()..moveTo(g.dx, g.dy);
    for (var i = 1; i <= 8; i++) {
      final f = i / 8 * prog;
      final j = (i % 2 == 0 ? 1 : -1) * r * 0.22;
      path.lineTo(g.dx + dir.dx * f + nx * j, g.dy + dir.dy * f + ny * j * 0.5);
    }
    _p
      ..strokeWidth = r * 0.5
      ..color = color.withAlpha((90 * fade).round());
    canvas.drawPath(path, _p);
    _p
      ..strokeWidth = r * 0.16
      ..color = ui.Color.fromARGB((230 * fade).round(), 30, 18, 12);
    canvas.drawPath(path, _p);
    // Anneaux de séisme.
    for (var i = 0; i < 3; i++) {
      final k = _k(0.4 + i * 0.06, 0.88);
      if (k <= 0) continue;
      final rr = r * 3.8 * Curves.easeOut.transform(k);
      _p
        ..strokeWidth = r * 0.28 * (1 - k) + 1
        ..color = (i == 0 ? _white : color).withAlpha(((1 - k) * 200).round());
      canvas.drawOval(ui.Rect.fromCenter(center: g, width: rr * 2, height: rr * 0.9), _p);
    }
    _glowCircle(canvas, end, r * 0.35 * fade, color);
    // Soulèvement au point d'arrivée.
    final k2 = _k(0.5, 0.9);
    if (k2 > 0) {
      final rr = r * 2.4 * Curves.easeOut.transform(k2);
      _p
        ..strokeWidth = r * 0.3 * (1 - k2) + 1
        ..color = _white.withAlpha(((1 - k2) * 230).round());
      canvas.drawOval(ui.Rect.fromCenter(center: gt, width: rr * 2, height: rr * 0.9), _p);
    }
  }

  void _pawn(ui.Canvas canvas, double r) {
    final dir = to - from;
    for (var i = 0; i < 6; i++) {
      final s = 0.1 + i * 0.1;
      final k = (t - s) / 0.1;
      if (k <= 0 || k >= 1) continue;
      final o = ui.Offset(to.x + math.sin(i * 2.7) * r * 0.55, to.y + math.cos(i * 1.9) * r * 0.45);
      final fist = ui.Offset(from.x + dir.x * (0.7 + 0.3 * k), from.y + dir.y * (0.7 + 0.3 * k));
      _p.blendMode = ui.BlendMode.plus;
      _p
        ..strokeWidth = r * 0.35
        ..color = color.withAlpha(200);
      canvas.drawLine(ui.Offset(from.x + dir.x * 0.4, from.y + dir.y * 0.4 - r * 0.2), o, _p);
      _p.blendMode = ui.BlendMode.srcOver;
      _glowCircle(canvas, fist, r * 0.2, color);
      // Étoile d'impact.
      _p
        ..strokeWidth = r * 0.12
        ..color = _white.withAlpha((255 * (1 - k)).round());
      for (var a = 0; a < 6; a++) {
        final ang = a * math.pi / 3 + i;
        final l1 = r * 0.15, l2 = r * (0.35 + 0.35 * k);
        canvas.drawLine(o + ui.Offset(math.cos(ang) * l1, math.sin(ang) * l1),
            o + ui.Offset(math.cos(ang) * l2, math.sin(ang) * l2), _p);
      }
      if (k < 0.2) pool.emit(o.dx, o.dy, 0, -40, 0.3, r * 0.2, _white);
    }
  }

  void _king(ui.Canvas canvas, double r) {
    final dir = to - from;
    final len = dir.length;
    if (len < 1e-3) return;
    final ang = math.atan2(dir.y, dir.x);
    if (t < 0.32) {
      // Le ki se rassemble.
      final k = _k(0, 0.32);
      _p
        ..strokeWidth = r * 0.14
        ..color = _gold.withAlpha((200 * k).round());
      final rr = r * (2.2 - 1.7 * k);
      canvas.drawOval(ui.Rect.fromCenter(center: ui.Offset(from.x, from.y), width: rr * 2, height: rr * 1.6), _p);
    }
    for (var i = 0; i < 3; i++) {
      final k = (t - (0.3 + i * 0.07)) / 0.3;
      if (k <= 0 || k >= 1.15) continue;
      final f = Curves.easeIn.transform(k.clamp(0.0, 1.0));
      final x = from.x + dir.x * f;
      final y = from.y + dir.y * f;
      final fade = (1 - (k - 0.8).clamp(0.0, 0.35) / 0.35);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(ang);
      _p.blendMode = ui.BlendMode.plus;
      final w = r * (1.6 + i * 0.4);
      final h = r * (3.4 + i * 0.5);
      _p
        ..strokeWidth = r * 0.5
        ..color = _gold.withAlpha((120 * fade).round());
      canvas.drawArc(ui.Rect.fromCenter(center: ui.Offset.zero, width: w, height: h), -math.pi * 0.42,
          math.pi * 0.84, false, _p);
      _p
        ..strokeWidth = r * 0.2
        ..color = ui.Color.fromARGB((255 * fade).round(), 255, 245, 200);
      canvas.drawArc(ui.Rect.fromCenter(center: ui.Offset.zero, width: w, height: h), -math.pi * 0.42,
          math.pi * 0.84, false, _p);
      _p.blendMode = ui.BlendMode.srcOver;
      canvas.restore();
    }
    final s = _k(0.55, 0.9);
    if (s > 0) {
      final rr = r * 3.2 * Curves.easeOut.transform(s);
      _f
        ..blendMode = ui.BlendMode.plus
        ..color = _gold.withAlpha(((1 - s) * 120).round());
      canvas.drawCircle(ui.Offset(to.x, to.y), rr, _f);
      _f.blendMode = ui.BlendMode.srcOver;
    }
  }
}

/// Déroule une prise : pose d'attaque, effet, impact sur la victime, puis déplacement
/// de l'attaquant. Non bloquant ; [finish] termine tout immédiatement (saut par tap).
class CaptureSequence extends Component {
  CaptureSequence({
    required this.host,
    required this.attacker,
    required this.victim,
    required this.destination,
    required this.destRadius,
    this.onImpact,
    this.onFinished,
  });

  final FxHost host;
  final PieceComponent attacker;
  final PieceComponent victim;
  final Vector2 destination;
  final double destRadius;
  final void Function()? onImpact;
  final void Function()? onFinished;

  double _t = 0;
  bool _impacted = false;
  bool _moved = false;
  bool _done = false;
  AttackEffect? _effect;

  static const total = 0.9;
  bool get isDone => _done;

  /// Position de la victime (conservée si elle est retirée du jeu).
  late final Vector2 _victimPos = chestOf(victim);

  @override
  void onMount() {
    super.onMount();
    final dir = victim.position - attacker.position;
    attacker.startAttack(dir);
    final pal = WarriorPalette.of(attacker.owner);
    _effect = AttackEffect(
      type: attacker.type,
      from: chestOf(attacker),
      to: _victimPos,
      unit: attacker.radius,
      color: attacker.type == PieceType.king ? const ui.Color(0xFFFFD34D) : pal.aura,
      pool: host.pool,
    );
    (parent ?? this).add(_effect!);
  }

  void _impact() {
    if (_impacted) return;
    _impacted = true;
    victim.hit();
    final pool = host.pool;
    final r = victim.radius;
    final vp = _victimPos;
    final vpal = WarriorPalette.of(victim.owner);
    pool.burst(vp.x, vp.y, 28, r * 14, r * 0.28, vpal.aura, lifeS: 0.8);
    pool.burst(vp.x, vp.y, 18, r * 10, r * 0.2, const ui.Color(0xFFFFFFFF), lifeS: 0.5);
    pool.burst(vp.x, vp.y, 10, r * 9, r * 0.16, vpal.dark, lifeS: 0.9, g: 500, glow: false);
    victim.parent?.add(ShockRing(
        center: victim.position + Vector2(0, r * 0.6), maxRadius: r * 2.8, color: vpal.aura));
    host.hitstop(0.08);
    host.shake(attacker.type == PieceType.rook ? r * 0.7 : r * 0.35,
        attacker.type == PieceType.rook ? 0.5 : 0.3);
    onImpact?.call();
  }

  void _startMove() {
    if (_moved) return;
    _moved = true;
    attacker.endAttack();
    attacker.moveTo(destination, destRadius);
  }

  @override
  void update(double dt) {
    if (_done) return;
    _t += dt;
    if (!_impacted && _t >= impactTime(attacker.type)) _impact();
    if (_impacted && _t >= impactTime(attacker.type) + 0.2 && victim.isMounted) {
      victim.removeFromParent();
    }
    if (!_moved && _t >= 0.72) _startMove();
    if (_t >= total) finish();
  }

  /// Termine immédiatement la séquence (fin normale ou saut par l'utilisateur).
  void finish() {
    if (_done) return;
    _done = true;
    _impact();
    if (victim.isMounted) victim.removeFromParent();
    _effect?.removeFromParent();
    _startMove();
    removeFromParent();
    onFinished?.call();
  }
}
