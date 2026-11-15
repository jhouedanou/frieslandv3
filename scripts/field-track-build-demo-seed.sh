#!/bin/bash
# ============================================================================
# Field Track — fabrique demo/seed.sql, la base embarquée du mode démo.
#
#   ./scripts/field-track-build-demo-seed.sh "<DATABASE_URL>"
#
# DATABASE_URL : une base Field Track déjà installée par
# scripts/field-track-setup.sh (schéma + comptes + démo). Le fichier produit
# contient le schéma public, les statistiques et les données de démonstration.
# Il ne contient aucun mot de passe : le mode démo a les siens (demo/comptes.ts).
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
DB_URL="${1:?DATABASE_URL manquante}"
PG_DUMP="${PG_DUMP:-pg_dump}"
PSQL="${PSQL:-psql}"
SORTIE=demo/seed.sql

autres=$($PSQL "$DB_URL" -qAt -c "select count(*) from public.profiles where email not like '%@fieldtrack.demo'")
[ "$autres" = "0" ] || { echo "❌ Arrêt : $autres compte(s) hors @fieldtrack.demo, ce n'est pas la base de démonstration."; exit 1; }

nettoyer() { grep -v -E '^(\\|SET |SELECT pg_catalog\.set_config|CREATE SCHEMA public;|--|$)' ; }

{
  echo "-- Field Track — base embarquée du mode démo. Fichier généré par"
  echo "-- scripts/field-track-build-demo-seed.sh : ne pas le modifier à la main."
  echo "-- Date de référence des visites : $(date -u +%F)"
  echo "create extension if not exists pgcrypto with schema public;"
  cat demo/sql/00_supabase_stubs.sql
  echo 'create extension if not exists "uuid-ossp" with schema extensions;'
  echo "create extension if not exists pg_trgm with schema public;"
  echo "create extension if not exists unaccent with schema public;"
  echo "set check_function_bodies = false;"
  # Comptes : identifiants et rôles seulement.
  $PSQL "$DB_URL" -qAt -c "select format('insert into auth.users(id, email, raw_user_meta_data) values (%L, %L, %L);', id, email, jsonb_build_object('nom', nom, 'role', role, 'must_change_password', false)) from public.profiles order by email"
  $PG_DUMP "$DB_URL" --no-owner --inserts --rows-per-insert=200 -n public -n stats | nettoyer
  cat <<'SQL'
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
-- Comme sur Supabase : les rôles ont accès aux tables, les règles RLS font le tri.
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant usage on schema stats to anon, authenticated, service_role;
-- Fonctions : Supabase en donne l'exécution aux rôles connectés par défaut ; on
-- referme ensuite celles que les migrations réservent au serveur.
grant execute on all functions in schema public to authenticated, service_role;
do $$
declare r record;
begin
  for r in select oid::regprocedure as sig from pg_proc
           where pronamespace = 'public'::regnamespace
             and proname in ('notifier_action_assignee', 'import_zone_secteur', 'import_pdv_from_csv', 'import_visite_from_csv')
  loop execute format('revoke execute on function %s from authenticated', r.sig); end loop;
end $$;
SQL
} > "$SORTIE"
echo "✅ $SORTIE ($(wc -c < "$SORTIE") octets)"
