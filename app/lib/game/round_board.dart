import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart';

import '../models/geometry.dart';

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

  void paintStatic(Canvas canvas, BoardView v, {List<bool> active = const [true, true, true]}) {
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
    _paintTop(canvas, v, active);
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

  void _paintTop(Canvas canvas, BoardView v, List<bool> active) {
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

    // Diagonales colorées discrètes (de coin à coin, dans chaque arc de joueur).
    final rings = geometry.rings;
    if (rings.length == 5) {
      final starts = <double>[for (var s = 0; s < 3; s++) _sectorStart(s)];
      for (var s = 0; s < 3; s++) {
        final col = boardPlayerColors[s];
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * 0.0042
          ..color = col.withValues(alpha: 0.42);
        for (var f0 = 0; f0 <= 8; f0++) {
          for (final dir in const [1, -1]) {
            final path = Path();
            var started = false;
            for (var k = 0; k <= 4; k++) {
              final f = f0 + dir * k;
              if (f < 0 || f > 8) break;
              // Segment interpolé (spirale) entre deux coins.
              final steps = k == 0 ? 1 : 6;
              for (var t = 1; t <= steps; t++) {
                final u = k == 0 ? 0.0 : (k - 1) + t / steps;
                final ang = starts[s] + 15 * (f0 + dir * u);
                final idx = u.floor().clamp(0, 3);
                final fr = u - idx;
                final rho = rings[idx] + (rings[math.min(idx + 1, 4)] - rings[idx]) * fr;
                final pt = BoardView.polar(rho, ang);
                if (!started) {
                  path.moveTo(pt.dx, pt.dy);
                  started = true;
                } else {
                  path.lineTo(pt.dx, pt.dy);
                }
              }
            }
            if (f0 + dir * 1 >= 0 && f0 + dir * 1 <= 8) canvas.drawPath(path, p);
          }
        }
      }
      // Frontières entre joueurs (h d'un joueur / a du suivant ne sont pas voisines) :
      // filets métalliques soulignés de la couleur des deux joueurs.
      for (var s = 0; s < 3; s++) {
        final ang = starts[s];
        final a = BoardView.polar(_med, ang);
        final b = BoardView.polar(r * 1.01, ang);
        canvas.drawLine(
            a,
            b,
            Paint()
              ..strokeWidth = r * 0.016
              ..strokeCap = StrokeCap.round
              ..color = const Color(0xFF1A130C));
        canvas.drawLine(
            a,
            b,
            Paint()
              ..strokeWidth = r * 0.008
              ..strokeCap = StrokeCap.round
              ..shader = ui.Gradient.linear(a, b, const [Color(0xFF8A7244), Color(0xFFE6CF98), Color(0xFF8A7244)], const [0, 0.5, 1]));
        // Milieu de l'arc (entre d et e) : filet fin de la couleur du joueur.
        final m0 = BoardView.polar(_med, ang + 60);
        final m1 = BoardView.polar(r, ang + 60);
        canvas.drawLine(
            m0,
            m1,
            Paint()
              ..strokeWidth = r * 0.005
              ..color = boardPlayerColors[s].withValues(alpha: 0.55));
      }
      // Lettres de colonnes sur le liseré, dans la couleur du joueur.
      for (var s = 0; s < 3; s++) {
        for (var f = 0; f < 8; f++) {
          _label(canvas, 'abcdefgh'[f], BoardView.polar(r * (1 + rimFactor) / 2, starts[s] + 15 * f + 7.5),
              starts[s] + 15 * f + 7.5, r * 0.058, Color.lerp(boardPlayerColors[s], const Color(0xFF1E1408), 0.6)!);
        }
      }
    }

    _paintMedallionBase(canvas);
  }

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

  void paintMedallion(Canvas canvas, double time) {
    final m = _med;
    final pulse = 0.5 + 0.5 * math.sin(time * 2.2);
    // Halo d'énergie.
    canvas.drawCircle(
      _center,
      m * 0.8,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(_center, m * 0.8, [
          Color.fromRGBO(140, 220, 255, 0.30 + 0.25 * pulse),
          Color.fromRGBO(90, 120, 255, 0.10 + 0.10 * pulse),
          const Color(0x00000000),
        ], const [0, 0.55, 1]),
    );
    final arms = _energyArms(m, 4 * math.sin(time * 0.7));
    canvas.drawPath(
      arms,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(_center, m * 0.75, [
          Color.fromRGBO(255, 255, 255, 0.55 + 0.35 * pulse),
          Color.fromRGBO(120, 210, 255, 0.45 + 0.3 * pulse),
          Color.fromRGBO(80, 90, 255, 0.15),
        ], const [0, 0.5, 1]),
    );
    canvas.drawPath(
      arms,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = m * 0.03
        ..color = Color.fromRGBO(230, 205, 140, 0.55 + 0.3 * pulse),
    );
    // Cœur.
    canvas.drawCircle(
      _center,
      m * (0.13 + 0.03 * pulse),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(_center, m * 0.18, [
          const Color(0xFFFFFFFF),
          Color.fromRGBO(140, 230, 255, 0.6),
          const Color(0x00000000),
        ], const [0, 0.5, 1]),
    );
    // Anneau gravé qui s'illumine.
    canvas.drawCircle(
      _center,
      m * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = m * 0.03
        ..color = Color.fromRGBO(120, 210, 255, 0.15 + 0.35 * pulse),
    );
  }

  void paintHighlights(
    Canvas canvas, {
    required double time,
    String? selected,
    Iterable<String> targets = const [],
    bool Function(String id)? isCapture,
    String? lastFrom,
    String? lastTo,
    Iterable<String> checked = const [],
  }) {
    final r = _r;
    final pulse = 0.5 + 0.5 * math.sin(time * 6);
    Path pathOf(String id) => paths[BoardGeometry.cellIndexOf(id)];

    for (final id in [lastFrom, lastTo]) {
      if (id == null) continue;
      canvas.drawPath(pathOf(id), Paint()..color = const Color(0x66FFB23D));
      canvas.drawPath(
          pathOf(id),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.006
            ..color = const Color(0xAAFFC266));
    }
    for (final id in checked) {
      canvas.drawPath(pathOf(id), Paint()..color = Color.fromRGBO(255, 40, 40, 0.30 + 0.35 * pulse));
      canvas.drawPath(
          pathOf(id),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.012
            ..color = Color.fromRGBO(255, 90, 70, 0.6 + 0.4 * pulse));
    }
    if (selected != null) {
      canvas.drawPath(pathOf(selected), Paint()..color = const Color(0x7035E0FF));
      canvas.drawPath(
          pathOf(selected),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.012
            ..color = const Color(0xFF6FF0FF));
    }
    for (final id in targets) {
      final c = geometry.byId(id);
      final capture = isCapture?.call(id) ?? false;
      final at = Offset(c.x, c.y);
      if (capture) {
        canvas.drawPath(pathOf(id), Paint()..color = Color.fromRGBO(255, 60, 60, 0.22 + 0.12 * pulse));
        canvas.drawPath(
            pathOf(id),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * 0.012
              ..color = const Color(0xFFFF5A4D));
      } else {
        final size = math.min(c.r1 - c.r0, (c.r0 + c.r1) / 2 * math.pi / 12);
        final rad = size * (0.22 + 0.03 * pulse);
        canvas.drawCircle(
          at,
          rad * 2.2,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(at, rad * 2.2, [
              Color.fromRGBO(255, 210, 110, 0.85),
              Color.fromRGBO(255, 140, 40, 0.30),
              const Color(0x00000000),
            ], const [0, 0.45, 1]),
        );
        canvas.drawCircle(at, rad * 0.75, Paint()..color = const Color(0xFFFFE2A0));
      }
    }
  }
}

