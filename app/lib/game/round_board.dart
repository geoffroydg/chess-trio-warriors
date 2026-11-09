import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';

import '../models/geometry.dart';
import 'perf.dart';

/// Couleurs des trois joueurs sur le plateau (or, rouge, bleu).
const boardPlayerColors = <Color>[Color(0xFFE9C25A), Color(0xFFE5533F), Color(0xFF4F93FF)];

/// Rayon extérieur du liseré métallique (fraction du rayon du disque de jeu).
const rimFactor = 1.075;

/// Épaisseur visible de la tranche du disque (fraction de l'échelle d'écran).
const rimThickness = 0.045;

/// Données d'écran nécessaires au dessin du plateau rond.
class BoardView {
  BoardView({
    required this.geometry,
    required this.projection,
    required this.scale,
    required this.origin,
  }) : matrix = screenMatrix(projection, scale, origin);

  final BoardGeometry geometry;
  final BoardProjection projection;
  final double scale;
  final Offset origin;

  /// Coordonnées normalisées du plateau -> pixels (perspective comprise).
  final Float64List matrix;

  Offset toScreen(double nx, double ny) {
    final p = projection.project(nx, ny);
    return Offset(origin.dx + p.dx * scale, origin.dy + p.dy * scale);
  }

  /// Point du disque à l'angle [deg] (sens trigonométrique à l'écran) et au rayon [rho].
  static Offset polar(double rho, double deg) {
    final a = deg * math.pi / 180;
    return Offset(0.5 + rho * math.cos(a), 0.5 - rho * math.sin(a));
  }

  Offset screenPolar(double rho, double deg) {
    final p = polar(rho, deg);
    return toScreen(p.dx, p.dy);
  }

  /// Matrice 4×4 (colonnes) : origine + échelle appliquées à la projection.
  static Float64List screenMatrix(BoardProjection projection, double scale, Offset origin) {
    final m = projection.matrix();
    final out = Float64List.fromList(m);
    for (var col = 0; col < 4; col++) {
      final w = m[col * 4 + 3];
      out[col * 4 + 0] = scale * m[col * 4 + 0] + origin.dx * w;
      out[col * 4 + 1] = scale * m[col * 4 + 1] + origin.dy * w;
    }
    return out;
  }
}

/// Chemin exact (arcs) d'une case en coordonnées normalisées du plateau.
Path cellPath(CellGeom c) {
  if (c.r1 <= 0) return Path()..addPolygon(c.polygon, true);
  final outer = Rect.fromCircle(center: const Offset(0.5, 0.5), radius: c.r1);
  final inner = Rect.fromCircle(center: const Offset(0.5, 0.5), radius: c.r0);
  final a0 = -c.a0 * math.pi / 180;
  final sweep = -(c.a1 - c.a0) * math.pi / 180;
  return Path()
    ..arcTo(outer, a0, sweep, true)
    ..arcTo(inner, a0 + sweep, -sweep, false)
    ..close();
}

/// Peintre du plateau rond : couche statique (pré-rendue) et couche animée.
class RoundBoardPainter {
  RoundBoardPainter(this.geometry) : paths = [for (final c in geometry.cells) cellPath(c)];

  final BoardGeometry geometry;
  final List<Path> paths;

  static const _center = Offset(0.5, 0.5);
  double get _r => geometry.radius;
  double get _med => geometry.medallion > 0 ? geometry.medallion : _r * 0.22;

  /// Points du bord extérieur (liseré) en pixels.
  List<Offset> rimScreen(BoardView v, {double factor = rimFactor, int n = 144}) =>
      [for (var i = 0; i < n; i++) v.screenPolar(_r * factor, 360 * i / n)];

  // ---------------------------------------------------------------------------
  // Couche statique.
  // ---------------------------------------------------------------------------

