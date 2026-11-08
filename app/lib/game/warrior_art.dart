import 'dart:ui' as ui;

import '../models/protocol.dart';

/// Rôles de couleur des calques (remplacés par la palette du joueur).
class Role {
  static const outfit = 0, dark = 1, light = 2, skin = 3, skinDark = 4, accent = 5;
}

/// Palette d'un camp : tenue ET aura portent la couleur du joueur.
class WarriorPalette {
  WarriorPalette({
    required this.outfit,
    required this.dark,
    required this.light,
    required this.aura,
    required this.accent,
    this.skin = const ui.Color(0xFFE8B98F),
    this.skinDark = const ui.Color(0xFFC48F66),
  }) {
    roles = [outfit, dark, light, skin, skinDark, accent];
    // Niveaux d'alpha pré-calculés pour les flammes (aucune allocation par image).
    flames = List.generate(16, (i) => aura.withAlpha((i + 1) * 16 - 1));
    final cache = ui.Gradient.radial(ui.Offset.zero, 1,
        [aura.withAlpha(255), aura.withAlpha(110), aura.withAlpha(0)], [0, 0.5, 1]);
    glow = ui.Paint()..shader = cache;
  }

  final ui.Color outfit, dark, light, aura, accent, skin, skinDark;
  late final List<ui.Color> roles;
  late final List<ui.Color> flames;
  late final ui.Paint glow;

  /// Blanc : or/orange. Rouge : cramoisi. Noir : violet/indigo.
  static final white = WarriorPalette(
      outfit: const ui.Color(0xFFF2A93B),
      dark: const ui.Color(0xFFA8641A),
      light: const ui.Color(0xFFFFD98A),
      aura: const ui.Color(0xFFFFB84D),
      accent: const ui.Color(0xFFFFF3C4));
  static final red = WarriorPalette(
      outfit: const ui.Color(0xFFD81F3C),
      dark: const ui.Color(0xFF7A0F25),
      light: const ui.Color(0xFFFF6B7D),
      aura: const ui.Color(0xFFFF3355),
      accent: const ui.Color(0xFFFFD0A0));
  static final black = WarriorPalette(
      outfit: const ui.Color(0xFF5B3FBF),
      dark: const ui.Color(0xFF2A2070),
      light: const ui.Color(0xFF9B83F0),
      aura: const ui.Color(0xFF9A6BFF),
      accent: const ui.Color(0xFFC9B8FF));

  /// Alerte d'échec : flammes rouge vif quelle que soit la couleur du joueur.
  static final alert = WarriorPalette(
      outfit: red.outfit, dark: red.dark, light: red.light,
      aura: const ui.Color(0xFFFF2020), accent: red.accent);

