import 'dart:io';

import 'package:chesstrio/game/chess_game.dart';
import 'package:chesstrio/models/geometry.dart';
import 'package:chesstrio/models/protocol.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GameMsg _msg(int ply, Map<int, Map<String, dynamic>> pieces,
    {Map<String, dynamic>? event, List<Map<String, String>> legal = const []}) {
  return GameMsg.fromJson({
    'state': {
      'mode': 'firstMate',
      'board': List.generate(96, (i) => pieces[i]),
      'turn': 0,
      'active': [true, true, true],
      'ply': ply,
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
  testWidgets('plateau Flame : sélection, coup, animation et prise', (tester) async {
    final geo = BoardGeometry.fromJsonString(File('assets/geometry.json').readAsStringSync());
    String? moved;
    final game = ChessGame(geometry: geo, viewer: 0, onMove: (f, t) => moved = '$f$t');
    await tester.pumpWidget(MaterialApp(
        home: SizedBox(width: 400, height: 400, child: GameWidget(game: game))));
    await tester.pump();
    final a = geo.byId('0e2').index;
    final b = geo.byId('0e4').index;
    game.applyGame(
        _msg(0, {a: {'type': 'P', 'owner': 0}, b: {'type': 'P', 'owner': 1}},
            legal: [
              {'from': '0e2', 'to': '0e4'}
            ]),
        0);
    await tester.pump();
    await tester.pump();
    final p = game.cellPosition('0e2');
    game.handleTap(Offset(p.x, p.y));
    expect(game.selected, '0e2');
    expect(game.targets, {'0e4'});
    final q = game.cellPosition('0e4');
    game.handleTap(Offset(q.x, q.y));
    expect(moved, '0e20e4');

    game.applyGame(
        _msg(1, {b: {'type': 'P', 'owner': 0}}, event: {
          'kind': 'move',
          'player': 0,
          'move': {'from': '0e2', 'to': '0e4'},
          'piece': 'P',
          'captured': {'type': 'P', 'owner': 1, 'frozen': false, 'at': '0e4'},
          'checks': [],
          'mates': [],
          'eliminated': [],
          'passes': [],
        }),
        0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.hasPiece('0e4'), isTrue);
    expect(game.hasPiece('0e2'), isFalse);
  });
}