  void paintStatic(Canvas canvas, BoardView v,
      {List<bool> active = const [true, true, true], List<bool> hilts = const [false, false, false]}) {
    final rim = rimScreen(v);
    final rimPath = Path()..addPolygon(rim, true);
    final th = v.scale * rimThickness;

    // Ombre portée sur le fond.
    canvas.drawPath(
      rimPath.shift(Offset(0, th * 2.2)),
      Paint()
        ..color = const Color(0xB0000000)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, v.scale * 0.035),
    );
    canvas.drawPath(
      rimPath.shift(Offset(0, th * 1.2)),
      Paint()
        ..color = const Color(0x90000000)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, v.scale * 0.012),
    );

    // Tranche : bande entre l'ellipse du dessus et la même ellipse décalée vers le bas.
    var li = 0, ri = 0;
    for (var i = 0; i < rim.length; i++) {
      if (rim[i].dx < rim[li].dx) li = i;
      if (rim[i].dx > rim[ri].dx) ri = i;
    }
    final front = <Offset>[];
    // L'avant (bas de l'écran) va de la gauche à la droite en passant par 270°.
    for (var i = li;; i = (i + 1) % rim.length) {
      front.add(rim[i]);
      if (i == ri) break;
    }
    final side = Path()..moveTo(front.first.dx, front.first.dy);
    for (final p in front) {
      side.lineTo(p.dx, p.dy);
    }
    for (final p in front.reversed) {
      side.lineTo(p.dx, p.dy + th);
    }
    side.close();
    final bounds = rimPath.getBounds();
    canvas.drawPath(
      side,
      Paint()
        ..shader = ui.Gradient.linear(bounds.centerLeft, bounds.centerRight, const [
          Color(0xFF1A1512),
          Color(0xFF5A4A3A),
          Color(0xFF8C7660),
          Color(0xFF4A3C30),
          Color(0xFF16110E),
        ], const [0, 0.25, 0.45, 0.7, 1]),
    );
    // Filet métallique au bas de la tranche.
    final lip = Path()..moveTo(front.first.dx, front.first.dy + th);
    for (final p in front) {
      lip.lineTo(p.dx, p.dy + th * 0.82);
    }
    canvas.drawPath(
      lip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, th * 0.12)
        ..color = const Color(0x55E8D2A8),
    );

    canvas.save();
    canvas.transform(v.matrix);
    _paintTop(canvas, v, active, hilts);
    canvas.restore();

    // Reflet spéculaire sur le liseré (espace écran).
    canvas.drawPath(
      rimPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, v.scale * 0.004)
        ..shader = ui.Gradient.linear(bounds.topCenter, bounds.bottomCenter, const [
          Color(0x00FFFFFF),
          Color(0x66FFF4D8),
          Color(0x22FFFFFF),
        ], const [0, 0.55, 1]),
    );
  }

  void _paintTop(Canvas canvas, BoardView v, List<bool> active, List<bool> hilts) {
    final r = _r;
    final rimR = r * rimFactor;

    // Liseré métallique (laiton brossé).
    canvas.drawCircle(
      _center,
      rimR,
      Paint()
        ..shader = ui.Gradient.sweep(_center, const [
          Color(0xFF6E5734),
          Color(0xFFD8BD84),
          Color(0xFF7A6038),
          Color(0xFFE9D6A6),
          Color(0xFF6A532F),
          Color(0xFFCBAE72),
          Color(0xFF6E5734),
        ], const [0, 0.17, 0.33, 0.5, 0.67, 0.83, 1]),
    );
    final ringLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.004
      ..color = const Color(0xAA2A1E10);
    canvas.drawCircle(_center, rimR - r * 0.003, ringLine);
    canvas.drawCircle(_center, r * 1.012, ringLine..color = const Color(0xCC1E150B));

    // Plateau de bois sombre sous les cases (petit jonc entre liseré et cases).
    canvas.drawCircle(
      _center,
      r * 1.01,
      Paint()
        ..shader = ui.Gradient.radial(_center, r * 1.01, const [
          Color(0xFF3A2A1E),
          Color(0xFF2A1D14),
          Color(0xFF1E140D),
        ], const [0, 0.7, 1]),
    );

    // Cases en damier gris anthracite / gris clair, pierre polie.
    const light = Color(0xFF8A8E95);
    const dark = Color(0xFF2C2F35);
    final rng = math.Random(7);
    for (var i = 0; i < geometry.cells.length; i++) {
      final c = geometry.cells[i];
      var base = c.light ? light : dark;
      base = Color.lerp(base, boardPlayerColors[c.sector], c.light ? 0.06 : 0.05)!;
      if (!active[c.sector]) base = Color.lerp(base, const Color(0xFF5B5B5B), 0.45)!;
      final path = paths[i];
      final mid = BoardView.polar((c.r0 + c.r1) / 2, c.angle);
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(mid.dx - r * 0.02, mid.dy - r * 0.03),
            (c.r1 - c.r0) * 1.6 + r * 0.05,
            [Color.lerp(base, const Color(0xFFFFFFFF), c.light ? 0.10 : 0.06)!, base,
              Color.lerp(base, const Color(0xFF000000), 0.18)!],
            const [0, 0.6, 1],
          ),
      );
      // Grain de pierre : quelques veines et mouchetures.
      canvas.save();
      canvas.clipPath(path);
      final speck = Paint()..color = (c.light ? const Color(0x14000000) : const Color(0x10FFFFFF));
      for (var k = 0; k < 10; k++) {
        final a = c.a0 + rng.nextDouble() * (c.a1 - c.a0);
        final rho = c.r0 + rng.nextDouble() * (c.r1 - c.r0);
        canvas.drawCircle(BoardView.polar(rho, a), r * (0.002 + rng.nextDouble() * 0.004), speck);
      }
      final vein = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.0025
        ..color = c.light ? const Color(0x18000000) : const Color(0x12FFFFFF);
      final va = c.a0 + rng.nextDouble() * 15;
      final p0 = BoardView.polar(c.r0, va);
      final p1 = BoardView.polar(c.r1, va + (rng.nextDouble() - 0.5) * 18);
      final pc = BoardView.polar((c.r0 + c.r1) / 2, va + (rng.nextDouble() - 0.5) * 20);
      canvas.drawPath(Path()
        ..moveTo(p0.dx, p0.dy)
        ..quadraticBezierTo(pc.dx, pc.dy, p1.dx, p1.dy), vein);
      canvas.restore();
    }

    // Fins traits de séparation : anneaux et rayons.
    final sep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.005
      ..color = const Color(0xCC15110D);
    for (final rr in geometry.rings) {
      canvas.drawCircle(_center, rr, sep);
    }
    for (var k = 0; k < 24; k++) {
      final a = BoardView.polar(_med, k * 15.0);
      final b = BoardView.polar(r, k * 15.0);
      canvas.drawLine(a, b, sep);
    }

    final starts = <double>[for (var s = 0; s < 3; s++) _sectorStart(s)];
    if (geometry.ringCount >= 2) {
      // Lignes de trajet diagonales (centres de cases, pas « anneau ±1, colonne ±1 ») : fines
      // spirales colorées discrètes, de la couleur de l'équipe où elles commencent (anneau 1).
      for (var w0 = 0; w0 < 24; w0++) {
        final col = boardPlayerColors[_wedgeTeam(w0)];
        for (final dir in const [1, -1]) {
          final path = Path();
          final n = geometry.ringCount;
          for (var i = 0; i <= (n - 1) * 6 + 3; i++) {
            final t = i / 6; // 0 .. n - 0.5
            final pt = BoardView.polar(_ringMid(t), (w0 + dir * t) * 15.0 + 7.5);
            if (i == 0) {
              path.moveTo(pt.dx, pt.dy);
            } else {
              path.lineTo(pt.dx, pt.dy);
            }
          }
          canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeWidth = r * 0.0032
                ..color = col.withValues(alpha: dir > 0 ? 0.30 : 0.22));
        }
      }
      // Frontières entre équipes : filets métalliques (les épées sont dessinées par-dessus).
      for (var s = 0; s < 3; s++) {
        final ang = starts[s];
        final a = BoardView.polar(_med, ang);
        final b = BoardView.polar(r * 1.01, ang);
        canvas.drawLine(
            a,
            b,
            Paint()
              ..strokeWidth = r * 0.012
              ..strokeCap = StrokeCap.round
              ..color = const Color(0xFF1A130C));
        canvas.drawLine(
            a,
            b,
            Paint()
              ..strokeWidth = r * 0.005
              ..strokeCap = StrokeCap.round
              ..shader = ui.Gradient.linear(a, b, const [Color(0xFF8A7244), Color(0xFFE6CF98), Color(0xFF8A7244)], const [0, 0.5, 1]));
        // Milieu de l'arc (entre d et e) : filet fin de la couleur de l'équipe.
        final m0 = BoardView.polar(_med, ang + 60);
        final m1 = BoardView.polar(r, ang + 60);
        canvas.drawLine(
            m0,
            m1,
            Paint()
              ..strokeWidth = r * 0.004
              ..color = boardPlayerColors[s].withValues(alpha: 0.45));
      }
      // Lettres de colonnes sur le liseré, dans la couleur de l'équipe.
      for (var s = 0; s < 3; s++) {
        for (var f = 0; f < 8; f++) {
          _label(canvas, 'abcdefgh'[f], BoardView.polar(r * (1 + rimFactor) / 2, starts[s] + 15 * f + 7.5),
              starts[s] + 15 * f + 7.5, r * 0.058, Color.lerp(boardPlayerColors[s], const Color(0xFF1E1408), 0.6)!);
        }
      }
      for (final sw in geometry.swords) {
        _paintSword(canvas, sw, open: sw.border < hilts.length && hilts[sw.border]);
      }
    }

    _paintMedallionBase(canvas);
  }

  /// Rayon (normalisé) au milieu de l'anneau t (0 = anneau 1), interpolé pour t fractionnaire ;
  /// au-delà du dernier anneau, on rejoint le bord du médaillon.
  double _ringMid(double t) {
    final rings = geometry.rings;
    final n = geometry.ringCount;
    double mid(int k) => k >= n ? rings[n] : (rings[k] + rings[k + 1]) / 2;
    final k = t.floor().clamp(0, n);
    final fr = t - k;
    return mid(k) + (mid(math.min(k + 1, n)) - mid(k)) * fr;
  }

  late final List<int> _teamOfWedge = () {
    final out = List<int>.filled(24, 0);
    for (final c in geometry.cells) {
      if (c.wedge >= 0 && c.wedge < 24) out[c.wedge] = c.sector;
    }
    return out;
  }();
  int _wedgeTeam(int w) => _teamOfWedge[((w % 24) + 24) % 24];

  /// Épée sur une frontière : lame (anneaux 2-3) pointée vers le centre, poignée sur l'anneau 1.
  /// Poignée ouverte : garde translucide et gemme cyan (le passage est libre, sans prise).
  void _paintSword(Canvas canvas, SwordGeom sw, {required bool open}) {
    final r = _r;
    final a = sw.angle;
    Offset pt(double rho, double halfWidth) =>
        BoardView.polar(rho, a + (halfWidth / rho) * 180 / math.pi);
    // Ombre portée.
    final bladeHalf = r * 0.024;
    final blade = Path()
      ..moveTo(pt(sw.bladeR1, -bladeHalf).dx, pt(sw.bladeR1, -bladeHalf).dy)
      ..lineTo(pt(sw.bladeR0 + r * 0.04, -bladeHalf * 0.8).dx, pt(sw.bladeR0 + r * 0.04, -bladeHalf * 0.8).dy)
      ..lineTo(pt(sw.bladeR0, 0).dx, pt(sw.bladeR0, 0).dy)
      ..lineTo(pt(sw.bladeR0 + r * 0.04, bladeHalf * 0.8).dx, pt(sw.bladeR0 + r * 0.04, bladeHalf * 0.8).dy)
      ..lineTo(pt(sw.bladeR1, bladeHalf).dx, pt(sw.bladeR1, bladeHalf).dy)
      ..close();
    canvas.drawPath(
        blade.shift(Offset(r * 0.006, r * 0.008)),
        Paint()
          ..color = const Color(0x90000000)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, r * 0.006));
    final b0 = pt(sw.bladeR1, 0), b1 = pt(sw.bladeR0, 0);
    canvas.drawPath(
        blade,
        Paint()
          ..shader = ui.Gradient.linear(pt(sw.bladeR1, -bladeHalf), pt(sw.bladeR1, bladeHalf), const [
            Color(0xFF8E98A6),
            Color(0xFFF2F6FA),
            Color(0xFFB8C2CE),
            Color(0xFF5E6874),
          ], const [0, 0.42, 0.55, 1]));
    canvas.drawLine(b0, b1, Paint()
      ..strokeWidth = r * 0.003
      ..color = const Color(0x80FFFFFF));
    canvas.drawPath(
        blade,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.003
          ..color = const Color(0xFF2A2F38));
    // Poignée : fusée, garde et pommeau.
    final guardRho = sw.hiltR0 + r * 0.004;
    final gripEnd = sw.hiltR1 - r * 0.018;
    final gold = open ? const Color(0x9077E8FF) : const Color(0xFFE2C178);
    final goldDark = open ? const Color(0x80306A80) : const Color(0xFF7A5A26);
    canvas.drawLine(pt(guardRho, 0), pt(gripEnd, 0), Paint()
      ..strokeWidth = r * 0.022
      ..strokeCap = StrokeCap.round
      ..color = open ? const Color(0x80213A48) : const Color(0xFF3B2414));
    // Bandes de cuir de la fusée.
    for (var k = 1; k < 5; k++) {
      final rho = guardRho + (gripEnd - guardRho) * k / 5;
      canvas.drawLine(pt(rho, -r * 0.008), pt(rho, r * 0.008), Paint()
        ..strokeWidth = r * 0.0025
        ..color = open ? const Color(0x6077E8FF) : const Color(0xFF6E4A2A));
    }
    final guardHalf = r * 0.07;
    final guard = Path()
      ..moveTo(pt(guardRho - r * 0.009, -guardHalf).dx, pt(guardRho - r * 0.009, -guardHalf).dy)
      ..lineTo(pt(guardRho + r * 0.01, -guardHalf * 0.85).dx, pt(guardRho + r * 0.01, -guardHalf * 0.85).dy)
      ..lineTo(pt(guardRho + r * 0.01, guardHalf * 0.85).dx, pt(guardRho + r * 0.01, guardHalf * 0.85).dy)
      ..lineTo(pt(guardRho - r * 0.009, guardHalf).dx, pt(guardRho - r * 0.009, guardHalf).dy)
      ..close();
    canvas.drawPath(guard, Paint()
      ..shader = ui.Gradient.linear(pt(guardRho, -guardHalf), pt(guardRho, guardHalf), [goldDark, gold, goldDark], const [0, 0.5, 1]));
    canvas.drawPath(guard, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.0025
      ..color = open ? const Color(0xA0B8F6FF) : const Color(0xFF3A2810));
    final gem = pt(guardRho, 0);
    canvas.drawCircle(gem, r * 0.012, Paint()..color = open ? const Color(0xFF8FF4FF) : const Color(0xFFC0263A));
    canvas.drawCircle(gem.translate(-r * 0.003, -r * 0.003), r * 0.003, Paint()..color = const Color(0xC0FFFFFF));
    final pommel = pt(gripEnd + r * 0.006, 0);
    canvas.drawCircle(pommel, r * 0.016, Paint()
      ..shader = ui.Gradient.radial(pommel.translate(-r * 0.004, -r * 0.004), r * 0.014, [gold, goldDark]));
    if (open) {
      // Halo permanent discret : la poignée est ouverte.
      canvas.drawCircle(gem, r * 0.03, Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(gem, r * 0.03, const [Color(0x6060E8FF), Color(0x00000000)]));
    }
  }

  /// Centre (coordonnées normalisées) de la poignée d'une épée.
  Offset hiltCenter(SwordGeom sw) => BoardView.polar((sw.hiltR0 + sw.hiltR1) / 2, sw.angle);

  double _sectorStart(int s) {
    for (final c in geometry.cells) {
      if (c.sector == s && c.file == 0) return c.a0;
    }
    return 210.0 - 120 * s;
  }

  void _label(Canvas canvas, String text, Offset at, double angleDeg, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(fontFamily: 'Roboto', fontSize: 40, fontWeight: FontWeight.w800, color: color, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    // Lettre droite pour le joueur assis au bord (pied vers l'extérieur).
    canvas.rotate(-(angleDeg - 270) * math.pi / 180);
    final k = size / 40;
    canvas.scale(k, k);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  void _paintMedallionBase(Canvas canvas) {
    final m = _med;
    // Cerclage métallique.
    canvas.drawCircle(
      _center,
      m * 1.04,
      Paint()
        ..shader = ui.Gradient.sweep(_center, const [
          Color(0xFF6E5734),
          Color(0xFFE6CF98),
          Color(0xFF6E5734),
          Color(0xFFD9BD80),
          Color(0xFF6E5734),
        ], const [0, 0.25, 0.5, 0.75, 1]),
    );
    // Pierre sombre gravée.
    canvas.drawCircle(
      _center,
      m * 0.95,
      Paint()
        ..shader = ui.Gradient.radial(_center, m, const [Color(0xFF2B2440), Color(0xFF171425), Color(0xFF0D0B16)],
            const [0, 0.7, 1]),
    );
    final engr = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = m * 0.025
      ..color = const Color(0x80C9B07A);
    canvas.drawCircle(_center, m * 0.86, engr);
    canvas.drawCircle(_center, m * 0.80, engr..strokeWidth = m * 0.012);
    // Les trois diamètres (frontières / milieux d'arcs) traversent le médaillon.
    for (var s = 0; s < 3; s++) {
      final ang = _sectorStart(s);
      canvas.drawLine(BoardView.polar(m * 0.80, ang), BoardView.polar(m * 0.80, ang + 180),
          Paint()
            ..strokeWidth = m * 0.018
            ..color = const Color(0x55C9B07A));
    }
    // Petites graduations (24 secteurs).
    for (var k = 0; k < 24; k++) {
      canvas.drawLine(BoardView.polar(m * 0.86, k * 15.0 + 7.5), BoardView.polar(m * 0.93, k * 15.0 + 7.5),
          Paint()
            ..strokeWidth = m * 0.02
            ..color = const Color(0x70C9B07A));
    }
  }

  // ---------------------------------------------------------------------------
  // Couche animée (chaque image) : médaillon lumineux et surlignages.
  // ---------------------------------------------------------------------------

  /// Motif d'énergie (trois flammes enroulées) du médaillon, centré en (0.5, 0.5).
  Path _energyArms(double m, double twist) {
    final path = Path();
    for (var s = 0; s < 3; s++) {
      final base = _sectorStart(s) + 60 + twist;
      final tip = BoardView.polar(m * 0.72, base + 70);
      final c1 = BoardView.polar(m * 0.62, base - 10);
      final c2 = BoardView.polar(m * 0.38, base + 95);
      final root = BoardView.polar(m * 0.12, base + 40);
      path
        ..moveTo(root.dx, root.dy)
        ..quadraticBezierTo(c1.dx, c1.dy, tip.dx, tip.dy)
        ..quadraticBezierTo(c2.dx, c2.dy, root.dx, root.dy)
        ..close();
    }
    return path;
  }

  // Médaillon : dégradés, tracés et pinceaux créés une fois (aucune allocation par image).
  late final Shader _medHalo = ui.Gradient.radial(_center, _med * 0.8, const [
    Color.fromRGBO(140, 220, 255, 0.55),
    Color.fromRGBO(90, 120, 255, 0.20),
    Color(0x00000000),
  ], const [0, 0.55, 1]);
  late final Shader _medArms = ui.Gradient.radial(_center, _med * 0.75, const [
    Color.fromRGBO(255, 255, 255, 0.90),
    Color.fromRGBO(120, 210, 255, 0.75),
    Color.fromRGBO(80, 90, 255, 0.15),
  ], const [0, 0.5, 1]);
  late final Shader _medCore = ui.Gradient.radial(_center, _med * 0.18, const [
    Color(0xFFFFFFFF),
    Color.fromRGBO(140, 230, 255, 0.6),
    Color(0x00000000),
  ], const [0, 0.5, 1]);
  late final Path _armsPath = _energyArms(_med, 0);
  final Paint _mAdd = Paint()..blendMode = BlendMode.plus;
  final Paint _mLine = Paint()..style = PaintingStyle.stroke;

  void paintMedallion(Canvas canvas, double time) {
    final m = _med;
    final pulse = 0.5 + 0.5 * math.sin(time * 2.2);
    // Halo d'énergie (opacité du pinceau modulée par la pulsation).
    _mAdd
      ..shader = _medHalo
      ..color = Color.fromRGBO(255, 255, 255, (0.30 + 0.25 * pulse) / 0.55);
    canvas.drawCircle(_center, m * 0.8, _mAdd);
    // Bras d'énergie : tracé mis en cache, tourné par le canevas.
    canvas.save();
    canvas.translate(_center.dx, _center.dy);
    canvas.rotate(-4 * math.sin(time * 0.7) * math.pi / 180);
    canvas.translate(-_center.dx, -_center.dy);
    _mAdd
      ..shader = _medArms
      ..color = Color.fromRGBO(255, 255, 255, (0.55 + 0.35 * pulse) / 0.9);
    canvas.drawPath(_armsPath, _mAdd);
    _mLine
      ..strokeWidth = m * 0.03
      ..color = Color.fromRGBO(230, 205, 140, 0.55 + 0.3 * pulse);
    canvas.drawPath(_armsPath, _mLine);
    canvas.restore();
    // Cœur.
    _mAdd
      ..shader = _medCore
      ..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(_center, m * (0.13 + 0.03 * pulse), _mAdd);
    _mAdd.shader = null;
    // Anneau gravé qui s'illumine.
    _mLine.color = Color.fromRGBO(120, 210, 255, 0.15 + 0.35 * pulse);
    canvas.drawCircle(_center, m * 0.86, _mLine);
  }

  /// Traînée lumineuse d'un coup qui traverse le médaillon : départ → centre → arrivée
  /// (courbe lisse qui passe exactement par le centre). [age] en secondes.
  static const trailDraw = 0.45, trailFade = 1.1;

  Path centerTrailPath(Offset from, Offset to) {
    const c = _center;
    var t = to - from;
    final len = t.distance;
    t = len < 1e-9 ? Offset.zero : t / len;
    final k = _med * 0.55;
    return Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(from.dx + (c.dx - from.dx) * 0.4, from.dy + (c.dy - from.dy) * 0.4, c.dx - t.dx * k, c.dy - t.dy * k,
          c.dx, c.dy)
      ..cubicTo(c.dx + t.dx * k, c.dy + t.dy * k, to.dx + (c.dx - to.dx) * 0.4, to.dy + (c.dy - to.dy) * 0.4, to.dx,
          to.dy);
  }

  void paintCenterTrail(Canvas canvas, Offset from, Offset to, double age, Color color) {
    if (age < 0 || age > trailDraw + trailFade) return;
    final r = _r;
    final metrics = centerTrailPath(from, to).computeMetrics().toList();
    if (metrics.isEmpty) return;
    final m = metrics.first;
    final total = m.length;
    final head = (age / trailDraw).clamp(0.0, 1.0) * total;
    final fading = age > trailDraw ? ((age - trailDraw) / trailFade).clamp(0.0, 1.0) : 0.0;
    final tail = math.max(0.0, head - total * 0.9) + fading * total * 0.6;
    if (head - tail <= 1e-6) return;
    final seg = m.extractPath(tail, head);
    final alpha = 1 - fading;
    // Lueur sans flou par image : deux traits larges et transparents superposés.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    canvas.drawPath(
        seg,
        glow
          ..strokeWidth = r * 0.08
          ..color = color.withValues(alpha: 0.16 * alpha));
    canvas.drawPath(
        seg,
        glow
          ..strokeWidth = r * 0.045
          ..color = color.withValues(alpha: 0.38 * alpha));
    canvas.drawPath(
        seg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * 0.009
          ..blendMode = BlendMode.plus
          ..color = Color.fromRGBO(255, 255, 255, 0.85 * alpha));
    // Tête de la traînée et éclair du médaillon au passage.
    final pos = m.getTangentForOffset(head)?.position;
    if (pos != null && fading == 0) {
      canvas.drawCircle(
          pos,
          r * 0.03,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(pos, r * 0.03, [const Color(0xFFFFFFFF), color.withValues(alpha: 0)]));
    }
    final passed = head / total;
    if (passed > 0.4) {
      final f = math.max(0.0, 1 - (age - trailDraw * 0.5) / (trailDraw + trailFade * 0.6));
      canvas.drawCircle(
          _center,
          _med * (0.6 + 0.4 * (1 - f)),
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(_center, _med, [
              color.withValues(alpha: 0.6 * f),
              color.withValues(alpha: 0.15 * f),
              const Color(0x00000000),
            ], const [0, 0.6, 1]));
    }
  }

  /// Éclat lumineux d'une poignée qui vient de s'ouvrir. [age] en secondes.
  static const hiltFlashLife = 2.4;

  void paintHiltFlash(Canvas canvas, SwordGeom sw, double age) {
    if (age < 0 || age > hiltFlashLife) return;
    final r = _r;
    final u = age / hiltFlashLife;
    final k = 1 - u;
    final c = hiltCenter(sw);
    final a = BoardView.polar(sw.bladeR0, sw.angle);
    final b = BoardView.polar(sw.hiltR1, sw.angle);
    final pulse = 0.6 + 0.4 * math.sin(age * 14);
    final glow = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    canvas.drawLine(
        a,
        b,
        glow
          ..strokeWidth = r * 0.1 * k
          ..color = Color.fromRGBO(110, 230, 255, 0.22 * k * pulse));
    canvas.drawLine(
        a,
        b,
        glow
          ..strokeWidth = r * 0.05 * k
          ..color = Color.fromRGBO(110, 230, 255, 0.5 * k * pulse));
    for (var i = 0; i < 2; i++) {
      final e = Curves.easeOutCubic.transform(((u * 1.6) - i * 0.25).clamp(0.0, 1.0));
      canvas.drawCircle(
          c,
          r * (0.02 + 0.16 * e),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.012 * (1 - e)
            ..blendMode = BlendMode.plus
            ..color = Color.fromRGBO(150, 240, 255, 0.9 * (1 - e)));
    }
    for (var i = 0; i < 10; i++) {
      final ang = i * 36.0 + age * 40;
      final p0 = c + Offset(math.cos(ang * math.pi / 180), math.sin(ang * math.pi / 180)) * (r * 0.02);
      final p1 = c + Offset(math.cos(ang * math.pi / 180), math.sin(ang * math.pi / 180)) * (r * (0.04 + 0.08 * u));
      canvas.drawLine(
          p0,
          p1,
          Paint()
            ..strokeWidth = r * 0.004
            ..blendMode = BlendMode.plus
            ..color = Color.fromRGBO(255, 255, 255, 0.8 * k));
    }
  }

  final Paint _hFill = Paint();
  final Paint _hLine = Paint()..style = PaintingStyle.stroke;
  final Paint _hGlow = Paint()..blendMode = BlendMode.plus;
  Shader? _targetShader;

  /// Surlignages (dernier coup, échec, sélection, destinations). [visible] : culling des
  /// cases hors champ (null : toutes dessinées).
  void paintHighlights(
    Canvas canvas, {
    required double time,
    String? selected,
    Iterable<String> targets = const [],
    bool Function(String id)? isCapture,
    String? lastFrom,
    String? lastTo,
    Iterable<String> checked = const [],
    bool Function(String id)? visible,
  }) {
    final r = _r;
    final pulse = 0.5 + 0.5 * math.sin(time * 6);
    Path pathOf(String id) => paths[BoardGeometry.cellIndexOf(id)];
    bool shown(String id) => visible == null || visible(id);
    void cell(String id, Color fill, double width, Color line) {
      _hFill.color = fill;
      canvas.drawPath(pathOf(id), _hFill);
      _hLine
        ..strokeWidth = width
        ..color = line;
      canvas.drawPath(pathOf(id), _hLine);
    }

    if (lastFrom != null && shown(lastFrom)) cell(lastFrom, const Color(0x66FFB23D), r * 0.006, const Color(0xAAFFC266));
    if (lastTo != null && shown(lastTo)) cell(lastTo, const Color(0x66FFB23D), r * 0.006, const Color(0xAAFFC266));
    for (final id in checked) {
      if (!shown(id)) continue;
      cell(id, Color.fromRGBO(255, 40, 40, 0.30 + 0.35 * pulse), r * 0.012,
          Color.fromRGBO(255, 90, 70, 0.6 + 0.4 * pulse));
    }
    if (selected != null && shown(selected)) {
      cell(selected, const Color(0x7035E0FF), r * 0.012, const Color(0xFF6FF0FF));
    }
    // Halo des destinations : un dégradé unitaire partagé, mis à l'échelle par le canevas.
    final sh = _targetShader ??= ui.Gradient.radial(Offset.zero, 1, const [
      Color.fromRGBO(255, 210, 110, 0.85),
      Color.fromRGBO(255, 140, 40, 0.30),
      Color(0x00000000),
    ], const [0, 0.45, 1]);
    for (final id in targets) {
      if (!shown(id)) continue;
      final c = geometry.byId(id);
      final capture = isCapture?.call(id) ?? false;
      if (capture) {
        cell(id, Color.fromRGBO(255, 60, 60, 0.22 + 0.12 * pulse), r * 0.012, const Color(0xFFFF5A4D));
      } else {
        final size = math.min(c.r1 - c.r0, (c.r0 + c.r1) / 2 * math.pi / 12);
        final rad = size * (0.22 + 0.03 * pulse);
        canvas.save();
        canvas.translate(c.x, c.y);
        canvas.scale(rad * 2.2);
        _hGlow.shader = sh;
        canvas.drawCircle(Offset.zero, 1, _hGlow);
        canvas.restore();
        _hFill.color = const Color(0xFFFFE2A0);
        canvas.drawCircle(Offset(c.x, c.y), rad * 0.75, _hFill);
      }
    }
  }
}

