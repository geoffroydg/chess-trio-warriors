# Chess Trio Warriors
Jeu d'échecs à 3 joueurs en ligne (Android), thème guerriers d'énergie façon anime (100 % original, aucun nom/visuel/son de franchise existante).

- `engine/` : moteur de règles TypeScript, sans dépendance, source de vérité (utilisé par le serveur). Tests : `cd engine && npm test`.
- `server/` : Cloudflare Worker + Durable Object par salon (WebSocket, minuteur 60 s, coup aléatoire, notifications FCM).
- `app/` : application Flutter + Flame (vue 2D inclinée), le client reçoit l'état et les coups légaux du serveur.
- `docs/RULES.md` : règles officielles du jeu.
Langue de l'UI et des voix : français. Hooks `.claude/hooks/check.sh` : les tests doivent passer avant de finir une tâche.
