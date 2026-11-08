# Serveur de salons (Cloudflare Workers)

Worker + Durable Object `Room` (un salon = un objet), WebSocket, minuteur 60 s, notifications FCM.
Protocole : `docs/PROTOCOL.md`. Offre gratuite Cloudflare suffisante, sans carte bancaire.

## Déploiement (sans terminal, via GitHub Actions)

1. Crée un compte gratuit sur <https://dash.cloudflare.com/sign-up>. Dans *Workers & Pages*, choisis un nom de
   sous-domaine `workers.dev` si Cloudflare le demande.
2. Crée un jeton API : *My Profile > API Tokens > Create Token > modèle « Edit Cloudflare Workers »*.
   Note aussi ton **Account ID** (page *Workers & Pages*, colonne de droite).
3. Sur GitHub : *Settings > Secrets and variables > Actions > New repository secret*. Ajoute :
   - `CLOUDFLARE_API_TOKEN` : le jeton ;
   - `CLOUDFLARE_ACCOUNT_ID` : l'identifiant du compte ;
   - `FCM_SERVICE_ACCOUNT` (optionnel, pour les notifications) : le contenu complet du fichier JSON du compte de
     service Firebase (*Console Firebase > Paramètres du projet > Comptes de service > Générer une clé*).
4. Pousse sur `main` (ou *Actions > Serveur > Run workflow*) : le workflow `.github/workflows/server.yml` lance les
   tests puis déploie. L'URL du worker (`https://chess-trio-warriors.<ton-sous-domaine>.workers.dev`) s'affiche dans
   le résumé du job. Test : ouvre `<URL>/health`.

Sans `CLOUDFLARE_API_TOKEN`, seuls les tests tournent. Sans `FCM_SERVICE_ACCOUNT`, les notifications sont désactivées.

## Avec un terminal (optionnel)

```
cd server && npm install
npx wrangler login
npx wrangler deploy
npx wrangler secret put FCM_SERVICE_ACCOUNT   # coller le JSON
```

## Développement

`npm test` (logique pure `src/room-logic.ts`), `npm run typecheck`, `npm run dev` (wrangler en local).
