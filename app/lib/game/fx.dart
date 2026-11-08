import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, FontWeight, FontStyle, TextDirection, Shadow;

/// Pool de particules à capacité fixe (tableaux typés, aucun objet par particule).
/// Une particule émise écrase la plus ancienne quand le pool est plein.
class ParticlePool {
  ParticlePool([this.capacity = 900])
      : x = Float32List(capacity),
        y = Float32List(capacity),
        vx = Float32List(capacity),
        vy = Float32List(capacity),
        life = Float32List(capacity),
        maxLife = Float32List(capacity),
        size = Float32List(capacity),
        gravity = Float32List(capacity),
        color = Int32List(capacity),
        additive = Uint8List(capacity);

  final int capacity;
  final Float32List x, y, vx, vy, life, maxLife, size, gravity;
  final Int32List color;
  final Uint8List additive;
  int _next = 0;
  final math.Random rng = math.Random(7);
  final ui.Paint _paint = ui.Paint();

  int get aliveCount {
    var n = 0;
    for (var i = 0; i < capacity; i++) {
      if (life[i] > 0) n++;
    }
    return n;
  }

  void emit(double px, double py, double pvx, double pvy, double lifeS, double sz, ui.Color c,
      {double g = 0, bool glow = true}) {
    final i = _next;
    _next = (_next + 1) % capacity;
    x[i] = px;
    y[i] = py;
    vx[i] = pvx;
    vy[i] = pvy;
    life[i] = lifeS;
    maxLife[i] = lifeS;
    size[i] = sz;
    gravity[i] = g;
    color[i] = c.toARGB32();
    additive[i] = glow ? 1 : 0;
  }

  /// Explosion radiale de [count] particules.
  void burst(double cx, double cy, int count, double speed, double sz, ui.Color c,
      {double lifeS = 0.7, double g = 0, bool glow = true}) {
    for (var i = 0; i < count; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final s = speed * (0.25 + rng.nextDouble() * 0.75);
      emit(cx, cy, math.cos(a) * s, math.sin(a) * s * 0.8, lifeS * (0.5 + rng.nextDouble() * 0.6),
          sz * (0.5 + rng.nextDouble() * 0.8), c,
          g: g, glow: glow);
    }
  }

  void update(double dt) {
    for (var i = 0; i < capacity; i++) {
      if (life[i] <= 0) continue;
      life[i] -= dt;
      x[i] += vx[i] * dt;
      y[i] += vy[i] * dt;
      vy[i] += gravity[i] * dt;
      final drag = 1 - 1.5 * dt;
      vx[i] *= drag;
      vy[i] *= drag;
    }
  }

  void render(ui.Canvas canvas) {
    for (var i = 0; i < capacity; i++) {
      final l = life[i];
      if (l <= 0) continue;
      final k = l / maxLife[i];
      final argb = color[i];
      final a = (((argb >>> 24) & 0xFF) * math.min(1.0, k * 1.6)).round();
      _paint
        ..color = ui.Color((a << 24) | (argb & 0x00FFFFFF))
        ..blendMode = additive[i] == 1 ? ui.BlendMode.plus : ui.BlendMode.srcOver;
      canvas.drawCircle(ui.Offset(x[i], y[i]), size[i] * (0.35 + 0.65 * k), _paint);
    }
  }
}

/// Composant qui met à jour et dessine le pool (au-dessus des pièces).
class ParticleLayer extends Component {
  ParticleLayer(this.pool) : super(priority: 99999);
  final ParticlePool pool;

  @override
  void update(double dt) => pool.update(dt);

  @override
  void render(ui.Canvas canvas) => pool.render(canvas);
}

/// Services d'effets partagés par le jeu et la galerie : particules, tremblement de caméra,
/// hitstop (ralenti de 80 ms) et bannières de texte.
mixin FxHost on FlameGame {
  final ParticlePool pool = ParticlePool();
  double _shakeAmp = 0;
  double _shakeLeft = 0;
  double _shakeDur = 0.3;
  double _shakeClock = 0;
  double _hitstop = 0;

  /// Nombre de hitstops déclenchés (utile pour les tests).
  int hitstopCount = 0;
  int shakeCount = 0;

  Future<void> initFx() async => add(ParticleLayer(pool));

  void shake(double amplitude, [double duration = 0.35]) {
    shakeCount++;
    _shakeAmp = math.max(_shakeAmp * (_shakeLeft > 0 ? 1 : 0), amplitude);
    _shakeLeft = duration;
    _shakeDur = duration;
  }

  void hitstop([double seconds = 0.08]) {
    hitstopCount++;
    _hitstop = seconds;
  }

  void showBanner(String text, ui.Color color,
      {double seconds = 1.4, double sizeFactor = 0.17, ui.Color? outline}) {
    add(BannerText(
      text: text,
      color: color,
      outline: outline ?? const ui.Color(0xFF1A0A20),
      seconds: seconds,
      fontSize: math.min(size.x * sizeFactor, 110),
    )..position = Vector2(size.x / 2, size.y * 0.3));
  }

  @override
  void update(double dt) {
    var d = dt;
    if (_hitstop > 0) {
      _hitstop -= dt;
      d = dt * 0.08;
    }
    if (_shakeLeft > 0) {
      _shakeLeft -= dt;
      _shakeClock += dt;
    } else {
      _shakeAmp = 0;
    }
    super.update(d);
  }

  @override
  void render(ui.Canvas canvas) {
    if (_shakeLeft > 0 && _shakeAmp > 0) {
      final k = (_shakeLeft / _shakeDur).clamp(0.0, 1.0);
      final a = _shakeAmp * k * k;
      canvas.save();
      canvas.translate(math.sin(_shakeClock * 83) * a, math.cos(_shakeClock * 67) * a * 0.8);
      super.render(canvas);
      canvas.restore();
    } else {
      super.render(canvas);
    }
  }
}