/// Composant Flame du plateau rond : couche statique pré-rendue (image de base asynchrone +
/// tuiles haute résolution des zones visibles), médaillon et surlignages redessinés à chaque
/// image (cases hors champ ignorées).
class BoardComponent extends PositionComponent {
  BoardComponent(this.host) : super(position: Vector2.zero());

  final BoardHost host;
  double _time = 0;
  RoundBoardPainter? _painter;

  // --- Mode historique (PerfConfig.asyncBoard faux) : image re-rendue en toImageSync. ---
  ui.Image? _image;
  ui.Picture? _picture;
  Float64List? _builtFor;
  List<bool> _builtActive = const [];
  List<bool> _builtHilts = const [];
  double _builtRatio = 0;
  BoardView? _builtView;

  // --- Mode asynchrone : Picture de la couche statique enregistrée une fois pour la vue
  // entière, image de base rastérisée en asynchrone (texture plafonnée), tuiles haute
  // résolution des zones visibles re-rendues à l'arrêt du geste et affichées en fondu. ---
  ui.Picture? _basePic;
  BoardView? _baseView;
  Rect _baseBounds = Rect.zero;
  ui.Image? _baseImg;
  double _baseDensity = 1;
  int _contentGen = 0;
  List<_BoardTile> _tiles = const [];
  BoardView? _tilesView;
  List<_BoardTile> _oldTiles = const [];
  BoardView? _oldTilesView;
  double _fade = 1;
  bool _tilesBuilding = false;
  int _tileGen = 0;
  final Paint _imgPaint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _baseImgPaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _tilePaint = Paint()
    ..filterQuality = FilterQuality.low
    ..isAntiAlias = false;

