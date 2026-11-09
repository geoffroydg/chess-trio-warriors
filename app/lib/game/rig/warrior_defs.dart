import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../models/protocol.dart';
import '../warrior_art.dart';
import 'anim.dart';
import 'skeleton.dart';

// ---------------------------------------------------------------------------
// Géométrie vectorielle (construite une seule fois par type, puis réutilisée :
// seules les matrices des os changent à chaque image).
// ---------------------------------------------------------------------------

/// Morceau de dessin rigide attaché à un os (repère local de l'os).
class RigPart {
  RigPart(this.bone, this.path,
      {this.role = -1,
      this.color,
      this.z = 0,
      this.outline = true,
      this.shade = true,
      this.rim = false,
      this.grad = false,
      this.lodMin = 0,
      this.lodMax = 2}) {
    final b = path.getBounds();
    final d = math.max(0.03, math.min(b.width, b.height) * 0.2);
    // Cel-shading : croissant d'ombre en bas à droite, liseré de lumière à droite.
    if (shade) {
      shadePath = ui.Path.combine(ui.PathOperation.difference, path, path.shift(ui.Offset(-d, -d)));
    }
    if (rim) {
      final r = math.max(0.025, math.min(b.width, b.height) * 0.09);
      rimPath = ui.Path.combine(ui.PathOperation.difference, path, path.shift(ui.Offset(-r, r * 0.4)));
    }
    bounds = b;
  }

  final int bone;
  final ui.Path path;
  final int role;
  final ui.Color? color;
  final int z;
  final bool outline;
  final bool shade;
  final bool rim;
  final bool grad;
  final int lodMin;
  final int lodMax;
  ui.Path? shadePath;
  ui.Path? rimPath;
  late final ui.Rect bounds;
}

/// Proportions d'un guerrier (unités d'art).
class _Spec {
  const _Spec({
    required this.thigh,
    required this.shin,
    this.foot = 0.1,
    required this.torso,
    required this.neck,
    required this.headR,
    required this.shX,
    required this.hipX,
    required this.armU,
    required this.armL,
    required this.legR,
    required this.armR,
    required this.fistR,
    required this.topW,
    required this.botW,
  });
  final double thigh, shin, foot, torso, neck, headR, shX, hipX, armU, armL;
  final double legR, armR, fistR, topW, botW;
  double get hipY => thigh + shin + foot;
}

const ink = ui.Color(0xFF14101E);
const _white = ui.Color(0xFFF7F3EA);
const _hairBrown = ui.Color(0xFF3A2216);
const _hairRed = ui.Color(0xFF7A2A18);
const _boot = ui.Color(0xFF3B2A28);
const _wood = ui.Color(0xFF6B4A2B);

ui.Path _poly(List<double> p) {
  final path = ui.Path()..moveTo(p[0], p[1]);
  for (var i = 2; i < p.length; i += 2) {
    path.lineTo(p[i], p[i + 1]);
  }
  return path..close();
}

/// Courbe fermée lissée passant près des points (milieux + quadratiques).
ui.Path _smooth(List<double> p) {
  final n = p.length ~/ 2;
  double px(int i) => p[(i % n) * 2];
  double py(int i) => p[(i % n) * 2 + 1];
  final path = ui.Path()..moveTo((px(n - 1) + px(0)) / 2, (py(n - 1) + py(0)) / 2);
  for (var i = 0; i < n; i++) {
    path.quadraticBezierTo(px(i), py(i), (px(i) + px(i + 1)) / 2, (py(i) + py(i + 1)) / 2);
  }
  return path..close();
}

ui.Path _oval(double cx, double cy, double rx, double ry) =>
    ui.Path()..addOval(ui.Rect.fromCenter(center: ui.Offset(cx, cy), width: rx * 2, height: ry * 2));

ui.Path _rr(double l, double t, double r, double b, [double rad = 0.04]) =>
    ui.Path()..addRRect(ui.RRect.fromLTRBR(l, t, r, b, ui.Radius.circular(rad)));

/// Membre fuselé le long de +y (articulation en 0, extrémité en [len]), bouts arrondis.
ui.Path _limb(double len, double r0, double r1, {double bulge = 1.06}) {
  final p = ui.Path()..moveTo(-r0, 0);
  p.arcToPoint(ui.Offset(r0, 0), radius: ui.Radius.circular(r0));
  p.cubicTo(r0 * bulge, len * 0.35, r1 * bulge, len * 0.72, r1, len);
  p.arcToPoint(ui.Offset(-r1, len), radius: ui.Radius.circular(r1));
  p.cubicTo(-r1 * bulge, len * 0.72, -r0 * bulge, len * 0.35, -r0, 0);
  return p..close();
}

/// Définition complète d'un guerrier : squelette, dessin, chaînes et clips.
class RigDef {
  RigDef({
    required this.type,
    required this.parents,
    required this.rest,
    required List<RigPart> parts,
    required this.chains,
    required this.clips,
    required this.height,
    required this.chestY,
  }) : parts = (List.of(parts)..sort((a, b) => a.z != b.z ? a.z - b.z : a.bone - b.bone)) {
    // Silhouette par os : union des pièces à contour (un seul trait épais par os).
    silhouettes = List.generate(parents.length, (b) {
      ui.Path? u;
      for (final p in this.parts) {
        if (p.bone != b || !p.outline || p.lodMin > 0) continue;
        u = u == null ? (ui.Path()..addPath(p.path, ui.Offset.zero)) : ui.Path.combine(ui.PathOperation.union, u, p.path);
      }
      return u;
    });
  }

  final PieceType type;
  final List<int> parents;
  final List<double> rest;
  final List<RigPart> parts;
  final List<ChainDef> chains;
  final Map<AnimState, Clip> clips;
  late final List<ui.Path?> silhouettes;

  /// Hauteur totale (unités) et hauteur du torse (effets).
  final double height;
  final double chestY;

  static final Map<PieceType, RigDef> _cache = {};
  static RigDef of(PieceType t) => _cache.putIfAbsent(t, () => _build(t));
}

/// Hauteur approximative (unités d'art) de chaque guerrier.
double rigHeight(PieceType t) => RigDef.of(t).height;

// ---------------------------------------------------------------------------
// Construction.
// ---------------------------------------------------------------------------

class _Builder {
  _Builder(this.s);
  final _Spec s;
  final List<RigPart> parts = [];
  final List<ChainDef> chains = [];

  void add(int bone, ui.Path path,
          {int role = -1,
          ui.Color? color,
          int z = 0,
          bool outline = true,
          bool shade = true,
          bool rim = false,
          bool grad = false,
          int lodMin = 0,
          int lodMax = 2}) =>
      parts.add(RigPart(bone, path,
          role: role,
          color: color,
          z: z,
          outline: outline,
          shade: shade,
          rim: rim,
          grad: grad,
          lodMin: lodMin,
          lodMax: lodMax));

  List<int> get parents => [
        -1, // root
        B.root, // pelvis
        B.pelvis, // torso
        B.torso, // head
        B.head, // eyes
        B.torso, B.armBackU,
        B.torso, B.armFrontU,
        B.pelvis, B.legBackU,
        B.pelvis, B.legFrontU,
        B.armFrontL, // prop
      ];

  List<double> get rest {
    final r = s.headR;
    return [
      0, 0, 0, // root
      0, -s.hipY, 0, // pelvis
      0, 0, 0, // torso
      0, -s.torso - s.neck, 0, // head
      r * 0.2, -r * 0.92, 0, // eyes
      s.shX * 0.8, -s.torso + s.armR * 1.1, -0.16, // armBackU
      0, s.armU, -0.22, // armBackL
      -s.shX, -s.torso + s.armR * 1.1, 0.2, // armFrontU
      0, s.armU, -0.3, // armFrontL
      s.hipX, 0, -0.03, // legBackU
      0, s.thigh, 0.02, // legBackL
      -s.hipX, 0, 0.05, // legFrontU
      0, s.thigh, 0.02, // legFrontL
      0, s.armL + s.fistR * 0.5, 0, // prop
    ];
  }

  // --- Pièces communes ---