/// Texte stylisé (« ÉCHEC ! », « MAT ! ») : apparition en rebond, maintien, fondu.
class BannerText extends PositionComponent {
  BannerText({
    required String text,
    required this.color,
    required this.outline,
    required this.seconds,
    required double fontSize,
  }) : super(anchor: Anchor.center, priority: 100002) {
    TextPainter make(ui.Paint? stroke, ui.Color? fill, {bool shadow = false}) => TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              letterSpacing: fontSize * 0.04,
              color: fill,
              foreground: stroke,
              shadows: shadow
                  ? [Shadow(color: color.withAlpha(180), blurRadius: fontSize * 0.25)]
                  : null,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
    _stroke = make(
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = fontSize * 0.14
          ..strokeJoin = ui.StrokeJoin.round
          ..color = outline,
        null,
        shadow: true);
    _fill = make(null, const ui.Color(0xFFFFFFFF));
    _tint = make(null, color);
    size = Vector2(_fill.width, _fill.height);
  }

  final ui.Color color;
  final ui.Color outline;
  final double seconds;
  late final TextPainter _stroke;
  late final TextPainter _fill;
  late final TextPainter _tint;
  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= seconds) removeFromParent();
  }

  @override
  void render(ui.Canvas canvas) {
    final pop = _t < 0.28 ? Curves.elasticOut.transform(_t / 0.28) : 1.0;
    final fade = _t > seconds - 0.3 ? ((seconds - _t) / 0.3).clamp(0.0, 1.0) : 1.0;
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.rotate(-0.1);
    canvas.scale(math.max(0.01, pop) * (1 + 0.04 * math.sin(_t * 18)));
    canvas.translate(-size.x / 2, -size.y / 2);
    canvas.saveLayer(
        ui.Rect.fromLTWH(-40, -40, size.x + 80, size.y + 80),
        ui.Paint()..color = ui.Color.fromARGB((fade * 255).round(), 255, 255, 255));
    _stroke.paint(canvas, ui.Offset.zero);
    _tint.paint(canvas, ui.Offset.zero);
    // Reflet : moitié haute plus claire.
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(0, 0, size.x, size.y * 0.45));
    _fill.paint(canvas, ui.Offset.zero);
    canvas.restore();
    canvas.restore();
    canvas.restore();
  }
}

/// Anneau de choc au sol (ellipse aplatie qui s'étend) ; composant à usage unique.
class ShockRing extends PositionComponent {
  ShockRing({
    required Vector2 center,
    required this.maxRadius,
    required this.color,
    this.seconds = 0.5,
    this.squash = 0.45,
    this.delay = 0,
  }) : super(position: center, anchor: Anchor.center, priority: 99990);
  final double maxRadius;
  final ui.Color color;
  final double seconds;
  final double squash;
  final double delay;
  double _t = 0;
  final ui.Paint _p = ui.Paint()..style = ui.PaintingStyle.stroke;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= seconds + delay) removeFromParent();
  }

  @override
  void render(ui.Canvas canvas) {
    final t = (_t - delay) / seconds;
    if (t <= 0) return;
    final k = Curves.easeOut.transform(t.clamp(0.0, 1.0));
    final r = maxRadius * k;
    final a = ((1 - k) * 255).round();
    _p
      ..strokeWidth = maxRadius * 0.16 * (1 - k) + 1.5
      ..color = color.withAlpha((a * 0.7).round());
    canvas.drawOval(ui.Rect.fromCenter(center: ui.Offset.zero, width: r * 2, height: r * 2 * squash), _p);
    _p
      ..strokeWidth = maxRadius * 0.05 * (1 - k) + 1
      ..color = ui.Color.fromARGB(a, 255, 255, 255);
    canvas.drawOval(
        ui.Rect.fromCenter(center: ui.Offset.zero, width: r * 1.8, height: r * 1.8 * squash), _p);
  }
}
