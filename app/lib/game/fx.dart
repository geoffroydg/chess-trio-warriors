import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, FontWeight, FontStyle, TextDirection, Shadow;

/// Textures d'effets (app/assets/fx, CC0) regroupées dans un atlas 8 x 128 px.
enum Fx { glow, smokeA, smokeB, spark, star, trace, flare, flame }

class FxAtlas {
  static const cell = 128.0;
  static const files = ['glow', 'smoke_a', 'smoke_b', 'spark', 'star', 'trace', 'flare', 'flame'];
  static ui.Image? _image;
  static bool _fromAssets = false;
  static Future<void>? _loading;

  /// Atlas courant : textures des assets si chargées, sinon repli procédural (synchrone).
  static ui.Image get image => _image ??= _procedural();
  static bool get fromAssets => _fromAssets;

  static ui.Rect rect(Fx f) => ui.Rect.fromLTWH(f.index * cell, 0, cell, cell);

  /// Charge les PNG de app/assets/fx (non bloquant pour le jeu : le repli sert en attendant).
  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final imgs = <ui.Image>[];
      for (final f in files) {
        final data = await rootBundle.load('assets/fx/$f.png');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        imgs.add((await codec.getNextFrame()).image);
      }
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      final p = ui.Paint()..filterQuality = ui.FilterQuality.medium;
      for (var i = 0; i < imgs.length; i++) {
        final im = imgs[i];
        c.drawImageRect(im, ui.Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
            ui.Rect.fromLTWH(i * cell, 0, cell, cell), p);
      }
      _image = await rec.endRecording().toImage((cell * files.length).round(), cell.round());
      _fromAssets = true;
    } catch (_) {
      _loading = null; // repli procédural conservé
    }
  }

  /// Textures équivalentes dessinées en code (halo, fumée, étincelle, étoile, traînée...).
  static ui.Image _procedural() {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    const h = cell / 2;
    const white = ui.Color(0xFFFFFFFF);
    const clear = ui.Color(0x00FFFFFF);
    ui.Paint radial(double cx, double r, List<ui.Color> cols, [List<double>? stops]) =>
        ui.Paint()..shader = ui.Gradient.radial(ui.Offset(cx, h), r, cols, stops);
    for (final f in Fx.values) {
      final cx = f.index * cell + h;
      final o = ui.Offset(cx, h);
      switch (f) {
        case Fx.glow:
          c.drawCircle(o, h, radial(cx, h, [white, const ui.Color(0x88FFFFFF), clear], [0, 0.25, 1]));
        case Fx.smokeA:
        case Fx.smokeB:
          final rng = math.Random(f.index * 31);
          final p = ui.Paint()..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9);
          for (var i = 0; i < 9; i++) {
            final a = rng.nextDouble() * math.pi * 2, d = rng.nextDouble() * h * 0.4;
            p.color = ui.Color.fromARGB(60 + rng.nextInt(60), 255, 255, 255);
            c.drawCircle(o + ui.Offset(math.cos(a) * d, math.sin(a) * d), h * (0.25 + rng.nextDouble() * 0.25), p);
          }
        case Fx.spark:
          final p = ui.Paint()
            ..color = white
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2);
          c.drawPath(_star(o, 4, h * 0.95, h * 0.07), p);
          c.drawCircle(o, h * 0.35, radial(cx, h * 0.35, [white, clear]));
        case Fx.star:
          c.drawPath(_star(o, 5, h * 0.85, h * 0.35),
              ui.Paint()
                ..color = white
                ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4));
        case Fx.trace:
          c.drawOval(ui.Rect.fromCenter(center: o, width: cell * 0.95, height: cell * 0.12),
              ui.Paint()
                ..color = white
                ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4));
        case Fx.flare:
          c.drawCircle(o, h * 0.62,
              ui.Paint()
                ..style = ui.PaintingStyle.stroke
                ..strokeWidth = 4
                ..color = const ui.Color(0xAAFFFFFF)
                ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3));
          c.drawPath(_star(o, 4, h * 0.9, h * 0.05), ui.Paint()..color = white);
          c.drawCircle(o, h * 0.3, radial(cx, h * 0.3, [white, clear]));
        case Fx.flame:
          final path = ui.Path()
            ..moveTo(cx, 6)
            ..cubicTo(cx + h * 0.2, h * 0.6, cx + h * 0.75, h * 1.2, cx, cell - 8)
            ..cubicTo(cx - h * 0.75, h * 1.2, cx - h * 0.2, h * 0.6, cx, 6)
            ..close();
          c.drawPath(
              path,
              ui.Paint()
                ..shader = ui.Gradient.radial(ui.Offset(cx, h * 1.4), h * 1.1, [white, const ui.Color(0x66FFFFFF), clear],
                    [0, 0.5, 1])
                ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5));
      }
    }
    return rec.endRecording().toImageSync((cell * Fx.values.length).round(), cell.round());
  }

  static ui.Path _star(ui.Offset o, int n, double r0, double r1) {
    final p = ui.Path();
    for (var i = 0; i < n * 2; i++) {
      final a = -math.pi / 2 + i * math.pi / n;
      final r = i.isEven ? r0 : r1;
      final pt = o + ui.Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }
}

