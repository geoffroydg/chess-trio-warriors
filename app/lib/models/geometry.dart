import 'dart:convert';
import 'dart:math' as math;
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
      );
}

class BoardGeometry {
  BoardGeometry(this.outline, this.cells);
  final List<Offset> outline;
  final List<CellGeom> cells;

  CellGeom byId(String id) => cells[cellIndexOf(id)];

  static int cellIndexOf(String id) =>
      (id.codeUnitAt(0) - 48) * 32 + (id.codeUnitAt(2) - 49) * 8 + (id.codeUnitAt(1) - 97);

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
    );
  }

  static Future<BoardGeometry> load() async =>
      BoardGeometry.fromJsonString(await rootBundle.loadString('assets/geometry.json'));
}

/// Projection « vue 2D inclinée » : rotation du plateau (le joueur [viewer] en bas),
/// écrasement vertical [squash] et mise à l'échelle selon la profondeur.
///
/// Espace de sortie : x dans [-1, 1], y dans ≈ [-squash, squash], y vers le bas.
class BoardProjection {
  const BoardProjection({required this.viewer, this.squash = 0.6, this.depth = 0.28});
  final int viewer;
  final double squash;

  /// Réduction maximale de l'échelle tout au fond du plateau (0 = pas de perspective).
  final double depth;

  /// Coordonnées normalisées du plateau (0..1) -> repère tourné (-1..1, y vers le bas).
  Offset rotate(double nx, double ny) {
    final dx = (nx - 0.5) * 2;
    final dy = (ny - 0.5) * 2;
    final a = viewer * 2 * math.pi / 3;
    final c = math.cos(a);
    final s = math.sin(a);
    return Offset(dx * c - dy * s, dx * s + dy * c);
  }

  /// Facteur d'échelle de perspective pour une ordonnée tournée [ry] (1 = devant, -1 = fond).
  double scaleAtRotatedY(double ry) => 1 - depth * (1 - ry) / 2;

  Offset project(double nx, double ny) {
    final r = rotate(nx, ny);
    final f = scaleAtRotatedY(r.dy);
    return Offset(r.dx * f, r.dy * squash * f);
  }

  /// Échelle de perspective à l'endroit d'un point du plateau.
  double scaleAt(double nx, double ny) => scaleAtRotatedY(rotate(nx, ny).dy);

  Offset projectOffset(Offset p) => project(p.dx, p.dy);
}