  void legs({int thighRole = Role.dark, int shinRole = Role.dark, ui.Color boot = _boot, double flare = 1}) {
    for (final back in [true, false]) {
      final u = back ? B.legBackU : B.legFrontU;
      final l = back ? B.legBackL : B.legFrontL;
      final z = back ? -40 : -30;
      add(u, _limb(s.thigh + s.legR * 0.3, s.legR, s.legR * 0.88), role: thighRole, z: z + 1, grad: true);
      add(l, _limb(s.shin, s.legR * 0.86, s.legR * 0.7 * flare), role: shinRole, z: z);
      final r = s.legR;
      // Botte (semelle à y = shin + foot -> sol).
      add(
          l,
          _smooth([
            -r * 0.85, s.shin - 0.16, r * 0.8, s.shin - 0.17, r * 0.95 + 0.06, s.shin - 0.02,
            r + 0.2, s.shin + 0.02, r + 0.24, s.shin + s.foot, -r * 0.95, s.shin + s.foot,
          ]),
          color: boot,
          z: z + 2,
          rim: true);
    }
  }

  /// Bras : manche ([sleeve] = rôle, null = peau nue), avant-bras, brassard, poing.
  void arms({int? sleeve = Role.outfit, double sleeveLen = 0.6, int forearm = Role.skin, int band = Role.accent,
      int fist = Role.skin, double fistScale = 1, bool wideSleeve = false}) {
    for (final back in [true, false]) {
      final u = back ? B.armBackU : B.armFrontU;
      final l = back ? B.armBackL : B.armFrontL;
      final z = back ? -60 : 40;
      final ar = s.armR;
      add(u, _limb(s.armU, ar, ar * 0.9), role: Role.skin, z: z);
      if (sleeve != null) {
        if (wideSleeve) {
          add(u, _limb(s.armU * 1.05, ar * 1.25, ar * 1.7, bulge: 1.15), role: sleeve, z: z + 1, grad: true, rim: !back);
        } else {
          add(u, _limb(s.armU * sleeveLen, ar * 1.15, ar * 1.12), role: sleeve, z: z + 1, grad: true, rim: !back);
        }
      }
      add(l, _limb(s.armL, ar * 0.9, ar * 0.75), role: forearm, z: z + 2);
      if (band >= 0) {
        add(l, _rr(-ar * 0.95, s.armL * 0.55, ar * 0.95, s.armL * 0.9, 0.03), role: band, z: z + 3, shade: false);
      }
      final f = s.fistR * fistScale;
      add(l, _smooth([-f, s.armL - f * 0.2, f * 0.9, s.armL - f * 0.3, f * 1.05, s.armL + f * 1.1, -f * 0.8, s.armL + f * 1.2]),
          role: fist, z: z + 4, rim: !back);
      add(l, _rr(-f * 0.2, s.armL + f * 0.15, f * 0.75, s.armL + f * 0.3, 0.02),
          color: const ui.Color(0x55000000), outline: false, shade: false, z: z + 5, lodMin: 2);
    }
  }

  /// Torse (haut en forme de V), col, ceinture.
  void torso({int role = Role.outfit, bool collar = true, int belt = Role.light, double beltH = 0.14}) {
    final t = s.torso, tw = s.topW, bw = s.botW;
    add(
        B.torso,
        _smooth([
          -bw, 0.08, bw, 0.08, bw * 1.04, -t * 0.4, tw * 1.02, -t * 0.82, tw * 0.82, -t * 1.04,
          -tw * 0.82, -t * 1.04, -tw * 1.02, -t * 0.82, -bw * 1.04, -t * 0.4,
        ]),
        role: role,
        z: 0,
        grad: true,
        rim: true);
    if (collar) {
      add(B.torso, _poly([-tw * 0.32, -t * 1.0, tw * 0.36, -t * 1.0, tw * 0.04, -t * 0.55]), role: Role.skin, z: 1, shade: false);
      add(B.torso, _poly([-tw * 0.32, -t * 1.0, -tw * 0.18, -t * 1.0, tw * 0.04, -t * 0.55, -tw * 0.02, -t * 0.5]),
          role: Role.light, z: 2, shade: false);
      add(B.torso, _poly([tw * 0.36, -t * 1.0, tw * 0.22, -t * 1.0, tw * 0.0, -t * 0.55, tw * 0.06, -t * 0.5]),
          role: Role.light, z: 2, shade: false);
    }
    if (belt >= 0) add(B.torso, _rr(-bw * 1.08, -beltH * 0.5, bw * 1.08, beltH * 0.6, 0.04), role: belt, z: 3);
  }

  void hips({int role = Role.dark}) {
    final w = s.hipX + s.legR * 1.1;
    add(B.pelvis, _smooth([-w, -0.12, w, -0.12, w * 1.06, s.legR * 1.6, 0, s.legR * 1.9, -w * 1.06, s.legR * 1.6]),
        role: role, z: -20, grad: true);
  }

  /// Robe longue jusqu'au sol (Fou, Roi) attachée au bassin.
  void robeSkirt({int role = Role.outfit, double flare = 1.0, int hem = Role.accent}) {
    final h = s.hipY - 0.16;
    final w0 = s.botW * 1.02, w1 = s.botW * 1.5 * flare;
    add(B.pelvis, _smooth([-w0, -0.12, w0, -0.12, w1 * 0.95, h * 0.6, w1, h, w1 * 0.3, h + 0.05, -w1 * 0.3, h + 0.05, -w1, h, -w0 * 1.25, h * 0.55]),
        role: role, z: -10, grad: true, rim: true);
    add(B.pelvis, _poly([-w1 * 0.98, h - 0.09, w1 * 0.98, h - 0.09, w1, h, w1 * 0.3, h + 0.05, -w1 * 0.3, h + 0.05, -w1, h]),
        role: hem, z: -9, shade: false);
  }

  /// Tête : visage 3/4 tourné vers +x, oreille, sourcils, bouche, yeux d'anime.
  void head({bool ear = true, bool mouth = true, bool brows = true, int browRole = -1, ui.Color browColor = ink,
      double browTilt = 0.08, bool eyes = true}) {
    final r = s.headR;
    add(
        B.head,
        _smooth([
          0.0, -r * 2.02, r * 0.92, -r * 1.55, r * 0.98, -r * 0.92, r * 0.62, -r * 0.18, r * 0.32, r * 0.02,
          -r * 0.42, -r * 0.16, -r * 0.92, -r * 0.7, -r * 0.98, -r * 1.42,
        ]),
        role: Role.skin,
        z: 100,
        rim: true);
    // Cou (sur le torse, sous la tête).
    add(B.torso, _rr(-r * 0.24, -s.torso - s.neck - r * 0.25, r * 0.28, -s.torso + 0.06, 0.06), role: Role.skinDark, z: 5);
    if (ear) {
      add(B.head, _oval(-r * 0.86, -r * 0.92, r * 0.16, r * 0.23), role: Role.skin, z: 99);
      add(B.head, _oval(-r * 0.88, -r * 0.9, r * 0.07, r * 0.12), role: Role.skinDark, z: 99, outline: false, shade: false, lodMin: 1);
    }
    if (mouth) {
      add(B.head, _poly([r * 0.2, -r * 0.36, r * 0.48, -r * 0.4, r * 0.46, -r * 0.34, r * 0.22, -r * 0.31]),
          color: const ui.Color(0xFF7A2E2E), z: 104, outline: false, shade: false, lodMin: 1);
      // Nez.
      add(B.head, _poly([r * 0.62, -r * 0.78, r * 0.72, -r * 0.6, r * 0.6, -r * 0.6]),
          role: Role.skinDark, z: 104, outline: false, shade: false, lodMin: 1);
    }
    if (brows) {
      final c = browRole >= 0 ? null : browColor;
      final t = browTilt * r;
      add(B.head, _poly([-r * 0.32, -r * 1.27 - t, r * 0.08, -r * 1.2 + t, r * 0.06, -r * 1.12 + t, -r * 0.3, -r * 1.16 - t]),
          role: browRole, color: c, z: 106, outline: false, shade: false);
      add(B.head, _poly([r * 0.34, -r * 1.2 + t, r * 0.74, -r * 1.27 - t, r * 0.74, -r * 1.18 - t, r * 0.36, -r * 1.12 + t]),
          role: browRole, color: c, z: 106, outline: false, shade: false);
    }
    if (eyes) animeEyes();
  }

