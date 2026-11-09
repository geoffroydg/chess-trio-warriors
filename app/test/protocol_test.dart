import 'dart:convert';

import 'package:chesstrio/models/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _state({int ply = 1, List<bool> active = const [true, true, true]}) => {
      'version': 1,
      'mode': 'firstMate',
      'board': List.generate(96, (i) => i == 4 ? {'type': 'K', 'owner': 0} : null),
      'turn': 1,
      'active': active,
      'ply': ply,
      'eliminations': [
        {'player': 2, 'by': 1, 'reason': 'mate', 'ply': 12}
      ],
      'result': null,
    };

void main() {
  test('parse room', () {
    final m = parseServerMessage(json.encode({
      'type': 'room',
      'code': 'K7M2QX',
      'mode': 'twoMates',
      'players': [
        {'id': 0, 'pseudo': 'Ana', 'connected': true, 'push': false},
        {'id': 1, 'pseudo': 'Bob', 'connected': false, 'push': true},
        {'id': 2, 'pseudo': 'Ryuna', 'connected': true, 'push': false, 'isBot': true, 'level': 'difficile'},
      ],
      'ready': false,
      'started': false,
      'you': 1,
    }));
    expect(m, isA<RoomMsg>());
    final r = m as RoomMsg;
    expect(r.code, 'K7M2QX');
    expect(r.players, hasLength(3));
    expect(r.playerById(1)!.isBot, isFalse);
    expect(r.playerById(2)!.isBot, isTrue);
    expect(r.playerById(2)!.level, 'difficile');
    expect(botLevelLabel(r.playerById(2)!.level), 'Difficile');
    expect(r.playerById(1)!.pseudo, 'Bob');
    expect(r.playerById(1)!.connected, isFalse);
    expect(r.you, 1);
  });

  test('parse game avec évènement automatique et capture', () {
    final m = parseServerMessage(json.encode({
      'type': 'game',
      'state': _state(),
      'lastEvent': {
        'kind': 'move',
        'player': 0,
        'move': {'from': '0e2', 'to': '1d4'},
        'piece': 'N',
        'captured': {'type': 'P', 'owner': 1, 'frozen': false, 'at': '1d4'},
        'promotion': null,
        'castle': null,
        'checks': [
          {'player': 1, 'by': [0]}
        ],
        'mates': [],
        'eliminated': [],
        'passes': [],
        'gameOver': null,
        'auto': true,
      },
      'turn': 1,
      'legalMoves': [
        {'from': '1e2', 'to': '1e4'}
      ],
      'turnDeadline': 1767225600000,
      'over': false,
      'result': null,
      'players': [],
    })) as GameMsg;
    expect(m.turn, 1);
    expect(m.turnDeadline, 1767225600000);
    expect(m.legalMoves.single.to, '1e4');
    expect(m.state.board[4]!.type, PieceType.king);
    final e = m.lastEvent!;
    expect(e.auto, isTrue);
    expect(e.piece, PieceType.knight);
    expect(e.captured!.type, PieceType.pawn);
    expect(e.captured!.at, '1d4');
    expect(e.checks.single.by, [0]);
  });

  test('parse fin de partie, erreur, pong, invalide', () {
    final over = parseServerMessage({
      'type': 'game',
      'state': _state(),
      'lastEvent': null,
      'turn': null,
      'legalMoves': [],
      'turnDeadline': null,
      'over': true,
      'result': {'winner': 1, 'reason': 'mate'},
    }) as GameMsg;
    expect(over.over, isTrue);
    expect(over.turn, isNull);
    expect(over.result!.winner, 1);

    final err = parseServerMessage('{"type":"error","code":"illegalMove","message":"Coup illégal"}');
    expect((err as ErrorMsg).code, 'illegalMove');
    expect((parseServerMessage('{"type":"pong","now":42}') as PongMsg).now, 42);
    expect(parseServerMessage('pas du json'), isNull);
    expect(parseServerMessage('{"type":"inconnu"}'), isNull);
  });

  test('index de case et classement', () {
    expect(cellIndex('0a1'), 0);
    expect(cellIndex('1e2'), 32 + 8 + 4);
    expect(cellIndex('2h4'), 95);

    final s = GameState.fromJson(_state(active: [true, true, false]));
    final r = computeRanking(s, const GameResult(winner: 1, reason: 'mate'));
    expect(r.first.player, 1);
    expect(r.first.rank, 1);
    expect(r.map((e) => e.rank), [1, 2, 3]);
    expect(r.last.player, 2); // éliminé : dernier
    final nulle = computeRanking(s, const GameResult(winner: null, reason: 'fiftyMoves'));
    expect(nulle.every((e) => e.rank == 1), isTrue);
  });
}
