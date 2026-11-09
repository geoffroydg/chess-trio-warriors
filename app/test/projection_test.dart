import 'dart:io';
import 'dart:math' as math;

import 'package:chesstrio/models/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final geo = BoardGeometry.fromJsonString(File('assets/geometry.json').readAsStringSync());

  test('96 cases chargées, plateau rond', () {
    expect(geo.cells, hasLength(96));
    expect(geo.byId('0e1').index, 4);
    expect(geo.byId('2h4').index, 95);
    expect(geo.round, isTrue);
    expect(geo.rings, hasLength(5));
    expect(geo.medallion, closeTo(0.11, 0.01));
    expect(geo.outline.length, greaterThan(48));
    for (final c in geo.cells) {
      expect(c.ring, c.rank);
      expect(c.polygon.length, 16);
    }
  });

  for (var viewer = 0; viewer < 3; viewer++) {
    test('le secteur du joueur $viewer est en bas', () {
      final proj = BoardProjection(viewer: viewer);
      final avg = List<double>.filled(3, 0);
      for (final c in geo.cells) {
        avg[c.sector] += proj.project(c.x, c.y).dy / 32;
      }
      final lowest = avg.indexOf(avg.reduce((a, b) => a > b ? a : b));
      expect(lowest, viewer);
      // Les cases d1/e1 du joueur local sont tout en bas, centrées.
      for (final f in ['d', 'e']) {
        final mine = geo.byId('$viewer${f}1');
        final p = proj.project(mine.x, mine.y);
        for (final c in geo.cells.where((c) => c.sector != viewer)) {
          expect(p.dy, greaterThan(proj.project(c.x, c.y).dy));
        }
        expect(p.dx.abs(), lessThan(0.2));
      }
      // a à gauche, h à droite pour le joueur local.
      expect(proj.project(geo.byId('${viewer}a1').x, geo.byId('${viewer}a1').y).dx,
          lessThan(proj.project(geo.byId('${viewer}h1').x, geo.byId('${viewer}h1').y).dx));
    });
  }

  test('écrasement vertical (~0,62) et perspective', () {
    final proj = BoardProjection(viewer: 0);
    final pts = [for (final p in geo.outline) proj.projectOffset(p)];
    final w = pts.map((p) => p.dx).reduce(math.max) - pts.map((p) => p.dx).reduce(math.min);
    final h = pts.map((p) => p.dy).reduce(math.max) - pts.map((p) => p.dy).reduce(math.min);
    expect(h / w, closeTo(0.62, 0.04));
    expect(proj.scaleAtRotatedY(-1), lessThan(proj.scaleAtRotatedY(1)));
    final c = proj.project(0.5, 0.5);
    expect(c.dx.abs(), lessThan(1e-9));
    expect(c.dy.abs(), lessThan(1e-9));
  });

  test('la matrice 4×4 donne la même projection que project()', () {
    for (var viewer = 0; viewer < 3; viewer++) {
      final proj = BoardProjection(viewer: viewer);
      final m = proj.matrix();
      for (final c in geo.cells) {
        final x = m[0] * c.x + m[4] * c.y + m[12];
        final y = m[1] * c.x + m[5] * c.y + m[13];
        final w = m[3] * c.x + m[7] * c.y + m[15];
        final p = proj.project(c.x, c.y);
        expect(x / w, closeTo(p.dx, 1e-9));
        expect(y / w, closeTo(p.dy, 1e-9));
      }
    }
  });
}