  /// Yeux (os « eyes », mis à l'échelle verticalement pour cligner).
  void animeEyes({int iris = Role.dark, double size = 1}) {
    final r = s.headR * size;
    for (final far in [false, true]) {
      final cx = far ? r * 0.34 : -r * 0.3;
      final w = far ? r * 0.17 : r * 0.21;
      final h = r * 0.25;
      // LOD bas : simple trait sombre.
      add(B.eyes, _oval(cx + w * 0.15, 0, w * 0.6, h * 0.8), color: ink, z: 103, outline: false, shade: false, lodMax: 0);
      add(B.eyes, _smooth([cx - w, -h * 0.55, cx + w, -h * 0.75, cx + w * 1.05, h * 0.5, cx, h * 1.05, cx - w * 0.95, h * 0.55]),
          color: _white, z: 103, outline: false, shade: false, lodMin: 1);
      add(B.eyes, _oval(cx + w * 0.22, h * 0.12, w * 0.62, h * 0.82), role: iris, z: 104, outline: false, shade: false, lodMin: 1);
      add(B.eyes, _oval(cx + w * 0.3, h * 0.18, w * 0.32, h * 0.45), color: ink, z: 105, outline: false, shade: false, lodMin: 1);
      add(B.eyes, _oval(cx + w * 0.0, -h * 0.18, w * 0.2, h * 0.22), color: const ui.Color(0xFFFFFFFF), z: 106,
          outline: false, shade: false, lodMin: 1);
      // Cils supérieurs épais.
      add(B.eyes, _poly([cx - w * 1.15, -h * 0.4, cx + w * 1.1, -h * 0.95, cx + w * 1.2, -h * 0.55, cx - w * 1.0, -h * 0.25]),
          color: ink, z: 107, outline: false, shade: false, lodMin: 1);
    }
  }

  ChainDef chain(int bone, double ax, double ay,
          {required int segments,
          required double segLen,
          required double angle,
          double curl = 0,
          double stiffness = 0.22,
          double damping = 0.9,
          double gravity = 6,
          double wind = 0.6,
          required double w0,
          required double w1,
          int role = -1,
          int z = -100,
          bool tipRound = true}) =>
      ChainDef(
          bone: bone,
          ax: ax,
          ay: ay,
          segments: segments,
          segLen: segLen,
          angle: angle,
          curl: curl,
          stiffness: stiffness,
          damping: damping,
          gravity: gravity,
          wind: wind,
          widths: [for (var i = 0; i <= segments; i++) w0 + (w1 - w0) * i / segments],
          role: role,
          z: z,
          tipRound: tipRound);
}

/// Rôle « couleur fixe » des chaînes : index dans [chainColors].
const chainColors = <ui.Color>[_hairBrown, _white, _hairRed];
int fixedChainRole(int i) => -10 - i;

RigDef _build(PieceType t) => switch (t) {
      PieceType.pawn => _pawn(),
      PieceType.rook => _rook(),
      PieceType.bishop => _bishop(),
      PieceType.knight => _knight(),
      PieceType.queen => _queen(),
      PieceType.king => _king(),
    };

RigDef _finish(PieceType t, _Builder b, {required double height, required _ClipStyle style}) => RigDef(
      type: t,
      parents: b.parents,
      rest: b.rest,
      parts: b.parts,
      chains: b.chains,
      clips: _clips(t, b.s, style),
      height: height,
      chestY: -(b.s.hipY + b.s.torso * 0.6),
    );

// --- Pion : jeune combattant, cheveux en pointes, bandeau à pans flottants ---
RigDef _pawn() {
  const s = _Spec(
      thigh: 0.36, shin: 0.34, torso: 0.6, neck: 0.04, headR: 0.44, shX: 0.31, hipX: 0.14,
      armU: 0.34, armL: 0.32, legR: 0.13, armR: 0.1, fistR: 0.12, topW: 0.37, botW: 0.27);
  final b = _Builder(s);
  b.legs();
  b.hips();
  b.torso();
  b.arms(sleeveLen: 0.55, band: Role.light);
  b.head();
  final r = s.headR;
  // Cheveux courts en pointes.
  b.add(
      B.head,
      _poly([
        -r * 1.02, -r * 0.95, -r * 1.25, -r * 1.35, -r * 0.92, -r * 1.48, -r * 1.12, -r * 1.95,
        -r * 0.55, -r * 1.85, -r * 0.5, -r * 2.38, -r * 0.05, -r * 2.05, r * 0.25, -r * 2.42,
        r * 0.5, -r * 2.0, r * 0.98, -r * 2.15, r * 0.95, -r * 1.68, r * 1.25, -r * 1.55,
        r * 0.98, -r * 1.35, r * 0.5, -r * 1.5, r * 0.2, -r * 1.36, -r * 0.2, -r * 1.5,
        -r * 0.6, -r * 1.3, -r * 0.75, -r * 0.95,
      ]),
      color: _hairBrown,
      z: 110,
      rim: true);
  // Bandeau.
  b.add(B.head, _smooth([-r * 1.0, -r * 1.42, r * 0.98, -r * 1.48, r * 0.98, -r * 1.3, -r * 1.0, -r * 1.24]),
      role: Role.light, z: 111);
  b.add(B.head, _oval(r * 0.4, -r * 1.37, r * 0.1, r * 0.09), role: Role.accent, z: 112, lodMin: 1);
  b.chains.add(b.chain(B.head, -r * 0.95, -r * 1.33,
      segments: 5, segLen: 0.13, angle: 1.0, curl: 0.05, stiffness: 0.12, w0: 0.11, w1: 0.07, role: Role.light, z: 99,
      tipRound: false));
  b.chains.add(b.chain(B.head, -r * 0.95, -r * 1.3,
      segments: 4, segLen: 0.13, angle: 0.55, curl: 0.08, stiffness: 0.14, w0: 0.1, w1: 0.06, role: Role.light, z: 98,
      tipRound: false));
  return _finish(PieceType.pawn, b, height: 2.45, style: const _ClipStyle(guard: 0.6));
}

// --- Tour : colosse en armure, casque crénelé, gantelets massifs ---
RigDef _rook() {
  const s = _Spec(
      thigh: 0.36, shin: 0.34, foot: 0.12, torso: 0.95, neck: 0.0, headR: 0.36, shX: 0.64, hipX: 0.24,
      armU: 0.48, armL: 0.44, legR: 0.2, armR: 0.17, fistR: 0.21, topW: 0.74, botW: 0.5);
  final b = _Builder(s);
  b.legs(thighRole: Role.dark, shinRole: Role.outfit);
  b.hips();
  b.torso(collar: false, belt: Role.dark, beltH: 0.2);
  final t = s.torso, tw = s.topW;
  // Plastron.
  b.add(B.torso, _smooth([-tw * 0.7, -t * 0.92, tw * 0.7, -t * 0.92, tw * 0.6, -t * 0.42, 0, -t * 0.3, -tw * 0.6, -t * 0.42]),
      role: Role.accent, z: 2, rim: true);
  b.add(B.torso, _poly([0, -t * 0.82, tw * 0.13, -t * 0.66, 0, -t * 0.5, -tw * 0.13, -t * 0.66]), role: Role.outfit, z: 3);
  b.arms(sleeve: null, forearm: Role.skin, band: Role.dark, fist: Role.dark, fistScale: 1.15);
  // Spalières (épaulières) sur les bras.
  for (final back in [true, false]) {
    b.add(back ? B.armBackU : B.armFrontU,
        _smooth([-0.3, -0.12, 0.0, -0.26, 0.3, -0.12, 0.32, 0.14, 0, 0.22, -0.32, 0.14]),
        role: Role.accent, z: back ? -55 : 46, rim: !back);
    b.add(back ? B.armBackU : B.armFrontU, _rr(-0.28, 0.06, 0.28, 0.13, 0.03), role: Role.dark, z: back ? -54 : 47, shade: false);
  }
  final r = s.headR;
  b.head(ear: false, mouth: false, brows: false, eyes: false);
  // Casque crénelé + visière.
  b.add(
      B.head,
      _poly([
        -r * 1.08, -r * 0.35, -r * 1.12, -r * 2.05, -r * 0.75, -r * 2.05, -r * 0.75, -r * 2.45,
        -r * 0.32, -r * 2.45, -r * 0.32, -r * 2.15, r * 0.12, -r * 2.15, r * 0.12, -r * 2.45,
        r * 0.55, -r * 2.45, r * 0.55, -r * 2.05, r * 1.1, -r * 2.05, r * 1.06, -r * 0.35,
        r * 0.55, -r * 0.18, -r * 0.2, -r * 0.18,
      ]),
      role: Role.dark,
      z: 110,
      rim: true);
  b.add(B.head, _rr(-r * 0.75, -r * 1.25, r * 1.0, -r * 0.85, 0.05), color: ink, z: 111, outline: false, shade: false);
  b.add(B.eyes, _rr(-r * 0.45, -r * 0.1, -r * 0.05, r * 0.08, 0.03), color: const ui.Color(0xFFFFFFFF), z: 112,
      outline: false, shade: false);
  b.add(B.eyes, _rr(r * 0.2, -r * 0.1, r * 0.55, r * 0.08, 0.03), color: const ui.Color(0xFFFFFFFF), z: 112,
      outline: false, shade: false);
  b.add(B.head, _rr(-r * 1.12, -r * 1.75, r * 1.1, -r * 1.58, 0.03), role: Role.accent, z: 113, shade: false);
  b.add(B.head, _poly([r * 0.0, -r * 1.55, r * 0.22, -r * 1.3, 0, -r * 1.3]), role: Role.accent, z: 113, lodMin: 1);
  return _finish(PieceType.rook, b, height: 2.75, style: const _ClipStyle(heavy: true));
}

