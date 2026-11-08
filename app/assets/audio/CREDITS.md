# Crédits audio

Tout l'audio du jeu est généré automatiquement par `scripts/audio/` (workflow `.github/workflows/audio.yml`), 100 % original.

- **Voix** : [Piper TTS](https://github.com/rhasspy/piper) (MIT) avec les voix françaises du dépôt
  [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices) (`fr_FR-tom-medium`, `fr_FR-siwis-medium`,
  `fr_FR-upmc-medium`, `fr_FR-gilles-low`), transformées par ffmpeg. Chaque voix garde sa propre licence
  (consulter les fiches de modèle) ; les répliques sont écrites pour ce jeu.
- **Musique** : [MusicGen](https://huggingface.co/facebook/musicgen-small) (`facebook/musicgen-small`, Meta),
  poids sous licence **CC-BY-NC 4.0** : utilisation non commerciale uniquement (jeu gratuit). Si MusicGen échoue,
  un repli procédural (numpy, sans licence particulière) est utilisé.
- **Effets sonores** : synthèse procédurale numpy (`scripts/audio/gen_sfx.py`).
