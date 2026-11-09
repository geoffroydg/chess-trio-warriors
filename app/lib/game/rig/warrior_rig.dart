import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/protocol.dart';
import '../warrior_art.dart';
import 'anim.dart';
import 'skeleton.dart';
import 'warrior_defs.dart';

/// Couleurs dérivées (remplissage, ombre, liseré, dégradé) d'un type pour une palette.
class _ColorSet {
  _ColorSet(RigDef def, WarriorPalette pal) {
    final stone = pal.id == 4;
    ui.Color base(int role, ui.Color? c) {
      if (role >= 0) return pal.roles[role];
      if (role <= -10) {
        final f = chainColors[-10 - role];
        return stone ? stoneOf(f) : f;
      }
      final f = c ?? const ui.Color(0xFFFF00FF);
      if (!stone || f.a < 0.99) return f;
      return stoneOf(f);
    }

    for (final p in def.parts) {
      final f = base(p.role, p.color);
      fill.add(f);
      shade.add(_shadeOf(f));
      rim.add(_rimOf(f, pal.aura));
      if (p.grad) {
        final b = p.bounds;
        grad.add(ui.Gradient.linear(ui.Offset(0, b.top), ui.Offset(0, b.bottom),
            [ui.Color.lerp(f, const ui.Color(0xFFFFFFFF), 0.2)!, f, ui.Color.lerp(f, const ui.Color(0xFF000000), 0.12)!],
            const [0, 0.45, 1]));
      } else {
        grad.add(null);
      }
    }
    for (final c in def.chains) {
      chainFill.add(base(c.role, null));
    }
  }

  final List<ui.Color> fill = [], shade = [], rim = [], chainFill = [];
  final List<ui.Shader?> grad = [];

  static ui.Color _shadeOf(ui.Color c) {
    // Ombre « anime » : plus sombre et légèrement bleutée.
    final r = (c.r * 255 * 0.68).round(), g = (c.g * 255 * 0.62).round();
    final b = math.min(255, (c.b * 255 * 0.74 + 22).round());
    return ui.Color.fromARGB(255, r, g, b);
  }

  static ui.Color _rimOf(ui.Color c, ui.Color aura) =>
      ui.Color.lerp(ui.Color.lerp(c, aura, 0.45), const ui.Color(0xFFFFFFFF), 0.5)!.withAlpha(230);
}

/// Instance animée d'un guerrier : squelette, machine à états, chaînes souples, rendu.
class WarriorRig {
  WarriorRig(this.type, {double phase = 0})
      : def = RigDef.of(type),
        _time = phase,
        _blinkAt = 1.5 + (phase * 7.31) % 2.5 {
    skeleton = Skeleton(parents: def.parents, rest: def.rest);
    sm = AnimationStateMachine(def.clips, def.parents.length);
    chains = [for (final c in def.chains) SpringChain(c)]..sort((a, b) => a.def.z - b.def.z);
    _chainColor = [for (final c in chains) def.chains.indexOf(c.def)];
    sm.time = phase;
    sm.update(0);
    skeleton.solve(sm.out);
    for (final c in chains) {
      c.reset(skeleton);
      c.buildPath();
    }
  }

  final PieceType type;
  final RigDef def;
  late final Skeleton skeleton;
  late final AnimationStateMachine sm;
  late final List<SpringChain> chains;
  late final List<int> _chainColor;
  double _time;
  double _blinkAt;

  /// Physique des chaînes (désactivée pour une statue).
  bool physics = true;

  AnimState get state => sm.state;
  double get stateTime => sm.time / (sm.speed == 0 ? 1 : sm.speed);

  void play(AnimState s, {double? duration, double blend = 0.15, bool restart = true}) =>
      sm.play(s, duration: duration, blend: blend, restart: restart);

  /// Avance l'animation. [shiftX]/[shiftY] : déplacement de la pièce (unités d'art, repère
  /// du personnage) depuis l'image précédente, pour l'inertie des chaînes.
  void update(double dt, {double shiftX = 0, double shiftY = 0}) {
    _time += dt;
    sm.update(dt);
    // Clignement des yeux (procédural, par-dessus le clip).
    if (sm.state != AnimState.ko && sm.state != AnimState.petrified) {
      final k = _time - _blinkAt;
      if (k > 0) {
        final b = k < 0.06 ? 1 - k / 0.06 : (k < 0.13 ? (k - 0.06) / 0.07 : 1.0);
        sm.out.set(B.eyes, Ch.sy, sm.out.get(B.eyes, Ch.sy) * (0.1 + 0.9 * b));
        if (k >= 0.13) _blinkAt = _time + 2.2 + (_time * 3.7) % 2.6;
      }
    }
    skeleton.solve(sm.out);
    if (physics) {
      for (final c in chains) {
        if (shiftX != 0 || shiftY != 0) c.shift(-shiftX, -shiftY);
        c.update(skeleton, dt, _time);
      }
    }
    for (final c in chains) {
      c.buildPath();
    }
  }

