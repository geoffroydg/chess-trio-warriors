import 'dart:io';

import 'package:chesstrio/game/board_camera.dart';
import 'package:chesstrio/game/chess_game.dart';
import 'package:chesstrio/game/game_view.dart';
import 'package:chesstrio/models/geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final geo = BoardGeometry.fromJsonString(File('assets/geometry.json').readAsStringSync());

  group('BoardCamera', () {
    BoardCamera cam() => BoardCamera()
      ..setViewport(const Size(400, 600), const Rect.fromLTWH(10, 100, 380, 400));

    test('écran <-> monde sont réciproques à tout zoom/pan', () {
      final c = cam();
      c.zoomAt(const Offset(200, 300), 2.5);
      c.panBy(const Offset(-60, 40));
      for (final p in const [Offset(0, 0), Offset(123, 456), Offset(399, 599)]) {
        final back = c.toScreen(c.toWorld(p));
        expect((back - p).distance, lessThan(1e-9));
      }
    });

    test('le zoom est borné à x1..x3,5 et centré sur le point entre les doigts', () {
      final c = cam();
      const f = Offset(250, 350);
      final w = c.toWorld(f);
      c.zoomAt(f, 2);
      expect((c.toScreen(w) - f).distance, lessThan(1e-9));
      c.zoomAt(f, 10);
      expect(c.zoom, BoardCamera.maxZoom);
      c.zoomAt(f, 0.1);
      expect(c.zoom, 1);
      expect(c.pan, Offset.zero);
    });

    test('le plateau ne sort pas de l\'écran', () {
      final c = cam();
      c.zoomAt(const Offset(200, 300), 3);
      c.panBy(const Offset(5000, 5000));
      expect(c.toScreen(c.content.topLeft).dx, lessThanOrEqualTo(1e-9));
      expect(c.toScreen(c.content.topLeft).dy, lessThanOrEqualTo(1e-9));
      c.panBy(const Offset(-50000, -50000));
      expect(c.toScreen(c.content.bottomRight).dx, greaterThanOrEqualTo(400 - 1e-9));
      expect(c.toScreen(c.content.bottomRight).dy, greaterThanOrEqualTo(600 - 1e-9));
    });

    test('double tap : zoom x2,2 sur le point puis retour à la vue entière', () {
      final c = cam();
      const f = Offset(300, 200);
      final w = c.toWorld(f);
      c.doubleTap(f);
      expect(c.animating, isTrue);
      for (var i = 0; i < 20; i++) {
        c.update(0.02);
      }
      expect(c.animating, isFalse);
      expect(c.zoom, closeTo(BoardCamera.doubleTapZoom, 1e-9));
      // Le point touché reste (à la bordure près) sous le doigt.
      final s = c.toScreen(w);
      expect((s - f).distance, lessThan(40));
      c.doubleTap(const Offset(10, 10));
      for (var i = 0; i < 20; i++) {
        c.update(0.02);
      }
      expect(c.zoom, 1);
      expect(c.pan, Offset.zero);
    });

    test('inertie : continue puis s\'arrête', () {
      final c = cam()..zoomAt(const Offset(200, 300), 3);
      final p0 = c.pan;
      c.fling(const Offset(-800, 0));
      c.update(0.016);
      expect(c.pan.dx, lessThan(p0.dx));
      for (var i = 0; i < 600; i++) {
        c.update(0.016);
      }
      expect(c.inertia, isFalse);
    });
  });

  group('ChessGame zoomé', () {
    testWidgets('hit-test cohérent à plusieurs zooms et panoramiques', (tester) async {
      final game = ChessGame(geometry: geo, viewer: 0);
      await tester.pumpWidget(MaterialApp(
          home: SizedBox(width: 420, height: 600, child: ChessGameView(game: game))));
      await tester.pump();
      for (final (z, d) in [(1.0, Offset.zero), (2.0, const Offset(-40, 25)), (3.5, const Offset(80, -60))]) {
        game.boardCamera.zoomAt(const Offset(210, 300), z);
        game.boardCamera.panBy(d);
        await tester.pump();
        var visible = 0;
        for (final c in geo.cells) {
          final p = game.cellPosition(c.id);
          final o = Offset(p.x, p.y);
          if (o.dx < 0 || o.dy < 0 || o.dx > 420 || o.dy > 600) continue;
          visible++;
          expect(game.cellAt(o), c.id, reason: 'zoom $z ${c.id}');
        }
        expect(visible, greaterThan(10));
        // Le monde est bien transformé par la caméra.
        expect(game.worldLayer.scale.x, closeTo(game.boardCamera.zoom, 1e-9));
        expect(game.boardView!.scale, closeTo(game.scale * game.boardCamera.zoom, 1e-9));
      }
    });

    testWidgets('pincer, glisser, tap court et double tap', (tester) async {
      final game = ChessGame(geometry: geo, viewer: 0);
      await tester.pumpWidget(MaterialApp(
          home: SizedBox(width: 420, height: 600, child: ChessGameView(game: game))));
      await tester.pump();
      final cam = game.boardCamera;
      // Pincement à deux doigts.
      final a = await tester.startGesture(const Offset(180, 300), pointer: 1);
      final b = await tester.startGesture(const Offset(240, 300), pointer: 2);
      await a.moveTo(const Offset(120, 300));
      await b.moveTo(const Offset(300, 300));
      await a.up();
      await b.up();
      await tester.pump();
      expect(cam.zoom, closeTo(3.0, 0.01));
      expect(game.zoomed.value, isTrue);
      // Glissé : panoramique, pas de sélection.
      final before = cam.pan;
      final g = await tester.startGesture(const Offset(200, 300));
      await g.moveBy(const Offset(4, 0)); // sous le seuil : ignoré
      expect(cam.pan, before);
      await g.moveBy(const Offset(30, 0));
      await g.moveBy(const Offset(20, 0));
      await g.up();
      expect(cam.pan.dx, greaterThan(before.dx));
      cam.stop();
      // Double tap : retour à la vue entière.
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(cam.zoom, 1);
      expect(game.zoomed.value, isFalse);
    });
  });
}
