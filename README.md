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

- Score = mètres parcourus + 10 points par pièce.
- Le meilleur score, les pièces et les achats sont gardés sur l'appareil.
- Après une chute : « Rejouer », ou « Continuer » une fois par partie.

## Difficulté

La vitesse accélère sans limite (`speedAt` dans `www/game.js`) :

| Temps | Vitesse | Ce qui change |
| --- | --- | --- |
| 0 s | 14 m/s | 1 obstacle par rangée, le plus souvent |
| 30 s | 23 m/s | conteneurs plus longs, rangées doublées |
| 60 s | 33 m/s | conteneurs qui changent de couloir |
| 90 s | 46 m/s | souvent 3 obstacles par rangée |
| 150 s | 79 m/s | presque impossible |

Un nouveau niveau tous les 400 m, annoncé par une arche. L'ambiance change à chaque niveau : matin, plein soleil, coucher de soleil, nuit sous les projecteurs.

## Bonus et boutique

Les bonus apparaissent sur la piste. Les pièces ramassées servent à les améliorer dans la boutique.

| Bonus | Effet | Amélioration |
| --- | --- | --- |
| Aimant | attire les pièces | durée, grand rayon au niveau 3 |
| Bouclier | encaisse un choc | durée, 2 chocs au niveau 4 |
| Pièces x2 | double les pièces | durée, x3 au niveau 5 |
| Fusée (1 500 pièces) | vole au-dessus des obstacles | durée |
| Sablier (2 500 pièces) | ralentit la course | durée, ralenti plus fort |
| Chance | bonus plus fréquents | de 650 m à 225 m, bonus doubles |

Prix d'un niveau : 250, 600, 1 400, 3 000, 6 000 pièces (Chance : 400 à 9 000).
Une bonne partie d'une minute rapporte environ 100 à 200 pièces : tout acheter demande des centaines de parties.

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
