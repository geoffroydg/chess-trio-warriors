import 'package:shared_preferences/shared_preferences.dart';

class Session {
  const Session({required this.code, required this.token, required this.playerId});
  final String code;
  final String token;
  final int playerId;
}

/// Persistance locale : pseudo, URL du serveur, salon courant et jeton joueur.
class Storage {
  Storage(this._prefs);
  final SharedPreferences _prefs;

  static Future<Storage> open() async => Storage(await SharedPreferences.getInstance());

  String get pseudo => _prefs.getString('pseudo') ?? '';
  Future<void> setPseudo(String v) => _prefs.setString('pseudo', v);

  /// Overlay FPS de débogage (Réglages).
  bool get debugFps => _prefs.getBool('debug.fps') ?? false;
  Future<void> setDebugFps(bool v) => _prefs.setBool('debug.fps', v);

  /// Recentrer automatiquement sur le dernier coup quand on est zoomé (Réglages).
  bool get autoRecenter => _prefs.getBool('game.autoRecenter') ?? false;
  Future<void> setAutoRecenter(bool v) => _prefs.setBool('game.autoRecenter', v);

  String? get serverUrl => _prefs.getString('serverUrl');
  Future<void> setServerUrl(String? v) =>
      v == null ? _prefs.remove('serverUrl') : _prefs.setString('serverUrl', v);

  Session? get session {
    final code = _prefs.getString('session.code');
    final token = _prefs.getString('session.token');
    final id = _prefs.getInt('session.playerId');
    if (code == null || token == null || id == null) return null;
    return Session(code: code, token: token, playerId: id);
  }

  Future<void> saveSession(Session s) async {
    await _prefs.setString('session.code', s.code);
    await _prefs.setString('session.token', s.token);
    await _prefs.setInt('session.playerId', s.playerId);
  }

  Future<void> clearSession() async {
    await _prefs.remove('session.code');
    await _prefs.remove('session.token');
    await _prefs.remove('session.playerId');
  }

  String? get fcmToken => _prefs.getString('fcmToken');
  Future<void> setFcmToken(String v) => _prefs.setString('fcmToken', v);
}
