-- ============================================================================
-- Big Five Force — prélude à jouer juste APRÈS supabase/_archive/001_initial_schema.sql
-- sur une base neuve. Il pose ce que la base d'origine a reçu hors migrations
-- (colonnes ajoutées à la main, tables héritées), sans quoi les migrations
-- de supabase/nouveau échouent. Rejouable sans effet.
-- ============================================================================
alter table public.pdv add column if not exists territory_code text;
alter table public.pdv add column if not exists area_code text;
alter table public.pdv add column if not exists distributor_name text;

-- Tables héritées, jamais lues par l'application : les migrations de sécurité
-- y retirent des droits, elles doivent donc exister (vides).
create table if not exists public.pos_types (id bigserial primary key, level3_fr text, level4_fr text, level3_en text, level4_en text);
create table if not exists public.app_users (id bigserial primary key);
create table if not exists public.commerciaux (id bigserial primary key);
create table if not exists public.pdvs (id bigserial primary key);
create table if not exists public.geofence_zones (id bigserial primary key);

-- Fonction posée par Supabase sur certains projets (activation automatique de
-- RLS). Une migration lui retire des droits : on la crée vide si elle manque.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is null then
    execute 'create function public.rls_auto_enable() returns void language sql as ''select''';
  end if;
end $$;
