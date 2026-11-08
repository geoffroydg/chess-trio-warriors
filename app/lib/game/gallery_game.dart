import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../models/protocol.dart';
import 'arena_backdrop.dart';
import 'attacks.dart';
import 'fx.dart';
import 'warrior_piece.dart';

const galleryOrder = [
  PieceType.king,
  PieceType.queen,
  PieceType.bishop,
  PieceType.knight,
  PieceType.rook,
  PieceType.pawn,
];

String pieceNameFr(PieceType t) => switch (t) {
      PieceType.king => 'Roi',
      PieceType.queen => 'Dame',
      PieceType.bishop => 'Fou',
      PieceType.knight => 'Cavalier',
      PieceType.rook => 'Tour',
      PieceType.pawn => 'Pion',
    };

/// Scène de démonstration : les 6 guerriers des 3 couleurs et une arène pour les attaques.
class GalleryGame extends FlameGame with FxHost {
  final List<WarriorPiece> grid = [];
  WarriorPiece? stageAttacker;
  WarriorPiece? stageVictim;
  CaptureSequence? _seq;
  bool _ready = false;
  bool selectedAll = false;
  bool frozenAll = false;
  bool checkAll = false;

  /// Dernières attaques lancées (pour les tests / l'audio de démo).
  void Function(PieceType attacker, PieceType victim)? onCapture;

  @override
  ui.Color backgroundColor() => const ui.Color(0xFF0B1022);

  @override
  Future<void> onLoad() async {
    await add(ArenaBackdrop());
    for (var o = 0; o < 3; o++) {
      for (final t in galleryOrder) {
        final p = WarriorPiece(type: t, owner: o, cellId: '0a1');
        grid.add(p);
        await add(p);
      }
    }
    await initFx();
    _ready = true;
    _layout(size);
    resetStage();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (_ready) {
      _layout(size);
      resetStage();
    }
  }

  double get cell => size.x / 6;
  double get unit => math.min(cell * 0.4, size.y / 14);

  void _layout(Vector2 s) {
    if (s.x <= 0 || s.y <= 0) return;
    final rowH = math.min(s.y * 0.2, cell * 1.5);
    for (var i = 0; i < grid.length; i++) {
      final o = i ~/ 6, c = i % 6;
      grid[i].placeAt(Vector2(cell * (c + 0.5), rowH * (o + 0.75) + unit), unit);
    }
  }

  Vector2 get _attackerSpot => Vector2(size.x * 0.25, size.y * 0.84);
  Vector2 get _victimSpot => Vector2(size.x * 0.72, size.y * 0.84);

  /// Remet en place l'attaquant et la victime de la scène.
  void resetStage([PieceType attacker = PieceType.queen]) {
    finishAttack();
    stageAttacker?.removeFromParent();
    stageVictim?.removeFromParent();
    final r = unit * 1.15;
    stageAttacker = WarriorPiece(type: attacker, owner: 0, cellId: 'a')
      ..placeAt(_attackerSpot, r);
    stageVictim = WarriorPiece(type: PieceType.knight, owner: 2, cellId: 'b')
      ..placeAt(_victimSpot, r);
    add(stageAttacker!);
    add(stageVictim!);
  }

  void finishAttack() {
    _seq?.finish();
    _seq = null;
  }

  /// Joue l'attaque spéciale de [type] sur la victime de la scène.
  void playAttack(PieceType type, {int owner = 0}) {
    if (!_ready) return;
    finishAttack();
    resetStage(type);
    final a = stageAttacker!;
    final v = stageVictim!;
    final seq = CaptureSequence(
      host: this,
      attacker: a,
      victim: v,
      destination: _victimSpot.clone(),
      destRadius: a.radius,
      onImpact: () => onCapture?.call(type, v.type),
      onFinished: () {
        _seq = null;
        add(TimerComponent(period: 0.8, removeOnFinish: true, onTick: () => resetStage(type)));
      },
    );
    _seq = seq;
    add(seq);
  }

  void showCheck() {
    final k = grid.firstWhere((p) => p.type == PieceType.king && p.owner == 0);
    k.inCheck = true;
    showBanner('ÉCHEC !', const ui.Color(0xFFFFB02E), seconds: 1.2);
    add(TimerComponent(period: 2.0, removeOnFinish: true, onTick: () => k.inCheck = checkAll));
  }

  void showMate() {
    final k = stageVictim ?? grid.first;
    showBanner('MAT !', const ui.Color(0xFFFF3B5C), seconds: 2.0, sizeFactor: 0.22);
    final at = chestOf(k);
    pool.burst(at.x, at.y, 90, k.radius * 22, k.radius * 0.4, const ui.Color(0xFFFF5A7A), lifeS: 1.2);
    pool.burst(at.x, at.y, 60, k.radius * 16, k.radius * 0.3, const ui.Color(0xFFFFFFFF), lifeS: 0.8);
    for (var i = 0; i < 3; i++) {
      add(ShockRing(
          center: at + Vector2(0, k.radius * 0.8),
          maxRadius: k.radius * (4 + i * 1.6),
          color: const ui.Color(0xFFFF5A7A),
          seconds: 0.7,
          delay: i * 0.12));
    }
    hitstop(0.12);
    shake(k.radius, 0.7);
  }

  void toggleSelected() {
    selectedAll = !selectedAll;
    for (final p in grid) {
      p.setSelected(selectedAll);
    }
  }

  void toggleFrozen() {
    frozenAll = !frozenAll;
    for (final p in grid) {
      p.frozen = frozenAll;
    }
  }

  void toggleCheck() {
    checkAll = !checkAll;
    for (final p in grid) {
      if (p.type == PieceType.king) p.inCheck = checkAll;
    }
  }
}
