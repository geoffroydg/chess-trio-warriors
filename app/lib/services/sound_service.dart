import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/protocol.dart';

/// Conservé pour compatibilité : évènements vocaux d'une pièce.
enum SoundEvent { move, capture, check, mate }

class _Track {
  _Track(this.player);
  final AudioPlayer player;
  String? name;
  double level = 0;
  double target = 0;
}

/// Sons du jeu (étape 4b) : musique avec fondu, voix par personnage en file
/// d'attente avec ducking, effets. Ne lève jamais d'erreur si un fichier ou
/// le lecteur audio est absent. Fichiers attendus : assets/audio/README.md.
class SoundService {
  SoundService({AudioPlayer Function()? playerFactory, Random? random})
      : _playerFactory = playerFactory ?? AudioPlayer.new,
        _rng = random ?? Random();

  final AudioPlayer Function() _playerFactory;
  final Random _rng;

  static const _ext = 'ogg';
  static const _fade = Duration(milliseconds: 50);
  static const _duckLevel = 0.35;
  static const _maxQueue = 3;
  static const _loopedMusic = {'menu', 'battle', 'tension'};
  static const _sfxAliases = {
    'select': 'aura',
    'move': 'dash',
    'capture': 'impact',
    'check': 'beam',
    'mate': 'explosion',
    'turn': 'notify',
  };

  // Réglages (persistés).
  double musicVolume = 0.6;
  double voiceVolume = 1.0;
  double sfxVolume = 0.8;
  bool muted = false;
  bool get enabled => !muted;

  Set<String>? _assets;
  Future<void>? _loading;
  final List<_Track> _tracks = [];
  int _active = 0;
  String? _currentMusic;
  Timer? _ticker;
  double _duck = 1;
  double _duckTarget = 1;

  final List<AudioPlayer> _sfxPool = [];
  int _sfxNext = 0;
  AudioPlayer? _voice;
  final List<String> _queue = [];
  bool _draining = false;
  final Map<String, int> _lastVariant = {};
  int _lastTick = -1;
  bool _disposed = false;

  // ---------------------------------------------------------------- réglages

