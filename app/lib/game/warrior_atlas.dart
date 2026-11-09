import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Component;

import '../models/protocol.dart';
import 'fx.dart';
import 'perf.dart';
import 'rig/skeleton.dart';
import 'rig/warrior_defs.dart';
import 'rig/warrior_rig.dart';
import 'warrior_art.dart';
import 'warrior_piece.dart';

/// Palier de résolution de l'atlas : pixels physiques par unité d'art, images du clip IDLE.
class AtlasTier {
  const AtlasTier(this.ppu, this.frames);
  final double ppu;
  final int frames;
}

/// Trois paliers selon le zoom (vue entière, zoom moyen, zoom fort). Au-delà du dernier, les
/// sprites sont légèrement agrandis.
const atlasTiers = [AtlasTier(32, 12), AtlasTier(56, 12), AtlasTier(88, 6)];

/// Palier adapté à une densité voulue (pixels physiques par unité d'art).
int atlasTierFor(double needPpu) {
  for (var i = 0; i < atlasTiers.length; i++) {
    if (atlasTiers[i].ppu >= needPpu * 0.8) return i;
  }
  return atlasTiers.length - 1;
}

/// Taille maximale d'une page d'atlas (une seule texture : un seul appel drawAtlas).
const atlasMaxTexture = 4096;

/// Emprise (unités d'art, pieds en 0,0, face +x) des guerriers au repos ou pétrifiés,
/// mesurée sur le rendu et élargie d'une marge.
const _typeBounds = <PieceType, List<double>>{
  PieceType.king: [-1.05, -3.2, 1.35, 0.25],
  PieceType.queen: [-1.6, -2.95, 1.05, 0.25],
  PieceType.rook: [-1.2, -2.95, 1.6, 0.25],
  PieceType.bishop: [-1.55, -3.45, 1.1, 0.25],
  PieceType.knight: [-1.7, -3.1, 1.1, 0.25],
  PieceType.pawn: [-1.2, -2.8, 1.05, 0.25],
};
const _socleBounds = [-1.6, -0.65, 1.6, 0.8];
const _shadowBounds = [-2.7, -1.0, 2.7, 1.3];

/// Rayon d'un pion en unités d'art (une unité = 0,72 rayon).
const double _r = 1 / 0.72;

/// Atlas prêt à l'emploi : une texture, et pour chaque cellule sa région et son point
/// d'ancrage (pieds), en pixels de la texture.
class WarriorAtlasData {
  WarriorAtlasData._(this.tier, this.frames, this.ppu, this.outlinePx, this.cells, this.orb, this.image);

  final int tier;
  final int frames;
  final double ppu;
  final double outlinePx;

  /// 6 valeurs par cellule : gauche, haut, droite, bas, ancrage x, ancrage y.
  final Float32List cells;

  /// Position (unités d'art) de l'orbe du bâton du fou pour chaque image du clip.
  final Float32List orb;
  final ui.Image image;

  int idle(PieceType t, int owner, int frame) => (t.index * 3 + owner) * frames + frame;
  int petrified(PieceType t) => 18 * frames + t.index;

  /// Socle : 0..2 joueurs, 3 pierre.
  int socle(int palette) => 18 * frames + 6 + palette;
  int get shadow => 18 * frames + 10;
  int get count => 18 * frames + 11;

  static int cellCount(int frames) => 18 * frames + 11;

  void dispose() => image.dispose();
}

/// Construction incrémentale d'un atlas : quelques cellules par image (budget en µs), puis
/// rastérisation asynchrone (Picture.toImage).
class _AtlasBuild {
  _AtlasBuild(this.tier, this.outlinePx)
      : frames = atlasTiers[tier].frames,
        ppu = atlasTiers[tier].ppu,
        // Même niveau de détail que le rendu vectoriel des pièces de l'anneau extérieur.
        lod = WarriorPiece.lodFor(outlinePx / 0.72) {
    final n = WarriorAtlasData.cellCount(frames);
    cells = Float32List(n * 6);
    orb = Float32List(frames * 2);
    _plan();
    _jobs.add(_drawStatic);
    for (final t in PieceType.values) {
      _jobs.add(() => _startType(t));
      final p = idlePeriod(t);
      final chunks = (2 * p / 0.5).ceil();
      for (var i = 0; i < chunks; i++) {
        _jobs.add(() => _advance(2 * p / chunks));
      }
      for (var k = 0; k < frames; k++) {
        _jobs.add(() => _frame(t, k, p));
      }
      _jobs.add(() => _petrified(t));
    }
  }

