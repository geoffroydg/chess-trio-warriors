# Turbo Couloirs

Prototype d'un jeu de course infinie pour téléphone (style Temple Run / Subway Surfers).
Une piste d'athlétisme, 3 couloirs, des haies, des barres, des caisses et des pièces.

## Choix technique

**Three.js (3D dans le navigateur) + Capacitor plus tard pour l'appli Android.**
Le même code tourne dès aujourd'hui dans un navigateur de téléphone, et Capacitor l'emballera tel quel en appli Play Store, avec le plugin AdMob ; les modèles Meshy (format GLB) se chargent directement dans Three.js.

## Comment jouer

| Geste | Action |
| --- | --- |
| Glisser à gauche / à droite | Changer de couloir |
| Glisser vers le haut | Sauter (par-dessus les haies) |
| Glisser vers le bas | Glisser (sous les barres jaunes) |
| Pencher le téléphone (option) | Changer de couloir |

Sur ordinateur : flèches du clavier, et Échap pour la pause.

- La vitesse augmente avec le temps.
- Score = mètres parcourus + 10 points par pièce.
- Le meilleur score est gardé sur l'appareil.
- Après une chute : « Rejouer », ou « Continuer » une fois par partie.

## Publicité (prévue, pas activée)

- `ADS.enabled = false` dans `www/game.js`.
- **Bannière** : la bande en bas de l'écran (`#ad-banner`). Elle est sous le jeu, jamais par-dessus.
- **Vidéo bonus** : le bouton « Continuer (vidéo bonus) » sur l'écran de fin. Le joueur choisit de la regarder. Pour l'instant, un faux compte à rebours de 3 secondes la remplace.
- Aucune pub plein écran imposée.

## Fichiers

- `www/index.html` : l'écran, les menus, les styles.
- `www/game.js` : tout le jeu (scène 3D, commandes, obstacles, score, pubs).
- `www/lib/three.min.js` : la bibliothèque Three.js r128, copiée ici pour marcher sans Internet dans l'appli.
- `scripts/build-artifact.sh` : fabrique une page unique pour la publier sur claude.ai.
- `ETAPES.md` : ce que tu devras faire toi-même (comptes, Play Store, pubs).

## Tester sur ordinateur

```bash
cd www && python3 -m http.server 8080
```

Puis ouvrir http://localhost:8080 dans le navigateur.

## Remarque sur l'inclinaison

L'inclinaison du téléphone marche quand le jeu est ouvert directement (et dans la future appli).
Dans la page claude.ai, le navigateur bloque ce capteur : utilise les glissements du doigt.
