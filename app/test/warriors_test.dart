import 'dart:io';
import 'dart:ui' as ui;

import 'package:chesstrio/game/attacks.dart';
import 'package:chesstrio/game/gallery_game.dart';
import 'package:chesstrio/game/warrior_piece.dart';
import 'package:chesstrio/models/protocol.dart';
import 'package:chesstrio/screens/gallery_screen.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _advance(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['CAPTURE_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('galerie : 18 guerriers, toutes les attaques, états, sans exception', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final game = GalleryGame();
    final captures = <String>[];
    game.onCapture = (a, v) => captures.add('${a.name}>${v.name}');
    await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(key: key, child: GameWidget(game: game))));
    await tester.pump();
    await tester.pump();
    expect(game.grid.length, 18);
    await _advance(tester, 600);
    await _capture(tester, key, 'galerie');

    game.toggleSelected();
    game.toggleCheck();
    await _advance(tester, 400);
    await _capture(tester, key, 'galerie_selection_echec');
    game.toggleSelected();
    game.toggleCheck();
    game.toggleFrozen();
    await _advance(tester, 300);
    await _capture(tester, key, 'galerie_gel');
    game.toggleFrozen();

    for (final t in galleryOrder) {
      game.playAttack(t);
      await _advance(tester, 350);
      await _capture(tester, key, 'attaque_${t.name}_1');
      await _advance(tester, 250);
      await _capture(tester, key, 'attaque_${t.name}_2');
      await _advance(tester, 1800);
    }
    expect(captures.length, galleryOrder.length);
    expect(game.hitstopCount, galleryOrder.length);
    expect(game.shakeCount, galleryOrder.length);

    game.showCheck();
    await _advance(tester, 500);
    await _capture(tester, key, 'echec');
    game.showMate();
    await _advance(tester, 400);
    await _capture(tester, key, 'mat');
    await _advance(tester, 2500);
    expect(game.pool.aliveCount, lessThan(game.pool.capacity));
  });

  testWidgets('galerie : chaque état d\'animation sur les 18 guerriers', (tester) async {
    final game = GalleryGame();
    await tester.pumpWidget(MaterialApp(home: SizedBox(width: 450, height: 800, child: GameWidget(game: game))));
    await tester.pump();
    await tester.pump();
    for (final s in AnimState.values) {
      game.playState(s);
      await _advance(tester, 100);
      for (final p in game.grid) {
        expect(p.rig.isFinite, isTrue);
        if (s != AnimState.hit) expect(p.animState, s, reason: s.name);
      }
      await _advance(tester, 2600);
      for (final p in game.grid) {
        expect(p.isMounted, isTrue); // la galerie ne retire pas les guerriers K.-O.
      }
    }
    game.playState(AnimState.idle);
    await _advance(tester, 300);
    expect(game.grid.every((p) => p.animState == AnimState.idle && p.alpha == 1), isTrue);
  });

  testWidgets('saut d\'une attaque par finish()', (tester) async {
    final game = GalleryGame();
    await tester.pumpWidget(MaterialApp(home: SizedBox(width: 400, height: 700, child: GameWidget(game: game))));
    await tester.pump();
    await tester.pump();
    game.playAttack(PieceType.rook);
    await _advance(tester, 100);
    game.finishAttack();
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.stageVictim!.isMounted, isFalse);
    await _advance(tester, 2000);
  });

  testWidgets('écran galerie et boutons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GalleryScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Séisme'), findsOneWidget);
    for (final label in ['Repos', 'Marche', 'Saut', 'Attaque', 'Touché', 'K.-O.', 'Victoire', 'Pétrifié', 'Rayon', 'Rafale', 'Coup de pied', 'Séisme', 'Combo', 'Vague', 'Sélection', 'Gel', 'ÉCHEC', 'MAT']) {
      final f = find.textContaining(label);
      await tester.ensureVisible(f.first);
      await tester.tap(f.first);
      await _advance(tester, 300);
    }
    await _advance(tester, 2500);
    expect(attackName(PieceType.pawn), isNotEmpty);
    expect(WarriorPiece(type: PieceType.king, owner: 1, cellId: '0a1').type, PieceType.king);
  });
}
