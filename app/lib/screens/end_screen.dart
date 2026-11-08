import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/piece_component.dart';
import '../models/protocol.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class EndScreen extends StatelessWidget {
  const EndScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final g = app.game!;
    final result = g.result ?? g.state.result;
    final ranking = computeRanking(g.state, result);
    final winner = result?.winner;
    final title = winner == null
        ? 'Partie nulle'
        : (winner == app.me ? 'Victoire !' : '${app.playerName(winner)} gagne');
    return Scaffold(
      body: Backdrop(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(winner == app.me ? Icons.emoji_events : Icons.flag,
                      size: 80, color: winner == app.me ? kOrange : kBlue),
                  const SizedBox(height: 8),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
                  if (result != null)
                    Text(reasonLabel(result.reason),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 17, color: Colors.white70)),
                  const SizedBox(height: 24),
                  for (final r in ranking)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: kPanel,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: r.rank == 1 && winner != null ? kOrange : Colors.white12,
                            width: 2),
                      ),
                      child: Row(
                        children: [
                          Text('${r.rank}',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 16),
                          CircleAvatar(
                            backgroundColor: playerColors[r.player],
                            radius: 14,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${app.playerName(r.player)}${r.player == app.me ? ' (toi)' : ''}',
                              style:
                                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(r.note, style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  BigButton(
                    label: 'Rejouer',
                    icon: Icons.replay,
                    onPressed: () => app.leaveRoom(),
                  ),
                  const SizedBox(height: 6),
                  const Text('Crée un nouveau salon pour une nouvelle partie.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