  /// Taille (pixels physiques) d'une tuile.
  static const int tilePx = PerfConfig.maxTexture ~/ 2;
  static const double fadeSeconds = 0.18;

  /// Tuiles haute résolution construites (tests).
  int tileBuilds = 0;
  int get tileCount => _tiles.length;

  /// Enregistrements de la couche statique (tests).
  int get contentBuilds => _contentGen;
  bool get baseCached => _baseImg != null;
  bool get tilesPending => _tilesBuilding;

  final List<({String from, String to, double start, Color color})> _trails = [];
  final Map<int, double> _flashes = {};

  /// Traînée d'un coup qui traverse le médaillon.
  void startTrail(String from, String to, Color color) {
    _trails.add((from: from, to: to, start: _time, color: color));
  }

  /// Éclat d'une poignée qui vient de s'ouvrir (frontière [border]).
  void flashHilt(int border) => _flashes[border] = _time;

  /// Effets en cours (tests).
  int get activeEffects => _trails.length + _flashes.length;

  RoundBoardPainter get painter => _painter ??= RoundBoardPainter(host.geometry);

  @override
  void updateTree(double dt) {
    final t0 = PerfStats.now();
    super.updateTree(dt);
    PerfStats.add(PerfSub.board, t0);
  }

  @override
  void renderTree(Canvas canvas) {
    final t0 = PerfStats.now();
    super.renderTree(canvas);
    PerfStats.add(PerfSub.board, t0);
  }

