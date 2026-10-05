# Décisions — Music Room

> Journal des choix techniques. Chaque entrée dit ce qui a été choisi, pourquoi, ce qui a
> été écarté et ce que ça implique. Le sujet exige de pouvoir justifier chaque choix.
>
> Statuts : **retenue** (appliquée), **proposée** (à valider avant de coder),
> **ouverte** (question non tranchée).

---

## Organisation

### D01 — Périmètre : 3 services et 4 bonus — retenue

- **Choix** : les trois services (Track Vote, Control Delegation, Playlist Editor) et les
  quatre bonus.
- **Pourquoi** : le sujet n'exige que 2 services sur 3 (V.2), mais le bonus abonnement
  (VI.3) cite le Playlist Editor comme fonction payante.
- **Règle** : les bonus ne sont évalués que si l'obligatoire est parfait (VI). On fige
  l'obligatoire avant le premier bonus.
- **Ordre des bonus** : VI.3 abonnement, VI.1 multi-plateforme, VI.2 iBeacon, VI.4 hors
  ligne en dernier (collision avec le temps réel).

### D02 — Organisation de l'équipe — retenue

- **Choix** : pas de répartition par personne, chacun touche au front et au back.
- **Conséquences** : tranches verticales (base → API → écran), revue croisée obligatoire,
  ce journal, et `docs/IA.md` pour l'usage de l'IA (exigé par le sujet).

---

## Architecture

### D03 — Back-end : Django + DRF + Channels — retenue

- **Choix** : Django, Django REST Framework, Django Channels (ASGI) pour le temps réel,
  documentation OpenAPI générée par `drf-spectacular`.
- **Pourquoi** : ORM et migrations, transactions et verrous de ligne pour la concurrence,
  écosystème mûr pour l'authentification (e-mail, Google, Facebook).
- **Écarté** : Node.js, Go. Pas de défaut bloquant, mais moins d'outillage prêt pour
  l'authentification et l'administration.
- **Conséquences** : serveur ASGI, Redis obligatoire pour le channel layer.

### D04 — Client : React Native avec Expo — retenue

- **Choix** : React Native (Expo), cible Android, `react-native-web` prévu dès le départ.
- **Pourquoi** : le sujet demande une application mobile (IV.2). Prévoir le web dès le
  début rend le bonus VI.1 peu coûteux ; l'ajouter après coup imposerait une réécriture.
- **Écarté** : React web seul (n'est pas une application mobile), React web enveloppé
  (Capacitor, PWA).
- **Conséquences** : un *development build* Expo est requis pour le BLE (bonus iBeacon),
  Expo Go ne le gère pas.

### D05 — Django dans un conteneur — retenue

- **Pourquoi** : un clone doit suffire à tout récupérer (IV.1), et on évite les écarts
  entre Windows et Linux.
- **Conséquences** : PostgreSQL et Redis ne publient aucun port sur l'hôte, seul Django en
  publiera un.

---

## Données et infrastructure

### D06 — PostgreSQL 17 plutôt que SQLite — retenue

- **Pourquoi** : la gestion de la concurrence (votes simultanés, déplacements de pistes)
  repose sur des verrous de ligne (`select_for_update`), que SQLite ne fournit pas
  réellement. Les tests doivent tourner sur le même moteur que la production.
- **Image** : `postgres:17-alpine`.

### D07 — Redis 8.10 — retenue

- **Image** : `redis:8.10-alpine`.
- **Écarté** : Valkey (fork libre de Redis).
- **Pourquoi** : *à compléter par Greg* (licence des versions récentes de Redis,
  compatibilité avec `channels_redis`).

### D08 — Redis sans persistance, `noeviction` — retenue

- **Pas de volume** : le channel layer ne transporte que des messages éphémères. Si Redis
  redémarre, les clients se reconnectent. La vérité est dans PostgreSQL (V.3).
- **`--maxmemory 128mb --maxmemory-policy noeviction`** : mémoire pleine = écritures en
  erreur visible, plutôt que des clés jetées en silence et des messages temps réel perdus
  sans trace.

### D09 — Réseaux séparés — retenue

- `net_database` : PostgreSQL. `net_cache` : Redis. Seul Django sera branché sur les deux.
- Pas de `name:` sur les réseaux : compose les préfixe avec le nom du projet, ce qui évite
  les collisions avec d'autres projets de la machine.

---

## Sécurité

### D10 — Secrets Docker pour les mots de passe — retenue

- **Choix** : les mots de passe vivent dans `secrets/` (ignoré par git), montés dans
  `/run/secrets/<nom>`. `.env` ne garde que la configuration non secrète.
- **Pourquoi** : une variable d'environnement apparaît en clair dans `docker inspect`. Un
  secret n'y montre que son chemin. Vérifié : 0 occurrence des mots de passe dans
  `docker inspect` (05/10/2026).
- **Limite, à assumer en soutenance** : hors Swarm, un secret compose est un fichier monté
  non chiffré. Il protège contre l'affichage accidentel, pas contre quelqu'un qui a déjà
  accès à Docker (équivalent root).
- **PostgreSQL** : `POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password`. Le mot de passe
  n'est lu qu'à la première initialisation du volume : changer le secret impose un
  `docker compose down -v` (perte des données).
- **Redis** : l'image ne lit pas de mot de passe depuis un fichier. Lancement par
  `sh -c "exec docker-entrypoint.sh redis-server --requirepass \"$(cat …)\" …"`.
  Rappeler `docker-entrypoint.sh` garde le passage à l'utilisateur `redis` (sinon Redis
  tournerait en root) et le chargement des modules ; `exec` lui transmet les signaux
  d'arrêt.
