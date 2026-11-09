import 'dart:io';
import 'dart:ui' as ui;

import 'package:chesstrio/game/chess_game.dart';
import 'package:chesstrio/game/perf.dart';
import 'package:chesstrio/game/warrior_atlas.dart';
import 'package:chesstrio/game/warrior_piece.dart';
import 'package:chesstrio/models/geometry.dart';
import 'package:chesstrio/models/protocol.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'round_board_test.dart' show initialMsg;

/// Image complète hors pipeline Flutter (mise à jour + dessin enregistré).
void _frame(ChessGame game) {
  game.update(1 / 60);
  final rec = ui.PictureRecorder();
  game.render(Canvas(rec));
  rec.endRecording().dispose();
}

Future<ChessGame> _game(WidgetTester tester, BoardGeometry geo) async {
  final game = ChessGame(geometry: geo, viewer: 0);
  await tester.pumpWidget(MaterialApp(
      home: Center(child: SizedBox(width: 420, height: 640, child: GameWidget(game: game, key: UniqueKey())))));
  await tester.pump();
  game.applyGame(initialMsg(), 0);
  await tester.pump();
  return game;
}

List<WarriorPiece> _warriors(ChessGame g) => g.worldLayer.children.whereType<WarriorPiece>().toList();

void main() {
  final geo = BoardGeometry.fromJsonString(File('assets/geometry.json').readAsStringSync());
  tearDown(() => PerfConfig.setAll(true));

  group('culling', () {
    testWidgets('pièce hors champ : ni dessinée ni mise à jour à chaque image', (tester) async {
      PerfConfig.spriteCache = false; // tout en vectoriel : on observe les rendus propres
      final game = await _game(tester, geo);
      _frame(game);
      final all = _warriors(game);
      expect(all.length, 48);
      expect(all.where((p) => p.culled), isEmpty, reason: 'vue entière : tout est visible');

      // Zoom fort sur le camp du bas-gauche.
      game.boardCamera.zoomAt(const Offset(60, 560), 3.5);
      _frame(game);
      final hidden = all.where((p) => p.culled).toList();
      final shown = all.where((p) => !p.culled).toList();
      expect(hidden, isNotEmpty);
      expect(shown, isNotEmpty);
      final r = game.cullRect!;
      for (final p in hidden) {
        expect(r.contains(Offset(p.position.x, p.position.y)), isFalse);
      }
      final renders = {for (final p in all) p: p.renderCount};
      final updates = {for (final p in all) p: p.rigUpdates};
      for (var i = 0; i < 32; i++) {
        _frame(game);
      }
      for (final p in hidden) {
        expect(p.renderCount, renders[p], reason: 'pièce hors champ dessinée');
        expect(p.rigUpdates - updates[p]!, lessThanOrEqualTo(2), reason: 'rig hors champ mis à jour à basse fréquence');
      }
      for (final p in shown) {
        expect(p.renderCount - renders[p]!, 32);
        expect(p.rigUpdates - updates[p]!, 32);
      }

      // Particules émises hors champ : ignorées ; dans le champ : conservées.
      final pool = game.pool;
      final far = hidden.first.position;
      final before = pool.aliveCount;
      pool.burst(far.x, far.y, 20, 10, 2, const Color(0xFFFFFFFF));
      expect(pool.aliveCount, before);
      final near = r.center;
      pool.burst(near.dx, near.dy, 20, 10, 2, const Color(0xFFFFFFFF));
      expect(pool.aliveCount, before + 20);

      // Retour à la vue entière : tout redevient visible.
      game.boardCamera.zoomAt(const Offset(60, 560), 1);
      _frame(game);
      expect(all.where((p) => p.culled), isEmpty);
    });

    testWidgets('sans culling (réglage coupé) : toutes les pièces sont dessinées', (tester) async {
      PerfConfig.spriteCache = false;
      PerfConfig.culling = false;
      final game = await _game(tester, geo);
      game.boardCamera.zoomAt(const Offset(60, 560), 3.5);
      _frame(game);
      final all = _warriors(game);
      final n0 = all.fold<int>(0, (s, p) => s + p.renderCount);
      _frame(game);
      expect(all.fold<int>(0, (s, p) => s + p.renderCount) - n0, 48);
    });
  });

  group('atlas de sprites', () {
    test('plafonds : 2048 px, 8 Mo par palier, 8 images IDLE', () {
      for (var t = 0; t < atlasTiers.length; t++) {
        final p = WarriorAtlas.planFor(t);
        expect(p.width, lessThanOrEqualTo(2048), reason: 'palier $t');
        expect(p.height, lessThanOrEqualTo(2048), reason: 'palier $t');
        expect(p.bytes, lessThanOrEqualTo(8 * 1024 * 1024), reason: 'palier $t');
        expect(atlasTiers[t].frames, 8);
        // ignore: avoid_print
        print('palier $t : ${p.width}×${p.height} px, ${(p.bytes / 1048576).toStringAsFixed(1)} Mo');
      }
    });

    testWidgets('construction répartie sur plusieurs images, puis changement de palier sans trou',
        (tester) async {
      await tester.runAsync(() async {
        final atlas = WarriorAtlas();
        var steps = 0;
        while (atlas.ready == null && steps < 2000) {
          atlas.update(needPpu: 30, outlinePx: 14, moving: false);
          steps++;
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        final a0 = atlas.ready!;
        expect(steps, greaterThan(3), reason: 'pré-rendu réparti sur plusieurs images');
        expect(a0.tier, 0);
        expect(a0.frames, atlasTiers[0].frames);
        expect(a0.image.width, lessThanOrEqualTo(atlasMaxTexture));
        expect(a0.image.height, lessThanOrEqualTo(atlasMaxTexture));
        // Les cellules sont dans l'image et non vides (corps d'un roi rouge).
        final cell = a0.idle(PieceType.king, 1, 3) * 6;
        expect(a0.cells[cell + 2], lessThanOrEqualTo(a0.image.width.toDouble()));
        final bytes = (await a0.image.toByteData())!;
        var opaque = 0;
        for (var y = a0.cells[cell + 1].toInt(); y < a0.cells[cell + 3].toInt(); y++) {
          for (var x = a0.cells[cell].toInt(); x < a0.cells[cell + 2].toInt(); x++) {
            if (bytes.getUint8((y * a0.image.width + x) * 4 + 3) > 200) opaque++;
          }
        }
        expect(opaque, greaterThan(100));

        // Pendant un geste : pas de nouveau palier.
        atlas.update(needPpu: 40, outlinePx: 14, moving: true);
        expect(atlas.building, isFalse);
        // À l'arrêt : palier supérieur construit en arrière-plan, l'ancien reste affiché.
        atlas.update(needPpu: 40, outlinePx: 14, moving: false);
        expect(atlas.buildingTier, 1);
        expect(atlas.ready, same(a0));
        steps = 0;
        while (atlas.ready == a0 && steps < 2000) {
          atlas.update(needPpu: 40, outlinePx: 14, moving: false);
          expect(atlas.ready, isNotNull);
          steps++;
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(atlas.ready!.tier, 1);
        expect(atlas.ready!.ppu, greaterThan(a0.ppu));
        expect(atlas.builds, 2);
        atlas.dispose();
      });
    });

    testWidgets('en jeu : guerriers au repos en un lot, pièce sélectionnée en vectoriel', (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final game = await _game(tester, geo);
      await tester.runAsync(() async {
        for (var i = 0; i < 2000 && game.atlas.ready == null; i++) {
          _frame(game);
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });
      expect(game.atlas.ready, isNotNull);
      _frame(game);
      _frame(game);
      final all = _warriors(game);
      expect(game.batchLayer.drawn, 48);
      expect(game.batchLayer.calls, lessThanOrEqualTo(8), reason: 'quelques appels drawAtlas pour 48 guerriers');
      final n0 = all.fold<int>(0, (s, p) => s + p.renderCount);
      _frame(game);
      expect(all.fold<int>(0, (s, p) => s + p.renderCount), n0, reason: 'aucun rendu vectoriel au repos');

      // Une pièce sélectionnée (animation active) repasse en rendu vectoriel complet.
      final p = all.first;
      p.setSelected(true);
      _frame(game);
      expect(p.batched, isFalse);
      final r0 = p.renderCount;
      _frame(game);
      expect(p.renderCount, r0 + 1);
      expect(game.batchLayer.drawn, 47);
      p.setSelected(false);

      // Application en arrière-plan : atlas libéré.
      game.lifecycleStateChange(AppLifecycleState.paused);
      expect(game.atlas.ready, isNull);
      expect(game.atlas.building, isFalse);
    });
  });

  testWidgets('plateau : tuiles haute résolution asynchrones à l\'arrêt, plafonnées', (tester) async {
    final game = await _game(tester, geo);
    await tester.runAsync(() async {
      for (var i = 0; i < 400 && !game.board.baseCached; i++) {
        _frame(game);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(game.board.baseCached, isTrue);
      final cam = game.boardCamera;
      final builds0 = game.board.tileBuilds;
      cam.gestureActive = true;
      cam.zoomAt(const Offset(210, 320), 3);
      for (var i = 0; i < 10; i++) {
        _frame(game);
      }
      expect(game.board.tileBuilds, builds0, reason: 'pendant le geste : simple transformation');
      cam.gestureActive = false;
      for (var i = 0; i < 300 && (game.board.tileCount == 0 || game.board.tilesPending); i++) {
        _frame(game);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(game.board.tileBuilds, builds0 + 1);
      expect(game.board.tileCount, greaterThan(0));
    });
  });
}
