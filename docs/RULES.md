# Règles officielles — Chess Trio Warriors

Ce document est la référence des règles du jeu. Le moteur `engine/` en est l'implémentation
exacte (source de vérité côté serveur).

## 1. Joueurs et ordre de jeu

- Trois joueurs : **0 = Blanc**, **1 = Rouge**, **2 = Noir**.
- Ordre de jeu : 0 → 1 → 2 → 0… Les joueurs éliminés sont sautés.

## 2. Le plateau

### 2.1 Forme

Le plateau est un hexagone régulier de **96 cases** :

- 3 **secteurs** (un par joueur) de 4 rangées × 8 colonnes = 32 cases ;
- chaque secteur est coupé en deux **moitiés** de 4 × 4 : colonnes a-d et colonnes e-h ;
- chaque moitié est un quadrilatère (« cerf-volant ») construit autour d'un sommet de
  l'hexagone ; les 6 moitiés se rejoignent au **centre** en rosette : les 6 cases d4/e4 des
  trois joueurs touchent toutes le point central.

Trois côtés alternés de l'hexagone portent les rangées 1 des joueurs ; les trois autres côtés
sont formés par la colonne a d'un joueur et la colonne h de son voisin.

### 2.2 Coordonnées

Une case s'écrit `<secteur><colonne><rangée>`, vue depuis le **propriétaire du secteur** :

- secteur `0`, `1` ou `2` (le joueur à qui appartient ce secteur) ;
- colonne `a` à `h`, de la gauche vers la droite du propriétaire, assis face au centre ;
- rangée `1` à `4`, de son bord (rangée 1) vers le centre (rangée 4).

Exemples : `0e1` est la case de départ du roi Blanc, `2d4` une case centrale du secteur Noir.

Index interne (0..95) : `secteur × 32 + (rangée − 1) × 8 + colonne` (a = 0 … h = 7).

### 2.3 Voisinage et traversée du centre

Dans un secteur, le voisinage est celui d'un échiquier ordinaire. « Avant » signifie « vers
le centre » pour le propriétaire du secteur, « droite » vers la colonne h.

**Franchir la rangée 4** fait entrer dans le secteur voisin, par sa rangée 4 :

| Depuis (secteur s, rangée 4) | Arrivée                               |
|------------------------------|---------------------------------------|
| colonne a, b, c, d           | secteur s−1 (mod 3), colonne h, g, f, e |
| colonne e, f, g, h           | secteur s+1 (mod 3), colonne d, c, b, a |

Exemple : la colonne d de Blanc se prolonge par la colonne e de Noir (`0d1 … 0d4, 2e4 … 2e1`),
la colonne e de Blanc par la colonne d de Rouge. En entrant dans le secteur voisin, le sens
s'inverse : « avant » devient « arrière », « droite » devient « gauche » (rotation de 180°).

Les rangées ne se prolongent pas : au-delà de la colonne a ou h, c'est le bord du plateau.

**Diagonales.** Un pas en diagonale est la composition d'un pas avant/arrière et d'un pas
gauche/droite. Partout sur le plateau, les deux ordres possibles mènent à la même case, **sauf
au centre**, où 6 cases se touchent au lieu de 4 : la diagonale qui passe par le point central
**se dédouble**. Depuis une case centrale, la diagonale « avant-intérieure » mène aux deux cases
centrales situées à deux crans autour du point central. Exemple : depuis `0d4`, la diagonale
avant-droite mène à `1d4` **et** à `2d4` (mais pas à `1e4`, la case « opposée »). Ainsi la
grande diagonale `0a1-0b2-0c3-0d4` se prolonge à la fois par `1d4-1c3-1b2-1a1` et par
`2d4-2c3-2b2-2a1`.

Conséquences : une case centrale (d4/e4) a 9 voisines au lieu de 8 ; un fou, une dame ou un
pion peuvent avoir deux trajectoires après le centre.

## 3. Position initiale

Chaque joueur, dans son secteur : rangée 1 = T C F D R F C T (de a à h, dame en d1, roi en
e1), rangée 2 = 8 pions. La position est identique pour les trois joueurs (symétrie de
rotation).

## 4. Déplacement des pièces

Les mouvements sont ceux des échecs classiques, appliqués à la topologie ci-dessus :

- **Tour** : en ligne droite (avant/arrière/gauche/droite), autant de cases que voulu, sans
  sauter de pièce ; une colonne se poursuit dans le secteur d'en face (2.3).
- **Fou** : en diagonale, idem ; au centre la trajectoire se dédouble (les deux branches sont
  possibles, chacune bloquée indépendamment).
- **Dame** : tour + fou.
- **Roi** : une case dans n'importe laquelle des directions (y compris les deux cases d'une
  diagonale dédoublée).
- **Cavalier** : deux pas orthogonaux dans une direction puis un pas perpendiculaire, les pas
  pouvant être faits dans n'importe quel ordre (2-1, 1-2 ou pas intercalé) ; il saute par-dessus
  les pièces. La case d'arrivée n'est jamais voisine de la case de départ. Près du centre, les
  différents ordres peuvent mener à des cases différentes : toutes sont autorisées.
- **Pion** : avance d'une case vers l'avant (vers le centre tant qu'il est dans son secteur ;
  une fois entré dans un autre secteur, vers la rangée 1 de ce secteur). Depuis sa rangée 2 de
  départ, il peut avancer de deux cases si les deux sont libres. Il prend en diagonale vers
  l'avant (diagonales dédoublées comprises).
  - **Promotion** : un pion qui atteint la rangée 1 d'un adversaire est automatiquement
    promu en **dame**.
  - **Pas de prise en passant.**
