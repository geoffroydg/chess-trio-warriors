import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart' show Color, Offset, Path, Canvas, Paint, PaintingStyle, StrokeJoin;

import '../models/geometry.dart';
import '../models/protocol.dart';
import 'piece_component.dart';

/// Jeu Flame : plateau hexagonal en vue 2D inclinée, pièces, sélection et animations.
class ChessGame extends FlameGame {
  ChessGame({
    required this.geometry,
    required this.viewer,
    PieceFactory? pieceFactory,
    this.onMove,
    this.onSelect,
  })  : projection = BoardProjection(viewer: viewer),
        pieceFactory = pieceFactory ??
            ((t, o, c) => PlaceholderPieceComponent(type: t, owner: o, cellId: c));

  final BoardGeometry geometry;
  final int viewer;
  final BoardProjection projection;
  final PieceFactory pieceFactory;

  /// Appelé quand le joueur choisit un coup (départ, arrivée).
  void Function(String from, String to)? onMove;
  void Function(String cellId)? onSelect;

  late final BoardComponent board = BoardComponent(this)..priority = -1000;
  final Map<String, PieceComponent> _pieces = {};

  GameMsg? _msg;
  int _me = 0;
  int? _lastPly;
  String? selected;
  Set<String> targets = {};
  Set<String> checkedKings = {};
  String? lastFrom;
  String? lastTo;

  // Mise en page courante.
  double scale = 1;
  Offset origin = Offset.zero;
  bool _laidOut = false;
  List<List<Offset>> screenPolygons = const [];
  List<Offset> screenOutline = const [];

  @override
  ui.Color backgroundColor() => const ui.Color(0x00000000);

  @override
  Future<void> onLoad() async {
    await add(board);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _relayout(size);
  }

  void _relayout(Vector2 size) {
    if (size.x <= 0 || size.y <= 0) return;
    // Emprise de l'hexagone projeté.
    final pts = [for (final p in geometry.outline) projection.projectOffset(p)];
    var minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    const marginTop = 0.10; // place pour les pièces qui dépassent
    const marginSide = 0.04;
    final w = (maxX - minX) + 2 * marginSide;
    final h = (maxY - minY) + marginTop + 0.06;
    scale = math.min(size.x / w, size.y / h);
    final cx = (minX + maxX) / 2;
    final top = minY - marginTop;
    origin = Offset(size.x / 2 - cx * scale, (size.y - h * scale) / 2 - top * scale);
    screenOutline = [for (final p in pts) _toScreen(p)];
    screenPolygons = [
      for (final c in geometry.cells)
        [for (final p in c.polygon) _toScreen(projection.projectOffset(p))],
    ];
    _laidOut = true;
    board.size = size;
    for (final e in _pieces.entries) {
      _place(e.value, e.key);
    }
  }

  Offset _toScreen(Offset p) => Offset(origin.dx + p.dx * scale, origin.dy + p.dy * scale);

  Vector2 cellPosition(String id) {
    final c = geometry.byId(id);
    final p = _toScreen(projection.project(c.x, c.y));
    return Vector2(p.dx, p.dy);
  }

  /// Rayon d'un pion à l'endroit de la case.
  double pieceRadius(String id) {
    final c = geometry.byId(id);
    return scale * 0.052 * projection.scaleAt(c.x, c.y);
  }

  void _place(PieceComponent p, String id) =>
      p.placeAt(cellPosition(id) + Vector2(0, -pieceRadius(id) * 0.1), pieceRadius(id));

  // --- État de jeu ---

  bool get myTurn => _msg != null && !_msg!.over && _msg!.turn == _me;

  void applyGame(GameMsg msg, int me) {
    final prevPly = _lastPly;
    _msg = msg;
    _me = me;
    _lastPly = msg.state.ply;
    selected = null;
    targets = {};
    final ev = msg.lastEvent;
    lastFrom = ev?.from;
    lastTo = ev?.to;
    checkedKings = {};
    if (ev != null) {
      for (final ch in ev.checks) {
        for (var i = 0; i < msg.state.board.length; i++) {
          final p = msg.state.board[i];
          if (p != null && p.type == PieceType.king && p.owner == ch.player) {
            checkedKings.add(geometry.cells[i].id);
          }
        }
      }
    }
    if (!_laidOut) {
      _pendingSync = true;
      return;
    }
    _sync(animate: prevPly != null && prevPly != msg.state.ply && ev != null && ev.isMove);
  }

