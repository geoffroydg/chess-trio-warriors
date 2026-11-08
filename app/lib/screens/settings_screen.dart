import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/api.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

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
    _url = TextEditingController(text: context.read<AppState>().serverUrl);
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

  @override
  Widget build(BuildContext context) {
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
                  BigButton(label: 'Tester la connexion', secondary: true, onPressed: _test),
                  const SizedBox(height: 14),
                  BigButton(label: 'Enregistrer', icon: Icons.save, onPressed: _save),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