- **Roque** (petit : roi e1→g1 et tour h1→f1 ; grand : roi e1→c1 et tour a1→d1) aux
  conditions classiques : ni le roi ni la tour concernée n'ont bougé (un droit est perdu dès
  que la pièce quitte sa case ou que la tour y est prise), les cases entre eux sont vides, le
  roi n'est pas en échec, et ni la case traversée ni la case d'arrivée du roi ne sont
  attaquées par **un quelconque adversaire actif**.

Le coup est désigné par sa case de départ et d'arrivée (pour le roque : celles du roi).

## 5. Échec, mat et pat

- Un roi est **en échec** s'il est attaqué par une pièce d'un adversaire **actif**.
- Un coup est **illégal** s'il laisse le roi de celui qui joue attaqué par une pièce active
  de n'importe quel adversaire.
- Un roi actif ne peut jamais être pris : s'il se trouve attaqué par le joueur au trait (par
  exemple après une attaque à la découverte provoquée par le troisième joueur), il reste
  simplement en échec, et son propriétaire devra parer à son tour.
- **Au début du tour d'un joueur actif** :
  - s'il n'a aucun coup légal et qu'il est en échec → il est **mat** ;
  - s'il n'a aucun coup légal sans être en échec → il est **pat** : il **passe son tour**
    (il n'est pas éliminé et rejouera dès qu'il aura un coup légal). Si tous les joueurs
    actifs sont pats l'un après l'autre, la partie est nulle.
- **Crédit du mat** : le mat est crédité à l'adversaire qui attaque le roi ; si les deux
  adversaires l'attaquent, il est crédité à celui des deux qui a joué le plus récemment.

## 6. Modes de fin de partie

- **`firstMate`** : la partie s'arrête au premier mat ; le vainqueur est le joueur crédité du
  mat.
- **`twoMates`** : le joueur mat est **éliminé** ; la partie continue entre les deux autres ;
  le dernier joueur restant gagne.

## 7. Pièces d'un joueur éliminé (gelées)

Les pièces d'un joueur éliminé (mat en mode `twoMates`, ou abandon) **restent sur le
plateau, gelées** :

- elles ne bougent plus ;
- elles ne donnent jamais échec et n'attaquent aucune case (y compris pour le roque) ;
- elles bloquent les lignes comme n'importe quelle pièce ;
- elles peuvent être prises par les joueurs actifs, **roi gelé compris** (la prise du roi
  gelé n'a aucun effet particulier).

## 8. Abandon, déconnexion, temps

- **Abandon / déconnexion** : le joueur est éliminé comme s'il était mat, **sans crédit**
  pour personne ; ses pièces sont gelées. S'il ne reste qu'un joueur actif, celui-ci gagne.
  - **Choix en mode `firstMate`** : un abandon ne termine pas la partie (personne n'a fait
    mat). La partie continue à deux joueurs et s'arrête au **mat suivant**, gagné par celui qui
    le donne (ou par le joueur restant si l'autre abandonne aussi).
- **Temps écoulé** : quand un joueur dépasse son temps de réflexion (60 s, géré par le
  serveur), un **coup légal tiré au hasard** est joué à sa place.

## 9. Parties nulles

- **Règle des 50 coups** : la partie est nulle après **50 tours complets** sans prise ni
  mouvement de pion. Un tour complet = un tour de chaque joueur actif ; le seuil est donc de
  50 × (nombre de joueurs actifs) tours individuels consécutifs (150 à trois, 100 à deux). Un
  tour passé pour cause de pat compte comme un tour.
- **Triple répétition** : la partie est nulle quand la même position se présente pour la
  troisième fois (même placement des pièces, même joueur au trait, mêmes joueurs actifs, mêmes
  droits de roque).
- Plus aucun joueur actif ne peut jouer (tous pats) : nulle.

Il n'y a pas de nulle automatique par matériel insuffisant.

## 10. Interface du moteur (`engine/src/index.ts`)

État immuable, entièrement sérialisable en JSON (`GameState`).

| Fonction | Rôle |
|----------|------|
| `initialState(mode)` | nouvelle partie (`'firstMate'` ou `'twoMates'`) |
| `legalMoves(state)` | coups légaux du joueur au trait (`{ from, to, castle?, promotion?, capture? }`) |
| `applyMove(state, move)` | nouvel état ; lève une erreur si le coup est illégal |
| `randomMove(state, rng?)` | coup légal aléatoire (timeout), `rng` injectable |
| `resign(state, player)` | abandon / déconnexion |
| `status(state)` | trait, échecs en cours, joueurs actifs, éliminations, résultat |
| `boardCells()` | géométrie de rendu des 96 cases (centre + 4 sommets) |
| `customState(mode, pieces, opts)` | position arbitraire (tests, puzzles) |

`state.lastEvent` décrit le dernier évènement (pour animations et voix) : pièce déplacée,
pièce prise (type, propriétaire, gelée ou non), promotion, roque (avec le trajet de la tour),
échecs en cours après le coup (`checks` : joueur attaqué + attaquants), mats constatés
(`mates`), éliminations, passes pour pat, fin de partie (`gameOver`).

### Géométrie

`boardCells()` (et le fichier `engine/geometry.json` produit par
`npm run export-geometry`) donne, pour chaque case : `id`, `index`, `sector`, `file`, `rank`,
centre `x, y` et `polygon` (4 sommets). Repère normalisé : x vers la droite, **y vers le bas**,
hexagone de centre (0,5 ; 0,5) et de rayon 0,5. Blanc (0) est en bas, Rouge (1) en haut à
droite, Noir (2) en haut à gauche ; une rotation de 120° fait passer d'un secteur au suivant.
Le client peut faire pivoter l'ensemble pour placer le joueur local en bas.
