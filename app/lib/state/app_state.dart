import 'dart:async';

import 'package:flutter/widgets.dart';

import '../config.dart';
import '../models/protocol.dart';
import '../services/api.dart';
import '../services/connection.dart';
import '../services/notification_service.dart';
import '../services/sound_service.dart';
import '../services/storage.dart';

enum Phase { home, lobby, game, over }

typedef ConnectionBuilder = RoomConnection Function({
  required Uri uri,
  required void Function(Object msg) onMessage,
  required void Function(ConnStatus status) onStatus,
});

/// État global de l'application (ChangeNotifier + provider).
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({
    required this.storage,
    SoundService? sound,
    this.notifications,
    ApiClient Function(String url)? apiFactory,
    ConnectionBuilder? connectionBuilder,
  })  : sound = sound ?? SoundService(),
        _apiFactory = apiFactory ?? ApiClient.new,
        _connBuilder = connectionBuilder ?? _defaultBuilder {
    pseudo = storage.pseudo;
    serverUrl = storage.serverUrl ?? kDefaultServerUrl;
    session = storage.session;
    _fcmToken = storage.fcmToken;
    WidgetsBinding.instance.addObserver(this);
    notifications
      ?..onOpenRoom = openRoom
      ..isShowingRoom = isShowingRoom
      ..onToken = setFcmToken;
  }

  static RoomConnection _defaultBuilder({
    required Uri uri,
    required void Function(Object msg) onMessage,
    required void Function(ConnStatus status) onStatus,
  }) =>
      RoomConnection(uri: uri, onMessage: onMessage, onStatus: onStatus);

  final Storage storage;
  final SoundService sound;
  final NotificationService? notifications;
  final ApiClient Function(String url) _apiFactory;
  final ConnectionBuilder _connBuilder;

  late String pseudo;
  late String serverUrl;
  Session? session;
  RoomMsg? room;
  GameMsg? game;
  ConnStatus connStatus = ConnStatus.idle;
  int clockOffsetMs = 0;
  bool inForeground = true;
  String? _fcmToken;
  RoomConnection? _conn;

  final _toasts = StreamController<String>.broadcast();
  Stream<String> get toasts => _toasts.stream;

  Phase get phase {
    if (session == null) return Phase.home;
    final g = game;
    if (g != null) return g.over ? Phase.over : Phase.game;
    return Phase.lobby;
  }

  int get me => session?.playerId ?? room?.you ?? 0;

  String playerName(int id) {
    final p = room?.playerById(id) ?? _gamePlayer(id);
    final pseudo = p?.pseudo ?? '';
    return pseudo.isEmpty ? playerNames[id] : pseudo;
  }

  PlayerInfo? _gamePlayer(int id) {
    for (final p in game?.players ?? const <PlayerInfo>[]) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool playerConnected(int id) => (_gamePlayer(id) ?? room?.playerById(id))?.connected ?? false;

  /// Heure serveur estimée (ms).
  int get serverNowMs => DateTime.now().millisecondsSinceEpoch + clockOffsetMs;

  // --- Démarrage / reprise ---

  Future<void> init() async {
    if (session != null) _connect();
    _syncMusic();
  }

  bool isShowingRoom(String code) =>
      inForeground && session?.code == code && (phase == Phase.game || phase == Phase.lobby);

  void openRoom(String code) {
    if (session?.code == code) _conn?.reconnectNow();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    inForeground = state == AppLifecycleState.resumed;
    if (inForeground) _conn?.reconnectNow();
  }

  // --- Réglages ---

  Future<void> setPseudo(String v) async {
    pseudo = v.trim();
    await storage.setPseudo(pseudo);
    notifyListeners();
  }

  Future<void> setServerUrl(String? v) async {
    final u = (v == null || v.trim().isEmpty) ? null : normalizeServerUrl(v);
    await storage.setServerUrl(u);
    serverUrl = u ?? kDefaultServerUrl;
    notifyListeners();
  }

  void setFcmToken(String token) {
    _fcmToken = token;
    storage.setFcmToken(token);
    _sendPushToken();
  }

  void _sendPushToken() {
    final t = _fcmToken;
    if (t != null && connStatus == ConnStatus.connected) {
      _conn?.send({'type': 'registerPush', 'fcmToken': t});
    }
  }

  // --- Salons ---

  Future<void> createRoom(String password, String mode) async {
    final s = await _apiFactory(serverUrl).createRoom(pseudo, password, mode);
    await _enter(s);
  }

  Future<void> joinRoom(String code, String password) async {
    final s = await _apiFactory(serverUrl).joinRoom(code, pseudo, password);
    await _enter(s);
  }

  Future<void> _enter(Session s) async {
    _disconnect();
    session = s;
    room = null;
    game = null;
    await storage.saveSession(s);
    _connect();
    _syncMusic();
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    _disconnect();
    session = null;
    room = null;
    game = null;
    await storage.clearSession();
    _syncMusic();
    notifyListeners();
  }

  // --- Actions de jeu ---

  bool startGame() => _conn?.send({'type': 'start'}) ?? false;
  bool resign() => _conn?.send({'type': 'resign'}) ?? false;
  bool sendMove(String from, String to) =>
      _conn?.send({'type': 'move', 'from': from, 'to': to}) ?? false;

  void toast(String msg) => _toasts.add(msg);

  // --- Réseau ---

  void _connect() {
    final s = session;
    if (s == null) return;
    _conn = _connBuilder(
      uri: webSocketUri(serverUrl, s.code, s.token),
      onMessage: _onMessage,
      onStatus: (st) {
        connStatus = st;
        if (st == ConnStatus.connected) _sendPushToken();
        notifyListeners();
      },
    )..connect();
  }

  void _disconnect() {
    _conn?.close();
    _conn = null;
    connStatus = ConnStatus.idle;
  }

  void _onMessage(Object msg) {
    switch (msg) {
      case RoomMsg m:
        room = m;
      case GameMsg m:
        _onGame(m);
      case PongMsg m:
        clockOffsetMs = m.now - DateTime.now().millisecondsSinceEpoch;
      case ErrorMsg m:
        if (m.message.isNotEmpty) toast(m.message);
    }
    notifyListeners();
  }

  void _onGame(GameMsg m) {
    final prev = game;
    final wasPhase = phase;
    game = m;
    final e = m.lastEvent;
    final isNew = prev != null && prev.state.ply != m.state.ply && e != null;
    if (isNew) {
      if (e.auto && e.isMove) {
        toast('Temps écoulé : coup joué automatiquement pour ${playerName(e.player)}');
      } else if (e.kind == 'resign') {
        toast('${playerName(e.player)} a abandonné');
      }
      _playEventSounds(e);
    }
    if (m.turn == me && (prev == null || prev.turn != m.turn)) {
      sound.playEffect('turn');
    }
    if (wasPhase != phase) _syncMusic();
  }

  void _playEventSounds(GameEvent e) {
    if (!e.isMove || e.piece == null) return;
    final ev = e.mates.isNotEmpty
        ? SoundEvent.mate
        : e.checks.isNotEmpty
            ? SoundEvent.check
            : e.captured != null
                ? SoundEvent.capture
                : SoundEvent.move;
    sound.playEffect(ev.name);
    sound.playVoice(e.piece!, ev);
  }

  void _syncMusic() {
    switch (phase) {
      case Phase.game:
        sound.playMusic('game');
      case Phase.over:
        sound.stopMusic();
      default:
        sound.playMusic('menu');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disconnect();
    _toasts.close();
    sound.dispose();
    super.dispose();
  }
}