  bool _pendingSync = false;

  @override
  void onMount() {
    super.onMount();
    if (_pendingSync && _laidOut) {
      _pendingSync = false;
      _sync(animate: false);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_pendingSync && _laidOut && isMounted) {
      _pendingSync = false;
      _sync(animate: false);
    }
  }

  void _sync({required bool animate}) {
    final msg = _msg!;
    final ev = msg.lastEvent;
    if (animate && ev != null) {
      final cap = ev.captured;
      if (cap != null) {
        final victim = _pieces.remove(cap.at);
        if (victim != null) {
          victim.onCaptured();
          add(FlashComponent(
              center: victim.position.clone(),
              maxRadius: victim.radius * 1.4,
              color: playerAccents[cap.owner]));
          victim.removeFromParent();
        }
      }
      _animateMove(ev.from!, ev.to!);
      if (ev.castleRookFrom != null && ev.castleRookTo != null) {
        _animateMove(ev.castleRookFrom!, ev.castleRookTo!);
      }
    }
    // Réconciliation avec le plateau reçu.
    for (var i = 0; i < msg.state.board.length; i++) {
      final id = geometry.cells[i].id;
      final want = msg.state.board[i];
      final have = _pieces[id];
      if (want == null) {
        if (have != null) {
          have.removeFromParent();
          _pieces.remove(id);
        }
        continue;
      }
      var piece = have;
      if (piece != null && piece.owner != want.owner) {
        piece.removeFromParent();
        _pieces.remove(id);
        piece = null;
      }
      if (piece == null) {
        piece = pieceFactory(want.type, want.owner, id);
        _pieces[id] = piece;
        _place(piece, id);
        add(piece);
      } else {
        piece.type = want.type; // promotion
      }
      piece.frozen = !msg.state.active[want.owner];
      piece.setSelected(false);
    }
  }

  void _animateMove(String from, String to) {
    final p = _pieces.remove(from);
    if (p == null) return;
    _pieces.remove(to)?.removeFromParent();
    p.cellId = to;
    _pieces[to] = p;
    p.moveTo(cellPosition(to) + Vector2(0, -pieceRadius(to) * 0.1), pieceRadius(to));
  }

  // --- Interaction ---

  /// Case la plus proche du point (en pixels), ou null.
  String? cellAt(Offset pos) {
    String? best;
    var bestD = double.infinity;
    for (var i = 0; i < screenPolygons.length; i++) {
      final poly = screenPolygons[i];
      final inside = _contains(poly, pos);
      var cx = 0.0, cy = 0.0;
      for (final p in poly) {
        cx += p.dx / 4;
        cy += p.dy / 4;
      }
      final d = (Offset(cx, cy) - pos).distance;
      final tol = scale * 0.07;
      if ((inside || d < tol) && (d - (inside ? tol : 0)) < bestD) {
        bestD = d - (inside ? tol : 0);
        best = geometry.cells[i].id;
      }
    }
    return best;
  }

  static bool _contains(List<Offset> poly, Offset p) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  void handleTap(Offset pos) {
    final id = cellAt(pos);
    final msg = _msg;
    if (id == null || msg == null || !myTurn) return;
    if (selected != null && targets.contains(id)) {
      final from = selected!;
      _clearSelection();
      onMove?.call(from, id);
      return;
    }
    if (selected == id) {
      _clearSelection();
      return;
    }
    final dests = {for (final m in msg.legalMoves) if (m.from == id) m.to};
    _clearSelection();
    if (dests.isNotEmpty) {
      selected = id;
      targets = dests;
      _pieces[id]?.setSelected(true);
      onSelect?.call(id);
    }
  }

