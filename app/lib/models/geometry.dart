import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

class CellGeom {
  CellGeom({
    required this.id,
    required this.index,
    required this.sector,
    required this.file,
    required this.rank,
    required this.x,
    required this.y,
    required this.polygon,
    required this.light,
    this.ring = 0,
    this.wedge = 0,
    this.angle = 0,
    this.a0 = 0,
    this.a1 = 0,
    this.r0 = 0,
    this.r1 = 0,
  });
  final String id;
  final int index;
  final int sector;
  final int file;
  final int rank;
  final double x;
  final double y;
  final List<Offset> polygon;
  final bool light;

  /// Plateau rond : anneau (1 = extérieur), secteur angulaire 0..23, angles en degrés
  /// (sens trigonométrique vu à l'écran) et rayons normalisés du secteur annulaire.
  final int ring;
  final int wedge;
  final double angle;
  final double a0;
  final double a1;
  final double r0;
  final double r1;

  factory CellGeom.fromJson(Map<String, dynamic> j) => CellGeom(
        id: j['id'] as String,
        index: j['index'] as int,
        sector: j['sector'] as int,
        file: j['file'] as int,
        rank: j['rank'] as int,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        polygon: (j['polygon'] as List)
            .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
            .toList(),
        light: (j['light'] ?? false) as bool,
        ring: (j['ring'] ?? 0) as int,
        wedge: (j['wedge'] ?? 0) as int,
        angle: ((j['angle'] ?? 0) as num).toDouble(),
        a0: ((j['a0'] ?? 0) as num).toDouble(),
        a1: ((j['a1'] ?? 0) as num).toDouble(),
        r0: ((j['r0'] ?? 0) as num).toDouble(),
        r1: ((j['r1'] ?? 0) as num).toDouble(),
      );
}

/// Épée posée sur une frontière entre deux équipes : poignée sur l'anneau 1, lame sur les
/// anneaux 2-3 (rayons normalisés).
class SwordGeom {
  const SwordGeom({
    required this.border,
    required this.teams,
    required this.angle,
    required this.hiltR0,
    required this.hiltR1,
    required this.bladeR0,
    required this.bladeR1,
  });
  final int border;
  final List<int> teams;
  final double angle;
  final double hiltR0, hiltR1, bladeR0, bladeR1;

  factory SwordGeom.fromJson(Map<String, dynamic> j) {
    double d(Map m, String k) => (m[k] as num).toDouble();
    final h = j['hilt'] as Map, b = j['blade'] as Map;
    return SwordGeom(
      border: j['border'] as int,
      teams: [for (final t in j['teams'] as List) t as int],
      angle: (j['angle'] as num).toDouble(),
      hiltR0: d(h, 'r0'),
      hiltR1: d(h, 'r1'),
      bladeR0: d(b, 'r0'),
      bladeR1: d(b, 'r1'),
    );
  }
}

class BoardGeometry {
  BoardGeometry(this.outline, this.cells,
      {this.round = false,
      this.rings = const [],
      this.medallion = 0,
      this.radius = 0.5,
      this.swords = const []});

  /// Les 3 épées (frontières entre équipes).
  final List<SwordGeom> swords;
  final List<Offset> outline;
  final List<CellGeom> cells;

  /// Plateau rond (disque de centre (0.5, 0.5) et de rayon [radius]).
  final bool round;

  /// Rayons des bords d'anneaux, de l'extérieur vers le médaillon (normalisés).
  final List<double> rings;
  final double medallion;
  final double radius;

  CellGeom byId(String id) => cells[cellIndexOf(id)];

  /// "0d1" (équipe, colonne a-h, anneau 1-6) -> index 0..143.
  static int cellIndexOf(String id) =>
      (id.codeUnitAt(0) - 48) * 48 + (id.codeUnitAt(2) - 49) * 8 + (id.codeUnitAt(1) - 97);

  /// Nombre d'anneaux de cases.
  int get ringCount => rings.isEmpty ? 0 : rings.length - 1;