  /// Pièce gelée : pierre grise.
  static final stone = WarriorPalette(
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

/// Un calque de dessin en coordonnées unitaires (pieds en y=0, hauteur vers y<0).
class ArtLayer {
  ArtLayer(this.path, {this.role = -1, ui.Color? color, this.outline = true})
      : color = color,
        stone = color == null ? null : _gray(color);
  final ui.Path path;
  final int role;
  final ui.Color? color;
  final ui.Color? stone;
  final bool outline;

  static ui.Color _gray(ui.Color c) {
    final l = (0.3 * c.r + 0.59 * c.g + 0.11 * c.b);
    final v = (60 + l * 120).round().clamp(0, 255);
    return ui.Color.fromARGB(255, v, v, v + 4 > 255 ? 255 : v + 4);
  }
}

ui.Path _poly(List<double> p) {
  final path = ui.Path()..moveTo(p[0], p[1]);
  for (var i = 2; i < p.length; i += 2) {
    path.lineTo(p[i], p[i + 1]);
  }
  return path..close();
}

/// Courbe fermée lissée passant près des points (milieux + quadratiques).
ui.Path _smooth(List<double> p) {
  final n = p.length ~/ 2;
  double px(int i) => p[(i % n) * 2];
  double py(int i) => p[(i % n) * 2 + 1];
  final path = ui.Path()..moveTo((px(n - 1) + px(0)) / 2, (py(n - 1) + py(0)) / 2);
  for (var i = 0; i < n; i++) {
    path.quadraticBezierTo(px(i), py(i), (px(i) + px(i + 1)) / 2, (py(i) + py(i + 1)) / 2);
  }
  return path..close();
}

ui.Path _oval(double cx, double cy, double rx, double ry) =>
    ui.Path()..addOval(ui.Rect.fromCenter(center: ui.Offset(cx, cy), width: rx * 2, height: ry * 2));

ui.Path _rr(double l, double t, double r, double b, [double rad = 0.05]) => ui.Path()
  ..addRRect(ui.RRect.fromLTRBR(l, t, r, b, ui.Radius.circular(rad)));

List<double> _mirror(List<double> p) => [
      for (var i = 0; i < p.length; i += 2) ...[-p[i], p[i + 1]],
    ];

const _ink = ui.Color(0xFF14101E);
const _white = ui.Color(0xFFF4F1EA);

/// Silhouettes des six guerriers, construites une seule fois.
class WarriorArt {
  static final Map<PieceType, List<ArtLayer>> _cache = {};

  /// Hauteur approximative (unités) pour placer l'aura et les effets.
  static double heightOf(PieceType t) => switch (t) {
        PieceType.king => 3.55,
        PieceType.queen => 3.2,
        PieceType.bishop => 3.5,
        PieceType.knight => 2.9,
        PieceType.rook => 3.0,
        PieceType.pawn => 2.3,
      };

  static List<ArtLayer> layers(PieceType t) => _cache.putIfAbsent(t, () => _build(t));

  static List<ArtLayer> _build(PieceType t) => switch (t) {
        PieceType.pawn => _pawn(),
        PieceType.rook => _rook(),
        PieceType.bishop => _bishop(),
        PieceType.knight => _knight(),
        PieceType.queen => _queen(),
        PieceType.king => _king(),
      };

  static ArtLayer _eye(double x, double y, [double rx = 0.05, double ry = 0.065]) =>
      ArtLayer(_oval(x, y, rx, ry), color: _ink, outline: false);

  static List<ArtLayer> _pawn() => [
        ArtLayer(_poly([-0.55, 0, 0.55, 0, 0.42, -0.9, -0.42, -0.9]), role: Role.dark),
        ArtLayer(_oval(-0.28, -0.03, 0.26, 0.11), color: const ui.Color(0xFF3B2A22)),
        ArtLayer(_oval(0.28, -0.03, 0.26, 0.11), color: const ui.Color(0xFF3B2A22)),
        ArtLayer(_poly([-0.48, -0.8, 0.48, -0.8, 0.4, -1.58, -0.4, -1.58]), role: Role.outfit),
        ArtLayer(_poly([-0.2, -1.58, 0.2, -1.58, 0, -1.15]), role: Role.skinDark, outline: false),
        ArtLayer(_rr(-0.5, -1.02, 0.5, -0.82), color: _white),
        ArtLayer(_smooth([-0.46, -1.52, -0.26, -1.45, -0.5, -0.92, -0.7, -1.0]), role: Role.light),
        ArtLayer(_smooth([0.46, -1.52, 0.26, -1.45, 0.5, -0.92, 0.7, -1.0]), role: Role.light),
        ArtLayer(_oval(-0.6, -0.86, 0.13, 0.13), role: Role.skin),
        ArtLayer(_oval(0.6, -0.86, 0.13, 0.13), role: Role.skin),
        ArtLayer(_rr(-0.1, -1.72, 0.1, -1.55, 0.03), role: Role.skinDark, outline: false),
        ArtLayer(_oval(0, -1.9, 0.35, 0.37), role: Role.skin),
        ArtLayer(
            _poly([-0.37, -1.92, -0.32, -2.2, -0.16, -2.12, -0.06, -2.38, 0.1, -2.14, 0.26, -2.27,
              0.36, -1.92, 0, -2.06]),
            color: const ui.Color(0xFF2A1A12)),
        ArtLayer(_rr(-0.37, -2.04, 0.37, -1.93, 0.03), role: Role.light),
        ArtLayer(_poly([0.33, -2.0, 0.78, -1.82, 0.58, -1.9, 0.8, -1.62, 0.33, -1.94]),
            role: Role.light),
        _eye(-0.13, -1.8),
        _eye(0.13, -1.8),
      ];

  static List<ArtLayer> _rook() => [
        ArtLayer(_poly([-0.85, 0, -0.08, 0, -0.1, -0.95, -0.85, -0.95]), role: Role.dark),
        ArtLayer(_poly(_mirror([-0.85, 0, -0.08, 0, -0.1, -0.95, -0.85, -0.95])), role: Role.dark),
        ArtLayer(_rr(-0.9, -0.3, -0.05, -0.1, 0.04), role: Role.accent),
        ArtLayer(_rr(0.05, -0.3, 0.9, -0.1, 0.04), role: Role.accent),
        ArtLayer(_poly([-0.95, -0.85, 0.95, -0.85, 1.02, -2.05, -1.02, -2.05]), role: Role.outfit),
        ArtLayer(_poly([-0.62, -1.05, 0.62, -1.05, 0.72, -2.0, -0.72, -2.0]), role: Role.light),
        ArtLayer(_poly([-0.62, -1.05, -0.5, -1.05, -0.58, -2.0, -0.72, -2.0]),
            role: Role.outfit, outline: false),
        ArtLayer(_rr(-0.97, -1.08, 0.97, -0.85, 0.03), role: Role.dark),
        ArtLayer(_poly([0, -1.2, 0.17, -1.5, 0, -1.8, -0.17, -1.5]), role: Role.accent),
        ArtLayer(_smooth([-1.0, -1.95, -0.8, -1.9, -0.82, -0.95, -1.35, -0.95, -1.4, -1.5]),
            role: Role.outfit),
        ArtLayer(_smooth([1.0, -1.95, 0.8, -1.9, 0.82, -0.95, 1.35, -0.95, 1.4, -1.5]),
            role: Role.outfit),
        ArtLayer(_oval(-1.1, -0.82, 0.3, 0.27), role: Role.accent),
        ArtLayer(_oval(1.1, -0.82, 0.3, 0.27), role: Role.accent),
        ArtLayer(_oval(-1.05, -2.05, 0.42, 0.33), role: Role.accent),
        ArtLayer(_oval(1.05, -2.05, 0.42, 0.33), role: Role.accent),
        ArtLayer(_rr(-0.42, -2.78, 0.42, -2.1, 0.08), role: Role.dark),
        ArtLayer(_rr(-0.4, -3.02, -0.2, -2.78, 0.02), role: Role.dark),
        ArtLayer(_rr(-0.1, -3.02, 0.1, -2.78, 0.02), role: Role.dark),
        ArtLayer(_rr(0.2, -3.02, 0.4, -2.78, 0.02), role: Role.dark),
        ArtLayer(_rr(-0.32, -2.58, 0.32, -2.38, 0.04), role: Role.skinDark),
        ArtLayer(_rr(-0.24, -2.54, -0.06, -2.46, 0.02), color: const ui.Color(0xFFFFFFFF), outline: false),
        ArtLayer(_rr(0.06, -2.54, 0.24, -2.46, 0.02), color: const ui.Color(0xFFFFFFFF), outline: false),
      ];

  static List<ArtLayer> _bishop() => [
        ArtLayer(_poly([-0.85, 0, 0.85, 0, 0.52, -1.7, 0.46, -2.15, -0.46, -2.15, -0.52, -1.7]),
            role: Role.outfit),
        ArtLayer(_poly([-0.22, 0, 0.22, 0, 0.17, -2.15, -0.17, -2.15]), role: Role.light),
        ArtLayer(_poly([-0.5, -1.95, -0.38, -2.1, 0.55, -1.1, 0.42, -0.95]), role: Role.dark),
        ArtLayer(_smooth([-0.44, -2.08, -0.95, -1.75, -1.05, -1.05, -0.62, -1.08, -0.4, -1.5]),
            role: Role.light),
        ArtLayer(_smooth([0.44, -2.08, 0.92, -1.9, 1.0, -1.3, 0.62, -1.35, 0.4, -1.6]),
            role: Role.light),
        ArtLayer(_oval(-0.78, -1.02, 0.12, 0.12), role: Role.skin),
        // Bâton.
        ArtLayer(_rr(0.84, -3.3, 0.94, 0.1, 0.04), color: const ui.Color(0xFF6B4A2B)),
        ArtLayer(_oval(0.89, -1.5, 0.13, 0.13), role: Role.skin),
        // Capuche pointue + visage.
        ArtLayer(_smooth([-0.5, -2.1, 0.5, -2.1, 0.46, -2.65, 0, -3.25, -0.46, -2.65]),
            role: Role.dark),
        ArtLayer(_oval(0, -2.62, 0.27, 0.3), role: Role.skin),
        ArtLayer(_oval(0, -2.85, 0.07, 0.07), role: Role.accent, outline: false),
        ArtLayer(_rr(-0.17, -2.66, -0.06, -2.62, 0.01), color: _ink, outline: false),
        ArtLayer(_rr(0.06, -2.66, 0.17, -2.62, 0.01), color: _ink, outline: false),
        for (var i = 0; i < 7; i++)
          ArtLayer(_oval(-0.34 + i * 0.113, -2.12 + (i - 3) * (i - 3) * 0.012, 0.055, 0.055),
              role: Role.accent, outline: false),
      ];

  static List<ArtLayer> _knight() => [
        ArtLayer(_poly([-1.0, -0.15, -0.88, 0.0, -0.05, -0.85, 0.12, -0.62]), role: Role.dark),
        ArtLayer(_oval(-0.95, -0.07, 0.17, 0.12), role: Role.accent),
        ArtLayer(_poly([0.05, -0.9, 0.5, -0.8, 0.62, -0.12, 0.42, -0.04, 0.32, -0.5, -0.02, -0.65]),
            role: Role.dark),
        ArtLayer(_oval(0.52, -0.06, 0.2, 0.12), role: Role.accent),
        ArtLayer(_poly([-0.4, -0.7, 0.46, -0.7, 0.42, -1.72, -0.36, -1.72]), role: Role.outfit),
        ArtLayer(_rr(-0.42, -0.92, 0.48, -0.74, 0.03), role: Role.accent),
        ArtLayer(_poly([-0.28, -1.72, 0.3, -1.72, 0.0, -1.2]), role: Role.light, outline: false),
        ArtLayer(_smooth([-0.3, -1.62, -0.14, -1.5, -0.8, -1.05, -0.98, -1.2]), role: Role.skin),
        ArtLayer(_oval(-1.0, -1.12, 0.13, 0.13), role: Role.accent),
        ArtLayer(_smooth([0.32, -1.62, 0.42, -1.45, 0.95, -1.32, 0.88, -1.58]), role: Role.skin),
        ArtLayer(_oval(1.0, -1.44, 0.17, 0.15), role: Role.accent),
        ArtLayer(_oval(0.05, -2.0, 0.31, 0.33), role: Role.skin),
        _eye(0.0, -1.98),
        _eye(0.2, -1.98),
        ArtLayer(_poly([-0.05, -2.07, 0.1, -2.1, 0.0, -2.04]), color: _ink, outline: false),
      ];

  /// Cheveux et écharpe du cavalier : dessinés dynamiquement (voir WarriorPiece).
  static List<ArtLayer> _queen() => [
        ArtLayer(_poly([-0.5, 0, -0.08, 0, -0.1, -1.1, -0.48, -1.1]), role: Role.dark),
        ArtLayer(_poly([0.5, 0, 0.08, 0, 0.1, -1.1, 0.48, -1.1]), role: Role.dark),
        ArtLayer(_poly([-0.55, 0, -0.07, 0, -0.09, -0.45, -0.52, -0.45]), role: Role.accent),
        ArtLayer(_poly([0.55, 0, 0.07, 0, 0.09, -0.45, 0.52, -0.45]), role: Role.accent),
        ArtLayer(_poly([-0.68, -0.75, 0.68, -0.75, 0.42, -1.4, -0.42, -1.4]), role: Role.outfit),
        ArtLayer(_poly([-0.68, -0.75, -0.3, -0.75, -0.05, -1.4, -0.42, -1.4]),
            role: Role.light, outline: false),
        ArtLayer(_poly([-0.4, -1.3, 0.4, -1.3, 0.36, -2.12, -0.36, -2.12]), role: Role.outfit),
        ArtLayer(_rr(-0.42, -1.45, 0.42, -1.28, 0.03), role: Role.accent),
        ArtLayer(_poly([-0.2, -2.12, 0.2, -2.12, 0, -1.7]), role: Role.skin, outline: false),
        ArtLayer(_smooth([-0.4, -2.05, -0.28, -1.95, -0.62, -1.3, -0.76, -1.4]), role: Role.skin),
        ArtLayer(_smooth([0.4, -2.05, 0.28, -1.95, 0.62, -1.3, 0.76, -1.4]), role: Role.skin),
        ArtLayer(_oval(-0.7, -1.32, 0.13, 0.13), role: Role.accent),
        ArtLayer(_oval(0.7, -1.32, 0.13, 0.13), role: Role.accent),
        ArtLayer(_oval(-0.46, -2.1, 0.22, 0.15), role: Role.accent),
        ArtLayer(_oval(0.46, -2.1, 0.22, 0.15), role: Role.accent),
        ArtLayer(_rr(-0.07, -2.3, 0.07, -2.14, 0.02), role: Role.skinDark, outline: false),
        ArtLayer(_oval(0, -2.55, 0.3, 0.34), role: Role.skin),
        _eye(-0.12, -2.52, 0.05, 0.07),
        _eye(0.12, -2.52, 0.05, 0.07),
        ArtLayer(_rr(-0.07, -2.38, 0.07, -2.33, 0.02), color: const ui.Color(0xFFC0405A), outline: false),
      ];

  static List<ArtLayer> _king() => [
        ArtLayer(_poly([-1.0, 0, 1.0, 0, 0.74, -1.5, 0.62, -2.15, -0.62, -2.15, -0.74, -1.5]),
            role: Role.outfit),
        ArtLayer(_poly([-0.08, 0, 0.08, 0, 0.05, -2.15, -0.05, -2.15]), role: Role.dark, outline: false),
        ArtLayer(_poly([-1.0, 0, 1.0, 0, 0.97, -0.16, -0.97, -0.16]), role: Role.accent),
        ArtLayer(_poly([-0.42, -2.15, 0.42, -2.15, 0, -1.45]), role: Role.light),
        ArtLayer(_rr(-0.74, -1.4, 0.74, -1.14, 0.04), role: Role.dark),
        ArtLayer(_oval(0, -1.27, 0.17, 0.2), role: Role.accent),
        ArtLayer(_smooth([-0.55, -2.1, -0.98, -1.75, -1.1, -1.0, -0.7, -0.98, -0.5, -1.5]),
            role: Role.light),
        ArtLayer(_smooth([0.55, -2.1, 0.98, -1.75, 1.1, -1.0, 0.7, -0.98, 0.5, -1.5]),
            role: Role.light),
        ArtLayer(_oval(0, -1.02, 0.2, 0.12), role: Role.skin),
        ArtLayer(_oval(0, -1.78, 0.11, 0.11), role: Role.accent, outline: false),
        ArtLayer(_oval(0, -2.58, 0.37, 0.4), role: Role.skin),
        ArtLayer(_oval(0, -3.1, 0.15, 0.15), color: const ui.Color(0xFFD7D7E0)),
        ArtLayer(_smooth([-0.37, -2.7, -0.3, -2.95, 0, -3.0, 0.3, -2.95, 0.37, -2.7, 0.25, -2.85, 0, -2.88, -0.25, -2.85]),
            color: const ui.Color(0xFFD7D7E0), outline: false),
        ArtLayer(_smooth([-0.34, -2.45, 0.34, -2.45, 0.3, -2.0, 0, -1.5, -0.3, -2.0]),
            color: _white),
        ArtLayer(_poly([-0.22, -2.4, 0, -2.34, 0.22, -2.4, 0.12, -2.28, -0.12, -2.28]),
            color: const ui.Color(0xFFE6E2D8), outline: false),
        ArtLayer(_poly([-0.3, -2.72, -0.08, -2.64, -0.08, -2.7, -0.3, -2.8]), color: _white, outline: false),
        ArtLayer(_poly([0.3, -2.72, 0.08, -2.64, 0.08, -2.7, 0.3, -2.8]), color: _white, outline: false),
        _eye(-0.16, -2.62, 0.06, 0.03),
        _eye(0.16, -2.62, 0.06, 0.03),
      ];
}
