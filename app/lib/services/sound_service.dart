import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/protocol.dart';

enum SoundEvent { move, capture, check, mate }

/// Sons du jeu (étape 4). Ne fait rien si les fichiers sont absents ou si
/// le lecteur audio n'est pas disponible. Fichiers attendus : assets/audio/README.md.
class SoundService {
  SoundService({AudioPlayer Function()? playerFactory})
      : _playerFactory = playerFactory ?? AudioPlayer.new;

  final AudioPlayer Function() _playerFactory;
  Set<String>? _assets;
  AudioPlayer? _music;
  AudioPlayer? _voice;
  AudioPlayer? _sfx;
  String? _currentMusic;
  bool enabled = true;
  bool musicEnabled = true;

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

  Future<void> _play(AudioPlayer? Function() get, void Function(AudioPlayer) set, String path,
      {double volume = 1, bool loop = false}) async {
    if (!enabled) return;
    try {
      if (!await _exists(path)) return;
      var p = get();
      if (p == null) {
        p = _playerFactory();
        set(p);
      }
      await p.stop();
      await p.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
      await p.setVolume(volume);
      await p.play(AssetSource('audio/$path'));
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService: $e');
    }
  }

  /// Musique de fond en boucle ('menu' ou 'game').
  Future<void> playMusic(String name) async {
    if (!musicEnabled || _currentMusic == name) return;
    _currentMusic = name;
    await _play(() => _music, (p) => _music = p, 'music/$name.mp3', volume: 0.4, loop: true);
  }

  Future<void> stopMusic() async {
    _currentMusic = null;
    try {
      await _music?.stop();
    } catch (_) {}
  }

  /// Effet sonore : 'select', 'move', 'capture', 'check', 'mate', 'turn', 'win', 'lose'.
  Future<void> playEffect(String name) =>
      _play(() => _sfx, (p) => _sfx = p, 'sfx/$name.mp3', volume: 0.8);

  static String voiceName(PieceType t) => t.name;

  /// Voix de la pièce pour un évènement : `voice/PIECE_EVENEMENT.mp3`.
  Future<void> playVoice(PieceType type, SoundEvent event) =>
      _play(() => _voice, (p) => _voice = p, 'voice/${voiceName(type)}_${event.name}.mp3');

  Future<void> dispose() async {
    for (final p in [_music, _voice, _sfx]) {
      try {
        await p?.dispose();
      } catch (_) {}
    }
  }
}