- **Healthcheck Redis** : `REDISCLI_AUTH` défini pour la seule commande, depuis le fichier,
  et `grep -q PONG` car `redis-cli` peut sortir en 0 sur une erreur.
- **Génération** : `make secrets` crée des valeurs aléatoires (32 octets de
  `/dev/urandom` en hexadécimal) et ne doit jamais écraser un secret existant.
- **Alternative plus poussée** : fichier ACL Redis avec mot de passe haché (SHA-256).

### D11 — Clé secrète Django — retenue

- Signe les sessions, les jetons de réinitialisation et de validation d'e-mail, le CSRF,
  et les JWT si on en utilise. Une fuite permet d'usurper n'importe quel compte (V.6).
- Longue, aléatoire, différente par environnement, jamais versionnée.
  Rotation : `SECRET_KEY_FALLBACKS`.

### D12 — Fins de ligne LF imposées — retenue

- `.gitattributes` force LF sur le dépôt et sur le disque, quel que soit `core.autocrlf`.
- **Pourquoi** : `docker build` copie les fichiers du disque. Un script en CRLF casse dans
  un conteneur Linux.

---

## Musique

### D13 — Jamendo comme fournisseur par défaut — retenue

- **Pourquoi** : titres complets sans compte premium, `client_id` seul pour lire le
  catalogue, 35 000 requêtes par mois en non commercial. La démo ne dépend d'aucun
  abonnement.
- **Écarté** :
  - Spotify en principal : depuis février 2026, le mode développeur exige un compte
    Premium et limite à 5 utilisateurs de test.
  - Deezer : l'API publique ne donne que des extraits de 30 s.
  - YouTube : lecture par WebView, publicités, CGU contraignantes.
- **Conséquence** : une interface « fournisseur de musique » côté Django (chercher,
  récupérer un titre, obtenir l'URL de lecture) qui renvoie une forme normalisée.
  Spotify pourra s'y brancher en second fournisseur.
- **SDK** : le sujet interdit qu'il fasse le travail à notre place (III). Jamendo ne fournit
  que le catalogue et l'audio ; vote, playlists, droits et délégation sont à nous.

### D14 — Ce qu'on stocke d'un titre — proposée

- **Stocker** : identifiant externe (chaîne, unique avec le nom du fournisseur), titre,
  artiste, album, durée (secondes), pochette.
- **Ne pas stocker** : l'URL audio. Observé le 04/10/2026 : son jeton `from=…` change à
  chaque requête. `get_stream_url` la redemande à l'API au moment de jouer.
- **Ne pas stocker** : `waveform` (volumineux, inutile à la vérité du back-end).
- **Conséquence** : prévoir un état « titre indisponible » si Jamendo retire un titre.
- **Mesures** (04/10/2026, titre 2277995) : `200`, `audio/mpeg`, pas de redirection,
  `Accept-Ranges: bytes` (avance rapide possible), environ 97 kbit/s.
- **Ouvert** : durée de validité de l'URL audio, à mesurer en relançant la même URL après
  plusieurs heures.

### D15 — Licences des titres — ouverte

- Observé : `license_ccurl` vide sur les anciens titres, renseigné sur les récents
  (exemple : CC BY-NC-ND 3.0).
- **BY** : afficher titre, artiste et lien sur chaque piste jouée.
- **NC** : compatible avec un projet d'école. En conflit avec un vrai abonnement payant
  (bonus VI.3) : à expliquer en soutenance, ou à régler en filtrant les licences.
- **ND** : lecture telle quelle, pas de remix ni de fondu enchaîné.
- **Proposé** : un titre sans licence renseignée est inconnu, pas libre, et filtré par
  défaut.

---

## Concurrence

### D16 — Votes et ordre des playlists — proposée

- **Votes** : idempotents (un identifiant d'opération par vote), dans une transaction avec
  verrou de ligne.
- **Ordre des pistes** : ordre fractionnaire, pour que deux déplacements simultanés ne se
  marchent pas dessus.
- **Tests** : opérations simultanées sur un vrai PostgreSQL (pytest-django en mode
  transaction), sinon on ne prouve pas que les verrous fonctionnent.

---

## Observabilité et tests

### D17 — Observabilité dans le dépôt, désactivable — retenue

- Voir `docs/OBSERVABILITE-ET-TESTS.md`.
- **Obligatoire** : logs JSON de chaque action avec plateforme, appareil et version de
  l'application (V.6), mesure de charge (V.7), tests par couche (V.8).
- **En plus** : OpenTelemetry, Tempo, Loki, Prometheus, Grafana, Alertmanager, dans un
  profil compose séparé. L'obligatoire n'en dépend jamais ; OTel se coupe par variable
  d'environnement.
- **Garde-fous** :
  - le test de charge vise un faux fournisseur, jamais Jamendo (quota de 35 000
    requêtes par mois) ;
  - aucune donnée sensible dans les logs (mots de passe, jetons, e-mails, champs privés
    du profil) ;
  - jamais d'identifiant d'utilisateur ou de piste en étiquette de métrique ;
  - la capacité se mesure sur une vraie machine dont on donne les caractéristiques.
- **Ouvert** : ce que « toute action » veut dire en V.6 (seulement les appels API, ou
  aussi des événements envoyés par l'application).
