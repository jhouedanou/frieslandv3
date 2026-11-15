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

Les clés techniques (`br_160g`, `maison_br`, `fc-red`…) ne changent pas : le calcul
Perfect Store et les données enregistrées en dépendent.

Pour changer encore de marque : remplacer `resources/logo.svg` et
`resources/glyphe.svg`, puis `node scripts/generate-brand-assets.mjs`.
La couleur se règle dans `tailwind.config.ts` et `assets/css/main.css`.

## Données de démonstration

- **15 points de vente** fictifs à Abidjan (Cocody 1, Marcory, Plateau, Treichville, Yopougon 1).
- **15 visites**, une par point de vente : 3 Flagship, 3 VIP, 4 Core, 5 sous le niveau Core.
- **9 comptes**, tous en `@fieldtrack.demo` :

| Rôle | E-mail | Territoires | Encadre |
|---|---|---|---|
| admin | `admin@fieldtrack.demo` | tous | — |
| commercial | `commercial1@fieldtrack.demo` | Cocody 1, Plateau | merchandisers 1 et 2 |
| commercial | `commercial2@fieldtrack.demo` | Marcory, Treichville | merchandisers 3 et 4 |
| commercial | `commercial3@fieldtrack.demo` | Yopougon 1 | merchandiser 5 |
| merchandiser | `merchandiser1@fieldtrack.demo` | Cocody 1 | |
| merchandiser | `merchandiser2@fieldtrack.demo` | Plateau | |
| merchandiser | `merchandiser3@fieldtrack.demo` | Marcory | |
| merchandiser | `merchandiser4@fieldtrack.demo` | Treichville | |
| merchandiser | `merchandiser5@fieldtrack.demo` | Yopougon 1 | |

Le mot de passe commun est celui que vous mettez dans `FIELD_TRACK_DEMO_PASSWORD`.
Distributeurs et marques concurrentes sont rebaptisés (`Distributeur 07`, `Concurrent A`).

## Installer la base (projet Supabase neuf)

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
  rejoue sans doublon, les scores Perfect Store sont calculés.
- Vérifié : `pnpm vitest run` (147 tests) et `pnpm build`.
- **Non vérifié** : l'installation sur un vrai projet Supabase et la création des
  comptes par `scripts/field-track-create-accounts.mjs` (aucune base Field Track
  n'était accessible).

## Android

- L'identifiant a changé : c'est une **nouvelle application** pour Google Play.
- Notifications : il faut un `android/app/google-services.json` Firebase pour
  `com.fieldtrack.app` (l'ancien fichier ne convient plus).
- Signature : prévoir un keystore propre à Field Track (`android/keystore.properties`).
