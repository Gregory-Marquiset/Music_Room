# Observabilité et tests — Music Room

> Document de cadrage. Écrit le 05/10/2026.
> À lire avant de toucher à l'observabilité ou à la chaîne de tests.

## Pourquoi ce document

Music Room sert donc de **banc d'entraînement** pour construire une observabilité par raport a La Suite numérique de la DINUM. La forme du projet s'y
prête bien:

| Mission DINUM | Équivalent Music Room |
|---|---|
| Applications Django | Django + DRF |
| LiveKit (temps réel, sessions longues) | Channels / WebSocket |
| Redis | Redis du channel layer |
| Bases SQL | PostgreSQL |
| Clients | Application React Native |
| Dépendances externes | API Jamendo |

## Trois périmètres à ne pas confondre

**Obligatoire, exigé par le sujet :**

- **Les tests** — section V.8, « des tests spécifiques pour chaque couche ».
- **Les logs applicatifs** — section V.6 : *« toute action sur l'application mobile doit
  générer des logs sur le back-end »*, avec **plateforme, appareil et version de
  l'application**. C'est du log structuré, et il alimente directement Loki.
- **La mesure de charge** — section V.7 : il faut *« évaluer, justifier et mesurer le
  nombre d'utilisateurs simultanés »* que l'API supporte, et préciser les caractéristiques
  du serveur. Le sujet cite AB, Gatling, Siege, Tsung, JMeter ; **k6 fait le même travail**
  et c'est l'outil de La Suite.

**Entraînement personnel, hors sujet :** la pile complète OTel, Tempo, Grafana,
Alertmanager, les SLO.

**Autrement dit :** les logs structurés et le test de charge sont à faire de toute façon.
Les monter proprement dès le départ coûte à peine plus cher et sert deux fois.

## Les outils à utiliser

### Observabilité

| Outil | Rôle | Paquet ou image |
|---|---|---|
| OpenTelemetry Collector | Carrefour unique : reçoit, filtre, redistribue | `otel/opentelemetry-collector-contrib` |
| OTel Python | Instrumente Django, PostgreSQL, Redis, les appels sortants | `opentelemetry-distro`, `opentelemetry-exporter-otlp`, puis `opentelemetry-bootstrap -a install` |
| OTel JS | Traces côté client mobile | `@opentelemetry/api`, `@opentelemetry/sdk-trace-web`, exporter OTLP HTTP |
| Tempo | Stockage des traces | `grafana/tempo` |
| Loki | Stockage des logs | `grafana/loki` |
| Prometheus | Base de séries temporelles, évalue les règles d'alerte | `prom/prometheus` |
| Grafana | Affichage, et sauts métrique ↔ trace ↔ log | `grafana/grafana` |
| Alertmanager | Regroupe, déduplique, route, gère les silences | `prom/alertmanager` |
| django-prometheus | Expose `/metrics` côté Django, comme La Suite | `django-prometheus` (pip) |
| Sentry | Erreurs applicatives | `sentry-sdk` (pip), `@sentry/react-native` (mobile) |
| redis_exporter | Métriques du channel layer | `oliver006/redis_exporter` |
| postgres_exporter | Métriques de la base | `prometheuscommunity/postgres-exporter` |

### Tests

| Besoin | Outil | Paquet |
|---|---|---|
| Unitaire et intégration back | pytest | `pytest`, `pytest-django`, `pytest-cov`, `pytest-xdist` |
| Fixtures back | factory_boy | `factory_boy` |
| Simulation des API externes (Jamendo) | responses | `responses` |
| Unitaire front mobile | Jest (preset Expo) | `jest-expo`, `@testing-library/react-native` |
| Unitaire front web | Vitest | `vitest`, `@testing-library/react` |
| Bout en bout mobile | Maestro | binaire `maestro` (ou Detox si besoin de plus de contrôle) |
| Bout en bout web | Playwright | `@playwright/test` |
| Charge | k6 | `grafana/k6` |

**Attention aux transpositions hâtives.** La Suite utilise Vitest et Playwright, mais leurs
fronts sont des applications web Next.js. Sur du React Native :

- **Jest avec le preset `jest-expo` est le standard**, pas Vitest. Vitest ne devient
  pertinent que sur la variante `react-native-web`.
- **Playwright pilote des navigateurs**, donc il ne teste pas une application mobile.
  Pour le bout en bout mobile, c'est **Maestro** (simple, bien intégré à Expo) ou Detox.
  Playwright reste le bon choix si le bonus web responsive est fait.

## Ce que La Suite utilise réellement

Vérifié le 05/10/2026 en lisant les dépôts publics `suitenumerique/hub`,
`suitenumerique/meet`, `suitenumerique/docs` et `suitenumerique/messages`.

**Point important : la pile OpenTelemetry → Loki → Tempo décrite dans la mission n'est PAS
leur pile actuelle. C'est la cible que le stage doit construire.** Aujourd'hui ils ont :

