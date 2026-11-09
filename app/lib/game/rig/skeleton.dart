import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'anim.dart';

/// Indices des os communs à tous les guerriers (parent toujours avant l'enfant).
class B {
  static const root = 0,
      pelvis = 1,
      torso = 2,
      head = 3,
      eyes = 4,
      armBackU = 5,
      armBackL = 6,
      armFrontU = 7,
      armFrontL = 8,
      legBackU = 9,
      legBackL = 10,
      legFrontU = 11,
      legFrontL = 12,
      prop = 13;
  static const count = 14;
  static const names = [
    'root', 'pelvis', 'torso', 'head', 'eyes', 'armBackU', 'armBackL', 'armFrontU',
    'armFrontL', 'legBackU', 'legBackL', 'legFrontU', 'legFrontL', 'prop',
  ];
}

/// Hiérarchie d'os 2D. Repère « art » : pieds en y = 0, le haut vers y < 0, face vers +x.
/// Transformations mondiales en affine 2x3 (a b c d e f), recalculées sans allocation.
class Skeleton {
  Skeleton({required List<int> parents, required List<double> rest})
      : parent = Int32List.fromList(parents),
        restX = Float32List(parents.length),
        restY = Float32List(parents.length),
        restRot = Float32List(parents.length),
        world = Float64List(parents.length * 6) {
    for (var i = 0; i < parents.length; i++) {
      assert(parents[i] < i);
      restX[i] = rest[i * 3];
      restY[i] = rest[i * 3 + 1];
      restRot[i] = rest[i * 3 + 2];
    }
  }

  final Int32List parent;
  final Float32List restX, restY, restRot;
  final Float64List world;
  int get length => parent.length;

  void solve(Pose pose) {
    final v = pose.v;
    for (var i = 0; i < parent.length; i++) {
      final o = i * Ch.count;
      final rot = restRot[i] + v[o];
      final sx = v[o + 3], sy = v[o + 4];
      final cs = math.cos(rot), sn = math.sin(rot);
      final la = cs * sx, lb = sn * sx, lc = -sn * sy, ld = cs * sy;
      final le = restX[i] + v[o + 1], lf = restY[i] + v[o + 2];
      final w = i * 6;
      final p = parent[i];
      if (p < 0) {
        world[w] = la;
        world[w + 1] = lb;
        world[w + 2] = lc;
        world[w + 3] = ld;
        world[w + 4] = le;
        world[w + 5] = lf;
      } else {
        final q = p * 6;
        final pa = world[q], pb = world[q + 1], pc = world[q + 2], pd = world[q + 3];
        world[w] = pa * la + pc * lb;
        world[w + 1] = pb * la + pd * lb;
        world[w + 2] = pa * lc + pc * ld;
        world[w + 3] = pb * lc + pd * ld;
        world[w + 4] = pa * le + pc * lf + world[q + 4];
        world[w + 5] = pb * le + pd * lf + world[q + 5];
      }
    }
  }

  double worldX(int bone, double x, double y) {
    final w = bone * 6;
    return world[w] * x + world[w + 2] * y + world[w + 4];
  }

  double worldY(int bone, double x, double y) {
    final w = bone * 6;
    return world[w + 1] * x + world[w + 3] * y + world[w + 5];
  }

  /// Angle mondial de l'axe local +y de l'os (direction « vers le bas » au repos).
  double worldAngle(int bone) {
    final w = bone * 6;
    return math.atan2(world[w + 3], world[w + 2]);
  }

  /// Remplit [m4] (Matrix4 colonne-major, 16 valeurs) avec la transformation de l'os.
  void matrix4(int bone, Float64List m4) {
    final w = bone * 6;
    m4[0] = world[w];
    m4[1] = world[w + 1];
    m4[4] = world[w + 2];
    m4[5] = world[w + 3];
    m4[12] = world[w + 4];
    m4[13] = world[w + 5];
  }

  static Float64List identity4() => Float64List(16)
    ..[0] = 1
    ..[5] = 1
    ..[10] = 1
    ..[15] = 1;
}

/// Description d'une chaîne souple (cheveux, barbe, écharpe, bandeau).
class ChainDef {
  const ChainDef({
    required this.bone,
    required this.ax,
    required this.ay,
    required this.segments,
    required this.segLen,
    required this.angle,
    this.curl = 0,
    this.stiffness = 0.25,
    this.damping = 0.9,
    this.gravity = 6,
    this.wind = 0.6,
    required this.widths,
    required this.role,
    this.z = 0,
    this.tipRound = true,
  });

  /// Os d'ancrage et point d'ancrage dans son repère.
  final int bone;
  final double ax, ay;
  final int segments;
  final double segLen;

  /// Direction de repos (radians, relative à l'axe +y de l'os) et courbure par segment.
  final double angle;
  final double curl;
  final double stiffness;
  final double damping;
  final double gravity;
  final double wind;

  /// Largeurs aux points 0..segments.
  final List<double> widths;
  final int role;
  final int z;
  final bool tipRound;
}

/// Chaîne de segments simulée par intégration de Verlet + contraintes de longueur,
/// rappelée vers sa forme de repos (ressort) : réagit aux mouvements du corps.
class SpringChain {
  SpringChain(this.def)
      : x = Float32List(def.segments + 1),
        y = Float32List(def.segments + 1),
        ox = Float32List(def.segments + 1),
        oy = Float32List(def.segments + 1),
        _lx = Float32List(def.segments + 1),
        _ly = Float32List(def.segments + 1),
        _rx = Float32List(def.segments + 1),
        _ry = Float32List(def.segments + 1);