// --- Fou : mystique encapuchonné, bâton à orbe, étole flottante ---
RigDef _bishop() {
  const s = _Spec(
      thigh: 0.46, shin: 0.46, torso: 0.82, neck: 0.04, headR: 0.36, shX: 0.33, hipX: 0.13,
      armU: 0.44, armL: 0.4, legR: 0.12, armR: 0.11, fistR: 0.11, topW: 0.4, botW: 0.32);
  final b = _Builder(s);
  b.legs();
  b.robeSkirt(flare: 1.15, hem: Role.light);
  b.torso(collar: false, belt: Role.accent);
  final t = s.torso, tw = s.topW;
  // Étole.
  b.add(B.torso, _poly([-tw * 0.42, -t * 1.0, -tw * 0.15, -t * 1.0, -tw * 0.08, t * 0.1, -tw * 0.35, t * 0.1]),
      role: Role.light, z: 4, shade: false);
  b.add(B.torso, _poly([tw * 0.42, -t * 1.0, tw * 0.15, -t * 1.0, tw * 0.1, t * 0.1, tw * 0.37, t * 0.1]),
      role: Role.light, z: 4, shade: false);
  b.arms(sleeve: Role.outfit, wideSleeve: true, band: -1);
  // Bâton (os « prop » dans la main avant) + orbe.
  b.add(B.prop, _rr(-0.045, -1.75, 0.045, 1.05, 0.04), color: _wood, z: 38, rim: true);
  b.add(B.prop, _smooth([-0.16, -1.78, 0.0, -2.12, 0.16, -1.78, 0.0, -1.64]), role: Role.accent, z: 39);
  b.add(B.prop, _oval(0, -2.02, 0.14, 0.14), role: Role.aura, z: 39, outline: false, shade: false);
  b.add(B.prop, _oval(-0.04, -2.06, 0.05, 0.05), color: const ui.Color(0xFFFFFFFF), z: 39, outline: false, shade: false);
  final r = s.headR;
  b.head(ear: false, mouth: false, brows: false, eyes: false);
  // Capuche pointue.
  b.add(
      B.head,
      _smooth([
        -r * 1.25, r * 0.15, -r * 1.3, -r * 1.3, -r * 1.0, -r * 2.2, -r * 0.6, -r * 2.75, -r * 0.9, -r * 3.35,
        r * 0.1, -r * 2.75, r * 1.05, -r * 2.05, r * 1.25, -r * 1.2, r * 1.2, r * 0.15,
      ]),
      role: Role.dark,
      z: 95,
      rim: true);
  // Ombre du visage + yeux brillants.
  b.add(B.head, _smooth([-r * 0.65, -r * 1.52, r * 0.95, -r * 1.55, r * 0.98, -r * 1.05, -r * 0.62, -r * 1.0]),
      color: const ui.Color(0x66201030), z: 108, outline: false, shade: false);
  b.add(B.eyes, _rr(-r * 0.42, -r * 0.05, -r * 0.1, r * 0.08, 0.03), role: Role.accent, z: 112, outline: false, shade: false);
  b.add(B.eyes, _rr(r * 0.22, -r * 0.05, r * 0.5, r * 0.08, 0.03), role: Role.accent, z: 112, outline: false, shade: false);
  // Barbe courte.
  b.add(B.head, _smooth([-r * 0.3, -r * 0.42, r * 0.85, -r * 0.5, r * 0.55, r * 0.35, r * 0.2, r * 0.55]),
      color: const ui.Color(0xFFD9D4CC), z: 109);
  // Bord de la capuche (par-dessus le visage).
  b.add(B.head, _smooth([-r * 1.1, -r * 1.6, -r * 0.6, -r * 2.1, r * 0.2, -r * 2.25, r * 1.05, -r * 1.85, r * 0.95, -r * 1.6, r * 0.1, -r * 1.85, -r * 0.6, -r * 1.75]),
      role: Role.dark, z: 113);
  b.chains.add(b.chain(B.torso, s.botW * 0.3, 0.05,
      segments: 5, segLen: 0.16, angle: -0.05, stiffness: 0.2, w0: 0.13, w1: 0.1, role: Role.accent, z: 5, tipRound: false));
  return _finish(PieceType.bishop, b, height: 3.25, style: const _ClipStyle(staff: true));
}

// --- Cavalier : combattant aérien, cheveux en flammes, longue écharpe ---
RigDef _knight() {
  const s = _Spec(
      thigh: 0.44, shin: 0.42, torso: 0.66, neck: 0.05, headR: 0.4, shX: 0.33, hipX: 0.14,
      armU: 0.4, armL: 0.36, legR: 0.13, armR: 0.1, fistR: 0.11, topW: 0.38, botW: 0.25);
  final b = _Builder(s);
  b.legs(thighRole: Role.outfit, shinRole: Role.outfit);
  b.hips(role: Role.outfit);
  b.torso(collar: false, belt: Role.dark);
  final t = s.torso, tw = s.topW;
  b.add(B.torso, _poly([-tw * 0.06, -t * 1.0, tw * 0.06, -t * 1.0, tw * 0.05, 0, -tw * 0.05, 0]), role: Role.accent, z: 2, shade: false);
  b.add(B.torso, _smooth([-tw * 0.95, -t * 0.98, tw * 0.95, -t * 0.98, tw * 0.6, -t * 0.72, -tw * 0.6, -t * 0.72]),
      role: Role.dark, z: 3);
  b.arms(sleeve: null, band: Role.accent, fist: Role.dark);
  b.head(browTilt: 0.14);
  final r = s.headR;
  // Cheveux en flammes rejetés vers l'arrière.
  b.add(
      B.head,
      _poly([
        -r * 0.95, -r * 0.85, -r * 1.55, -r * 1.1, -r * 1.1, -r * 1.45, -r * 1.75, -r * 1.85, -r * 1.05, -r * 1.85,
        -r * 1.45, -r * 2.5, -r * 0.55, -r * 2.1, -r * 0.45, -r * 2.75, r * 0.05, -r * 2.15, r * 0.45, -r * 2.55,
        r * 0.55, -r * 1.95, r * 1.1, -r * 2.0, r * 0.95, -r * 1.6, r * 1.2, -r * 1.35, r * 0.6, -r * 1.42,
        r * 0.3, -r * 1.3, -r * 0.1, -r * 1.48, -r * 0.6, -r * 1.25, -r * 0.7, -r * 0.92,
      ]),
      color: _hairRed,
      z: 110,
      rim: true);
  b.chains.add(b.chain(B.torso, -0.05, -s.torso + 0.02,
      segments: 8, segLen: 0.19, angle: 1.35, curl: 0.03, stiffness: 0.08, damping: 0.92, gravity: 3, wind: 1.2,
      w0: 0.2, w1: 0.13, role: Role.light, z: -100, tipRound: false));
  b.add(B.torso, _smooth([-tw * 0.75, -t * 1.05, tw * 0.8, -t * 1.05, tw * 0.75, -t * 0.88, -tw * 0.7, -t * 0.88]),
      role: Role.light, z: 6);
  return _finish(PieceType.knight, b, height: 2.75, style: const _ClipStyle(guard: 1.0, bouncy: true));
}