  factory BoardGeometry.fromJsonString(String s) {
    final j = json.decode(s) as Map<String, dynamic>;
    final cells = (j['cells'] as List)
        .map((c) => CellGeom.fromJson(c as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return BoardGeometry(
      (j['outline'] as List)
          .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(),
      cells,
      round: j['shape'] == 'round',
      rings: [for (final r in (j['rings'] as List? ?? const [])) (r as num).toDouble()],
      medallion: ((j['medallion'] ?? 0) as num).toDouble(),
      radius: ((j['radius'] ?? 0.5) as num).toDouble(),
      swords: [
        for (final w in (j['swords'] as List? ?? const [])) SwordGeom.fromJson(w as Map<String, dynamic>)
      ],
    );
  }

  static Future<BoardGeometry> load() async =>
      BoardGeometry.fromJsonString(await rootBundle.loadString('assets/geometry.json'));
}

/// Projection « vue inclinée » : rotation du plateau (le joueur [viewer] en bas), puis
/// vraie perspective d'un plan posé sur une table (homographie) : écrasement vertical
/// [squash] et grossissement de ce qui est devant ([tilt] > 0). Un cercle reste une ellipse.
///
/// Espace de sortie : x ≈ [-1, 1], y ≈ [-squash, squash], y vers le bas ; le centre du
/// plateau est à l'origine.
class BoardProjection {
  const BoardProjection({required this.viewer, this.squash = 0.62, this.tilt = 0.13});
  final int viewer;
  final double squash;

  /// Force de la perspective : rapport d'échelle avant/fond = (1 + tilt) / (1 - tilt).
  final double tilt;

  /// Angle de rotation (radians, sens trigonométrique vu à l'écran) : sur le plateau rond,
  /// le joueur 1 est en haut à gauche (150°) et le joueur 2 en haut à droite (30°) ;
  /// tourner de viewer × 120° amène le joueur [viewer] en bas (270°).
  double get angle => viewer * 2 * math.pi / 3;

  /// Coordonnées normalisées du plateau (0..1) -> repère tourné (-1..1, y vers le bas).
  Offset rotate(double nx, double ny) {
    final dx = (nx - 0.5) * 2;
    final dy = (ny - 0.5) * 2;
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(dx * c + dy * s, -dx * s + dy * c);
  }

  /// Facteur d'échelle de perspective pour une ordonnée tournée [ry] (1 = devant, -1 = fond).
  double scaleAtRotatedY(double ry) => 1 / (1 - tilt * ry);

  Offset project(double nx, double ny) {
    final r = rotate(nx, ny);
    final f = scaleAtRotatedY(r.dy);
    return Offset(r.dx * f, r.dy * squash * f);
  }

  /// Échelle de perspective à l'endroit d'un point du plateau.
  double scaleAt(double nx, double ny) => scaleAtRotatedY(rotate(nx, ny).dy);

  Offset projectOffset(Offset p) => project(p.dx, p.dy);

  /// Même transformation sous forme de matrice 4×4 (colonnes, pour Canvas.transform) :
  /// coordonnées normalisées du plateau -> espace projeté.
  Float64List matrix() {
    final c = math.cos(angle);
    final s = math.sin(angle);
    // Rotation + centrage : (x, y) -> (rx, ry) = R·(2x - 1, 2y - 1).
    final ax = 2 * c, bx = 2 * s, cx = -c - s; // rx = ax·x + bx·y + cx
    final ay = -2 * s, by = 2 * c, cy = s - c; // ry = ay·x + by·y + cy
    // Sortie : X = rx / w, Y = squash·ry / w, w = 1 - tilt·ry.
    return Float64List.fromList([
      ax, squash * ay, 0, -tilt * ay, //
      bx, squash * by, 0, -tilt * by, //
      0, 0, 1, 0, //
      cx, squash * cy, 0, 1 - tilt * cy, //
    ]);
  }
}
