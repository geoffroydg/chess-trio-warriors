import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'create_screen.dart';
import 'join_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _pseudo;

  @override
  void initState() {
    super.initState();
    _pseudo = TextEditingController(text: context.read<AppState>().pseudo);
  }

  @override
  void dispose() {
    _pseudo.dispose();
    super.dispose();
  }

  Future<void> _go(Widget screen) async {
    final app = context.read<AppState>();
    final p = _pseudo.text.trim();
    if (p.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choisis d\'abord un pseudo.')));
      return;
    }
    await app.setPseudo(p);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Backdrop(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Réglages',
                icon: const Icon(Icons.settings, size: 28),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.hexagon_outlined, size: 84, color: kOrange),
                      const SizedBox(height: 8),
                      ShaderMask(
                        shaderCallback: (r) =>
                            const LinearGradient(colors: [kOrange, kBlue]).createShader(r),
                        child: const Text(
                          kAppName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text('Les échecs à trois guerriers',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.white70)),
                      const SizedBox(height: 36),
                      TextField(
                        controller: _pseudo,
                        maxLength: 16,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(fontSize: 20),
                        decoration: const InputDecoration(
                          labelText: 'Ton pseudo',
                          counterText: '',
                          prefixIcon: Icon(Icons.person),
                        ),
                        onChanged: (v) => context.read<AppState>().setPseudo(v),
                      ),
                      const SizedBox(height: 24),
                      BigButton(
                        label: 'Créer un salon',
                        icon: Icons.add_circle_outline,
                        onPressed: () => _go(const CreateScreen()),
                      ),
                      const SizedBox(height: 16),
                      BigButton(
                        label: 'Rejoindre',
                        icon: Icons.login,
                        secondary: true,
                        onPressed: () => _go(const JoinScreen()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