// --- Dame : combattante élégante, longue queue de cheval, brassards ---
RigDef _queen() {
  const s = _Spec(
      thigh: 0.5, shin: 0.46, torso: 0.7, neck: 0.07, headR: 0.38, shX: 0.3, hipX: 0.13,
      armU: 0.4, armL: 0.38, legR: 0.12, armR: 0.085, fistR: 0.095, topW: 0.33, botW: 0.22);
  final b = _Builder(s);
  b.legs(thighRole: Role.dark, shinRole: Role.dark, flare: 1.35);
  b.hips();
  b.torso(collar: false, belt: Role.accent);
  final t = s.torso, tw = s.topW;
  b.add(B.torso, _smooth([-tw * 0.6, -t * 0.95, tw * 0.6, -t * 0.95, tw * 0.45, -t * 0.35, 0, -t * 0.25, -tw * 0.45, -t * 0.35]),
      role: Role.light, z: 2);
  b.add(B.torso, _oval(0, -t * 0.82, 0.06, 0.06), role: Role.accent, z: 3, lodMin: 1);
  b.arms(sleeve: Role.outfit, sleeveLen: 0.35, forearm: Role.skin, band: Role.accent);
  b.head(browTilt: 0.05);
  final r = s.headR;
  // Chevelure (couleur du camp) + frange.
  b.add(
      B.head,
      _smooth([
        -r * 1.05, -r * 0.5, -r * 1.12, -r * 1.5, -r * 0.7, -r * 2.12, r * 0.2, -r * 2.2, r * 0.95, -r * 1.85,
        r * 1.08, -r * 1.25, r * 0.85, -r * 1.42, r * 0.55, -r * 1.2, r * 0.4, -r * 1.5, -r * 0.1, -r * 1.3,
        -r * 0.5, -r * 1.45, -r * 0.7, -r * 1.0,
      ]),
      role: Role.light,
      z: 110,
      rim: true);
  b.add(B.head, _rr(-r * 0.55, -r * 2.12, r * 0.55, -r * 1.98, 0.04), role: Role.accent, z: 111, lodMin: 1);
  b.add(B.head, _oval(-r * 0.62, -r * 0.55, r * 0.07, r * 0.09), role: Role.accent, z: 112, lodMin: 1);
  b.chains.add(b.chain(B.head, -r * 0.8, -r * 1.75,
      segments: 7, segLen: 0.17, angle: 1.25, curl: -0.08, stiffness: 0.1, w0: 0.3, w1: 0.06, role: Role.light, z: -100));
  return _finish(PieceType.queen, b, height: 2.85, style: const _ClipStyle(elegant: true));
}

// --- Roi : vieux maître, robe à mantelet, longue barbe blanche, chignon ---
RigDef _king() {
  const s = _Spec(
      thigh: 0.4, shin: 0.38, torso: 0.92, neck: 0.03, headR: 0.42, shX: 0.52, hipX: 0.18,
      armU: 0.46, armL: 0.42, legR: 0.16, armR: 0.13, fistR: 0.14, topW: 0.6, botW: 0.52);
  final b = _Builder(s);
  b.legs();
  b.robeSkirt(flare: 1.0);
  b.torso(collar: true, belt: Role.dark, beltH: 0.18);
  final t = s.torso, tw = s.topW;
  // Mantelet sur les épaules + médaillon.
  b.add(B.torso, _smooth([-tw * 1.15, -t * 0.62, -tw * 1.0, -t * 1.06, tw * 1.0, -t * 1.06, tw * 1.15, -t * 0.62, 0, -t * 0.72]),
      role: Role.light, z: 10, rim: true);
  b.add(B.torso, _oval(0, -t * 0.62, 0.11, 0.12), role: Role.accent, z: 12);
  b.add(B.torso, _oval(0, 0.0, 0.12, 0.1), role: Role.accent, z: 12);
  b.arms(sleeve: Role.outfit, wideSleeve: true, band: -1);
  b.head(browRole: -1, browColor: _white, browTilt: -0.05);
  final r = s.headR;
  // Touffes latérales + chignon + couronne.
  b.add(B.head, _smooth([-r * 1.02, -r * 0.7, -r * 1.12, -r * 1.25, -r * 0.8, -r * 1.55, -r * 0.62, -r * 1.05]),
      color: _white, z: 109);
  b.add(B.head, _oval(r * 0.0, -r * 2.25, r * 0.32, r * 0.28), color: _white, z: 96);
  b.add(B.head, _smooth([-r * 0.92, -r * 1.62, -r * 0.6, -r * 2.25, -r * 0.25, -r * 1.95, 0, -r * 2.38, r * 0.25, -r * 1.95, r * 0.6, -r * 2.25, r * 0.92, -r * 1.62, 0, -r * 1.75]),
      role: Role.accent, z: 111, rim: true);
  b.add(B.head, _oval(0, -r * 1.85, r * 0.1, r * 0.1), role: Role.aura, z: 112, outline: false, lodMin: 1);
  // Moustache.
  b.add(B.head, _smooth([-r * 0.1, -r * 0.5, r * 0.4, -r * 0.6, r * 0.9, -r * 0.48, r * 0.75, -r * 0.3, r * 0.4, -r * 0.42, 0, -r * 0.3]),
      color: _white, z: 115);
  b.chains.add(b.chain(B.head, r * 0.35, -r * 0.3,
      segments: 5, segLen: 0.15, angle: -0.1, curl: 0.05, stiffness: 0.3, w0: 0.5, w1: 0.08,
      role: fixedChainRole(1), z: 114));
  return _finish(PieceType.king, b, height: 3.05, style: const _ClipStyle(heavy: true, elegant: true));
}

// ---------------------------------------------------------------------------
// Clips (keyframes) — angles en radians : pour un membre pendant, un angle
// négatif porte l'extrémité vers l'avant (+x) ; pour le torse/la tête, positif = penché en avant.
// ---------------------------------------------------------------------------

class _ClipStyle {
  const _ClipStyle({this.guard = 0, this.heavy = false, this.bouncy = false, this.staff = false, this.elegant = false});
  final double guard;
  final bool heavy;
  final bool bouncy;
  final bool staff;
  final bool elegant;
}

Track _t(int bone, int ch, List<double> keys, [Ease e = Ease.inOutSine]) => Track(bone, ch, keys, ease: e);

Map<AnimState, Clip> _clips(PieceType type, _Spec s, _ClipStyle st) => {
      AnimState.idle: _idle(st),
      AnimState.move: _move(st),
      AnimState.jump: _jump(st),
      AnimState.attack: _attack(type, st),
      AnimState.hit: _hit(),
      AnimState.ko: _ko(),
      AnimState.victory: _victory(st),
      AnimState.petrified: _petrified(),
    };

Clip _idle(_ClipStyle st) {
  final g = st.guard;
  final p = st.bouncy ? 0.8 : (st.heavy ? 3.0 : 2.4);
  final h = p / 2;
  final tracks = <Track>[
    _t(B.torso, Ch.sy, [0, 1, h, 1.03, p, 1]),
    _t(B.torso, Ch.rot, [0, 0.02, h, -0.015, p, 0.02]),
    _t(B.head, Ch.rot, [0, -0.02, h, 0.03, p, -0.02]),
    _t(B.root, Ch.ty, [0, 0, h, st.bouncy ? -0.06 : 0.0, p, 0]),
    _t(B.legFrontU, Ch.rot, [0, 0.05 + 0.1 * g, h, 0.08 + 0.18 * g, p, 0.05 + 0.1 * g]),
    _t(B.legFrontL, Ch.rot, [0, -0.05 - 0.15 * g, h, -0.1 - 0.3 * g, p, -0.05 - 0.15 * g]),
    _t(B.legBackU, Ch.rot, [0, -0.05 - 0.1 * g, h, -0.1 - 0.2 * g, p, -0.05 - 0.1 * g]),
    _t(B.legBackL, Ch.rot, [0, 0.1 + 0.15 * g, h, 0.18 + 0.3 * g, p, 0.1 + 0.15 * g]),
  ];
  if (g > 0) {
    // Garde : poings levés.
    tracks.addAll([
      _t(B.armFrontU, Ch.rot, [0, -0.35 * g, h, -0.42 * g, p, -0.35 * g]),
      _t(B.armFrontL, Ch.rot, [0, -1.9 * g, h, -2.0 * g, p, -1.9 * g]),
      _t(B.armBackU, Ch.rot, [0, -0.5 * g, h, -0.55 * g, p, -0.5 * g]),
      _t(B.armBackL, Ch.rot, [0, -1.7 * g, h, -1.8 * g, p, -1.7 * g]),
    ]);
  } else if (st.staff) {
    tracks.addAll([
      _t(B.armFrontU, Ch.rot, [0, -0.25, h, -0.3, p, -0.25]),
      _t(B.armFrontL, Ch.rot, [0, -0.7, h, -0.75, p, -0.7]),
      _t(B.prop, Ch.rot, [0, 0.95, h, 1.0, p, 0.95]),
      _t(B.armBackU, Ch.rot, [0, 0.05, h, 0.1, p, 0.05]),
    ]);
  } else {
    tracks.addAll([
      _t(B.armFrontU, Ch.rot, [0, 0.0, h, 0.06, p, 0.0]),
      _t(B.armBackU, Ch.rot, [0, 0.0, h, -0.06, p, 0.0]),
      _t(B.armFrontL, Ch.rot, [0, st.elegant ? -0.5 : 0, h, st.elegant ? -0.55 : -0.05, p, st.elegant ? -0.5 : 0]),
    ]);
  }
  return Clip(p, tracks, loop: true);
}

