import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/chess_game.dart';
import '../models/geometry.dart';
import '../models/protocol.dart';
import '../services/connection.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/player_banner.dart';

Future<BoardGeometry>? _geometryFuture;

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    _geometryFuture ??= BoardGeometry.load();
    return FutureBuilder<BoardGeometry>(
      future: _geometryFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Scaffold(body: Center(child: Text('Plateau introuvable.')));
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return _GameView(geometry: snap.data!);
      },
    );
  }
}

class _GameView extends StatefulWidget {
  const _GameView({required this.geometry});
  final BoardGeometry geometry;

  @override
  State<_GameView> createState() => _GameViewState();
}

class _GameViewState extends State<_GameView> {
  late final AppState _app;
  late final ChessGame _game;
  GameMsg? _applied;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _game = ChessGame(
      geometry: widget.geometry,
      viewer: _app.me,
      onMove: (from, to) {
        if (!_app.sendMove(from, to)) {
          _app.toast('Connexion perdue, réessaie dans un instant.');
        }
      },
      onSelect: (_) => _app.sound.playEffect('select'),
    );
    _app.addListener(_onApp);
    _onApp();
  }

  void _onApp() {
    final g = _app.game;
    if (g != null && !identical(g, _applied)) {
      _applied = g;
      _game.applyGame(g, _app.me);
    }
  }

  @override
  void dispose() {
    _app.removeListener(_onApp);
    super.dispose();
  }

  Future<void> _resign() async {
    final ok = await confirmDialog(context,
        title: 'Abandonner ?',
        message: 'Tu seras éliminé et tes pièces seront gelées. Cette action est définitive.',
        yes: 'Abandonner',
        no: 'Continuer');
    if (ok) _app.resign();
  }

  Future<void> _quit() async {
    final ok = await confirmDialog(context,
        title: 'Quitter la partie ?',
        message: 'Tu ne pourras plus la reprendre sur cet appareil.',
        yes: 'Quitter',
        no: 'Rester');
    if (ok) await _app.leaveRoom();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final g = app.game!;
    final me = app.me;
    final iAmActive = g.state.active[me];
    final myTurn = g.turn == me && !g.over;
    final String status;
    if (!iAmActive) {
      status = 'Tu es éliminé : tu regardes la partie.';
    } else if (myTurn) {
      status = 'À toi de jouer !';
    } else if (g.turn != null) {
      status = 'Tour de ${app.playerName(g.turn!)}…';
    } else {
      status = '';
    }
    return Scaffold(
      body: Backdrop(
        child: Column(
          children: [
            PlayerBanner(app: app, game: g),
            if (app.connStatus != ConnStatus.connected)
              Container(
                width: double.infinity,
                color: const Color(0xFF7A3B00),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: const Text('Reconnexion…',
                    textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            Expanded(child: RepaintBoundary(child: GameWidget(game: _game))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: myTurn ? kOrange : Colors.white70,
                      ),
                    ),
                  ),
                  if (iAmActive)
                    SizedBox(
                      width: 160,
                      child: BigButton(
                        label: 'Abandonner',
                        icon: Icons.flag_outlined,
                        danger: true,
                        onPressed: _resign,
                      ),
                    )
                  else
                    SizedBox(
                      width: 160,
                      child: BigButton(
                          label: 'Quitter', icon: Icons.logout, secondary: true, onPressed: _quit),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