  final int tier;
  final int frames;
  final double ppu;
  final double outlinePx;
  final int lod;
  late final Float32List cells;
  late final Float32List orb;
  int width = 0, height = 0;
  final ui.PictureRecorder _rec = ui.PictureRecorder();
  late final ui.Canvas _c = ui.Canvas(_rec);
  final List<void Function()> _jobs = [];
  int _next = 0;
  WarriorRig? _rig;
  bool cancelled = false;
  bool failed = false;
  bool get recorded => _next >= _jobs.length;
  WarriorAtlasData? result;

  void _plan() {
    final n = WarriorAtlasData.cellCount(frames);
    final sizes = Float32List(n * 2);
    final anchors = Float32List(n * 2);
    void set(int i, List<double> b) {
      sizes[i * 2] = ((b[2] - b[0]) * ppu).ceilToDouble();
      sizes[i * 2 + 1] = ((b[3] - b[1]) * ppu).ceilToDouble();
      anchors[i * 2] = -b[0] * ppu;
      anchors[i * 2 + 1] = -b[1] * ppu;
    }

    for (final t in PieceType.values) {
      for (var o = 0; o < 3; o++) {
        for (var k = 0; k < frames; k++) {
          set((t.index * 3 + o) * frames + k, _typeBounds[t]!);
        }
      }
      set(18 * frames + t.index, _typeBounds[t]!);
    }
    for (var p = 0; p < 4; p++) {
      set(18 * frames + 6 + p, _socleBounds);
    }
    set(18 * frames + 10, _shadowBounds);

    // Rangées (« shelf packing ») ; 2 px de marge contre le débordement du filtrage.
    for (final maxW in const [2048, atlasMaxTexture]) {
      var x = 0.0, y = 0.0, row = 0.0, w = 0.0;
      for (var i = 0; i < n; i++) {
        final cw = sizes[i * 2] + 2, ch = sizes[i * 2 + 1] + 2;
        if (x + cw > maxW) {
          x = 0;
          y += row;
          row = 0;
        }
        cells[i * 6] = x + 1;
        cells[i * 6 + 1] = y + 1;
        cells[i * 6 + 2] = x + 1 + sizes[i * 2];
        cells[i * 6 + 3] = y + 1 + sizes[i * 2 + 1];
        cells[i * 6 + 4] = anchors[i * 2];
        cells[i * 6 + 5] = anchors[i * 2 + 1];
        x += cw;
        row = math.max(row, ch);
        w = math.max(w, x);
      }
      width = w.ceil();
      height = (y + row).ceil();
      if (height <= maxW) break;
    }
    if (width > atlasMaxTexture || height > atlasMaxTexture) failed = true;
  }

  /// Exécute des étapes jusqu'à épuisement du budget ; lance la rastérisation à la fin.
  void step(int budgetMicros) {
    if (failed || cancelled || recorded) return;
    final t0 = PerfStats.now();
    while (!recorded && PerfStats.now() - t0 < budgetMicros) {
      _jobs[_next++]();
    }
    if (recorded) _rasterize();
  }

  /// Termine tout de suite l'enregistrement (tests).
  void finishRecording() => step(1 << 40);

  void _rasterize() {
    final pic = _rec.endRecording();
    _rig = null;
    pic.toImage(width, height).then((img) {
      pic.dispose();
      if (cancelled) {
        img.dispose();
        return;
      }
      result = WarriorAtlasData._(tier, frames, ppu, outlinePx, cells, orb, img);
    }, onError: (Object _) {
      pic.dispose();
      failed = true;
    });
  }

  void _begin(int cell) {
    _c.save();
    final l = cells[cell * 6], t = cells[cell * 6 + 1];
    _c.clipRect(ui.Rect.fromLTRB(l, t, cells[cell * 6 + 2], cells[cell * 6 + 3]));
    _c.translate(l + cells[cell * 6 + 4], t + cells[cell * 6 + 5]);
    _c.scale(ppu);
  }