Clip _move(_ClipStyle st) {
  const p = 0.5, q = p / 4;
  const e = Ease.inOutSine;
  return Clip(
      p,
      [
        _t(B.root, Ch.rot, [0, 0.08, p, 0.08]),
        _t(B.root, Ch.ty, [0, 0, q, -0.08, 2 * q, 0, 3 * q, -0.08, p, 0], e),
        _t(B.torso, Ch.rot, [0, 0.12, q, 0.16, 2 * q, 0.12, 3 * q, 0.16, p, 0.12]),
        _t(B.torso, Ch.sy, [0, 0.97, q, 1.02, 2 * q, 0.97, 3 * q, 1.02, p, 0.97]),
        _t(B.head, Ch.rot, [0, -0.08, p, -0.08]),
        _t(B.legFrontU, Ch.rot, [0, -0.65, 2 * q, 0.55, p, -0.65], e),
        _t(B.legFrontL, Ch.rot, [0, 0.15, q, 0.25, 2 * q, 0.15, 3 * q, 0.95, p, 0.15], e),
        _t(B.legBackU, Ch.rot, [0, 0.55, 2 * q, -0.65, p, 0.55], e),
        _t(B.legBackL, Ch.rot, [0, 0.15, q, 0.95, 2 * q, 0.15, 3 * q, 0.25, p, 0.15], e),
        _t(B.armFrontU, Ch.rot, [0, 0.7, 2 * q, -0.6, p, 0.7], e),
        _t(B.armFrontL, Ch.rot, [0, -0.5, 2 * q, -1.1, p, -0.5], e),
        _t(B.armBackU, Ch.rot, [0, -0.6, 2 * q, 0.7, p, -0.6], e),
        _t(B.armBackL, Ch.rot, [0, -1.1, 2 * q, -0.5, p, -1.1], e),
        if (st.staff) _t(B.prop, Ch.rot, [0, 1.2, p, 1.2]),
      ],
      loop: true);
}

Clip _jump(_ClipStyle st) {
  // 0–0.2 anticipation (écrasement), 0.2–0.75 vol (étirement puis repli), 0.75–1 réception.
  const eo = Ease.outCubic, ei = Ease.inCubic, io = Ease.inOutSine;
  return Clip(1.0, [
    Track(B.root, Ch.sy, [0, 1, 0.18, 0.74, 0.3, 1.22, 0.5, 1.0, 0.76, 1.05, 0.84, 0.78, 1.0, 1.0],
        eases: [eo, Ease.outBack, io, io, eo, Ease.outBack]),
    Track(B.root, Ch.sx, [0, 1, 0.18, 1.2, 0.3, 0.86, 0.5, 1.0, 0.76, 0.97, 0.84, 1.18, 1.0, 1.0],
        eases: [eo, Ease.outBack, io, io, eo, Ease.outBack]),
    Track(B.root, Ch.ty, [0, 0, 0.2, 0, 0.5, -0.9, 0.78, 0, 1.0, 0], eases: [io, eo, ei, io]),
    Track(B.root, Ch.rot, [0, 0, 0.2, 0.1, 0.5, 0.2, 0.78, 0.05, 1.0, 0], ease: io),
    Track(B.torso, Ch.rot, [0, 0, 0.18, 0.35, 0.32, -0.05, 0.55, 0.15, 0.84, 0.3, 1.0, 0], ease: io),
    Track(B.head, Ch.rot, [0, 0, 0.18, -0.2, 0.4, 0.1, 1.0, 0], ease: io),
    Track(B.legFrontU, Ch.rot, [0, 0, 0.18, -0.9, 0.3, 0.1, 0.5, -1.25, 0.76, -0.2, 0.84, -0.8, 1.0, 0], ease: io),
    Track(B.legFrontL, Ch.rot, [0, 0, 0.18, 1.5, 0.3, 0.05, 0.5, 1.9, 0.76, 0.3, 0.84, 1.4, 1.0, 0], ease: io),
    Track(B.legBackU, Ch.rot, [0, 0, 0.18, -0.7, 0.3, 0.35, 0.5, -0.7, 0.76, 0.1, 0.84, -0.6, 1.0, 0], ease: io),
    Track(B.legBackL, Ch.rot, [0, 0, 0.18, 1.4, 0.3, 0.2, 0.5, 1.6, 0.76, 0.3, 0.84, 1.2, 1.0, 0], ease: io),
    Track(B.armFrontU, Ch.rot, [0, 0, 0.18, 0.9, 0.32, -2.6, 0.55, -2.0, 0.84, -0.6, 1.0, 0], ease: io),
    Track(B.armFrontL, Ch.rot, [0, 0, 0.32, -0.2, 0.55, -0.6, 1.0, 0], ease: io),
    Track(B.armBackU, Ch.rot, [0, 0, 0.18, 0.8, 0.32, -2.3, 0.55, -1.6, 0.84, -0.4, 1.0, 0], ease: io),
    Track(B.armBackL, Ch.rot, [0, 0, 0.32, -0.3, 0.55, -0.8, 1.0, 0], ease: io),
    if (st.staff) _t(B.prop, Ch.rot, [0, 0.9, 0.5, 1.5, 1.0, 0.9]),
  ]);
}

