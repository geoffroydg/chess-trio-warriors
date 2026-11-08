# Fichiers audio (étape 4b)

Générés par `scripts/audio/` (workflow `.github/workflows/audio.yml`), format OGG Vorbis, 100 % originaux
(voir `CREDITS.md`). Tous sont facultatifs : `SoundService` ignore silencieusement ceux qui manquent.

## Musique (`music/`, stéréo 44,1 kHz ~96 kbps)
- `music/menu.ogg` : accueil et salon (boucle, ~30 s)
- `music/battle.ogg` : partie en cours (boucle, ~30 s)
- `music/tension.ogg` : un roi est en échec (boucle, ~20 s)
- `music/victory.ogg` : fanfare de victoire (~10 s, sans boucle)

## Effets (`sfx/`)
- `sfx/aura.ogg` : sélection d'une pièce / début de partie
- `sfx/dash.ogg` : déplacement
- `sfx/impact.ogg` : prise
- `sfx/explosion.ogg` : mat
- `sfx/beam.ogg` : échec (rayon d'énergie)
- `sfx/tick.ogg` : tic du minuteur (10 dernières secondes)
- `sfx/notify.ogg` : c'est ton tour

## Voix (`voice/`, mono 22 kHz) : `<pièce>` = `king`, `queen`, `rook`, `bishop`, `knight`, `pawn`
- `voice/<pièce>_move_1..3.ogg` (déplacement)
- `voice/<pièce>_capture_1..3.ogg` (prise)
- `voice/<pièce>_check_1..2.ogg` (échec donné)
- `voice/<pièce>_mate_1.ogg` (mat donné)
- `voice/<pièce>_captured_1.ogg` (je suis pris)
- `voice/kiai_1..4.ogg` (cris de combat)
- `voice/announcer_check.ogg`, `announcer_mate.ogg`, `announcer_yourturn.ogg`, `announcer_start.ogg`,
  `announcer_victory.ogg`, `announcer_timeout.ogg`

Soit 60 répliques de pièces + 4 kiai + 6 annonces. Textes dans `scripts/audio/lines.json`.
Les fichiers présents dans le dépôt peuvent être des versions de repli (effets numpy, musique procédurale)
remplacées par le workflow lorsque MusicGen et Piper ont pu tourner.
