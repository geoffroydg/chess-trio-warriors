import 'dart:ui' as ui;

/// Rôles de couleur des calques (remplacés par la palette du joueur).
class Role {
  static const outfit = 0, dark = 1, light = 2, skin = 3, skinDark = 4, accent = 5, aura = 6;
  static const count = 7;
}

/// Palette d'un camp : tenue ET aura portent la couleur du joueur.
class WarriorPalette {
  WarriorPalette({
    required this.id,
    required this.outfit,
    required this.dark,
    required this.light,
    required this.aura,
    required this.accent,
    this.skin = const ui.Color(0xFFE8B98F),
    this.skinDark = const ui.Color(0xFFC48F66),
  }) {
    roles = [outfit, dark, light, skin, skinDark, accent, aura];
    // Niveaux d'alpha pré-calculés pour les flammes (aucune allocation par image).
    flames = List.generate(16, (i) => aura.withAlpha((i + 1) * 16 - 1));
    final cache = ui.Gradient.radial(ui.Offset.zero, 1,
        [aura.withAlpha(255), aura.withAlpha(110), aura.withAlpha(0)], [0, 0.5, 1]);
    glow = ui.Paint()..shader = cache;
  }

  /// Identifiant (cache des couleurs dérivées) : 0..2 joueurs, 3 alerte, 4 pierre.
  final int id;
  final ui.Color outfit, dark, light, aura, accent, skin, skinDark;
  late final List<ui.Color> roles;
  late final List<ui.Color> flames;
  late final ui.Paint glow;

  /// Blanc : or/orange. Rouge : cramoisi. Noir : violet/indigo.
  static final white = WarriorPalette(
      id: 0,
      outfit: const ui.Color(0xFFF2A93B),
      dark: const ui.Color(0xFFA8641A),
      light: const ui.Color(0xFFFFD98A),
      aura: const ui.Color(0xFFFFB84D),
      accent: const ui.Color(0xFFFFF3C4));
  static final red = WarriorPalette(
      id: 1,
      outfit: const ui.Color(0xFFD81F3C),
      dark: const ui.Color(0xFF7A0F25),
      light: const ui.Color(0xFFFF6B7D),
      aura: const ui.Color(0xFFFF3355),
      accent: const ui.Color(0xFFFFD0A0));
  static final black = WarriorPalette(
      id: 2,
      outfit: const ui.Color(0xFF5B3FBF),
      dark: const ui.Color(0xFF2A2070),
      light: const ui.Color(0xFF9B83F0),
      aura: const ui.Color(0xFF9A6BFF),
      accent: const ui.Color(0xFFC9B8FF));

  /// Alerte d'échec : flammes rouge vif quelle que soit la couleur du joueur.
  static final alert = WarriorPalette(
      id: 3,
      outfit: red.outfit, dark: red.dark, light: red.light,
      aura: const ui.Color(0xFFFF2020), accent: red.accent);

  /// Pièce gelée : pierre grise.
  static final stone = WarriorPalette(
      id: 4,
      outfit: const ui.Color(0xFF8A8D96),
      dark: const ui.Color(0xFF4E5058),
      light: const ui.Color(0xFFB3B6BE),
      aura: const ui.Color(0xFF8A8D96),
      accent: const ui.Color(0xFFA0A3AB),
      skin: const ui.Color(0xFF9A9CA4),
      skinDark: const ui.Color(0xFF6D6F77));

  static WarriorPalette of(int owner) => const [0, 1, 2].contains(owner)
      ? [white, red, black][owner]
      : white;
}

/// Gris « pierre » d'une couleur fixe (pièces pétrifiées).
ui.Color stoneOf(ui.Color c) {
  final l = (0.3 * c.r + 0.59 * c.g + 0.11 * c.b);
  final v = (60 + l * 120).round().clamp(0, 255);
  return ui.Color.fromARGB(255, v, v, v + 4 > 255 ? 255 : v + 4);
}