Clip _attack(PieceType type, _ClipStyle st) {
  const io = Ease.inOutSine, eo = Ease.outCubic, ei = Ease.inCubic, ob = Ease.outBack;
  switch (type) {
    case PieceType.queen:
      // Charge (bras ramenés), poussée des deux paumes : rayon d'énergie.
      return Clip(0.9, [
        Track(B.torso, Ch.rot, [0, 0, 0.3, -0.22, 0.42, 0.22, 0.75, 0.18, 0.9, 0], eases: [io, eo, io, io]),
        Track(B.root, Ch.tx, [0, 0, 0.3, -0.15, 0.42, 0.2, 0.75, 0.15, 0.9, 0], eases: [io, eo, io, io]),
        Track(B.armFrontU, Ch.rot, [0, 0, 0.3, 0.9, 0.42, -1.55, 0.75, -1.5, 0.9, 0], eases: [io, ob, io, io]),
        Track(B.armFrontL, Ch.rot, [0, 0, 0.3, -1.9, 0.42, -0.05, 0.75, -0.1, 0.9, 0], eases: [io, eo, io, io]),
        Track(B.armBackU, Ch.rot, [0, 0, 0.3, 0.7, 0.42, -1.4, 0.75, -1.35, 0.9, 0], eases: [io, ob, io, io]),
        Track(B.armBackL, Ch.rot, [0, 0, 0.3, -1.9, 0.42, -0.1, 0.75, -0.1, 0.9, 0], eases: [io, eo, io, io]),
        Track(B.legFrontU, Ch.rot, [0, 0, 0.3, -0.4, 0.42, -0.6, 0.9, 0], ease: io),
        Track(B.legBackU, Ch.rot, [0, 0, 0.3, 0.3, 0.42, 0.55, 0.9, 0], ease: io),
        Track(B.legFrontL, Ch.rot, [0, 0, 0.3, 0.5, 0.42, 0.3, 0.9, 0], ease: io),
        Track(B.head, Ch.rot, [0, 0, 0.3, -0.1, 0.42, 0.05, 0.9, 0], ease: io),
      ]);
    case PieceType.bishop:
      // Bâton levé au-dessus de la tête puis pointé vers la cible ; lévitation.
      return Clip(0.9, [
        Track(B.root, Ch.ty, [0, 0, 0.35, -0.35, 0.6, -0.3, 0.9, 0], ease: io),
        Track(B.armFrontU, Ch.rot, [0, 0, 0.35, -2.7, 0.48, -1.5, 0.75, -1.45, 0.9, 0], eases: [io, eo, io, io]),
        Track(B.armFrontL, Ch.rot, [0, 0, 0.35, -0.2, 0.48, 0.0, 0.9, 0], ease: io),
        Track(B.prop, Ch.rot, [0, 0.95, 0.35, 0.2, 0.48, -0.1, 0.75, 0.0, 0.9, 0.95], eases: [io, eo, io, io]),
        Track(B.armBackU, Ch.rot, [0, 0, 0.35, -1.4, 0.48, 0.3, 0.9, 0], ease: io),
        Track(B.armBackL, Ch.rot, [0, 0, 0.35, -1.2, 0.48, -0.3, 0.9, 0], ease: io),
        Track(B.torso, Ch.rot, [0, 0, 0.35, -0.15, 0.48, 0.2, 0.9, 0], eases: [io, eo, io]),
        Track(B.head, Ch.rot, [0, 0, 0.35, -0.2, 0.48, 0.1, 0.9, 0], ease: io),
        Track(B.legFrontU, Ch.rot, [0, 0, 0.35, -0.3, 0.9, 0], ease: io),
        Track(B.legFrontL, Ch.rot, [0, 0, 0.35, 0.6, 0.9, 0], ease: io),
      ]);
    case PieceType.knight:
      // Coup de pied sauté : appel, envol, jambe tendue, réception.
      return Clip(0.9, [
        Track(B.root, Ch.ty, [0, 0, 0.14, 0.0, 0.34, -0.6, 0.6, -0.5, 0.8, 0, 0.9, 0], eases: [io, eo, io, ei, io]),
        Track(B.root, Ch.rot, [0, 0, 0.14, 0.1, 0.34, -0.45, 0.6, -0.4, 0.8, 0, 0.9, 0], ease: io),
        Track(B.root, Ch.sy, [0, 1, 0.14, 0.8, 0.24, 1.1, 0.34, 1, 0.8, 0.85, 0.9, 1], eases: [eo, ob, io, ei, ob]),
        Track(B.root, Ch.sx, [0, 1, 0.14, 1.15, 0.24, 0.92, 0.34, 1, 0.8, 1.12, 0.9, 1], eases: [eo, ob, io, ei, ob]),
        Track(B.legFrontU, Ch.rot, [0, 0, 0.14, -0.6, 0.34, -1.75, 0.6, -1.7, 0.8, -0.2, 0.9, 0], eases: [io, ob, io, io, io]),
        Track(B.legFrontL, Ch.rot, [0, 0, 0.14, 1.2, 0.24, 1.6, 0.34, 0.0, 0.6, 0.05, 0.8, 0.6, 0.9, 0], eases: [io, io, eo, io, io, io]),
        Track(B.legBackU, Ch.rot, [0, 0, 0.14, -0.5, 0.34, 0.2, 0.6, 0.3, 0.9, 0], ease: io),
        Track(B.legBackL, Ch.rot, [0, 0, 0.14, 1.0, 0.34, 1.7, 0.6, 1.6, 0.9, 0], ease: io),
        Track(B.armFrontU, Ch.rot, [0, -0.35, 0.34, 1.2, 0.6, 1.1, 0.9, -0.35], ease: io),
        Track(B.armFrontL, Ch.rot, [0, -1.9, 0.34, -0.6, 0.9, -1.9], ease: io),
        Track(B.armBackU, Ch.rot, [0, -0.5, 0.34, -1.6, 0.6, -1.5, 0.9, -0.5], ease: io),
        Track(B.armBackL, Ch.rot, [0, -1.7, 0.34, -0.4, 0.9, -1.7], ease: io),
        Track(B.torso, Ch.rot, [0, 0, 0.14, 0.3, 0.34, -0.25, 0.8, 0.1, 0.9, 0], ease: io),
      ]);
    case PieceType.rook:
      // Bond, poings joints au-dessus de la tête, frappe au sol (séisme).
      return Clip(0.9, [
        Track(B.root, Ch.ty, [0, 0, 0.12, 0, 0.4, -0.75, 0.5, 0, 0.9, 0], eases: [io, eo, ei, io]),
        Track(B.root, Ch.sy, [0, 1, 0.12, 0.82, 0.22, 1.12, 0.4, 1.05, 0.5, 0.72, 0.62, 1.05, 0.75, 1, 0.9, 1],
            eases: [eo, ob, io, ei, ob, io, io]),
        Track(B.root, Ch.sx, [0, 1, 0.12, 1.12, 0.22, 0.92, 0.4, 0.97, 0.5, 1.25, 0.62, 0.97, 0.75, 1, 0.9, 1],
            eases: [eo, ob, io, ei, ob, io, io]),
        Track(B.armFrontU, Ch.rot, [0, 0, 0.12, 0.5, 0.4, -3.0, 0.5, -1.0, 0.75, -0.9, 0.9, 0], eases: [io, eo, ei, io, io]),
        Track(B.armFrontL, Ch.rot, [0, 0, 0.4, -0.6, 0.5, 0.0, 0.9, 0], ease: io),
        Track(B.armBackU, Ch.rot, [0, 0, 0.12, 0.4, 0.4, -2.7, 0.5, -0.8, 0.75, -0.7, 0.9, 0], eases: [io, eo, ei, io, io]),
        Track(B.armBackL, Ch.rot, [0, 0, 0.4, -0.7, 0.5, 0.0, 0.9, 0], ease: io),
        Track(B.torso, Ch.rot, [0, 0, 0.4, -0.2, 0.5, 0.4, 0.75, 0.3, 0.9, 0], eases: [io, ei, io, io]),
        Track(B.legFrontU, Ch.rot, [0, 0, 0.12, -0.6, 0.4, -0.3, 0.5, -0.8, 0.9, 0], ease: io),
        Track(B.legFrontL, Ch.rot, [0, 0, 0.12, 1.0, 0.4, 0.5, 0.5, 1.2, 0.9, 0], ease: io),
        Track(B.legBackU, Ch.rot, [0, 0, 0.12, -0.4, 0.5, -0.5, 0.9, 0], ease: io),
        Track(B.legBackL, Ch.rot, [0, 0, 0.12, 0.9, 0.5, 1.0, 0.9, 0], ease: io),
      ]);
    case PieceType.pawn:
      // Combo de poings alternés.
      final fu = <double>[0, -0.35], fl = <double>[0, -1.9], bu = <double>[0, -0.5], bl = <double>[0, -1.7];
      final tr = <double>[0, 0];
      for (var i = 0; i < 6; i++) {
        final t0 = 0.1 + i * 0.1;
        final front = i.isEven;
        (front ? fu : bu).addAll([t0 + 0.05, -1.5, t0 + 0.1, front ? -0.35 : -0.5]);
        (front ? fl : bl).addAll([t0 + 0.05, -0.05, t0 + 0.1, front ? -1.9 : -1.7]);
        tr.addAll([t0 + 0.05, front ? 0.2 : -0.05]);
      }
      fu.addAll([0.9, -0.35]);
      fl.addAll([0.9, -1.9]);
      bu.addAll([0.9, -0.5]);
      bl.addAll([0.9, -1.7]);
      tr.addAll([0.9, 0]);
      return Clip(0.9, [
        _t(B.armFrontU, Ch.rot, fu, eo),
        _t(B.armFrontL, Ch.rot, fl, eo),
        _t(B.armBackU, Ch.rot, bu, eo),
        _t(B.armBackL, Ch.rot, bl, eo),
        _t(B.torso, Ch.rot, tr, eo),
        _t(B.root, Ch.tx, [0, 0, 0.1, 0.2, 0.7, 0.25, 0.9, 0]),
        _t(B.legFrontU, Ch.rot, [0, 0.1, 0.1, -0.45, 0.7, -0.45, 0.9, 0.1]),
        _t(B.legFrontL, Ch.rot, [0, -0.1, 0.1, 0.5, 0.7, 0.5, 0.9, -0.1]),
        _t(B.legBackU, Ch.rot, [0, -0.1, 0.1, 0.4, 0.7, 0.4, 0.9, -0.1]),
      ]);
    case PieceType.king:
      // Ki rassemblé à la poitrine, puis poussée des deux paumes (vague dorée).
      return Clip(0.9, [
        Track(B.torso, Ch.rot, [0, 0, 0.32, -0.2, 0.55, 0.22, 0.8, 0.15, 0.9, 0], eases: [io, eo, io, io]),
        Track(B.armFrontU, Ch.rot, [0, 0, 0.32, -0.5, 0.55, -1.5, 0.8, -1.4, 0.9, 0], eases: [io, ob, io, io]),
        Track(B.armFrontL, Ch.rot, [0, 0, 0.32, -1.9, 0.55, -0.1, 0.9, 0], eases: [io, eo, io]),
        Track(B.armBackU, Ch.rot, [0, 0, 0.32, -0.6, 0.55, -1.45, 0.8, -1.35, 0.9, 0], eases: [io, ob, io, io]),
        Track(B.armBackL, Ch.rot, [0, 0, 0.32, -1.8, 0.55, -0.15, 0.9, 0], eases: [io, eo, io]),
        Track(B.root, Ch.ty, [0, 0, 0.32, -0.12, 0.55, 0, 0.9, 0], ease: io),
        Track(B.legFrontU, Ch.rot, [0, 0, 0.32, -0.2, 0.55, -0.45, 0.9, 0], ease: io),
        Track(B.legBackU, Ch.rot, [0, 0, 0.55, 0.4, 0.9, 0], ease: io),
        Track(B.head, Ch.rot, [0, 0, 0.32, -0.15, 0.55, 0.1, 0.9, 0], ease: io),
      ]);
  }
}

