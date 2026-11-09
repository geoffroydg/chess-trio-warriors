import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../game/fx.dart' show DebugFlags;
import '../services/api.dart';
import '../services/sound_service.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'gallery_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  String? _status;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _url = TextEditingController(text: app.serverUrl);
    app.sound.loadSettings().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context.read<AppState>().setServerUrl(_url.text);
    if (!mounted) return;
    setState(() => _status = 'Enregistré.');
  }

  Future<void> _test() async {
    setState(() => _status = 'Test en cours…');
    final ok = await ApiClient(_url.text).health();
    if (!mounted) return;
    setState(() => _status = ok ? 'Serveur joignable.' : 'Serveur injoignable.');
  }

  Widget _slider(String label, IconData icon, double value, Future<void> Function(double) set) {
    return Row(children: [
      Icon(icon),
      const SizedBox(width: 8),
      SizedBox(width: 72, child: Text(label)),
      Expanded(
        child: Slider(value: value, onChanged: (v) => setState(() => set(v))),
      ),
    ]);
  }

  Widget _audio(SoundService s) {
    return Column(children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: Icon(s.muted ? Icons.volume_off : Icons.volume_up),
        title: const Text('Muet'),
        value: s.muted,
        onChanged: (v) => setState(() => s.setMuted(v)),
      ),
      _slider('Musique', Icons.music_note, s.musicVolume, s.setMusicVolume),
      _slider('Voix', Icons.record_voice_over, s.voiceVolume, s.setVoiceVolume),
      _slider('Effets', Icons.graphic_eq, s.sfxVolume, s.setSfxVolume),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final sound = context.read<AppState>().sound;
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
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
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'URL du serveur',
                      prefixIcon: Icon(Icons.dns),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _url.text = kDefaultServerUrl),
                      child: const Text('Valeur par défaut'),
                    ),
                  ),
                  if (_status != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_status!,
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                    ),
                  const SizedBox(height: 8),
                  _audio(sound),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.speed),
                    title: const Text('Afficher les FPS (débogage)'),
                    value: DebugFlags.showFps.value,
                    onChanged: (v) {
                      setState(() => DebugFlags.showFps.value = v);
                      context.read<AppState>().storage.setDebugFps(v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.center_focus_strong),
                    title: const Text('Recentrer automatiquement sur le dernier coup'),
                    value: context.read<AppState>().storage.autoRecenter,
                    onChanged: (v) {
                      context.read<AppState>().storage.setAutoRecenter(v);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  BigButton(label: 'Tester la connexion', secondary: true, onPressed: _test),
                  const SizedBox(height: 14),
                  BigButton(label: 'Enregistrer', icon: Icons.save, onPressed: _save),
                  const SizedBox(height: 14),
                  BigButton(
                    label: 'Galerie des guerriers',
                    icon: Icons.auto_awesome,
                    secondary: true,
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const GalleryScreen())),
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