  final ChainDef def;
  final Float32List x, y, ox, oy;
  final Float32List _lx, _ly, _rx, _ry;
  final ui.Path path = ui.Path();
  bool _init = false;
  double _acc = 0;
  static const _step = 1 / 60;

  void _anchor(Skeleton sk, List<double> out) {
    out[0] = sk.worldX(def.bone, def.ax, def.ay);
    out[1] = sk.worldY(def.bone, def.ax, def.ay);
    out[2] = sk.worldAngle(def.bone);
  }

  final List<double> _a = [0, 0, 0];

  void reset(Skeleton sk) {
    _anchor(sk, _a);
    var px = _a[0], py = _a[1];
    var ang = _a[2] + def.angle;
    for (var i = 0; i <= def.segments; i++) {
      if (i > 0) {
        px += math.cos(ang) * def.segLen;
        py += math.sin(ang) * def.segLen;
        ang += def.curl;
      }
      x[i] = px;
      y[i] = py;
      ox[i] = px;
      oy[i] = py;
    }
    _init = true;
  }

  /// Décale toute la chaîne (déplacement de la pièce à l'écran, en unités d'art).
  void shift(double dx, double dy) {
    if (!_init) return;
    for (var i = 1; i <= def.segments; i++) {
      x[i] += dx;
      y[i] += dy;
      ox[i] += dx;
      oy[i] += dy;
    }
  }

  void update(Skeleton sk, double dt, double time) {
    if (!_init) {
      reset(sk);
      return;
    }
    _acc = math.min(_acc + dt, _step * 4);
    while (_acc >= _step) {
      _acc -= _step;
      _substep(sk, time);
    }
  }

  void _substep(Skeleton sk, double time) {
    _anchor(sk, _a);
    x[0] = _a[0];
    y[0] = _a[1];
    ox[0] = _a[0];
    oy[0] = _a[1];
    const h2 = _step * _step;
    final windX = (math.sin(time * 1.7) * 0.5 + math.sin(time * 4.3) * 0.25) * def.wind;
    var ang = _a[2] + def.angle;
    for (var i = 1; i <= def.segments; i++) {
      final vx = (x[i] - ox[i]) * def.damping;
      final vy = (y[i] - oy[i]) * def.damping;
      ox[i] = x[i];
      oy[i] = y[i];
      // Forme de repos relative au point précédent (ressort angulaire).
      final tx = x[i - 1] + math.cos(ang) * def.segLen;
      final ty = y[i - 1] + math.sin(ang) * def.segLen;
      ang += def.curl;
      final k = def.stiffness;
      x[i] += vx + (tx - x[i]) * k + windX * h2 * i;
      y[i] += vy + (ty - y[i]) * k + def.gravity * h2;
    }
    // Contraintes de longueur (2 passes).
    for (var it = 0; it < 2; it++) {
      for (var i = 1; i <= def.segments; i++) {
        final dx = x[i] - x[i - 1], dy = y[i] - y[i - 1];
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < 1e-6) continue;
        final f = def.segLen / d;
        x[i] = x[i - 1] + dx * f;
        y[i] = y[i - 1] + dy * f;
      }
    }
  }

  /// Construit le ruban (largeur variable) dans [path], réutilisé à chaque image.
  ui.Path buildPath() {
    final n = def.segments;
    for (var i = 0; i <= n; i++) {
      final a = i == 0 ? 0 : i - 1;
      final b = i == 0 ? 1 : i;
      var dx = x[b] - x[a], dy = y[b] - y[a];
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < 1e-6) {
        dx = 0;
        dy = 1;
      } else {
        dx /= d;
        dy /= d;
      }
      final w = def.widths[i] * 0.5;
      _lx[i] = x[i] - dy * w;
      _ly[i] = y[i] + dx * w;
      _rx[i] = x[i] + dy * w;
      _ry[i] = y[i] - dx * w;
    }
    path.reset();
    path.moveTo(_lx[0], _ly[0]);
    for (var i = 1; i < n; i++) {
      path.quadraticBezierTo(_lx[i], _ly[i], (_lx[i] + _lx[i + 1]) / 2, (_ly[i] + _ly[i + 1]) / 2);
    }
    path.lineTo(_lx[n], _ly[n]);
    if (def.tipRound) {
      final ex = x[n] + (x[n] - x[n - 1]) * 0.6, ey = y[n] + (y[n] - y[n - 1]) * 0.6;
      path.quadraticBezierTo(ex, ey, _rx[n], _ry[n]);
    } else {
      path.lineTo(_rx[n], _ry[n]);
    }
    for (var i = n - 1; i > 0; i--) {
      path.quadraticBezierTo(_rx[i], _ry[i], (_rx[i] + _rx[i - 1]) / 2, (_ry[i] + _ry[i - 1]) / 2);
    }
    path.lineTo(_rx[0], _ry[0]);
    path.close();
    return path;
  }

  bool get valid {
    for (var i = 0; i <= def.segments; i++) {
      if (!x[i].isFinite || !y[i].isFinite) return false;
    }
    return true;
  }
}
