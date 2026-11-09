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
  double rate = 0.05; // variation de niveau par pas de 50 ms
}

/// Sons du jeu (étape 4b) : musique avec fondus enchaînés, voix par personnage
/// en file d'attente avec ducking, effets. Ne lève jamais d'erreur si un fichier
/// ou le lecteur audio est absent. Fichiers attendus : assets/audio/README.md.
///
/// Musique : `menu` hors partie (rebouclé par fondu enchaîné), en partie une
/// playlist aléatoire de `game_1..6` sans répétition jusqu'à épuisement avec
/// fondus enchaînés de 4 s, `check_sting` par-dessus lors d'un échec,
/// `victory` / `defeat` en fin de partie.
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
  static const _gameTracks = ['game_1', 'game_2', 'game_3', 'game_4', 'game_5', 'game_6'];
  static const _crossfade = Duration(seconds: 4);
  static const _screenFade = Duration(milliseconds: 1500);
  static const _endFade = Duration(milliseconds: 800);
  static const _sfxAliases = {
    'select': 'aura',
    'move': 'dash',
    'capture': 'impact',
    'check': 'beam',
    'mate': 'explosion',
    'turn': 'notify',
  };

  // Réglages (persistés).
  double musicVolume = 0.35;
  double voiceVolume = 1.0;
  double sfxVolume = 0.8;
  bool muted = false;
  bool get enabled => !muted;

  Set<String>? _assets;
  Future<void>? _loading;
  final List<_Track> _tracks = [];
  int _active = 0;
  String? _currentMusic; // 'menu', 'game', 'victory', 'defeat'
  final List<String> _bag = [];
  String? _lastGameTrack;
  Timer? _watch;
  bool _advancing = false;
  AudioPlayer? _sting;
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
        musicVolume = (p.getDouble(_musicKey) ?? musicVolume).clamp(0, 1).toDouble();
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
      await p.setDouble(_musicKey, musicVolume);
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

  // Nouvelle clé : le volume musique par défaut a été abaissé avec la nouvelle musique.
  static const _musicKey = 'snd_music_v2';

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

  static double _rateFor(Duration d) => _fade.inMilliseconds / max(1, d.inMilliseconds);

  void _startTicker() {
    _ticker ??= Timer.periodic(_fade, (_) => _step());
  }

  void _step() {
    var busy = false;
    if (_duck != _duckTarget) {
      _duck = _duckTarget > _duck ? min(_duckTarget, _duck + 0.1) : max(_duckTarget, _duck - 0.1);
      busy = busy || _duck != _duckTarget;
    }
    for (final t in _tracks) {
      if (t.level != t.target) {
        t.level = t.target > t.level ? min(t.target, t.level + t.rate) : max(t.target, t.level - t.rate);
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

  /// Musique de fond : 'menu' (écrans hors partie), 'game' (playlist de partie ;
  /// anciens noms 'battle' / 'tension' acceptés), 'victory' ou 'defeat'.
  Future<void> playMusic(String name) async {
    if (name == 'battle' || name == 'tension') name = 'game';
    if (_currentMusic == name || _disposed) return;
    await loadSettings();
    _currentMusic = name;
    if (name == 'game') {
      await _playFile(await _nextGameTrack(), _screenFade);
    } else {
      final ok = await _exists('music/$name.$_ext');
      if (_currentMusic != name) return; // changé pendant l'attente
      final fast = name == 'victory' || name == 'defeat';
      await _playFile(ok ? name : null, fast ? _endFade : _screenFade);
    }
  }

  /// Prochain morceau de partie : tirage sans remise parmi les fichiers présents,
  /// pas deux fois le même d'affilée lors du renouvellement du sac.
  Future<String?> _nextGameTrack() async {
    if (_bag.isEmpty) {
      final assets = await _loadAssets();
      final all = _gameTracks.where((n) => assets.contains('assets/audio/music/$n.$_ext')).toList();
      if (all.isEmpty) return null;
      all.shuffle(_rng);
      if (all.length > 1 && all.first == _lastGameTrack) {
        all.add(all.removeAt(0));
      }
      _bag.addAll(all);
    }
    final n = _bag.removeAt(0);
    _lastGameTrack = n;
    return n;
  }

  /// Fondu enchaîné vers [file] (null = fondu vers le silence).
  Future<void> _playFile(String? file, Duration fade) async {
    final mode = _currentMusic;
    for (final t in _tracks) {
      t.target = 0;
      t.rate = _rateFor(fade);
    }
    if (_tracks.any((t) => t.level != t.target)) _startTicker();
    if (file == null) {
      _stopWatch();
      return;
    }
    try {
      _active = (_active + 1) % 2;
      final t = _track(_active);
      t.target = 0;
      t.level = 0;
      await t.player.stop();
      await t.player.setReleaseMode(ReleaseMode.release);
      if (_currentMusic != mode || _disposed) return;
      t.name = file;
      t.rate = _rateFor(fade);
      t.target = 1;
      await t.player.setVolume(0);
      await t.player.play(AssetSource('audio/music/$file.$_ext'));
      _startTicker();
      if (mode == 'menu' || mode == 'game') _startWatch();
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService: $e');
    }
  }

  /// Surveille la fin du morceau courant pour lancer le suivant 4 s avant
  /// (playlist de partie, ou menu rebouclé), sans blanc.
  void _startWatch() {
    _watch ??= Timer.periodic(const Duration(milliseconds: 500), (_) => _checkEnd());
  }

  void _stopWatch() {
    _watch?.cancel();
    _watch = null;
  }

  Future<void> _checkEnd() async {
    final mode = _currentMusic;
    if (_advancing || _disposed || (mode != 'menu' && mode != 'game')) {
      if (mode != 'menu' && mode != 'game') _stopWatch();
      return;
    }
    final t = _track(_active);
    if (t.name == null) return;
    _advancing = true;
    try {
      final pos = await t.player.getCurrentPosition();
      final dur = await t.player.getDuration();
      if (pos == null || dur == null || dur == Duration.zero) return;
      final ended = t.player.state == PlayerState.completed;
      if (ended || dur - pos <= _crossfade) {
        final next = mode == 'game' ? await _nextGameTrack() : 'menu';
        if (_currentMusic == mode) await _playFile(next, _crossfade);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService: $e');
    } finally {
      _advancing = false;
    }
  }

  void _fadeOutAll() {
    for (final t in _tracks) {
      t.target = 0;
    }
    _stopWatch();
    _startTicker();
  }

  Future<void> stopMusic() async {
    _currentMusic = null;
    _fadeOutAll();
  }

  /// Petite touche dramatique (taiko + cordes) jouée par-dessus la musique.
  Future<void> _playSting() async {
    await loadSettings();
    if (muted || _disposed) return;
    try {
      if (!await _exists('music/check_sting.$_ext')) return;
      final p = _sting ??= _playerFactory();
      await p.stop();
      await p.setReleaseMode(ReleaseMode.release);
      await p.setVolume(min(1.0, musicVolume * 1.6));
      await p.play(AssetSource('audio/music/check_sting.$_ext'));
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService: $e');
    }
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

  /// Cri de combat (kiai) générique, une fois sur quatre.
  bool _kiai() {
    if (_rng.nextInt(4) != 0) return false;
    _enqueue('voice/kiai', droppable: true);
    return true;
  }

  void onMove(PieceType pieceType) {
    playEffect('dash');
    if (!_kiai()) _enqueue('voice/${_name(pieceType)}_move', droppable: true);
  }

  void onCapture(PieceType attackerType, PieceType victimType) {
    playEffect('impact');
    _enqueue('voice/${_name(attackerType)}_capture');
    if (_rng.nextBool()) _enqueue('voice/${_name(victimType)}_captured');
  }

  void onCheck(PieceType giverType) {
    playEffect('beam');
    _playSting();
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
    playMusic(won ? 'victory' : 'defeat');
    if (won) _enqueue('voice/announcer_victory.$_ext', variants: false);
  }

  Future<void> dispose() async {
    _disposed = true;
    _ticker?.cancel();
    _stopWatch();
    _queue.clear();
    final all = <AudioPlayer>[..._tracks.map((t) => t.player), ..._sfxPool, ?_voice, ?_sting];
    for (final p in all) {
      await _safe(() => p.dispose());
    }
  }
}
