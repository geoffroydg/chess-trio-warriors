import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'storage.dart';

class ApiException implements Exception {
  ApiException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

String normalizeServerUrl(String url) {
  var u = url.trim();
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}

Uri webSocketUri(String serverUrl, String code, String token) {
  final base = Uri.parse(normalizeServerUrl(serverUrl));
  return base.replace(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    path: '${base.path}/rooms/$code/ws',
    queryParameters: {'token': token},
  );
}

class ApiClient {
  ApiClient(this.serverUrl, {http.Client? client}) : _client = client ?? http.Client();
  final String serverUrl;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse('${normalizeServerUrl(serverUrl)}$path');

  Future<Session> createRoom(String pseudo, String password, String mode) async {
    final j = await _post('/rooms', {'pseudo': pseudo, 'password': password, 'mode': mode});
    return _session(j);
  }

  /// Partie solo : salon avec 2 bots, démarré aussitôt par le serveur.
  Future<Session> createSoloRoom(String pseudo, String mode, List<String> botLevels) async {
    final j = await _post('/rooms', {
      'pseudo': pseudo,
      'mode': mode,
      'bots': [for (final l in botLevels) {'level': l}],
    });
    return _session(j);
  }

  Future<Session> joinRoom(String code, String pseudo, String password) async {
    final j = await _post(
        '/rooms/${Uri.encodeComponent(code.trim().toUpperCase())}/join',
        {'pseudo': pseudo, 'password': password});
    return _session(j);
  }

  Future<bool> health() async {
    try {
      final r = await _client.get(_uri('/health')).timeout(const Duration(seconds: 8));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Session _session(Map<String, dynamic> j) => Session(
        code: j['code'] as String,
        token: j['playerToken'] as String,
        playerId: j['playerId'] as int,
      );

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    http.Response r;
    try {
      r = await _client
          .post(_uri(path),
              headers: {'content-type': 'application/json'}, body: json.encode(body))
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw ApiException('timeout', 'Le serveur ne répond pas. Réessaie dans un instant.');
    } catch (_) {
      throw ApiException('network', 'Impossible de joindre le serveur. Vérifie ta connexion.');
    }
    Map<String, dynamic>? j;
    try {
      j = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (r.statusCode >= 200 && r.statusCode < 300 && j != null) return j;
    throw ApiException(
      (j?['error'] ?? 'http${r.statusCode}') as String,
      (j?['message'] ?? 'Erreur du serveur (${r.statusCode}).') as String,
    );
  }
}
