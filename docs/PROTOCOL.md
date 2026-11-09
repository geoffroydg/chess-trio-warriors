# Protocole client ↔ serveur

Le serveur est un Worker Cloudflare ; chaque salon est un Durable Object. Tout le trafic est du JSON.
Les joueurs sont numérotés comme dans le moteur : 0 = Blanc (hôte), 1 = Gris, 2 = Noir (dans l'app : or, cramoisi,
violet). Ordre de jeu 0 → 1 → 2 (sens horaire sur le plateau).

**Cases** (plateau rond de 144 cases, voir `docs/RULES.md`) : `"<équipe><colonne><anneau>"`, équipe `0`-`2`, colonne
`a`-`h` (dans le sens trigonométrique), anneau `1`-`6` (1 = extérieur, 6 = bord du médaillon), ex. `"0d1"`. Index dans
`state.board` : `équipe × 48 + (anneau − 1) × 8 + colonne`. La géométrie de rendu est dans `engine/geometry.json`
(copiée dans `app/assets/geometry.json`, avec les 3 épées).

## 1. API HTTP

CORS permissif sur toutes les routes (`OPTIONS` géré). Corps JSON, 2 Ko maximum.

### `GET /health`
Renvoie `{ "ok": true }`.

### `POST /rooms`
Corps : `{ "pseudo": string, "password": string, "mode": "firstMate" | "twoMates" }`
- `pseudo` : 1 à 16 caractères (espaces de bord retirés) ; `password` : 1 à 64 caractères.
- Réponse 201 : `{ "code": "K7M2QX", "playerId": 0, "playerToken": "…" }`
- Le code a 6 caractères parmi `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (sans O/0/I/1).
- Le mot de passe est stocké haché (SHA-256 + sel aléatoire).
- Option `bots` : `[{ "level": "facile" | "moyen" | "difficile" }, …]` (1 ou 2 bots), placés sur les sièges 1 puis 2.
  - **Partie solo** : avec 2 bots, le salon est complet et la partie **démarre aussitôt** (pas de `start`) ;
    `password` est alors facultatif (personne ne peut rejoindre).
  - Avec 1 bot, `password` reste obligatoire : un second humain rejoint sur le siège libre.
  - Exemple : `{ "pseudo": "Ana", "mode": "firstMate", "bots": [{ "level": "moyen" }, { "level": "moyen" }] }`.

### `POST /rooms/:code/join`
Corps : `{ "pseudo": string, "password": string }`
- Réponse 200 : `{ "code", "playerId": 1 | 2, "playerToken" }` (premier siège libre, ceux des bots étant occupés)
- Erreurs : 400 `badRequest`, 403 `wrongPassword`, 404 `roomNotFound`, 409 `roomFull` (ou `alreadyStarted`).

Erreur HTTP : `{ "error": "<code>", "message": "<texte français>" }`.

Le `playerToken` sert à se (re)connecter ; il doit être conservé par l'app.

### `GET /rooms/:code/ws?token=<playerToken>`
Mise à niveau WebSocket. Jeton inconnu : 401 `badToken`. Plusieurs connexions du même joueur sont permises
(tous les sockets du joueur reçoivent les messages). Se reconnecter = ouvrir un nouveau socket avec le même jeton ;
le serveur renvoie aussitôt `room` puis (si la partie a commencé) `game`.

## 2. Messages client → serveur

| `type` | Champs | Effet |
|--------|--------|-------|
| `start` | — | Hôte uniquement, quand 3 joueurs (humains ou bots) sont présents : lance la partie. |
| `addBot` | `seat?` (1 ou 2 ; défaut : premier siège libre), `level` (`facile` \| `moyen` \| `difficile`, défaut `moyen`) | Hôte uniquement, en salle d'attente : place un bot sur un siège libre. |
| `removeBot` | `seat` | Hôte uniquement, en salle d'attente : retire le bot de ce siège (le siège redevient libre). |
| `move` | `from`, `to` (cases, ex. `"0e2"`), `promotion?` (`Q` \| `R` \| `B` \| `N`) | Joue un coup (au tour du joueur). Pour un roque, cases du roi. Pour une promotion, la pièce choisie (absent = dame ; autre valeur : `illegalMove`). |
| `resign` | — | Abandon : le joueur est éliminé (règles §8). |
| `registerPush` | `fcmToken` (string, ≤ 4096 car.) | Enregistre le jeton FCM du joueur pour les notifications. Un même jeton n'est associé qu'à un siège par salon (il est retiré des autres sièges). |
| `unregisterPush` | — | Supprime le jeton FCM du joueur dans ce salon. |
| `leave` | — | Quitte définitivement le salon : partie en cours → équivaut à `resign` (si le joueur est encore en jeu), puis jeton supprimé et sockets du joueur fermés ; salle d'attente → le siège est libéré (salon supprimé s'il ne reste aucun humain). Après `leave`, le serveur ignore les messages de ce siège. |
| `ping` | — | Le serveur répond `pong`. |

## 3. Messages serveur → client

### `room` — état du salon
Envoyé à la connexion et à chaque changement (arrivée, connexion/déconnexion, démarrage).
```json
{ "type": "room", "code": "K7M2QX", "mode": "firstMate",
  "players": [ { "id": 0, "pseudo": "Ana", "connected": true, "push": true, "isBot": false },
               { "id": 2, "pseudo": "Ryuna", "connected": true, "push": false, "isBot": true, "level": "difficile" } ],
  "ready": false, "started": false, "you": 0 }
