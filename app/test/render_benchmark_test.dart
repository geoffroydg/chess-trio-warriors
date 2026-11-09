import 'dart:io';
import 'dart:ui' as ui;

import 'package:chesstrio/game/chess_game.dart';
import 'package:chesstrio/game/perf.dart';
import 'package:chesstrio/game/piece_component.dart';
import 'package:chesstrio/models/geometry.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'round_board_test.dart' show initialMsg;

/// Banc d'essai headless : 300 images de pan/zoom avec les 48 guerriers, avant (optimisations
/// coupées) / après. Temps CPU = mise à jour + enregistrement du dessin ; « raster » =
/// rastérisation logicielle de l'image enregistrée (indicateur du travail GPU).
class _Stats {
  _Stats(this.label);
  final String label;
  final cpu = <double>[];
  final raster = <double>[];
  final subs = {for (final s in PerfSub.values) s: 0.0};
  int vectorRenders = 0;
  int batched = 0;

  static String _fmt(List<double> l) {
    final s = List.of(l)..sort();
    final mean = s.reduce((a, b) => a + b) / s.length;
    return 'moy ${mean.toStringAsFixed(2)} / p95 ${s[(s.length * 0.95).floor()].toStringAsFixed(2)}'
        ' / max ${s.last.toStringAsFixed(2)} ms';
  }

  double get meanCpu => cpu.reduce((a, b) => a + b) / cpu.length;
  double get meanRaster => raster.reduce((a, b) => a + b) / raster.length;

  @override
  String toString() {
    final n = cpu.length;
    final per = PerfSub.values.map((s) => '${s.name} ${(subs[s]! / n).toStringAsFixed(2)}').join(', ');
    return '[$label] CPU ${_fmt(cpu)} | raster ${_fmt(raster)}\n'
        '    par sous-système (ms/image) : $per | rendus vectoriels/image '
        '${(vectorRenders / n).toStringAsFixed(1)}, guerriers en lot/image ${(batched / n).toStringAsFixed(1)}';
  }
}

const _dpr = 2.75;

Future<_Stats> _run(WidgetTester tester, BoardGeometry geo, {required bool optimized, bool rasterize = true}) async {
  PerfConfig.setAll(optimized);
  final only = Platform.environment['BENCH_ONLY'];
  if (optimized && only != null) {
    PerfConfig.setAll(false);
    if (only.contains('c')) PerfConfig.culling = true;
    if (only.contains('s')) PerfConfig.spriteCache = true;
    if (only.contains('g')) PerfConfig.gestureLite = true;
    if (only.contains('b')) PerfConfig.asyncBoard = true;
  }
  final game = ChessGame(geometry: geo, viewer: 0);
  await tester.pumpWidget(MaterialApp(home: GameWidget(game: game, key: UniqueKey())));
  await tester.pump();
  game.applyGame(initialMsg(), 0);
  await tester.pump();
  await tester.pump();
  final stats = _Stats(optimized ? 'après' : 'avant');
  final cam = game.boardCamera;
  final w = game.size.x, h = game.size.y;
  await tester.runAsync(() async {
    // Démarrage : atlas des guerriers, fond et plateau mis en cache (asynchrones).
    for (var i = 0; i < 400; i++) {
      game.update(1 / 60);
      final rec = ui.PictureRecorder();
      game.render(Canvas(rec));
      rec.endRecording().dispose();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (!optimized && i > 30) break;
      if (optimized && game.atlas.ready != null && game.board.baseCached && game.backdrop.cached && i > 30) break;
    }
    if (optimized) expect(game.atlas.ready, isNotNull, reason: 'atlas construit au démarrage');
    PerfStats.reset();
    final sw = Stopwatch();
    for (var f = 0; f < 300; f++) {
      cam.gestureActive = f < 240;
      if (f < 60) {
        cam.zoomAt(Offset(w / 2, h / 2), 1 + 2.0 * (f + 1) / 60);
      } else if (f < 180) {
        cam.panBy(Offset(f < 120 ? -6 : 6, f % 40 < 20 ? 4 : -4));
      } else if (f < 240) {
        cam.zoomAt(Offset(w * 0.4, h * 0.5), cam.zoom * 0.985);
      }
      final renders0 = _renders(game);
      sw
        ..reset()
        ..start();
      game.update(1 / 60);
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..scale(_dpr);
      game.render(canvas);
      final pic = rec.endRecording();
      sw.stop();
      stats.cpu.add(sw.elapsedMicroseconds / 1000);
      if (Platform.environment['BENCH_DEBUG'] != null && sw.elapsedMicroseconds > 8000) {
        // ignore: avoid_print
        print('image $f : ${sw.elapsedMicroseconds / 1000} ms ${PerfSub.values.map((s) => PerfStats.lastMs(s).toStringAsFixed(1))}');
      }
      for (final s in PerfSub.values) {
        stats.subs[s] = stats.subs[s]! + PerfStats.lastMs(s);
      }
      stats.vectorRenders += _renders(game) - renders0;
      stats.batched += game.batchLayer.drawn;
      if (rasterize) {
        final s2 = Stopwatch()..start();
        final img = await pic.toImage((w * _dpr).round(), (h * _dpr).round());
        s2.stop();
        stats.raster.add(s2.elapsedMicroseconds / 1000);
        img.dispose();
      } else {
        stats.raster.add(0);
      }
      pic.dispose();
      await Future<void>.delayed(Duration.zero);
    }
  });
  if (Platform.environment['BENCH_DEBUG'] != null) {
    String m(int a, int b) => (stats.raster.sublist(a, b).reduce((x, y) => x + y) / (b - a)).toStringAsFixed(1);
    // ignore: avoid_print
    print('plateau : contenu ${game.board.contentBuilds}, base ${game.board.baseCached}, tuiles ${game.board.tileBuilds}/${game.board.tileCount}');
    // ignore: avoid_print
    print('raster par phase : zoom ${m(0, 60)}, pan ${m(60, 180)}, dézoom ${m(180, 240)}, arrêt ${m(240, 300)}');
  }
  await tester.pumpWidget(const SizedBox());
  return stats;
}

int _renders(ChessGame game) {
  var n = 0;
  for (final c in game.worldLayer.children) {
    if (c is PieceComponent) n += c.renderCount;
  }
  return n;
}

void main() {
  final geo = BoardGeometry.fromJsonString(File('assets/geometry.json').readAsStringSync());
  // Rastérisation logicielle (lente) : BENCH_RASTER=1. Dans flutter_tester, toImage rastérise
  // de façon synchrone sur le fil appelant : les pics « max » au re-rendu en font partie.
  final rasterize = Platform.environment['BENCH_RASTER'] != null;

  tearDown(() => PerfConfig.setAll(true));

  testWidgets('banc d\'essai pan/zoom : 300 images, 48 guerriers, avant/après', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    final before = await _run(tester, geo, optimized: false, rasterize: rasterize);
    final after = await _run(tester, geo, optimized: true, rasterize: rasterize);
    // ignore: avoid_print
    print('$before\n$after');
    expect(after.batched, greaterThan(0), reason: 'les guerriers au repos passent par l\'atlas');
    expect(after.vectorRenders, lessThan(before.vectorRenders));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
