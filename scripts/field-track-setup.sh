#!/bin/bash
# ============================================================================
# Field Track — installe la base de démonstration sur un projet Supabase NEUF.
#
#   ./scripts/field-track-setup.sh schema  "<DATABASE_URL>"   # tables, fonctions, règles d'accès
#   ./scripts/field-track-setup.sh comptes                    # 9 comptes fictifs (lit .env)
#   ./scripts/field-track-setup.sh demo    "<DATABASE_URL>"   # 15 PDV, 15 visites, équipes
#   ./scripts/field-track-setup.sh tout    "<DATABASE_URL>"   # les trois, dans l'ordre
#
# DATABASE_URL : Supabase > Project Settings > Database > Connection string (URI).
# ⚠️ Jamais sur la base d'un client : « demo » vide les PDV et les visites.
#    Le script s'arrête s'il trouve un compte hors @fieldtrack.demo.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

ETAPE="${1:-}"
DB_URL="${2:-}"
PSQL="${PSQL:-psql}"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

besoin_db() {
  [ -n "$DB_URL" ] || { echo "❌ DATABASE_URL manquante."; usage; }
  # Garde-fou : une base qui porte déjà des comptes réels n'est pas une base de démonstration.
  local n existe
  existe=$($PSQL "$DB_URL" -qAt -c "select to_regclass('public.profiles') is not null" 2>/dev/null || echo "?")
  if [ "$existe" = "f" ]; then return 0; fi
  n="?"
  if [ "$existe" = "t" ]; then
    n=$($PSQL "$DB_URL" -qAt -c "select count(*) from public.profiles where email not like '%@fieldtrack.demo'" 2>/dev/null || echo "?")
  fi
  if [ "$n" != "0" ]; then
    echo "❌ Arrêt : connexion impossible ou base non vierge ($n compte(s) hors @fieldtrack.demo)."
    exit 1
  fi
}

schema() {
  besoin_db
  local fichiers=(
    supabase/_archive/001_initial_schema.sql
    supabase/field-track/00_prelude.sql
    supabase/_archive/002_seed_data_and_import.sql
    supabase/_archive/007_optimize_dashboard.sql
    supabase/_archive/007_routing_system.sql
    supabase/_archive/009_routing_templates.sql
    supabase/_archive/010_optimize_pdv_indexes.sql
    supabase/_archive/011_rbac_role_section_access.sql
    supabase/_archive/012_sku_thresholds.sql
    supabase/_archive/013_016_perfect_store.sql
    supabase/_archive/017_geofence_radius_200.sql
    supabase/_archive/018_rbac_perfect_store_section.sql
    supabase/_archive/019_security_hardening.sql
    supabase/_archive/022_visibility_and_mt_weights.sql
    supabase/_archive/023_referentiels_admin_canal.sql
    supabase/_archive/CATCHUP_019_023.sql
  )
  # Migrations datées, sauf les trois qui chargent des données du client d'origine.
  for f in supabase/nouveau/2*.sql; do
    case "$f" in
      *20260630140000*|*20260716140000*|*20260911090000*) ;;
      *) fichiers+=("$f") ;;
    esac
  done

  local total=0
  for f in "${fichiers[@]}"; do
    local err
    err=$($PSQL "$DB_URL" -q -f "$f" 2>&1 | grep "ERROR" || true)
    if [ -n "$err" ]; then
      local n; n=$(echo "$err" | wc -l)
      total=$((total + n))
      echo "⚠️  $f : $n erreur(s)"; echo "$err" | head -3 | cut -c1-200
    else
      echo "✅ $f"
    fi
  done
  echo
  echo "Schéma joué. Erreurs : $total."
  echo "Une seule est attendue et sans effet : 20260716200000 (colonne p.quartier),"
  echo "la fonction concernée est recréée par une migration suivante."
  [ "$total" -le 1 ] || { echo "❌ Plus d'erreurs que prévu : lire la liste ci-dessus avant de continuer."; exit 1; }
}

comptes() { node scripts/field-track-create-accounts.mjs; }

demo() {
  besoin_db
  $PSQL "$DB_URL" -q -v ON_ERROR_STOP=1 -f supabase/field-track/90_demo.sql
  $PSQL "$DB_URL" -qAt -c "select 'PDV : ' || (select count(*) from public.pdv) || ' · visites : ' || (select count(*) from public.visites) || ' · comptes : ' || (select count(*) from public.profiles)"
}

case "$ETAPE" in
  schema) schema ;;
  comptes) comptes ;;
  demo) demo ;;
  tout) schema; comptes; demo ;;
  *) usage ;;
esac
