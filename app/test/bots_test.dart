import 'dart:convert';

import 'package:chesstrio/app.dart';
import 'package:chesstrio/models/protocol.dart';
import 'package:chesstrio/services/api.dart';
import 'package:chesstrio/services/connection.dart';
import 'package:chesstrio/services/storage.dart';
import 'package:chesstrio/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Connexion factice : toujours « connectée », mémorise les messages envoyés.
class FakeConnection extends RoomConnection {
  FakeConnection({required super.uri, required super.onMessage, required super.onStatus});
  final sent = <Map<String, dynamic>>[];
  @override
  void connect() => onStatus(ConnStatus.connected);
  @override
  bool send(Map<String, dynamic> msg) {
    sent.add(msg);
    return true;
  }

  @override
  void close() {}
  @override
  void reconnectNow() {}
}

Map<String, dynamic> _room(List<Map<String, dynamic>> players) => {
      'type': 'room',
      'code': 'K7M2QX',
      'mode': 'firstMate',
      'players': players,
      'ready': players.length == 3,
      'started': false,
      'you': 0,
    };

void main() {
  testWidgets('Jouer seul : mode + niveau puis création du salon avec 2 bots', (tester) async {
    SharedPreferences.setMockInitialValues({'pseudo': 'Ana'});
    final storage = await Storage.open();
    Map<String, dynamic>? body;
    FakeConnection? conn;
    final app = AppState(
      storage: storage,
      apiFactory: (url) => ApiClient(url, client: MockClient((req) async {
        body = json.decode(req.body) as Map<String, dynamic>;
        return http.Response(json.encode({'code': 'SOLO23', 'playerId': 0, 'playerToken': 't'}), 201);
      })),
      connectionBuilder: ({required uri, required onMessage, required onStatus}) =>
          conn = FakeConnection(uri: uri, onMessage: onMessage, onStatus: onStatus),
    );
    await app.init();
    await tester.pumpWidget(ChessTrioApp(appState: app));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jouer seul'));
    await tester.pumpAndSettle();
    expect(find.text('Premier mat'), findsOneWidget);
    for (final l in ['Facile', 'Moyen', 'Difficile']) {
      expect(find.text(l), findsOneWidget);
    }
    await tester.tap(find.text('Deux mats'));
    await tester.ensureVisible(find.text('Difficile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Difficile'));
    await tester.pump();
    await tester.ensureVisible(find.text('Lancer la partie'));
    await tester.tap(find.text('Lancer la partie'));
    await tester.pumpAndSettle();

    expect(body!['mode'], 'twoMates');
    expect(body!['pseudo'], 'Ana');
    expect(body!.containsKey('password'), isFalse);
    expect(body!['bots'], [
      {'level': 'difficile'},
      {'level': 'difficile'}
    ]);
    expect(app.session!.code, 'SOLO23');
    expect(conn, isNotNull);
  });

  testWidgets('salle d\'attente : l\'hôte ajoute puis retire un bot', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pseudo': 'Ana',
      'session.code': 'K7M2QX',
      'session.token': 'tok',
      'session.playerId': 0,
    });
    final storage = await Storage.open();
    late FakeConnection conn;
    late void Function(Object) push;
    final app = AppState(
      storage: storage,
      connectionBuilder: ({required uri, required onMessage, required onStatus}) {
        push = onMessage;
        return conn = FakeConnection(uri: uri, onMessage: onMessage, onStatus: onStatus);
      },
    );
    await app.init();
    push(parseServerMessage(_room([
      {'id': 0, 'pseudo': 'Ana', 'connected': true, 'push': false, 'isBot': false},
    ]))!);
    await tester.pumpWidget(ChessTrioApp(appState: app));
    await tester.pumpAndSettle();

    expect(find.text('+ Ajouter un bot'), findsNWidgets(2));
    await tester.ensureVisible(find.text('+ Ajouter un bot').first);
    await tester.tap(find.text('+ Ajouter un bot').first);
    await tester.pumpAndSettle();
    expect(find.text('Niveau du bot 🤖'), findsOneWidget);
    await tester.tap(find.text('Difficile'));
    await tester.pumpAndSettle();
    expect(conn.sent.last, {'type': 'addBot', 'seat': 1, 'level': 'difficile'});

    push(parseServerMessage(_room([
      {'id': 0, 'pseudo': 'Ana', 'connected': true, 'push': false, 'isBot': false},
      {'id': 1, 'pseudo': 'Ryuna', 'connected': true, 'push': false, 'isBot': true, 'level': 'difficile'},
    ]))!);
    await tester.pumpAndSettle();
    expect(find.text('Ryuna'), findsOneWidget);
    expect(find.text('🤖 Difficile'), findsOneWidget);
    expect(find.text('+ Ajouter un bot'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Retirer le bot'));
    await tester.tap(find.byTooltip('Retirer le bot'));
    await tester.pump();
    expect(conn.sent.last, {'type': 'removeBot', 'seat': 1});
  });
}
