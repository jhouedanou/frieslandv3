# Field Track — version marque blanche

Cette branche (`claude/field-track-white-label-q2fvlf`) porte la même application,
avec les mêmes fonctions, sous le nom **Field Track** et avec des données fictives.
La branche `main` reste la version du client d'origine.

## Ce qui change par rapport à `main`

| Sujet | Avant | Field Track |
|---|---|---|
| Nom affiché (web, PWA, Android) | nom du client | Field Track |
| Identifiant Android | `com.bdco.bonnetrouge` | `com.fieldtrack.app` |
| Couleur principale | rouge `#C8102E` | bleu `#1D4ED8` |
| Logo, icônes, écran de démarrage | logo du client | repère bleu (`resources/logo.svg`) |
| Libellés produits | `BR`, `BRB`, `Pearl`, `Yogoo` | `FT`, `FTB`, `Opale`, `Yaourt` |
| Mot de passe provisoire | `BR-xxxx-xxxx` | `FT-xxxx-xxxx` |
| « Perfect Store » | concept du client | « conformité » (PDV conformes, niveau de conformité) |
| « Field coaching » | concept du client | « accompagnement terrain » |
| Catégories de produits | `EVAP`, `IMP`, `SCM`, `UHT`… | `Gamme A` à `Gamme F` |
| Marques concurrentes | noms réels | `Concurrent A`, `Concurrent B`… |
| Découpage territorial | régions, territoires et quartiers du client | 2 régions, 6 territoires génériques, 3 quartiers chacun |

Seul l'affichage change. Les clés techniques (`br_160g`, `evap`, `maison_br`,
`perfect_store`, `field_coaching`, `fc-red`, les adresses `/admin/perfect-store`…)
restent : les calculs et les données enregistrées en dépendent. Les niveaux
s'affichent `Flagship`, `VIP`, `Core`, `Basic`.

Pour changer encore de marque : remplacer `resources/logo.svg` et
`resources/glyphe.svg`, puis `node scripts/generate-brand-assets.mjs`.
La couleur se règle dans `tailwind.config.ts` et `assets/css/main.css`.

## Deux façons de lancer Field Track

| | Mode démo | Mode Supabase |
|---|---|---|
| Base de données | embarquée dans le navigateur ou le téléphone | projet Supabase dédié |
| Installation | aucune | voir « Installer la base » plus bas |
| Données partagées entre appareils | non | oui |
| Usage | démonstration commerciale | usage réel à plusieurs |

## Mode démo (sans Supabase)

L'application tourne seule, admin et mobile. La base est un vrai PostgreSQL
compilé pour le navigateur (PGlite) : mêmes tables, mêmes calculs de conformité,
mêmes droits par rôle que la version Supabase. Les écrans ne changent pas.

```bash
pnpm dev:demo              # essai en local
pnpm generate:demo         # site statique dans .output/public
pnpm android:apk:demo      # APK de démonstration
```

- **Connexion** : l'écran de connexion liste les 9 comptes fictifs, un clic suffit.
  Mot de passe commun : `fieldtrack`.
- **Données** : les 15 PDV et 15 visites sont chargés au premier lancement, puis
  les saisies restent sur l'appareil. Les dates des visites sont recalées sur le
  jour du premier lancement.
- **Remise à zéro** : lien « Remettre les données de démonstration à zéro » sur
  l'écran de connexion.
- **Hébergement web** : dossier `.output/public`, sur un hébergeur statique avec
  repli vers `200.html` pour les adresses inconnues.
- **Vercel** : `vercel.json` règle tout sur cette branche (build en mode démo,
  dossier de sortie, repli des adresses). Aucune variable d'environnement à
  saisir. Ce fichier n'existe pas sur `main`, qui garde son build habituel.

Limites du mode démo :

- Une saisie faite sur un téléphone n'apparaît pas sur un autre appareil.
- Les photos sont gardées dans la base de l'appareil, pas sur un serveur.
- Pas de notifications push, pas de mise à jour en temps réel entre comptes.
- Premier lancement : 3 à 4 secondes (ouverture de la base, environ 15 Mo à télécharger).
- Aucune tournée n'est préparée : l'écran Routing est vide tant qu'on n'en crée pas.

Fichiers du mode démo : dossier `demo/`.

| Fichier | Rôle |
|---|---|
| `demo/seed.sql` | schéma et données, fabriqué par `scripts/field-track-build-demo-seed.sh` |
| `demo/db.ts` | ouvre la base embarquée et charge les données |
| `demo/postgrest.ts` | traduit les requêtes de l'application en SQL |
| `demo/client.ts` | faux client Supabase (lectures, écritures, connexion, photos) |
| `demo/api.ts` | routes d'administration, rejouées dans le navigateur |
| `demo/comptes.ts` | comptes fictifs et mot de passe |

