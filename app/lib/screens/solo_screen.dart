import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/protocol.dart';
import '../services/api.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// « Jouer seul » : choix du mode et du niveau des 2 bots, puis partie immédiate.
class SoloScreen extends StatefulWidget {
  const SoloScreen({super.key});

  @override
  State<SoloScreen> createState() => _SoloScreenState();
}

class _SoloScreenState extends State<SoloScreen> {
  String _mode = 'firstMate';
  String _level = 'moyen';
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await context.read<AppState>().createSoloRoom(_mode, _level);
      nav.popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card({
    required bool selected,
    required VoidCallback onTap,
    required String title,
    required String desc,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2A3560) : kPanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? kOrange : Colors.white12, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, size: 30, color: selected ? kOrange : Colors.white54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(desc, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: kOrange),
          ],
        ),
      ),
    );
  }

  static const _levelDesc = {
    'facile': 'Des guerriers débutants, parfait pour apprendre.',
    'moyen': 'Ils protègent leurs pièces et sautent sur tes erreurs.',
    'difficile': 'Des maîtres qui calculent plusieurs coups à l\'avance.',
  };

  static const _levelIcons = {
    'facile': Icons.sentiment_satisfied_alt,
    'moyen': Icons.bolt,
    'difficile': Icons.local_fire_department,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jouer seul')),
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
                  const SizedBox(height: 40),
                  const Text('Mode de jeu', style: TextStyle(fontSize: 16, color: Colors.white70)),
                  const SizedBox(height: 8),
                  _card(
                    selected: _mode == 'firstMate',
                    onTap: () => setState(() => _mode = 'firstMate'),
                    title: 'Premier mat',
                    desc: 'La partie s\'arrête au premier échec et mat.',
                    icon: Icons.flag,
                  ),
                  const SizedBox(height: 10),
                  _card(
                    selected: _mode == 'twoMates',
                    onTap: () => setState(() => _mode = 'twoMates'),
                    title: 'Deux mats',
                    desc: 'Le joueur maté est éliminé, le dernier en jeu gagne.',
                    icon: Icons.military_tech,
                  ),
                  const SizedBox(height: 20),
                  const Text('Niveau des 2 bots 🤖',
                      style: TextStyle(fontSize: 16, color: Colors.white70)),
                  const SizedBox(height: 8),
                  for (final l in botLevels) ...[
                    _card(
                      selected: _level == l,
                      onTap: () => setState(() => _level = l),
                      title: botLevelLabel(l),
                      desc: _levelDesc[l]!,
                      icon: _levelIcons[l]!,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 16)),
                  ],
                  const SizedBox(height: 18),
                  BigButton(
                    label: _busy ? 'Préparation…' : 'Lancer la partie',
                    icon: Icons.play_arrow_rounded,
                    onPressed: _busy ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