  @override
  void update(double dt) {
    _time += dt;
    _trails.removeWhere((t) => _time - t.start > RoundBoardPainter.trailDraw + RoundBoardPainter.trailFade);
    _flashes.removeWhere((_, t) => _time - t > RoundBoardPainter.hiltFlashLife);
    if (_fade < 1) {
      _fade = math.min(1, _fade + dt / fadeSeconds);
      if (_fade >= 1) _disposeTiles(_oldTiles);
      if (_fade >= 1) _oldTiles = const [];
    }
  }

  /// Force la reconstruction de la couche statique (mise en page, joueurs gelés).
  void invalidate() {
    _builtFor = null;
    _baseView = null;
  }

  double get _ratio => deviceRatio();

  // ------------------------------------------------------------------ mode historique

  void _ensureStatic(BoardView v) {
    final active = host.activePlayers;
    final hilts = host.hilts;
    final ratio = _ratio;
    final stale = _builtFor != null && !_listEq(_builtFor!, v.matrix);
    if (stale && !host.cameraSettled && _boolsEq(_builtActive, active) && _boolsEq(_builtHilts, hilts)) {
      return; // en mouvement : on transforme l'ancienne image (re-rendue à l'arrêt)
    }
    if (_builtFor != null &&
        _listEq(_builtFor!, v.matrix) &&
        _builtRatio == ratio &&
        _boolsEq(_builtActive, active) &&
        _boolsEq(_builtHilts, hilts)) {
      return;
    }
    _image?.dispose();
    _picture?.dispose();
    _image = null;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    painter.paintStatic(c, v, active: active, hilts: hilts);
    final pic = rec.endRecording();
    _picture = pic;
    final w = (size.x * ratio).ceil(), h = (size.y * ratio).ceil();
    if (w > 0 && h > 0 && w * h < 4096 * 4096) {
      final rec2 = ui.PictureRecorder();
      Canvas(rec2)
        ..scale(ratio)
        ..drawPicture(pic);
      final pic2 = rec2.endRecording();
      try {
        _image = pic2.toImageSync(w, h);
      } catch (_) {
        _image = null;
      }
      pic2.dispose();
    }
    _builtFor = v.matrix;
    _builtView = v;
    _builtActive = List.of(active);
    _builtHilts = List.of(hilts);
    _builtRatio = ratio;
  }

