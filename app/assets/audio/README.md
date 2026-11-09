# Fichiers audio (étape 4b)

Générés par `scripts/audio/` (workflow `.github/workflows/audio.yml`), format OGG Vorbis, 100 % originaux
(voir `CREDITS.md`). Tous sont facultatifs : `SoundService` ignore silencieusement ceux qui manquent.

## Musique (`music/`, OGG Vorbis stéréo 44,1 kHz, ~60 kb/s, ≤ 12 Mo au total)
Composée par algorithme (`scripts/audio/compose.py`, `scores.py`), rendue par FluidSynth + FluidR3_GM puis
mixée par ffmpeg (réverbération de salle, EQ, compression légère, -20 LUFS). Leitmotiv commun à tous les morceaux.
- `music/menu.ogg` : accueil et salon (~2 min, héroïque et lumineux, rebouclé par fondu enchaîné)
- `music/game_1.ogg` … `game_6.ogg` : partie en cours (3–4 min chacun, 74–92 BPM) ; playlist aléatoire sans
  répétition jusqu'à épuisement, fondus enchaînés de 4 s :
  1. Aube sur la montagne (ré dorien, shakuhachi, koto) · 2. Méditation du maître (la éolien, piano, cloche) ·
  3. Entraînement (sol dorien, flûte, pizzicati, taiko léger) · 4. Ciel du tournoi (fa majeur → sol, cors, harpe) ·
  5. Rivalité (mi éolien, violoncelle, hautbois) · 6. Sérénité avant le combat (si♭ majeur, flûte, piano)
- `music/check_sting.ogg` : échec (~3 s, taiko + cordes en trémolo), joué par-dessus la musique
- `music/victory.ogg` : fanfare douce de victoire (~15 s) ; `music/defeat.ogg` : défaite (~10 s, mélancolique)

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
Le workflow recompose toujours la musique ; voix et effets ne sont régénérés que s'ils manquent
(`workflow_dispatch` avec `regen=all` ou variable de dépôt `AUDIO_REGEN=all` pour tout refaire).
Les MIDI de contrôle sont écrits dans `scripts/audio/out/` (non suivis) et publiés comme artefact de la CI.