  /// Point d'un os en coordonnées d'art (effets accrochés à une main, au bâton...).
  ui.Offset bonepoint(int bone, double x, double y) =>
      ui.Offset(skeleton.worldX(bone, x, y), skeleton.worldY(bone, x, y));

  bool get isFinite {
    for (final v in skeleton.world) {
      if (!v.isFinite) return false;
    }
    for (final v in sm.out.v) {
      if (!v.isFinite) return false;
    }
    for (final c in chains) {
      if (!c.valid) return false;
    }
    return true;
  }

  // ------------------------------------------------------------------ rendu

  static final Map<int, _ColorSet> _colorCache = {};
  static final Float64List _m4 = Skeleton.identity4();
  static final ui.Paint _fill = ui.Paint()..isAntiAlias = true;
  static final ui.Paint _stroke = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeCap = ui.StrokeCap.round;
  static const _stoneInk = ui.Color(0xFF26272E);

  _ColorSet _colors(WarriorPalette pal) =>
      _colorCache.putIfAbsent(type.index * 16 + pal.id, () => _ColorSet(def, pal));

  void _push(ui.Canvas canvas, int bone) {
    canvas.save();
    skeleton.matrix4(bone, _m4);
    canvas.transform(_m4);
  }

  /// Dessine le guerrier dans le repère d'art courant (pieds en 0,0).
  /// [pxPerUnit] : pixels par unité (épaisseur des contours) ; [lod] 0..2 ; [flash] 0..1 (blanc).
  void render(ui.Canvas canvas, WarriorPalette pal, {required double pxPerUnit, int lod = 2, double flash = 0}) {
    final cs = _colors(pal);
    final outer = math.max(0.11, 2.6 / pxPerUnit);
    final inner = math.max(0.03, 0.9 / pxPerUnit);
    final inkC = pal.id == 4 ? _stoneInk : ink;

    // Passe 1 : silhouette épaisse (un trait par os + chaînes), sous tout le reste.
    _stroke
      ..color = inkC
      ..strokeWidth = outer;
    final sil = def.silhouettes;
    for (var b = 0; b < sil.length; b++) {
      final p = sil[b];
      if (p == null) continue;
      _push(canvas, b);
      canvas.drawPath(p, _stroke);
      canvas.restore();
    }
    for (final c in chains) {
      canvas.drawPath(c.path, _stroke);
    }

    // Passe 2 : remplissages par profondeur, ombre cel 2 tons, liseré, traits intérieurs.
    _stroke.strokeWidth = inner;
    var cur = -1;
    var ci = 0;
    final parts = def.parts;
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      while (ci < chains.length && chains[ci].def.z <= p.z) {
        if (cur != -1) {
          canvas.restore();
          cur = -1;
        }
        _drawChain(canvas, chains[ci], cs.chainFill[_chainColor[ci]], flash, inkC);
        ci++;
      }
      if (lod < p.lodMin || lod > p.lodMax) continue;
      if (p.bone != cur) {
        if (cur != -1) canvas.restore();
        _push(canvas, p.bone);
        cur = p.bone;
      }
      final g = lod >= 1 && flash <= 0 ? cs.grad[i] : null;
      _fill.color = flash > 0 ? ui.Color.lerp(cs.fill[i], const ui.Color(0xFFFFFFFF), flash)! : cs.fill[i];
      if (g != null) _fill.shader = g;
      canvas.drawPath(p.path, _fill);
      if (g != null) _fill.shader = null;
      if (lod >= 1 && p.shadePath != null && flash < 0.5) {
        _fill.color = cs.shade[i];
        canvas.drawPath(p.shadePath!, _fill);
      }
      if (lod >= 2 && p.rimPath != null) {
        _fill.color = cs.rim[i];
        canvas.drawPath(p.rimPath!, _fill);
      }
      if (lod >= 1 && p.outline) {
        _stroke.color = inkC;
        canvas.drawPath(p.path, _stroke);
      }
    }
    if (cur != -1) canvas.restore();
    while (ci < chains.length) {
      _drawChain(canvas, chains[ci], cs.chainFill[_chainColor[ci]], flash, inkC);
      ci++;
    }
  }

  void _drawChain(ui.Canvas canvas, SpringChain c, ui.Color color, double flash, ui.Color inkC) {
    _fill.color = flash > 0 ? ui.Color.lerp(color, const ui.Color(0xFFFFFFFF), flash)! : color;
    canvas.drawPath(c.path, _fill);
    _stroke.color = inkC;
    canvas.drawPath(c.path, _stroke);
  }
}
