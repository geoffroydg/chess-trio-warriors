import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../game/piece_component.dart';
import '../models/protocol.dart';
import '../services/connection.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final room = app.room;
    final code = room?.code ?? app.session?.code ?? '------';
    final isHost = app.me == 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salle d\'attente'),
        leading: IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Quitter le salon',
          onPressed: () async {
            if (await confirmDialog(context,
                title: 'Quitter le salon ?',
                message: 'Tu devras le rejoindre à nouveau avec le code et le mot de passe.',
                yes: 'Quitter',
                no: 'Rester')) {
              await app.leaveRoom();
            }
          },
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Backdrop(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 36),
                  const Text('Code du salon',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.white70)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Code copié.')));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: kPanel,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kOrange, width: 2),
                      ),
                      child: Text(code,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 46, fontWeight: FontWeight.w900, letterSpacing: 8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    label: 'Partager le code',
                    icon: Icons.share,
                    secondary: true,
                    onPressed: () => SharePlus.instance.share(ShareParams(
                        text:
                            'Rejoins-moi sur $kAppName ! Code du salon : $code (demande-moi le mot de passe).')),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    room?.mode == 'twoMates' ? 'Mode : Deux mats' : 'Mode : Premier mat',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  for (var i = 0; i < 3; i++) _slot(app, room?.playerById(i), i),
                  const SizedBox(height: 20),
                  if (app.connStatus != ConnStatus.connected && room == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('Connexion au salon…',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                    ),
                  if (isHost)
                    BigButton(
                      label: (room?.ready ?? false)
                          ? 'Lancer la partie'
                          : 'En attente de joueurs (${room?.players.length ?? 1}/3)',
                      icon: Icons.play_arrow_rounded,
                      onPressed: (room?.ready ?? false) ? () => app.startGame() : null,
                    )
                  else
                    const Text('L\'hôte lancera la partie dès que tout le monde est là.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _slot(AppState app, PlayerInfo? p, int i) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p == null ? Colors.white12 : playerAccents[i], width: 2),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: p == null ? Colors.white12 : playerColors[i],
            child: Text(i == 0 ? 'B' : (i == 1 ? 'R' : 'N'),
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: i == 0 && p != null ? const Color(0xFF1A2347) : Colors.white)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              p == null ? 'En attente d\'un joueur…' : '${p.pseudo}${i == app.me ? ' (toi)' : ''}${i == 0 ? ' · hôte' : ''}',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: p == null ? Colors.white38 : Colors.white),
            ),
          ),
          if (p != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 12, color: p.connected ? const Color(0xFF3DDC84) : Colors.grey),
              const SizedBox(width: 6),
              Text(p.connected ? 'connecté' : 'hors ligne',
                  style: const TextStyle(color: Colors.white70)),
            ]),
        ],
      ),
    );
  }
}
