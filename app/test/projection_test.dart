import 'dart:io';

import 'package:chesstrio/models/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final geo = BoardGeometry.fromJsonString(File('assets/geometry.json').readAsStringSync());

  test('96 cases chargées', () {
    expect(geo.cells, hasLength(96));
    expect(geo.byId('0e1').index, 4);
    expect(geo.byId('2h4').index, 95);
    expect(geo.outline, hasLength(6));
  });

  for (var viewer = 0; viewer < 3; viewer++) {
    test('le secteur du joueur $viewer est en bas', () {
      final proj = BoardProjection(viewer: viewer);
      // Ordonnée projetée moyenne de chaque secteur.
      final avg = List<double>.filled(3, 0);
      for (final c in geo.cells) {
        avg[c.sector] += proj.project(c.x, c.y).dy / 32;
      }
      final lowest = avg.indexOf(avg.reduce((a, b) => a > b ? a : b));
      expect(lowest, viewer);
      // Une case de la rangée 1 du joueur local est plus basse que toute case d'un autre secteur.
      final mine = geo.byId('${viewer}e1');
      final dy = proj.project(mine.x, mine.y).dy;
      for (final c in geo.cells.where((c) => c.sector != viewer)) {
        expect(dy, greaterThan(proj.project(c.x, c.y).dy));
      }
    });
  }

  test('écrasement vertical et perspective', () {
    final proj = BoardProjection(viewer: 0);
    final pts = [for (final p in geo.outline) proj.projectOffset(p)];
    final w = pts.map((p) => p.dx).reduce((a, b) => a > b ? a : b) -
        pts.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
    final h = pts.map((p) => p.dy).reduce((a, b) => a > b ? a : b) -
        pts.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
    expect(h / w, lessThan(0.6)); // hexagone (0.866) écrasé
    // Le fond est plus petit que le devant.
    expect(proj.scaleAtRotatedY(-1), lessThan(proj.scaleAtRotatedY(1)));
    // Le centre du plateau reste au centre.
    final c = proj.project(0.5, 0.5);
    expect(c.dx.abs(), lessThan(1e-9));
    expect(c.dy.abs(), lessThan(1e-9));
  });
}
