import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'screens/end_screen.dart';
import 'screens/game_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lobby_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

class ChessTrioApp extends StatefulWidget {
  const ChessTrioApp({super.key, required this.appState});
  final AppState appState;

  @override
  State<ChessTrioApp> createState() => _ChessTrioAppState();
}

class _ChessTrioAppState extends State<ChessTrioApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.appState.toasts.listen((msg) {
      _messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: widget.appState,
      child: MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        scaffoldMessengerKey: _messenger,
        home: const _Root(),
      ),
    );
  }
}

/// Choisit l'écran selon la phase : accueil, salle d'attente, partie, fin.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final phase = context.select<AppState, Phase>((a) => a.phase);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: switch (phase) {
        Phase.home => const HomeScreen(key: ValueKey('home')),
        Phase.lobby => const LobbyScreen(key: ValueKey('lobby')),
        Phase.game => const GameScreen(key: ValueKey('game')),
        Phase.over => const EndScreen(key: ValueKey('over')),
      },
    );
  }
}
