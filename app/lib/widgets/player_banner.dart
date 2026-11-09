import 'package:flutter/material.dart';

import '../game/piece_component.dart';
import '../models/protocol.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'turn_timer.dart';

/// Bandeau des 3 joueurs ; celui au trait est mis en avant avec le minuteur.
class PlayerBanner extends StatelessWidget {
  const PlayerBanner({super.key, required this.app, required this.game});
  final AppState app;
  final GameMsg game;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          for (var p = 0; p < 3; p++)
            Expanded(child: _tile(p)),
        ],
      ),
    );
  }

  Widget _tile(int p) {
    final active = game.state.active[p];
    final turn = !game.over && game.turn == p;
    final connected = app.playerConnected(p);
    final info = app.playerInfo(p);
    final avatar = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? playerColors[p] : Colors.grey.shade700,
        border: Border.all(color: playerAccents[p], width: 2),
      ),
      child: Text(
        app.playerName(p).characters.first.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: p == 0 && active ? const Color(0xFF1A2347) : Colors.white,
        ),
      ),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: turn ? const Color(0xFF2A3560) : kPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: turn ? kOrange : Colors.transparent, width: 2),
        boxShadow: turn ? [BoxShadow(color: kOrange.withAlpha(80), blurRadius: 14)] : null,
      ),
      child: Opacity(
        opacity: active ? 1 : 0.55,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                if (turn)
                  TurnTimer(
                    key: ValueKey('timer-${game.state.ply}'),
                    deadlineMs: game.turnDeadline,
                    nowMs: () => app.serverNowMs,
                    size: 56,
                    child: avatar,
                  )
                else
                  SizedBox(width: 56, height: 56, child: Center(child: avatar)),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected ? const Color(0xFF3DDC84) : Colors.grey,
                      border: Border.all(color: kBg, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              p == app.me ? '${app.playerName(p)} (toi)' : app.playerName(p),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            if (info != null && info.isBot)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: BotBadge(level: info.level, small: true),
              ),
            if (!active)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C), borderRadius: BorderRadius.circular(8)),
                child: const Text('Éliminé',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              )
            else
              Text(playerNames[p],
                  style: TextStyle(fontSize: 11, color: playerAccents[p])),
          ],
        ),
      ),
    );
  }
}