  void _drawStatic() {
    // Ombre douce pré-floutée (une seule fois, à la résolution du palier).
    _begin(18 * frames + 10);
    _c.drawOval(
        ui.Rect.fromCenter(center: const ui.Offset(0, 0.1 * _r), width: 3.4 * _r * 0.75, height: 1.6 * _r * 0.625),
        ui.Paint()
          ..color = const ui.Color(0xFF000000)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 0.26));
    _c.restore();
    // Socles des trois joueurs et de la pierre.
    final fill = ui.Paint();
    final line = ui.Paint()..style = ui.PaintingStyle.stroke;
    for (var p = 0; p < 4; p++) {
      final stone = p == 3;
      final pal = stone ? WarriorPalette.stone : WarriorPalette.of(p);
      _begin(18 * frames + 6 + p);
      fill.color = stone ? const ui.Color(0xFF3A3C44) : pal.dark;
      _c.drawOval(ui.Rect.fromCenter(center: const ui.Offset(0, 0.1 * _r), width: 2.1 * _r, height: 0.8 * _r), fill);
      fill.color = stone ? const ui.Color(0xFF5A5C66) : ui.Color.lerp(pal.dark, pal.outfit, 0.55)!;
      _c.drawOval(ui.Rect.fromCenter(center: ui.Offset.zero, width: 2.1 * _r, height: 0.78 * _r), fill);
      line
        ..strokeWidth = 0.09 * _r
        ..color = stone ? const ui.Color(0xFF8C8F99) : pal.light;
      _c.drawOval(ui.Rect.fromCenter(center: ui.Offset.zero, width: 1.9 * _r, height: 0.68 * _r), line);
      _c.restore();
    }
  }

  void _startType(PieceType t) {
    _rig = WarriorRig(t)..blink = false;
  }

  void _advance(double seconds) {
    final rig = _rig!;
    final n = math.max(1, (seconds * 60).ceil());
    for (var i = 0; i < n; i++) {
      rig.update(seconds / n);
    }
  }

  void _frame(PieceType t, int k, double period) {
    if (k > 0) _advance(period / frames);
    final rig = _rig!;
    for (var o = 0; o < 3; o++) {
      _begin((t.index * 3 + o) * frames + k);
      rig.render(_c, WarriorPalette.of(o), pxPerUnit: outlinePx, lod: lod);
      _c.restore();
    }
    if (t == PieceType.bishop) {
      final p = rig.bonepoint(B.prop, 0, -2.02);
      orb[k * 2] = p.dx;
      orb[k * 2 + 1] = p.dy;
    }
  }

  void _petrified(PieceType t) {
    final rig = WarriorRig(t)..blink = false;
    rig.play(AnimState.petrified, blend: 0.25);
    _rig = rig;
    _advance(0.9);
    rig.physics = false;
    _advance(0.2);
    _begin(18 * frames + t.index);
    rig.render(_c, WarriorPalette.stone, pxPerUnit: outlinePx, lod: lod);
    _c.restore();
  }
}

/// Durée de la boucle IDLE d'un guerrier.
double idlePeriod(PieceType t) => RigDef.of(t).clips[AnimState.idle]!.duration;

/// Gestion des atlas : un atlas prêt (affiché) et au plus une construction en cours. Quand le
/// zoom change de palier, le nouvel atlas est construit en arrière-plan ; l'ancien reste
/// utilisé (mis à l'échelle) jusqu'à ce qu'il soit prêt.
class WarriorAtlas {
  WarriorAtlasData? ready;
  _AtlasBuild? _build;

  /// Nombre de constructions lancées (tests, overlay).
  int builds = 0;
  int _failedTier = -1;

  /// Palier visé (après hystérésis) ou en cours de construction.
  int? get buildingTier => _build?.tier;
  bool get building => _build != null;

  /// Budget CPU par image consacré à la construction (µs).
  static const int budgetSettled = 4000;
  static const int budgetMoving = 1000;

  void update({required double needPpu, required double outlinePx, required bool moving}) {
    final want = atlasTierFor(needPpu);
    final b = _build;
    if (b != null) {
      if (b.result != null) {
        ready?.dispose();
        ready = b.result;
        _build = null;
      } else if (b.failed) {
        _failedTier = b.tier;
        _build = null;
      } else if (!b.recorded) {
        if (b.tier != want && !moving && ready != null) {
          b.cancelled = true;
          _build = null;
        } else {
          b.step(moving ? budgetMoving : budgetSettled);
        }
      }
      return;
    }
    final r = ready;
    if (r != null && moving) return; // on ne change de palier qu'à l'arrêt
    if (want == _failedTier) return;
    if (r == null || r.tier != want || (r.outlinePx - outlinePx).abs() > outlinePx * 0.15) {
      _build = _AtlasBuild(want, outlinePx);
      builds++;
    }
  }

  /// Termine l'enregistrement de la construction en cours (tests : la rastérisation reste
  /// asynchrone).
  void finishRecording() => _build?.finishRecording();

