import 'dart:io';
import 'dart:ui' as ui;

import 'package:chesstrio/game/chess_game.dart';
import 'package:chesstrio/game/round_board.dart';
import 'package:chesstrio/models/geometry.dart';
import 'package:chesstrio/models/protocol.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Position initiale : rangée 1 = T C F D R F C T, rangée 2 = pions, pour les 3 joueurs.
GameMsg initialMsg({List<Map<String, String>> legal = const [], Map<String, dynamic>? event}) {
  const back = ['R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R'];
  final board = List<Map<String, dynamic>?>.filled(96, null);
  for (var s = 0; s < 3; s++) {
    for (var f = 0; f < 8; f++) {
      board[s * 32 + f] = {'type': back[f], 'owner': s};
      board[s * 32 + 8 + f] = {'type': 'P', 'owner': s};
    }
  }
  return GameMsg.fromJson({
    'state': {
      'mode': 'firstMate',
      'board': board,
      'turn': 0,
      'active': [true, true, true],
      'ply': 0,
      'eliminations': [],
    },
    'lastEvent': event,
    'turn': 0,
    'legalMoves': legal,
    'turnDeadline': 1,
    'over': false,
    'players': [],
  });
}

void main() {
  final geo = BoardGeometry.fromJsonString(File('assets/geometry.json').readAsStringSync());

  testWidgets('hit-test par polygone : chaque centre de case renvoie sa case', (tester) async {
    for (var viewer = 0; viewer < 3; viewer++) {
      final game = ChessGame(geometry: geo, viewer: viewer);
      await tester.pumpWidget(MaterialApp(
          home: SizedBox(width: 420, height: 600, child: GameWidget(game: game))));
      await tester.pump();
      for (final c in geo.cells) {
        final p = game.cellPosition(c.id);
        expect(game.cellAt(Offset(p.x, p.y)), c.id);
      }
      // Hors du disque : rien.
      expect(game.cellAt(const Offset(2, 2)), isNull);
      // Médaillon : aucune case (le centre exact n'est dans aucun secteur).
      final mid = game.boardView!.toScreen(0.5, 0.5);
      expect(geo.cells.any((c) => game.cellAt(mid) == c.id && c.ring != 4), isFalse);
      // Le joueur local est en bas de l'écran.
      final mine = game.cellPosition('${viewer}e1').y;
      for (final c in geo.cells.where((c) => c.sector != viewer)) {
        expect(mine, greaterThan(game.cellPosition(c.id).y));
      }
      // Les pièces du devant sont plus grandes que celles du fond.
      final far = geo.cells.where((c) => c.sector != viewer && c.rank == 1).first.id;
      expect(game.pieceRadius('${viewer}e1'), greaterThan(game.pieceRadius(far)));
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('polygones projetés sans chevauchement (échantillonnage)', (tester) async {
    final game = ChessGame(geometry: geo, viewer: 1);
    await tester.pumpWidget(MaterialApp(home: SizedBox(width: 400, height: 560, child: GameWidget(game: game))));
    await tester.pump();
    final b = game.boardView!;
    for (var i = 0; i < 1500; i++) {
      final a = i * 2.39996;
      final rho = 0.5 * (i + 0.5) / 1500;
      final p = b.toScreen(0.5 + rho * cosT(a), 0.5 - rho * sinT(a));
      var n = 0;
      for (final poly in game.screenPolygons) {
        if (insidePoly(poly, p)) n++;
      }
      expect(n, lessThanOrEqualTo(1));
    }
  });

  testWidgets('capture du plateau rond (position initiale, coups légaux)', (tester) async {
    tester.view.physicalSize = const Size(1080, 1500);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
    final font = File('$root/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf');
    if (Platform.environment['CAPTURE_DIR'] != null && font.existsSync()) {
      await tester.runAsync(() async {
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await loader.load();
      });
    }
    final game = ChessGame(geometry: geo, viewer: 0);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            backgroundColor: const Color(0xFF0B1022),
            body: RepaintBoundary(key: key, child: GameWidget(game: game)))));
    await tester.pump();
    game.applyGame(
        initialMsg(legal: [
          {'from': '0g1', 'to': '0f3'},
          {'from': '0g1', 'to': '0h3'},
        ]),
        0);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final p = game.cellPosition('0g1');
    game.handleTap(Offset(p.x, p.y));
    expect(game.selected, '0g1');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final dir = Platform.environment['CAPTURE_DIR'];
    if (dir == null) return;
    await tester.runAsync(() async {
      final rb = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await rb.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/plateau_rond.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });

  test('chemins exacts des cases', () {
    final painter = RoundBoardPainter(geo);
    for (final c in geo.cells) {
      expect(painter.paths[c.index].contains(Offset(c.x, c.y)), isTrue, reason: c.id);
    }
  });
}

double cosT(double a) => _c(a);
double sinT(double a) => _c(a - 1.5707963267948966);
double _c(double a) {
  return ui.Offset.fromDirection(a).dx;
}

bool insidePoly(List<Offset> poly, Offset p) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}