/// Composant Flame du plateau rond : couche statique pré-rendue en image, médaillon et
/// surlignages redessinés à chaque image.
class BoardComponent extends PositionComponent with TapCallbacks {
  BoardComponent(this.host) : super(position: Vector2.zero());

  final BoardHost host;
  double _time = 0;
  RoundBoardPainter? _painter;
  ui.Image? _image;
  ui.Picture? _picture;
  Float64List? _builtFor;
  List<bool> _builtActive = const [];
  double _builtRatio = 0;

  RoundBoardPainter get painter => _painter ??= RoundBoardPainter(host.geometry);

  @override
  void update(double dt) {
    _time += dt;
  }

  @override
  void onTapDown(TapDownEvent event) {
    final p = event.localPosition;
    host.handleTap(Offset(p.x, p.y));
  }

  /// Force la reconstruction de la couche statique (mise en page, joueurs gelés).
  void invalidate() => _builtFor = null;

  double get _ratio {
    try {
      return ui.PlatformDispatcher.instance.views.first.devicePixelRatio.clamp(1.0, 3.0);
    } catch (_) {
      return 2;
    }
  }

  void _ensureStatic(BoardView v) {
    final active = host.activePlayers;
    final ratio = _ratio;
    if (_builtFor != null &&
        _listEq(_builtFor!, v.matrix) &&
        _builtRatio == ratio &&
        _builtActive.length == active.length &&
        [for (var i = 0; i < active.length; i++) active[i] == _builtActive[i]].every((x) => x)) {
      return;
    }
    _image?.dispose();
    _picture?.dispose();
    _image = null;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    painter.paintStatic(c, v, active: active);
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
    _builtActive = List.of(active);
    _builtRatio = ratio;
  }

  static bool _listEq(Float64List a, Float64List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void render(Canvas canvas) {
    final v = host.boardView;
    if (v == null) return;
    _ensureStatic(v);
    final img = _image;
    if (img != null) {
      final ratio = _builtRatio;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(0, 0, img.width / ratio, img.height / ratio),
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else if (_picture != null) {
      canvas.drawPicture(_picture!);
    }
    canvas.save();
    canvas.transform(v.matrix);
    painter.paintMedallion(canvas, _time);
    painter.paintHighlights(
      canvas,
      time: _time,
      selected: host.selected,
      targets: host.targets,
      isCapture: host.hasPiece,
      lastFrom: host.lastFrom,
      lastTo: host.lastTo,
      checked: host.checkedKings,
    );
    canvas.restore();
  }

  @override
  void onRemove() {
    _image?.dispose();
    _picture?.dispose();
    _image = null;
    _picture = null;
    super.onRemove();
  }
}

/// Ce dont le plateau a besoin du jeu.
abstract class BoardHost {
  BoardGeometry get geometry;
  BoardView? get boardView;
  List<bool> get activePlayers;
  String? get selected;
  Set<String> get targets;
  Set<String> get checkedKings;
  String? get lastFrom;
  String? get lastTo;
  bool hasPiece(String id);
  void handleTap(Offset pos);
}