/// Lot de sprites de l'atlas dessinés en un seul appel (drawRawAtlas), tableaux préalloués.
class SpriteBatch {
  SpriteBatch(this.capacity)
      : _xf = Float32List(capacity * 4),
        _rc = Float32List(capacity * 4),
        _col = Int32List(capacity);

  final int capacity;
  final Float32List _xf, _rc;
  final Int32List _col;
  int length = 0;
  final ui.Paint _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;
  // Vues mises en cache par taille (aucune allocation en régime établi).
  final Map<int, (Float32List, Float32List, Int32List)> _views = {};

  void clear() => length = 0;

  /// Ajoute un sprite centré en (x, y), de diamètre [size] px, teinté par [argb].
  void add(Fx f, double x, double y, double size, int argb, {double rot = 0}) {
    if (length >= capacity || size <= 0.01 || (argb >>> 24) == 0) return;
    final i = length++;
    final sc = size / FxAtlas.cell;
    final cs = math.cos(rot) * sc, sn = math.sin(rot) * sc;
    const h = FxAtlas.cell / 2;
    _xf[i * 4] = cs;
    _xf[i * 4 + 1] = sn;
    _xf[i * 4 + 2] = x - cs * h + sn * h;
    _xf[i * 4 + 3] = y - sn * h - cs * h;
    final l = f.index * FxAtlas.cell;
    _rc[i * 4] = l;
    _rc[i * 4 + 1] = 0;
    _rc[i * 4 + 2] = l + FxAtlas.cell;
    _rc[i * 4 + 3] = FxAtlas.cell;
    _col[i] = argb;
  }

  void addColor(Fx f, double x, double y, double size, ui.Color c, {double rot = 0, double alpha = 1}) {
    final a = (c.a * 255 * alpha).round().clamp(0, 255);
    add(f, x, y, size, (a << 24) | (c.toARGB32() & 0x00FFFFFF), rot: rot);
  }

  /// Dessine puis vide le lot ; [additive] : mélange BlendMode.plus.
  void flush(ui.Canvas canvas, {bool additive = true}) {
    final n = length;
    if (n == 0) return;
    final v = _views.putIfAbsent(n, () => (
          Float32List.sublistView(_xf, 0, n * 4),
          Float32List.sublistView(_rc, 0, n * 4),
          Int32List.sublistView(_col, 0, n),
        ));
    _paint.blendMode = additive ? ui.BlendMode.plus : ui.BlendMode.srcOver;
    canvas.drawRawAtlas(FxAtlas.image, v.$1, v.$2, v.$3, ui.BlendMode.modulate, null, _paint);
    length = 0;
  }
}

/// Dessin immédiat d'un sprite (effets ponctuels : impacts, orbes, halos).
final SpriteBatch _one = SpriteBatch(32);
void drawFxSprite(ui.Canvas canvas, Fx f, ui.Offset at, double size, ui.Color color,
    {double rot = 0, bool additive = true, double alpha = 1}) {
  _one.addColor(f, at.dx, at.dy, size, color, rot: rot, alpha: alpha);
  _one.flush(canvas, additive: additive);
}