```
`players` est trié par `id` et peut avoir des trous (siège libre). Un bot a `isBot: true`, `level` et est toujours
`connected`.
`ready` = 3 joueurs présents (l'hôte peut envoyer `start`). `started` = partie lancée. `you` = id du destinataire.

### `game` — état de la partie
Envoyé à tous après `start` et après chaque coup / abandon / coup automatique, et à la connexion.
```json
{ "type": "game",
  "state": { "…GameState complet du moteur…" },
  "lastEvent": { "…GameEvent du moteur…", "auto": true },
  "turn": 1,
  "legalMoves": [ { "from": "1e2", "to": "1e4" }, { "from": "1b2", "to": "1b1", "promotion": "N" } ],
  "turnDeadline": 1767225600000,
  "over": false, "result": null,
  "players": [ { "id": 0, "pseudo": "Ana", "connected": true, "push": false } ] }
```
- `lastEvent` : celui du moteur (`state.lastEvent`) ; `auto: true` si le coup a été joué par le serveur après
  expiration des 60 s. `null` juste après `start`.
- `turn` : joueur au trait (`null` si la partie est finie). `legalMoves` : ses coups légaux (vide si fini). Champs
  facultatifs d'un coup : `capture`, `castle` (`king` = petit roque côté a, `queen` = grand roque côté h), `enPassant`,
  `promotion`. Un coup de promotion apparaît **4 fois** (une par pièce : `Q`, `R`, `B`, `N`).
- `state` (moteur, `version: 2`) : `board` (144 cases, `null` ou `{ type, owner, crossed? }` — `crossed: true` pour un
  pion qui a traversé le centre), `hilts` (`[bool ×3]`, poignée de la frontière b ouverte), `enPassant`
  (`[{ target, pawn, owner }]`), `turn`, `active`, `castling`, `ply`, `quietTurns`, `eliminations`, `result`…
- `lastEvent` (moteur) : `kind`, `player`, `move`, `piece`, `captured` (`at` = case du pion pris en passant),
  `promotion` (`Q`/`R`/`B`/`N` ou `null`), `castle`, `crossedCenter` (le coup traverse le médaillon), `enPassant`,
  `kingCaptured` (équipe dont le roi « emprisonné » vient d'être capturé), `hiltsOpened` (frontières dont la poignée
  vient de s'ouvrir), `checks`, `mates`, `eliminated`, `passes` (équipes pates qui ont passé), `blocked` (équipe
  éliminée car aucune équipe ne pouvait jouer), `gameOver`.
- Raisons de fin (`result.reason`) : `mate`, `blockade` (firstMate : aucune équipe ne peut jouer), `lastStanding`,
  `fiftyMoves`, `repetition`, `stalemate`.
- `turnDeadline` : timestamp ms (horloge serveur) de la fin du tour ; `null` si la partie est finie.
- `result` : `{ winner: Player | null, reason }` du moteur quand `over`.

### `error`
`{ "type": "error", "code": "...", "message": "..." }`. Codes : `badMessage`, `notHost`, `notEnoughPlayers`,
`alreadyStarted`, `seatTaken`, `roomFull`, `notBot`, `notStarted`, `notYourTurn`, `illegalMove`, `gameOver`, `notActive`.

### `pong`
`{ "type": "pong", "now": 1767225600000 }` (permet de recaler l'horloge).

## 4. Règles de fonctionnement

- Minuteur : 60 s par tour. À l'échéance, le serveur joue `randomMove` (promotion en dame) pour le joueur au trait, connecté ou non
  (`lastEvent.auto = true`). La partie continue même si des joueurs sont déconnectés ; seul `resign` élimine.
- Bots : quand c'est au tour d'un bot, le serveur joue son coup (`botMove` du moteur, niveau du bot, promotion en dame) après un délai
  naturel de 1,2 à 2,5 s, que les humains soient connectés ou non. Un Durable Object n'a qu'une alarme : elle est
  toujours réglée sur l'échéance la plus proche (coup du bot, fin des 60 s, nettoyage du salon). Le coup d'un bot n'a
  pas `auto: true`. Les bots ne reçoivent ni messages ni notifications et n'abandonnent jamais.
- Fin de partie : plus de minuteur ; le salon est supprimé 24 h après la fin, ou 7 jours après la dernière activité
  d'un joueur.

## 5. Notifications push (FCM HTTP v1)

Envoyées aux joueurs humains ayant un jeton, même connectés (l'app filtre). Messages **data-only** à priorité haute
(`android.priority = high`, pas de bloc `notification`) : `data { roomCode, type, title, body }` (toutes les valeurs sont des
chaînes). L'app affiche elle-même la notification locale (canal `turns`) et ignore celles d'un salon qui n'est plus son salon courant.

| `type` | Destinataire | Titre | Corps |
|--------|--------------|-------|-------|
| `turn` | joueur suivant | « C'est ton tour ! » | coup de l'adversaire |
| `move` | autres joueurs encore en jeu (hors auteur) | « {pseudo} a joué » | le coup |
| `resign` | autres joueurs encore en jeu | « {pseudo} a abandonné » | — |
| `eliminated` | joueur éliminé par mat (mode `twoMates`) | « Tu as été éliminé » | le coup |
| `gameOver` | tous les jetons restants | « Partie terminée » | vainqueur / nulle |

Cycle de vie des jetons :
- Un joueur qui abandonne (`resign`/`leave`) ne reçoit **aucune** notification pour cet abandon ; son jeton est supprimé aussitôt.
- Un joueur éliminé par mat reçoit une seule notification `eliminated` (ou `gameOver` si la partie se termine), puis son jeton est supprimé.
- À la fin de la partie, `gameOver` est envoyé à tous, puis tous les jetons sont supprimés.
- Un jeton refusé par FCM (`UNREGISTERED` / HTTP 404) est supprimé du salon.