- **Sentry** (`sentry-sdk`) pour les erreurs applicatives, dans `hub` comme dans `meet`
- **django-prometheus** exposant `/metrics`, délibérément hors de `/api/`, protégé par un
  jeton bearer et désactivé par défaut (`PROMETHEUS_METRICS_ENABLED`, `PROMETHEUS_API_KEY`)
- **Prometheus et Grafana** déployés par Helm avec l'opérateur Prometheus, plus Tilt pour
  le cluster de développement local
- **Tableaux de bord Grafana versionnés en JSON** dans le dépôt
- **k6** pour les tests de charge, avec écriture directe dans Prometheus en remote write

OpenTelemetry n'existe chez eux qu'à la marge : dépendance transitive dans `docs`, service
`summary` de `meet`, et traçage LLM dans `conversations`.

### Le dépôt de référence

**`suitenumerique/docs`** est leur implémentation la plus avancée. À lire avant de
commencer :

- `documentation/metrics.md`
- `documentation/load-testing.md`
- `src/helm/env.d/dev/values.prometheus.yaml.gotmpl`
- `src/loadtest/dashboards/`
- `bin/Tiltfile`

## La pile retenue pour Music Room

Deux couches, et les deux ont une raison d'être.

### Couche 1 — leur pile actuelle

Pour parler la même langue que l'équipe dès le premier jour du stage.

- `django-prometheus` sur le backend, `/metrics` protégé par jeton, comme chez eux
- `sentry-sdk` pour les erreurs
- `redis_exporter` et `postgres_exporter`
- Prometheus + Grafana
- `k6` pour le test de charge

### Couche 2 — la cible du stage

Pour arriver avec de l'avance sur ce qu'il faudra construire.

- **OpenTelemetry Collector** en point d'entrée unique
- `opentelemetry-distro`, `opentelemetry-exporter-otlp`, et les instrumentations
  `django`, `psycopg`, `redis`, `requests`
- **Tempo** pour les traces, **Loki** pour les logs
- Grafana devant l'ensemble, avec les sauts trace ↔ logs ↔ métriques

### Comment ça circule

Deux chemins, et c'est la source de confusion la plus fréquente :

- **Push** — les applications instrumentées OTel *envoient* en OTLP au Collector
- **Pull** — `redis_exporter` et `postgres_exporter` exposent une page `/metrics` et
  attendent qu'on vienne la lire

Attention au piège de vocabulaire : un **exporter Prometheus** est un programme qui expose
`/metrics` ; un **exporter du Collector** est son étage de sortie. Rien à voir.

```
  React Native ──────OTLP──┐
  Django + Channels ───────┼──push──►  OTel Collector ──►  Tempo  (traces)
                           │                            ──►  Loki   (logs)
  redis_exporter ─┐        │                            ──►  Prometheus
  postgres_exporter┘──/metrics──┘                              (métriques)
      (lus en pull)                                               │
                                                                  ▼
                                            Grafana  ◄── Tempo, Loki, Prometheus

  Prometheus ──évalue les règles──►  Alertmanager ──►  notifications
```

Prometheus **évalue** les règles d'alerte. Alertmanager ne fait que regrouper, dédupliquer,
router et gérer les silences.

## Ce qu'il faut instrumenter

### Les trois signaux, sur une requête de vote

- **Métrique** : « la latence du vote est passée à 2 s » → *qu'il y a* un problème
- **Trace** : « 1,8 s passée dans l'appel Jamendo » → *où*
- **Log** : « Jamendo a renvoyé 429 » → *quoi*

Les trois reliés par le même `trace_id`. C'est tout l'objet de la mission.

### Métriques propres à Music Room