  /// Charge les réglages sauvegardés (sans erreur si indisponible).
  Future<void> loadSettings() {
    return _loading ??= () async {
      try {
        final p = await SharedPreferences.getInstance();
        musicVolume = (p.getDouble('snd_music') ?? musicVolume).clamp(0, 1).toDouble();
        voiceVolume = (p.getDouble('snd_voice') ?? voiceVolume).clamp(0, 1).toDouble();
        sfxVolume = (p.getDouble('snd_sfx') ?? sfxVolume).clamp(0, 1).toDouble();
        muted = p.getBool('snd_muted') ?? muted;
      } catch (_) {}
      _applyVolumes();
    }();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('snd_music', musicVolume);
      await p.setDouble('snd_voice', voiceVolume);
      await p.setDouble('snd_sfx', sfxVolume);
      await p.setBool('snd_muted', muted);
    } catch (_) {}
  }

  Future<void> setMusicVolume(double v) async {
    musicVolume = v.clamp(0, 1).toDouble();
    _applyVolumes();
    await _save();
  }

  Future<void> setVoiceVolume(double v) async {
    voiceVolume = v.clamp(0, 1).toDouble();
    await _safe(() => _voice?.setVolume(voiceVolume));
    await _save();
  }

  Future<void> setSfxVolume(double v) async {
    sfxVolume = v.clamp(0, 1).toDouble();
    await _save();
  }

  Future<void> setMuted(bool m) async {
    muted = m;
    if (m) {
      _queue.clear();
      await _safe(() => _voice?.stop());
      for (final p in _sfxPool) {
        await _safe(() => p.stop());
      }
    }
    _applyVolumes();
    await _save();
  }

  // ---------------------------------------------------------------- assets

  Future<Set<String>> _loadAssets() async {
    if (_assets != null) return _assets!;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _assets = manifest.listAssets().where((a) => a.startsWith('assets/audio/')).toSet();
    } catch (_) {
      _assets = <String>{};
    }
    return _assets!;
  }

  Future<bool> _exists(String path) async => (await _loadAssets()).contains('assets/audio/$path');

  Future<void> _safe(FutureOr<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService: $e');
    }
  }

  /// Choisit une variante `prefix_N.ogg` existante, différente de la précédente.
  Future<String?> _pickVariant(String prefix) async {
    final assets = await _loadAssets();
    final found = <int>[];
    for (var i = 1; i <= 9; i++) {
      if (assets.contains('assets/audio/${prefix}_$i.$_ext')) found.add(i);
    }
    if (found.isEmpty) return null;
    var choices = found;
    if (found.length > 1) choices = found.where((i) => i != _lastVariant[prefix]).toList();
    final n = choices[_rng.nextInt(choices.length)];
    _lastVariant[prefix] = n;
    return '${prefix}_$n.$_ext';
  }

  // ---------------------------------------------------------------- musique

  _Track _track(int i) {
    while (_tracks.length <= i) {
      _tracks.add(_Track(_playerFactory()));
    }
    return _tracks[i];
  }

  void _applyVolumes() {
    for (final t in _tracks) {
      _safe(() => t.player.setVolume(_trackVolume(t)));
    }
  }

  double _trackVolume(_Track t) => muted ? 0 : (t.level * musicVolume * _duck).clamp(0, 1).toDouble();

  void _startTicker() {
    _ticker ??= Timer.periodic(_fade, (_) => _step());
  }

  void _step() {
    var busy = false;
    const k = 0.05; // 1 s pour un fondu complet
    if (_duck != _duckTarget) {
      _duck = _duckTarget > _duck ? min(_duckTarget, _duck + 0.1) : max(_duckTarget, _duck - 0.1);
      busy = busy || _duck != _duckTarget;
    }
    for (final t in _tracks) {
      if (t.level != t.target) {
        t.level = t.target > t.level ? min(t.target, t.level + k) : max(t.target, t.level - k);
        busy = busy || t.level != t.target;
      }
      _safe(() => t.player.setVolume(_trackVolume(t)));
      if (t.level == 0 && t.target == 0 && t.name != null) {
        t.name = null;
        _safe(() => t.player.stop());
      }
    }
    if (!busy) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Musique de fond : 'menu', 'battle', 'tension' ou 'victory' (fondu enchaîné).
  Future<void> playMusic(String name) async {
    if (name == 'game') name = 'battle';
    if (_currentMusic == name || _disposed) return;
    await loadSettings();
    _currentMusic = name;
    final path = 'music/$name.$_ext';
    try {
      if (!await _exists(path)) {
        _fadeOutAll();
        return;
      }
      if (_currentMusic != name) return; // changé pendant l'attente
      for (final t in _tracks) {
        t.target = 0;
      }
      _active = (_active + 1) % 2;
      final t = _track(_active);
      await t.player.stop();
      await t.player.setReleaseMode(_loopedMusic.contains(name) ? ReleaseMode.loop : ReleaseMode.release);
      t.name = name;
      t.level = 0;
      t.target = 1;
      await t.player.setVolume(0);
      await t.player.play(AssetSource('audio/$path'));
      _startTicker();
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService: $e');
    }
  }

  void _fadeOutAll() {
    for (final t in _tracks) {
      t.target = 0;
    }
    _startTicker();
  }

  Future<void> stopMusic() async {
    _currentMusic = null;
    _fadeOutAll();
  }

  // ---------------------------------------------------------------- effets

  /// Effet : 'aura', 'dash', 'impact', 'explosion', 'beam', 'tick', 'notify'
  /// (anciens noms 'select', 'move', 'capture', 'check', 'mate', 'turn' acceptés).
  Future<void> playEffect(String name, {double volume = 1}) async {
    await loadSettings();
    if (muted || _disposed) return;
    final file = _sfxAliases[name] ?? name;
    try {
      if (!await _exists('sfx/$file.$_ext')) return;
      if (_sfxPool.length < 4) _sfxPool.add(_playerFactory());
      final p = _sfxPool[_sfxNext++ % _sfxPool.length];
      await p.stop();
      await p.setReleaseMode(ReleaseMode.release);
      await p.setVolume((sfxVolume * volume).clamp(0, 1).toDouble());
      await p.play(AssetSource('audio/sfx/$file.$_ext'));
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService: $e');
    }
  }

  // ---------------------------------------------------------------- voix

  /// Met une voix en file (jamais deux voix superposées). Si [droppable] et que
  /// la file est occupée, la voix est ignorée.
  Future<void> _enqueue(String prefixOrPath, {bool variants = true, bool droppable = false}) async {
    await loadSettings();
    if (muted || _disposed) return;
    try {
      final file = variants ? await _pickVariant(prefixOrPath) : (await _exists(prefixOrPath) ? prefixOrPath : null);
      if (file == null) return;
      if (droppable && (_draining || _queue.isNotEmpty)) return;
      if (_queue.length >= _maxQueue) _queue.removeAt(0);
      _queue.add(file);
      unawaited(_drain());
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService: $e');
    }
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && !muted && !_disposed) {
        final file = _queue.removeAt(0);
        _duckTarget = _duckLevel;
        _startTicker();
        await _playVoiceFile(file);
      }
    } finally {
      _draining = false;
      _duckTarget = 1;
      if (!_disposed) _startTicker();
    }
  }

  Future<void> _playVoiceFile(String file) async {
    try {
      final p = _voice ??= _playerFactory();
      await p.stop();
      await p.setReleaseMode(ReleaseMode.release);
      await p.setVolume(voiceVolume);
      final done = p.onPlayerComplete.first.timeout(const Duration(seconds: 6), onTimeout: () {});
      await p.play(AssetSource('audio/$file'));
      await done;
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService: $e');
    }
  }

  static String _name(PieceType t) => t.name;

  /// Voix directe d'une pièce (compatibilité) : `voice/PIECE_EVENEMENT_N.ogg`.
  Future<void> playVoice(PieceType type, SoundEvent event) =>
      _enqueue('voice/${_name(type)}_${event.name}');

  // ---------------------------------------------------------------- évènements de jeu

  void _relaxTension() {
    if (_currentMusic == 'tension') playMusic('battle');
  }

  /// Cri de combat (kiai) générique, une fois sur quatre.
  bool _kiai() {
    if (_rng.nextInt(4) != 0) return false;
    _enqueue('voice/kiai', droppable: true);
    return true;
  }

  void onMove(PieceType pieceType) {
    _relaxTension();
    playEffect('dash');
    if (!_kiai()) _enqueue('voice/${_name(pieceType)}_move', droppable: true);
  }

  void onCapture(PieceType attackerType, PieceType victimType) {
    _relaxTension();
    playEffect('impact');
    _enqueue('voice/${_name(attackerType)}_capture');
    if (_rng.nextBool()) _enqueue('voice/${_name(victimType)}_captured');
  }

  void onCheck(PieceType giverType) {
    playEffect('beam');
    playMusic('tension');
    _enqueue('voice/${_name(giverType)}_check');
    _enqueue('voice/announcer_check.$_ext', variants: false);
  }

  void onMate(PieceType giverType) {
    playEffect('explosion');
    _enqueue('voice/${_name(giverType)}_mate');
    _enqueue('voice/announcer_mate.$_ext', variants: false);
  }

  void onYourTurn() {
    playEffect('notify');
    _enqueue('voice/announcer_yourturn.$_ext', variants: false, droppable: true);
  }

  void onGameStart() {
    playEffect('aura');
    _enqueue('voice/announcer_start.$_ext', variants: false);
  }

  void onTimeout() => _enqueue('voice/announcer_timeout.$_ext', variants: false);

  /// À appeler à chaque seconde restante ; tic pendant les 10 dernières secondes.
  void onTimerTick(int secondsLeft) {
    if (secondsLeft < 1 || secondsLeft > 10 || secondsLeft == _lastTick) return;
    _lastTick = secondsLeft;
    playEffect('tick', volume: secondsLeft <= 3 ? 1 : 0.7);
  }

  void onGameOver(bool won) {
    _lastTick = -1;
    if (won) {
      playMusic('victory');
      _enqueue('voice/announcer_victory.$_ext', variants: false);
    } else {
      stopMusic();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _ticker?.cancel();
    _queue.clear();
    final all = <AudioPlayer>[..._tracks.map((t) => t.player), ..._sfxPool, ?_voice];
    for (final p in all) {
      await _safe(() => p.dispose());
    }
  }
}
