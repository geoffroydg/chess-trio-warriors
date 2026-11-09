import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chesstrio/game/fx.dart';
import 'package:chesstrio/game/rig/anim.dart';
import 'package:chesstrio/game/rig/skeleton.dart';
import 'package:chesstrio/game/rig/warrior_defs.dart';
import 'package:chesstrio/game/rig/warrior_rig.dart';
import 'package:chesstrio/game/warrior_art.dart';
import 'package:chesstrio/game/warrior_piece.dart';
import 'package:chesstrio/models/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

const order = [PieceType.king, PieceType.queen, PieceType.bishop, PieceType.knight, PieceType.rook, PieceType.pawn];

void main() {
  group('easing', () {
    test('bornes 0 et 1 pour toutes les courbes', () {
      for (final e in Ease.values) {
        expect(ease(e, 0), closeTo(0, 1e-9), reason: e.name);
        expect(ease(e, 1), closeTo(1, 1e-9), reason: e.name);
        expect(ease(e, -1), closeTo(0, 1e-9), reason: e.name);
        expect(ease(e, 2), closeTo(1, 1e-9), reason: e.name);
        for (var i = 0; i <= 50; i++) {
          expect(ease(e, i / 50).isFinite, isTrue);
        }
      }
    });
    test('formes : cubic, back (dépassement), elastic (oscillation)', () {
      expect(ease(Ease.inCubic, 0.5), closeTo(0.125, 1e-9));
      expect(ease(Ease.outCubic, 0.5), closeTo(0.875, 1e-9));
      expect(ease(Ease.inOutCubic, 0.5), closeTo(0.5, 1e-9));
      expect(ease(Ease.inBack, 0.2), lessThan(0));
      final ob = [for (var i = 1; i < 20; i++) ease(Ease.outBack, i / 20)];
      expect(ob.reduce(math.max), greaterThan(1.05));
      final el = [for (var i = 1; i < 40; i++) ease(Ease.outElastic, i / 40)];
      expect(el.reduce(math.max), greaterThan(1.0));
      expect(ease(Ease.step, 0.99), 0);
    });
  });

  group('pistes et clips', () {
    test('interpolation entre keyframes', () {
      final t = Track(0, Ch.rot, [0, 0, 1, 2, 2, 0], ease: Ease.linear);
      expect(t.sample(-1), 0);
      expect(t.sample(0.5), closeTo(1, 1e-6));
      expect(t.sample(1), closeTo(2, 1e-6));
      expect(t.sample(1.5), closeTo(1, 1e-6));
      expect(t.sample(5), 0);
      final e = Track(0, Ch.rot, [0, 0, 1, 1], ease: Ease.inQuad);
      expect(e.sample(0.5), closeTo(0.25, 1e-6));
    });
    test('clip bouclé, pose par défaut et fondu', () {
      final c = Clip(1, [Track(2, Ch.sy, [0, 1, 0.5, 2, 1, 1], ease: Ease.linear)], loop: true);
      final p = Pose(3);
      c.sampleInto(p, 1.25);
      expect(p.get(2, Ch.sy), closeTo(1.5, 1e-6));
      expect(p.get(0, Ch.sx), 1);
      expect(p.get(1, Ch.rot), 0);
      final a = Pose(3), b = Pose(3)..set(1, Ch.rot, 2);
      p.blend(a, b, 0.25);
      expect(p.get(1, Ch.rot), closeTo(0.5, 1e-6));
    });
  });

  group('machine à états', () {
    test('JUMP enchaîne sur IDLE, durée imposée, fondu progressif', () {
      final sm = AnimationStateMachine(RigDef.of(PieceType.knight).clips, B.count);
      sm.update(0.5);
      sm.play(AnimState.jump, duration: 0.5, blend: 0.15);
      expect(sm.speed, closeTo(2, 1e-6));
      expect(sm.blending, isTrue);
      sm.update(0.05);
      expect(sm.blendWeight, closeTo(1 / 3, 1e-3));
      sm.update(0.15);
      expect(sm.blending, isFalse);
      for (var i = 0; i < 20; i++) {
        sm.update(1 / 60);
      }
      expect(sm.state, AnimState.idle);
      expect(sm.blending, isTrue); // fondu de sortie vers le repos
    });
    test('KO et PETRIFIED restent sur leur dernière pose ; VICTORY boucle', () {
      for (final s in [AnimState.ko, AnimState.petrified, AnimState.victory]) {
        final sm = AnimationStateMachine(RigDef.of(PieceType.pawn).clips, B.count);
        sm.play(s, blend: 0.12);
        for (var i = 0; i < 300; i++) {
          sm.update(1 / 60);
        }
        expect(sm.state, s);
      }
      final sm = AnimationStateMachine(RigDef.of(PieceType.pawn).clips, B.count)..play(AnimState.attack);
      for (var i = 0; i < 120; i++) {
        sm.update(1 / 60);
      }
      expect(sm.state, AnimState.idle);
    });
    test('restart: false ne relance pas l\'état courant', () {
      final sm = AnimationStateMachine(RigDef.of(PieceType.queen).clips, B.count)..play(AnimState.move);
      sm.update(0.2);
      sm.play(AnimState.move, restart: false);
      expect(sm.time, greaterThan(0));
    });
  });

  test('chaque guerrier dans chaque état : aucune exception, aucun NaN', () {
    final rng = math.Random(1);
    for (final t in order) {
      for (final s in AnimState.values) {
        final rig = WarriorRig(t, phase: rng.nextDouble() * 3);
        rig.play(s, duration: s == AnimState.jump ? 0.5 : null);
        for (var i = 0; i < 200; i++) {
          // dt irréguliers + secousses de déplacement (inertie des chaînes).
          rig.update(rng.nextDouble() * 0.05, shiftX: (rng.nextDouble() - 0.5) * 0.4, shiftY: (rng.nextDouble() - 0.5) * 0.4);
          expect(rig.isFinite, isTrue, reason: '${t.name} ${s.name} @$i');
        }
        rig.update(0.5); // grande pause (image perdue)
        expect(rig.isFinite, isTrue);
        for (final pal in [WarriorPalette.white, WarriorPalette.stone]) {
          for (var lod = 0; lod <= 2; lod++) {
            final rec = ui.PictureRecorder();
            rig.render(ui.Canvas(rec), pal, pxPerUnit: 10.0 + lod * 15, lod: lod, flash: lod == 1 ? 0.5 : 0);
            rec.endRecording().dispose();
          }
        }
      }
    }
  });

  test('os connectés : chaque enfant reste attaché à son parent', () {
    for (final t in order) {
      final rig = WarriorRig(t);
      for (final s in AnimState.values) {
        rig.play(s, blend: 0);
        for (var i = 0; i < 40; i++) {
          rig.update(1 / 30);
          final sk = rig.skeleton;
          for (var b = 1; b < sk.length; b++) {
            final p = sk.parent[b];
            // Le pivot de l'enfant = point de repos (restX/restY) dans le repère du parent.
            final px = sk.worldX(p, sk.restX[b], sk.restY[b]);
            final py = sk.worldY(p, sk.restX[b], sk.restY[b]);
            final dx = sk.worldX(b, 0, 0) - px, dy = sk.worldY(b, 0, 0) - py;
            final off = math.sqrt(dx * dx + dy * dy);
            // Seuls root (translation) et eyes peuvent être décalés par un clip.
            expect(off, lessThan(0.6), reason: '${t.name} ${s.name} os $b');
          }
        }
      }
    }
  });

  test('captures PNG de la planche (RIG_CAPTURES=dossier)', () async {
    final dir = Platform.environment['RIG_CAPTURES'];
    if (dir == null) return;
    Directory(dir).createSync(recursive: true);
    await FxAtlas.load();
    final states = AnimState.values;
    final at = {
      AnimState.idle: 0.3, AnimState.move: 0.3, AnimState.jump: 0.5, AnimState.attack: 0.5, AnimState.hit: 0.2,
      AnimState.ko: 1.0, AnimState.victory: 0.32, AnimState.petrified: 1.0,
    };
    Future<void> sheet(String name, List<AnimState> rows, double scale, {Map<AnimState, double>? when}) async {
      final cw = scale * 3.6, ch = scale * 4.6;
      final w = (cw * 6).round(), h = (ch * rows.length).round();
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint()
            ..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(0, h.toDouble()),
                const [ui.Color(0xFF1A1440), ui.Color(0xFF3A1F5A), ui.Color(0xFF6A2F5B)], const [0, 0.6, 1]));
      final glow = SpriteBatch(4);
      for (var si = 0; si < rows.length; si++) {
        for (var ti = 0; ti < order.length; ti++) {
          final st = rows[si];
          final rig = WarriorRig(order[ti]);
          rig.play(st, blend: 0, duration: st == AnimState.jump ? 1.0 : null);
          final d = rig.sm.clip.duration;
          final k = (when ?? at)[st]!;
          for (var tt = 0.0; tt < d * k; tt += 1 / 60) {
            rig.update(1 / 60);
          }
          final cx = ti * cw + cw / 2, fy = si * ch + ch - scale * 0.55;
          final pal = st == AnimState.petrified ? WarriorPalette.stone : WarriorPalette.of(ti % 3);
          c.drawOval(ui.Rect.fromCenter(center: ui.Offset(cx, fy + 2), width: scale * 2.2, height: scale * 0.55),
              ui.Paint()
                ..color = const ui.Color(0x88000000)
                ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, scale * 0.12));
          if (st != AnimState.petrified) {
            glow.addColor(Fx.glow, cx, fy - scale * 1.3, scale * 4, pal.aura, alpha: 0.35);
            glow.flush(c);
          }
          c.save();
          c.translate(cx, fy);
          c.scale(scale * (ti >= 3 ? -1 : 1), scale);
          rig.render(c, pal, pxPerUnit: scale, lod: WarriorPiece.lodFor(scale / 0.72));
          c.restore();
        }
      }
      final img = await rec.endRecording().toImage(w, h);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    }

    await sheet('rig_planche', states, 52);
    await sheet('rig_repos_attaque', [AnimState.idle, AnimState.attack], 110);
    await sheet('rig_saut', [AnimState.jump, AnimState.jump, AnimState.jump], 60,
        when: {AnimState.jump: 0.15});
    await sheet('rig_lod', [AnimState.idle], 14);
  });
}