**WebSocket** — connexions actives, durée de vie, messages par seconde, **taux de
reconnexion** (meilleur indicateur de santé d'un temps réel).

**Service de vote** — votes par seconde, et surtout la **latence entre un vote et sa
réception par tous les clients**. C'est la métrique produit.

**Redis (channel layer)** — `evicted_keys`, ratio hits/misses, latence des commandes,
mémoire. Les évictions sont le signal précoce : Redis jette des clés, le temps réel perd
des messages, et aucune erreur n'apparaît.

**PostgreSQL** — connexions actives contre `max_connections`, verrous en attente, requêtes
lentes.

**Jamendo** — latence, taux d'erreur, quota restant. Dépendance externe non maîtrisée :
c'est un sujet à part entière, et l'offre DINUM insiste dessus.

### Grilles de lecture

- **RED** (Rate, Errors, Duration) pour tout ce qui sert des requêtes
- **USE** (Utilization, Saturation, Errors) pour les ressources

## Le point dur : la corrélation

C'est 80 % de la valeur de l'exercice. Le reste est de la plomberie.

**Propagation.** Standard W3C Trace Context, en-tête `traceparent`. Le client React Native
le génère, Django le reçoit et le transmet à PostgreSQL, Redis et Jamendo.

**Logs.** En **JSON structuré**, avec le `trace_id` injecté dans chaque enregistrement,
sinon Loki ne peut rien corréler. L'instrumentation Python sait le faire — vérifier le
réglage exact dans la documentation, il a changé entre versions.

**Channels — la vraie difficulté.** Une connexion WebSocket vit plusieurs minutes et
transporte des dizaines de messages. Il faut trancher :

> Une trace par connexion, ou une trace par message avec un lien vers la connexion ?

**Réponse retenue : une trace par message**, avec un lien vers la connexion. Une trace de
dix minutes est illisible. C'est exactement le même problème que les sessions LiveKit, et
c'est un arbitrage à savoir défendre à l'oral.

## SLO et alertes

**Deux ou trois SLO, pas plus.** Par exemple : 99 % des requêtes API sous 300 ms, 99,5 %
des votes propagés sous 1 s, 99,9 % de disponibilité. Calculer le **budget d'erreur** et
afficher sa consommation.

**Alerter sur les symptômes, pas sur les causes.** Jamais « le CPU est à 90 % », mais « les
utilisateurs attendent plus d'une seconde ». La cause se cherche ensuite, dans les traces.

Cinq alertes suffisent : budget d'erreur consommé trop vite, taux d'erreur HTTP, saturation
du pool PostgreSQL, évictions Redis, et **absence de métriques** — une application morte ne
déclenche rien si ce cas n'est pas prévu.

## Les tests

Alignés sur la pile exacte de La Suite. Même effort, double bénéfice : exigence du sujet 42
et préparation au stage.

### Back-end Django

`pytest`, `pytest-django`, `pytest-cov`, `pytest-xdist` (parallélisme), `factory_boy`
(fixtures), `responses` (simulation des API externes, donc Jamendo).

### Front React Native

**Jest avec le preset `jest-expo`** et `@testing-library/react-native`. C'est le standard
de l'écosystème Expo.

La Suite utilise Vitest, mais sur des fronts web Next.js : la transposition directe ne
tient pas ici. Vitest redevient le bon choix si le bonus `react-native-web` est réalisé.

### Bout en bout

**Maestro** pour le mobile — simple, déclaratif, bien intégré à Expo. Detox si un contrôle
plus fin devient nécessaire.

**Playwright** uniquement pour la variante web, si le bonus responsive est fait. C'est leur
outil : chez `hub`, la CI le lance sur **trois navigateurs en matrice** — chromium, firefox,
webkit.

### Charge

**k6**, avec écriture dans Prometheus en remote write.

**Méthode à appliquer** : monter en charge jusqu'à ce que la latence décroche, noter le
nombre de connexions WebSocket simultanées tenues, puis **fixer les seuils d'alerte à
partir de cette mesure**, pas au jugé. C'est littéralement la méthode de la mission
(« mesurer la vraie capacité avant de fixer les seuils »).

## Tout en code

Exigence explicite de la mission : « dashboards et alertes versionnés en code pour rester
reproductibles ».

- Tableaux de bord Grafana : fichiers JSON provisionnés
- Règles d'alerte : fichiers YAML
- Pile entière : `compose.yml` ou chart Helm
- Rien qui n'existe que dans l'interface web

**Test de validation** : tout détruire, tout relancer, retrouver l'identique.

## Ordre de mise en œuvre

Ne pas tout monter d'un coup.

1. **Collector + Tempo + Grafana**, Django instrumenté → voir une première trace
2. **Loki**, logs JSON avec `trace_id`, saut trace ↔ logs dans Grafana
3. **Le problème Channels**, tranché et justifié par écrit
4. **django-prometheus**, `redis_exporter`, `postgres_exporter`, Prometheus
5. **Sentry**
6. **SLO et budget d'erreur**
7. **k6**, puis les seuils déduits de la mesure
8. **Alertmanager** en dernier — alerter sur un système qu'on ne sait pas lire ne sert à rien

L'étape 2 est celle qui apprend le plus, et celle que la plupart des gens sautent.

## Règles de travail sur ce projet

- **Claude ne code pas ici.** Il guide, explique les compromis, relit. Greg écrit.
  Le sujet impose de pouvoir défendre chaque décision à l'oral.
- **Aucun secret commité.** `.env` est dans `.gitignore`. Un secret dans l'historique = échec.
- **Chaque choix technique se justifie** et se consigne dans `docs/DECISIONS.md`.
- **L'usage de l'IA se documente** dans `docs/IA.md`, le sujet l'exige.
- L'observabilité reste **hors périmètre d'équipe** tant que l'obligatoire n'est pas figé.

## Références

- Sujet : `Downloads/en.subject (1).pdf` (Music Room v6)
- Dépôts : `github.com/suitenumerique/{docs,hub,meet,messages}`
- Décisions produit du projet : `docs/DECISIONS.md`
