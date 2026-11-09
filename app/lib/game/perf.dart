import 'dart:typed_data';
import 'dart:ui' as ui;

/// Sous-systèmes mesurés par [PerfStats] (temps CPU de mise à jour + enregistrement du dessin).
enum PerfSub { backdrop, board, pieces, fx }

/// Compteurs de temps CPU par sous-système, sans allocation : une horloge unique toujours
/// démarrée, des cumuls en microsecondes, et une moyenne glissante par image.
class PerfStats {
  PerfStats._();

  static final Stopwatch _clock = Stopwatch()..start();
  static final Float64List _acc = Float64List(PerfSub.values.length);
  static final Float64List _last = Float64List(PerfSub.values.length);
  static final Float64List _avg = Float64List(PerfSub.values.length);
  static int frames = 0;

  /// Horodatage courant (µs) à passer à [add].
  static int now() => _clock.elapsedMicroseconds;

  /// Ajoute le temps écoulé depuis [start] au sous-système [s].
  static void add(PerfSub s, int start) => _acc[s.index] += _clock.elapsedMicroseconds - start;

  /// Clôt une image : les cumuls deviennent la dernière image et alimentent la moyenne.
  static void endFrame() {
    for (var i = 0; i < _acc.length; i++) {
      _last[i] = _acc[i];
      _avg[i] = frames == 0 ? _acc[i] : _avg[i] * 0.9 + _acc[i] * 0.1;
      _acc[i] = 0;
    }
    frames++;
  }

  /// Temps (ms) de la dernière image complète.
  static double lastMs(PerfSub s) => _last[s.index] / 1000;

  /// Moyenne glissante (ms).
  static double avgMs(PerfSub s) => _avg[s.index] / 1000;

  static void reset() {
    for (var i = 0; i < _acc.length; i++) {
      _acc[i] = 0;
      _last[i] = 0;
      _avg[i] = 0;
    }
    frames = 0;
  }
}

/// Réglages des optimisations de rendu (tous actifs par défaut ; le banc d'essai les
/// désactive pour mesurer l'« avant »).
class PerfConfig {
  PerfConfig._();

  /// Pièces, surlignages, particules et effets hors du rectangle visible : ni mis à jour ni dessinés.
  static bool culling = true;

  /// Guerriers au repos dessinés depuis l'atlas de sprites (drawAtlas) plutôt qu'en vectoriel.
  static bool spriteCache = true;

  /// Pendant un pan/zoom : traînées et particules ambiantes coupées, ressorts gelés.
  static bool gestureLite = true;

  /// Plateau haute résolution re-rendu en asynchrone, par tuiles visibles.
  static bool asyncBoard = true;

  /// Taille maximale d'une texture (plateau, atlas).
  static const int maxTexture = 2048;

  static void setAll(bool on) {
    culling = on;
    spriteCache = on;
    gestureLite = on;
    asyncBoard = on;
  }
}

/// Ce dont les composants ont besoin pour se rendre « au plus juste ».
abstract class CullHost {
  /// Rectangle visible en coordonnées monde (marge comprise), ou null (pas de culling).
  ui.Rect? get cullRect;

  /// Vrai pendant un pan/zoom (doigt posé, animation ou inertie de la caméra).
  bool get cameraMoving;
}

/// Teste qu'un rectangle centré (cx, cy) de demi-taille (hw, hh) touche [r] (null = visible).
bool cullVisible(ui.Rect? r, double cx, double cy, double hw, double hh) =>
    r == null || (cx + hw >= r.left && cx - hw <= r.right && cy + hh >= r.top && cy - hh <= r.bottom);

/// Densité de pixels de l'écran (1..3).
double deviceRatio() {
  try {
    return ui.PlatformDispatcher.instance.views.first.devicePixelRatio.clamp(1.0, 3.0);
  } catch (_) {
    return 2;
  }
}
