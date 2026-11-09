import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/animation.dart' show Curves;

/// Caméra 2D du plateau : zoom ×1 à ×3,5 et panoramique, indépendante de Flame (testable).
///
/// Le « monde » est l'écran de la vue entière (coordonnées de base calculées par la mise en
/// page) ; l'écran réel est `monde * zoom + pan`.
class BoardCamera {
  static const double minZoom = 1;
  static const double maxZoom = 3.5;
  static const double doubleTapZoom = 2.2;
  static const double animSeconds = 0.22;

  /// Zone d'écran occupée par le plateau en vue entière (coordonnées monde).
  Rect content = Rect.zero;
  Size viewport = Size.zero;

  double zoom = 1;
  Offset pan = Offset.zero;

  /// Incrémenté à chaque changement de zoom/pan.
  int version = 0;

  /// Vrai tant qu'un doigt manipule la caméra.
  bool gestureActive = false;

  // Animation (easing) et inertie.
  double _animT = -1;
  double _fromZoom = 1, _toZoom = 1;
  Offset _fromPan = Offset.zero, _toPan = Offset.zero;
  Offset _velocity = Offset.zero;
  double _sinceChange = 1;

  bool get zoomed => zoom > 1.02;
  bool get animating => _animT >= 0;
  bool get inertia => _velocity != Offset.zero;

  /// Pas de mouvement en cours : on peut re-rendre le plateau en haute résolution.
  bool get settled => !gestureActive && !animating && !inertia && _sinceChange > 0.12;

  Offset toWorld(Offset screen) => (screen - pan) / zoom;
  Offset toScreen(Offset world) => world * zoom + pan;

  void setViewport(Size size, Rect contentRect) {
    viewport = size;
    content = contentRect;
    _set(zoom, pan);
  }

  /// Déplacement admissible pour un zoom donné : le plateau couvre l'écran (ou reste centré
  /// quand il est plus petit que l'écran sur l'axe).
  Offset clampPan(Offset p, double z) {
    double axis(double v, double view, double lo, double hi) {
      final min = view - hi * z, max = -lo * z;
      if (min >= max) return (min + max) / 2;
      return math.min(math.max(v, min), max);
    }

    return Offset(axis(p.dx, viewport.width, content.left, content.right),
        axis(p.dy, viewport.height, content.top, content.bottom));
  }

  void _set(double z, Offset p) {
    final nz = z.clamp(minZoom, maxZoom).toDouble();
    final np = clampPan(p, nz);
    if (nz != zoom || np != pan) {
      zoom = nz;
      pan = np;
      version++;
      _sinceChange = 0;
    }
  }

  /// Zoom immédiat autour du point d'écran [focus].
  void zoomAt(Offset focus, double newZoom) {
    final z = newZoom.clamp(minZoom, maxZoom).toDouble();
    _set(z, focus - (focus - pan) * (z / zoom));
  }

  void panBy(Offset delta) => _set(zoom, pan + delta);

  void stop() {
    _animT = -1;
    _velocity = Offset.zero;
  }

  void reset() => animateTo(1, Offset.zero);

  void animateTo(double z, Offset p) {
    _velocity = Offset.zero;
    _fromZoom = zoom;
    _fromPan = pan;
    _toZoom = z.clamp(minZoom, maxZoom).toDouble();
    _toPan = clampPan(p, _toZoom);
    _animT = 0;
  }

  /// Zoom animé autour d'un point d'écran.
  void animateZoomAt(Offset focus, double z) {
    final nz = z.clamp(minZoom, maxZoom).toDouble();
    animateTo(nz, focus - (focus - pan) * (nz / zoom));
  }

  /// Double tap : zoom ×2,2 sur le point touché, ou retour à la vue entière si déjà zoomé.
  void doubleTap(Offset screen) {
    if (zoomed) {
      reset();
    } else {
      animateZoomAt(screen, doubleTapZoom);
    }
  }

  /// Centre (animé) l'écran sur un point du monde en gardant le zoom.
  void centerOn(Offset world) {
    animateTo(zoom, Offset(viewport.width / 2, viewport.height / 2) - world * zoom);
  }

  /// Fin d'un glissé : inertie légère.
  void fling(Offset velocity) {
    if (!zoomed || velocity.distance < 150) return;
    _animT = -1;
    _velocity = velocity;
  }

  /// Avance les animations ; renvoie vrai si la caméra a bougé.
  bool update(double dt) {
    final before = version;
    _sinceChange += dt;
    if (_animT >= 0) {
      _animT += dt;
      final k = Curves.easeOutCubic.transform((_animT / animSeconds).clamp(0.0, 1.0));
      _set(_fromZoom + (_toZoom - _fromZoom) * k, Offset.lerp(_fromPan, _toPan, k)!);
      if (_animT >= animSeconds) _animT = -1;
    } else if (_velocity != Offset.zero) {
      final prev = pan;
      _set(zoom, pan + _velocity * dt);
      // Bloqué contre un bord : on annule la composante correspondante.
      final moved = pan - prev;
      var vx = _velocity.dx, vy = _velocity.dy;
      if ((moved.dx - _velocity.dx * dt).abs() > 1e-6) vx = 0;
      if ((moved.dy - _velocity.dy * dt).abs() > 1e-6) vy = 0;
      final decay = math.exp(-5 * dt);
      _velocity = Offset(vx * decay, vy * decay);
      if (_velocity.distance < 20) _velocity = Offset.zero;
    }
    return version != before;
  }
}
