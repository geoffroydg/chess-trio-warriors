
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'chess_game.dart';

/// Plateau interactif : pincer pour zoomer, glisser pour se déplacer (zoomé), tap pour jouer,
/// double tap pour zoomer / revenir à la vue entière, bouton « vue entière ».
class ChessGameView extends StatefulWidget {
  const ChessGameView({super.key, required this.game});
  final ChessGame game;

  /// Mouvement maximal (pixels) d'un tap.
  static const double tapSlop = 8;
  static const Duration doubleTapWindow = Duration(milliseconds: 300);

  @override
  State<ChessGameView> createState() => _ChessGameViewState();
}

class _ChessGameViewState extends State<ChessGameView> {
  final Map<int, Offset> _pointers = {};
  Offset _downPos = Offset.zero;
  bool _moved = false; // au-delà du seuil : ce n'est plus un tap
  bool _multi = false; // deux doigts à un moment du geste
  Offset? _lastTapPos;
  Duration? _lastTapTime;
  Offset _velocity = Offset.zero;
  Duration _lastMoveTime = Duration.zero;

  ChessGame get game => widget.game;

  double _dist() {
    final v = _pointers.values.toList();
    return (v[0] - v[1]).distance;
  }

  Offset _mid() {
    final v = _pointers.values.toList();
    return (v[0] + v[1]) / 2;
  }

  void _down(PointerDownEvent e) {
    if (_pointers.isEmpty) {
      _downPos = e.localPosition;
      _moved = false;
      _multi = false;
      _velocity = Offset.zero;
      game.boardCamera.stop();
    }
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length >= 2) _multi = true;
    game.boardCamera.gestureActive = true;
  }

  void _move(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;
    final cam = game.boardCamera;
    if (_pointers.length >= 2 && _pointers.length == 2) {
      final d0 = _dist(), m0 = _mid();
      _pointers[e.pointer] = e.localPosition;
      final d1 = _dist(), m1 = _mid();
      if (d0 > 1) cam.zoomAt(m0, cam.zoom * d1 / d0);
      cam.panBy(m1 - m0);
      return;
    }
    _pointers[e.pointer] = e.localPosition;
    if (_multi) return;
    if (!_moved) {
      if ((e.localPosition - _downPos).distance <= ChessGameView.tapSlop) return;
      _moved = true;
      // Le mouvement compte à partir du dépassement du seuil (pas de saut).
      _lastMoveTime = e.timeStamp;
      return;
    }
    final delta = e.localPosition - prev;
    cam.panBy(delta);
    final dt = (e.timeStamp - _lastMoveTime).inMicroseconds / 1e6;
    if (dt > 0) _velocity = Offset.lerp(_velocity, delta / dt, 0.5)!;
    _lastMoveTime = e.timeStamp;
  }

  void _up(PointerUpEvent e) {
    final wasLast = _pointers.length == 1;
    _pointers.remove(e.pointer);
    if (_pointers.isNotEmpty) return;
    final cam = game.boardCamera;
    cam.gestureActive = false;
    if (!wasLast) return;
    if (!_multi && !_moved) {
      final pos = e.localPosition;
      final now = e.timeStamp;
      final isDouble = _lastTapTime != null &&
          now - _lastTapTime! <= ChessGameView.doubleTapWindow &&
          (pos - _lastTapPos!).distance <= ChessGameView.tapSlop * 4;
      if (isDouble) {
        _lastTapTime = null;
        cam.doubleTap(pos);
      } else {
        _lastTapTime = now;
        _lastTapPos = pos;
        game.handleTap(pos);
      }
    } else if (_moved && !_multi) {
      // Un geste de plus d'un doigt n'a pas d'inertie ; un glissé simple oui.
      if (e.timeStamp - _lastMoveTime < const Duration(milliseconds: 80)) cam.fling(_velocity);
    }
  }

  void _cancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) game.boardCamera.gestureActive = false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: GameWidget(game: game),
          ),
        ),
        Positioned(
          right: 10,
          top: 10,
          child: ValueListenableBuilder<bool>(
            valueListenable: game.zoomed,
            builder: (context, zoomed, _) => zoomed
                ? IconButton.filledTonal(
                    key: const ValueKey('reset-zoom'),
                    tooltip: 'Vue entière',
                    icon: const Icon(Icons.zoom_out_map),
                    onPressed: game.resetView,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
