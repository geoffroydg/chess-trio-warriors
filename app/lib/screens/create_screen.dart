import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _password = TextEditingController();
  String _mode = 'firstMate';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Choisis un mot de passe pour ton salon.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await context.read<AppState>().createRoom(_password.text, _mode);
      nav.popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _modeCard(String mode, String title, String desc, IconData icon) {
    final sel = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF2A3560) : kPanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: sel ? kOrange : Colors.white12, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, size: 34, color: sel ? kOrange : Colors.white54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(desc, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            if (sel) const Icon(Icons.check_circle, color: kOrange),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un salon')),
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
                  TextField(
                    controller: _password,
                    obscureText: true,
                    maxLength: 64,
                    style: const TextStyle(fontSize: 20),
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe du salon',
                      counterText: '',
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Mode de jeu',
                      style: TextStyle(fontSize: 16, color: Colors.white70)),
                  const SizedBox(height: 8),
                  _modeCard('firstMate', 'Premier mat',
                      'La partie s\'arrête au premier échec et mat.', Icons.flag),
                  const SizedBox(height: 10),
                  _modeCard('twoMates', 'Deux mats',
                      'Le joueur maté est éliminé, le dernier en jeu gagne.', Icons.military_tech),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 16)),
                  ],
                  const SizedBox(height: 24),
                  BigButton(
                    label: _busy ? 'Création…' : 'Créer le salon',
                    icon: Icons.rocket_launch,
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
