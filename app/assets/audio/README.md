# Fichiers audio attendus (étape 4)

Tous les fichiers sont facultatifs : `SoundService` ignore silencieusement ceux qui manquent.
Format conseillé : `.mp3` (ou `.ogg`), 100 % original, aucune référence à une franchise existante.

## Musique de fond (`music/`)
- `music/menu.mp3` : accueil et salle d'attente (boucle)
- `music/game.mp3` : partie en cours (boucle)

## Effets (`sfx/`)
- `sfx/select.mp3` : sélection d'une pièce
- `sfx/move.mp3` : déplacement
- `sfx/capture.mp3` : prise
- `sfx/check.mp3` : échec
- `sfx/mate.mp3` : mat
- `sfx/turn.mp3` : c'est ton tour
- `sfx/win.mp3`, `sfx/lose.mp3` : fin de partie

## Voix françaises par pièce et évènement (`voice/`)
Nom : `voice/<pièce>_<évènement>.mp3`
- pièce : `king`, `queen`, `rook`, `bishop`, `knight`, `pawn`
- évènement : `move`, `capture`, `check`, `mate`

Exemple : `voice/knight_capture.mp3`, `voice/queen_mate.mp3` (24 fichiers au maximum).
