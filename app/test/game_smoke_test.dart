import 'dart:io';

import 'package:chesstrio/game/chess_game.dart';
import 'package:chesstrio/game/warrior_piece.dart';
import 'package:chesstrio/models/geometry.dart';
import 'package:chesstrio/models/protocol.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GameMsg _msg(int ply, Map<int, Map<String, dynamic>> pieces,
    {Map<String, dynamic>? event, List<Map<String, String>> legal = const [], List<bool>? hilts}) {
  return GameMsg.fromJson({
    'state': {
      'mode': 'firstMate',
      'board': List.generate(144, (i) => pieces[i]),
      'turn': 0,
      'active': [true, true, true],
      'ply': ply,
      'eliminations': [],
      'hilts': hilts ?? [false, false, false],
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
    final game = ChessGame(geometry: geo, viewer: 0, onMove: (f, t, _) => moved = '$f$t');
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

  testWidgets('fin de partie : VICTOIRE du gagnant, K.-O. du roi vaincu, éliminé PÉTRIFIÉ', (tester) async {
    final geo = BoardGeometry.fromJsonString(File('assets/geometry.json').readAsStringSync());
    final game = ChessGame(geometry: geo, viewer: 0);
    await tester.pumpWidget(MaterialApp(home: SizedBox(width: 400, height: 400, child: GameWidget(game: game))));
    await tester.pump();
    final k0 = geo.byId('0d1').index, p0 = geo.byId('0e2').index;
    final k1 = geo.byId('1d1').index, k2 = geo.byId('2d1').index;
    final pieces = {
      k0: {'type': 'K', 'owner': 0},
      p0: {'type': 'P', 'owner': 0},
      k1: {'type': 'K', 'owner': 1},
      k2: {'type': 'K', 'owner': 2},
    };
    final m = GameMsg.fromJson({
      'state': {
        'mode': 'firstMate',
        'board': List.generate(144, (i) => pieces[i]),
        'turn': 0,
        'active': [true, true, false],
        'ply': 3,
        'eliminations': [],
      },
      'turn': null,
      'legalMoves': [],
      'over': true,
      'result': {'winner': 0, 'reason': 'mate'},
      'players': [],
    });
    game.applyGame(m, 0);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    WarriorPiece at(String id) => game.worldLayer.children.whereType<WarriorPiece>().firstWhere((p) => p.cellId == id);
    expect(at('0d1').animState, AnimState.victory);
    expect(at('0e2').animState, AnimState.victory);
    expect(at('1d1').animState, AnimState.ko);
    expect(at('2d1').animState, AnimState.petrified);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(at('1d1').isMounted, isTrue); // K.-O. sans dissolution en fin de partie
  });

  testWidgets('promotion : sélecteur des 4 guerriers, choix envoyé avec le coup', (tester) async {
    final geo = BoardGeometry.fromJsonString(File('assets/geometry.json').readAsStringSync());
    final sent = <String>[];
    final game = ChessGame(geometry: geo, viewer: 0, onMove: (f, t, p) => sent.add('$f-$t=$p'));
    await tester.pumpWidget(MaterialApp(home: SizedBox(width: 400, height: 560, child: GameWidget(game: game))));
    await tester.pump();
    final pawn = geo.byId('2b2').index;
    game.applyGame(
        _msg(0, {pawn: {'type': 'P', 'owner': 0, 'crossed': true}}, legal: [
          for (final p in ['Q', 'R', 'B', 'N']) {'from': '2b2', 'to': '2b1', 'promotion': p},
          {'from': '0d1', 'to': '0c1'},
        ]),
        0);
    await tester.pump();
    await tester.pump();
    final a = game.cellPosition('2b2');
    game.handleTap(Offset(a.x, a.y));
    expect(game.targets, {'2b1'});
    final b = game.cellPosition('2b1');
    game.handleTap(Offset(b.x, b.y));
    expect(sent, isEmpty);
    final picker = game.picker!;
    expect(picker.options, ['Q', 'R', 'B', 'N']);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(picker.pieces.map((p) => p.type), [PieceType.queen, PieceType.rook, PieceType.bishop, PieceType.knight]);
    // Choix du cavalier.
    game.handleTap(picker.slots[3].center);
    expect(sent, ['2b2-2b1=N']);
    expect(game.picker, isNull);
    // Tap hors du panneau : annulation.
    game.handleTap(Offset(a.x, a.y));
    game.handleTap(Offset(b.x, b.y));
    expect(game.picker, isNotNull);
    game.handleTap(const Offset(1, 1));
    expect(game.picker, isNull);
    expect(sent, hasLength(1));
  });

  testWidgets('traversée du centre : traînée par le médaillon ; poignée ouverte : éclat', (tester) async {
    final geo = BoardGeometry.fromJsonString(File('assets/geometry.json').readAsStringSync());
    final game = ChessGame(geometry: geo, viewer: 0);
    await tester.pumpWidget(MaterialApp(home: SizedBox(width: 400, height: 560, child: GameWidget(game: game))));
    await tester.pump();
    final from = geo.byId('0a3').index, to = geo.byId('2e3').index;
    game.applyGame(_msg(0, {from: {'type': 'R', 'owner': 0}}), 0);
    await tester.pump();
    await tester.pump();
    game.applyGame(
        _msg(1, {to: {'type': 'R', 'owner': 0}}, hilts: [true, true, false], event: {
          'kind': 'move',
          'player': 0,
          'move': {'from': '0a3', 'to': '2e3'},
          'piece': 'R',
          'captured': null,
          'crossedCenter': true,
          'hiltsOpened': [0, 1],
          'checks': [],
          'mates': [],
          'eliminated': [],
          'passes': [],
        }),
        0);
    await tester.pump();
    expect(game.board.activeEffects, 3);
    expect(game.hilts, [true, true, false]);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.board.activeEffects, 0);
    expect(game.hasPiece('2e3'), isTrue);
  });
}