  void dispose() {
    _build?.cancelled = true;
    _build = null;
    ready?.dispose();
    ready = null;
  }
}

/// Ce que le jeu fournit aux guerriers pour le rendu par lot.
abstract class WarriorBatchHost {
  /// Atlas utilisable (null : rendu vectoriel pour tous).
  WarriorAtlasData? get warriorAtlas;
}

/// Couche qui dessine en lot (drawAtlas) tous les guerriers au repos visibles : auras (un
/// appel pour ombres + socles, un appel additif pour les auras, corps triés en profondeur (un
/// appel par série de même orientation), lueurs tenues (un appel additif). Les guerriers animés se dessinent seuls,
/// au-dessus.
class WarriorBatchLayer extends Component {
  WarriorBatchLayer(this.host) : super(priority: -1);

  final WarriorBatchHost host;

  /// Guerriers candidats (renseignés par le jeu à chaque image).
  final List<WarriorPiece> pieces = [];
  final List<WarriorPiece> _draw = [];
  final SpriteBatch _aura = SpriteBatch(48 * 16);
  final SpriteBatch _body = SpriteBatch(48 * 2);
  final SpriteBatch _held = SpriteBatch(48 * 2);

  /// Guerriers dessinés à la dernière image / appels drawAtlas (tests, overlay).
  int drawn = 0;
  int calls = 0;

  static int _byDepth(WarriorPiece a, WarriorPiece b) => a.position.y.compareTo(b.position.y);

  @override
  void render(ui.Canvas canvas) {
    final t0 = PerfStats.now();
    drawn = 0;
    calls = 0;
    final atlas = host.warriorAtlas;
    if (atlas != null) {
      _draw.clear();
      for (final p in pieces) {
        if (p.batched && !p.culled && p.isMounted) _draw.add(p);
      }
      if (_draw.isNotEmpty) _render(canvas, atlas);
    }
    PerfStats.add(PerfSub.pieces, t0);
  }

  void _render(ui.Canvas canvas, WarriorAtlasData atlas) {
    _draw.sort(_byDepth);
    drawn = _draw.length;
    // 1. Ombres et socles (même atlas, un appel), 2. auras additives, 3. corps triés en
    // profondeur (un appel par série d'orientation), 4. lueurs tenues.
    for (final p in _draw) {
      p.addBatchedGround(atlas, _body);
    }
    _flushBody(canvas, atlas, 1);
    for (final p in _draw) {
      p.addBatchedAura(_aura);
    }
    if (_aura.length > 0) calls++;
    _aura.flush(canvas);
    // Corps : drawAtlas ne sait pas retourner un sprite ; les guerriers tournés vers la
    // gauche sont dessinés dans un canevas en miroir. Un appel par orientation, triés en
    // profondeur ; les rares guerriers « droite » qui chevauchent par devant un guerrier
    // « gauche » sont repris dans un troisième appel pour garder l'ordre visuel.
    for (final a in _draw) {
      a.batchConflict = false;
      if (a.facing < 0) continue;
      for (final b in _draw) {
        if (b.facing >= 0 || b.position.y >= a.position.y) continue;
        final rr = a.radius + b.radius;
        if ((a.position.x - b.position.x).abs() < rr * 1.6 && a.position.y - b.position.y < rr * 2.6) {
          a.batchConflict = true;
          break;
        }
      }
    }
    for (final p in _draw) {
      if (p.facing >= 0 && !p.batchConflict) p.addBatchedBody(atlas, _body, 1);
    }
    _flushBody(canvas, atlas, 1);
    for (final p in _draw) {
      if (p.facing < 0) p.addBatchedBody(atlas, _body, -1);
    }
    _flushBody(canvas, atlas, -1);
    for (final p in _draw) {
      if (p.batchConflict) p.addBatchedBody(atlas, _body, 1);
      p.addBatchedHeld(atlas, _held);
    }
    _flushBody(canvas, atlas, 1);
    if (_held.length > 0) calls++;
    _held.flush(canvas);
  }

  void _flushBody(ui.Canvas canvas, WarriorAtlasData atlas, double sign) {
    if (_body.length == 0) return;
    calls++;
    if (sign < 0) {
      canvas.save();
      canvas.scale(-1, 1);
      _body.flush(canvas, additive: false, image: atlas.image);
      canvas.restore();
    } else {
      _body.flush(canvas, additive: false, image: atlas.image);
    }
  }
}
