import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';

/// Ciel de tournoi au crépuscule : dégradé, soleil bas, nuages, montagnes rocheuses
/// lointaines, étoiles et poussière d'énergie. Tout est mis en cache à la taille de l'écran ;
/// seules les positions des motifs mobiles sont recalculées à chaque image.
class ArenaBackdrop extends PositionComponent {
  ArenaBackdrop() : super(priority: -2000);

  double _t = 0;
  ui.Picture? _static;
  ui.Size _picSize = ui.Size.zero;
  static const _n = 56;
  final Float32List _dx = Float32List(_n);
  final Float32List _dy = Float32List(_n);
  final Float32List _ds = Float32List(_n);
  final Float32List _dv = Float32List(_n);
  static const _clouds = 5;
  final Float32List _cx = Float32List(_clouds);
  final Float32List _cy = Float32List(_clouds);
  final Float32List _cw = Float32List(_clouds);
  final ui.Paint _p = ui.Paint();
  final math.Random _rng = math.Random(11);
  ui.Shader? _sunShader;
  ui.Offset _sun = ui.Offset.zero;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size.clone();
    _build(size.x, size.y);
  }

  void _build(double w, double h) {
    if (w <= 0 || h <= 0) return;
    _picSize = ui.Size(w, h);
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    final rect = ui.Rect.fromLTWH(0, 0, w, h);
    c.drawRect(
        rect,
        ui.Paint()
          ..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(0, h), const [
            ui.Color(0xFF0E0B2B),
            ui.Color(0xFF2B1650),
            ui.Color(0xFF7A2F6B),
            ui.Color(0xFFE8704A),
            ui.Color(0xFFFFB86B),
          ], const [0, 0.3, 0.55, 0.78, 0.9]));
    // Étoiles.
    final star = ui.Paint()..color = const ui.Color(0xCCFFFFFF);
    for (var i = 0; i < 40; i++) {
      c.drawCircle(ui.Offset(_rng.nextDouble() * w, _rng.nextDouble() * h * 0.38),
          0.4 + _rng.nextDouble() * 0.9, star);
    }
    // Montagnes rocheuses lointaines (deux plans, arêtes anguleuses).
    _mountains(c, w, h, h * 0.62, h * 0.16, const ui.Color(0xFF3C2255), 1);
    _mountains(c, w, h, h * 0.72, h * 0.2, const ui.Color(0xFF1E1236), 2);
    // Arène lointaine : silhouette de piliers.
    final pil = ui.Paint()..color = const ui.Color(0xFF150C28);
    for (var i = 0; i < 6; i++) {
      final x = w * (0.06 + i * 0.176);
      final ph = h * (0.05 + (i % 3) * 0.02);
      c.drawRect(ui.Rect.fromLTWH(x, h * 0.86 - ph, w * 0.018, ph + h * 0.2), pil);
      c.drawRect(ui.Rect.fromLTWH(x - w * 0.006, h * 0.86 - ph - 4, w * 0.03, 5), pil);
    }
    c.drawRect(ui.Rect.fromLTWH(0, h * 0.86, w, h * 0.14), pil);
    // Voile sombre sous le plateau pour la lisibilité.
    c.drawRect(
        rect,
        ui.Paint()
          ..shader = ui.Gradient.radial(ui.Offset(w / 2, h * 0.55), math.max(w, h) * 0.7,
              const [ui.Color(0x66000000), ui.Color(0x00000000)], const [0, 1]));
    _static?.dispose();
    _static = rec.endRecording();

    _sun = ui.Offset(w * 0.72, h * 0.66);
    _sunShader = ui.Gradient.radial(ui.Offset.zero, 1,
        const [ui.Color(0xCCFFD28A), ui.Color(0x55FF8A4A), ui.Color(0x00FF8A4A)], const [0, 0.35, 1]);
    for (var i = 0; i < _n; i++) {
      _dx[i] = _rng.nextDouble() * w;
      _dy[i] = _rng.nextDouble() * h;
      _ds[i] = 0.8 + _rng.nextDouble() * 1.8;
      _dv[i] = 6 + _rng.nextDouble() * 16;
    }
    for (var i = 0; i < _clouds; i++) {
      _cx[i] = _rng.nextDouble() * w;
      _cy[i] = h * (0.18 + _rng.nextDouble() * 0.3);
      _cw[i] = w * (0.25 + _rng.nextDouble() * 0.3);
    }
  }

  void _mountains(ui.Canvas c, double w, double h, double base, double amp, ui.Color col, int seed) {
    final r = math.Random(seed * 31);
    final path = ui.Path()..moveTo(0, h);
    var x = 0.0;
    path.lineTo(0, base);
    while (x < w) {
      x += w * (0.05 + r.nextDouble() * 0.07);
      final peak = r.nextBool();
      path.lineTo(x, base - (peak ? amp * (0.4 + r.nextDouble() * 0.6) : amp * r.nextDouble() * 0.25));
    }
    path
      ..lineTo(w, h)
      ..close();
    c.drawPath(path, ui.Paint()..color = col);
  }

  @override
  void update(double dt) {
    _t += dt;
    final w = _picSize.width, h = _picSize.height;
    if (w <= 0) return;
    for (var i = 0; i < _n; i++) {
      _dy[i] -= _dv[i] * dt;
      _dx[i] += math.sin(_t * 0.8 + i) * 6 * dt;
      if (_dy[i] < -4) {
        _dy[i] = h + 4;
        _dx[i] = _rng.nextDouble() * w;
      }
    }
    for (var i = 0; i < _clouds; i++) {
      _cx[i] += (4 + i * 1.5) * dt;
      if (_cx[i] - _cw[i] > w) _cx[i] = -_cw[i];
    }
  }

  @override
  void render(ui.Canvas canvas) {
    final pic = _static;
    if (pic == null) return;
    // Le fond est dessiné en (0,0) dans l'espace du jeu.
    canvas.drawPicture(pic);
    final sh = _sunShader;
    if (sh != null) {
      canvas.save();
      canvas.translate(_sun.dx, _sun.dy);
      final pulse = 1 + 0.03 * math.sin(_t * 0.7);
      canvas.scale(_picSize.width * 0.3 * pulse);
      _p
        ..shader = sh
        ..blendMode = ui.BlendMode.plus;
      canvas.drawCircle(ui.Offset.zero, 1, _p);
      canvas.restore();
    }
    _p
      ..shader = null
      ..blendMode = ui.BlendMode.srcOver
      ..color = const ui.Color(0x22FFD9B0);
    for (var i = 0; i < _clouds; i++) {
      canvas.drawOval(
          ui.Rect.fromCenter(center: ui.Offset(_cx[i], _cy[i]), width: _cw[i], height: _cw[i] * 0.12),
          _p);
    }
    _p.blendMode = ui.BlendMode.plus;
    for (var i = 0; i < _n; i++) {
      final tw = 0.5 + 0.5 * math.sin(_t * 2 + i * 1.3);
      _p.color = ui.Color.fromARGB((50 + 90 * tw).round(), 255, 190, 110);
      canvas.drawCircle(ui.Offset(_dx[i], _dy[i]), _ds[i], _p);
    }
    _p.blendMode = ui.BlendMode.srcOver;
  }
}