/// Pool de particules à capacité fixe (tableaux typés, aucun objet par particule),
/// rendues en sprites texturés (atlas CC0) par lots additifs / normaux.
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
        rot = Float32List(capacity),
        spin = Float32List(capacity),
        color = Int32List(capacity),
        additive = Uint8List(capacity),
        sprite = Uint8List(capacity),
        _add = SpriteBatch(capacity),
        _norm = SpriteBatch(capacity);

  final int capacity;
  final Float32List x, y, vx, vy, life, maxLife, size, gravity, rot, spin;
  final Int32List color;
  final Uint8List additive, sprite;
  final SpriteBatch _add, _norm;
  int _next = 0;
  final math.Random rng = math.Random(7);

  int get aliveCount {
    var n = 0;
    for (var i = 0; i < capacity; i++) {
      if (life[i] > 0) n++;
    }
    return n;
  }

  void emit(double px, double py, double pvx, double pvy, double lifeS, double sz, ui.Color c,
      {double g = 0, bool glow = true, Fx? fx}) {
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
    sprite[i] = (fx ?? (glow ? Fx.glow : Fx.smokeA)).index;
    rot[i] = rng.nextDouble() * math.pi * 2;
    spin[i] = (rng.nextDouble() - 0.5) * 4;
  }

  /// Explosion radiale de [count] particules.
  void burst(double cx, double cy, int count, double speed, double sz, ui.Color c,
      {double lifeS = 0.7, double g = 0, bool glow = true, Fx? fx}) {
    for (var i = 0; i < count; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final s = speed * (0.25 + rng.nextDouble() * 0.75);
      emit(cx, cy, math.cos(a) * s, math.sin(a) * s * 0.8, lifeS * (0.5 + rng.nextDouble() * 0.6),
          sz * (0.5 + rng.nextDouble() * 0.8), c,
          g: g, glow: glow, fx: fx);
    }
  }

  void update(double dt) {
    for (var i = 0; i < capacity; i++) {
      if (life[i] <= 0) continue;
      life[i] -= dt;
      x[i] += vx[i] * dt;
      y[i] += vy[i] * dt;
      vy[i] += gravity[i] * dt;
      rot[i] += spin[i] * dt;
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
      final f = Fx.values[sprite[i]];
      final smoke = f == Fx.smokeA || f == Fx.smokeB;
      // La fumée grossit en vieillissant ; les lueurs rétrécissent.
      final s = size[i] * 3.2 * (smoke ? (1.6 - 0.8 * k) : (0.35 + 0.65 * k));
      (additive[i] == 1 ? _add : _norm)
          .add(f, x[i], y[i], s, (a << 24) | (argb & 0x00FFFFFF), rot: rot[i]);
    }
    _norm.flush(canvas, additive: false);
    _add.flush(canvas, additive: true);
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

  Future<void> initFx() async {
    FxAtlas.image; // repli procédural prêt immédiatement
    FxAtlas.load(); // textures CC0 des assets (asynchrone)
    add(ParticleLayer(pool));
    add(FpsOverlay(this));
  }

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

  /// Durée réelle de la dernière image (avant hitstop), pour l'overlay FPS.
  double lastFrameDt = 1 / 60;

  @override
  void update(double dt) {
    lastFrameDt = dt;
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
    if (k < 0.5) {
      drawFxSprite(canvas, Fx.glow, ui.Offset.zero, maxRadius * (0.8 + k), color, alpha: (1 - k * 2) * 0.8);
    }
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

/// Options de débogage (réglées dans Réglages, persistées par Storage).
class DebugFlags {
  static final ValueNotifier<bool> showFps = ValueNotifier(false);
}

/// Overlay de débogage : images/s lissées, temps d'image, particules vivantes.
class FpsOverlay extends Component {
  FpsOverlay(this.host) : super(priority: 1 << 30);
  final FxHost host;
  double _acc = 0;
  int _frames = 0;
  double _worst = 0;
  TextPainter? _tp;
  final ui.Paint _bg = ui.Paint()..color = const ui.Color(0xAA000000);

  @override
  void update(double dt) {
    if (!DebugFlags.showFps.value) {
      _tp = null;
      return;
    }
    final real = host.lastFrameDt;
    _acc += real;
    _frames++;
    _worst = math.max(_worst, real);
    if (_acc >= 0.5 || _tp == null) {
      final fps = _acc > 0 ? _frames / _acc : 0;
      final text = '${fps.toStringAsFixed(0)} img/s · pire ${(_worst * 1000).toStringAsFixed(1)} ms'
          ' · ${host.pool.aliveCount} particules';
      _tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fps >= 55 ? const ui.Color(0xFF7CFF8A) : (fps >= 40 ? const ui.Color(0xFFFFD34D) : const ui.Color(0xFFFF5A5A)))),
        textDirection: TextDirection.ltr,
      )..layout();
      _acc = 0;
      _frames = 0;
      _worst = 0;
    }
  }

  @override
  void render(ui.Canvas canvas) {
    final tp = _tp;
    if (tp == null || !DebugFlags.showFps.value) return;
    canvas.drawRRect(
        ui.RRect.fromLTRBR(4, 4, tp.width + 16, tp.height + 12, const ui.Radius.circular(6)), _bg);
    tp.paint(canvas, const ui.Offset(10, 8));
  }
}
