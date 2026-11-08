import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/attacks.dart';
import '../game/gallery_game.dart';
import '../theme.dart';

/// Galerie de démonstration : 6 guerriers x 3 couleurs et un bouton par attaque spéciale.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final GalleryGame _game = GalleryGame();

  Widget _btn(String label, VoidCallback onTap, {Color? color}) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color ?? kPanel,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 40),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Galerie des guerriers')),
      body: Column(
        children: [
          Expanded(child: RepaintBoundary(child: GameWidget(game: _game))),
          Container(
            color: kBg,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final t in galleryOrder)
                  _btn('${pieceNameFr(t)} : ${attackName(t)}', () => _game.playAttack(t),
                      color: const Color(0xFF7A3B1A)),
                _btn('Sélection', _game.toggleSelected),
                _btn('Gel', _game.toggleFrozen),
                _btn('Roi en échec', _game.toggleCheck),
                _btn('ÉCHEC !', _game.showCheck, color: const Color(0xFF8A5A00)),
                _btn('MAT !', _game.showMate, color: const Color(0xFF8A1A33)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