Clip _hit() {
  const eo = Ease.outCubic, io = Ease.inOutSine;
  return Clip(0.42, [
    Track(B.root, Ch.tx, [0, 0, 0.08, -0.3, 0.42, 0], eases: [eo, io]),
    Track(B.root, Ch.rot, [0, 0, 0.08, -0.22, 0.42, 0], eases: [eo, io]),
    Track(B.root, Ch.sx, [0, 1, 0.06, 0.88, 0.2, 1.06, 0.42, 1], eases: [eo, io, io]),
    Track(B.head, Ch.rot, [0, 0, 0.08, -0.45, 0.42, 0], eases: [eo, io]),
    Track(B.torso, Ch.rot, [0, 0, 0.08, -0.3, 0.42, 0], eases: [eo, io]),
    Track(B.armFrontU, Ch.rot, [0, 0, 0.08, -1.4, 0.42, 0], eases: [eo, io]),
    Track(B.armBackU, Ch.rot, [0, 0, 0.08, -1.2, 0.42, 0], eases: [eo, io]),
    Track(B.armFrontL, Ch.rot, [0, 0, 0.08, -0.8, 0.42, 0], eases: [eo, io]),
    Track(B.legFrontU, Ch.rot, [0, 0, 0.08, -0.35, 0.42, 0], eases: [eo, io]),
  ]);
}

Clip _ko() {
  const eo = Ease.outCubic, ei = Ease.inQuad, io = Ease.inOutSine;
  return Clip(1.0, [
    Track(B.root, Ch.rot, [0, 0, 0.12, -0.3, 0.55, -1.5, 0.68, -1.38, 0.8, -1.5, 1.0, -1.5], eases: [eo, ei, eo, ei, io]),
    Track(B.root, Ch.tx, [0, 0, 0.12, -0.25, 0.55, 1.05, 1.0, 1.1], eases: [eo, io, io]),
    Track(B.root, Ch.ty, [0, 0, 0.3, -0.45, 0.55, -0.3, 0.68, -0.42, 0.8, -0.3, 1.0, -0.3], eases: [eo, ei, eo, ei, io]),
    Track(B.head, Ch.rot, [0, 0, 0.12, -0.5, 0.55, 0.25, 1.0, 0.3], ease: io),
    Track(B.torso, Ch.rot, [0, 0, 0.12, -0.3, 0.55, 0.05, 1.0, 0.1], ease: io),
    Track(B.armFrontU, Ch.rot, [0, 0, 0.12, -1.8, 0.55, -2.6, 1.0, -2.8], ease: io),
    Track(B.armFrontL, Ch.rot, [0, 0, 0.55, -0.4, 1.0, -0.2], ease: io),
    Track(B.armBackU, Ch.rot, [0, 0, 0.12, -1.5, 0.55, -2.3, 1.0, -2.5], ease: io),
    Track(B.legFrontU, Ch.rot, [0, 0, 0.12, -0.6, 0.55, -0.3, 1.0, -0.35], ease: io),
    Track(B.legFrontL, Ch.rot, [0, 0, 0.12, 0.8, 0.55, 0.3, 1.0, 0.4], ease: io),
    Track(B.legBackU, Ch.rot, [0, 0, 0.12, -0.2, 1.0, 0.1], ease: io),
    Track(B.eyes, Ch.sy, [0, 1, 0.12, 0.15, 1.0, 0.15], ease: eo),
  ]);
}

Clip _victory(_ClipStyle st) {
  const io = Ease.inOutSine, eo = Ease.outCubic, ei = Ease.inQuad, ob = Ease.outBack;
  return Clip(1.4, [
    Track(B.root, Ch.ty, [0, 0, 0.12, 0, 0.42, -0.45, 0.72, 0, 1.4, 0], eases: [io, eo, ei, io]),
    Track(B.root, Ch.sy, [0, 1, 0.12, 0.84, 0.24, 1.12, 0.42, 1.0, 0.72, 0.84, 0.86, 1.0, 1.4, 1],
        eases: [eo, ob, io, ei, ob, io]),
    Track(B.root, Ch.sx, [0, 1, 0.12, 1.12, 0.24, 0.92, 0.42, 1.0, 0.72, 1.12, 0.86, 1.0, 1.4, 1],
        eases: [eo, ob, io, ei, ob, io]),
    Track(B.armFrontU, Ch.rot, [0, -2.9, 0.42, -3.05, 0.9, -2.85, 1.4, -2.9], ease: io),
    Track(B.armFrontL, Ch.rot, [0, -0.35, 0.42, -0.05, 0.9, -0.4, 1.4, -0.35], ease: io),
    Track(B.armBackU, Ch.rot, [0, 0.35, 1.4, 0.35], ease: io),
    Track(B.armBackL, Ch.rot, [0, -1.6, 1.4, -1.6], ease: io),
    Track(B.head, Ch.rot, [0, -0.2, 0.42, -0.3, 1.4, -0.2], ease: io),
    Track(B.torso, Ch.rot, [0, -0.05, 0.42, -0.12, 1.4, -0.05], ease: io),
    Track(B.legFrontU, Ch.rot, [0, 0, 0.42, -0.5, 0.72, 0, 1.4, 0], ease: io),
    Track(B.legFrontL, Ch.rot, [0, 0, 0.42, 0.9, 0.72, 0, 1.4, 0], ease: io),
    Track(B.legBackU, Ch.rot, [0, 0, 0.42, 0.3, 0.72, 0, 1.4, 0], ease: io),
    Track(B.legBackL, Ch.rot, [0, 0, 0.42, 0.8, 0.72, 0, 1.4, 0], ease: io),
    if (st.staff) _t(B.prop, Ch.rot, [0, 0, 1.4, 0]),
  ], loop: true);
}

Clip _petrified() {
  const eo = Ease.outCubic;
  // Pose défensive figée.
  return Clip(0.5, [
    Track(B.torso, Ch.rot, [0, 0, 0.5, 0.12], ease: eo),
    Track(B.head, Ch.rot, [0, 0, 0.5, 0.15], ease: eo),
    Track(B.armFrontU, Ch.rot, [0, 0, 0.5, -0.5], ease: eo),
    Track(B.armFrontL, Ch.rot, [0, 0, 0.5, -1.9], ease: eo),
    Track(B.armBackU, Ch.rot, [0, 0, 0.5, -0.65], ease: eo),
    Track(B.armBackL, Ch.rot, [0, 0, 0.5, -1.7], ease: eo),
    Track(B.legFrontU, Ch.rot, [0, 0, 0.5, -0.25], ease: eo),
    Track(B.legFrontL, Ch.rot, [0, 0, 0.5, 0.35], ease: eo),
    Track(B.legBackU, Ch.rot, [0, 0, 0.5, 0.15], ease: eo),
    Track(B.legBackL, Ch.rot, [0, 0, 0.5, 0.2], ease: eo),
    Track(B.eyes, Ch.sy, [0, 1, 0.5, 0.25], ease: eo),
  ]);
}
