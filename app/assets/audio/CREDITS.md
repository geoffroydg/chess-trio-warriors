# Crédits audio

Tout l'audio du jeu est généré automatiquement par `scripts/audio/` (workflow `.github/workflows/audio.yml`), 100 % original.

- **Voix** : [Piper TTS](https://github.com/rhasspy/piper) (MIT) avec les voix françaises du dépôt
  [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices) (`fr_FR-tom-medium`, `fr_FR-siwis-medium`,
  `fr_FR-upmc-medium`, `fr_FR-gilles-low`), transformées par ffmpeg. Chaque voix garde sa propre licence
  (consulter les fiches de modèle) ; les répliques sont écrites pour ce jeu.
- **Musique** : composition algorithmique originale écrite pour ce jeu (`scripts/audio/compose.py`, `scores.py` :
  aucune mélodie ni thème existant), rendue avec [FluidSynth](https://www.fluidsynth.org/) (LGPL-2.1, outil de rendu
  non distribué) et la soundfont General MIDI **FluidR3_GM** de Frank Wen (licence **MIT**, paquet Debian/Ubuntu
  `fluid-soundfont-gm`), mixée avec ffmpeg.
- **Effets sonores** : synthèse procédurale numpy (`scripts/audio/gen_sfx.py`).