  void _renderLegacy(Canvas canvas, BoardView v) {
    _ensureStatic(v);
    final img = _image;
    final bv = _builtView;
    canvas.save();
    if (bv != null && bv.scale != v.scale || bv != null && bv.origin != v.origin) {
      _transformBetween(canvas, bv, v);
    }
    if (img != null) {
      final ratio = _builtRatio;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(0, 0, img.width / ratio, img.height / ratio),
        _imgPaint,
      );
    } else if (_picture != null) {
      canvas.drawPicture(_picture!);
    }
    canvas.restore();
  }

  // ------------------------------------------------------------------ mode asynchrone

  /// Transformation affine entre deux vues du plateau (même projection).
  static void _transformBetween(Canvas canvas, BoardView from, BoardView to) {
    final k = to.scale / from.scale;
    canvas.translate(to.origin.dx, to.origin.dy);
    canvas.scale(k);
    canvas.translate(-from.origin.dx, -from.origin.dy);
  }

  void _ensureContent(BoardView v) {
    final b = host.baseView ?? v;
    final active = host.activePlayers;
    final hilts = host.hilts;
    final bv = _baseView;
    if (_basePic != null &&
        bv != null &&
        bv.scale == b.scale &&
        bv.origin == b.origin &&
        _boolsEq(_builtActive, active) &&
        _boolsEq(_builtHilts, hilts)) {
      return;
    }
    _contentGen++;
    _basePic?.dispose();
    final rec = ui.PictureRecorder();
    painter.paintStatic(Canvas(rec), b, active: active, hilts: hilts);
    _basePic = rec.endRecording();
    _baseView = b;
    _baseBounds = Rect.fromPoints(Offset.zero, Offset(size.x, size.y));
    _builtActive = List.of(active);
    _builtHilts = List.of(hilts);
    // Contenu changé : l'ancienne image de base n'est plus valable (la Picture la remplace
    // jusqu'à la nouvelle rastérisation), les tuiles non plus.
    _baseImg?.dispose();
    _baseImg = null;
    _disposeTiles(_tiles);
    _disposeTiles(_oldTiles);
    _tiles = const [];
    _oldTiles = const [];
    _tilesView = null;
    _cancelTiles();
    _rasterizeBase();
  }

  void _rasterizeBase() {
    final pic = _basePic;
    if (pic == null || size.x <= 0 || size.y <= 0) return;
    final gen = _contentGen;
    final d = math.min(_ratio, PerfConfig.maxTexture / math.max(size.x, size.y));
    final rec = ui.PictureRecorder();
    Canvas(rec)
      ..scale(d)
      ..drawPicture(pic);
    final p2 = rec.endRecording();
    p2.toImage((size.x * d).ceil(), (size.y * d).ceil()).then((img) {
      p2.dispose();
      if (gen != _contentGen || !isMounted) {
        img.dispose();
        return;
      }
      _baseImg?.dispose();
      _baseImg = img;
      _baseDensity = d;
    }, onError: (Object _) => p2.dispose());
  }

  /// Densité nécessaire (pixels physiques par pixel de la vue entière) pour la vue [v].
  double _needDensity(BoardView v) => _ratio * v.scale / _baseView!.scale;

  void _maybeBuildTiles(BoardView v) {
    if (_tilesBuilding) {
      // Le geste reprend : la construction en cours est abandonnée (re-rendu à l'arrêt).
      if (!host.cameraSettled) _cancelTiles();
      return;
    }
    if (!host.cameraSettled || _baseImg == null) return;
    final have = _baseDensity;
    if (_needDensity(v) <= have * 1.05) {
      // Vue entière nette : les tuiles ne servent plus.
      if (_tiles.isNotEmpty && _fade >= 1) {
        _disposeTiles(_tiles);
        _tiles = const [];
        _tilesView = null;
      }
      return;
    }
    final tv = _tilesView;
    if (tv != null && tv.scale == v.scale && tv.origin == v.origin) return;
    _buildTiles(v);
  }

  // Construction en cours : rectangles restants (du centre vers les bords), tuiles prêtes.
  final List<Rect> _pending = [];
  final List<_BoardTile> _ready = [];
  BoardView? _buildingView;
  bool _tileInFlight = false;

  void _cancelTiles() {
    _tileGen++;
    _tilesBuilding = false;
    _tileInFlight = false;
    _pending.clear();
    _disposeTiles(_ready);
    _ready.clear();
  }

  /// Re-rendu haute résolution des seules tuiles visibles de la vue [v] : une tuile par
  /// image (asynchrone, toImage), puis remplacement en fondu quand toutes sont prêtes.
  void _buildTiles(BoardView v) {
    final b = _baseView;
    if (_basePic == null || b == null) return;
    final ratio = _ratio;
    // Emprise du plateau dans la vue v, limitée à l'écran.
    final k = v.scale / b.scale;
    final bb = _baseBounds;
    final area = Rect.fromLTRB(v.origin.dx + (bb.left - b.origin.dx) * k, v.origin.dy + (bb.top - b.origin.dy) * k,
            v.origin.dx + (bb.right - b.origin.dx) * k, v.origin.dy + (bb.bottom - b.origin.dy) * k)
        .intersect(Rect.fromLTWH(0, 0, size.x, size.y));
    if (area.width <= 0 || area.height <= 0) return;
    _cancelTiles();
    // Grille alignée sur les pixels physiques : chaque tuile est dessinée à l'échelle 1 (pas
    // de couture visible).
    final x0 = (area.left * ratio).floor(), y0 = (area.top * ratio).floor();
    final x1 = (area.right * ratio).ceil(), y1 = (area.bottom * ratio).ceil();
    for (var y = y0; y < y1; y += tilePx) {
      for (var x = x0; x < x1; x += tilePx) {
        _pending.add(Rect.fromLTRB(
            x / ratio, y / ratio, math.min(x + tilePx, x1) / ratio, math.min(y + tilePx, y1) / ratio));
      }
    }
    final mid = area.center;
    _pending.sort((p, q) => (q.center - mid).distanceSquared.compareTo((p.center - mid).distanceSquared));
    _buildingView = v;
    _tilesBuilding = true;
    tileBuilds++;
  }

  /// Lance la tuile suivante (au plus une en vol à la fois).
  void _stepTiles() {
    if (!_tilesBuilding || _tileInFlight) return;
    final pic = _basePic, b = _baseView, v = _buildingView;
    if (pic == null || b == null || v == null) return;
    if (_pending.isEmpty) {
      _disposeTiles(_oldTiles);
      _oldTiles = _tiles;
      _oldTilesView = _tilesView;
      _tiles = List.of(_ready);
      _ready.clear();
      _tilesView = v;
      _fade = 0;
      _tilesBuilding = false;
      return;
    }
    final r = _pending.removeLast();
    final ratio = _ratio;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)
      ..scale(ratio)
      ..translate(-r.left, -r.top);
    _transformBetween(c, b, v);
    c.drawPicture(pic);
    final p = rec.endRecording();
    final gen = _tileGen;
    _tileInFlight = true;
    p.toImage(math.max(1, (r.width * ratio).round()), math.max(1, (r.height * ratio).round())).then((img) {
      p.dispose();
      if (gen != _tileGen || !isMounted) {
        img.dispose();
        return;
      }
      _tileInFlight = false;
      _ready.add(_BoardTile(img, r));
    }, onError: (Object _) {
      p.dispose();
      if (gen == _tileGen) _cancelTiles();
    });
  }

  static void _disposeTiles(List<_BoardTile> tiles) {
    for (final t in tiles) {
      t.image.dispose();
    }
  }

  void _drawTiles(Canvas canvas, List<_BoardTile> tiles, BoardView from, BoardView v, double alpha) {
    if (tiles.isEmpty || alpha <= 0) return;
    canvas.save();
    _transformBetween(canvas, from, v);
    final k = v.scale / from.scale;
    _tilePaint.color = Color.fromARGB((alpha * 255).round(), 255, 255, 255);
    for (final t in tiles) {
      final d = t.dst;
      // Tuile hors de l'écran dans la vue courante : ignorée.
      final l = v.origin.dx + (d.left - from.origin.dx) * k, r = v.origin.dx + (d.right - from.origin.dx) * k;
      final tp = v.origin.dy + (d.top - from.origin.dy) * k, bt = v.origin.dy + (d.bottom - from.origin.dy) * k;
      if (r < 0 || l > size.x || bt < 0 || tp > size.y) continue;
      canvas.drawImageRect(t.image, t.src, d, _tilePaint);
    }
    canvas.restore();
  }

  /// Les tuiles prêtes couvrent tout l'écran pour la vue courante : la base est inutile.
  bool _tilesCover(BoardView v) {
    final tv = _tilesView;
    return _fade >= 1 && tv != null && tv.scale == v.scale && tv.origin == v.origin && _tiles.isNotEmpty;
  }

  void _renderAsync(Canvas canvas, BoardView v) {
    _ensureContent(v);
    final b = _baseView!;
    _maybeBuildTiles(v);
    _stepTiles();
    final tv = _tilesView;
    if (_tilesCover(v)) {
      _drawTiles(canvas, _tiles, tv!, v, 1);
      return;
    }
    canvas.save();
    _transformBetween(canvas, b, v);
    final img = _baseImg;
    if (img != null) {
      canvas.save();
      canvas.scale(1 / _baseDensity);
      canvas.drawImage(img, Offset.zero, _baseImgPaint);
      canvas.restore();
    } else {
      canvas.drawPicture(_basePic!);
    }
    canvas.restore();
    final ov = _oldTilesView;
    if (ov != null && _fade < 1) _drawTiles(canvas, _oldTiles, ov, v, 1);
    if (tv != null) _drawTiles(canvas, _tiles, tv, v, _fade);
  }

  // ------------------------------------------------------------------ couche animée

  static bool _boolsEq(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _listEq(Float64List a, Float64List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  BoardView? _view;
  late final bool Function(String id) _visibleFn = _cellVisible;

  /// Case visible à l'écran (marge d'une demi-case) ?
  bool _cellVisible(String id) {
    final v = _view;
    if (v == null || !PerfConfig.culling) return true;
    final c = host.geometry.byId(id);
    final p = v.toScreen(c.x, c.y);
    final m = v.scale * 0.08;
    return p.dx >= -m && p.dy >= -m && p.dx <= size.x + m && p.dy <= size.y + m;
  }

  bool _pointVisible(BoardView v, double nx, double ny, double radius) {
    if (!PerfConfig.culling) return true;
    final p = v.toScreen(nx, ny);
    final m = v.scale * radius;
    return p.dx >= -m && p.dy >= -m && p.dx <= size.x + m && p.dy <= size.y + m;
  }

  @override
  void render(Canvas canvas) {
    final v = host.boardView;
    if (v == null) return;
    if (PerfConfig.asyncBoard) {
      _renderAsync(canvas, v);
    } else {
      _renderLegacy(canvas, v);
    }
    _view = v;
    canvas.save();
    canvas.transform(v.matrix);
    final med = painter.geometry.medallion > 0 ? painter.geometry.medallion : painter.geometry.radius * 0.22;
    if (_pointVisible(v, 0.5, 0.5, med)) painter.paintMedallion(canvas, _time);
    painter.paintHighlights(
      canvas,
      time: _time,
      selected: host.selected,
      targets: host.targets,
      isCapture: host.hasPiece,
      lastFrom: host.lastFrom,
      lastTo: host.lastTo,
      checked: host.checkedKings,
      visible: PerfConfig.culling ? _visibleFn : null,
    );
    for (final t in _trails) {
      final a = host.geometry.byId(t.from), b = host.geometry.byId(t.to);
      painter.paintCenterTrail(canvas, Offset(a.x, a.y), Offset(b.x, b.y), _time - t.start, t.color);
    }
    for (final e in _flashes.entries) {
      for (final sw in host.geometry.swords) {
        if (sw.border == e.key) painter.paintHiltFlash(canvas, sw, _time - e.value);
      }
    }
    canvas.restore();
  }

  @override
  void onRemove() {
    _image?.dispose();
    _picture?.dispose();
    _image = null;
    _picture = null;
    _contentGen++;
    _cancelTiles();
    _basePic?.dispose();
    _basePic = null;
    _baseImg?.dispose();
    _baseImg = null;
    _disposeTiles(_tiles);
    _disposeTiles(_oldTiles);
    _tiles = const [];
    _oldTiles = const [];
    super.onRemove();
  }
}

/// Tuile haute résolution du plateau : image et rectangle (coordonnées de la vue construite).
class _BoardTile {
  _BoardTile(this.image, this.dst) : src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  final ui.Image image;
  final Rect dst;
  final Rect src;
}

/// Ce dont le plateau a besoin du jeu.
abstract class BoardHost {
  BoardGeometry get geometry;
  BoardView? get boardView;
  List<bool> get activePlayers;

  /// Poignées ouvertes (index = frontière).
  List<bool> get hilts;
  String? get selected;
  Set<String> get targets;
  Set<String> get checkedKings;
  String? get lastFrom;
  String? get lastTo;
  bool hasPiece(String id);
  void handleTap(Offset pos);

  /// Faux pendant un zoom/panoramique : le plateau pré-rendu est alors simplement transformé.
  bool get cameraSettled;

  /// Vue entière (zoom ×1) : repère de la couche statique enregistrée une fois.
  BoardView? get baseView;
}