Pour changer les données de démonstration : modifier `supabase/field-track/90_demo.sql`,
rejouer `scripts/field-track-setup.sh` sur une base de travail, puis
`scripts/field-track-build-demo-seed.sh "<DATABASE_URL>"`.

## Données de démonstration

- **15 points de vente** fictifs, répartis sur 5 territoires génériques (Est, Centre, Sud, Lagune, Ouest). Sur la carte, ils sont placés à Abidjan.
- **15 visites**, une par point de vente : 3 Flagship, 3 VIP, 4 Core, 5 non conformes.
- **9 comptes**, tous en `@fieldtrack.demo` :

| Rôle | E-mail | Territoires | Encadre |
|---|---|---|---|
| admin | `admin@fieldtrack.demo` | tous | — |
| commercial | `commercial1@fieldtrack.demo` | Territoires Est et Centre | merchandisers 1 et 2 |
| commercial | `commercial2@fieldtrack.demo` | Territoires Sud et Lagune | merchandisers 3 et 4 |
| commercial | `commercial3@fieldtrack.demo` | Territoire Ouest | merchandiser 5 |
| merchandiser | `merchandiser1@fieldtrack.demo` | Territoire Est | |
| merchandiser | `merchandiser2@fieldtrack.demo` | Territoire Centre | |
| merchandiser | `merchandiser3@fieldtrack.demo` | Territoire Sud | |
| merchandiser | `merchandiser4@fieldtrack.demo` | Territoire Lagune | |
| merchandiser | `merchandiser5@fieldtrack.demo` | Territoire Ouest | |

Le mot de passe commun est celui que vous mettez dans `FIELD_TRACK_DEMO_PASSWORD`.
Distributeurs et marques concurrentes sont rebaptisés (`Distributeur 07`, `Concurrent A`).

## Mode Supabase : installer la base (projet neuf)

Field Track a besoin de **sa propre base**. Ne jamais utiliser celle d'un client :
l'étape `demo` vide les points de vente et les visites. Le script s'arrête s'il
trouve un compte hors `@fieldtrack.demo`.

1. Créer (ou réactiver) un projet Supabase dédié.
2. Remplir `.env` avec les valeurs de **ce** projet :

   ```
   SUPABASE_URL=https://<ref>.supabase.co
   SUPABASE_KEY=<clé publique>
   SUPABASE_SERVICE_ROLE_KEY=<clé service>
   FIELD_TRACK_DEMO_PASSWORD=<12 caractères au moins>
   ```

3. Lancer :

   ```bash
   ./scripts/field-track-setup.sh tout "<DATABASE_URL>"
   ```

   `DATABASE_URL` : Supabase → Project Settings → Database → Connection string (URI).
   Les trois étapes se lancent aussi une par une : `schema`, `comptes`, `demo`.

4. Dans Supabase → Storage, vérifier que le bucket `visite-images` existe (photos).

Une erreur est attendue pendant `schema` (migration `20260716200000`) : elle est
sans effet, la fonction est recréée juste après.

## Ce qui a été vérifié, et ce qui ne l'a pas été

- Vérifié sur un PostgreSQL 16 local : le schéma se construit de zéro, toutes les
  tables et fonctions appelées par l'application existent, la démo se charge et se
  rejoue sans doublon, les scores de conformité sont calculés.
- Vérifié : `pnpm vitest run` (160 tests, dont 13 sur le mode démo) et `pnpm build`.
- Vérifié en mode démo, dans un navigateur : connexion, les 41 écrans admin et les
  écrans mobiles (merchandiser et commercial) s'ouvrent sans erreur ; la version
  native (`CAPACITOR_BUILD=1`) se génère.
- **Non vérifié** en mode démo : l'APK sur un vrai téléphone, et la saisie
  complète d'une visite à la main (l'enregistrement est couvert par les tests).
- **Non vérifié** : l'installation sur un vrai projet Supabase et la création des
  comptes par `scripts/field-track-create-accounts.mjs` (aucune base Field Track
  n'était accessible).

## Android

- L'identifiant a changé : c'est une **nouvelle application** pour Google Play.
- Notifications : il faut un `android/app/google-services.json` Firebase pour
  `com.fieldtrack.app` (l'ancien fichier ne convient plus).
- Signature : prévoir un keystore propre à Field Track (`android/keystore.properties`).