  void _clearSelection() {
    if (selected != null) _pieces[selected!]?.setSelected(false);
    selected = null;
    targets = {};
  }

  /// Pièce adverse présente sur une case (pour dessiner les prises).
  bool hasPiece(String id) => _pieces.containsKey(id);
}

/// Dessin du plateau : socle, cases, surbrillances.
class BoardComponent extends PositionComponent with TapCallbacks {
  BoardComponent(this.game) : super(position: Vector2.zero());
  final ChessGame game;
  double _time = 0;

  static const _sectorTint = [Color(0xFF5B8CFF), Color(0xFFFF6B3D), Color(0xFF8B7CFF)];
  static const _light = Color(0xFF3A4668);
  static const _dark = Color(0xFF232B47);

  @override
  void update(double dt) {
    _time += dt;
  }

  @override
  void onTapDown(TapDownEvent event) {
    final p = event.localPosition;
    game.handleTap(Offset(p.x, p.y));
  }

  Path _path(List<Offset> pts) => Path()..addPolygon(pts, true);

  @override
  void render(Canvas canvas) {
    if (game.screenPolygons.isEmpty) return;
    final outline = _path(game.screenOutline);
    // Épaisseur du plateau + halo.
    final depth = game.scale * 0.035;
    canvas.drawPath(
      outline.shift(Offset(0, depth * 1.6)),
      Paint()
        ..color = const Color(0x55FF8A3D)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14),
    );
    canvas.drawPath(outline.shift(Offset(0, depth)), Paint()..color = const Color(0xFF0B1022));
    canvas.drawPath(outline, Paint()..color = const Color(0xFF151B33));

    final msg = game._msg;
    final active = msg?.state.active ?? const [true, true, true];

    for (var i = 0; i < game.screenPolygons.length; i++) {
      final c = game.geometry.cells[i];
      final base = c.light ? _light : _dark;
      var color = Color.lerp(base, _sectorTint[c.sector], 0.16)!;
      if (!active[c.sector]) color = Color.lerp(color, const Color(0xFF3A3A3A), 0.4)!;
      final path = _path(game.screenPolygons[i]);
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 0.8
          ..color = const Color(0xFF0E1328),
      );
    }

    // Dernier coup.
    for (final id in [game.lastFrom, game.lastTo]) {
      if (id == null) continue;
      canvas.drawPath(_path(game.screenPolygons[game.geometry.byId(id).index]),
          Paint()..color = const Color(0x55FFB23D));
    }
    // Rois en échec (pulsation).
    final pulse = 0.5 + 0.5 * math.sin(_time * 6);
    for (final id in game.checkedKings) {
      canvas.drawPath(
        _path(game.screenPolygons[game.geometry.byId(id).index]),
        Paint()..color = Color.fromRGBO(255, 40, 40, 0.25 + 0.3 * pulse),
      );
    }
    // Sélection et coups légaux.
    final sel = game.selected;
    if (sel != null) {
      canvas.drawPath(
        _path(game.screenPolygons[game.geometry.byId(sel).index]),
        Paint()..color = const Color(0x6635E0FF),
      );
      canvas.drawPath(
        _path(game.screenPolygons[game.geometry.byId(sel).index]),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFF35E0FF),
      );
    }
    for (final id in game.targets) {
      final cell = game.geometry.byId(id);
      final path = _path(game.screenPolygons[cell.index]);
      final capture = game.hasPiece(id);
      final col = capture ? const Color(0xFFFF4D4D) : const Color(0xFFFFA63D);
      canvas.drawPath(path, Paint()..color = col.withAlpha(capture ? 70 : 45));
      final pos = game.cellPosition(id);
      final r = game.pieceRadius(id);
      if (capture) {
        canvas.drawCircle(
          Offset(pos.x, pos.y),
          r * 1.15,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = col,
        );
      } else {
        canvas.drawCircle(Offset(pos.x, pos.y), r * (0.35 + 0.06 * pulse), Paint()..color = col);
      }
    }
  }
}
