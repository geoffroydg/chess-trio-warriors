# Les étapes à faire toi-même

Ce guide liste ce que **toi seul** peux faire : créer les comptes, payer, signer.
Claude ne crée aucun compte et ne tape jamais tes mots de passe ni tes clés.

Temps total : environ 3 à 4 heures, réparties sur plusieurs semaines.

**Règles de sécurité**
- Garde tes mots de passe dans un gestionnaire (celui de ton téléphone suffit).
- Active la double vérification (code par SMS ou appli) partout où c'est proposé.
- Ne colle jamais un mot de passe ou une clé secrète dans une conversation avec Claude.

---

## Étape 1 — Compte Meshy (les modèles 3D)

Quand : quand le prototype te plaît. Durée : 15 minutes.

1. Va sur **meshy.ai** et clique sur « Sign up ».
2. Connecte-toi avec ton compte Google ou ton e-mail.
3. Commence avec la formule **gratuite**. Elle suffit pour essayer.
4. Fais un essai : « Text to 3D », puis écris par exemple :
   *« cartoon runner character, low poly, bright colors »*.
5. Télécharge le résultat au format **GLB**.
6. Mets les fichiers GLB dans le dossier `www/models/` du projet, puis demande à Claude de les brancher dans le jeu.

À savoir :
- Vérifie la **licence** : pour un jeu vendu ou avec pub, il faut le droit d'usage commercial. Sur Meshy, ce droit dépend de la formule. Lis la page « Pricing » avant de publier.
- Il faudra 5 modèles environ : le coureur, une haie, une barre, une caisse, une pièce.

---

## Étape 2 — Compte développeur Google Play (25 $)

Quand : quand le jeu est prêt à être testé par d'autres. Durée : 30 minutes, puis quelques jours d'attente.

1. Va sur **play.google.com/console**.
2. Connecte-toi avec un compte Google. Conseil : crée un compte Google dédié au jeu, séparé de ton compte perso.
3. Choisis le type de compte **« Personnel »** (pas « Organisation » : plus simple).
4. Remplis ton nom, ton adresse, ton téléphone. Ils doivent être exacts.
5. Paie les **25 $** une seule fois (carte bancaire). C'est à vie.
6. Envoie la **pièce d'identité** demandée. Google vérifie en quelques jours.
7. Confirme ton téléphone sur l'appli **Google Play Console** (sur ton smartphone Android).

À savoir :
- Ton nom de développeur sera visible sur la fiche du jeu. Tu peux choisir un nom de studio.
- Une adresse e-mail de contact publique est obligatoire. Une adresse dédiée est mieux.

---

## Étape 3 — 12 testeurs pendant 14 jours (obligatoire)

Pour un compte personnel récent, Google exige un **test fermé** avant la publication publique :
**au moins 12 testeurs**, inscrits **pendant 14 jours d'affilée**.

1. Fais une liste de **15 personnes** (une marge, au cas où certains se désinscrivent) :
   famille, amis, collègues, étudiants volontaires.
2. Chacun doit avoir un **téléphone Android** et un **compte Google** (une adresse Gmail).
3. Récupère leurs adresses Gmail.
4. Dans la Play Console : « Tests » → « Test fermé » → crée une liste de testeurs et colle les adresses.
5. Claude préparera le fichier de l'appli (AAB). Tu l'envoies dans ce test fermé.
6. Envoie aux testeurs le **lien d'inscription** fourni par la Console.
7. Chaque testeur clique sur « Devenir testeur », puis installe le jeu depuis le Play Store.
8. Demande-leur de **rester inscrits 14 jours** et d'ouvrir le jeu de temps en temps.
9. Après 14 jours, la Console te propose de demander l'**accès à la production**. Réponds aux questions (ce que les testeurs ont dit, ce que tu as corrigé).

Message type à envoyer :
> Bonjour ! Je teste un petit jeu de course gratuit. Peux-tu m'aider ?
> 1) Envoie-moi ton adresse Gmail. 2) Clique sur le lien que je t'enverrai. 3) Installe le jeu et garde-le 14 jours. Merci !

---

## Étape 4 — Compte AdMob (les pubs)

Quand : pendant les 14 jours de test, ou juste après. Durée : 30 minutes.

1. Va sur **admob.google.com** avec le **même compte Google** que la Play Console.
2. Accepte les conditions et indique ton pays (France) et ta devise (euro).
3. Ajoute ton appli : « Applications » → « Ajouter » → Android → lie-la à la fiche Play Store.
4. Crée **deux blocs d'annonces**, et seulement ces deux :
   - un bloc **Bannière** (en bas de l'écran) ;
   - un bloc **Avec récompense** (la vidéo « Continuer »).
   Ne crée **pas** de bloc « Interstitiel » : ce sont les pubs plein écran imposées.
5. Note les **identifiants** des blocs (ils ressemblent à `ca-app-pub-1234…/5678…`). Ils ne sont pas secrets : tu peux les donner à Claude pour les brancher.
6. Remplis le **profil de paiement** : RIB (IBAN) et informations fiscales. Fais-le toi-même, directement sur le site AdMob.
7. Configure le **message de consentement** (RGPD), obligatoire en Europe : « Confidentialité et messages » → « RGPD » → crée un message. Claude branchera l'affichage dans le jeu.

À savoir :
- Google paie à partir de **70 €** de gains cumulés.
- Ne clique jamais sur tes propres pubs : Google peut fermer le compte. Pendant les tests, le jeu utilisera des pubs « de test ».

---

## Étape 5 — Pour la fiche Play Store

À préparer pendant le test fermé :

- **Une politique de confidentialité** : une page web obligatoire (le jeu affiche des pubs). Claude peut la rédiger ; tu la publies (par exemple sur Google Sites, gratuit).
- **Le public visé** : choisis **13 ans et plus**. Si tu vises les enfants, les règles sur les pubs sont beaucoup plus strictes.
- **Des captures d'écran** du jeu (Claude peut les produire) et une icône.
- **Le questionnaire de classification** du contenu (PEGI) : quelques questions, 10 minutes.
- **La section « Sécurité des données »** : indique que le jeu utilise AdMob (identifiant publicitaire).

---

## Ce que Claude fera de son côté

- Brancher les modèles Meshy dans le jeu.
- Emballer le jeu en appli Android avec **Capacitor** et produire le fichier AAB.
- Brancher AdMob (bannière + vidéo bonus), d'abord avec des pubs de test.

Une seule chose sensible reste chez toi : la **clé de signature** de l'appli et son mot de passe.
Claude t'expliquera comment la créer ; garde-la en lieu sûr (deux copies), car sans elle, impossible de mettre le jeu à jour.
