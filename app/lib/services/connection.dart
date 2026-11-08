import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/protocol.dart';

enum ConnStatus { idle, connecting, connected, reconnecting }

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

/// Connexion WebSocket avec reconnexion automatique (backoff exponentiel).
class RoomConnection {
  RoomConnection({
    required this.uri,
    required this.onMessage,
    required this.onStatus,
    ChannelFactory? factory,
    this.maxDelay = const Duration(seconds: 15),
  }) : _factory = factory ?? WebSocketChannel.connect;

  final Uri uri;
  final void Function(Object msg) onMessage;
  final void Function(ConnStatus status) onStatus;
  final ChannelFactory _factory;
  final Duration maxDelay;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _retry;
  Timer? _ping;
  int _attempt = 0;
  bool _closed = true;
  ConnStatus _status = ConnStatus.idle;

  ConnStatus get status => _status;
  int get failures => _attempt;

  static Duration backoff(int attempt, Duration max) {
    final ms = 1000 * math.pow(2, math.min(attempt, 6)).toInt();
    final d = Duration(milliseconds: ms);
    return d > max ? max : d;
  }

  void _setStatus(ConnStatus s) {
    if (_status == s) return;
    _status = s;
    onStatus(s);
  }

  void connect() {
    _closed = false;
    _open();
  }

  void _open() {
    _teardown();
    _setStatus(_attempt == 0 ? ConnStatus.connecting : ConnStatus.reconnecting);
    try {
      final ch = _factory(uri);
      _channel = ch;
      ch.ready.then((_) {
        if (_channel != ch || _closed) return;
        _attempt = 0;
        _setStatus(ConnStatus.connected);
        send({'type': 'ping'});
        _ping?.cancel();
        _ping = Timer.periodic(const Duration(seconds: 25), (_) => send({'type': 'ping'}));
      }).catchError((_) {
        if (_channel == ch) _scheduleRetry();
      });
      _sub = ch.stream.listen(
        (data) {
          final m = parseServerMessage(data);
          if (m != null) onMessage(m);
        },
        onError: (_) {
          if (_channel == ch) _scheduleRetry();
        },
        onDone: () {
          if (_channel == ch) _scheduleRetry();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_closed) return;
    _teardown();
    _setStatus(ConnStatus.reconnecting);
    final d = backoff(_attempt, maxDelay);
    _attempt++;
    _retry?.cancel();
    _retry = Timer(d, () {
      if (!_closed) _open();
    });
  }

  /// Relance immédiatement (retour au premier plan, par exemple).
  void reconnectNow() {
    if (_closed || _status == ConnStatus.connected) return;
    _retry?.cancel();
    _open();
  }

  bool send(Map<String, dynamic> msg) {
    if (_status != ConnStatus.connected || _channel == null) return false;
    try {
      _channel!.sink.add(json.encode(msg));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _teardown() {
    _ping?.cancel();
    _ping = null;
    _sub?.cancel();
    _sub = null;
    final ch = _channel;
    _channel = null;
    try {
      ch?.sink.close();
    } catch (_) {}
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    _teardown();
    _setStatus(ConnStatus.idle);
  }
}
