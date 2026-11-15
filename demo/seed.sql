-- Field Track — base embarquée du mode démo. Fichier généré par
-- scripts/field-track-build-demo-seed.sh : ne pas le modifier à la main.
-- Date de référence des visites : 2026-11-15
create extension if not exists pgcrypto with schema public;
-- Imitation minimale de Supabase (rôles, schémas auth / storage / cron / net / vault).
-- Sert au mode démo (base embarquée dans le navigateur) et aux essais sur un Postgres nu.
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
create role supabase_auth_admin nologin; create role authenticator nologin;
create schema extensions; create schema auth; create schema storage; create schema cron; create schema net; create schema vault;
create table auth.users (id uuid primary key default gen_random_uuid(), email text unique, encrypted_password text,
  raw_user_meta_data jsonb default '{}', raw_app_meta_data jsonb default '{}', created_at timestamptz default now(),
  last_sign_in_at timestamptz, email_confirmed_at timestamptz, banned_until timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
create function auth.role() returns text language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.role', true),''),'service_role') $$;
create function auth.jwt() returns jsonb language sql stable as $$ select '{}'::jsonb $$;
create function auth.email() returns text language sql stable as $$ select null::text $$;
create table storage.buckets (id text primary key, name text, public boolean default false, file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now(), updated_at timestamptz default now());
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, metadata jsonb, created_at timestamptz default now());
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name,'/') $$;
create table cron.job (jobid bigserial primary key, jobname text, schedule text, command text);
create function cron.schedule(text, text, text) returns bigint language sql as $$ insert into cron.job(jobname,schedule,command) values($1,$2,$3) returning jobid $$;
create function cron.unschedule(text) returns boolean language sql as $$ delete from cron.job where jobname=$1 returning true $$;
create function cron.unschedule(bigint) returns boolean language sql as $$ delete from cron.job where jobid=$1 returning true $$;
create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 1000) returns bigint language sql as $$ select 1::bigint $$;
create table vault.secrets (id uuid default gen_random_uuid(), name text, secret text);
create view vault.decrypted_secrets as select id, name, secret as decrypted_secret from vault.secrets;
create function vault.create_secret(text, text default null, text default null) returns uuid language sql as $$ insert into vault.secrets(secret,name) values($1,$2) returning id $$;
grant usage on schema public, extensions, auth, storage to anon, authenticated, service_role;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pg_trgm with schema public;
create extension if not exists unaccent with schema public;
set check_function_bodies = false;
insert into auth.users(id, email, raw_user_meta_data) values ('c1b8c7a8-c496-482e-acce-b7d41a18ab93', 'admin@fieldtrack.demo', '{"nom": "Admin Field Track", "role": "admin", "must_change_password": false}');
insert into auth.users(id, email, raw_user_meta_data) values ('1ce93462-59a6-4134-8c6a-f46bc3a868f9', 'commercial1@fieldtrack.demo', '{"nom": "Awa Démo", "role": "commercial", "must_change_password": false}');
insert into auth.users(id, email, raw_user_meta_data) values ('3fe0add4-79f2-4904-b7b0-54161b503ceb', 'commercial2@fieldtrack.demo', '{"nom": "Bakary Démo", "role": "commercial", "must_change_password": false}');
insert into auth.users(id, email, raw_user_meta_data) values ('939a7ba2-d282-452f-9706-ee73d62fa12f', 'commercial3@fieldtrack.demo', '{"nom": "Clarisse Démo", "role": "commercial", "must_change_password": false}');
insert into auth.users(id, email, raw_user_meta_data) values ('e3fd8415-d791-4164-80d3-2c3221ad27ca', 'merchandiser1@fieldtrack.demo', '{"nom": "Daouda Essai", "role": "merchandiser", "must_change_password": false}');
insert into auth.users(id, email, raw_user_meta_data) values ('ba78d180-c6bd-44f0-bcb0-b0a76d818a47', 'merchandiser2@fieldtrack.demo', '{"nom": "Estelle Essai", "role": "merchandiser", "must_change_password": false}');
insert into auth.users(id, email, raw_user_meta_data) values ('745aabe3-9648-4aa1-9feb-7d60f93a032a', 'merchandiser3@fieldtrack.demo', '{"nom": "Fabrice Essai", "role": "merchandiser", "must_change_password": false}');
insert into auth.users(id, email, raw_user_meta_data) values ('ecfef4e0-2429-4653-91aa-5a04eb14f1e0', 'merchandiser4@fieldtrack.demo', '{"nom": "Grâce Essai", "role": "merchandiser", "must_change_password": false}');
insert into auth.users(id, email, raw_user_meta_data) values ('5f7115ff-1868-49d3-917a-25797198941a', 'merchandiser5@fieldtrack.demo', '{"nom": "Hervé Essai", "role": "merchandiser", "must_change_password": false}');
COMMENT ON SCHEMA public IS 'standard public schema';
CREATE SCHEMA stats;
CREATE FUNCTION public.action_commerciale_touch() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at := now();
  return new;
end $$;
CREATE FUNCTION public.anonymiser_visites_du_profil() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  update public.visites
     set commercial = null,
         email = null
   where user_id = old.id;
  return old;
end;
$$;
CREATE FUNCTION public.calculer_dispo_categorie(p_data jsonb, p_cat text, p_canal text, p_segment text, p_grade text, p_base_calcul text DEFAULT 'taux_vente'::text) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select case
    when sum(pr.poids) > 0 then
      round(
        sum(pr.poids * (case
          -- Seuil quantité : en MT, priorité au standard MT vivant (seuil_disponibilite_mt),
          -- sinon seuil_disponibilite (GT ou repli). => l'éditeur admin MT est effectif.
          when coalesce((p_data->'produits'->cr.categorie_jsonb->'quantites'->>cr.sku_key)::numeric, 0) >= coalesce(mt.quantite_min, sd.quantite_min)
            -- Contrainte facings : uniquement MT (mt non null), sinon ignorée.
            and (mt.facings is null
                 or coalesce((p_data->'produits'->cr.categorie_jsonb->'facings'->>cr.sku_key)::numeric, 0) >= mt.facings)
          then 1 else 0 end))
        / sum(pr.poids) * 100
      )
    else null
  end
  from correspondance_reference cr
  join reference_produit rp on rp.id = cr.reference_produit_id
  join poids_reference pr on pr.reference_produit_id = rp.id
    and pr.canal = p_canal
    and pr.base_calcul = p_base_calcul
  join seuil_disponibilite sd on sd.reference_produit_id = rp.id
    and sd.segment = p_segment
    and sd.grade = p_grade
  left join seuil_disponibilite_mt mt on p_canal = 'MT'
    and mt.reference_produit_id = rp.id
    and mt.segment_mt = case p_grade
      when 'A' then 'Hypermarche'
      when 'B' then 'MoyenSuper'
      when 'C' then 'PetitSuper'
    end
  where cr.categorie_jsonb = p_cat;
$$;
CREATE FUNCTION public.calculer_perfect_store(p_visite_id uuid, p_base_calcul text DEFAULT 'taux_vente'::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_data jsonb;
  v_pdv text;
  v_canal text;
  v_segment text;
  v_grade text;
  v_vis_segment text;
  v_evap numeric;
  v_imp numeric;
  v_scm numeric;
  v_dispo numeric;
  -- PRÉSENCE
  v_pres_evap numeric;
  v_pres_imp numeric;
  v_pres_scm numeric;
  v_presence numeric;
  v_sku_presents integer;
  v_min_sku_presents integer;
  v_heros_obligatoires boolean;
  v_heros_total integer;
  v_heros_presents_count integer;
  v_assortiment numeric;
  v_heros_ok boolean;
  v_visi numeric;
  v_promo numeric;
  v_score numeric;
  v_niveau text;
  v_promo_applicable boolean;
  v_niveau_key text;
  n niveau_perfect_store%rowtype;
begin
  select data,pdv_id into v_data,v_pdv from visites where id=p_visite_id;
  if v_data is null then return; end if;
  select coalesce(cp.canal,'GT'),sg.segment,sg.grade,sv.segment
  into v_canal,v_segment,v_grade,v_vis_segment
  from pdv p
  left join lateral (
    select candidate.*
    from type_pdv candidate
    where regexp_replace(trim(candidate.nom),'\s+',' ','g')
      = regexp_replace(trim(p.sous_categorie_pdv),'\s+',' ','g')
    order by (candidate.nom=p.sous_categorie_pdv) desc
    limit 1
  ) tp on true
  left join categorie_pdv cp on cp.id=tp.categorie_pdv_id
  left join segment_grade_type_pdv sg on sg.type_pdv_id=tp.id
  left join segment_visibilite_type_pdv sv on sv.type_pdv_id=tp.id
  where p.pdv_id=v_pdv;
  v_canal := coalesce(v_canal,'GT');
  v_evap := calculer_dispo_categorie(v_data,'evap',v_canal,v_segment,v_grade,p_base_calcul);
  v_imp  := calculer_dispo_categorie(v_data,'imp',v_canal,v_segment,v_grade,p_base_calcul);
  v_scm  := calculer_dispo_categorie(v_data,'scm',v_canal,v_segment,v_grade,p_base_calcul);
  select round(avg(x)) into v_dispo
  from (values(v_evap),(v_imp),(v_scm)) as t(x)
  where x is not null;
  -- PRÉSENCE : même assiette de SKU, seuil ramené à 1.
  v_pres_evap := calculer_presence_categorie(v_data,'evap',v_canal,v_segment,v_grade,p_base_calcul);
  v_pres_imp  := calculer_presence_categorie(v_data,'imp',v_canal,v_segment,v_grade,p_base_calcul);
  v_pres_scm  := calculer_presence_categorie(v_data,'scm',v_canal,v_segment,v_grade,p_base_calcul);
  select round(avg(x)) into v_presence
  from (values(v_pres_evap),(v_pres_imp),(v_pres_scm)) as t(x)
  where x is not null;
  select sa.min_sku_presents, sa.heros_obligatoires
  into v_min_sku_presents, v_heros_obligatoires
  from standard_assortiment sa
  where sa.segment = v_segment
    and sa.grade = v_grade;
  if v_min_sku_presents is not null then
    select
      count(*) filter (
        where coalesce(
          (v_data->'produits'->cr.categorie_jsonb->'quantites'->>cr.sku_key)::numeric,
          0
        ) > 0
      ),
      count(*) filter (where rp.role = 'phare'),
      count(*) filter (
        where rp.role = 'phare'
          and coalesce(
            (v_data->'produits'->cr.categorie_jsonb->'quantites'->>cr.sku_key)::numeric,
            0
          ) > 0
      )
    into v_sku_presents, v_heros_total, v_heros_presents_count
    from correspondance_reference cr
    join reference_produit rp on rp.id = cr.reference_produit_id;
    v_assortiment := round(
      least(v_sku_presents::numeric / v_min_sku_presents, 1) * 100,
      2
    );
    v_heros_ok := not v_heros_obligatoires
      or v_heros_total = v_heros_presents_count;
  else
    v_sku_presents := null;
    v_assortiment := null;
    v_heros_ok := null;
  end if;
  v_promo_applicable := coalesce(
    (v_data->'visibilite'->>'promotion_applicable')::boolean,
    false
  );
  for n in select * from niveau_perfect_store order by rang desc
  loop
    v_niveau_key := case
      when n.code ilike 'FLAGSHIP%' then 'flagship'
      when n.code ilike 'VIP%' then 'vip'
      when n.code ilike 'CORE%' then 'core'
      else 'basic'
    end;
    v_visi := calculer_taux_standard(v_data,v_vis_segment,v_niveau_key,'visibilite');
    v_promo := case when v_promo_applicable
      then calculer_taux_standard(v_data,v_vis_segment,v_niveau_key,'promotion')
      else null
    end;
    if v_dispo is not null
       and v_dispo >= coalesce(n.dispo_rayon_min,0)
       and (
         v_assortiment is null
         or (v_assortiment >= 100 and coalesce(v_heros_ok,false))
       )
       and v_visi is not null
       and v_visi >= coalesce(n.visibilite_min,100)
       and (
         not v_promo_applicable
         or v_promo is null
         or v_promo >= coalesce(n.promotion_min,100)
       )
    then
      v_niveau := n.code;
      exit;
    end if;
  end loop;
  -- La présence n'entre PAS dans le score : le score reste la moyenne
  -- disponibilité / visibilité / promotion définie par le fichier Big Five.
  select round(avg(x),2) into v_score
  from (values
    (v_dispo),
    (v_visi),
    (case when v_promo_applicable then v_promo else null end)
  ) as t(x)
  where x is not null;
  insert into resultat_perfect_store(
    visite_id,base_calcul,dispo_rayon_evap,dispo_rayon_imp,dispo_rayon_scm,
    dispo_rayon,presence_rayon,presence_rayon_evap,presence_rayon_imp,presence_rayon_scm,
    assortiment,sku_presents,heros_presents,
    visibilite,promotion,score_global,niveau,calcule_le
  ) values (
    p_visite_id,p_base_calcul,v_evap,v_imp,v_scm,
    v_dispo,v_presence,v_pres_evap,v_pres_imp,v_pres_scm,
    v_assortiment,v_sku_presents,v_heros_ok,
    v_visi,v_promo,v_score,v_niveau,now()
  )
  on conflict (visite_id) do update set
    base_calcul=excluded.base_calcul,
    dispo_rayon_evap=excluded.dispo_rayon_evap,
    dispo_rayon_imp=excluded.dispo_rayon_imp,
    dispo_rayon_scm=excluded.dispo_rayon_scm,
    dispo_rayon=excluded.dispo_rayon,
    presence_rayon=excluded.presence_rayon,
    presence_rayon_evap=excluded.presence_rayon_evap,
    presence_rayon_imp=excluded.presence_rayon_imp,
    presence_rayon_scm=excluded.presence_rayon_scm,
    assortiment=excluded.assortiment,
    sku_presents=excluded.sku_presents,
    heros_presents=excluded.heros_presents,
    visibilite=excluded.visibilite,
    promotion=excluded.promotion,
    score_global=excluded.score_global,
    niveau=excluded.niveau,
    calcule_le=excluded.calcule_le;
end;
$$;
CREATE FUNCTION public.calculer_presence_categorie(p_data jsonb, p_cat text, p_canal text, p_segment text, p_grade text, p_base_calcul text DEFAULT 'taux_vente'::text) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select case
    when sum(pr.poids) > 0 then
      round(
        sum(pr.poids * (case
          when coalesce((p_data->'produits'->cr.categorie_jsonb->'quantites'->>cr.sku_key)::numeric, 0) >= 1
          then 1 else 0 end))
        / sum(pr.poids) * 100
      )
    else null
  end
  from correspondance_reference cr
  join reference_produit rp on rp.id = cr.reference_produit_id
  join poids_reference pr on pr.reference_produit_id = rp.id
    and pr.canal = p_canal
    and pr.base_calcul = p_base_calcul
  join seuil_disponibilite sd on sd.reference_produit_id = rp.id
    and sd.segment = p_segment
    and sd.grade = p_grade
  where cr.categorie_jsonb = p_cat;
$$;
CREATE FUNCTION public.calculer_taux_standard(p_data jsonb, p_segment text, p_niveau text, p_pilier text) RETURNS numeric
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    AS $$
declare
  v_total int;
  v_requis int;
  v_ok int;
begin
  if p_segment is null then return null; end if;
  select count(*),
         count(*) filter (where s.requis and not e.optionnel),
         count(*) filter (
           where s.requis and not e.optionnel
             and element_visibilite_observe(p_data,e.code)
         )
  into v_total, v_requis, v_ok
  from standard_visibilite s
  join element_visibilite e on e.id=s.element_visibilite_id
  where s.segment=p_segment
    and s.niveau_perfect_store=p_niveau
    and e.pilier=p_pilier;
  if v_total=0 then return null; end if;
  if v_requis=0 then return 100; end if;
  return round(v_ok::numeric/v_requis*100,2);
end;
$$;
CREATE FUNCTION public.compter_visites_a_recalculer() RETURNS bigint
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select count(*) from public.visites;
$$;
CREATE TABLE public.visite_perfect_store (
    visite_id text NOT NULL,
    basis text DEFAULT 'taux_vente'::text NOT NULL,
    osa_lineaire numeric,
    osa_pondere numeric,
    osa_note10 numeric,
    assortiment_taux numeric,
    visibilite_taux numeric,
    promo_taux numeric,
    score_global numeric,
    dispo_categorie jsonb DEFAULT '{}'::jsonb,
    is_perfect_store boolean DEFAULT false NOT NULL,
    tier_atteint text,
    computed_at timestamp with time zone DEFAULT now(),
    CONSTRAINT visite_perfect_store_basis_check CHECK ((basis = ANY (ARRAY['taux_vente'::text, 'taux_revu'::text]))),
    CONSTRAINT visite_perfect_store_tier_atteint_check CHECK ((tier_atteint = ANY (ARRAY['FLAGSHIP'::text, 'VIP'::text, 'CORE'::text, 'BASIC'::text])))
);
CREATE FUNCTION public.compute_perfect_store(p_visite_id text, p_basis text DEFAULT 'taux_vente'::text) RETURNS public.visite_perfect_store
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_visite   public.visites%ROWTYPE;
  v_pdv      public.pdv%ROWTYPE;
  v_group    TEXT; v_tier TEXT; v_trade TEXT; v_objectif TEXT;
  v_qte      INTEGER; v_min INTEGER; v_weight NUMERIC; v_avail BOOLEAN;
  g_eval     INTEGER := 0; g_avail INTEGER := 0;
  g_wsum     NUMERIC := 0; g_wtot NUMERIC := 0;
  cat_detail JSONB := '{}'::jsonb; cat_eval INTEGER; cat_avail INTEGER;
  vis_req    INTEGER := 0; vis_ok INTEGER := 0; vis_rate NUMERIC;
  v_minsku   INTEGER; assort NUMERIC;
  osa_lin    NUMERIC; osa_w NUMERIC; score NUMERIC; wden NUMERIC;
  cfg        public.perfect_store_score_config%ROWTYPE;
  res        public.visite_perfect_store%ROWTYPE;
  v_rec      RECORD;
BEGIN
  SELECT * INTO v_visite FROM public.visites WHERE visite_id = p_visite_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Visite % introuvable', p_visite_id; END IF;
  SELECT * INTO v_pdv FROM public.pdv WHERE pdv_id = v_visite.pdv_id;
  SELECT * INTO cfg  FROM public.perfect_store_score_config WHERE id = 1;
  SELECT standard_group, tier INTO v_group, v_tier
    FROM public.pos_standard_map WHERE sous_categorie_pdv = v_pdv.sous_categorie_pdv;
  v_trade := CASE WHEN v_pdv.canal ILIKE '%modern%' OR v_pdv.canal = 'MT' THEN 'MT' ELSE 'GT' END;
  v_objectif := COALESCE(v_pdv.objectif_perfect_store, 'BASIC');
  -- (1)(2)(3) OSA + assortiment
  FOR v_rec IN
    SELECT s.category, s.sku, s.min_quantity
    FROM public.availability_standards s
    WHERE s.standard_group = v_group AND s.tier = v_tier AND s.category IN ('evap','imp','scm')
  LOOP
    v_min := v_rec.min_quantity;
    v_qte := COALESCE(NULLIF(v_visite.data->'produits'->v_rec.category->'quantites'->>v_rec.sku,'')::INTEGER, 0);
    v_avail := v_qte >= v_min;
    SELECT weight INTO v_weight FROM public.availability_weights
      WHERE category=v_rec.category AND trade_type=v_trade AND basis=p_basis AND sku=v_rec.sku;
    v_weight := COALESCE(v_weight, 0);
    g_eval := g_eval + 1; g_wtot := g_wtot + v_weight;
    IF v_avail THEN g_avail := g_avail + 1; g_wsum := g_wsum + v_weight; END IF;
    cat_eval  := COALESCE((cat_detail->v_rec.category->>'eval')::INTEGER,0) + 1;
    cat_avail := COALESCE((cat_detail->v_rec.category->>'avail')::INTEGER,0) + (CASE WHEN v_avail THEN 1 ELSE 0 END);
    cat_detail := jsonb_set(cat_detail, ARRAY[v_rec.category],
      jsonb_build_object('eval',cat_eval,'avail',cat_avail), true);
  END LOOP;
  osa_lin := CASE WHEN g_eval>0 THEN g_avail::NUMERIC/g_eval ELSE NULL END;
  osa_w   := CASE WHEN g_wtot>0 THEN g_wsum/g_wtot ELSE NULL END;
  SELECT min_sku_present INTO v_minsku FROM public.assortment_standards
    WHERE standard_group=v_group AND tier=v_tier;
  assort := CASE WHEN v_minsku IS NULL OR v_minsku=0 THEN NULL
                 ELSE LEAST(g_avail::NUMERIC / v_minsku, 1) END;
  -- (4) Visibilité
  FOR v_rec IN
    SELECT zone, element_key FROM public.visibility_standards
    WHERE standard_group=v_group AND ps_tier=v_objectif AND is_required
  LOOP
    vis_req := vis_req + 1;
    IF COALESCE((v_visite.data->'visibilite'->v_rec.zone->>v_rec.element_key)::BOOLEAN, false) THEN
      vis_ok := vis_ok + 1;
    END IF;
  END LOOP;
  vis_rate := CASE WHEN vis_req>0 THEN vis_ok::NUMERIC/vis_req ELSE NULL END;
  -- (5) Score composite renormalisé sur les composantes présentes
  score := 0; wden := 0;
  IF osa_lin  IS NOT NULL THEN score := score + cfg.w_osa_lineaire*osa_lin; wden := wden + cfg.w_osa_lineaire; END IF;
  IF osa_w    IS NOT NULL THEN score := score + cfg.w_osa_pondere*osa_w;   wden := wden + cfg.w_osa_pondere; END IF;
  IF assort   IS NOT NULL THEN score := score + cfg.w_assortiment*assort;  wden := wden + cfg.w_assortiment; END IF;
  IF vis_rate IS NOT NULL THEN score := score + cfg.w_visibilite*vis_rate; wden := wden + cfg.w_visibilite; END IF;
  score := CASE WHEN wden>0 THEN score/wden ELSE NULL END;
  -- (6) Gating tier
  res.visite_id := p_visite_id; res.basis := p_basis;
  res.osa_lineaire := osa_lin; res.osa_pondere := osa_w; res.osa_note10 := ROUND(COALESCE(osa_w,0)*10,2);
  res.assortiment_taux := assort; res.visibilite_taux := vis_rate; res.promo_taux := NULL;
  res.score_global := score; res.dispo_categorie := cat_detail;
  res.is_perfect_store := false; res.tier_atteint := NULL; res.computed_at := NOW();
  SELECT ps_tier INTO res.tier_atteint
  FROM public.perfect_store_tier_config c
  WHERE COALESCE(osa_w,0)    >= c.osa_min
    AND COALESCE(assort,1)   >= c.assort_min
    AND COALESCE(vis_rate,0) >= c.visi_min
    AND (c.promo_min IS NULL OR COALESCE(res.promo_taux,0) >= c.promo_min)
  ORDER BY c.rang DESC
  LIMIT 1;
  res.is_perfect_store := res.tier_atteint IS NOT NULL;
  INSERT INTO public.visite_perfect_store AS t VALUES (res.*)
  ON CONFLICT (visite_id) DO UPDATE SET
    basis=EXCLUDED.basis, osa_lineaire=EXCLUDED.osa_lineaire, osa_pondere=EXCLUDED.osa_pondere,
    osa_note10=EXCLUDED.osa_note10, assortiment_taux=EXCLUDED.assortiment_taux,
    visibilite_taux=EXCLUDED.visibilite_taux, promo_taux=EXCLUDED.promo_taux,
    score_global=EXCLUDED.score_global, dispo_categorie=EXCLUDED.dispo_categorie,
    is_perfect_store=EXCLUDED.is_perfect_store, tier_atteint=EXCLUDED.tier_atteint,
    computed_at=EXCLUDED.computed_at;
  RETURN res;
END $$;
CREATE FUNCTION public.couverture_visites_par_commercial(p_division text DEFAULT NULL::text, p_territoire text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_distributeur text DEFAULT NULL::text, p_date_debut date DEFAULT NULL::date, p_date_fin date DEFAULT NULL::date) RETURNS TABLE(commercial text, email text, nb_visites bigint, nb_pdv bigint, nb_jours bigint, visites_par_jour numeric, pdv_visites jsonb)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    SET work_mem TO '16MB'
    AS $$
  with scope_pdv as (
    select p.pdv_id
    from pdv p
    left join territoire t on t.nom = p.zone
    left join sous_region sr on sr.code = t.sous_region_code
    left join region rg on rg.code = sr.region_code
    where (p_division is null or p_division = '' or rg.nom_affichage = p_division)
      and (p_territoire is null or p_territoire = '' or p.zone = p_territoire)
      and (p_area is null or p_area = '' or p.area_code = p_area or p.quartier = p_area)
      and (p_distributeur is null or p_distributeur = '' or p.distributor_name = p_distributeur)
  ),
  visites_scope as (
    select
      coalesce(nullif(trim(v.commercial), ''), v.email, '—') as commercial,
      coalesce(v.email, '') as email,
      v.pdv_id, v.date_visite,
      coalesce(p.nom_pdv, v.pdv_id) as nom_pdv
    from visites v
    join pdv p on p.pdv_id = v.pdv_id
    where v.pdv_id in (select pdv_id from scope_pdv)
      and (p_date_debut is null or v.date_visite >= p_date_debut::timestamptz)
      and (p_date_fin is null or v.date_visite < (p_date_fin + 1)::timestamptz)
  ),
  -- Un PDV par merchandiser, avec son nombre de passages sur la période.
  par_pdv as (
    select commercial, pdv_id, max(nom_pdv) as nom_pdv, count(*) as passages,
           max(date_visite) as derniere_visite
    from visites_scope
    group by commercial, pdv_id
  )
  select
    vs.commercial,
    max(vs.email) as email,
    count(*) as nb_visites,
    count(distinct vs.pdv_id) as nb_pdv,
    count(distinct date_trunc('day', vs.date_visite)) as nb_jours,
    round(count(*)::numeric / nullif(count(distinct date_trunc('day', vs.date_visite)), 0), 1) as visites_par_jour,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'pdv_id', pp.pdv_id,
        'nom_pdv', pp.nom_pdv,
        'passages', pp.passages,
        'derniere_visite', pp.derniere_visite
      ) order by pp.passages desc, pp.nom_pdv)
      from par_pdv pp where pp.commercial = vs.commercial
    ), '[]'::jsonb) as pdv_visites
  from visites_scope vs
  group by vs.commercial
  order by count(*) desc;
$$;
CREATE FUNCTION public.dashboard_perfect_store_filtre(p_division text DEFAULT NULL::text, p_territoire text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_distributeur text DEFAULT NULL::text, p_date_debut date DEFAULT NULL::date, p_date_fin date DEFAULT NULL::date) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    SET work_mem TO '16MB'
    AS $$
  with pdv_scope as (
    select p.pdv_id, p.is_active
    from pdv p
    where (p_territoire is null or p_territoire = '' or p.zone = p_territoire)
      and (p_area is null or p_area = '' or p.area_code = p_area or p.quartier = p_area)
      and (p_distributeur is null or p_distributeur = '' or p.distributor_name = p_distributeur)
      and (p_division is null or p_division = '' or exists (
            select 1
            from territoire t
            join sous_region sr on sr.code = t.sous_region_code
            join region rg on rg.code = sr.region_code
            where t.nom = p.zone and rg.nom_affichage = p_division))
  ),
  actifs as (
    select count(*) filter (where coalesce(is_active, true)) as pdv_total from pdv_scope
  ),
  visites_scope as (
    select v.id, v.pdv_id, v.date_visite
    from visites v
    where v.date_visite >= coalesce(p_date_debut::timestamptz, '-infinity'::timestamptz)
      and v.date_visite < coalesce((p_date_fin + 1)::timestamptz, 'infinity'::timestamptz)
      and exists (select 1 from pdv_scope s where s.pdv_id = v.pdv_id)
  ),
  scored as (
    select r.niveau, r.score_global, r.dispo_rayon, r.visibilite, r.promotion,
           r.assortiment, r.calcule_le, v.pdv_id, v.date_visite,
           r.presence_rayon, r.presence_rayon_evap, r.presence_rayon_imp, r.presence_rayon_scm,
           r.dispo_rayon_evap, r.dispo_rayon_imp, r.dispo_rayon_scm
    from resultat_perfect_store r
    join visites_scope v on v.id = r.visite_id
  ),
  -- Une ligne par PDV : sa dernière visite scorée de la période, avec TOUS ses
  -- piliers. Les moyennes ci-dessous portent sur cette CTE et non sur `scored`,
  -- sinon un PDV revisité 3 fois pèserait 3 fois dans le taux de présence alors
  -- que le reste de la page le compte une fois.
  dernier as (
    select distinct on (s.pdv_id) s.*
    from scored s
    order by s.pdv_id, s.date_visite desc, s.calcule_le desc
  ),
  -- Tous les niveaux du référentiel, y compris ceux à 0 PDV : le client lit
  -- « 500 Flagship, 0 VIP, … » — un niveau absent se lirait comme un oubli.
  par_niveau as (
    select n.code as niveau, count(d.pdv_id) as nb_pdv, n.rang
    from niveau_perfect_store n
    left join dernier d on d.niveau = n.code
    group by n.code, n.rang
  )
  select jsonb_build_object(
    'pdv_scores', (select count(*) from dernier),
    'pdv_perfect_stores', (select count(*) filter (where niveau is not null) from dernier),
    'pdv_perfect_store_pct', (select round(100.0 * count(*) filter (where niveau is not null) / nullif(count(*), 0), 1) from dernier),
    'pdv_non_conformes', (select count(*) filter (where niveau is null) from dernier),
    'par_niveau', coalesce((
      select jsonb_agg(jsonb_build_object('niveau', niveau, 'nb_pdv', nb_pdv) order by rang desc nulls last, niveau)
      from par_niveau
    ), '[]'::jsonb),
    -- Compteurs d'activité : ceux-là comptent bien des passages.
    'visites_scorees', (select count(*) from scored),
    'perfect_stores', (select count(*) filter (where niveau is not null) from scored),
    'perfect_store_pct', (select round(100.0 * count(*) filter (where niveau is not null) / nullif(count(*), 0), 1) from scored),
    -- Moyennes des piliers : base PDV distincts, comme le KPI principal.
    'score_global_moyen_pct', (select round(avg(score_global), 1) from dernier),
    'osa_moyen_pct', (select round(avg(dispo_rayon), 1) from dernier),
    'visibilite_moyenne_pct', (select round(avg(visibilite), 1) from dernier),
    'promotion_moyenne_pct', (select round(avg(promotion), 1) from dernier),
    'assortiment_moyen_pct', (select round(avg(assortiment), 1) from dernier),
    -- Taux de présence : distribution numérique (quantité >= 1).
    'presence_moyenne_pct', (select round(avg(presence_rayon), 1) from dernier),
    'par_categorie', coalesce((
      select jsonb_agg(x order by x->>'categorie')
      from (
        select jsonb_build_object(
          'categorie', c.cat,
          'presence_pct', round(avg(case c.cat when 'evap' then s.presence_rayon_evap when 'imp' then s.presence_rayon_imp else s.presence_rayon_scm end), 1),
          'disponibilite_pct', round(avg(case c.cat when 'evap' then s.dispo_rayon_evap when 'imp' then s.dispo_rayon_imp else s.dispo_rayon_scm end), 1)
        ) as x
        from dernier s cross join (values ('evap'),('imp'),('scm')) as c(cat)
        group by c.cat
      ) t
    ), '[]'::jsonb),
    'pdv_vus', (select count(distinct pdv_id) from visites_scope),
    'pdv_total', (select pdv_total from actifs),
    'couverture_pct', (
      select round(100.0 * (select count(distinct pdv_id) from visites_scope)
        / nullif((select pdv_total from actifs), 0), 1)
    ),
    'visites_total', (select count(*) from visites_scope)
  );
$$;
CREATE FUNCTION public.dashboard_presence_skus(p_division text DEFAULT NULL::text, p_territoire text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_distributeur text DEFAULT NULL::text, p_date_debut date DEFAULT NULL::date, p_date_fin date DEFAULT NULL::date) RETURNS TABLE(reference_nom text, role text, categorie text, releves bigint, presents bigint, disponibles bigint, presence_pct numeric, disponibilite_pct numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    SET work_mem TO '16MB'
    AS $$
  with scope_pdv as (
    select p.pdv_id
    from pdv p
    left join territoire t on t.nom = p.zone
    left join sous_region sr on sr.code = t.sous_region_code
    left join region rg on rg.code = sr.region_code
    where (p_division is null or p_division = '' or rg.nom_affichage = p_division)
      and (p_territoire is null or p_territoire = '' or p.zone = p_territoire)
      and (p_area is null or p_area = '' or p.area_code = p_area or p.quartier = p_area)
      and (p_distributeur is null or p_distributeur = '' or p.distributor_name = p_distributeur)
  ),
  -- Une visite par PDV (la dernière de la période), pour rester sur la même
  -- base de comptage que le reste du dashboard.
  derniere_visite as (
    select distinct on (v.pdv_id) v.id, v.pdv_id, v.data, p.sous_categorie_pdv
    from visites v
    join pdv p on p.pdv_id = v.pdv_id
    where v.pdv_id in (select pdv_id from scope_pdv)
      and (p_date_debut is null or v.date_visite >= p_date_debut::timestamptz)
      and (p_date_fin is null or v.date_visite < (p_date_fin + 1)::timestamptz)
    order by v.pdv_id, v.date_visite desc
  ),
  segment_du_pdv as (
    select dv.id, dv.data, sg.segment, sg.grade, coalesce(cp.canal, 'GT') as canal
    from derniere_visite dv
    left join lateral (
      select candidate.*
      from type_pdv candidate
      where regexp_replace(trim(candidate.nom),'\s+',' ','g')
        = regexp_replace(trim(dv.sous_categorie_pdv),'\s+',' ','g')
      order by (candidate.nom = dv.sous_categorie_pdv) desc
      limit 1
    ) tp on true
    left join categorie_pdv cp on cp.id = tp.categorie_pdv_id
    left join segment_grade_type_pdv sg on sg.type_pdv_id = tp.id
  ),
  releve as (
    select
      rp.nom as reference_nom,
      rp.role,
      cr.categorie_jsonb as categorie,
      coalesce((sp.data->'produits'->cr.categorie_jsonb->'quantites'->>cr.sku_key)::numeric, 0) as quantite,
      coalesce((sp.data->'produits'->cr.categorie_jsonb->'facings'->>cr.sku_key)::numeric, 0) as facings,
      -- Même règle de seuil que calculer_dispo_categorie depuis 20260716190000 :
      -- en modern trade, le standard MT vivant prime sur le seuil GT. Sans ça,
      -- la colonne « Dispo. » de ce tableau contredirait le bloc « Par catégorie »
      -- (qui lit dispo_rayon_*, lui MT-aware) sur les supermarchés.
      coalesce(mt.quantite_min, sd.quantite_min) as quantite_min,
      mt.facings as facings_min
    from segment_du_pdv sp
    join correspondance_reference cr on true
    join reference_produit rp on rp.id = cr.reference_produit_id
    join seuil_disponibilite sd on sd.reference_produit_id = rp.id
      and sd.segment = sp.segment
      and sd.grade = sp.grade
    left join seuil_disponibilite_mt mt on sp.canal = 'MT'
      and mt.reference_produit_id = rp.id
      and mt.segment_mt = case sp.grade
        when 'A' then 'Hypermarche'
        when 'B' then 'MoyenSuper'
        when 'C' then 'PetitSuper'
      end
    where rp.role in ('phare', 'nouveaute')
  )
  select
    r.reference_nom,
    r.role,
    r.categorie,
    count(*) as releves,
    count(*) filter (where r.quantite >= 1) as presents,
    count(*) filter (
      where r.quantite >= r.quantite_min
        and (r.facings_min is null or r.facings >= r.facings_min)
    ) as disponibles,
    round(100.0 * count(*) filter (where r.quantite >= 1) / nullif(count(*), 0), 1) as presence_pct,
    round(100.0 * count(*) filter (
      where r.quantite >= r.quantite_min
        and (r.facings_min is null or r.facings >= r.facings_min)
    ) / nullif(count(*), 0), 1) as disponibilite_pct
  from releve r
  group by r.reference_nom, r.role, r.categorie
  order by (r.role = 'phare') desc, r.reference_nom;
$$;
CREATE FUNCTION public.element_visibilite_observe(p_data jsonb, p_code text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select coalesce(
    (p_data->'visibilite'->'standards'->>p_code)::boolean,
    case p_code
      when 'affiche' then (p_data->'visibilite'->'exterieure'->>'poster')::boolean
      when 'guirlande' then (p_data->'visibilite'->'exterieure'->>'guirlande')::boolean
      when 'sign_board' then (p_data->'visibilite'->'exterieure'->>'sign_board')::boolean
      when 'panneau_privilege' then (p_data->'visibilite'->'exterieure'->>'panneau_privilege')::boolean
      when 'full_branding' then (p_data->'visibilite'->'exterieure'->>'full_branding')::boolean
      when 'reglette' then (p_data->'visibilite'->'interieure'->>'reglettes')::boolean
      when 'maison_br' then (p_data->'visibilite'->'interieure'->>'maison_bonnet_rouge')::boolean
      when 'hanger' then (p_data->'visibilite'->'interieure'->>'hanger')::boolean
      when 'presentoir' then (p_data->'visibilite'->'interieure'->>'presentoirs')::boolean
      when 'tg' then (p_data->'visibilite'->'interieure'->>'tete_gondole')::boolean
      when 'merchandising' then (p_data->'visibilite'->'interieure'->>'merchandising')::boolean
      else false
    end,
    false
  );
$$;
CREATE FUNCTION public.est_gestionnaire_perfect_store() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('admin','superviseur')
      and is_active = true
  );
$$;
CREATE FUNCTION public.fenetre_suivi_mois() RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select coalesce((select valeur from parametre_suivi where cle = 'fenetre_suivi_mois'), 12);
$$;
CREATE FUNCTION public.frequence_pour_pdv(p_zone text, p_type text) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select f.jours
  from frequence_visite f
  where (f.zone is null or f.zone = p_zone)
    and (f.type_pdv is null or f.type_pdv = p_type)
  order by (f.zone is not null)::int + (f.type_pdv is not null)::int desc,
           (f.type_pdv is not null)::int desc
  limit 1;
$$;
CREATE FUNCTION public.geolocaliser_pdv(p_pdv_id text, p_lat double precision, p_lng double precision, p_precision integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_n integer;
begin
  if not public.peut_ecrire_terrain() then
    return false;
  end if;
  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180
     or (p_lat = 0 and p_lng = 0) then
    return false;
  end if;
  if p_precision is null or p_precision < 0 or p_precision > 30 then
    return false;
  end if;
  if not exists (select 1 from public.pdv_ids_perimetre() x where x = p_pdv_id) then
    return false;
  end if;
  update public.pdv
  set geolocation_lat = p_lat,
      geolocation_lng = p_lng,
      gps_source = 'terrain',
      gps_precision_m = p_precision,
      gps_maj_par = auth.uid(),
      gps_maj_le = now()
  where pdv_id = p_pdv_id
    and (geolocation_lat is null or geolocation_lng is null);
  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$$;
CREATE FUNCTION public.get_visites_filtered(p_date_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_date_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_commercial text DEFAULT NULL::text, p_canal text DEFAULT NULL::text, p_categorie text DEFAULT NULL::text, p_sous_categorie text DEFAULT NULL::text, p_region text DEFAULT NULL::text, p_zone text DEFAULT NULL::text, p_secteur text DEFAULT NULL::text, p_nom_pdv text DEFAULT NULL::text, p_division text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_limit integer DEFAULT 2000, p_offset integer DEFAULT 0) RETURNS TABLE(visite_id text, date_visite timestamp with time zone, commercial text, email text, data jsonb, pdv_id text, nom_pdv text, canal text, categorie_pdv text, sous_categorie_pdv text, region text, zone text, quartier text)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    SET work_mem TO '16MB'
    AS $$
  select
    v.visite_id,
    v.date_visite,
    v.commercial,
    v.email,
    v.data,
    p.pdv_id,
    p.nom_pdv,
    p.canal,
    p.categorie_pdv,
    p.sous_categorie_pdv,
    p.region,
    p.zone,
    p.quartier
  from visites v
  left join pdv p on p.pdv_id = v.pdv_id
  left join territoire t on t.nom = p.zone
  left join sous_region sr on sr.code = t.sous_region_code
  left join region rg on rg.code = sr.region_code
  where (p_date_from is null or v.date_visite >= p_date_from)
    and (p_date_to is null or v.date_visite <= p_date_to)
    and (p_commercial is null or p_commercial = '' or v.commercial ilike '%' || p_commercial || '%' or v.email ilike '%' || p_commercial || '%')
    and (p_canal is null or p_canal = '' or p.canal = p_canal)
    and (p_categorie is null or p_categorie = '' or p.categorie_pdv = p_categorie)
    and (p_sous_categorie is null or p_sous_categorie = '' or p.sous_categorie_pdv = p_sous_categorie)
    and (p_division is null or p_division = '' or rg.nom_affichage = p_division)
    and (p_region is null or p_region = '' or sr.nom_affichage = p_region or p.region = p_region)
    and (p_zone is null or p_zone = '' or p.zone = p_zone)
    and (p_area is null or p_area = '' or p.area_code = p_area or p.quartier = p_area)
    and (p_secteur is null or p_secteur = '' or p.quartier ilike '%' || p_secteur || '%')
    and (p_nom_pdv is null or p_nom_pdv = '' or p.nom_pdv ilike '%' || p_nom_pdv || '%')
  -- Ordre TOTAL : sans le départage par visite_id, la pagination pourrait
  -- rendre deux fois la même ligne et en sauter une autre.
  order by v.date_visite desc, v.visite_id
  limit greatest(coalesce(p_limit, 2000), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;
CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  INSERT INTO public.profiles (id, email, nom, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'nom', ''),
    CASE
      WHEN NEW.raw_user_meta_data->>'role' IN ('admin', 'superviseur', 'merchandiser', 'commercial')
        THEN NEW.raw_user_meta_data->>'role'
      ELSE 'merchandiser'
    END
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE FUNCTION public.import_pdv_from_csv(p_pdv_id text, p_nom_pdv text, p_canal text DEFAULT 'General trade'::text, p_categorie_pdv text DEFAULT 'Point de vente détail'::text, p_sous_categorie_pdv text DEFAULT 'Boutique C'::text, p_autre_sous_categorie text DEFAULT NULL::text, p_region text DEFAULT NULL::text, p_zone text DEFAULT NULL::text, p_secteur text DEFAULT NULL::text, p_geolocation text DEFAULT NULL::text, p_adressage text DEFAULT NULL::text, p_image text DEFAULT NULL::text, p_date text DEFAULT NULL::text, p_ajoute_par text DEFAULT NULL::text, p_jour_routing text DEFAULT NULL::text, p_position_routing integer DEFAULT NULL::integer, p_canal_routing text DEFAULT NULL::text, p_sales_rep_routing text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare v_lat double precision; v_lng double precision; v_date date; v_parts text[];
begin
  if p_geolocation is not null and p_geolocation <> '' then
    v_parts := string_to_array(replace(p_geolocation,' ',''), ',');
    if array_length(v_parts,1)=2 then v_lat := v_parts[1]::double precision; v_lng := v_parts[2]::double precision; end if;
  end if;
  if p_date is not null and p_date <> '' then
    begin v_date := to_date(p_date,'DD/MM/YYYY'); exception when others then v_date := null; end;
  end if;
  insert into public.pdv (pdv_id, nom_pdv, canal, categorie_pdv, sous_categorie_pdv,
    autre_sous_categorie, region, zone, quartier, geolocation_lat, geolocation_lng, adressage,
    image_url, date_creation, ajoute_par, jour_routing, position_routing, canal_routing, sales_rep_routing)
  values (p_pdv_id, p_nom_pdv, p_canal, p_categorie_pdv, p_sous_categorie_pdv,
    nullif(p_autre_sous_categorie,''), p_region, p_zone, p_secteur, v_lat, v_lng, p_adressage,
    p_image, v_date, p_ajoute_par, nullif(p_jour_routing,''), p_position_routing,
    nullif(p_canal_routing,''), nullif(p_sales_rep_routing,''))
  on conflict (pdv_id) do update set
    nom_pdv=excluded.nom_pdv, canal=excluded.canal, categorie_pdv=excluded.categorie_pdv,
    sous_categorie_pdv=excluded.sous_categorie_pdv, autre_sous_categorie=excluded.autre_sous_categorie,
    region=excluded.region, zone=excluded.zone, quartier=excluded.quartier,
    geolocation_lat=excluded.geolocation_lat, geolocation_lng=excluded.geolocation_lng,
    adressage=excluded.adressage, image_url=excluded.image_url, date_creation=excluded.date_creation,
    ajoute_par=excluded.ajoute_par, jour_routing=excluded.jour_routing, position_routing=excluded.position_routing,
    canal_routing=excluded.canal_routing, sales_rep_routing=excluded.sales_rep_routing, updated_at=now();
end; $$;
CREATE FUNCTION public.import_visite_from_csv(p_data jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_date TIMESTAMPTZ;
  v_visite_data JSONB;
  v_images TEXT[];
  -- Extracted fields
  v_visite_id TEXT;
  v_pdv_id TEXT;
  v_commercial TEXT;
  v_email TEXT;
BEGIN
  v_visite_id := p_data->>'visite_id';
  v_pdv_id := p_data->>'pdv_id';
  v_commercial := p_data->>'commercial';
  v_email := p_data->>'email';
  -- Parse date "DD/MM/YYYY HH24:MI:SS"
  BEGIN
    v_date := to_timestamp(p_data->>'date', 'DD/MM/YYYY HH24:MI:SS');
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      v_date := to_timestamp(p_data->>'date', 'DD/MM/YYYY');
    EXCEPTION WHEN OTHERS THEN
      v_date := NOW();
    END;
  END;
  -- Build structured JSONB
  v_visite_data := jsonb_build_object(
    'produits', jsonb_build_object(
      'evap', jsonb_build_object(
        'present', COALESCE((p_data->>'evap_present')::boolean, false),
        'br_gold', COALESCE(p_data->>'evap_br_gold', 'En rupture'),
        'br_160g', COALESCE(p_data->>'evap_br_160g', 'En rupture'),
        'brb_160g', COALESCE(p_data->>'evap_brb_160g', 'En rupture'),
        'br_400g', COALESCE(p_data->>'evap_br_400g', 'En rupture'),
        'brb_400g', COALESCE(p_data->>'evap_brb_400g', 'En rupture'),
        'pearl_400g', COALESCE(p_data->>'evap_pearl_400g', 'En rupture'),
        'prix_respectes', COALESCE((p_data->>'evap_prix')::boolean, false)
      ),
      'imp', jsonb_build_object(
        'present', COALESCE((p_data->>'imp_present')::boolean, false),
        'br_400g', COALESCE(p_data->>'imp_br_400g', 'En rupture'),
        'br_900g', COALESCE(p_data->>'imp_br_900g', 'En rupture'),
        'br_2_5kg', COALESCE(p_data->>'imp_br_2_5kg', 'En rupture'),
        'br_375g', COALESCE(p_data->>'imp_br_375g', 'En rupture'),
        'brb_400g', COALESCE(p_data->>'imp_brb_400g', 'En rupture'),
        'br_20g', COALESCE(p_data->>'imp_br_20g', 'En rupture'),
        'brb_25g', COALESCE(p_data->>'imp_brb_25g', 'En rupture'),
        'brd_15g', COALESCE(p_data->>'imp_brd_15g', 'En rupture'),
        'brd_350g', COALESCE(p_data->>'imp_brd_350g', 'En rupture'),
        'prix_respectes', COALESCE((p_data->>'imp_prix')::boolean, false)
      ),
      'scm', jsonb_build_object(
        'present', COALESCE((p_data->>'scm_present')::boolean, false),
        'br_1kg', COALESCE(p_data->>'scm_br_1kg', 'En rupture'),
        'brb_1kg', COALESCE(p_data->>'scm_brb_1kg', 'En rupture'),
        'brb_397g', COALESCE(p_data->>'scm_brb_397g', 'En rupture'),
        'br_397g', COALESCE(p_data->>'scm_br_397g', 'En rupture'),
        'pearl_1kg', COALESCE(p_data->>'scm_pearl_1kg', 'En rupture'),
        'prix_respectes', COALESCE((p_data->>'scm_prix')::boolean, false)
      ),
      'uht', jsonb_build_object(
        'present', COALESCE((p_data->>'uht_present')::boolean, false),
        'demi_ecreme', COALESCE(p_data->>'uht_demi_ecreme', 'En rupture'),
        'elopack_500ml', COALESCE(p_data->>'uht_elopack_500ml', 'En rupture'),
        'brique_1l', COALESCE(p_data->>'uht_brique_1l', 'En rupture'),
        'prix_respectes', COALESCE((p_data->>'uht_prix')::boolean, false)
      ),
      'cereales', jsonb_build_object(
        'present', COALESCE((p_data->>'cereales_present')::boolean, false),
        'brcv', COALESCE(p_data->>'cereales_brcv', 'En rupture'),
        'brcc', COALESCE(p_data->>'cereales_brcc', 'En rupture'),
        'prix_respectes', COALESCE((p_data->>'cereales_prix')::boolean, false)
      ),
      'yaourt', jsonb_build_object(
        'present', COALESCE((p_data->>'yaourt_present')::boolean, false),
        'br_yogoo_nature_mini_90ml', COALESCE(p_data->>'yaourt_nature_mini', 'En rupture'),
        'br_yogoo_fraise_mini_90ml', COALESCE(p_data->>'yaourt_fraise_mini', 'En rupture'),
        'br_yogoo_fraise_maxi_318ml', COALESCE(p_data->>'yaourt_fraise_maxi', 'En rupture'),
        'br_yogoo_nature_maxi_318ml', COALESCE(p_data->>'yaourt_nature_maxi', 'En rupture'),
        'prix_respectes', COALESCE((p_data->>'yaourt_prix')::boolean, false)
      )
    ),
    'concurrence', jsonb_build_object(
      'presence_concurrents', COALESCE((p_data->>'conc_presence')::boolean, false),
      'evap', jsonb_build_object(
        'present', COALESCE((p_data->>'conc_evap_present')::boolean, false),
        'cowmilk', COALESCE((p_data->>'conc_evap_cowmilk')::boolean, false),
        'nido_150g', COALESCE((p_data->>'conc_evap_nido_150g')::boolean, false),
        'autre', COALESCE((p_data->>'conc_evap_autre')::boolean, false),
        'nom_concurrent', p_data->>'conc_evap_nom'
      ),
      'imp', jsonb_build_object(
        'present', COALESCE((p_data->>'conc_imp_present')::boolean, false),
        'nido', COALESCE((p_data->>'conc_imp_nido')::boolean, false),
        'laity', COALESCE((p_data->>'conc_imp_laity')::boolean, false),
        'top_lait', COALESCE((p_data->>'conc_imp_toplait')::boolean, false),
        'autre', COALESCE((p_data->>'conc_imp_autre')::boolean, false),
        'nom_concurrent', p_data->>'conc_imp_nom'
      ),
      'scm', jsonb_build_object(
        'present', COALESCE((p_data->>'conc_scm_present')::boolean, false),
        'top_saho', COALESCE((p_data->>'conc_scm_topsaho')::boolean, false),
        'autre', COALESCE((p_data->>'conc_scm_autre')::boolean, false),
        'nom_concurrent', p_data->>'conc_scm_nom'
      ),
      'uht', jsonb_build_object(
        'present', COALESCE((p_data->>'conc_uht_present')::boolean, false),
        'candia', COALESCE((p_data->>'conc_uht_candia')::boolean, false),
        'autre', COALESCE((p_data->>'conc_uht_autre')::boolean, false),
        'nom_concurrent', p_data->>'conc_uht_nom'
      )
    ),
    'visibilite', jsonb_build_object(
      'exterieure', jsonb_build_object(
        'presence_visibilite', COALESCE((p_data->>'vis_ext_presence')::boolean, false),
        'photo_branding', p_data->>'vis_ext_photo',
        'full_branding', COALESCE((p_data->>'vis_ext_full_branding')::boolean, false),
        'etat_branding', COALESCE(p_data->>'vis_ext_etat_branding', ''),
        'poster', COALESCE((p_data->>'vis_ext_poster')::boolean, false),
        'etat_poster', COALESCE(p_data->>'vis_ext_etat_poster', ''),
        'panneau_privilege', COALESCE((p_data->>'vis_ext_panneau')::boolean, false),
        'etat_panneau', COALESCE(p_data->>'vis_ext_etat_panneau', ''),
        'sign_board', COALESCE((p_data->>'vis_ext_signboard')::boolean, false),
        'etat_sign_board', COALESCE(p_data->>'vis_ext_etat_signboard', ''),
        'guirlande', COALESCE((p_data->>'vis_ext_guirlande')::boolean, false),
        'etat_guirlande', COALESCE(p_data->>'vis_ext_etat_guirlande', ''),
        'autre_branding', COALESCE((p_data->>'vis_ext_autre')::boolean, false),
        'etat_autre', COALESCE(p_data->>'vis_ext_etat_autre', '')
      ),
      'interieure', jsonb_build_object(
        'presence_visibilite', COALESCE((p_data->>'vis_int_presence')::boolean, false),
        'photo_visibilite', p_data->>'vis_int_photo',
        'hanger', COALESCE((p_data->>'vis_int_hanger')::boolean, false),
        'etat_hanger', COALESCE(p_data->>'vis_int_etat_hanger', ''),
        'tete_gondole', COALESCE((p_data->>'vis_int_tete_gondole')::boolean, false),
        'etat_tete_gondole', COALESCE(p_data->>'vis_int_etat_tete_gondole', ''),
        'maison_bonnet_rouge', COALESCE((p_data->>'vis_int_maison_br')::boolean, false),
        'etat_maison_br', COALESCE(p_data->>'vis_int_etat_maison_br', ''),
        'reglettes', COALESCE((p_data->>'vis_int_reglettes')::boolean, false),
        'etat_reglettes', COALESCE(p_data->>'vis_int_etat_reglettes', ''),
        'zone_chaude', COALESCE((p_data->>'vis_int_zone_chaude')::boolean, false),
        'etat_zone_chaude', COALESCE(p_data->>'vis_int_etat_zone_chaude', ''),
        'produits_frigo', COALESCE((p_data->>'vis_int_frigo')::boolean, false),
        'etat_frigo', COALESCE(p_data->>'vis_int_etat_frigo', ''),
        'presentoirs', COALESCE((p_data->>'vis_int_presentoirs')::boolean, false),
        'etat_presentoirs', COALESCE(p_data->>'vis_int_etat_presentoirs', ''),
        'bacs_pouch', COALESCE((p_data->>'vis_int_bacs')::boolean, false),
        'etat_bacs', COALESCE(p_data->>'vis_int_etat_bacs', ''),
        'autre_gt', COALESCE((p_data->>'vis_int_autre_gt')::boolean, false),
        'etat_autre_gt', COALESCE(p_data->>'vis_int_etat_autre_gt', ''),
        'habillage_rayon', COALESCE((p_data->>'vis_int_habillage')::boolean, false),
        'etat_habillage', COALESCE(p_data->>'vis_int_etat_habillage', ''),
        'merchandising', COALESCE((p_data->>'vis_int_merchandising')::boolean, false),
        'etat_merchandising', COALESCE(p_data->>'vis_int_etat_merchandising', ''),
        'autre_interieure', COALESCE((p_data->>'vis_int_autre')::boolean, false),
        'etat_autre_int', COALESCE(p_data->>'vis_int_etat_autre', '')
      ),
      'concurrence', jsonb_build_object(
        'presence_visibilite', COALESCE((p_data->>'vis_conc_presence')::boolean, false),
        'nido_exterieur', COALESCE((p_data->>'vis_conc_nido_ext')::boolean, false),
        'nido_interieur', COALESCE((p_data->>'vis_conc_nido_int')::boolean, false),
        'laity_exterieur', COALESCE((p_data->>'vis_conc_laity_ext')::boolean, false),
        'laity_interieur', COALESCE((p_data->>'vis_conc_laity_int')::boolean, false),
        'candia_exterieur', COALESCE((p_data->>'vis_conc_candia_ext')::boolean, false),
        'candia_interieur', COALESCE((p_data->>'vis_conc_candia_int')::boolean, false),
        'autre_exterieur', COALESCE((p_data->>'vis_conc_autre_ext')::boolean, false),
        'nom_concurrent_ext', p_data->>'vis_conc_nom_ext',
        'autre_interieur', COALESCE((p_data->>'vis_conc_autre_int')::boolean, false),
        'nom_concurrent_int', p_data->>'vis_conc_nom_int'
      )
    ),
    'actions', jsonb_build_object(
      'execution_visibilite', COALESCE((p_data->>'act_execution_vis')::boolean, false),
      'referencement_produits', COALESCE((p_data->>'act_referencement')::boolean, false),
      'execution_activites_promotionnelles', COALESCE((p_data->>'act_execution_promo')::boolean, false),
      'prospection_pdv', COALESCE((p_data->>'act_prospection')::boolean, false),
      'verification_fifo', COALESCE((p_data->>'act_fifo')::boolean, false),
      'rangement_produits', COALESCE((p_data->>'act_rangement')::boolean, false),
      'pose_affiches', COALESCE((p_data->>'act_affiches')::boolean, false),
      'pose_materiel_visibilite', COALESCE((p_data->>'act_materiel_vis')::boolean, false)
    )
  );
  -- Collect images
  v_images := ARRAY[]::TEXT[];
  IF p_data->>'vis_ext_photo' IS NOT NULL AND p_data->>'vis_ext_photo' != '' THEN
    v_images := array_append(v_images, p_data->>'vis_ext_photo');
  END IF;
  IF p_data->>'vis_int_photo' IS NOT NULL AND p_data->>'vis_int_photo' != '' THEN
    v_images := array_append(v_images, p_data->>'vis_int_photo');
  END IF;
  IF p_data->>'image' IS NOT NULL AND p_data->>'image' != '' THEN
    v_images := array_append(v_images, p_data->>'image');
  END IF;
  -- Auto-create PDV if it doesn't exist (placeholder with pdv_id)
  INSERT INTO public.pdv (pdv_id, nom_pdv)
  VALUES (v_pdv_id, 'PDV ' || v_pdv_id)
  ON CONFLICT (pdv_id) DO NOTHING;
  INSERT INTO public.visites (
    visite_id, pdv_id, date_visite, commercial, email,
    data, image_urls, sync_status
  ) VALUES (
    v_visite_id, v_pdv_id, v_date, v_commercial, v_email,
    v_visite_data, v_images, 'synced'
  )
  ON CONFLICT (visite_id) DO UPDATE SET
    pdv_id = EXCLUDED.pdv_id,
    date_visite = EXCLUDED.date_visite,
    commercial = EXCLUDED.commercial,
    email = EXCLUDED.email,
    data = EXCLUDED.data,
    image_urls = EXCLUDED.image_urls,
    updated_at = NOW();
END;
$$;
CREATE FUNCTION public.import_zone_secteur(p_secteur_id integer, p_zone text, p_secteur text, p_merchandiser text, p_email text, p_sales_rep text, p_email_sales_rep text, p_region text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  INSERT INTO public.zones_secteurs (id, zone, secteur, merchandiser, email_merchandiser, sales_rep, email_sales_rep, region)
  VALUES (p_secteur_id, p_zone, p_secteur, p_merchandiser, p_email, p_sales_rep, p_email_sales_rep, p_region)
  ON CONFLICT (id) DO UPDATE SET
    zone = EXCLUDED.zone,
    secteur = EXCLUDED.secteur,
    merchandiser = EXCLUDED.merchandiser,
    email_merchandiser = EXCLUDED.email_merchandiser,
    sales_rep = EXCLUDED.sales_rep,
    email_sales_rep = EXCLUDED.email_sales_rep,
    region = EXCLUDED.region;
END;
$$;
CREATE FUNCTION public.maj_telephone_contact(p_id uuid, p_telephone text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_moi_role   text;
  v_moi_terr   text[];
  v_cible      record;
  v_tel        text := nullif(btrim(coalesce(p_telephone, '')), '');
  v_chiffres   text;
  v_terr_cible text[];
begin
  if auth.uid() is null then
    raise exception 'Session expirée, reconnectez-vous';
  end if;
  if v_tel is null then
    raise exception 'Le numéro de téléphone est requis';
  end if;
  v_tel := left(v_tel, 50);
  v_chiffres := regexp_replace(v_tel, '[^0-9]', '', 'g');
  if length(v_chiffres) < 8 or length(v_chiffres) > 15 then
    raise exception 'Numéro illisible. Exemple attendu : 07 08 09 10 11';
  end if;
  select role,
         case
           when jsonb_typeof(territoires_assignes) = 'array' and jsonb_array_length(territoires_assignes) > 0
             then (select array_agg(t) from jsonb_array_elements_text(territoires_assignes) t where t <> '')
           when zone_assignee is not null and zone_assignee <> '' then array[zone_assignee]
           else array[]::text[]
         end
    into v_moi_role, v_moi_terr
  from public.profiles where id = auth.uid() and is_active = true;
  if v_moi_role is null then
    raise exception 'Compte inactif';
  end if;
  select id, role, commercial_id,
         case
           when jsonb_typeof(territoires_assignes) = 'array' and jsonb_array_length(territoires_assignes) > 0
             then (select array_agg(t) from jsonb_array_elements_text(territoires_assignes) t where t <> '')
           when zone_assignee is not null and zone_assignee <> '' then array[zone_assignee]
           else array[]::text[]
         end as terrs
    into v_cible
  from public.profiles where id = p_id;
  if v_cible.id is null then
    raise exception 'Contact introuvable';
  end if;
  if v_cible.id <> auth.uid() then
    if v_moi_role not in ('admin', 'superviseur', 'commercial') then
      raise exception 'Action réservée à l''encadrement';
    end if;
    if v_cible.role = 'admin' then
      raise exception 'Le numéro d''un administrateur se modifie dans l''administration';
    end if;
    if v_moi_role = 'commercial' then
      if v_cible.role <> 'merchandiser' then
        raise exception 'Vous ne pouvez corriger que le numéro d''un merchandiseur';
      end if;
      if coalesce(v_cible.commercial_id, '00000000-0000-0000-0000-000000000000'::uuid) <> auth.uid()
         and cardinality(v_moi_terr) > 0 then
        v_terr_cible := v_cible.terrs;
        if v_terr_cible is null or cardinality(v_terr_cible) = 0
           or not exists (
             select 1
             from public.territoires_etendus(v_moi_terr) e
             join unnest(v_terr_cible) c on upper(unaccent_safe(c)) = upper(unaccent_safe(e))
           ) then
          raise exception 'Ce merchandiseur n''est pas dans votre périmètre';
        end if;
      end if;
    end if;
  end if;
  update public.profiles set telephone = v_tel where id = p_id;
  return v_tel;
end $$;
CREATE FUNCTION public.materialiser_routing_jour(p_user_id uuid, p_date date) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_routing_id uuid;
  v_template_id uuid;
  v_nb integer;
begin
  select id into v_routing_id
  from routings
  where user_id = p_user_id and date_routing = p_date
  limit 1;
  if v_routing_id is not null then
    return v_routing_id;
  end if;
  -- Étapes du jour : toutes les règles applicables, exceptions PDV retirées.
  -- Une tournée peut agréger plusieurs règles (deux territoires le même jour) ;
  -- on trace la première comme origine.
  select count(*), min(x.template_id::text)::uuid
  into v_nb, v_template_id
  from (
    select r.id as template_id
    from routing_regles_du_jour(p_user_id, p_date) r
    join routing_template_pdv tp on tp.template_id = r.id
    where not exists (
      select 1 from routing_template_exception e
      where e.template_id = r.id
        and e.pdv_id = tp.pdv_id
        and p_date between e.date_debut and e.date_fin
    )
  ) x;
  -- Aucune étape : on ne crée pas de tournée vide, le merchandiser verrait une
  -- journée « planifiée » sans contenu.
  if v_nb = 0 then
    return null;
  end if;
  insert into routings(user_id, date_routing, status, source, template_id, created_by)
  values (p_user_id, p_date, 'pending', 'regle', v_template_id, p_user_id)
  returning id into v_routing_id;
  -- distinct on (pdv_id) : un même PDV présent dans deux règles du même jour
  -- ne doit donner qu'une étape, sinon le merchandiser le visite deux fois.
  insert into routing_pdv(routing_id, pdv_id, position_order, objectifs, status)
  select v_routing_id, e.pdv_id, row_number() over (order by e.ordre), e.objectifs, 'pending'
  from (
    select distinct on (etape.pdv_id) etape.pdv_id, etape.objectifs, etape.ordre
    from (
      select
        tp.pdv_id,
        coalesce(tp.objectifs, '{}'::jsonb) as objectifs,
        row_number() over (order by r.created_at, tp.position_order) as ordre
      from routing_regles_du_jour(p_user_id, p_date) r
      join routing_template_pdv tp on tp.template_id = r.id
      where not exists (
        select 1 from routing_template_exception e2
        where e2.template_id = r.id
          and e2.pdv_id = tp.pdv_id
          and p_date between e2.date_debut and e2.date_fin
      )
    ) etape
    order by etape.pdv_id, etape.ordre
  ) e;
  return v_routing_id;
end;
$$;
CREATE FUNCTION public.materialiser_routings_periode(p_user_id uuid, p_date_debut date, p_date_fin date) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_jour date;
  v_cree integer := 0;
begin
  v_jour := p_date_debut;
  while v_jour <= p_date_fin loop
    if materialiser_routing_jour(p_user_id, v_jour) is not null then
      v_cree := v_cree + 1;
    end if;
    v_jour := v_jour + 1;
  end loop;
  return v_cree;
end;
$$;
CREATE FUNCTION public.notifier_action_assignee() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
declare
  v_url   text;
  v_token text;
begin
  -- Rien à notifier si l'action n'est assignée à personne, ou si la mise à jour
  -- ne change pas l'assigné (changement de statut, de commentaire…).
  if new.assigne_a is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.assigne_a is not distinct from new.assigne_a then
    return new;
  end if;
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'edge_notifier_action_url';
  select decrypted_secret into v_token
  from vault.decrypted_secrets where name = 'edge_notifier_action_token';
  if v_url is null or v_token is null then
    return new;
  end if;
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-notifier-secret', v_token
    ),
    body := jsonb_build_object('action_id', new.id),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;
COMMENT ON FUNCTION public.notifier_action_assignee() IS 'Prévient la fonction Edge notifier-action qu''une action vient d''être assignée. Silencieux si les secrets Vault ne sont pas posés.';
CREATE FUNCTION public.pdv_comparaison_periodes(p_pdv_id text, p_debut1 date, p_fin1 date, p_debut2 date, p_fin2 date) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  with h as (
    select * from pdv_historique_perfect_store(p_pdv_id)
  ),
  agg as (
    select
      n,
      count(*) as visites,
      round(avg(score_global), 1) as score_moyen,
      round(avg(dispo_rayon), 1) as dispo_moyenne,
      round(avg(visibilite), 1) as visibilite_moyenne,
      round(avg(promotion), 1) as promotion_moyenne,
      round(100.0 * count(*) filter (where niveau is not null) / nullif(count(*), 0), 1) as perfect_store_pct
    from (
      select 1 as n, h.* from h where h.date_visite >= p_debut1::timestamptz and h.date_visite < (p_fin1 + 1)::timestamptz
      union all
      select 2 as n, h.* from h where h.date_visite >= p_debut2::timestamptz and h.date_visite < (p_fin2 + 1)::timestamptz
    ) x
    group by n
  )
  select jsonb_build_object(
    'periode1', coalesce((select to_jsonb(a) - 'n' from agg a where n = 1), '{"visites":0}'::jsonb),
    'periode2', coalesce((select to_jsonb(a) - 'n' from agg a where n = 2), '{"visites":0}'::jsonb)
  );
$$;
CREATE FUNCTION public.pdv_dans_perimetre(p_pdv_id text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with moi as (
    select pr.role,
      case
        when jsonb_typeof(pr.territoires_assignes) = 'array'
             and jsonb_array_length(pr.territoires_assignes) > 0
          then (select array_agg(t) from jsonb_array_elements_text(pr.territoires_assignes) t where t <> '')
        when pr.zone_assignee is not null and pr.zone_assignee <> ''
          then array[pr.zone_assignee]
        else array[]::text[]
      end as territoires,
      case
        when jsonb_typeof(pr.quartiers_assignes) = 'array'
          then (select coalesce(array_agg(q), array[]::text[]) from jsonb_array_elements_text(pr.quartiers_assignes) q where q <> '')
        else array[]::text[]
      end as quartiers
    from public.profiles pr
    where pr.id = auth.uid() and pr.is_active = true
  )
  select exists (
    select 1
    from moi m
    left join public.pdv p on p.pdv_id = p_pdv_id
    where m.role in ('admin','superviseur')
       or (
         -- Seul le commercial encadre par territoire. Le merchandiseur est
         -- explicitement exclu : c'est le cloisonnement demandé.
         m.role = 'commercial'
         and p.pdv_id is not null
         and (cardinality(m.territoires) = 0 or p.zone = any(m.territoires))
         and (cardinality(m.quartiers) = 0 or p.quartier is null or p.quartier = any(m.quartiers))
       )
  );
$$;
COMMENT ON FUNCTION public.pdv_dans_perimetre(p_pdv_id text) IS 'PDV dans le périmètre d''ENCADREMENT de l''appelant : tout le réseau pour admin/superviseur, les territoires et quartiers assignés pour un commercial, FAUX pour un merchandiseur.';
CREATE FUNCTION public.pdv_dans_perimetre_commercial(p_pdv_id text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.role_actif_courant() = 'commercial' and p_pdv_id in (select public.pdv_ids_perimetre());
$$;
CREATE FUNCTION public.pdv_fraicheur_filtre(p_division text DEFAULT NULL::text, p_territoire text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_distributeur text DEFAULT NULL::text, p_etat text DEFAULT NULL::text, p_date_fin date DEFAULT NULL::date, p_fenetre_mois integer DEFAULT NULL::integer, p_suivi boolean DEFAULT NULL::boolean) RETURNS TABLE(pdv_id text, nom_pdv text, zone text, quartier text, sous_categorie_pdv text, distributor_name text, derniere_visite timestamp with time zone, derniere_visite_statut text, jours_depuis integer, frequence_jours integer, etat text, suivi boolean, niveau text, score_global numeric, visite_id uuid)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    SET work_mem TO '16MB'
    AS $$
declare
  v_ref     date := coalesce(p_date_fin, current_date);
  v_fenetre integer := coalesce(p_fenetre_mois, fenetre_suivi_mois());
begin
  return query
  -- plpgsql et non sql : une fonction SQL planifie sur des paramètres
  -- génériques et choisissait des nested loops (7 s à 70 s selon les bornes) ;
  -- plpgsql planifie avec les valeurs réelles. `materialized` évite en plus
  -- l'inlining des CTE référencées une fois. Mesuré : ~0,35 s réseau entier.
  with scope_pdv as materialized (
    select p.pdv_id, p.nom_pdv, p.zone, p.quartier, p.sous_categorie_pdv, p.distributor_name,
           (select f.jours from frequence_visite f
             where (f.zone is null or f.zone = p.zone)
               and (f.type_pdv is null or f.type_pdv = p.sous_categorie_pdv)
             order by (f.zone is not null)::int + (f.type_pdv is not null)::int desc,
                      (f.type_pdv is not null)::int desc
             limit 1) as frequence_jours
    from pdv p
    left join territoire t on t.nom = p.zone
    left join sous_region sr on sr.code = t.sous_region_code
    left join region rg on rg.code = sr.region_code
    where coalesce(p.is_active, true)
      and (p_division is null or p_division = '' or rg.nom_affichage = p_division)
      and (p_territoire is null or p_territoire = '' or p.zone = p_territoire)
      and (p_area is null or p_area = '' or p.area_code = p_area or p.quartier = p_area)
      and (p_distributeur is null or p_distributeur = '' or p.distributor_name = p_distributeur)
  ),
  -- Sur TOUTES les visites (26k lignes, agrégat trivial), jointes ensuite au
  -- périmètre par hash. Un « where pdv_id in (select … from scope_pdv) » ici
  -- devenait un nested loop × CTE scan dans la fonction (26k × 25k = 70 s).
  -- Bornée PAR LE HAUT seulement : voir l'en-tête, point 3.
  derniere as materialized (
    select distinct on (v.pdv_id) v.pdv_id, v.id as visite_id, v.date_visite, v.status
    from visites v
    where p_date_fin is null or v.date_visite < (p_date_fin + 1)::timestamptz
    order by v.pdv_id, v.date_visite desc
  ),
  etat as materialized (
    select s.*, d.visite_id, d.date_visite, d.status,
           case when d.date_visite is null then null
                else (v_ref - d.date_visite::date) end as jours_depuis,
           case
             when d.date_visite is null then 'jamais_visite'
             when (v_ref - d.date_visite::date) > coalesce(s.frequence_jours, 7) then 'en_retard'
             else 'a_jour'
           end as etat,
           coalesce(d.date_visite::date >= (v_ref - make_interval(months => v_fenetre)), false) as suivi
    from scope_pdv s
    left join derniere d on d.pdv_id = s.pdv_id
  )
  select e.pdv_id, e.nom_pdv, e.zone, e.quartier, e.sous_categorie_pdv, e.distributor_name,
         e.date_visite, e.status, e.jours_depuis, e.frequence_jours, e.etat, e.suivi,
         r.niveau, r.score_global, e.visite_id
  from etat e
  left join resultat_perfect_store r on r.visite_id = e.visite_id
  where (p_etat is null or p_etat = '' or e.etat = p_etat)
    and (p_suivi is null or e.suivi = p_suivi)
  order by case e.etat when 'jamais_visite' then 0 when 'en_retard' then 1 else 2 end,
           e.jours_depuis desc nulls first, e.nom_pdv;
end $$;
CREATE FUNCTION public.pdv_historique_perfect_store(p_pdv_id text) RETURNS TABLE(visite_id uuid, date_visite timestamp with time zone, commercial text, niveau text, score_global numeric, dispo_rayon numeric, visibilite numeric, promotion numeric, assortiment numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select v.id, v.date_visite, v.commercial,
         r.niveau, r.score_global, r.dispo_rayon, r.visibilite, r.promotion, r.assortiment
  from visites v
  left join resultat_perfect_store r on r.visite_id = v.id
  where v.pdv_id = p_pdv_id
  order by v.date_visite;
$$;
CREATE FUNCTION public.pdv_ids_perimetre() RETURNS SETOF text
    LANGUAGE sql STABLE SECURITY DEFINER ROWS 2000
    SET search_path TO 'public'
    AS $$
  with moi as materialized (
    select pr.role,
      case
        when jsonb_typeof(pr.territoires_assignes) = 'array' and jsonb_array_length(pr.territoires_assignes) > 0
          then (select array_agg(t) from jsonb_array_elements_text(pr.territoires_assignes) t where t <> '')
        when pr.zone_assignee is not null and pr.zone_assignee <> '' then array[pr.zone_assignee]
        else array[]::text[]
      end as territoires,
      case
        when jsonb_typeof(pr.quartiers_assignes) = 'array'
          then (select coalesce(array_agg(q), array[]::text[]) from jsonb_array_elements_text(pr.quartiers_assignes) q where q <> '')
        else array[]::text[]
      end as quartiers
    from public.profiles pr where pr.id = auth.uid() and pr.is_active = true
  ),
  terr as materialized (
    select m.territoires, m.quartiers,
           coalesce((select array_agg(x) from public.territoires_etendus(m.territoires) x), array[]::text[]) as noms
    from moi m
  )
  -- Deux branches sans OR sur une constante : le planificateur utilise l'index.
  select p.pdv_id
  from terr t
  join public.pdv p on p.zone = any(t.noms)
  where cardinality(t.territoires) > 0
    and (cardinality(t.quartiers) = 0 or p.quartier is null or p.quartier = any(t.quartiers))
  union all
  select p.pdv_id
  from terr t
  join public.pdv p on true
  where cardinality(t.territoires) = 0
    and (cardinality(t.quartiers) = 0 or p.quartier is null or p.quartier = any(t.quartiers));
$$;
CREATE FUNCTION public.pdv_link_referentiels() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare v_cnt integer; v_area text;
begin
  if new.territory_code is null and new.zone is not null then
    select t.code into new.territory_code
    from public.geo_territories t
    where upper(btrim(t.name)) = upper(btrim(new.zone)) limit 1;
  end if;
  if new.distributor_name is null and new.territory_code is not null
     and (new.canal is null or (new.canal not ilike '%modern%' and upper(btrim(new.canal)) <> 'MT')) then
    select a.distributor_name into new.distributor_name
    from public.geo_areas a
    where a.territory_code = new.territory_code
      and a.distributor_name is not null
      and a.distributor_name not in ('A POURVOIR','NOT AVAILABLE','NICE SERVICE','OMNI RETAIL')
    group by a.distributor_name
    order by count(*) desc, a.distributor_name limit 1;
  end if;
  if new.area_code is null and new.territory_code is not null and new.quartier is not null then
    select count(*), min(a.area_code) into v_cnt, v_area
    from public.geo_areas a
    where a.territory_code = new.territory_code
      and a.area_name ilike '%' || new.quartier || '%';
    if v_cnt = 1 then new.area_code := v_area; end if;
  end if;
  return new;
end;
$$;
CREATE FUNCTION public.perfect_store_evolution_filtre(p_division text DEFAULT NULL::text, p_territoire text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_distributeur text DEFAULT NULL::text, p_date_debut date DEFAULT NULL::date, p_date_fin date DEFAULT NULL::date) RETURNS TABLE(date text, perfect_stores bigint, pdv_scores bigint, perfect_store_pct numeric)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    SET work_mem TO '16MB'
    AS $$
  with scope_pdv as (
    select p.pdv_id
    from pdv p
    left join territoire t on t.nom = p.zone
    left join sous_region sr on sr.code = t.sous_region_code
    left join region rg on rg.code = sr.region_code
    where (p_division is null or p_division = '' or rg.nom_affichage = p_division)
      and (p_territoire is null or p_territoire = '' or p.zone = p_territoire)
      and (p_area is null or p_area = '' or p.area_code = p_area or p.quartier = p_area)
      and (p_distributeur is null or p_distributeur = '' or p.distributor_name = p_distributeur)
  ),
  scored as (
    select r.niveau, r.calcule_le, v.pdv_id, v.date_visite,
           date_trunc('day', v.date_visite) as jour
    from resultat_perfect_store r
    join visites v on v.id = r.visite_id
    where v.pdv_id in (select pdv_id from scope_pdv)
      and (p_date_debut is null or v.date_visite >= p_date_debut::timestamptz)
      and (p_date_fin is null or v.date_visite < (p_date_fin + 1)::timestamptz)
  ),
  dernier_du_jour as (
    select distinct on (s.jour, s.pdv_id) s.jour, s.pdv_id, s.niveau
    from scored s
    order by s.jour, s.pdv_id, s.date_visite desc, s.calcule_le desc
  )
  select
    to_char(d.jour, 'YYYY-MM-DD') as date,
    count(*) filter (where d.niveau is not null) as perfect_stores,
    count(*) as pdv_scores,
    round(100.0 * count(*) filter (where d.niveau is not null) / nullif(count(*), 0), 1) as perfect_store_pct
  from dernier_du_jour d
  group by d.jour
  order by 1;
$$;
CREATE FUNCTION public.perfect_store_liste_filtre(p_niveau text DEFAULT NULL::text, p_type text DEFAULT NULL::text, p_page integer DEFAULT 1, p_per_page integer DEFAULT 10, p_order text DEFAULT 'date'::text, p_division text DEFAULT NULL::text, p_territoire text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_distributeur text DEFAULT NULL::text, p_date_debut date DEFAULT NULL::date, p_date_fin date DEFAULT NULL::date, p_search text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    SET work_mem TO '16MB'
    AS $$
  with latest as (
    select distinct on (v.pdv_id)
      r.visite_id, v.pdv_id, p.nom_pdv,
      coalesce(p.sous_categorie_pdv, 'Non renseigné') as type_pdv,
      p.zone, v.date_visite, v.commercial,
      coalesce(r.niveau, 'NON CONFORME') as niveau,
      r.score_global, r.dispo_rayon, r.assortiment, r.visibilite, r.promotion
    from visites v
    join resultat_perfect_store r on r.visite_id = v.id
    join pdv p on p.pdv_id = v.pdv_id
    where v.date_visite >= coalesce(p_date_debut::timestamptz, '-infinity'::timestamptz)
      and v.date_visite < coalesce((p_date_fin + 1)::timestamptz, 'infinity'::timestamptz)
      and (p_territoire is null or p_territoire = '' or p.zone = p_territoire)
      and (p_area is null or p_area = '' or p.area_code = p_area or p.quartier = p_area)
      and (p_distributeur is null or p_distributeur = '' or p.distributor_name = p_distributeur)
      and (p_division is null or p_division = '' or exists (
            select 1
            from territoire t
            join sous_region sr on sr.code = t.sous_region_code
            join region rg on rg.code = sr.region_code
            where t.nom = p.zone and rg.nom_affichage = p_division))
    order by v.pdv_id, v.date_visite desc, r.calcule_le desc
  ),
  filtre as (
    select * from latest l
    where (p_niveau is null or p_niveau = ''
           or (p_niveau = 'CONFORMES' and l.niveau <> 'NON CONFORME')
           or l.niveau = p_niveau)
      and (p_type is null or p_type = '' or l.type_pdv = p_type)
      -- Mêmes colonnes que la recherche de l'ancien chemin « vue » :
      -- nom, code PDV, zone.
      and (p_search is null or btrim(p_search) = ''
           or l.nom_pdv ilike '%' || btrim(p_search) || '%'
           or l.pdv_id ilike '%' || btrim(p_search) || '%'
           or l.zone ilike '%' || btrim(p_search) || '%')
  ),
  page as (
    select * from filtre
    order by
      case when p_order = 'score' then score_global end desc nulls last,
      date_visite desc
    limit greatest(coalesce(p_per_page, 10), 1)
    offset greatest(coalesce(p_page, 1) - 1, 0) * greatest(coalesce(p_per_page, 10), 1)
  )
  select jsonb_build_object(
    'total', (select count(*) from filtre),
    'items', coalesce((
      select jsonb_agg(to_jsonb(pg)
        order by case when p_order = 'score' then pg.score_global end desc nulls last, pg.date_visite desc)
      from page pg
    ), '[]'::jsonb)
  );
$$;
CREATE TABLE public.element_visibilite (
    id bigint NOT NULL,
    segment text NOT NULL,
    code text NOT NULL,
    nom text NOT NULL,
    pilier text NOT NULL,
    emplacement text NOT NULL,
    optionnel boolean DEFAULT false NOT NULL,
    CONSTRAINT element_visibilite_emplacement_check CHECK ((emplacement = ANY (ARRAY['exterieure'::text, 'interieure'::text, 'promotion'::text]))),
    CONSTRAINT element_visibilite_pilier_check CHECK ((pilier = ANY (ARRAY['visibilite'::text, 'promotion'::text]))),
    CONSTRAINT element_visibilite_segment_check CHECK ((segment = ANY (ARRAY['boutique'::text, 'superette'::text, 'table_top'::text, 'pushcart'::text, 'porridge'::text, 'kiosque_aboki'::text, 'mt'::text])))
);
CREATE TABLE public.niveau_perfect_store (
    code text NOT NULL,
    rang integer NOT NULL,
    dispo_rayon_min numeric,
    visibilite_min numeric,
    promotion_min numeric
);
CREATE TABLE public.pdv (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pdv_id text NOT NULL,
    nom_pdv text NOT NULL,
    canal text DEFAULT 'General trade'::text,
    categorie_pdv text DEFAULT 'Point de vente détail'::text,
    sous_categorie_pdv text DEFAULT 'Boutique C'::text,
    autre_sous_categorie text,
    region text,
    zone text,
    quartier text,
    geolocation_lat double precision,
    geolocation_lng double precision,
    rayon_geofence integer DEFAULT 200,
    adressage text,
    image_url text,
    date_creation date,
    ajoute_par text,
    jour_routing text,
    position_routing integer,
    canal_routing text,
    sales_rep_routing text,
    mdm text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    territory_code text,
    area_code text,
    distributor_name text,
    objectif_perfect_store text,
    gps_source text,
    gps_precision_m integer,
    gps_maj_par uuid,
    gps_maj_le timestamp with time zone,
    CONSTRAINT pdv_gps_source_valide CHECK (((gps_source IS NULL) OR (gps_source = ANY (ARRAY['dms'::text, 'dms-absent'::text, 'dms-depot'::text, 'terrain'::text, 'admin'::text])))),
    CONSTRAINT pdv_objectif_perfect_store_check CHECK ((objectif_perfect_store = ANY (ARRAY['FLAGSHIP'::text, 'VIP'::text, 'CORE'::text, 'BASIC'::text])))
);
COMMENT ON COLUMN public.pdv.gps_source IS 'Origine des coordonnées : dms, terrain (relevé par un merchandiser), admin. Sans coordonnées : dms-absent (absentes du DMS) ou dms-depot (point partagé par 10 clients et plus, écarté).';
COMMENT ON COLUMN public.pdv.gps_precision_m IS 'Précision annoncée par le téléphone au relevé terrain, en mètres.';
COMMENT ON COLUMN public.pdv.gps_maj_par IS 'Auteur du dernier relevé de coordonnées.';
COMMENT ON COLUMN public.pdv.gps_maj_le IS 'Date du dernier relevé de coordonnées.';
CREATE TABLE public.region (
    id bigint NOT NULL,
    code text NOT NULL,
    nom text NOT NULL,
    nom_affichage text,
    pays_code text NOT NULL
);
CREATE TABLE public.resultat_perfect_store (
    visite_id uuid NOT NULL,
    base_calcul text DEFAULT 'taux_vente'::text NOT NULL,
    dispo_rayon_evap numeric,
    dispo_rayon_imp numeric,
    dispo_rayon_scm numeric,
    dispo_rayon numeric,
    assortiment numeric,
    sku_presents integer,
    heros_presents boolean,
    visibilite numeric,
    promotion numeric,
    score_global numeric,
    niveau text,
    calcule_le timestamp with time zone DEFAULT now() NOT NULL,
    presence_rayon numeric,
    presence_rayon_evap numeric,
    presence_rayon_imp numeric,
    presence_rayon_scm numeric,
    CONSTRAINT resultat_perfect_store_base_calcul_check CHECK ((base_calcul = ANY (ARRAY['taux_vente'::text, 'taux_revu'::text])))
);
COMMENT ON COLUMN public.resultat_perfect_store.presence_rayon IS 'Distribution numérique pondérée : part des SKU avec quantité >= 1. À opposer à dispo_rayon (quantité >= seuil_disponibilite).';
CREATE TABLE public.segment_visibilite_type_pdv (
    type_pdv_id bigint NOT NULL,
    segment text NOT NULL,
    CONSTRAINT segment_visibilite_type_pdv_segment_check CHECK ((segment = ANY (ARRAY['boutique'::text, 'superette'::text, 'table_top'::text, 'pushcart'::text, 'porridge'::text, 'kiosque_aboki'::text, 'mt'::text])))
);
CREATE TABLE public.sous_region (
    id bigint NOT NULL,
    code text NOT NULL,
    nom text NOT NULL,
    nom_affichage text,
    region_code text NOT NULL
);
CREATE TABLE public.standard_visibilite (
    segment text NOT NULL,
    niveau_perfect_store text NOT NULL,
    element_visibilite_id bigint NOT NULL,
    requis boolean DEFAULT false NOT NULL,
    CONSTRAINT standard_visibilite_niveau_perfect_store_check CHECK ((niveau_perfect_store = ANY (ARRAY['flagship'::text, 'vip'::text, 'core'::text, 'basic'::text])))
);
CREATE TABLE public.territoire (
    id bigint NOT NULL,
    code text NOT NULL,
    nom text NOT NULL,
    sous_region_code text NOT NULL
);
CREATE TABLE public.type_pdv (
    id bigint NOT NULL,
    categorie_pdv_id bigint NOT NULL,
    nom text NOT NULL,
    nom_fr text
);
CREATE TABLE public.visites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    visite_id text NOT NULL,
    pdv_id text,
    user_id uuid,
    date_visite timestamp with time zone NOT NULL,
    commercial text,
    email text,
    geolocation_lat double precision,
    geolocation_lng double precision,
    geofence_validated boolean DEFAULT false,
    precision_gps double precision,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    image_urls text[] DEFAULT '{}'::text[],
    sync_status text DEFAULT 'synced'::text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    status text DEFAULT 'soumis'::text NOT NULL,
    synced_at timestamp with time zone,
    CONSTRAINT visites_status_check CHECK ((status = ANY (ARRAY['soumis'::text, 'validé'::text, 'rejeté'::text]))),
    CONSTRAINT visites_sync_status_check CHECK ((sync_status = ANY (ARRAY['synced'::text, 'pending'::text, 'error'::text])))
);
CREATE VIEW public.v_perfect_store_manques WITH (security_invoker='on') AS
 WITH base AS (
         SELECT r.visite_id,
            v.pdv_id,
            v.data,
            r.niveau AS niveau_actuel,
            r.dispo_rayon,
            r.assortiment,
            COALESCE(n.rang, 0) AS rang_actuel,
            p.nom_pdv,
            p.sous_categorie_pdv AS type_pdv,
            p.zone,
            p.quartier AS secteur,
            p.distributor_name,
            rg.nom_affichage AS division
           FROM ((((((public.resultat_perfect_store r
             JOIN public.visites v ON ((v.id = r.visite_id)))
             JOIN public.pdv p ON ((p.pdv_id = v.pdv_id)))
             LEFT JOIN public.niveau_perfect_store n ON ((n.code = r.niveau)))
             LEFT JOIN public.territoire t ON ((t.nom = p.zone)))
             LEFT JOIN public.sous_region sr ON ((sr.code = t.sous_region_code)))
             LEFT JOIN public.region rg ON ((rg.code = sr.region_code)))
        ), resolu AS (
         SELECT b.visite_id,
            b.pdv_id,
            b.data,
            b.niveau_actuel,
            b.dispo_rayon,
            b.assortiment,
            b.rang_actuel,
            b.nom_pdv,
            b.type_pdv,
            b.zone,
            b.secteur,
            b.distributor_name,
            b.division,
            sv.segment AS vis_segment
           FROM ((base b
             LEFT JOIN LATERAL ( SELECT c_1.id,
                    c_1.categorie_pdv_id,
                    c_1.nom
                   FROM public.type_pdv c_1
                  WHERE (regexp_replace(TRIM(BOTH FROM c_1.nom), '\s+'::text, ' '::text, 'g'::text) = regexp_replace(TRIM(BOTH FROM b.type_pdv), '\s+'::text, ' '::text, 'g'::text))
                  ORDER BY (c_1.nom = b.type_pdv) DESC
                 LIMIT 1) tp ON (true))
             LEFT JOIN public.segment_visibilite_type_pdv sv ON ((sv.type_pdv_id = tp.id)))
        ), cible AS (
         SELECT r.visite_id,
            r.pdv_id,
            r.data,
            r.niveau_actuel,
            r.dispo_rayon,
            r.assortiment,
            r.rang_actuel,
            r.nom_pdv,
            r.type_pdv,
            r.zone,
            r.secteur,
            r.distributor_name,
            r.division,
            r.vis_segment,
            nt.code AS niveau_cible,
            nt.dispo_rayon_min,
                CASE
                    WHEN (nt.code ~~* 'FLAGSHIP%'::text) THEN 'flagship'::text
                    WHEN (nt.code ~~* 'VIP%'::text) THEN 'vip'::text
                    WHEN (nt.code ~~* 'CORE%'::text) THEN 'core'::text
                    ELSE 'basic'::text
                END AS key_cible
           FROM (resolu r
             JOIN public.niveau_perfect_store nt ON ((nt.rang = (r.rang_actuel + 1))))
        )
 SELECT visite_id,
    pdv_id,
    nom_pdv,
    type_pdv,
    division,
    zone,
    secteur AS quartier,
    distributor_name,
    niveau_actuel,
    niveau_cible,
    (dispo_rayon < dispo_rayon_min) AS dispo_manque,
    dispo_rayon,
    dispo_rayon_min,
    ((assortiment IS NOT NULL) AND (assortiment < (100)::numeric)) AS assortiment_manque,
    ( SELECT COALESCE(array_agg(e.nom ORDER BY e.nom), '{}'::text[]) AS "coalesce"
           FROM (public.standard_visibilite s
             JOIN public.element_visibilite e ON ((e.id = s.element_visibilite_id)))
          WHERE ((s.segment = c.vis_segment) AND (s.niveau_perfect_store = c.key_cible) AND s.requis AND (NOT e.optionnel) AND (e.pilier = 'visibilite'::text) AND (NOT public.element_visibilite_observe(c.data, e.code)))) AS visibilite_manques,
    ( SELECT COALESCE(array_agg(e.nom ORDER BY e.nom), '{}'::text[]) AS "coalesce"
           FROM (public.standard_visibilite s
             JOIN public.element_visibilite e ON ((e.id = s.element_visibilite_id)))
          WHERE ((s.segment = c.vis_segment) AND (s.niveau_perfect_store = c.key_cible) AND s.requis AND (NOT e.optionnel) AND (e.pilier = 'promotion'::text) AND COALESCE((((c.data -> 'visibilite'::text) ->> 'promotion_applicable'::text))::boolean, false) AND (NOT public.element_visibilite_observe(c.data, e.code)))) AS promotion_manques
   FROM cible c;
CREATE FUNCTION public.perfect_store_manques_filtre(p_division text DEFAULT NULL::text, p_territoire text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_distributeur text DEFAULT NULL::text, p_date_debut date DEFAULT NULL::date, p_date_fin date DEFAULT NULL::date, p_limit integer DEFAULT 50) RETURNS SETOF public.v_perfect_store_manques
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    SET work_mem TO '16MB'
    AS $$
  with derniere as (
    select distinct on (v.pdv_id) v.id as visite_id, v.pdv_id
    from visites v
    where (p_date_debut is null or v.date_visite >= p_date_debut::timestamptz)
      and (p_date_fin is null or v.date_visite < (p_date_fin + 1)::timestamptz)
    order by v.pdv_id, v.date_visite desc
  ),
  -- Les 50 visites retenues, avec les seules colonnes utiles au tri et aux
  -- filtres. Mêmes jointures que la vue (division via territoire → sous-région
  -- → région ; niveau cible = rang actuel + 1, donc un PDV au niveau maximal
  -- n'a pas de « niveau supérieur » et n'apparaît pas, comme dans la vue).
  candidats as (
    select d.visite_id,
           r.niveau as niveau_actuel,
           (r.dispo_rayon < nt.dispo_rayon_min) as dispo_manque
    from derniere d
    join resultat_perfect_store r on r.visite_id = d.visite_id
    join pdv p on p.pdv_id = d.pdv_id
    left join niveau_perfect_store n on n.code = r.niveau
    join niveau_perfect_store nt on nt.rang = coalesce(n.rang, 0) + 1
    left join territoire t on t.nom = p.zone
    left join sous_region sr on sr.code = t.sous_region_code
    left join region rg on rg.code = sr.region_code
    where (p_division is null or p_division = '' or rg.nom_affichage = p_division)
      and (p_territoire is null or p_territoire = '' or p.zone = p_territoire)
      and (p_area is null or p_area = '' or p.quartier = p_area)
      and (p_distributeur is null or p_distributeur = '' or p.distributor_name = p_distributeur)
    -- Les moins conformes d'abord : non conformes (niveau null), puis dispo manquante.
    order by r.niveau asc nulls first, (r.dispo_rayon < nt.dispo_rayon_min) desc
    limit greatest(coalesce(p_limit, 50), 1)
  ),
  -- Ci-dessous : corps de v_perfect_store_manques, démarré depuis `candidats`.
  base as (
    select r.visite_id, v.pdv_id, v.data, r.niveau as niveau_actuel, r.dispo_rayon, r.assortiment,
           coalesce(n.rang, 0) as rang_actuel, p.nom_pdv, p.sous_categorie_pdv as type_pdv, p.zone,
           p.quartier as secteur, p.distributor_name, rg.nom_affichage as division,
           c.niveau_actuel as tri_niveau, c.dispo_manque as tri_dispo
    from candidats c
    join resultat_perfect_store r on r.visite_id = c.visite_id
    join visites v on v.id = r.visite_id
    join pdv p on p.pdv_id = v.pdv_id
    left join niveau_perfect_store n on n.code = r.niveau
    left join territoire t on t.nom = p.zone
    left join sous_region sr on sr.code = t.sous_region_code
    left join region rg on rg.code = sr.region_code
  ),
  resolu as (
    select b.*, sv.segment as vis_segment
    from base b
    left join lateral (
      select c_1.id
      from type_pdv c_1
      where regexp_replace(trim(c_1.nom), '\s+', ' ', 'g') = regexp_replace(trim(b.type_pdv), '\s+', ' ', 'g')
      order by (c_1.nom = b.type_pdv) desc
      limit 1
    ) tp on true
    left join segment_visibilite_type_pdv sv on sv.type_pdv_id = tp.id
  ),
  cible as (
    select r.*, nt.code as niveau_cible, nt.dispo_rayon_min,
           case
             when nt.code ilike 'FLAGSHIP%' then 'flagship'
             when nt.code ilike 'VIP%' then 'vip'
             when nt.code ilike 'CORE%' then 'core'
             else 'basic'
           end as key_cible
    from resolu r
    join niveau_perfect_store nt on nt.rang = r.rang_actuel + 1
  )
  select c.visite_id, c.pdv_id, c.nom_pdv, c.type_pdv, c.division, c.zone, c.secteur as quartier,
         c.distributor_name, c.niveau_actuel, c.niveau_cible,
         c.dispo_rayon < c.dispo_rayon_min as dispo_manque, c.dispo_rayon, c.dispo_rayon_min,
         c.assortiment is not null and c.assortiment < 100::numeric as assortiment_manque,
         (select coalesce(array_agg(e.nom order by e.nom), '{}'::text[])
            from standard_visibilite s
            join element_visibilite e on e.id = s.element_visibilite_id
           where s.segment = c.vis_segment and s.niveau_perfect_store = c.key_cible and s.requis
             and not e.optionnel and e.pilier = 'visibilite'
             and not element_visibilite_observe(c.data, e.code)) as visibilite_manques,
         (select coalesce(array_agg(e.nom order by e.nom), '{}'::text[])
            from standard_visibilite s
            join element_visibilite e on e.id = s.element_visibilite_id
           where s.segment = c.vis_segment and s.niveau_perfect_store = c.key_cible and s.requis
             and not e.optionnel and e.pilier = 'promotion'
             and coalesce(((c.data -> 'visibilite') ->> 'promotion_applicable')::boolean, false)
             and not element_visibilite_observe(c.data, e.code)) as promotion_manques
  from cible c
  order by c.tri_niveau asc nulls first, c.tri_dispo desc;
$$;
CREATE FUNCTION public.perfect_store_par_type_filtre(p_division text DEFAULT NULL::text, p_territoire text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_distributeur text DEFAULT NULL::text, p_date_debut date DEFAULT NULL::date, p_date_fin date DEFAULT NULL::date) RETURNS TABLE(type_pdv text, pdv_scores bigint, pdv_perfect_stores bigint, perfect_store_pct numeric, score_global_moyen_pct numeric, visites_scorees bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    SET work_mem TO '16MB'
    AS $$
  with scope_pdv as (
    select p.pdv_id
    from pdv p
    left join territoire t on t.nom = p.zone
    left join sous_region sr on sr.code = t.sous_region_code
    left join region rg on rg.code = sr.region_code
    where (p_division is null or p_division = '' or rg.nom_affichage = p_division)
      and (p_territoire is null or p_territoire = '' or p.zone = p_territoire)
      and (p_area is null or p_area = '' or p.area_code = p_area or p.quartier = p_area)
      and (p_distributeur is null or p_distributeur = '' or p.distributor_name = p_distributeur)
  ),
  scored as (
    select r.niveau, r.score_global, r.calcule_le, v.pdv_id, v.date_visite,
           coalesce(p.sous_categorie_pdv, 'Non renseigné') as type_pdv
    from resultat_perfect_store r
    join visites v on v.id = r.visite_id
    join pdv p on p.pdv_id = v.pdv_id
    where v.pdv_id in (select pdv_id from scope_pdv)
      and (p_date_debut is null or v.date_visite >= p_date_debut::timestamptz)
      and (p_date_fin is null or v.date_visite < (p_date_fin + 1)::timestamptz)
  ),
  dernier as (
    select distinct on (s.pdv_id) s.pdv_id, s.type_pdv, s.niveau, s.score_global
    from scored s
    order by s.pdv_id, s.date_visite desc, s.calcule_le desc
  )
  select
    d.type_pdv,
    count(*) as pdv_scores,
    count(*) filter (where d.niveau is not null) as pdv_perfect_stores,
    round(100.0 * count(*) filter (where d.niveau is not null) / nullif(count(*), 0), 1) as perfect_store_pct,
    round(avg(d.score_global), 1) as score_global_moyen_pct,
    (select count(*) from scored s where s.type_pdv = d.type_pdv) as visites_scorees
  from dernier d
  group by d.type_pdv
  order by 1;
$$;
CREATE FUNCTION public.peut_ecrire_terrain() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(public.role_actif_courant() in ('admin','superviseur','merchandiser'), false);
$$;
CREATE FUNCTION public.prevent_profile_privilege_escalation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if (new.role                 is distinct from old.role)
  or (new.is_active            is distinct from old.is_active)
  or (new.zone_assignee        is distinct from old.zone_assignee)
  or (new.territoires_assignes is distinct from old.territoires_assignes)
  or (new.quartiers_assignes   is distinct from old.quartiers_assignes)
  or (new.commercial_id        is distinct from old.commercial_id)
  then
    if auth.uid() is not null
       and not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
      raise exception 'Rôle, activation et périmètre se modifient depuis l''administration (profil %)', new.id
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end $$;
CREATE FUNCTION public.profiles_commercial_id_valide() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare v_role text;
begin
  if new.commercial_id is null then
    return new;
  end if;
  if new.commercial_id = new.id then
    raise exception 'Un profil ne peut pas être son propre commercial responsable';
  end if;
  select role into v_role from public.profiles where id = new.commercial_id;
  if v_role is null then
    raise exception 'Commercial responsable introuvable';
  end if;
  if v_role not in ('commercial', 'admin') then
    raise exception 'Le responsable doit être un commercial (rôle reçu : %)', v_role;
  end if;
  return new;
end $$;
CREATE FUNCTION public.recalculer_perfect_store_lot(p_limit integer DEFAULT 500, p_offset integer DEFAULT 0, p_base_calcul text DEFAULT 'taux_vente'::text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_count bigint;
begin
  if p_base_calcul not in ('taux_vente','taux_revu') then
    raise exception 'Base de calcul invalide : %', p_base_calcul;
  end if;
  if not public.est_gestionnaire_perfect_store() then
    raise exception 'Permission refusée : rôle admin ou superviseur requis'
      using errcode = '42501';
  end if;
  -- `order by id` : un ordre total et stable. Sans lui, deux appels successifs
  -- pourraient rendre les mêmes lignes et en oublier d'autres.
  with lot as (
    select v.id from public.visites v
    order by v.id
    limit greatest(coalesce(p_limit, 500), 1)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select count(*) into v_count from lot;
  perform public.calculer_perfect_store(id, p_base_calcul)
  from (
    select v.id from public.visites v
    order by v.id
    limit greatest(coalesce(p_limit, 500), 1)
    offset greatest(coalesce(p_offset, 0), 0)
  ) s;
  -- Nombre de visites RÉELLEMENT traitées : l'appelant s'arrête quand il
  -- reçoit moins que `p_limit`.
  return v_count;
end;
$$;
COMMENT ON FUNCTION public.recalculer_perfect_store_lot(p_limit integer, p_offset integer, p_base_calcul text) IS 'Recalcule un lot de visites. À appeler en boucle depuis l''administration (offset croissant) : le recalcul complet dépasse le statement_timeout de 30 s.';
CREATE FUNCTION public.recalculer_tous_perfect_store(p_base_calcul text DEFAULT 'taux_vente'::text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_count bigint;
begin
  if p_base_calcul not in ('taux_vente','taux_revu') then
    raise exception 'Base de calcul invalide : %', p_base_calcul;
  end if;
  if not public.est_gestionnaire_perfect_store() then
    raise exception 'Permission refusée : rôle admin ou superviseur requis'
      using errcode = '42501';
  end if;
  select count(*) into v_count from public.visites;
  perform public.calculer_perfect_store(id,p_base_calcul)
  from public.visites;
  return v_count;
end;
$$;
CREATE FUNCTION public.refresh_stats_dashboard() RETURNS timestamp with time zone
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'stats'
    SET statement_timeout TO '600s'
    AS $$
begin
  if current_user <> 'postgres'
     and coalesce(public.role_actif_courant(), '') not in ('admin', 'superviseur') then
    raise exception 'refresh_stats_dashboard : réservé aux administrateurs';
  end if;
  refresh materialized view concurrently stats.mv_stats_visites;
  refresh materialized view concurrently stats.mv_performance_commerciaux;
  refresh materialized view concurrently stats.mv_visites_par_jour;
  refresh materialized view concurrently stats.mv_distribution_pdv;
  return now();
end;
$$;
CREATE FUNCTION public.rls_auto_enable() RETURNS void
    LANGUAGE sql
    AS $$select$$;
CREATE FUNCTION public.role_actif_courant() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select role from public.profiles
  where id = auth.uid() and is_active = true
  limit 1;
$$;
CREATE TABLE public.routing_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    day_of_week integer,
    label text,
    notes text,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    days_of_week integer[],
    territoire text,
    distributeur text,
    date_debut date,
    date_fin date,
    CONSTRAINT routing_templates_day_of_week_check CHECK (((day_of_week >= 0) AND (day_of_week <= 6))),
    CONSTRAINT routing_templates_jours_non_vides CHECK (((days_of_week IS NULL) OR (array_length(days_of_week, 1) > 0)))
);
COMMENT ON COLUMN public.routing_templates.days_of_week IS 'Jours de la semaine où la règle s''applique (0 = dimanche … 6 = samedi). Remplace day_of_week, conservée pour compatibilité.';
COMMENT ON COLUMN public.routing_templates.territoire IS 'Territoire couvert par CETTE règle. Un merchandiser peut avoir deux règles sur deux territoires le même mois.';
COMMENT ON COLUMN public.routing_templates.distributeur IS 'Distributeur rattaché à CETTE règle, pour la même raison.';
COMMENT ON COLUMN public.routing_templates.date_fin IS 'Fin de validité. NULL = la règle court indéfiniment — c''est le cas nominal demandé par le client.';
CREATE FUNCTION public.routing_regles_du_jour(p_user_id uuid, p_date date) RETURNS SETOF public.routing_templates
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select t.*
  from routing_templates t
  where t.user_id = p_user_id
    and coalesce(t.is_active, true)
    -- extract(dow) : 0 = dimanche, même convention que JS getDay().
    and coalesce(t.days_of_week, array[t.day_of_week]) @> array[extract(dow from p_date)::int]
    and (t.date_debut is null or p_date >= t.date_debut)
    and (t.date_fin is null or p_date <= t.date_fin)
    -- Règle suspendue en entier sur cette date (exception sans pdv_id).
    and not exists (
      select 1 from routing_template_exception e
      where e.template_id = t.id
        and e.pdv_id is null
        and p_date between e.date_debut and e.date_fin
    );
$$;
CREATE FUNCTION public.synthese_zones_filtre(p_division text DEFAULT NULL::text, p_territoire text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_distributeur text DEFAULT NULL::text, p_date_debut date DEFAULT NULL::date, p_date_fin date DEFAULT NULL::date, p_fenetre_mois integer DEFAULT NULL::integer) RETURNS TABLE(zone text, pdv_total bigint, pdv_visites bigint, pdv_non_visites bigint, pdv_suivis bigint, a_prospecter bigint, a_jour bigint, en_retard bigint, jamais_visites bigint, alertes bigint, alertes_toutes bigint, dispo_moyenne numeric, perfect_store_pct numeric)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    SET work_mem TO '16MB'
    AS $$
declare
  v_ref     date := coalesce(p_date_fin, current_date);
  v_fenetre integer := coalesce(p_fenetre_mois, fenetre_suivi_mois());
begin
  return query
  with scope_pdv as materialized (
    select p.pdv_id, p.zone,
           (select f.jours from frequence_visite f
             where (f.zone is null or f.zone = p.zone)
               and (f.type_pdv is null or f.type_pdv = p.sous_categorie_pdv)
             order by (f.zone is not null)::int + (f.type_pdv is not null)::int desc,
                      (f.type_pdv is not null)::int desc
             limit 1) as frequence_jours
    from pdv p
    left join territoire t on t.nom = p.zone
    left join sous_region sr on sr.code = t.sous_region_code
    left join region rg on rg.code = sr.region_code
    where coalesce(p.is_active, true)
      and (p_division is null or p_division = '' or rg.nom_affichage = p_division)
      and (p_territoire is null or p_territoire = '' or p.zone = p_territoire)
      and (p_area is null or p_area = '' or p.area_code = p_area or p.quartier = p_area)
      and (p_distributeur is null or p_distributeur = '' or p.distributor_name = p_distributeur)
  ),
  -- Agrégats sur toutes les visites, jointure au périmètre ensuite (voir
  -- pdv_fraicheur_filtre : le semi-join sur la CTE coûtait 70 s).
  derniere as materialized (
    select v.pdv_id, max(v.date_visite) as date_visite
    from visites v
    where p_date_fin is null or v.date_visite < (p_date_fin + 1)::timestamptz
    group by v.pdv_id
  ),
  -- Dernière visite de chaque PDV DANS la période : c'est elle qui compte.
  periode as materialized (
    select distinct on (v.pdv_id) v.pdv_id, v.id as visite_id
    from visites v
    where (p_date_debut is null or v.date_visite >= p_date_debut::timestamptz)
      and (p_date_fin is null or v.date_visite < (p_date_fin + 1)::timestamptz)
    order by v.pdv_id, v.date_visite desc
  ),
  scored as materialized (
    select p.pdv_id, r.dispo_rayon, r.niveau
    from periode p
    left join resultat_perfect_store r on r.visite_id = p.visite_id
  ),
  etat as materialized (
    select s.pdv_id, s.zone,
           case
             when d.date_visite is null then 'jamais_visite'
             when (v_ref - d.date_visite::date) > coalesce(s.frequence_jours, 7) then 'en_retard'
             else 'a_jour'
           end as etat,
           coalesce(d.date_visite::date >= (v_ref - make_interval(months => v_fenetre)), false) as suivi
    from scope_pdv s
    left join derniere d on d.pdv_id = s.pdv_id
  )
  select
    coalesce(e.zone, '—') as zone,
    count(*) as pdv_total,
    count(sc.pdv_id) as pdv_visites,
    count(*) - count(sc.pdv_id) as pdv_non_visites,
    count(*) filter (where e.suivi) as pdv_suivis,
    count(*) filter (where not e.suivi) as a_prospecter,
    count(*) filter (where e.etat = 'a_jour') as a_jour,
    count(*) filter (where e.etat = 'en_retard') as en_retard,
    count(*) filter (where e.etat = 'jamais_visite') as jamais_visites,
    -- Le sens d'`alertes` CHANGE ici, et c'est voulu : seuls les PDV sous
    -- couverture en retard. `alertes_toutes` conserve l'ancien chiffre.
    count(*) filter (where e.suivi and e.etat = 'en_retard') as alertes,
    count(*) filter (where e.etat in ('en_retard', 'jamais_visite')) as alertes_toutes,
    round(avg(sc.dispo_rayon), 1) as dispo_moyenne,
    round(100.0 * count(*) filter (where sc.niveau is not null) / nullif(count(sc.pdv_id), 0), 1) as perfect_store_pct
  from etat e
  left join scored sc on sc.pdv_id = e.pdv_id
  group by coalesce(e.zone, '—')
  order by 10 desc, 1;
end $$;
CREATE FUNCTION public.territoires_etendus(p_noms text[]) RETURNS SETOF text
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  with entree as (
    select distinct upper(unaccent_safe(n)) as k, n from unnest(coalesce(p_noms, array[]::text[])) n where n <> ''
  ),
  codes as (
    select t.code from public.territoire t join entree e on upper(unaccent_safe(t.nom)) = e.k
    union
    select a.territoire_code from public.territoire_alias a join entree e on upper(unaccent_safe(a.alias)) = e.k
  )
  select n from entree
  union
  select t.nom from public.territoire t join codes c on c.code = t.code
  union
  select upper(t.nom) from public.territoire t join codes c on c.code = t.code
  union
  select a.alias from public.territoire_alias a join codes c on c.code = a.territoire_code;
$$;
CREATE FUNCTION public.transferer_field_coaching(p_coaching_id uuid, p_vers uuid, p_motif text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare v_de uuid;
begin
  select assigne_a into v_de from public.field_coaching where id = p_coaching_id;
  if not found then raise exception 'coaching introuvable'; end if;
  update public.field_coaching set assigne_a = p_vers where id = p_coaching_id;
  if not found then raise exception 'transfert refusé'; end if;
  insert into public.field_coaching_transfert (coaching_id, de_user, vers_user, par_user, motif)
  values (p_coaching_id, v_de, p_vers, auth.uid(), p_motif);
end $$;
CREATE FUNCTION public.trg_calculer_perfect_store() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
begin
  perform calculer_perfect_store(new.id,'taux_vente');
  return new;
end;
$$;
CREATE FUNCTION public.trg_compute_perfect_store() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM public.compute_perfect_store(NEW.visite_id, 'taux_vente');
  RETURN NEW;
END $$;
CREATE FUNCTION public.unaccent_safe(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select translate(coalesce(p, ''), 'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖòóôõöÙÚÛÜùúûüÇçÑñ', 'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn');
$$;
CREATE FUNCTION public.update_routing_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;
CREATE FUNCTION public.update_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;
CREATE FUNCTION public.visites_garde_statut() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.status is distinct from old.status
     and new.status in ('validé', 'rejeté')
     and auth.uid() is not null
     and not public.est_gestionnaire_perfect_store() then
    raise exception 'Seuls un admin ou un superviseur peuvent valider ou rejeter une visite.';
  end if;
  return new;
end;
$$;
CREATE FUNCTION public.visites_touch_synced_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.synced_at = now();
  return new;
end;
$$;
CREATE TABLE public.action_commerciale (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pdv_id text NOT NULL,
    visite_id uuid,
    auteur_id uuid NOT NULL,
    type_code text NOT NULL,
    assigne_a uuid,
    echeance date,
    statut text DEFAULT 'a_faire'::text NOT NULL,
    commentaire text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT action_commerciale_statut_check CHECK ((statut = ANY (ARRAY['a_faire'::text, 'en_cours'::text, 'faite'::text, 'annulee'::text])))
);
ALTER TABLE ONLY public.action_commerciale REPLICA IDENTITY FULL;
COMMENT ON TABLE public.action_commerciale IS 'Action décidée par un commercial (ou un privilégié) sur un PDV, éventuellement à partir d''une visite, assignée à un merchandiseur.';
CREATE TABLE public.app_users (
    id bigint NOT NULL
);
CREATE SEQUENCE public.app_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.app_users_id_seq OWNED BY public.app_users.id;
CREATE TABLE public.appareil_push (
    jeton text NOT NULL,
    user_id uuid NOT NULL,
    plateforme text DEFAULT 'android'::text NOT NULL,
    modele text,
    cree_le timestamp with time zone DEFAULT now() NOT NULL,
    vu_le timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT appareil_push_plateforme_check CHECK ((plateforme = ANY (ARRAY['android'::text, 'ios'::text, 'web'::text])))
);
COMMENT ON TABLE public.appareil_push IS 'Jetons FCM des appareils. Un même utilisateur peut en avoir plusieurs ; un jeton change à la réinstallation de l''app.';
COMMENT ON COLUMN public.appareil_push.vu_le IS 'Dernière fois que l''app a confirmé ce jeton. Sert à purger les appareils dormants.';
CREATE TABLE public.assortment_standards (
    standard_group text NOT NULL,
    tier text NOT NULL,
    min_sku_count integer NOT NULL,
    min_sku_present integer NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT assortment_standards_tier_check CHECK ((tier = ANY (ARRAY['A'::text, 'B'::text, 'C'::text])))
);
CREATE TABLE public.availability_standards (
    category text NOT NULL,
    sku text NOT NULL,
    standard_group text NOT NULL,
    tier text NOT NULL,
    min_quantity integer NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT availability_standards_tier_check CHECK ((tier = ANY (ARRAY['A'::text, 'B'::text, 'C'::text])))
);
CREATE TABLE public.availability_weights (
    category text NOT NULL,
    trade_type text NOT NULL,
    basis text NOT NULL,
    sku text NOT NULL,
    weight numeric NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT availability_weights_basis_check CHECK ((basis = ANY (ARRAY['taux_vente'::text, 'taux_revu'::text]))),
    CONSTRAINT availability_weights_trade_type_check CHECK ((trade_type = ANY (ARRAY['GT'::text, 'MT'::text]))),
    CONSTRAINT availability_weights_weight_check CHECK (((weight >= (0)::numeric) AND (weight <= (1)::numeric)))
);
CREATE TABLE public.canaux_routing (
    id integer NOT NULL,
    canal text NOT NULL
);
CREATE SEQUENCE public.canaux_routing_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.canaux_routing_id_seq OWNED BY public.canaux_routing.id;
CREATE TABLE public.categorie_pdv (
    id bigint NOT NULL,
    nom text NOT NULL,
    canal text,
    nom_fr text,
    CONSTRAINT categorie_pdv_canal_check CHECK ((canal = ANY (ARRAY['GT'::text, 'MT'::text])))
);
ALTER TABLE public.categorie_pdv ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.categorie_pdv_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.categorie_produit (
    id bigint NOT NULL,
    code text NOT NULL,
    nom text NOT NULL
);
ALTER TABLE public.categorie_produit ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.categorie_produit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.categorie_releve (
    code text NOT NULL,
    libelle text NOT NULL,
    actif boolean DEFAULT true NOT NULL,
    ordre integer DEFAULT 0 NOT NULL,
    CONSTRAINT categorie_releve_code_check CHECK ((code = ANY (ARRAY['evap'::text, 'imp'::text, 'scm'::text, 'uht'::text, 'yaourt'::text, 'cereales'::text])))
);
COMMENT ON TABLE public.categorie_releve IS 'Catégories du relevé produit du formulaire de visite. actif=false retire la catégorie du wizard mobile, des onglets et récaps admin, sans toucher aux visites historiques.';
COMMENT ON COLUMN public.categorie_releve.code IS 'Clé JSONB sous visites.data.produits.<code>. Structurelle : jamais supprimée, seulement désactivée.';
CREATE TABLE public.category_weights (
    category text NOT NULL,
    trade_type text NOT NULL,
    weight numeric NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT category_weights_trade_type_check CHECK ((trade_type = ANY (ARRAY['GT'::text, 'MT'::text]))),
    CONSTRAINT category_weights_weight_check CHECK (((weight >= (0)::numeric) AND (weight <= (1)::numeric)))
);
CREATE TABLE public.commerciaux (
    id bigint NOT NULL
);
CREATE SEQUENCE public.commerciaux_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.commerciaux_id_seq OWNED BY public.commerciaux.id;
CREATE TABLE public.correspondance_reference (
    reference_produit_id bigint NOT NULL,
    categorie_jsonb text NOT NULL,
    sku_key text NOT NULL
);
CREATE TABLE public.distributeur (
    id bigint NOT NULL,
    nom text NOT NULL,
    "national" boolean DEFAULT false NOT NULL
);
ALTER TABLE public.distributeur ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.distributeur_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
ALTER TABLE public.element_visibilite ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.element_visibilite_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.engin_vente (
    code text NOT NULL,
    libelle text NOT NULL,
    ordre integer DEFAULT 100 NOT NULL,
    actif boolean DEFAULT true NOT NULL
);
CREATE TABLE public.field_coaching (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    date_coaching timestamp with time zone DEFAULT now() NOT NULL,
    auteur_id uuid NOT NULL,
    superviseur_id uuid,
    assigne_a uuid,
    distributeur_id bigint,
    distributeur_nom text,
    engin_code text,
    pdv_id text NOT NULL,
    route_jour text,
    type_pdv text,
    commune text,
    quartier text,
    rue text,
    proche_de text,
    proprietaire_nom text,
    proprietaire_prenom text,
    proprietaire_tel text,
    nb_sku_pdv integer,
    nb_sku_dispo integer,
    skus_disponibles jsonb DEFAULT '[]'::jsonb NOT NULL,
    reponses jsonb DEFAULT '{}'::jsonb NOT NULL,
    commentaire text,
    image_urls text[] DEFAULT '{}'::text[] NOT NULL,
    statut text DEFAULT 'soumis'::text NOT NULL,
    geolocation_lat double precision,
    geolocation_lng double precision,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    vendeur_nom text,
    type_pdv_detail text,
    motif_non_participation text,
    CONSTRAINT field_coaching_statut_check CHECK ((statut = ANY (ARRAY['soumis'::text, 'valide'::text])))
);
COMMENT ON TABLE public.field_coaching IS 'Field coaching (ex-Kobo) : identification superviseur / vendeur / PDV / propriétaire puis évaluation Maximise Distribution (13 questions Oui/Non/NA).';
CREATE TABLE public.field_coaching_transfert (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    coaching_id uuid NOT NULL,
    de_user uuid,
    vers_user uuid NOT NULL,
    par_user uuid NOT NULL,
    motif text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.frequence_visite (
    id bigint NOT NULL,
    zone text,
    type_pdv text,
    jours integer NOT NULL,
    CONSTRAINT frequence_visite_jours_check CHECK ((jours > 0))
);
COMMENT ON TABLE public.frequence_visite IS 'Nombre de jours attendu entre deux visites d''un PDV. Ligne (null, null) = défaut réseau. Surcharges par territoire et/ou type de PDV.';
ALTER TABLE public.frequence_visite ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.frequence_visite_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.geofence_zones (
    id bigint NOT NULL
);
CREATE SEQUENCE public.geofence_zones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.geofence_zones_id_seq OWNED BY public.geofence_zones.id;
CREATE TABLE public.jours_routing (
    id integer NOT NULL,
    jour text NOT NULL
);
CREATE SEQUENCE public.jours_routing_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.jours_routing_id_seq OWNED BY public.jours_routing.id;
CREATE TABLE public.marque_concurrente (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    famille text NOT NULL,
    code text NOT NULL,
    nom text NOT NULL,
    actif boolean DEFAULT true NOT NULL,
    ordre integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT marque_concurrente_famille_check CHECK ((famille = ANY (ARRAY['evap'::text, 'imp'::text, 'scm'::text, 'uht'::text])))
);
COMMENT ON TABLE public.marque_concurrente IS 'Référentiel des marques concurrentes suivies dans le relevé de visite. Gérées depuis l''admin (Référentiels), plus codées en dur.';
COMMENT ON COLUMN public.marque_concurrente.code IS 'Clé du statut dans visites.data.concurrence.<famille>.<code>. Figée à la création — en changer orphelinerait les relevés existants.';
CREATE TABLE public.marque_concurrente_sku (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    marque_id uuid NOT NULL,
    code text NOT NULL,
    libelle text NOT NULL,
    grammage_g integer,
    format text,
    colisage integer,
    image_url text,
    actif boolean DEFAULT true NOT NULL,
    ordre integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
COMMENT ON TABLE public.marque_concurrente_sku IS 'SKU concurrents suivis (marque + grammage), source fichier client du 7 sept. 2026. Relevés sous visites.data.concurrence.<famille>.skus.<code>.';
COMMENT ON COLUMN public.marque_concurrente_sku.code IS 'Clé JSONB du statut. Figée à la création — en changer orphelinerait les relevés existants.';
COMMENT ON COLUMN public.marque_concurrente_sku.image_url IS 'Photo du SKU (bucket visite-images). Nulle tant que le client n''a pas fourni les visuels.';
CREATE TABLE public.parametre_suivi (
    cle text NOT NULL,
    valeur integer NOT NULL,
    libelle text NOT NULL,
    aide text,
    CONSTRAINT parametre_suivi_cle_check CHECK ((cle = 'fenetre_suivi_mois'::text)),
    CONSTRAINT parametre_suivi_valeur_check CHECK ((valeur > 0))
);
COMMENT ON TABLE public.parametre_suivi IS 'Paramètres de pilotage du suivi. fenetre_suivi_mois : au-delà de ce nombre de mois sans visite, un PDV sort des alertes et bascule dans « à prospecter ».';
CREATE TABLE public.pays (
    id bigint NOT NULL,
    code text NOT NULL,
    nom text NOT NULL
);
ALTER TABLE public.pays ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.pays_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.pdvs (
    id bigint NOT NULL
);
CREATE SEQUENCE public.pdvs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.pdvs_id_seq OWNED BY public.pdvs.id;
CREATE TABLE public.perfect_store_score_config (
    id integer DEFAULT 1 NOT NULL,
    w_osa_lineaire numeric DEFAULT 0.10 NOT NULL,
    w_osa_pondere numeric DEFAULT 0.45 NOT NULL,
    w_assortiment numeric DEFAULT 0.15 NOT NULL,
    w_visibilite numeric DEFAULT 0.30 NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT perfect_store_score_config_id_check CHECK ((id = 1))
);
CREATE TABLE public.perfect_store_tier_config (
    ps_tier text NOT NULL,
    osa_min numeric NOT NULL,
    assort_min numeric NOT NULL,
    visi_min numeric NOT NULL,
    promo_min numeric,
    rang integer NOT NULL,
    CONSTRAINT perfect_store_tier_config_ps_tier_check CHECK ((ps_tier = ANY (ARRAY['FLAGSHIP'::text, 'VIP'::text, 'CORE'::text, 'BASIC'::text])))
);
CREATE TABLE public.poids_reference (
    reference_produit_id bigint NOT NULL,
    canal text NOT NULL,
    base_calcul text DEFAULT 'taux_vente'::text NOT NULL,
    poids numeric NOT NULL,
    CONSTRAINT poids_reference_base_calcul_check CHECK ((base_calcul = ANY (ARRAY['taux_vente'::text, 'taux_revu'::text]))),
    CONSTRAINT poids_reference_canal_check CHECK ((canal = ANY (ARRAY['GT'::text, 'MT'::text])))
);
CREATE TABLE public.pos_standard_map (
    sous_categorie_pdv text NOT NULL,
    standard_group text NOT NULL,
    tier text NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT pos_standard_map_tier_check CHECK ((tier = ANY (ARRAY['A'::text, 'B'::text, 'C'::text])))
);
CREATE TABLE public.pos_types (
    id bigint NOT NULL,
    level3_fr text,
    level4_fr text,
    level3_en text,
    level4_en text,
    canal text,
    CONSTRAINT pos_types_canal_check CHECK ((canal = ANY (ARRAY['GT'::text, 'MT'::text])))
);
COMMENT ON COLUMN public.pos_types.canal IS 'Canal commercial : GT (traditionnel) ou MT (moderne). NULL = non classé.';
CREATE SEQUENCE public.pos_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.pos_types_id_seq OWNED BY public.pos_types.id;
CREATE TABLE public.position_tournee (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    tournee_id uuid NOT NULL,
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    accuracy double precision,
    speed double precision,
    captured_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
COMMENT ON TABLE public.position_tournee IS 'Points GPS captés par l''app mobile native pendant les tournées terrain.';
CREATE TABLE public.profiles (
    id uuid NOT NULL,
    email text NOT NULL,
    nom text DEFAULT ''::text NOT NULL,
    telephone text,
    role text DEFAULT 'merchandiser'::text NOT NULL,
    zone_assignee text,
    quartiers_assignes jsonb DEFAULT '[]'::jsonb,
    region text,
    avatar_url text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    territoires_assignes jsonb DEFAULT '[]'::jsonb NOT NULL,
    commercial_id uuid,
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'superviseur'::text, 'merchandiser'::text, 'commercial'::text])))
);
COMMENT ON COLUMN public.profiles.quartiers_assignes IS 'Quartiers (pdv.quartier) du périmètre, tableau JSON de textes. Vide = pas de contrainte quartier.';
COMMENT ON COLUMN public.profiles.territoires_assignes IS 'Territoires (pdv.zone) du périmètre, tableau JSON de textes. Vide = repli sur zone_assignee.';
COMMENT ON COLUMN public.profiles.commercial_id IS 'Commercial responsable de ce merchandiseur. Lien organisationnel : filtres « mon équipe » et relances, sans effet sur le périmètre de lecture (territorial).';
CREATE TABLE public.quartier (
    id integer NOT NULL,
    zone_id integer NOT NULL,
    nom text NOT NULL,
    ordre integer DEFAULT 1 NOT NULL
);
CREATE SEQUENCE public.quartier_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.quartier_id_seq OWNED BY public.quartier.id;
CREATE TABLE public.reference_produit (
    id bigint NOT NULL,
    nom text NOT NULL,
    categorie_produit_id bigint NOT NULL,
    role text NOT NULL,
    CONSTRAINT reference_produit_role_check CHECK ((role = ANY (ARRAY['phare'::text, 'soutien'::text, 'croissance'::text, 'nouveaute'::text, 'a_retirer'::text])))
);
ALTER TABLE public.reference_produit ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.reference_produit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
ALTER TABLE public.region ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.region_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.role_section_access (
    role text NOT NULL,
    section text NOT NULL,
    can_access boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.routing_data (
    id integer NOT NULL,
    jour_routing text,
    canal text,
    position_order integer,
    sales_rep text,
    mdm text,
    created_at timestamp with time zone DEFAULT now()
);
CREATE SEQUENCE public.routing_data_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.routing_data_id_seq OWNED BY public.routing_data.id;
CREATE TABLE public.routing_pdv (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    routing_id uuid NOT NULL,
    pdv_id text NOT NULL,
    position_order integer NOT NULL,
    objectifs jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    arrived_at timestamp with time zone,
    completed_at timestamp with time zone,
    geofence_validated boolean DEFAULT false,
    geolocation_lat double precision,
    geolocation_lng double precision,
    precision_gps double precision,
    result_notes text,
    visite_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT routing_pdv_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'skipped'::text])))
);
CREATE TABLE public.routing_template_exception (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    pdv_id text,
    date_debut date NOT NULL,
    date_fin date NOT NULL,
    motif text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT routing_template_exception_check CHECK ((date_fin >= date_debut))
);
COMMENT ON TABLE public.routing_template_exception IS 'Désactivation ponctuelle d''une règle de routing : « cette semaine, il ne visite pas ce PDV ». La règle reste intacte.';
CREATE TABLE public.routing_template_pdv (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    pdv_id text NOT NULL,
    position_order integer NOT NULL,
    objectifs jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.routings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    date_routing date NOT NULL,
    created_by uuid,
    notes text,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    template_id uuid,
    source text DEFAULT 'manuel'::text NOT NULL,
    CONSTRAINT routings_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text])))
);
COMMENT ON COLUMN public.routings.source IS 'manuel = créée à la main ou importée ; regle = matérialisée depuis une règle récurrente.';
CREATE TABLE public.sales_reps (
    id integer NOT NULL,
    nom text NOT NULL
);
CREATE SEQUENCE public.sales_reps_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.sales_reps_id_seq OWNED BY public.sales_reps.id;
CREATE TABLE public.segment_grade_type_pdv (
    type_pdv_id bigint NOT NULL,
    segment text NOT NULL,
    grade text NOT NULL,
    CONSTRAINT segment_grade_type_pdv_grade_check CHECK ((grade = ANY (ARRAY['A'::text, 'B'::text, 'C'::text])))
);
CREATE TABLE public.seuil_disponibilite (
    reference_produit_id bigint NOT NULL,
    segment text NOT NULL,
    grade text NOT NULL,
    quantite_min integer NOT NULL,
    CONSTRAINT seuil_disponibilite_grade_check CHECK ((grade = ANY (ARRAY['A'::text, 'B'::text, 'C'::text]))),
    CONSTRAINT seuil_disponibilite_segment_check CHECK ((segment = ANY (ARRAY['Boutique'::text, 'Minimarket'::text, 'Kiosque'::text, 'Aboki'::text, 'Pushcart'::text, 'TableTop'::text, 'Porridge'::text, 'SupermarcheMT'::text])))
);
CREATE TABLE public.seuil_disponibilite_mt (
    reference_produit_id bigint NOT NULL,
    segment_mt text NOT NULL,
    quantite_min integer NOT NULL,
    facings integer NOT NULL,
    CONSTRAINT seuil_disponibilite_mt_segment_mt_check CHECK ((segment_mt = ANY (ARRAY['Hypermarche'::text, 'MoyenSuper'::text, 'PetitSuper'::text])))
);
CREATE TABLE public.sku_thresholds (
    category text NOT NULL,
    sku text NOT NULL,
    label text,
    seuil_bas integer DEFAULT 3 NOT NULL,
    ordre integer DEFAULT 0,
    updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.sous_region ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.sous_region_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.standard_assortiment (
    segment text NOT NULL,
    grade text NOT NULL,
    sku_cibles integer NOT NULL,
    min_sku_presents integer NOT NULL,
    heros_obligatoires boolean DEFAULT true NOT NULL,
    CONSTRAINT standard_assortiment_grade_check CHECK ((grade = ANY (ARRAY['A'::text, 'B'::text, 'C'::text]))),
    CONSTRAINT standard_assortiment_min_sku_presents_check CHECK ((min_sku_presents > 0)),
    CONSTRAINT standard_assortiment_segment_check CHECK ((segment = ANY (ARRAY['Boutique'::text, 'Minimarket'::text]))),
    CONSTRAINT standard_assortiment_sku_cibles_check CHECK ((sku_cibles > 0))
);
CREATE TABLE public.territoire_alias (
    alias text NOT NULL,
    territoire_code text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
COMMENT ON TABLE public.territoire_alias IS 'Libellé de territoire hors référentiel (pdv.zone, profiles.territoires_assignes) rattaché à un territoire réel.';
CREATE TABLE public.territoire_distributeur (
    territoire_id bigint NOT NULL,
    distributeur_id bigint NOT NULL
);
ALTER TABLE public.territoire ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.territoire_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.type_action_commerciale (
    code text NOT NULL,
    libelle text NOT NULL,
    ordre integer DEFAULT 100 NOT NULL,
    actif boolean DEFAULT true NOT NULL
);
COMMENT ON TABLE public.type_action_commerciale IS 'Types d''action qu''un commercial peut décider après consultation d''une visite. Paramétrable depuis l''admin, aucune liste figée dans le code.';
ALTER TABLE public.type_pdv ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.type_pdv_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE VIEW public.v_couverture WITH (security_invoker='on') AS
 SELECT commercial AS merchandiser,
    to_char(date_trunc('month'::text, date_visite), 'YYYY-MM'::text) AS periode,
    count(DISTINCT pdv_id) AS pdv_vus
   FROM public.visites v
  GROUP BY commercial, (date_trunc('month'::text, date_visite));
CREATE VIEW public.v_couverture_globale WITH (security_invoker='on') AS
 SELECT to_char(date_trunc('month'::text, date_visite), 'YYYY-MM'::text) AS periode,
    count(DISTINCT pdv_id) AS pdv_vus,
    ( SELECT count(*) AS count
           FROM public.pdv p
          WHERE COALESCE(p.is_active, true)) AS pdv_total,
    round(((100.0 * (count(DISTINCT pdv_id))::numeric) / (NULLIF(( SELECT count(*) AS count
           FROM public.pdv p
          WHERE COALESCE(p.is_active, true)), 0))::numeric), 1) AS couverture_pct
   FROM public.visites v
  GROUP BY (date_trunc('month'::text, date_visite));
CREATE VIEW public.v_dispo_produits_zone WITH (security_invoker='on') AS
 SELECT p.zone,
    count(*) AS total_visites,
    round(((100.0 * (count(*) FILTER (WHERE ((((v.data -> 'produits'::text) -> 'evap'::text) ->> 'present'::text))::boolean))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS taux_evap,
    round(((100.0 * (count(*) FILTER (WHERE ((((v.data -> 'produits'::text) -> 'imp'::text) ->> 'present'::text))::boolean))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS taux_imp,
    round(((100.0 * (count(*) FILTER (WHERE ((((v.data -> 'produits'::text) -> 'scm'::text) ->> 'present'::text))::boolean))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS taux_scm,
    round(((100.0 * (count(*) FILTER (WHERE ((((v.data -> 'produits'::text) -> 'uht'::text) ->> 'present'::text))::boolean))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS taux_uht,
    round(((100.0 * (count(*) FILTER (WHERE ((((v.data -> 'produits'::text) -> 'yaourt'::text) ->> 'present'::text))::boolean))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS taux_yaourt,
    round(((100.0 * (count(*) FILTER (WHERE (((v.data -> 'concurrence'::text) ->> 'presence_concurrents'::text))::boolean))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS taux_concurrence
   FROM (public.visites v
     JOIN public.pdv p ON ((p.pdv_id = v.pdv_id)))
  GROUP BY p.zone
  ORDER BY p.zone;
CREATE MATERIALIZED VIEW stats.mv_distribution_pdv AS
 SELECT COALESCE(sous_categorie_pdv, 'Autre'::text) AS type,
    count(*) AS count
   FROM public.pdv
  WHERE (is_active = true)
  GROUP BY COALESCE(sous_categorie_pdv, 'Autre'::text)
  WITH NO DATA;
CREATE VIEW public.v_distribution_pdv WITH (security_invoker='on') AS
 SELECT type,
    count
   FROM stats.mv_distribution_pdv
  ORDER BY count DESC;
CREATE VIEW public.v_perfect_store_evolution WITH (security_invoker='on') AS
 SELECT to_char(date_trunc('day'::text, v.date_visite), 'YYYY-MM-DD'::text) AS date,
    count(*) FILTER (WHERE (r.niveau IS NOT NULL)) AS perfect_stores,
    count(*) AS visites_scorees,
    round(((100.0 * (count(*) FILTER (WHERE (r.niveau IS NOT NULL)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS perfect_store_pct
   FROM (public.visites v
     JOIN public.resultat_perfect_store r ON ((r.visite_id = v.id)))
  GROUP BY (date_trunc('day'::text, v.date_visite));
CREATE VIEW public.v_perfect_store_global WITH (security_invoker='on') AS
 SELECT count(*) AS visites_scorees,
    count(*) FILTER (WHERE (niveau IS NOT NULL)) AS perfect_stores,
    round(((100.0 * (count(*) FILTER (WHERE (niveau IS NOT NULL)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS perfect_store_pct,
    round(avg(score_global), 1) AS score_global_moyen_pct,
    round(avg(dispo_rayon), 1) AS osa_moyen_pct,
    round(avg(visibilite), 1) AS visibilite_moyenne_pct,
    round(avg(promotion), 1) AS promotion_moyenne_pct,
    round(avg(assortiment), 1) AS assortiment_moyen_pct
   FROM public.resultat_perfect_store;
CREATE VIEW public.v_perfect_store_liste WITH (security_invoker='true') AS
 SELECT visite_id,
    pdv_id,
    nom_pdv,
    type_pdv,
    zone,
    date_visite,
    commercial,
    niveau,
    score_global,
    dispo_rayon,
    assortiment,
    visibilite,
    promotion
   FROM ( SELECT DISTINCT ON (v.pdv_id) r.visite_id,
            v.pdv_id,
            p.nom_pdv,
            COALESCE(p.sous_categorie_pdv, 'Non renseigné'::text) AS type_pdv,
            p.zone,
            v.date_visite,
            v.commercial,
            r.niveau,
            r.score_global,
            r.dispo_rayon,
            r.assortiment,
            r.visibilite,
            r.promotion
           FROM ((public.resultat_perfect_store r
             JOIN public.visites v ON ((v.id = r.visite_id)))
             JOIN public.pdv p ON ((p.pdv_id = v.pdv_id)))
          ORDER BY v.pdv_id, v.date_visite DESC, r.calcule_le DESC) latest
  WHERE (niveau IS NOT NULL);
CREATE VIEW public.v_perfect_store_liste_full WITH (security_invoker='true') AS
 SELECT visite_id,
    pdv_id,
    nom_pdv,
    type_pdv,
    zone,
    date_visite,
    commercial,
    COALESCE(niveau, 'NON CONFORME'::text) AS niveau,
    score_global,
    dispo_rayon,
    assortiment,
    visibilite,
    promotion
   FROM ( SELECT DISTINCT ON (v.pdv_id) r.visite_id,
            v.pdv_id,
            p.nom_pdv,
            COALESCE(p.sous_categorie_pdv, 'Non renseigné'::text) AS type_pdv,
            p.zone,
            v.date_visite,
            v.commercial,
            r.niveau,
            r.score_global,
            r.dispo_rayon,
            r.assortiment,
            r.visibilite,
            r.promotion
           FROM ((public.resultat_perfect_store r
             JOIN public.visites v ON ((v.id = r.visite_id)))
             JOIN public.pdv p ON ((p.pdv_id = v.pdv_id)))
          ORDER BY v.pdv_id, v.date_visite DESC, r.calcule_le DESC) latest;
CREATE VIEW public.v_perfect_store_par_categorie_pdv WITH (security_invoker='on') AS
 SELECT COALESCE(p.sous_categorie_pdv, 'Non renseigné'::text) AS type_pdv,
    count(*) AS visites_scorees,
    count(*) FILTER (WHERE (r.niveau IS NOT NULL)) AS perfect_stores,
    round(((100.0 * (count(*) FILTER (WHERE (r.niveau IS NOT NULL)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS perfect_store_pct,
    round(avg(r.score_global), 1) AS score_global_moyen_pct
   FROM ((public.resultat_perfect_store r
     JOIN public.visites v ON ((v.id = r.visite_id)))
     JOIN public.pdv p ON ((p.pdv_id = v.pdv_id)))
  GROUP BY COALESCE(p.sous_categorie_pdv, 'Non renseigné'::text);
CREATE VIEW public.v_perfect_store_par_type WITH (security_invoker='on') AS
 SELECT p.sous_categorie_pdv AS type_pdv,
    count(*) AS visites_scorees,
    count(*) FILTER (WHERE vps.is_perfect_store) AS perfect_stores,
    round(((100.0 * (count(*) FILTER (WHERE vps.is_perfect_store))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS perfect_store_pct,
    round((avg(vps.score_global) * (100)::numeric), 1) AS score_global_moyen_pct
   FROM ((public.visite_perfect_store vps
     JOIN public.visites v ON ((v.visite_id = vps.visite_id)))
     JOIN public.pdv p ON ((p.pdv_id = v.pdv_id)))
  GROUP BY p.sous_categorie_pdv
  ORDER BY (round(((100.0 * (count(*) FILTER (WHERE vps.is_perfect_store))::numeric) / (NULLIF(count(*), 0))::numeric), 1)) DESC NULLS LAST;
CREATE MATERIALIZED VIEW stats.mv_performance_commerciaux AS
 SELECT row_number() OVER (ORDER BY (count(*)) DESC, commercial, email) AS id,
    commercial AS nom,
    email,
    count(*) AS total_visites,
    count(*) FILTER (WHERE (date_visite >= date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone))) AS visites_mois,
    max(date_visite) AS derniere_visite
   FROM public.visites
  GROUP BY commercial, email
  WITH NO DATA;
CREATE VIEW public.v_performance_commerciaux WITH (security_invoker='on') AS
 SELECT nom,
    email,
    total_visites,
    visites_mois,
    derniere_visite
   FROM stats.mv_performance_commerciaux
  ORDER BY id;
CREATE MATERIALIZED VIEW stats.mv_stats_visites AS
 SELECT 1 AS id,
    count(*) AS total_visites,
    count(DISTINCT pdv_id) AS pdv_visites,
    count(DISTINCT user_id) AS commerciaux_actifs,
    count(*) FILTER (WHERE ((date_visite)::date = CURRENT_DATE)) AS visites_today,
    count(*) FILTER (WHERE (date_visite >= date_trunc('week'::text, (CURRENT_DATE)::timestamp with time zone))) AS visites_week,
    count(*) FILTER (WHERE (date_visite >= date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone))) AS visites_month,
    round(((100.0 * (count(*) FILTER (WHERE (((((data -> 'produits'::text) -> 'evap'::text) ->> 'present'::text))::boolean = true)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS taux_evap,
    round(((100.0 * (count(*) FILTER (WHERE (((((data -> 'produits'::text) -> 'imp'::text) ->> 'present'::text))::boolean = true)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS taux_imp,
    round(((100.0 * (count(*) FILTER (WHERE (((((data -> 'produits'::text) -> 'scm'::text) ->> 'present'::text))::boolean = true)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS taux_scm,
    round(((100.0 * (count(*) FILTER (WHERE (((((data -> 'produits'::text) -> 'uht'::text) ->> 'present'::text))::boolean = true)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS taux_uht,
    round(((100.0 * (count(*) FILTER (WHERE (((((data -> 'produits'::text) -> 'yaourt'::text) ->> 'present'::text))::boolean = true)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS taux_yaourt,
    now() AS calcule_le
   FROM public.visites
  WITH NO DATA;
CREATE VIEW public.v_stats_visites WITH (security_invoker='on') AS
 SELECT total_visites,
    pdv_visites,
    commerciaux_actifs,
    visites_today,
    visites_week,
    visites_month,
    taux_evap,
    taux_imp,
    taux_scm,
    taux_uht,
    taux_yaourt
   FROM stats.mv_stats_visites;
CREATE VIEW public.v_stats_zone_secteur WITH (security_invoker='on') AS
 SELECT p.region,
    p.zone,
    p.quartier,
    count(DISTINCT p.pdv_id) AS total_pdv,
    count(DISTINCT v.visite_id) AS total_visites,
    count(DISTINCT v.commercial) AS nb_commerciaux,
    round(((100.0 * (count(DISTINCT v.pdv_id))::numeric) / (NULLIF(count(DISTINCT p.pdv_id), 0))::numeric), 1) AS taux_couverture,
    max(v.date_visite) AS derniere_visite
   FROM (public.pdv p
     LEFT JOIN public.visites v ON ((v.pdv_id = p.pdv_id)))
  GROUP BY p.region, p.zone, p.quartier
  ORDER BY p.region, p.zone, p.quartier;
CREATE VIEW public.v_visites_detail WITH (security_invoker='on') AS
 SELECT v.id,
    v.visite_id,
    v.pdv_id,
    v.date_visite,
    v.commercial,
    v.email,
    p.nom_pdv,
    p.canal,
    p.zone,
    p.quartier,
    p.region,
    p.categorie_pdv,
    ((((v.data -> 'produits'::text) -> 'evap'::text) ->> 'present'::text))::boolean AS evap_present,
    ((((v.data -> 'produits'::text) -> 'evap'::text) ->> 'prix_respectes'::text))::boolean AS evap_prix_ok,
    ((((v.data -> 'produits'::text) -> 'imp'::text) ->> 'present'::text))::boolean AS imp_present,
    ((((v.data -> 'produits'::text) -> 'imp'::text) ->> 'prix_respectes'::text))::boolean AS imp_prix_ok,
    ((((v.data -> 'produits'::text) -> 'scm'::text) ->> 'present'::text))::boolean AS scm_present,
    ((((v.data -> 'produits'::text) -> 'scm'::text) ->> 'prix_respectes'::text))::boolean AS scm_prix_ok,
    ((((v.data -> 'produits'::text) -> 'uht'::text) ->> 'present'::text))::boolean AS uht_present,
    ((((v.data -> 'produits'::text) -> 'uht'::text) ->> 'prix_respectes'::text))::boolean AS uht_prix_ok,
    ((((v.data -> 'produits'::text) -> 'cereales'::text) ->> 'present'::text))::boolean AS cereales_present,
    ((((v.data -> 'produits'::text) -> 'yaourt'::text) ->> 'present'::text))::boolean AS yaourt_present,
    (((v.data -> 'concurrence'::text) ->> 'presence_concurrents'::text))::boolean AS concurrence_presente,
    ((((v.data -> 'visibilite'::text) -> 'exterieure'::text) ->> 'presence_visibilite'::text))::boolean AS vis_ext_presente,
    ((((v.data -> 'visibilite'::text) -> 'interieure'::text) ->> 'presence_visibilite'::text))::boolean AS vis_int_presente,
    (((v.data -> 'actions'::text) ->> 'referencement_produits'::text))::boolean AS act_referencement,
    (((v.data -> 'actions'::text) ->> 'verification_fifo'::text))::boolean AS act_fifo,
    (((v.data -> 'actions'::text) ->> 'rangement_produits'::text))::boolean AS act_rangement,
    v.image_urls,
    v.created_at
   FROM (public.visites v
     LEFT JOIN public.pdv p ON ((p.pdv_id = v.pdv_id)));
CREATE MATERIALIZED VIEW stats.mv_visites_par_jour AS
 SELECT (date_visite)::date AS date,
    count(*) AS count
   FROM public.visites
  GROUP BY ((date_visite)::date)
  ORDER BY ((date_visite)::date) DESC
 LIMIT 90
  WITH NO DATA;
CREATE VIEW public.v_visites_par_jour WITH (security_invoker='on') AS
 SELECT date,
    count
   FROM stats.mv_visites_par_jour
  ORDER BY date DESC;
CREATE TABLE public.version_app (
    plateforme text NOT NULL,
    version_code_min integer DEFAULT 1 NOT NULL,
    version_nom_min text,
    url_telechargement text,
    message text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT version_app_plateforme_check CHECK ((plateforme = ANY (ARRAY['android'::text, 'ios'::text]))),
    CONSTRAINT version_app_version_code_min_check CHECK ((version_code_min > 0))
);
COMMENT ON TABLE public.version_app IS 'Version minimale de l''app mobile par plateforme. En dessous de version_code_min (versionCode Android), l''app bloque et propose url_telechargement.';
CREATE TABLE public.version_installee (
    user_id uuid NOT NULL,
    plateforme text DEFAULT 'android'::text NOT NULL,
    version_code integer NOT NULL,
    version_nom text,
    vu_le timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT version_installee_plateforme_check CHECK ((plateforme = ANY (ARRAY['android'::text, 'ios'::text])))
);
COMMENT ON TABLE public.version_installee IS 'Dernière version de l''app mobile ouverte par chaque utilisateur (déclarée au lancement).';
CREATE TABLE public.visibility_standards (
    standard_group text NOT NULL,
    ps_tier text NOT NULL,
    zone text NOT NULL,
    element_key text NOT NULL,
    is_required boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT visibility_standards_ps_tier_check CHECK ((ps_tier = ANY (ARRAY['FLAGSHIP'::text, 'VIP'::text, 'CORE'::text, 'BASIC'::text]))),
    CONSTRAINT visibility_standards_zone_check CHECK ((zone = ANY (ARRAY['exterieure'::text, 'interieure'::text])))
);
CREATE TABLE public.zone (
    id bigint NOT NULL,
    code text,
    nom text NOT NULL,
    territoire_code text NOT NULL
);
CREATE TABLE public.zone_distributeur (
    zone_id bigint NOT NULL,
    distributeur_id bigint NOT NULL
);
ALTER TABLE public.zone ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.zone_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.zones_secteurs (
    id integer NOT NULL,
    zone text NOT NULL,
    secteur text,
    merchandiser text,
    email_merchandiser text,
    sales_rep text,
    email_sales_rep text,
    region text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);
CREATE SEQUENCE public.zones_secteurs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.zones_secteurs_id_seq OWNED BY public.zones_secteurs.id;
ALTER TABLE ONLY public.app_users ALTER COLUMN id SET DEFAULT nextval('public.app_users_id_seq'::regclass);
ALTER TABLE ONLY public.canaux_routing ALTER COLUMN id SET DEFAULT nextval('public.canaux_routing_id_seq'::regclass);
ALTER TABLE ONLY public.commerciaux ALTER COLUMN id SET DEFAULT nextval('public.commerciaux_id_seq'::regclass);
ALTER TABLE ONLY public.geofence_zones ALTER COLUMN id SET DEFAULT nextval('public.geofence_zones_id_seq'::regclass);
ALTER TABLE ONLY public.jours_routing ALTER COLUMN id SET DEFAULT nextval('public.jours_routing_id_seq'::regclass);
ALTER TABLE ONLY public.pdvs ALTER COLUMN id SET DEFAULT nextval('public.pdvs_id_seq'::regclass);
ALTER TABLE ONLY public.pos_types ALTER COLUMN id SET DEFAULT nextval('public.pos_types_id_seq'::regclass);
ALTER TABLE ONLY public.quartier ALTER COLUMN id SET DEFAULT nextval('public.quartier_id_seq'::regclass);
ALTER TABLE ONLY public.routing_data ALTER COLUMN id SET DEFAULT nextval('public.routing_data_id_seq'::regclass);
ALTER TABLE ONLY public.sales_reps ALTER COLUMN id SET DEFAULT nextval('public.sales_reps_id_seq'::regclass);
ALTER TABLE ONLY public.zones_secteurs ALTER COLUMN id SET DEFAULT nextval('public.zones_secteurs_id_seq'::regclass);
INSERT INTO public.assortment_standards VALUES
	('BOUTIQUE', 'A', 15, 10, '2026-11-15 14:07:54.407833+00'),
	('BOUTIQUE', 'B', 12, 8, '2026-11-15 14:07:54.407833+00'),
	('BOUTIQUE', 'C', 11, 5, '2026-11-15 14:07:54.407833+00'),
	('MINI MARKET', 'A', 15, 10, '2026-11-15 14:07:54.407833+00'),
	('MINI MARKET', 'B', 12, 8, '2026-11-15 14:07:54.407833+00'),
	('MINI MARKET', 'C', 11, 5, '2026-11-15 14:07:54.407833+00');
INSERT INTO public.availability_standards VALUES
	('evap', 'br_gold', 'BOUTIQUE', 'A', 24, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_gold', 'BOUTIQUE', 'B', 24, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_gold', 'BOUTIQUE', 'C', 12, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_160g', 'BOUTIQUE', 'A', 48, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_160g', 'BOUTIQUE', 'B', 36, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_160g', 'BOUTIQUE', 'C', 18, '2026-11-15 14:07:54.40222+00'),
	('evap', 'brb_160g', 'BOUTIQUE', 'A', 24, '2026-11-15 14:07:54.40222+00'),
	('evap', 'brb_160g', 'BOUTIQUE', 'B', 18, '2026-11-15 14:07:54.40222+00'),
	('evap', 'brb_160g', 'BOUTIQUE', 'C', 12, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_400g', 'BOUTIQUE', 'A', 24, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_400g', 'BOUTIQUE', 'B', 18, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_400g', 'BOUTIQUE', 'C', 10, '2026-11-15 14:07:54.40222+00'),
	('evap', 'brb_400g', 'BOUTIQUE', 'A', 12, '2026-11-15 14:07:54.40222+00'),
	('evap', 'brb_400g', 'BOUTIQUE', 'B', 12, '2026-11-15 14:07:54.40222+00'),
	('evap', 'brb_400g', 'BOUTIQUE', 'C', 6, '2026-11-15 14:07:54.40222+00'),
	('evap', 'pearl_400g', 'BOUTIQUE', 'A', 24, '2026-11-15 14:07:54.40222+00'),
	('evap', 'pearl_400g', 'BOUTIQUE', 'B', 18, '2026-11-15 14:07:54.40222+00'),
	('evap', 'pearl_400g', 'BOUTIQUE', 'C', 10, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_gold', 'MINI MARKET', 'A', 24, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_gold', 'MINI MARKET', 'B', 12, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_160g', 'MINI MARKET', 'A', 48, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_160g', 'MINI MARKET', 'B', 24, '2026-11-15 14:07:54.40222+00'),
	('evap', 'brb_160g', 'MINI MARKET', 'A', 24, '2026-11-15 14:07:54.40222+00'),
	('evap', 'brb_160g', 'MINI MARKET', 'B', 18, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_400g', 'MINI MARKET', 'A', 24, '2026-11-15 14:07:54.40222+00'),
	('evap', 'br_400g', 'MINI MARKET', 'B', 18, '2026-11-15 14:07:54.40222+00'),
	('evap', 'brb_400g', 'MINI MARKET', 'A', 12, '2026-11-15 14:07:54.40222+00'),
	('evap', 'brb_400g', 'MINI MARKET', 'B', 12, '2026-11-15 14:07:54.40222+00'),
	('evap', 'pearl_400g', 'MINI MARKET', 'A', 24, '2026-11-15 14:07:54.40222+00'),
	('evap', 'pearl_400g', 'MINI MARKET', 'B', 18, '2026-11-15 14:07:54.40222+00'),
	('scm', 'br_1kg', 'BOUTIQUE', 'A', 3, '2026-11-15 14:07:54.40222+00'),
	('scm', 'br_1kg', 'MINI MARKET', 'A', 6, '2026-11-15 14:07:54.40222+00'),
	('scm', 'br_1kg', 'MINI MARKET', 'B', 3, '2026-11-15 14:07:54.40222+00'),
	('scm', 'pearl_1kg', 'BOUTIQUE', 'A', 12, '2026-11-15 14:07:54.40222+00'),
	('scm', 'pearl_1kg', 'BOUTIQUE', 'B', 6, '2026-11-15 14:07:54.40222+00'),
	('scm', 'pearl_1kg', 'BOUTIQUE', 'C', 3, '2026-11-15 14:07:54.40222+00'),
	('scm', 'pearl_1kg', 'MINI MARKET', 'A', 12, '2026-11-15 14:07:54.40222+00'),
	('scm', 'pearl_1kg', 'MINI MARKET', 'B', 6, '2026-11-15 14:07:54.40222+00'),
	('imp', 'br_20g', 'BOUTIQUE', 'A', 12, '2026-11-15 14:07:54.40222+00'),
	('imp', 'br_20g', 'BOUTIQUE', 'B', 12, '2026-11-15 14:07:54.40222+00'),
	('imp', 'br_20g', 'BOUTIQUE', 'C', 3, '2026-11-15 14:07:54.40222+00'),
	('imp', 'brd_15g', 'BOUTIQUE', 'A', 12, '2026-11-15 14:07:54.40222+00'),
	('imp', 'brd_15g', 'BOUTIQUE', 'B', 12, '2026-11-15 14:07:54.40222+00'),
	('imp', 'brd_15g', 'BOUTIQUE', 'C', 3, '2026-11-15 14:07:54.40222+00'),
	('imp', 'br_375g', 'BOUTIQUE', 'A', 6, '2026-11-15 14:07:54.40222+00'),
	('imp', 'br_375g', 'BOUTIQUE', 'B', 3, '2026-11-15 14:07:54.40222+00'),
	('imp', 'br_375g', 'BOUTIQUE', 'C', 3, '2026-11-15 14:07:54.40222+00'),
	('imp', 'br_900g', 'BOUTIQUE', 'A', 12, '2026-11-15 14:07:54.40222+00'),
	('imp', 'br_900g', 'BOUTIQUE', 'B', 6, '2026-11-15 14:07:54.40222+00'),
	('imp', 'br_900g', 'BOUTIQUE', 'C', 3, '2026-11-15 14:07:54.40222+00'),
	('imp', 'br_2_5kg', 'BOUTIQUE', 'A', 6, '2026-11-15 14:07:54.40222+00'),
	('imp', 'br_2_5kg', 'BOUTIQUE', 'B', 3, '2026-11-15 14:07:54.40222+00');
INSERT INTO public.availability_weights VALUES
	('evap', 'GT', 'taux_vente', 'br_160g', 0.75, '2026-11-15 14:07:54.41279+00'),
	('evap', 'GT', 'taux_vente', 'brb_160g', 0.08, '2026-11-15 14:07:54.41279+00'),
	('evap', 'GT', 'taux_vente', 'br_400g', 0.05, '2026-11-15 14:07:54.41279+00'),
	('evap', 'GT', 'taux_vente', 'brb_400g', 0.01, '2026-11-15 14:07:54.41279+00'),
	('evap', 'GT', 'taux_vente', 'br_gold', 0.01, '2026-11-15 14:07:54.41279+00'),
	('evap', 'GT', 'taux_vente', 'pearl_400g', 0.10, '2026-11-15 14:07:54.41279+00'),
	('evap', 'GT', 'taux_revu', 'br_160g', 0.65, '2026-11-15 14:07:54.41279+00'),
	('evap', 'GT', 'taux_revu', 'brb_160g', 0.07, '2026-11-15 14:07:54.41279+00'),
	('evap', 'GT', 'taux_revu', 'br_400g', 0.05, '2026-11-15 14:07:54.41279+00'),
	('evap', 'GT', 'taux_revu', 'brb_400g', 0.03, '2026-11-15 14:07:54.41279+00'),
	('evap', 'GT', 'taux_revu', 'br_gold', 0.10, '2026-11-15 14:07:54.41279+00'),
	('evap', 'GT', 'taux_revu', 'pearl_400g', 0.10, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_vente', 'br_160g', 0.69, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_vente', 'brb_160g', 0.09, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_vente', 'br_400g', 0.08, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_vente', 'brb_400g', 0.04, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_vente', 'br_gold', 0.04, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_vente', 'pearl_400g', 0.05, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_revu', 'br_160g', 0.55, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_revu', 'brb_160g', 0.12, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_revu', 'br_400g', 0.08, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_revu', 'brb_400g', 0.05, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_revu', 'br_gold', 0.15, '2026-11-15 14:07:54.41279+00'),
	('evap', 'MT', 'taux_revu', 'pearl_400g', 0.05, '2026-11-15 14:07:54.41279+00'),
	('scm', 'GT', 'taux_vente', 'pearl_1kg', 0.95, '2026-11-15 14:07:54.41279+00'),
	('scm', 'GT', 'taux_vente', 'br_1kg', 0.05, '2026-11-15 14:07:54.41279+00'),
	('scm', 'GT', 'taux_revu', 'pearl_1kg', 0.95, '2026-11-15 14:07:54.41279+00'),
	('scm', 'GT', 'taux_revu', 'br_1kg', 0.05, '2026-11-15 14:07:54.41279+00'),
	('imp', 'MT', 'taux_vente', 'br_20g', 0.5754, '2026-11-15 14:07:54.603924+00'),
	('imp', 'MT', 'taux_revu', 'br_20g', 0.25, '2026-11-15 14:07:54.603924+00'),
	('imp', 'MT', 'taux_vente', 'br_375g', 0.2401, '2026-11-15 14:07:54.603924+00'),
	('imp', 'MT', 'taux_revu', 'br_375g', 0.16, '2026-11-15 14:07:54.603924+00'),
	('imp', 'MT', 'taux_vente', 'brd_15g', 0.0786, '2026-11-15 14:07:54.603924+00'),
	('imp', 'MT', 'taux_revu', 'brd_15g', 0.15, '2026-11-15 14:07:54.603924+00'),
	('imp', 'MT', 'taux_vente', 'br_900g', 0.0231, '2026-11-15 14:07:54.603924+00'),
	('imp', 'MT', 'taux_revu', 'br_900g', 0.15, '2026-11-15 14:07:54.603924+00'),
	('imp', 'MT', 'taux_vente', 'br_2_5kg', 0.0138, '2026-11-15 14:07:54.603924+00'),
	('imp', 'MT', 'taux_revu', 'br_2_5kg', 0.12, '2026-11-15 14:07:54.603924+00'),
	('scm', 'MT', 'taux_vente', 'pearl_1kg', 0.0247, '2026-11-15 14:07:54.603924+00'),
	('scm', 'MT', 'taux_revu', 'pearl_1kg', 0.3, '2026-11-15 14:07:54.603924+00'),
	('scm', 'MT', 'taux_vente', 'br_1kg', 0.775, '2026-11-15 14:07:54.603924+00'),
	('scm', 'MT', 'taux_revu', 'br_1kg', 0.7, '2026-11-15 14:07:54.603924+00'),
	('scm', 'MT', 'taux_vente', 'br_397g', 0.074, '2026-11-15 14:07:54.603924+00'),
	('scm', 'MT', 'taux_vente', 'brb_1kg', 0.1263, '2026-11-15 14:07:54.603924+00');
INSERT INTO public.canaux_routing VALUES
	(1, 'GT'),
	(2, 'MT'),
	(3, 'GT et MT');
INSERT INTO public.categorie_pdv OVERRIDING SYSTEM VALUE VALUES
	(6, 'Hypermarkets', 'MT', 'Hypermarchés'),
	(11, 'Premium Supermarkets', 'MT', 'Supermarchés premium'),
	(15, 'Value Supermarkets', 'MT', 'Supermarchés économiques'),
	(9, 'Minimarkets', 'GT', 'Supérettes'),
	(13, 'Small/Medium Grocery GT', 'GT', 'Épiceries de proximité (GT)'),
	(3, 'Fuel forecourts', 'GT', 'Boutiques de station-service'),
	(10, 'Pharmacy Chain/Independent', 'GT', 'Pharmacies (chaînes & indépendantes)'),
	(1, 'Bakery (Chain/Independent)', 'GT', 'Boulangeries (chaînes & indépendantes)'),
	(16, 'Wet/Public Market', 'GT', 'Marchés publics'),
	(14, 'Traditional Wholesale', 'GT', 'Commerce de gros traditionnel'),
	(17, 'Wholesale Club/Cash & Carry', 'GT', 'Libre-service de gros'),
	(2, 'Bricks and Clicks', 'GT', 'Commerce en ligne'),
	(12, 'Shop in Shop', 'GT', 'Corner (shop-in-shop)'),
	(5, 'Hotel chains', 'GT', 'Hôtellerie'),
	(4, 'Full Service Restaurant', 'GT', 'Restauration'),
	(7, 'Independent Street Vendor Tea & Coffee', 'GT', 'Vente ambulante thé & café'),
	(8, 'Institutes/Office/Factory/Industry', 'GT', 'Institutions & entreprises');
INSERT INTO public.categorie_produit OVERRIDING SYSTEM VALUE VALUES
	(1, 'EVAP', 'Lait évaporé'),
	(2, 'IMP', 'Lait en poudre'),
	(3, 'SCM', 'Lait concentré sucré');
INSERT INTO public.categorie_releve VALUES
	('evap', 'EVAP', true, 1),
	('imp', 'IMP', true, 2),
	('scm', 'SCM', true, 3),
	('uht', 'UHT', true, 4),
	('yaourt', 'Yaourt', false, 5),
	('cereales', 'Céréales', false, 6);
INSERT INTO public.correspondance_reference VALUES
	(1, 'evap', 'pearl_400g'),
	(2, 'evap', 'brb_400g'),
	(3, 'evap', 'br_400g'),
	(4, 'evap', 'brb_160g'),
	(5, 'evap', 'br_160g'),
	(6, 'evap', 'br_gold'),
	(8, 'imp', 'br_2_5kg'),
	(9, 'imp', 'br_900g'),
	(10, 'imp', 'brd_350g'),
	(11, 'imp', 'br_375g'),
	(12, 'imp', 'brd_15g'),
	(13, 'imp', 'br_20g'),
	(14, 'scm', 'pearl_1kg'),
	(15, 'scm', 'br_1kg'),
	(7, 'imp', 'br_400g');
INSERT INTO public.distributeur OVERRIDING SYSTEM VALUE VALUES
	(1, 'Distributeur 01', false),
	(2, 'Distributeur 02', false),
	(3, 'Distributeur 03', true),
	(4, 'Distributeur 04', false),
	(5, 'Distributeur 05', false),
	(6, 'Distributeur 06', false),
	(7, 'Distributeur 07', false),
	(8, 'Distributeur 08', true),
	(9, 'Distributeur 09', true),
	(10, 'Distributeur 10', true),
	(11, 'Distributeur 11', false),
	(12, 'Distributeur 12', false),
	(13, 'Distributeur 13', false),
	(14, 'Distributeur 14', false),
	(15, 'Distributeur 15', false),
	(16, 'Distributeur 16', false),
	(17, 'Distributeur 17', false),
	(18, 'Distributeur 18', true),
	(19, 'Distributeur 19', false),
	(20, 'Distributeur 20', false),
	(21, 'Distributeur 21', false),
	(22, 'Distributeur 22', false),
	(23, 'Distributeur 23', false),
	(24, 'Distributeur 24', false),
	(25, 'Distributeur 25', true),
	(26, 'Distributeur 26', true),
	(27, 'Distributeur 27', false),
	(28, 'Distributeur 28', false),
	(29, 'Distributeur 29', false),
	(30, 'Distributeur 30', false),
	(31, 'Distributeur 31', false),
	(32, 'Distributeur 32', true),
	(33, 'Distributeur 33', false),
	(34, 'Distributeur 34', true),
	(35, 'Distributeur 35', false),
	(36, 'Distributeur 36', false),
	(37, 'Distributeur 37', false),
	(38, 'Distributeur 38', false),
	(39, 'Distributeur 39', true),
	(40, 'Distributeur 40', false),
	(41, 'Distributeur 41', false),
	(42, 'Distributeur 42', false),
	(43, 'Distributeur 43', false),
	(44, 'Distributeur 44', false),
	(45, 'Distributeur 45', false);
INSERT INTO public.element_visibilite OVERRIDING SYSTEM VALUE VALUES
	(1, 'boutique', 'affiche', 'Affiche', 'visibilite', 'exterieure', false),
	(3, 'boutique', 'guirlande', 'Guirlande', 'visibilite', 'exterieure', true),
	(4, 'boutique', 'sign_board', 'sign board', 'visibilite', 'exterieure', false),
	(5, 'boutique', 'panneau_privilege', 'Panneau privilège', 'visibilite', 'exterieure', false),
	(6, 'boutique', 'full_branding', 'Full branding', 'visibilite', 'exterieure', false),
	(7, 'boutique', 'reglette', 'Reglette', 'visibilite', 'interieure', false),
	(14, 'boutique', 'merchandising', 'Merchandising', 'visibilite', 'interieure', false),
	(15, 'boutique', 'standard', 'Standard', 'promotion', 'promotion', false),
	(16, 'boutique', 'hotesses', 'Hotesses', 'promotion', 'promotion', false),
	(17, 'boutique', 'degustation', 'Dégustation', 'promotion', 'promotion', false),
	(18, 'superette', 'affiche', 'Affiche', 'visibilite', 'exterieure', true),
	(20, 'superette', 'sign_board', 'sign board lumineux', 'visibilite', 'exterieure', true),
	(21, 'superette', 'panneau_privilege', 'Panneau privilège lumineux', 'visibilite', 'exterieure', true),
	(28, 'superette', 'merchandising', 'Merchandising', 'visibilite', 'interieure', false),
	(29, 'superette', 'standard', 'Standard', 'promotion', 'promotion', false),
	(30, 'superette', 'hotesses', 'Hotesses', 'promotion', 'promotion', false),
	(31, 'superette', 'degustation', 'Dégustation', 'promotion', 'promotion', false),
	(32, 'table_top', 'parasol', 'PARASOLS', 'visibilite', 'exterieure', false),
	(33, 'table_top', 'nappe', 'NAPPE', 'visibilite', 'interieure', false),
	(34, 'table_top', 'hanger', 'HANGER', 'visibilite', 'interieure', false),
	(35, 'table_top', 'tablier', 'TABLIER', 'visibilite', 'interieure', true),
	(36, 'table_top', 'promotion', 'Promotion', 'promotion', 'promotion', false),
	(37, 'pushcart', 'affiche', 'AFFICHE', 'visibilite', 'exterieure', false),
	(38, 'pushcart', 'thermos', 'THERMOS', 'visibilite', 'interieure', false),
	(40, 'pushcart', 'chasuble', 'CHASUBLE', 'visibilite', 'interieure', false),
	(41, 'pushcart', 'full_branding', 'FULL BRANDING', 'visibilite', 'exterieure', false),
	(42, 'pushcart', 'promotion', 'Promotion', 'promotion', 'promotion', false),
	(43, 'porridge', 'parasol', 'PARASOLS', 'visibilite', 'exterieure', false),
	(44, 'porridge', 'nappe', 'NAPPE', 'visibilite', 'interieure', false),
	(2, 'boutique', 'fleche', 'Flèche', 'visibilite', 'exterieure', true),
	(9, 'boutique', 'hanger', 'Hanger', 'visibilite', 'interieure', true),
	(10, 'boutique', 'wobler', 'Wobler', 'visibilite', 'interieure', true),
	(11, 'boutique', 'presentoir', 'Présentoire', 'visibilite', 'interieure', true),
	(12, 'boutique', 'tg', 'TG', 'visibilite', 'interieure', true),
	(19, 'superette', 'fleche', 'Flèche (Entrée et sortie)', 'visibilite', 'exterieure', true),
	(22, 'superette', 'reglette', 'Reglette', 'visibilite', 'interieure', true),
	(24, 'superette', 'wobler', 'Wobler rayon', 'visibilite', 'interieure', true),
	(25, 'superette', 'presentoir', 'Présentoire', 'visibilite', 'interieure', true),
	(26, 'superette', 'tg', 'TG', 'visibilite', 'interieure', true),
	(39, 'pushcart', 'verre_jetable', 'VERRE JETABLE', 'visibilite', 'interieure', true),
	(8, 'boutique', 'maison_br', 'Maison FT', 'visibilite', 'interieure', false),
	(13, 'boutique', 'plaque_br', 'Plaque FT', 'visibilite', 'interieure', true),
	(23, 'superette', 'espace_br', 'Espace FT', 'visibilite', 'interieure', false),
	(27, 'superette', 'plaque_br', 'Plaque FT', 'visibilite', 'interieure', true),
	(45, 'porridge', 'hanger', 'HANGER', 'visibilite', 'interieure', false),
	(47, 'porridge', 'tablier', 'TABLIER', 'visibilite', 'interieure', false),
	(48, 'porridge', 'standard', 'STANDARD', 'promotion', 'promotion', false),
	(49, 'porridge', 'degustation', 'DEGUSTATION', 'promotion', 'promotion', false),
	(50, 'kiosque_aboki', 'affiche', 'AFFICHE', 'visibilite', 'exterieure', false),
	(51, 'kiosque_aboki', 'thermos', 'THERMOS', 'visibilite', 'interieure', false),
	(52, 'kiosque_aboki', 'verre', 'VERRE', 'visibilite', 'interieure', false),
	(53, 'kiosque_aboki', 'carafe', 'CARAFE', 'visibilite', 'interieure', false),
	(55, 'kiosque_aboki', 'chasuble', 'CHASUBLE', 'visibilite', 'interieure', false),
	(56, 'kiosque_aboki', 'full_branding', 'FULL BRANDING', 'visibilite', 'exterieure', false),
	(57, 'kiosque_aboki', 'promotion', 'Promotion', 'promotion', 'promotion', false),
	(59, 'mt', 'wobler', 'Wobbler', 'visibilite', 'interieure', false),
	(60, 'mt', 'hotesses', 'Hôtesses', 'promotion', 'promotion', false),
	(61, 'mt', 'niche', 'Niche', 'visibilite', 'interieure', false),
	(62, 'mt', 'top_shelf', 'Top shelf', 'visibilite', 'interieure', false),
	(63, 'mt', 'plot', 'Plot', 'promotion', 'promotion', false),
	(64, 'mt', 'bacs', 'Bacs', 'visibilite', 'interieure', false),
	(65, 'mt', 'reglette', 'Réglettes', 'visibilite', 'interieure', false),
	(66, 'kiosque_aboki', 'nappe', 'NAPPE', 'visibilite', 'interieure', false),
	(46, 'porridge', 'verre_jetable', 'VERRE JETABLE', 'visibilite', 'interieure', true),
	(58, 'mt', 'tg', 'TG (activités promotionnelles)', 'promotion', 'promotion', false),
	(54, 'kiosque_aboki', 'maison_br', 'MAISON FT', 'visibilite', 'interieure', false);
INSERT INTO public.engin_vente VALUES
	('van', 'Van', 10, true),
	('mini_van', 'Mini Van', 20, true),
	('tricycle', 'Tricycle', 30, true),
	('moto', 'Moto', 40, true),
	('truck', 'Truck', 50, true);
INSERT INTO public.frequence_visite OVERRIDING SYSTEM VALUE VALUES
	(1, NULL, NULL, 7);
INSERT INTO public.jours_routing VALUES
	(1, 'Lundi 1'),
	(2, 'Lundi 2'),
	(3, 'Lundi 3'),
	(4, 'Lundi 4'),
	(5, 'Mardi 1'),
	(6, 'Mardi 2'),
	(7, 'Mardi 3'),
	(8, 'Mardi 4'),
	(9, 'Mercredi 1'),
	(10, 'Mercredi 2'),
	(11, 'Mercredi 3'),
	(12, 'Mercredi 4'),
	(13, 'Jeudi 1'),
	(14, 'Jeudi 2'),
	(15, 'Jeudi 3'),
	(16, 'Jeudi 4'),
	(17, 'Vendredi 1'),
	(18, 'Vendredi 2'),
	(19, 'Vendredi 3'),
	(20, 'Vendredi 4'),
	(21, 'Samedi 1'),
	(22, 'Samedi 2'),
	(23, 'Samedi 3'),
	(24, 'Samedi 4');
INSERT INTO public.marque_concurrente VALUES
	('50fafc96-06fc-4833-9874-e12ccd01d5ed', 'evap', 'cowmilk', 'Concurrent D', true, 1, '2026-11-15 14:07:56.549409+00'),
	('c7cc0e9e-8dc1-45ff-8b5c-d44dca480047', 'evap', 'nido_150g', 'Concurrent G', true, 2, '2026-11-15 14:07:56.549409+00'),
	('9f3805bf-6ded-409f-a2af-0a306241f2df', 'imp', 'nido', 'Concurrent F', true, 1, '2026-11-15 14:07:56.549409+00'),
	('99269224-fca9-4910-a1f9-c3a48e09be56', 'imp', 'laity', 'Concurrent E', true, 2, '2026-11-15 14:07:56.549409+00'),
	('1d660e8b-2e71-4255-be33-343cc7f53569', 'imp', 'top_lait', 'Concurrent I', true, 3, '2026-11-15 14:07:56.549409+00'),
	('ad5c53dc-37d1-4ae8-9ef7-31e4e3a0f241', 'scm', 'top_saho', 'Concurrent J', true, 1, '2026-11-15 14:07:56.549409+00'),
	('1bfab556-6cea-4923-984e-0d8e2356b02f', 'uht', 'candia', 'Concurrent B', true, 1, '2026-11-15 14:07:56.549409+00'),
	('3da2c307-9502-45f6-a2a5-0c920b552825', 'evap', 'laity', 'Concurrent E', true, 3, '2026-11-15 14:07:56.765551+00'),
	('596e3516-298d-4c3d-88ad-7ebccb36421d', 'evap', 'soleil', 'Concurrent H', true, 4, '2026-11-15 14:07:56.765551+00'),
	('2c57e7b2-f596-497b-a0ad-7a7717836266', 'imp', 'biblos', 'Concurrent A', true, 4, '2026-11-15 14:07:56.765551+00'),
	('199096b5-efa4-44c5-a6bd-477e20ed9b51', 'imp', 'captain', 'Concurrent C', true, 5, '2026-11-15 14:07:56.765551+00');
INSERT INTO public.marque_concurrente_sku VALUES
	('cf5fc557-7952-45f7-bd1d-df11c98ead80', '50fafc96-06fc-4833-9874-e12ccd01d5ed', 'cowmilk_160g', 'Concurrent D 160g', 160, 'Boîte', 48, NULL, true, 1, '2026-11-15 14:07:56.765551+00'),
	('c0d6b28c-9b0f-4e8f-9ad4-4b91da08439d', '9f3805bf-6ded-409f-a2af-0a306241f2df', 'nido_2500g', 'Concurrent F 2500g', 2500, 'Boîte', 6, NULL, true, 5, '2026-11-15 14:07:56.765551+00'),
	('a8a327c5-74af-42b7-afe1-8e5787707976', '9f3805bf-6ded-409f-a2af-0a306241f2df', 'nido_800g', 'Concurrent F 800g', 800, 'Boîte', NULL, NULL, true, 4, '2026-11-15 14:07:56.765551+00'),
	('02dd36af-665b-4db1-b36f-7a80b5464789', '9f3805bf-6ded-409f-a2af-0a306241f2df', 'nido_400g', 'Concurrent F 400g', 400, 'Boîte', 24, NULL, true, 3, '2026-11-15 14:07:56.765551+00'),
	('6239d2a9-3568-4dda-822d-13a6b07a5e3d', '9f3805bf-6ded-409f-a2af-0a306241f2df', 'nido_350g', 'Concurrent F 350g', 350, 'Pouch', NULL, NULL, true, 2, '2026-11-15 14:07:56.765551+00'),
	('9de00b1d-fb6f-4ff1-8bbd-cc1339e28c69', '9f3805bf-6ded-409f-a2af-0a306241f2df', 'nido_15g', 'Concurrent F 15g', 15, 'Sachet', 120, NULL, true, 1, '2026-11-15 14:07:56.765551+00'),
	('d70ec1e2-71dc-4798-90c1-48de9c250945', '99269224-fca9-4910-a1f9-c3a48e09be56', 'laity_900g', 'Concurrent E 900g', 900, 'Boîte', NULL, NULL, true, 4, '2026-11-15 14:07:56.765551+00'),
	('8af89153-a0a5-4dc0-ad3e-8c43d71f36e0', '99269224-fca9-4910-a1f9-c3a48e09be56', 'laity_400g', 'Concurrent E 400g', 400, 'Boîte', NULL, NULL, true, 3, '2026-11-15 14:07:56.765551+00'),
	('9cd004ea-0b12-4ce0-9e72-798e86685b86', '99269224-fca9-4910-a1f9-c3a48e09be56', 'laity_360g', 'Concurrent E 360g', 360, 'Pouch', 6, NULL, true, 2, '2026-11-15 14:07:56.765551+00'),
	('737a94ec-33f6-491e-9efd-3a489204ce4c', '99269224-fca9-4910-a1f9-c3a48e09be56', 'laity_18g', 'Concurrent E 18g', 18, 'Sachet', 120, NULL, true, 1, '2026-11-15 14:07:56.765551+00'),
	('28dbd862-42b4-41c2-82b7-ee56c331a2cf', '1d660e8b-2e71-4255-be33-343cc7f53569', 'top_lait_400g', 'Concurrent I 400g', 400, 'Boîte', NULL, NULL, true, 2, '2026-11-15 14:07:56.765551+00'),
	('280976b5-b31d-4b1a-a172-d5c3bb372091', '1d660e8b-2e71-4255-be33-343cc7f53569', 'top_lait_12g', 'Concurrent I 12g', 12, 'Sachet', NULL, NULL, true, 1, '2026-11-15 14:07:56.765551+00'),
	('e11603fb-796e-43ba-92f2-35b8764bf0d2', '3da2c307-9502-45f6-a2a5-0c920b552825', 'laity_150g', 'Concurrent E 150g', 150, 'Boîte', 24, NULL, true, 1, '2026-11-15 14:07:56.765551+00'),
	('958c0f34-a88a-42d7-aeba-ef091625d07d', '596e3516-298d-4c3d-88ad-7ebccb36421d', 'soleil_400g', 'Concurrent H 400g', 400, 'Boîte', NULL, NULL, true, 1, '2026-11-15 14:07:56.765551+00'),
	('fcb02b0f-8f7d-48a1-8ec7-0e63be74b444', '2c57e7b2-f596-497b-a0ad-7a7717836266', 'biblos_900g', 'Concurrent A 900g', 900, 'Boîte', 20, NULL, true, 3, '2026-11-15 14:07:56.765551+00'),
	('7ec0ae52-9f67-4da7-a0f4-95775ae3fdcf', '2c57e7b2-f596-497b-a0ad-7a7717836266', 'biblos_360g', 'Concurrent A 360g', 360, 'Pouch', 6, NULL, true, 2, '2026-11-15 14:07:56.765551+00'),
	('c3623b98-70da-45e5-b638-3e192c1968e7', '2c57e7b2-f596-497b-a0ad-7a7717836266', 'biblos_16g', 'Concurrent A 16g', 16, 'Sachet', 120, NULL, true, 1, '2026-11-15 14:07:56.765551+00'),
	('471eba22-5c68-49cf-b334-778b2316dbf5', '199096b5-efa4-44c5-a6bd-477e20ed9b51', 'captain_22g', 'Concurrent C 22g', 22, 'Sachet', 120, NULL, true, 2, '2026-11-15 14:07:56.765551+00'),
	('8f48df7f-a4f6-4e69-bfd7-bd2e42cc6e74', '199096b5-efa4-44c5-a6bd-477e20ed9b51', 'captain_12g', 'Concurrent C 12g', 12, 'Sachet', NULL, NULL, true, 1, '2026-11-15 14:07:56.765551+00');
INSERT INTO public.niveau_perfect_store VALUES
	('FLAGSHIP STORE', 4, 95, 100, 100),
	('VIP PERFECT STORE', 3, 85, 100, 100),
	('CORE PERFECT STORE', 2, 75, 100, 100),
	('BASIC PERFECT STORE', 1, 60, 100, 100);
INSERT INTO public.parametre_suivi VALUES
	('fenetre_suivi_mois', 12, 'Fenêtre de suivi (mois)', 'Un PDV visité au moins une fois dans cette fenêtre est « suivi » et compte dans les alertes. Au-delà, il bascule dans « à prospecter ».');
INSERT INTO public.pays OVERRIDING SYSTEM VALUE VALUES
	(1, 'CI1', 'Cote d''Ivoire');
INSERT INTO public.pdv VALUES
	('9ac3ad3a-f641-4b7c-b592-a21994bab9cb', 'FT-001', 'Boutique Le Baobab', 'General trade', 'Point de vente détail', 'Boutique A', NULL, 'Abidjan', 'Cocody 1', 'PALMERAIE', 5.3697, -3.959, 200, 'Carrefour Palmeraie, face à la pharmacie', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'COC 1', NULL, 'Distributeur 23', 'FLAGSHIP', 'admin', NULL, NULL, NULL),
	('7b691e4a-155b-4ef4-9cf1-7c25de843ad2', 'FT-002', 'Superette Les Flamboyants', 'General trade', 'Point de vente détail', 'Superettes A', NULL, 'Abidjan', 'Cocody 1', 'PERLE', 5.3581, -3.9712, 200, 'Rue des Jardins, près du rond-point', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'COC 1', NULL, 'Distributeur 23', 'FLAGSHIP', 'admin', NULL, NULL, NULL),
	('c3bc8795-be7c-4179-b991-adc443730096', 'FT-003', 'Supermarché Horizon', 'Modern trade', 'Point de vente détail', 'Supermarket A', NULL, 'Abidjan', 'Cocody 1', 'LYCEE TECHNIQUE', 5.3452, -4.0018, 200, 'Boulevard de France, galerie commerciale', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'COC 1', NULL, 'Distributeur 23', 'FLAGSHIP', 'admin', NULL, NULL, NULL),
	('53b6f9b5-dcfd-4321-89bd-d7bdfb60340b', 'FT-004', 'Boutique Chez Tantie Rose', 'General trade', 'Point de vente détail', 'Boutique B', NULL, 'Abidjan', 'Marcory', 'RÉSIDENTIEL', 5.3011, -3.9921, 200, 'Rue du Canal, à côté de la boulangerie', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'MAR', NULL, 'Distributeur 31', 'VIP', 'admin', NULL, NULL, NULL),
	('ed31dd44-84b1-4c77-a9f2-0148abfdc300', 'FT-005', 'Boutique La Confiance', 'General trade', 'Point de vente détail', 'Boutique B', NULL, 'Abidjan', 'Marcory', 'SICOGI', 5.3062, -3.9853, 200, 'Marché Sicogi, allée centrale', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'MAR', NULL, 'Distributeur 31', 'VIP', 'admin', NULL, NULL, NULL),
	('bb77db07-e28c-486a-8bfc-3739ede21d5d', 'FT-006', 'Boutique Le Bon Coin', 'General trade', 'Point de vente détail', 'Boutique B', NULL, 'Abidjan', 'Marcory', 'HIBISCUS', 5.2987, -3.9802, 200, 'Cité Hibiscus, entrée principale', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'MAR', NULL, 'Distributeur 31', 'VIP', 'admin', NULL, NULL, NULL),
	('eca35fb2-3040-413f-8d85-a74061f0bdef', 'FT-007', 'Boutique Le Palmier', 'General trade', 'Point de vente détail', 'Boutique C', NULL, 'Abidjan', 'Plateau', 'PLATEAU CENTRE', 5.3231, -4.0203, 200, 'Avenue du Commerce, immeuble Les Arcades', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'PLA', NULL, 'Distributeur 07', 'CORE', 'admin', NULL, NULL, NULL),
	('2a923947-0821-4fee-9a83-25481cef219f', 'FT-008', 'Boutique Étoile du Matin', 'General trade', 'Point de vente détail', 'Boutique C', NULL, 'Abidjan', 'Plateau', 'CITE FERMONT', 5.3274, -4.0171, 200, 'Cité Fermont, bloc B', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'PLA', NULL, 'Distributeur 07', 'CORE', 'admin', NULL, NULL, NULL),
	('abf36be5-628c-4f72-9365-bb0bdb72bdc1', 'FT-009', 'Boutique Aux Trois Frères', 'General trade', 'Point de vente détail', 'Boutique C', NULL, 'Abidjan', 'Plateau', 'MARCHE DE FRUIT', 5.3302, -4.0236, 200, 'Marché de fruits, rangée 2', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'PLA', NULL, 'Distributeur 07', 'CORE', 'admin', NULL, NULL, NULL),
	('3edb516f-4ccc-4c10-95e5-c0c04213bcfa', 'FT-010', 'Boutique La Lagune', 'General trade', 'Point de vente détail', 'Boutique C', NULL, 'Abidjan', 'Treichville', 'ZONE 3', 5.2952, -4.0021, 200, 'Zone 3, rue des Pêcheurs', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'TRE', NULL, 'Distributeur 31', 'CORE', 'admin', NULL, NULL, NULL),
	('c6cbe057-50ed-4cdd-8088-df599d42cc00', 'FT-011', 'Kiosque du Carrefour', 'General trade', 'Point de vente détail', 'Kiosk A', NULL, 'Abidjan', 'Treichville', 'ARAS', 5.3003, -4.0082, 200, 'Carrefour Aras, côté gare', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'TRE', NULL, 'Distributeur 31', 'BASIC', 'admin', NULL, NULL, NULL),
	('a63c43b5-48eb-4286-9da6-00bca79f4510', 'FT-012', 'Kiosque Le Rendez-vous', 'General trade', 'Point de vente détail', 'Kiosk A', NULL, 'Abidjan', 'Treichville', 'BELLEVILLE', 5.3051, -4.0043, 200, 'Belleville, face à lécole primaire', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'TRE', NULL, 'Distributeur 31', 'BASIC', 'admin', NULL, NULL, NULL),
	('6c533d01-8135-48e8-b46d-decf6ed87c47', 'FT-013', 'Boutique Petit Marché', 'General trade', 'Point de vente détail', 'Boutique C', NULL, 'Abidjan', 'Yopougon 1', 'WASSAKARA', 5.3412, -4.0703, 200, 'Wassakara, près du terminus', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'YOP 1', NULL, 'Distributeur 36', 'CORE', 'admin', NULL, NULL, NULL),
	('a182de89-2ae1-4572-a0ae-ef92cf1b7a35', 'FT-014', 'Supermarché Bel Air', 'Modern trade', 'Point de vente détail', 'Supermarket C', NULL, 'Abidjan', 'Yopougon 1', 'YOPOUGON SABLE', 5.3361, -4.0781, 200, 'Sable, boulevard principal', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'YOP 1', NULL, 'Distributeur 36', 'CORE', 'admin', NULL, NULL, NULL),
	('167eda1f-4dd0-4f35-8d93-96448a657ec1', 'FT-015', 'Boutique Wassa', 'General trade', 'Point de vente détail', 'Boutique B', NULL, 'Abidjan', 'Yopougon 1', 'TOIT ROUGE', 5.3304, -4.0852, 200, 'Toit Rouge, derrière la station', NULL, NULL, 'admin@fieldtrack.demo', NULL, NULL, NULL, NULL, NULL, true, '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'YOP 1', NULL, 'Distributeur 36', 'VIP', 'admin', NULL, NULL, NULL);
INSERT INTO public.perfect_store_score_config VALUES
	(1, 0.10, 0.45, 0.15, 0.30, '2026-11-15 14:07:54.427461+00');
INSERT INTO public.perfect_store_tier_config VALUES
	('FLAGSHIP', 0.95, 1.00, 1.00, NULL, 4),
	('VIP', 0.85, 0.90, 1.00, NULL, 3),
	('CORE', 0.75, 0.80, 1.00, NULL, 2),
	('BASIC', 0.60, 0.60, 1.00, NULL, 1);
INSERT INTO public.poids_reference VALUES
	(1, 'GT', 'taux_vente', 0.1031887494),
	(2, 'GT', 'taux_vente', 0.005407986339),
	(3, 'GT', 'taux_vente', 0.04827634345),
	(4, 'GT', 'taux_vente', 0.08421527549),
	(5, 'GT', 'taux_vente', 0.749443117),
	(6, 'GT', 'taux_vente', 0.009468528271),
	(7, 'GT', 'taux_vente', 0.0006256053519412669),
	(8, 'GT', 'taux_vente', 0.0009114034803),
	(9, 'GT', 'taux_vente', 0.002414206552),
	(10, 'GT', 'taux_vente', 0.008819685235),
	(11, 'GT', 'taux_vente', 0.05424448477),
	(12, 'GT', 'taux_vente', 0.07805304413),
	(13, 'GT', 'taux_vente', 0.8549315705),
	(14, 'MT', 'taux_vente', 0.4677043522764932),
	(14, 'GT', 'taux_vente', 0.9461997208476083),
	(15, 'MT', 'taux_vente', 0.44385217874148497),
	(15, 'GT', 'taux_vente', 0.05380027915239183),
	(1, 'MT', 'taux_revu', 0.05),
	(1, 'GT', 'taux_revu', 0.10),
	(2, 'MT', 'taux_revu', 0.05),
	(2, 'GT', 'taux_revu', 0.03),
	(3, 'MT', 'taux_revu', 0.08),
	(3, 'GT', 'taux_revu', 0.05),
	(4, 'MT', 'taux_revu', 0.12),
	(4, 'GT', 'taux_revu', 0.07),
	(5, 'MT', 'taux_revu', 0.55),
	(5, 'GT', 'taux_revu', 0.65),
	(6, 'MT', 'taux_revu', 0.15),
	(6, 'GT', 'taux_revu', 0.10),
	(7, 'MT', 'taux_revu', 0.07),
	(7, 'GT', 'taux_revu', 0.02),
	(8, 'MT', 'taux_revu', 0.12),
	(8, 'GT', 'taux_revu', 0.02),
	(9, 'MT', 'taux_revu', 0.15),
	(9, 'GT', 'taux_revu', 0.05),
	(10, 'MT', 'taux_revu', 0.10),
	(10, 'GT', 'taux_revu', 0.03),
	(11, 'MT', 'taux_revu', 0.16),
	(11, 'GT', 'taux_revu', 0.07),
	(12, 'MT', 'taux_revu', 0.15),
	(12, 'GT', 'taux_revu', 0.05),
	(13, 'MT', 'taux_revu', 0.25),
	(13, 'GT', 'taux_revu', 0.76),
	(14, 'MT', 'taux_revu', 0.30),
	(14, 'GT', 'taux_revu', 0.9461997208476083),
	(15, 'MT', 'taux_revu', 0.70),
	(15, 'GT', 'taux_revu', 0.05380027915239183),
	(1, 'MT', 'taux_vente', 0.036255),
	(2, 'MT', 'taux_vente', 0.062622),
	(3, 'MT', 'taux_vente', 0.138184),
	(4, 'MT', 'taux_vente', 0.135132),
	(5, 'MT', 'taux_vente', 0.488953),
	(6, 'MT', 'taux_vente', 0.138855),
	(7, 'MT', 'taux_vente', 0.005445),
	(8, 'MT', 'taux_vente', 0.013755),
	(9, 'MT', 'taux_vente', 0.023089),
	(10, 'MT', 'taux_vente', 0.063667),
	(11, 'MT', 'taux_vente', 0.240079),
	(12, 'MT', 'taux_vente', 0.078602),
	(13, 'MT', 'taux_vente', 0.575363);
INSERT INTO public.pos_standard_map VALUES
	('Boutique A', 'BOUTIQUE', 'A', '2026-11-15 14:07:54.39488+00'),
	('Boutique B', 'BOUTIQUE', 'B', '2026-11-15 14:07:54.39488+00'),
	('Boutique C', 'BOUTIQUE', 'C', '2026-11-15 14:07:54.39488+00'),
	('Superette GT', 'MINI MARKET', 'A', '2026-11-15 14:07:54.39488+00'),
	('Kiosque', 'KIOSQUE', 'A', '2026-11-15 14:07:54.39488+00');
INSERT INTO public.profiles VALUES
	('c1b8c7a8-c496-482e-acce-b7d41a18ab93', 'admin@fieldtrack.demo', 'Admin Field Track', NULL, 'admin', NULL, '[]', NULL, NULL, true, '2026-11-15 14:08:07.942506+00', '2026-11-15 14:08:07.942506+00', '[]', NULL),
	('1ce93462-59a6-4134-8c6a-f46bc3a868f9', 'commercial1@fieldtrack.demo', 'Awa Démo', NULL, 'commercial', 'Cocody 1', '[]', 'Abidjan', NULL, true, '2026-11-15 14:08:07.942506+00', '2026-11-15 14:08:19.360439+00', '["Cocody 1", "Plateau"]', NULL),
	('3fe0add4-79f2-4904-b7b0-54161b503ceb', 'commercial2@fieldtrack.demo', 'Bakary Démo', NULL, 'commercial', 'Marcory', '[]', 'Abidjan', NULL, true, '2026-11-15 14:08:07.942506+00', '2026-11-15 14:08:19.360439+00', '["Marcory", "Treichville"]', NULL),
	('939a7ba2-d282-452f-9706-ee73d62fa12f', 'commercial3@fieldtrack.demo', 'Clarisse Démo', NULL, 'commercial', 'Yopougon 1', '[]', 'Abidjan', NULL, true, '2026-11-15 14:08:07.942506+00', '2026-11-15 14:08:19.360439+00', '["Yopougon 1"]', NULL),
	('e3fd8415-d791-4164-80d3-2c3221ad27ca', 'merchandiser1@fieldtrack.demo', 'Daouda Essai', NULL, 'merchandiser', 'Cocody 1', '[]', 'Abidjan', NULL, true, '2026-11-15 14:08:07.942506+00', '2026-11-15 14:08:19.360439+00', '["Cocody 1"]', '1ce93462-59a6-4134-8c6a-f46bc3a868f9'),
	('ba78d180-c6bd-44f0-bcb0-b0a76d818a47', 'merchandiser2@fieldtrack.demo', 'Estelle Essai', NULL, 'merchandiser', 'Plateau', '[]', 'Abidjan', NULL, true, '2026-11-15 14:08:07.942506+00', '2026-11-15 14:08:19.360439+00', '["Plateau"]', '1ce93462-59a6-4134-8c6a-f46bc3a868f9'),
	('745aabe3-9648-4aa1-9feb-7d60f93a032a', 'merchandiser3@fieldtrack.demo', 'Fabrice Essai', NULL, 'merchandiser', 'Marcory', '[]', 'Abidjan', NULL, true, '2026-11-15 14:08:07.942506+00', '2026-11-15 14:08:19.360439+00', '["Marcory"]', '3fe0add4-79f2-4904-b7b0-54161b503ceb'),
	('ecfef4e0-2429-4653-91aa-5a04eb14f1e0', 'merchandiser4@fieldtrack.demo', 'Grâce Essai', NULL, 'merchandiser', 'Treichville', '[]', 'Abidjan', NULL, true, '2026-11-15 14:08:07.942506+00', '2026-11-15 14:08:19.360439+00', '["Treichville"]', '3fe0add4-79f2-4904-b7b0-54161b503ceb'),
	('5f7115ff-1868-49d3-917a-25797198941a', 'merchandiser5@fieldtrack.demo', 'Hervé Essai', NULL, 'merchandiser', 'Yopougon 1', '[]', 'Abidjan', NULL, true, '2026-11-15 14:08:07.942506+00', '2026-11-15 14:08:19.360439+00', '["Yopougon 1"]', '939a7ba2-d282-452f-9706-ee73d62fa12f');
INSERT INTO public.quartier VALUES
	(1, 1, 'NOUVEAU GOUDRON', 1),
	(2, 1, 'FEH KESSE', 2),
	(3, 1, 'CITE SIR', 3),
	(4, 1, 'AKANDJE', 4),
	(5, 1, 'LAURIER 15', 5),
	(6, 1, 'SANTE', 6),
	(7, 2, 'BLANCHON', 1),
	(8, 2, 'PALMERAIE BINGERVILLE', 2),
	(9, 2, 'ADJAME BINGERVILLE', 3),
	(10, 2, 'BREGBO', 4),
	(11, 2, 'AKOUAI SANTE', 5),
	(12, 2, 'AMAN', 6),
	(13, 3, 'BASE CIE', 1),
	(14, 3, 'KOROCOBOUGOU', 2),
	(15, 3, 'GBAGBA', 3),
	(16, 3, 'BERLIN', 4),
	(17, 3, 'SAVANE', 5),
	(18, 3, 'MACHOU', 6),
	(19, 3, 'SICOGI', 7),
	(20, 3, 'MACHOUX', 8),
	(21, 3, 'MARCHE', 9),
	(22, 4, 'ABATTA', 1),
	(23, 4, 'ABATTA VILLAGE', 2),
	(24, 4, 'JULES VERNE', 3),
	(25, 4, 'CITE DU PORT', 4),
	(26, 5, 'TOUT BINGERVILLE', 1),
	(27, 6, 'LYCEE TECHNIQUE', 1),
	(28, 6, 'VALLON', 2),
	(29, 6, 'COLOMBIE', 3),
	(30, 7, 'MAHOU COLOMBIE', 1),
	(31, 8, 'PERLE', 1),
	(32, 8, 'MAHOU', 2),
	(33, 8, 'ANGRE', 3),
	(34, 9, 'PALMERAIE', 1),
	(35, 9, 'ATTOBAN', 2),
	(36, 9, 'BONOUMIN', 3),
	(37, 10, 'PALMERAIE2 COCOVICO', 1),
	(38, 11, 'ANGRE 2PLATEAUX 7 TRANCHE', 1),
	(39, 12, 'BESSIKOI', 1),
	(40, 12, 'DJOROBITE', 2),
	(41, 13, 'DANGA', 1),
	(42, 13, 'COCODY CENTRE', 2),
	(43, 13, 'BLAUKOSS', 3),
	(44, 14, 'BLAUKOSS COCODY CENTRE', 1),
	(45, 15, 'RIVIERA 2', 1),
	(46, 15, 'RIVIERA 3', 2),
	(47, 15, 'GOLF', 3),
	(48, 16, 'ANONO', 1),
	(49, 17, 'FAYA BON PRIX', 1),
	(50, 17, 'ABATTA', 2),
	(51, 18, 'CIAD', 1),
	(52, 18, 'MPOUTO', 2),
	(53, 18, 'SYNACACI', 3),
	(54, 18, 'FAYA (COTE ECHANGEUR)', 4),
	(55, 19, 'ARAS', 1),
	(56, 19, 'BELLEVILLE', 2),
	(57, 19, 'BIAFRA', 3),
	(58, 19, 'QUARTIER APOLLO', 4),
	(59, 19, 'ZONE 3', 5),
	(60, 20, 'ARAS', 1),
	(61, 20, 'BELLEVILLE', 2),
	(62, 20, 'BIAFRA', 3),
	(63, 20, 'QUARTIER APOLLO', 4),
	(64, 20, 'ZONE 3', 5),
	(65, 21, 'RÉSIDENTIEL', 1),
	(66, 21, 'CHAMPROUX', 2),
	(67, 21, 'GROUPEMENT', 3),
	(68, 21, 'HIBISCUS', 4),
	(69, 21, 'MASSARANA', 5),
	(70, 22, 'SICOGI', 1),
	(71, 22, 'REMBLAIS', 2),
	(72, 22, 'ANOUMANBO', 3),
	(73, 22, 'SANS FIL', 4),
	(74, 22, 'ZONE 4', 5),
	(75, 23, 'RÉSIDENTIEL', 1),
	(76, 23, 'CHAMPROUX', 2),
	(77, 23, 'GRPE', 3),
	(78, 23, 'HIBISCUS', 4),
	(79, 23, 'MASSARANA', 5),
	(80, 23, 'SICOGI', 6),
	(81, 23, 'REMBLAIS', 7),
	(82, 23, 'ANOUMANBO', 8),
	(83, 23, 'SANS FIL', 9),
	(84, 23, 'ZONE4', 10),
	(85, 24, 'REMBLAIS', 1),
	(86, 24, 'MARAIS', 2),
	(87, 24, 'DIVO', 3),
	(88, 24, 'KOUMASSI 32', 4),
	(89, 24, 'TERM 05', 5),
	(90, 25, 'CITÉ 147', 1),
	(91, 25, 'PRODOMO', 2),
	(92, 25, 'SOPIM', 3),
	(93, 25, 'CAMPEMENT', 4),
	(94, 25, 'SOWETO', 5),
	(95, 25, 'SICOGI', 6),
	(96, 26, 'AHOUSSABOUGOU', 1),
	(97, 26, '3 AMPOULES', 2),
	(98, 26, 'MARCHÉ DJE KONAN', 3),
	(99, 26, 'SOLEIL', 4),
	(100, 26, 'GELTI', 5),
	(101, 27, 'REMBLAIS', 1),
	(102, 27, 'MARAIS', 2),
	(103, 27, 'DIVO', 3),
	(104, 27, 'KOUMASSI 32', 4),
	(105, 27, 'TERM 05', 5),
	(106, 27, '3 AMPOULES', 6),
	(107, 27, 'AHOUSSABOUGOU', 7),
	(108, 28, 'CITÉ 147', 1),
	(109, 28, 'PRODOMO', 2),
	(110, 28, 'SOPIM', 3),
	(111, 28, 'CAMPEMENT', 4),
	(112, 28, 'SOWETO', 5),
	(113, 28, 'SICOGI', 6),
	(114, 28, 'MARCHÉ DJE KONAN', 7),
	(115, 28, 'SOLEIL', 8),
	(116, 29, 'PORT BOUET CENTRE', 1),
	(117, 29, 'CITÉ POLICIÈRE', 2),
	(118, 29, 'PETIT BASSAM', 3),
	(119, 29, 'VRIDI', 4),
	(120, 30, 'AÉROPORT', 1),
	(121, 30, 'ADJAWUI', 2),
	(122, 31, 'JEAN FOLLY', 1),
	(123, 31, 'ADJOUFOU', 2),
	(124, 32, 'TERRE ROUGE', 1),
	(125, 32, 'CORRIDOR', 2),
	(126, 32, 'ANANI', 3),
	(127, 33, 'PORT BOUET', 1),
	(128, 34, 'MOCKEYVILLE', 1),
	(129, 34, 'UNIVERSITÉ AMÉRICAINE', 2),
	(130, 34, 'EDOUKOU MIEZAN', 3),
	(131, 34, 'QUARTIER ARTISANAL', 4),
	(132, 34, 'MODESTE', 5),
	(133, 34, 'ANANI', 6),
	(134, 34, 'MOOSOU 1', 7),
	(135, 35, 'VETOCO', 1),
	(136, 35, 'MOOSOU2', 2),
	(137, 35, 'IMPERIAL', 3),
	(138, 35, 'DOS', 4),
	(139, 35, 'QUARTIER FRANCE', 5),
	(140, 35, 'DIOULABOUGOU', 6),
	(141, 35, 'AZURETI', 7),
	(142, 36, 'ANANI', 1),
	(143, 36, 'DOS', 2),
	(144, 36, 'DIOULABOUGO', 3),
	(145, 36, 'PETIT MARCHÉ', 4),
	(146, 37, '8 KILOS', 1),
	(147, 37, 'YAOU', 2),
	(148, 37, 'CENTRE VILLE', 3),
	(149, 37, 'BEGNERI', 4),
	(150, 37, 'SAMO', 5),
	(151, 37, 'ASSINIE', 6),
	(152, 38, '8 KILOS', 1),
	(153, 38, 'YAOU', 2),
	(154, 38, 'CENTRE VILLE', 3),
	(155, 38, 'BEGNERI', 4),
	(156, 38, 'SAMO', 5),
	(157, 38, 'ASSINIE', 6),
	(158, 39, '8 KILOS', 1),
	(159, 39, 'YAOU', 2),
	(160, 39, 'CENTRE VILLE', 3),
	(161, 39, 'BEGNERI', 4),
	(162, 40, 'DJELIBA', 1),
	(163, 40, 'TP', 2),
	(164, 40, 'PARCERELLE', 3),
	(165, 40, 'KONAN KAN', 4),
	(166, 40, 'BOIS BLANC', 5),
	(167, 40, 'AYEBO', 6),
	(168, 40, 'ADAOU', 7),
	(169, 41, 'DIATEKRO', 1),
	(170, 41, 'SOKORA', 2),
	(171, 41, 'CCE', 3),
	(172, 41, 'WATTVILLE', 4),
	(173, 41, 'BELLEVILLE', 5),
	(174, 41, 'SOS', 6),
	(175, 41, 'DOSOBAH', 7),
	(176, 41, 'CITÉ KOUMI', 8),
	(177, 41, 'LYCÉE', 9),
	(178, 41, 'KRINDJABO', 10),
	(179, 41, 'KOLAIWA', 11),
	(180, 41, 'SANHOUMAN', 12),
	(181, 42, 'AYAMÉ', 1),
	(182, 42, 'EBIKRA', 2),
	(183, 42, 'AKRESIE', 3),
	(184, 42, 'N’ZIKRO', 4),
	(185, 42, 'BABADOUGOU', 5),
	(186, 42, 'EBOUÉ', 6),
	(187, 42, 'ABY', 7),
	(188, 42, 'ADJOUAN', 8),
	(189, 42, 'MOYASSUÉ', 9),
	(190, 42, 'AKAKRO', 10),
	(191, 42, 'V1', 11),
	(192, 42, 'V2', 12),
	(193, 42, 'KRINDJABO', 13),
	(194, 42, 'KASSIKRO', 14),
	(195, 43, 'ADIAKÉ', 1),
	(196, 43, 'ABOISSO', 2),
	(197, 43, 'AYAMÉ', 3),
	(198, 43, 'KRINDJABO', 4),
	(199, 43, 'NOÉ', 5),
	(200, 43, 'ASSE', 6);
INSERT INTO public.quartier VALUES
	(201, 43, 'SOUMIÉ', 7),
	(202, 43, 'N''ZIKRO', 8),
	(203, 43, 'KOFFIKRO', 9),
	(204, 43, 'BABADOUGOU', 10),
	(205, 43, 'CARF AHENOUA', 11),
	(206, 43, 'ADAOU', 12),
	(207, 44, 'AGBAN VILLAGE', 1),
	(208, 44, 'CITE FERMONT', 2),
	(209, 44, 'ATTECOUBE CENTRE', 3),
	(210, 44, 'PLATEAU CENTRE', 4),
	(211, 44, 'MARCHE DE FRUIT', 5),
	(212, 45, 'AGBAN VILLAGE', 1),
	(213, 45, 'CITE FERMONT', 2),
	(214, 45, 'ATTECOUBE CENTRE', 3),
	(215, 45, 'PLATEAU CENTRE', 4),
	(216, 45, 'MARCHE DE FRUIT', 5),
	(217, 46, 'YOPOUGON 1 & 2', 1),
	(218, 47, 'WASSAKARA', 1),
	(219, 47, 'SELMER', 2),
	(220, 47, 'SICOGI', 3),
	(221, 48, 'WASSAKARA', 1),
	(222, 48, 'SELMER', 2),
	(223, 48, 'SICOGI', 3),
	(224, 49, 'YOPOUGON SABLE', 1),
	(225, 49, 'MILLIONNAIRE', 2),
	(226, 49, 'NOUVEAU QUARTIER', 3),
	(227, 50, 'YOPOUGON SABLE', 1),
	(228, 50, 'MILLIONNAIRE', 2),
	(229, 50, 'NOUVEAU QUARTIER', 3),
	(230, 51, 'NIANGON NORD', 1),
	(231, 51, 'SIDECI', 2),
	(232, 52, 'TOIT ROUGE', 1),
	(233, 52, 'LOKODJRO', 2),
	(234, 52, 'ATTECOUBE MOSSIKRO', 3),
	(235, 53, 'TOIT ROUGE', 1),
	(236, 53, 'LOKODJRO', 2),
	(237, 53, 'ATTECOUBE MOSSIKRO', 3),
	(238, 54, 'NIANGON SUD', 1),
	(239, 54, 'AZITO', 2),
	(240, 55, 'NIANGON SUD', 1),
	(241, 55, 'AZITO', 2),
	(242, 56, 'KOUTÉ', 1),
	(243, 56, 'PETIT TOIT ROUGE', 2),
	(244, 56, 'BÉAGO', 3),
	(245, 57, 'KOUTÉ', 1),
	(246, 57, 'PETIT TOIT ROUGE', 2),
	(247, 57, 'BÉAGO', 3),
	(248, 58, 'KOWEIT', 1),
	(249, 58, 'SANTÉ', 2),
	(250, 58, 'ABOBO DOUMÉ', 3),
	(251, 58, 'AGBAYATÉ', 4),
	(252, 59, 'KOWEIT', 1),
	(253, 59, 'YOPOUGON SANTÉ', 2),
	(254, 59, 'ABOBO DOUMÉ', 3),
	(255, 59, 'AGBAYATÉ', 4),
	(256, 60, 'ANDOKOI', 1),
	(257, 60, 'UNIWAX', 2),
	(258, 60, 'CRF ZONE', 3),
	(259, 60, 'PRISON CIVILE', 4),
	(260, 60, 'SODEFOR ET CITÉ ADO', 5),
	(261, 61, 'ZONE INDUSTRIELLE', 1),
	(262, 61, 'MICAO', 2),
	(263, 61, 'GESCO FOURRIÈRE', 3),
	(264, 61, 'PK22', 4),
	(265, 61, 'SIKENSI', 5),
	(266, 61, 'ATTINGUÉ', 6),
	(267, 62, 'ANDOKOI', 1),
	(268, 62, 'UNIWAX', 2),
	(269, 62, 'ZONE INDUSTRIELLE', 3),
	(270, 62, 'MICAO GESCO FOURRIÈRE', 4),
	(271, 62, 'PRISON CIVILE', 5),
	(272, 62, 'SODEFOR', 6),
	(273, 62, 'CITÉ ADO......', 7),
	(274, 63, 'ANDOKOI', 1),
	(275, 63, 'UNIWAX', 2),
	(276, 63, 'ZONE INDUSTRIELLE', 3),
	(277, 63, 'MICAO', 4),
	(278, 63, 'GESCO FOURRIÈRE', 5),
	(279, 63, 'PRISON CIVILE', 6),
	(280, 63, 'SODEFOR ET CITÉ ADO....', 7),
	(281, 64, 'SIPOREX', 1),
	(282, 64, 'BANCO2', 2),
	(283, 64, 'ABOULAYE DIALLO', 3),
	(284, 64, 'ANANERAIE', 4),
	(285, 64, 'MAMIE ADJOUA', 5),
	(286, 64, 'PORT BOUET 2', 6),
	(287, 64, 'CRF CHU', 7),
	(288, 64, 'MOSQUÉE KOUDOUS', 8),
	(289, 65, 'PORT BOUET 2', 1),
	(290, 65, 'CRF CHU', 2),
	(291, 65, 'MOSQUÉE KOUDOUS', 3),
	(292, 65, 'ANANERAIE', 4),
	(293, 65, 'FUSCOM PORT BOUET 2', 5),
	(294, 65, 'RD POINT GESCO', 6),
	(295, 66, 'ANANERAIE', 1),
	(296, 66, 'GESCO RD POINT', 2),
	(297, 66, 'BATIM', 3),
	(298, 66, 'MAMIE ADJOUA', 4),
	(299, 67, 'LUBAFRIQUE', 1),
	(300, 67, 'JATARK', 2),
	(301, 67, 'LOKOA', 3),
	(302, 67, 'CITÉ VERTE', 4),
	(303, 67, 'BAGNON', 5),
	(304, 67, 'LIÈVRE ROUGE', 6),
	(305, 67, 'KM17', 7),
	(306, 67, 'BIMBRESSO', 8),
	(307, 68, 'MATY', 1),
	(308, 68, 'CANARI', 2),
	(309, 68, 'ANTENNE', 3),
	(310, 68, 'SICOGI ATTIÉ', 4),
	(311, 68, 'NIANGON À DROITE', 5),
	(312, 68, 'NIANGON CONTINUE', 6),
	(313, 68, 'CITÉ EECI', 7),
	(314, 69, 'KM17', 1),
	(315, 69, 'BIMBRESSO', 2),
	(316, 69, '́JATARK', 3),
	(317, 69, 'LOKOA CITÉ VERTE', 4),
	(318, 69, 'LIÈVRE ROUGE', 5),
	(319, 70, 'SICOGI ATTIÉ', 1),
	(320, 70, 'ST ANDRÉ CÔTÉ DROIT', 2),
	(321, 70, 'PMI', 3),
	(322, 70, 'AIMÉ CESAIRE', 4),
	(323, 70, 'BON PRIX', 5),
	(324, 70, 'CRF BOBY & POLICIER CÔTÉ DROIT', 6),
	(325, 70, 'BAR ECLA', 7),
	(326, 71, 'TERMINUS 47 SECTEUR DROIT', 1),
	(327, 71, 'SICOGI PMI', 2),
	(328, 71, 'TIKEN DJA', 3),
	(329, 71, 'BMW', 4),
	(330, 71, 'KIMI', 5),
	(331, 72, 'ACADÉMIE', 1),
	(332, 72, 'FIN GOUDRON', 2),
	(333, 72, 'PAYS BAS', 3),
	(334, 72, 'CAISTAB', 4),
	(335, 72, 'CITÉ LAURIER', 5),
	(336, 72, 'CITÉ VERTE', 6),
	(337, 73, 'MAROC', 1),
	(338, 73, 'ANANERAIE', 2),
	(339, 73, 'PORT BOUET 2', 3),
	(340, 73, 'LUBAFRIQUE', 4),
	(341, 73, 'NIANGON À DROITE', 5),
	(342, 73, 'TEXACO À DROITE', 6),
	(343, 74, 'SONGON', 1),
	(344, 74, 'N’DJEM', 2),
	(345, 74, 'CARREFOUR JACQUESVILLE', 3),
	(346, 74, 'JACQUESVILLE VILLE', 4),
	(347, 74, 'DABOU', 5),
	(348, 74, 'N’ZEKREZESSOU....', 6),
	(349, 75, 'GRAND LAHOU', 1),
	(350, 75, 'CRF GRAND LAHOU', 2),
	(351, 75, 'CRF FRESCO', 3),
	(352, 75, 'FRESCO VILLE ET PÉRIPHÉRIES', 4),
	(353, 76, 'DABOU VILLE', 1),
	(354, 76, 'SONGON', 2),
	(355, 76, 'CARREFOUR JACQUESVILLE....', 3),
	(356, 77, 'SONGON', 1),
	(357, 77, 'CARREFOUR JACQUESVILLE', 2),
	(358, 77, 'JACQUESVILLE', 3),
	(359, 77, 'DABOU', 4),
	(360, 77, 'GRAND LAHOU', 5),
	(361, 77, 'FRESCO', 6),
	(362, 78, 'DOKUI', 1),
	(363, 78, 'ANADOR', 2),
	(364, 78, 'COCO SERVICE DERRIÈRE UNIVERSITÉ ABOBO', 3),
	(365, 78, 'ADJAMÉ', 4),
	(366, 78, 'ALEPE', 5),
	(367, 79, 'AVOCATIER', 1),
	(368, 79, 'BC AUTOUTE', 2),
	(369, 79, 'NOUVELLE GARE', 3),
	(370, 79, 'AGNISSANKOI', 4),
	(371, 79, 'BC', 5),
	(372, 80, 'SAMANKE', 1),
	(373, 80, 'KOLETCHA', 2),
	(374, 80, 'ABOBO BAOULE', 3),
	(375, 80, 'BIABOU', 4),
	(376, 81, 'AKEIKOI', 1),
	(377, 81, 'HABITAT', 2),
	(378, 81, 'AGBEKOI', 3),
	(379, 81, 'HOUPHOUT BOIGNY', 4),
	(380, 82, 'LYCEE MODERNE', 1),
	(381, 82, 'ETOILE', 2),
	(382, 82, 'GENDARMERIE', 3),
	(383, 82, 'BON PRIX GENDARMERIE', 4),
	(384, 82, 'CHATTONS', 5),
	(385, 83, 'CITE POLICIERE', 1),
	(386, 83, 'CAMP COMMANDO', 2),
	(387, 83, 'CNPS', 3),
	(388, 83, 'AVENUE KAZA', 4),
	(389, 83, 'COLATIER', 5),
	(390, 84, 'ABOBO GARE', 1),
	(391, 84, 'MAIRIE', 2),
	(392, 85, 'MOSQUE BLANCHE', 1),
	(393, 85, 'ANOKOUA KOUTE', 2),
	(394, 85, 'MARAHOUE', 3),
	(395, 85, 'AGRIPAC', 4),
	(400, 87, 'SODECI', 1),
	(401, 87, 'ONUCI', 2),
	(402, 87, 'SOTRAPIM', 3),
	(403, 87, 'CARREFOUR DIALLO', 4),
	(404, 87, 'TAXI BAGAGE', 5);
INSERT INTO public.quartier VALUES
	(410, 89, 'CMA', 1),
	(411, 89, 'COCCINELLE', 2),
	(412, 89, 'CONCORDE', 3),
	(413, 89, 'BOIS SEC', 4),
	(414, 89, 'DELICE DE FRANCE', 5),
	(415, 89, 'ANCIEN MARCHE', 6),
	(416, 89, 'UNICAFE', 7),
	(417, 89, 'FEU ENCIENNE GENDARMERIE', 8),
	(418, 90, 'ANCIENNE GENDARMERIE', 1),
	(419, 90, 'BELLE VILLE MORGUE', 2),
	(420, 90, 'GARE', 3),
	(421, 90, 'ADZOPE', 4),
	(422, 90, 'AGBOVILLE', 5),
	(423, 93, 'CHÄTEAU', 1),
	(424, 91, 'CHÄTEAU', 1),
	(425, 93, 'MARCHE COLA', 2),
	(426, 91, 'MARCHE COLA', 2),
	(427, 93, 'MARCHE D''ANYAMA', 3),
	(428, 91, 'MARCHE D''ANYAMA', 3),
	(429, 93, 'DON ORION', 4),
	(430, 91, 'DON ORION', 4),
	(431, 93, 'AZAGUIE', 5),
	(432, 91, 'AZAGUIE', 5),
	(433, 93, 'BILDA AZAGUIE AWA ATTINGUE', 6),
	(434, 91, 'BILDA AZAGUIE AWA ATTINGUE', 6),
	(443, 93, 'MACHE CHAKA KONE', 11),
	(444, 91, 'MACHE CHAKA KONE', 11),
	(445, 92, 'ANYAMA', 1),
	(446, 92, 'PLAQUE ARABE', 2),
	(447, 92, 'ANYAMA RESIDENTIEL', 3),
	(448, 92, 'EBIMPE', 4),
	(449, 94, 'AXE AUTOROUTE N''DOTRE', 1),
	(450, 94, 'DANDI', 2),
	(451, 94, 'COMPLEXE', 3),
	(452, 94, 'MAIRIE', 4),
	(453, 95, 'ANCIENNE GENDARMERIE', 1),
	(454, 95, 'BELLE VILLE MORGUE', 2),
	(455, 95, 'GARE', 3),
	(456, 96, 'BANDJI', 1),
	(457, 96, 'N''DOTRE EXTENSION', 2),
	(458, 96, 'CELESTE', 3),
	(459, 96, 'NOUVELLE CASSE', 4),
	(460, 96, 'ARC EN CIEL', 5),
	(461, 96, 'DANDY', 6),
	(462, 96, 'KOBAKRO', 7),
	(463, 96, 'TERRE ROUGE', 8),
	(464, 96, 'AKWABA', 9),
	(465, 97, 'BANDJI', 1),
	(466, 97, 'N''DOTRE EXTENSION', 2),
	(467, 97, 'CELESTE', 3),
	(468, 97, 'NOUVELLE CASSE', 4),
	(469, 97, 'ARC EN CIEL', 5),
	(470, 97, 'DANDY', 6),
	(471, 97, 'KOBAKRO', 7),
	(472, 97, 'TERRE ROUGE', 8),
	(473, 97, 'AKWABA', 9),
	(474, 98, '220LGTS', 1),
	(475, 98, 'LIBERTÉ', 2),
	(476, 98, 'QUARTIER LATIN', 3),
	(477, 98, 'BRACODI', 4),
	(478, 98, 'TERRASSE', 5),
	(479, 98, 'RENAULT', 6),
	(480, 99, 'WILLIAMSVILLE', 1),
	(481, 99, 'MACACI', 2),
	(482, 99, 'PAILLET', 3),
	(483, 99, 'VIDANGE', 4),
	(484, 99, 'HMA', 5),
	(485, 100, 'SAPEUR POMPIER', 1),
	(486, 100, 'SAINT MICHEL', 2),
	(487, 100, 'QUARTIER EBRIÉ', 3),
	(488, 100, 'DALLAS', 4),
	(489, 101, 'NANGUI ABROGOUA', 1),
	(490, 101, 'MARCHE GOURO', 2),
	(491, 101, 'BLACK MARKET', 3),
	(492, 101, 'MIRADOR', 4),
	(493, 101, 'NOUVELLE GARE', 5),
	(494, 102, 'BRAMACOTÉ', 1),
	(495, 102, 'DÉLÉGATION', 2),
	(496, 102, 'CITÉ RAN', 3),
	(497, 102, 'FORUM', 4),
	(498, 103, 'TERRITOIRE ADJAMÉ', 1),
	(499, 104, 'ADZOPE VILLE', 1),
	(500, 105, 'AKOUPE', 1),
	(501, 105, 'YAKASSE ATTOBROU', 2),
	(502, 105, 'ANDE', 3),
	(503, 105, 'YAKASSE ME', 4),
	(504, 106, 'AGBOVILLE VILLE', 1),
	(505, 106, 'N''DOUCI', 2),
	(506, 106, 'SIKENSI', 3),
	(507, 107, 'AZAGUIE', 1),
	(508, 107, 'PETIT YAPO', 2),
	(509, 107, 'GRAND YAPO', 3),
	(510, 107, 'RUBINO', 4),
	(511, 107, 'SECHI', 5),
	(512, 108, 'CAFETOUTOU', 1),
	(513, 108, 'AGNIKRO', 2),
	(514, 108, 'ADOUKOFFIKRO', 3),
	(515, 108, 'GARE DE NIABLE', 4),
	(516, 108, 'AFFALIKRO', 5),
	(517, 108, 'ANGOUAKRO', 6),
	(518, 108, 'DRAMANKRO', 7),
	(519, 108, 'NIABLE', 8),
	(520, 108, 'ADAOU', 9),
	(521, 108, 'BAOULEKRO', 10),
	(522, 109, 'COMMERCE', 1),
	(523, 109, 'RELAIS', 2),
	(524, 109, 'HKB', 3),
	(525, 109, 'LOBIKRO', 4),
	(526, 109, 'CAMP MILITAIRE', 5),
	(527, 109, 'PLATEAU', 6),
	(528, 110, 'RESIDENTIEL', 1),
	(529, 110, '120 LGMT', 2),
	(530, 110, 'CHICAGO', 3),
	(531, 110, 'BAOULEKRO', 4),
	(532, 110, 'DIOULAKRO', 5),
	(533, 110, 'GAGOU', 6),
	(534, 110, 'OUELLE', 7),
	(535, 110, 'GRAV D''OR', 8),
	(536, 110, 'COMMERCE', 9),
	(537, 110, 'KREGBE', 10),
	(538, 110, 'SOSSOBOUGOU', 11),
	(539, 111, 'ADAOU', 1),
	(540, 111, 'ADOUKOFIKRO', 2),
	(541, 111, 'BAOULEKRO', 3),
	(542, 111, 'CAFETOU', 4),
	(543, 111, 'AGNIKRO', 5),
	(544, 111, 'CMP MILITAIRE', 6),
	(545, 111, 'COMMERCE', 7),
	(546, 111, 'DIOULAKRO', 8),
	(547, 111, 'HKB', 9),
	(548, 111, 'LOBKRO', 10),
	(549, 111, 'PLATX', 11),
	(550, 111, 'RELAIS', 12),
	(551, 112, 'BONAHOUIN', 1),
	(552, 112, 'ARRAH', 2),
	(553, 112, 'BONGOUANOU', 3),
	(554, 112, 'APRONPRON', 4),
	(555, 112, 'ASSIKASSO', 5),
	(556, 112, 'AGNIBILEKRO', 6),
	(557, 112, 'ANDE', 7),
	(558, 112, 'APKAOUSSOU', 8),
	(559, 112, 'DAOUKRO', 9),
	(560, 112, 'TANKESSE', 10),
	(561, 112, 'ANUANSUE', 11),
	(562, 113, 'Bonon', 1),
	(563, 113, 'Garango', 2),
	(564, 113, 'Gobazra', 3),
	(565, 113, 'Bouaflé', 4),
	(566, 113, 'Zougoussou', 5),
	(567, 113, 'Zambakro', 6),
	(568, 113, 'Zuenoula', 7),
	(569, 114, 'Sopim', 1),
	(570, 114, 'Makora - Belleville', 2),
	(571, 114, 'Kokrenou 1', 3),
	(572, 114, 'Kokrenou 2', 4),
	(573, 114, 'Kokrenou 3', 5),
	(574, 114, 'Kokenou 4', 6),
	(575, 115, 'Assabou 1', 1),
	(576, 115, 'Djahakro', 2),
	(577, 115, '50 & 227 logements', 3),
	(578, 115, 'INPHB', 4),
	(579, 115, 'Assabou 2', 5),
	(580, 115, '220 logements', 6),
	(581, 116, 'Dioulabougou 1', 1),
	(582, 116, 'Dioulabougou 2', 2),
	(583, 116, 'Dioulabougou 3', 3),
	(584, 116, 'Dioulabougou 4', 4),
	(585, 116, 'Dioulabougou 5', 5),
	(586, 116, 'Dioulabougou 6', 6),
	(587, 117, 'Morofé', 1),
	(588, 117, 'Morofé extention', 2),
	(589, 117, 'Morofé 2', 3),
	(590, 117, 'Morofé 3 -Habitat 1', 4),
	(591, 117, 'Habitat', 5),
	(592, 118, 'Toumodi', 1),
	(593, 119, 'Dimbokro ville', 1),
	(594, 120, 'Toumodi', 1),
	(595, 120, 'Dimbokro', 2),
	(596, 120, 'M''batto', 3),
	(597, 120, 'Bocanda', 4),
	(598, 121, 'Sokoura', 1),
	(599, 121, 'Commerce', 2),
	(600, 121, 'Centre Ivoire', 3),
	(601, 121, 'Houphouet-Ville', 4),
	(602, 121, 'Nimbo', 5),
	(603, 121, 'Djamourou', 6),
	(604, 121, 'Dare_Salam', 7),
	(605, 121, 'Tola', 8),
	(606, 121, 'Maroc', 9),
	(607, 122, 'Koko', 1),
	(608, 122, 'Audjenekourani', 2),
	(609, 122, 'Hypodrome', 3),
	(610, 122, 'Beaufort', 4),
	(611, 122, 'Zone', 5),
	(612, 122, 'Gonvreville', 6),
	(614, 122, 'Habitat Gonvreville', 8),
	(615, 123, 'Cmrce', 1),
	(616, 123, 'Sokoura', 2),
	(617, 123, 'Marche', 3),
	(618, 123, 'Boniere', 4);
INSERT INTO public.quartier VALUES
	(619, 123, 'Bokala', 5),
	(620, 123, 'Dare salam', 6),
	(621, 123, 'Belle ville', 7),
	(622, 123, 'Air Frce', 8),
	(623, 123, 'Djanbourou', 9),
	(624, 123, 'Zone', 10),
	(625, 123, 'Sakasou', 11),
	(626, 123, 'Tola', 12),
	(627, 124, 'Commerce', 1),
	(628, 124, 'Nguattakro', 2),
	(629, 124, 'Ahougnansou', 3),
	(630, 124, 'Houphouet ville', 4),
	(631, 124, 'Broukro', 5),
	(632, 124, 'Sicogi', 6),
	(633, 124, 'Ndakro', 7),
	(634, 124, 'Campus', 8),
	(635, 124, 'Adje yaokro', 9),
	(636, 124, 'Tchelekro', 10),
	(637, 125, 'Bouaké ville', 1),
	(638, 126, 'Grand marche', 1),
	(639, 126, 'Nimbo', 2),
	(640, 126, 'Kennedi', 3),
	(641, 126, 'Sokoura', 4),
	(642, 127, 'Air France 1,2,3', 1),
	(643, 127, 'Corridor sud', 2),
	(644, 128, 'Dares salam Djambourou', 1),
	(645, 128, 'Abattoir', 2),
	(646, 128, 'Laraba', 3),
	(647, 128, 'Corridor Nord', 4),
	(648, 129, 'Belle ville 1,2,3', 1),
	(649, 129, 'Campement', 2),
	(650, 130, 'Grand marche', 1),
	(651, 130, 'Satama Sokora', 2),
	(652, 130, 'Brobo', 3),
	(653, 130, 'M''bahiakro', 4),
	(654, 130, 'Niakara', 5),
	(655, 130, 'Dabakala', 6),
	(656, 131, 'Katiola ville', 1),
	(657, 132, 'Commerce', 1),
	(658, 132, 'Boulevard Ado', 2),
	(659, 132, 'Voie kafoudal', 3),
	(660, 132, 'Voie de Mbengue', 4),
	(661, 132, 'Tarato', 5),
	(662, 132, 'Siempurgo', 6),
	(663, 132, 'Boundiali', 7),
	(664, 132, 'Gbon', 8),
	(665, 132, 'Kouto', 9),
	(666, 132, 'Tengréla', 10),
	(667, 133, 'Quartier 14', 1),
	(668, 133, 'Air France', 2),
	(669, 133, 'Sinistré', 3),
	(670, 133, 'Sodepra', 4),
	(671, 133, 'Cite des medecins', 5),
	(672, 133, 'Tiékélézo', 6),
	(673, 133, 'Prémafolo', 7),
	(674, 133, 'Soba', 8),
	(675, 133, 'Kassirimé', 9),
	(676, 134, 'Haoussadougou', 1),
	(677, 134, 'Petit Paris', 2),
	(678, 134, 'Soba', 3),
	(679, 135, 'Nouveau Quartier', 1),
	(680, 135, 'Sossorobougou', 2),
	(681, 135, 'Cocody', 3),
	(682, 135, 'Klofohakaha', 4),
	(683, 136, 'Boundiali & Environs', 1),
	(684, 137, 'Ferkessedougou & Environs SICAF1', 1),
	(685, 137, 'SICAF2', 2),
	(686, 138, 'Bouna', 1),
	(687, 138, 'Doropo', 2),
	(688, 138, 'Tanda', 3),
	(689, 139, 'Bondoukou 1', 1),
	(690, 140, 'Bondoukou 2', 1),
	(691, 141, 'Labia', 1),
	(692, 141, 'Mossibougou', 2),
	(693, 141, 'Texas', 3),
	(694, 141, 'Huberson', 4),
	(695, 141, 'Millionnaire', 5),
	(696, 141, 'Soleil', 6),
	(697, 141, 'Kenedy2', 7),
	(698, 141, 'Suisse', 8),
	(699, 141, 'Grand marche', 9),
	(700, 141, 'ORLY', 10),
	(701, 141, 'Flora', 11),
	(702, 142, 'Abattoir', 1),
	(703, 142, 'Marche Manioc', 2),
	(704, 142, 'Garage', 3),
	(705, 142, 'Orly plateau', 4),
	(706, 142, 'Dioulabougou', 5),
	(707, 143, 'Commerce', 1),
	(708, 143, 'Kani', 2),
	(709, 143, 'Mankono', 3),
	(710, 143, 'Serela', 4),
	(711, 143, 'Kouenahiri', 5),
	(712, 144, 'Commerce', 1),
	(713, 144, 'Kani', 2),
	(714, 144, 'Mankona', 3),
	(715, 145, 'Diomande', 1),
	(716, 145, 'Traoré', 2),
	(717, 145, 'Rymer', 3),
	(718, 145, 'Quartier Grarge', 4),
	(719, 145, 'Garage Angola', 5),
	(720, 145, 'Sifie', 6),
	(721, 145, 'Kouego', 7),
	(722, 146, 'Séguéla', 1),
	(723, 146, 'Mankono', 2),
	(724, 146, 'Kani', 3),
	(725, 146, 'Dianra', 4),
	(726, 147, 'Marche', 1),
	(727, 147, 'Zele', 2),
	(728, 147, 'Dayagoine', 3),
	(729, 147, 'Municipal', 4),
	(730, 147, 'Campus', 5),
	(731, 147, 'Quartier thérèse', 6),
	(732, 148, 'Cafop', 1),
	(733, 148, 'Camp SEA', 2),
	(734, 148, 'Lycée club', 3),
	(735, 148, 'Commerce', 4),
	(736, 148, 'Koko', 5),
	(737, 148, 'Libreville', 6),
	(738, 149, 'Biankouma', 1),
	(739, 149, 'Bafing', 2),
	(740, 149, 'Touba', 3),
	(741, 149, 'Koro', 4),
	(742, 149, 'Complexe', 5),
	(743, 149, 'Sangouine', 6),
	(744, 150, 'Man ville', 1),
	(745, 151, 'Nanbouhi', 1),
	(746, 151, 'Camp manoir', 2),
	(747, 151, 'Chateau résidentiel', 3),
	(748, 151, 'Gabon', 4),
	(749, 151, 'Gbakalepa', 5),
	(750, 151, 'Yabayo', 6),
	(751, 152, 'Anoumanbo', 1),
	(752, 152, 'Hibiscus', 2),
	(753, 152, 'Sicogi', 3),
	(754, 152, 'Sans fil', 4),
	(755, 152, 'Zone 4', 5),
	(756, 152, 'KBF', 6),
	(757, 153, 'Okrouyo', 1),
	(758, 153, 'Guehio', 2),
	(759, 153, 'Buyo', 3),
	(760, 153, 'Bakayo', 4),
	(761, 153, 'osserie', 5),
	(762, 153, 'logboville', 6),
	(763, 153, 'Dapea', 7),
	(764, 153, 'lessirie', 8),
	(765, 153, 'commerce', 9),
	(766, 153, 'kpeiri', 10),
	(767, 153, 'opouyo', 11),
	(768, 153, 'cité ouvriere', 12),
	(769, 154, 'Issia & Environs (mira, zobia, commerce, Saioua)', 1),
	(770, 155, 'Monogaga', 1),
	(771, 155, 'Dabiho', 2),
	(772, 155, 'Marche', 3),
	(773, 155, 'Doupoudou', 4),
	(774, 156, 'Grand marche', 1),
	(775, 156, 'Bereby', 2),
	(776, 156, 'Commerce', 3),
	(777, 157, 'Cité', 1),
	(778, 157, 'Jule Ferry', 2),
	(779, 157, 'Lac', 3),
	(780, 157, 'Sewke', 4),
	(781, 157, 'Bardot', 5),
	(782, 158, 'Lac', 1),
	(783, 158, 'Jules ferry', 2),
	(784, 158, 'Zone industrielle', 3),
	(785, 158, 'Bardot', 4),
	(786, 159, 'Corridor', 1),
	(787, 159, 'Gare', 2),
	(788, 159, 'Sotref', 3),
	(789, 159, 'Dafci', 4),
	(790, 160, 'Zapata', 1),
	(791, 160, 'Garahio', 2),
	(792, 160, 'Babre', 3),
	(793, 160, 'Soleil', 4),
	(794, 160, 'Dioulabougou', 5),
	(795, 161, 'Dares salam', 1),
	(796, 161, 'Grarage Koffi', 2),
	(797, 161, 'Garage Dosso', 3),
	(798, 161, 'Corridor Sinfra', 4),
	(799, 162, 'Gagnoa 2', 1),
	(800, 162, 'Guiberoua', 2),
	(801, 162, 'Issia', 3),
	(802, 162, 'Gueyo', 4),
	(803, 163, 'Commerce', 1),
	(804, 163, 'Gbakayo', 2),
	(805, 163, 'Galebre', 3),
	(806, 163, 'Tchedelei', 4),
	(807, 164, 'Soleil', 1),
	(808, 164, 'Delbo', 2),
	(809, 164, 'Millionnaire', 3),
	(810, 164, 'Commerce', 4),
	(811, 165, 'Dioulabougou', 1),
	(812, 165, 'Katalina', 2),
	(813, 165, 'Commerce', 3),
	(814, 165, 'Gbakayo', 4),
	(815, 166, 'Doukakou', 1),
	(816, 166, 'Sokoura', 2),
	(817, 166, 'Commerce', 3),
	(818, 166, 'Bribore', 4);
INSERT INTO public.quartier VALUES
	(819, 167, 'Konankro', 1),
	(820, 167, 'Libanais', 2),
	(821, 167, 'Jerusalem', 3),
	(822, 167, 'Dialogue 2', 4),
	(823, 167, 'Dioulabougou', 5),
	(824, 168, 'Commerce', 1),
	(825, 168, 'Dialogue 1', 2),
	(826, 168, 'Gremian', 3),
	(827, 168, 'Benoi', 4),
	(828, 169, 'Guiglo 1 nord', 1),
	(829, 170, 'Guiglo 1 sud', 1),
	(830, 171, 'Guiglo 1', 1),
	(831, 171, 'Duekoué', 2),
	(832, 172, 'Guiglo 2 Nord', 1),
	(833, 173, 'Guiglo 2 sud', 1),
	(834, 174, 'Guiglo 2', 1),
	(835, 174, 'Touba', 2),
	(836, 175, 'Odiénne 1', 1),
	(837, 176, 'Odiénne 2', 1),
	(838, 177, 'Odiénne', 1),
	(839, 177, 'Tiémé', 2),
	(840, 177, 'Madinani', 3),
	(841, 177, 'Samatiguila', 4),
	(842, 178, 'NI3-BLONTIARA', 1),
	(843, 178, 'DOROPO2-DASSIKELE', 2),
	(844, 178, 'BOBOSSO-ZONGO', 3),
	(845, 178, 'commerce', 4),
	(846, 178, 'TEFRO-BOUNA2', 5),
	(847, 178, 'CAMARASSO', 6),
	(848, 179, 'BOUNA', 1),
	(849, 179, 'BROMAKOTE-VARALE', 2),
	(850, 179, 'VARALE-DOROPO', 3),
	(851, 179, 'AXE BOUNA-VONKORO', 4),
	(852, 179, 'AXE BOUNA- MANGO', 5);
INSERT INTO public.reference_produit OVERRIDING SYSTEM VALUE VALUES
	(1, 'Opale 380g', 1, 'soutien'),
	(2, 'FTB 380g', 1, 'a_retirer'),
	(3, 'FT 380g', 1, 'soutien'),
	(4, 'FTB 150g', 1, 'croissance'),
	(5, 'FT 150g', 1, 'phare'),
	(6, 'FT Gold 160g', 1, 'soutien'),
	(7, 'FT tin 2500g', 2, 'soutien'),
	(8, 'FT tin 900g', 2, 'soutien'),
	(9, 'FT tin 400g', 2, 'croissance'),
	(10, 'FT Delice Pouch 350g', 2, 'nouveaute'),
	(11, 'FT Pouch 360g', 2, 'croissance'),
	(12, 'FT Délice 15g', 2, 'nouveaute'),
	(13, 'FT 15g', 2, 'phare'),
	(14, 'Opale 1kg', 3, 'croissance'),
	(15, 'FT 1kg', 3, 'soutien');
INSERT INTO public.region OVERRIDING SYSTEM VALUE VALUES
	(1, 'SOUTHDIV', 'SOUTH DIVISION', 'ABIDJAN', 'CI1'),
	(2, 'NORTHDIV', 'NORTH DIVISION', 'UP COUNTRY', 'CI1');
INSERT INTO public.resultat_perfect_store VALUES
	('ad319135-46fb-4039-bf7a-fded72b7ca77', 'taux_vente', 100, 100, 100, 100, 100.00, 15, true, 100.00, 100.00, 100.00, 'FLAGSHIP STORE', '2026-11-15 14:08:19.360439+00', 100, 100, 100, 100),
	('6c3b3abd-05c0-4a91-b20e-0aaf207797d7', 'taux_vente', 100, 100, 100, 100, 100.00, 15, true, 100.00, 100.00, 100.00, 'FLAGSHIP STORE', '2026-11-15 14:08:19.360439+00', 100, 100, 100, 100),
	('cc6d9a6f-8349-4196-a980-cbd57fae12bd', 'taux_vente', 100, 100, 100, 100, NULL, NULL, NULL, 100.00, 100.00, 100.00, 'FLAGSHIP STORE', '2026-11-15 14:08:19.360439+00', 100, 100, 100, 100),
	('4c4eb96a-56da-477b-be03-6fbd7a400fb7', 'taux_vente', 100, 100, 100, 100, 100.00, 15, true, 100.00, 100.00, 100.00, 'VIP PERFECT STORE', '2026-11-15 14:08:19.360439+00', 100, 100, 100, 100),
	('6b43542c-63bb-4be6-8c83-63a1d4a6fbfa', 'taux_vente', 100, 100, 100, 100, 100.00, 15, true, 100.00, 100.00, 100.00, 'VIP PERFECT STORE', '2026-11-15 14:08:19.360439+00', 100, 100, 100, 100),
	('49543ca4-5145-4a93-a035-09a06ee75755', 'taux_vente', 100, 100, 100, 100, 100.00, 15, true, 100.00, 100.00, 100.00, 'VIP PERFECT STORE', '2026-11-15 14:08:19.360439+00', 100, 100, 100, 100),
	('983d6529-81be-4495-8591-89dd23cea722', 'taux_vente', 100, 100, 100, 100, 100.00, 15, true, 100.00, NULL, 100.00, 'CORE PERFECT STORE', '2026-11-15 14:08:19.360439+00', 100, 100, 100, 100),
	('90ba0356-6d88-4267-9b65-acacd0e69a46', 'taux_vente', 100, 100, 100, 100, 100.00, 15, true, 100.00, NULL, 100.00, 'CORE PERFECT STORE', '2026-11-15 14:08:19.360439+00', 100, 100, 100, 100),
	('5276908e-7942-4bca-a495-2f1d16380040', 'taux_vente', 100, 100, 100, 100, 100.00, 15, true, 100.00, NULL, 100.00, 'CORE PERFECT STORE', '2026-11-15 14:08:19.360439+00', 100, 100, 100, 100),
	('9d75e67a-6248-4c9c-9bdd-0b6d3457247a', 'taux_vente', 100, 100, 100, 100, 100.00, 15, true, 100.00, NULL, 100.00, 'CORE PERFECT STORE', '2026-11-15 14:08:19.360439+00', 100, 100, 100, 100),
	('42db9b2b-f25d-40d5-a25f-50ba1907d9a0', 'taux_vente', 100, NULL, 100, 100, NULL, NULL, NULL, 0.00, NULL, 50.00, NULL, '2026-11-15 14:08:19.360439+00', 100, 100, NULL, 100),
	('d85c0bbf-ee9f-4e61-b00b-1490e4a325bb', 'taux_vente', 100, NULL, 100, 100, NULL, NULL, NULL, 0.00, NULL, 50.00, NULL, '2026-11-15 14:08:19.360439+00', 100, 100, NULL, 100),
	('ab7bb16e-e0a8-48ef-b1aa-bc64cd775db9', 'taux_vente', 0, 0, 0, 0, 0.00, 0, false, 0.00, NULL, 0.00, NULL, '2026-11-15 14:08:19.360439+00', 0, 0, 0, 0),
	('14e9768f-9d69-47bc-a528-a99104ad966d', 'taux_vente', 0, 0, 0, 0, NULL, NULL, NULL, 0.00, NULL, 0.00, NULL, '2026-11-15 14:08:19.360439+00', 0, 0, 0, 0),
	('37df3a9c-460b-4d06-8e29-20bd7caa4195', 'taux_vente', 0, 0, 0, 0, 37.50, 3, true, 50.00, NULL, 25.00, NULL, '2026-11-15 14:08:19.360439+00', 55, 80, 86, 0);
INSERT INTO public.role_section_access VALUES
	('admin', 'principal', true, '2026-11-15 14:07:54.309252+00'),
	('admin', 'pdv', true, '2026-11-15 14:07:54.309252+00'),
	('admin', 'visites', true, '2026-11-15 14:07:54.309252+00'),
	('admin', 'visibilite', true, '2026-11-15 14:07:54.309252+00'),
	('admin', 'concurrence', true, '2026-11-15 14:07:54.309252+00'),
	('admin', 'produits', true, '2026-11-15 14:07:54.309252+00'),
	('admin', 'actions', true, '2026-11-15 14:07:54.309252+00'),
	('superviseur', 'principal', true, '2026-11-15 14:07:54.309252+00'),
	('superviseur', 'pdv', true, '2026-11-15 14:07:54.309252+00'),
	('superviseur', 'visites', true, '2026-11-15 14:07:54.309252+00'),
	('superviseur', 'visibilite', true, '2026-11-15 14:07:54.309252+00'),
	('superviseur', 'concurrence', true, '2026-11-15 14:07:54.309252+00'),
	('superviseur', 'produits', true, '2026-11-15 14:07:54.309252+00'),
	('superviseur', 'actions', true, '2026-11-15 14:07:54.309252+00'),
	('merchandiser', 'principal', false, '2026-11-15 14:07:54.309252+00'),
	('merchandiser', 'pdv', false, '2026-11-15 14:07:54.309252+00'),
	('merchandiser', 'visites', false, '2026-11-15 14:07:54.309252+00'),
	('merchandiser', 'visibilite', false, '2026-11-15 14:07:54.309252+00'),
	('merchandiser', 'concurrence', false, '2026-11-15 14:07:54.309252+00'),
	('merchandiser', 'produits', false, '2026-11-15 14:07:54.309252+00'),
	('merchandiser', 'actions', false, '2026-11-15 14:07:54.309252+00'),
	('admin', 'perfect-store', true, '2026-11-15 14:07:54.521803+00'),
	('superviseur', 'perfect-store', true, '2026-11-15 14:07:54.521803+00'),
	('merchandiser', 'perfect-store', false, '2026-11-15 14:07:54.521803+00'),
	('admin', 'parametres', true, '2026-11-15 14:07:55.256973+00'),
	('superviseur', 'parametres', false, '2026-11-15 14:07:55.256973+00'),
	('merchandiser', 'parametres', false, '2026-11-15 14:07:55.256973+00'),
	('commercial', 'principal', true, '2026-11-15 14:07:56.917929+00'),
	('commercial', 'pdv', true, '2026-11-15 14:07:56.917929+00'),
	('commercial', 'visites', true, '2026-11-15 14:07:56.917929+00'),
	('commercial', 'perfect-store', true, '2026-11-15 14:07:56.917929+00'),
	('commercial', 'visibilite', true, '2026-11-15 14:07:56.917929+00'),
	('commercial', 'concurrence', true, '2026-11-15 14:07:56.917929+00'),
	('commercial', 'produits', true, '2026-11-15 14:07:56.917929+00'),
	('commercial', 'actions', true, '2026-11-15 14:07:56.917929+00'),
	('commercial', 'parametres', false, '2026-11-15 14:07:56.917929+00'),
	('commercial', 'administration', false, '2026-11-15 14:07:56.917929+00');
INSERT INTO public.sales_reps VALUES
	(23, 'Awa Démo'),
	(24, 'Bakary Démo'),
	(25, 'Clarisse Démo');
INSERT INTO public.segment_grade_type_pdv VALUES
	(11, 'TableTop', 'A'),
	(12, 'Porridge', 'A'),
	(14, 'Pushcart', 'B'),
	(15, 'Pushcart', 'A'),
	(16, 'Kiosque', 'B'),
	(17, 'Kiosque', 'A'),
	(18, 'Aboki', 'B'),
	(19, 'Aboki', 'A'),
	(22, 'Minimarket', 'C'),
	(23, 'Minimarket', 'B'),
	(24, 'Minimarket', 'A'),
	(30, 'Boutique', 'C'),
	(31, 'Boutique', 'B'),
	(32, 'Boutique', 'A'),
	(10, 'SupermarcheMT', 'A'),
	(28, 'SupermarcheMT', 'A'),
	(35, 'SupermarcheMT', 'C'),
	(36, 'SupermarcheMT', 'B');
INSERT INTO public.segment_visibilite_type_pdv VALUES
	(11, 'table_top'),
	(12, 'porridge'),
	(13, 'kiosque_aboki'),
	(14, 'pushcart'),
	(15, 'pushcart'),
	(16, 'kiosque_aboki'),
	(17, 'kiosque_aboki'),
	(18, 'kiosque_aboki'),
	(19, 'kiosque_aboki'),
	(22, 'superette'),
	(23, 'superette'),
	(24, 'superette'),
	(30, 'boutique'),
	(31, 'boutique'),
	(32, 'boutique'),
	(38, 'table_top'),
	(10, 'mt'),
	(28, 'mt'),
	(35, 'mt'),
	(36, 'mt');
INSERT INTO public.seuil_disponibilite VALUES
	(1, 'Aboki', 'B', 1),
	(1, 'Aboki', 'A', 2),
	(1, 'Kiosque', 'B', 3),
	(1, 'Kiosque', 'A', 3),
	(1, 'Minimarket', 'B', 18),
	(1, 'Minimarket', 'A', 24),
	(1, 'Boutique', 'C', 10),
	(1, 'Boutique', 'B', 18),
	(1, 'Boutique', 'A', 24),
	(2, 'Minimarket', 'B', 12),
	(2, 'Minimarket', 'A', 12),
	(2, 'Boutique', 'C', 6),
	(2, 'Boutique', 'B', 12),
	(2, 'Boutique', 'A', 12),
	(3, 'Porridge', 'A', 2),
	(3, 'Minimarket', 'B', 18),
	(3, 'Minimarket', 'A', 24),
	(3, 'Boutique', 'C', 10),
	(3, 'Boutique', 'B', 18),
	(3, 'Boutique', 'A', 24),
	(4, 'Minimarket', 'B', 18),
	(4, 'Minimarket', 'A', 24),
	(4, 'Boutique', 'C', 12),
	(4, 'Boutique', 'B', 18),
	(4, 'Boutique', 'A', 24),
	(5, 'Minimarket', 'B', 24),
	(5, 'Minimarket', 'A', 48),
	(5, 'Boutique', 'C', 18),
	(5, 'Boutique', 'B', 36),
	(5, 'Boutique', 'A', 48),
	(6, 'Minimarket', 'B', 12),
	(6, 'Minimarket', 'A', 24),
	(6, 'Boutique', 'C', 12),
	(6, 'Boutique', 'B', 24),
	(6, 'Boutique', 'A', 24),
	(7, 'Minimarket', 'B', 3),
	(7, 'Minimarket', 'A', 3),
	(7, 'Boutique', 'A', 3),
	(8, 'Minimarket', 'B', 3),
	(8, 'Minimarket', 'A', 6),
	(8, 'Boutique', 'B', 3),
	(8, 'Boutique', 'A', 6),
	(9, 'Minimarket', 'B', 6),
	(9, 'Minimarket', 'A', 12),
	(9, 'Boutique', 'C', 3),
	(9, 'Boutique', 'B', 6),
	(9, 'Boutique', 'A', 12),
	(10, 'Minimarket', 'B', 3),
	(10, 'Minimarket', 'A', 6),
	(10, 'Boutique', 'C', 3),
	(10, 'Boutique', 'B', 3),
	(10, 'Boutique', 'A', 6),
	(11, 'Minimarket', 'B', 3),
	(11, 'Minimarket', 'A', 6),
	(11, 'Boutique', 'C', 3),
	(11, 'Boutique', 'B', 3),
	(11, 'Boutique', 'A', 6),
	(12, 'Porridge', 'A', 1),
	(12, 'TableTop', 'A', 1),
	(12, 'Pushcart', 'B', 2),
	(12, 'Pushcart', 'A', 2),
	(12, 'Minimarket', 'B', 12),
	(12, 'Minimarket', 'A', 12),
	(12, 'Boutique', 'C', 3),
	(12, 'Boutique', 'B', 12),
	(12, 'Boutique', 'A', 12),
	(13, 'Minimarket', 'B', 12),
	(13, 'Minimarket', 'A', 12),
	(13, 'Boutique', 'C', 3),
	(13, 'Boutique', 'B', 12),
	(13, 'Boutique', 'A', 12),
	(14, 'Aboki', 'B', 2),
	(14, 'Aboki', 'A', 3),
	(14, 'Kiosque', 'B', 2),
	(14, 'Kiosque', 'A', 3),
	(14, 'Minimarket', 'B', 6),
	(14, 'Minimarket', 'A', 12),
	(14, 'Boutique', 'C', 3),
	(14, 'Boutique', 'B', 6),
	(14, 'Boutique', 'A', 12),
	(15, 'Minimarket', 'B', 3),
	(15, 'Minimarket', 'A', 6),
	(15, 'Boutique', 'A', 3),
	(1, 'SupermarcheMT', 'C', 24),
	(1, 'SupermarcheMT', 'B', 48),
	(1, 'SupermarcheMT', 'A', 48),
	(3, 'SupermarcheMT', 'C', 24),
	(3, 'SupermarcheMT', 'B', 24),
	(3, 'SupermarcheMT', 'A', 48),
	(4, 'SupermarcheMT', 'C', 24),
	(4, 'SupermarcheMT', 'B', 48),
	(4, 'SupermarcheMT', 'A', 96),
	(5, 'SupermarcheMT', 'C', 48),
	(5, 'SupermarcheMT', 'B', 96),
	(5, 'SupermarcheMT', 'A', 144),
	(6, 'SupermarcheMT', 'C', 24),
	(6, 'SupermarcheMT', 'B', 48),
	(6, 'SupermarcheMT', 'A', 96),
	(7, 'SupermarcheMT', 'C', 2),
	(7, 'SupermarcheMT', 'B', 4),
	(7, 'SupermarcheMT', 'A', 6),
	(8, 'SupermarcheMT', 'C', 6),
	(8, 'SupermarcheMT', 'B', 6),
	(8, 'SupermarcheMT', 'A', 12),
	(9, 'SupermarcheMT', 'C', 12),
	(9, 'SupermarcheMT', 'B', 12),
	(9, 'SupermarcheMT', 'A', 24),
	(10, 'SupermarcheMT', 'C', 6),
	(10, 'SupermarcheMT', 'B', 12),
	(10, 'SupermarcheMT', 'A', 30),
	(11, 'SupermarcheMT', 'C', 6),
	(11, 'SupermarcheMT', 'B', 12),
	(11, 'SupermarcheMT', 'A', 30),
	(12, 'SupermarcheMT', 'C', 12),
	(12, 'SupermarcheMT', 'B', 12),
	(12, 'SupermarcheMT', 'A', 24),
	(13, 'SupermarcheMT', 'C', 12),
	(13, 'SupermarcheMT', 'B', 12),
	(13, 'SupermarcheMT', 'A', 24),
	(14, 'SupermarcheMT', 'C', 24),
	(14, 'SupermarcheMT', 'B', 24),
	(14, 'SupermarcheMT', 'A', 24),
	(15, 'SupermarcheMT', 'C', 24),
	(15, 'SupermarcheMT', 'B', 24),
	(15, 'SupermarcheMT', 'A', 24);
INSERT INTO public.seuil_disponibilite_mt VALUES
	(1, 'PetitSuper', 24, 5),
	(1, 'MoyenSuper', 48, 7),
	(1, 'Hypermarche', 48, 11),
	(3, 'PetitSuper', 24, 5),
	(3, 'MoyenSuper', 24, 7),
	(3, 'Hypermarche', 48, 11),
	(4, 'PetitSuper', 24, 6),
	(4, 'MoyenSuper', 48, 8),
	(4, 'Hypermarche', 96, 13),
	(5, 'PetitSuper', 48, 6),
	(5, 'MoyenSuper', 96, 8),
	(5, 'Hypermarche', 144, 13),
	(6, 'PetitSuper', 24, 6),
	(6, 'MoyenSuper', 48, 8),
	(6, 'Hypermarche', 96, 13),
	(7, 'PetitSuper', 2, 2),
	(7, 'MoyenSuper', 4, 2),
	(7, 'Hypermarche', 6, 3),
	(8, 'PetitSuper', 6, 3),
	(8, 'MoyenSuper', 6, 3),
	(8, 'Hypermarche', 12, 5),
	(9, 'PetitSuper', 12, 5),
	(9, 'MoyenSuper', 12, 4),
	(9, 'Hypermarche', 24, 7),
	(10, 'PetitSuper', 6, 3),
	(10, 'MoyenSuper', 12, 2),
	(10, 'Hypermarche', 30, 5),
	(11, 'PetitSuper', 6, 3),
	(11, 'MoyenSuper', 12, 2),
	(11, 'Hypermarche', 30, 5),
	(12, 'PetitSuper', 12, 2),
	(12, 'MoyenSuper', 12, 2),
	(12, 'Hypermarche', 24, 2),
	(13, 'PetitSuper', 12, 2),
	(13, 'MoyenSuper', 12, 2),
	(13, 'Hypermarche', 24, 2),
	(14, 'PetitSuper', 24, 5),
	(14, 'MoyenSuper', 24, 4),
	(14, 'Hypermarche', 24, 6),
	(15, 'PetitSuper', 24, 5),
	(15, 'MoyenSuper', 24, 4),
	(15, 'Hypermarche', 24, 6);
INSERT INTO public.sku_thresholds VALUES
	('evap', 'br_gold', 'BR Gold', 3, 1, '2026-11-15 14:07:54.353878+00'),
	('evap', 'br_160g', 'BR 150g', 3, 2, '2026-11-15 14:07:54.353878+00'),
	('evap', 'brb_160g', 'BRB 150g', 3, 3, '2026-11-15 14:07:54.353878+00'),
	('evap', 'br_400g', 'BR 380g', 3, 4, '2026-11-15 14:07:54.353878+00'),
	('evap', 'brb_400g', 'BRB 380g', 3, 5, '2026-11-15 14:07:54.353878+00'),
	('evap', 'pearl_400g', 'Pearl 380g', 3, 6, '2026-11-15 14:07:54.353878+00'),
	('imp', 'br_400g', 'BR 2', 3, 1, '2026-11-15 14:07:54.353878+00'),
	('imp', 'br_20g', 'BR 15g', 3, 2, '2026-11-15 14:07:54.353878+00'),
	('imp', 'brb_25g', 'BRB 16g', 3, 3, '2026-11-15 14:07:54.353878+00'),
	('imp', 'br_375g', 'BR 360g', 3, 4, '2026-11-15 14:07:54.353878+00'),
	('imp', 'br_900g', 'BR 400g Tin', 3, 5, '2026-11-15 14:07:54.353878+00'),
	('imp', 'brb_400g', 'BRB 360g', 3, 6, '2026-11-15 14:07:54.353878+00'),
	('imp', 'br_2_5kg', 'BR 900g Tin', 3, 7, '2026-11-15 14:07:54.353878+00'),
	('imp', 'brd_15g', 'BRD 15g', 3, 8, '2026-11-15 14:07:54.353878+00'),
	('scm', 'pearl_1kg', 'Pearl 1Kg', 3, 1, '2026-11-15 14:07:54.353878+00'),
	('scm', 'br_1kg', 'BR 1Kg', 3, 2, '2026-11-15 14:07:54.353878+00'),
	('scm', 'brb_1kg', 'BRB 1Kg', 3, 3, '2026-11-15 14:07:54.353878+00'),
	('scm', 'br_397g', 'BR 397g', 3, 4, '2026-11-15 14:07:54.353878+00'),
	('scm', 'brb_397g', 'BRB 397g', 3, 5, '2026-11-15 14:07:54.353878+00'),
	('uht', 'demi_ecreme', 'BR 516ml', 3, 1, '2026-11-15 14:07:54.353878+00'),
	('uht', 'elopack_500ml', 'Elopack 500ml', 3, 2, '2026-11-15 14:07:54.353878+00'),
	('uht', 'brique_1l', 'Brique 1L', 3, 3, '2026-11-15 14:07:54.353878+00'),
	('yaourt', 'br_yogoo_fraise_mini_90ml', 'Yogoo Fraise Mini 90ml', 3, 1, '2026-11-15 14:07:54.353878+00'),
	('yaourt', 'br_yogoo_fraise_maxi_318ml', 'Yogoo Fraise Maxi 318ml', 3, 2, '2026-11-15 14:07:54.353878+00'),
	('yaourt', 'br_yogoo_nature_mini_90ml', 'Yogoo Nature Mini 90ml', 3, 3, '2026-11-15 14:07:54.353878+00'),
	('yaourt', 'br_yogoo_nature_maxi_318ml', 'Yogoo Nature Maxi 318ml', 3, 4, '2026-11-15 14:07:54.353878+00'),
	('cereales', 'brcv', 'Céréales BRCV', 3, 1, '2026-11-15 14:07:54.353878+00'),
	('cereales', 'brcc', 'Céréales BRCC', 3, 2, '2026-11-15 14:07:54.353878+00');
INSERT INTO public.sous_region OVERRIDING SYSTEM VALUE VALUES
	(1, 'SOUTH1', 'SOUTH 1 REGION', 'ABIDJAN 1', 'SOUTHDIV'),
	(2, 'SOUTH2', 'SOUTH 2 REGION', 'ABIDJAN 2', 'SOUTHDIV'),
	(3, 'CNE', 'CENTRE-NORD -EST REGION', 'NORTH 1', 'NORTHDIV'),
	(4, 'WEST', 'WEST REGION', 'NORTH 2', 'NORTHDIV');
INSERT INTO public.standard_assortiment VALUES
	('Boutique', 'A', 15, 10, true),
	('Boutique', 'B', 12, 8, true),
	('Boutique', 'C', 11, 5, true),
	('Minimarket', 'A', 15, 10, true),
	('Minimarket', 'B', 12, 8, true),
	('Minimarket', 'C', 11, 5, true);
INSERT INTO public.standard_visibilite VALUES
	('boutique', 'flagship', 1, true),
	('boutique', 'flagship', 2, true),
	('boutique', 'flagship', 3, true),
	('boutique', 'flagship', 4, true),
	('boutique', 'flagship', 5, true),
	('boutique', 'flagship', 6, true),
	('boutique', 'flagship', 7, true),
	('boutique', 'flagship', 8, true),
	('boutique', 'flagship', 9, true),
	('boutique', 'flagship', 10, true),
	('boutique', 'flagship', 11, true),
	('boutique', 'flagship', 12, true),
	('boutique', 'flagship', 13, true),
	('boutique', 'flagship', 14, true),
	('boutique', 'flagship', 15, true),
	('boutique', 'flagship', 16, true),
	('boutique', 'flagship', 17, true),
	('boutique', 'vip', 1, true),
	('boutique', 'vip', 2, true),
	('boutique', 'vip', 3, true),
	('boutique', 'vip', 4, true),
	('boutique', 'vip', 5, true),
	('boutique', 'vip', 6, false),
	('boutique', 'vip', 7, true),
	('boutique', 'vip', 8, true),
	('boutique', 'vip', 9, true),
	('boutique', 'vip', 10, true),
	('boutique', 'vip', 11, true),
	('boutique', 'vip', 12, true),
	('boutique', 'vip', 13, false),
	('boutique', 'vip', 14, true),
	('boutique', 'vip', 15, true),
	('boutique', 'vip', 16, true),
	('boutique', 'vip', 17, true),
	('boutique', 'core', 1, true),
	('boutique', 'core', 2, true),
	('boutique', 'core', 5, false),
	('boutique', 'core', 6, false),
	('boutique', 'core', 7, true),
	('boutique', 'core', 8, true),
	('boutique', 'core', 9, true),
	('boutique', 'core', 10, true),
	('boutique', 'core', 11, false),
	('boutique', 'core', 12, false),
	('boutique', 'core', 13, false),
	('boutique', 'core', 14, true),
	('boutique', 'core', 15, true),
	('boutique', 'core', 16, false),
	('boutique', 'core', 17, false),
	('boutique', 'basic', 1, true),
	('boutique', 'basic', 4, false),
	('boutique', 'basic', 5, false),
	('boutique', 'basic', 6, false),
	('boutique', 'basic', 7, true),
	('boutique', 'basic', 8, true),
	('boutique', 'basic', 9, true),
	('boutique', 'basic', 11, false),
	('boutique', 'basic', 12, false),
	('boutique', 'basic', 13, false),
	('boutique', 'basic', 14, true),
	('boutique', 'basic', 15, true),
	('boutique', 'basic', 16, false),
	('boutique', 'basic', 17, false),
	('superette', 'flagship', 18, true),
	('superette', 'flagship', 19, true),
	('superette', 'flagship', 20, true),
	('superette', 'flagship', 21, true),
	('superette', 'flagship', 22, true),
	('superette', 'flagship', 23, true),
	('superette', 'flagship', 24, true),
	('superette', 'flagship', 25, true),
	('superette', 'flagship', 26, true),
	('superette', 'flagship', 27, true),
	('superette', 'flagship', 28, true),
	('superette', 'flagship', 29, true),
	('superette', 'flagship', 30, true),
	('superette', 'flagship', 31, true),
	('superette', 'vip', 18, true),
	('superette', 'vip', 19, true),
	('superette', 'vip', 22, true),
	('superette', 'vip', 23, true),
	('superette', 'vip', 24, true),
	('superette', 'vip', 25, true),
	('superette', 'vip', 27, true),
	('superette', 'vip', 28, true),
	('superette', 'vip', 29, true),
	('superette', 'vip', 30, true),
	('superette', 'vip', 31, true),
	('superette', 'core', 18, true),
	('superette', 'core', 19, true),
	('superette', 'core', 20, false),
	('superette', 'core', 21, false),
	('superette', 'core', 22, true),
	('superette', 'core', 23, true),
	('superette', 'core', 24, true),
	('superette', 'core', 25, false),
	('superette', 'core', 26, false),
	('superette', 'core', 27, false),
	('superette', 'core', 28, true),
	('superette', 'core', 29, true),
	('superette', 'core', 30, true),
	('superette', 'basic', 18, true),
	('superette', 'basic', 20, false),
	('superette', 'basic', 21, false),
	('superette', 'basic', 22, true),
	('superette', 'basic', 23, true),
	('superette', 'basic', 25, false),
	('superette', 'basic', 26, false),
	('superette', 'basic', 27, false),
	('superette', 'basic', 28, true),
	('superette', 'basic', 29, true),
	('superette', 'basic', 30, false),
	('superette', 'basic', 31, false),
	('table_top', 'flagship', 32, true),
	('table_top', 'flagship', 33, true),
	('table_top', 'flagship', 34, true),
	('table_top', 'flagship', 35, true),
	('table_top', 'flagship', 36, true),
	('table_top', 'vip', 32, false),
	('table_top', 'vip', 33, true),
	('table_top', 'vip', 34, true),
	('table_top', 'vip', 35, true),
	('table_top', 'vip', 36, true),
	('table_top', 'core', 32, false),
	('table_top', 'core', 33, true),
	('table_top', 'core', 34, true),
	('table_top', 'core', 35, false),
	('table_top', 'core', 36, true),
	('table_top', 'basic', 32, false),
	('table_top', 'basic', 33, false),
	('table_top', 'basic', 34, true),
	('table_top', 'basic', 35, false),
	('table_top', 'basic', 36, false),
	('pushcart', 'flagship', 37, false),
	('pushcart', 'flagship', 38, true),
	('pushcart', 'flagship', 39, true),
	('pushcart', 'flagship', 40, true),
	('pushcart', 'flagship', 41, true),
	('pushcart', 'flagship', 42, true),
	('pushcart', 'vip', 38, true),
	('pushcart', 'vip', 39, true),
	('pushcart', 'vip', 40, true),
	('pushcart', 'vip', 41, false),
	('pushcart', 'vip', 42, true),
	('pushcart', 'core', 38, true),
	('pushcart', 'core', 39, true),
	('pushcart', 'core', 40, false),
	('pushcart', 'core', 41, false),
	('pushcart', 'core', 42, true),
	('pushcart', 'basic', 38, false),
	('pushcart', 'basic', 39, false),
	('pushcart', 'basic', 40, false),
	('pushcart', 'basic', 41, false),
	('pushcart', 'basic', 42, true),
	('porridge', 'flagship', 43, true),
	('porridge', 'flagship', 44, true),
	('porridge', 'flagship', 45, true),
	('porridge', 'flagship', 46, true),
	('porridge', 'flagship', 47, true),
	('porridge', 'flagship', 48, true),
	('porridge', 'flagship', 49, true),
	('porridge', 'vip', 44, true),
	('porridge', 'vip', 45, true),
	('porridge', 'vip', 46, true),
	('porridge', 'vip', 47, false),
	('porridge', 'vip', 48, true),
	('porridge', 'vip', 49, false),
	('porridge', 'core', 43, false),
	('porridge', 'core', 45, true),
	('porridge', 'core', 46, true),
	('porridge', 'core', 47, false),
	('porridge', 'core', 48, true),
	('porridge', 'core', 49, false),
	('porridge', 'basic', 43, false),
	('porridge', 'basic', 44, false),
	('porridge', 'basic', 45, true),
	('porridge', 'basic', 46, false),
	('porridge', 'basic', 47, false),
	('porridge', 'basic', 48, true),
	('porridge', 'basic', 49, false),
	('kiosque_aboki', 'flagship', 50, true),
	('kiosque_aboki', 'flagship', 51, true),
	('kiosque_aboki', 'flagship', 52, true),
	('kiosque_aboki', 'flagship', 53, true),
	('kiosque_aboki', 'flagship', 54, true),
	('kiosque_aboki', 'flagship', 55, true),
	('kiosque_aboki', 'flagship', 56, true),
	('kiosque_aboki', 'flagship', 57, true),
	('kiosque_aboki', 'vip', 51, true),
	('kiosque_aboki', 'vip', 52, true),
	('kiosque_aboki', 'vip', 53, true),
	('kiosque_aboki', 'vip', 54, true),
	('kiosque_aboki', 'vip', 55, true),
	('kiosque_aboki', 'vip', 56, false),
	('kiosque_aboki', 'vip', 57, true),
	('kiosque_aboki', 'core', 51, false),
	('kiosque_aboki', 'core', 52, true),
	('kiosque_aboki', 'core', 53, true),
	('kiosque_aboki', 'core', 54, true),
	('kiosque_aboki', 'core', 55, false);
INSERT INTO public.standard_visibilite VALUES
	('kiosque_aboki', 'core', 56, false),
	('kiosque_aboki', 'core', 57, true),
	('kiosque_aboki', 'basic', 51, false),
	('kiosque_aboki', 'basic', 52, false),
	('kiosque_aboki', 'basic', 53, false),
	('kiosque_aboki', 'basic', 54, false),
	('kiosque_aboki', 'basic', 55, false),
	('kiosque_aboki', 'basic', 56, false),
	('kiosque_aboki', 'basic', 57, false),
	('mt', 'flagship', 58, true),
	('mt', 'vip', 58, true),
	('mt', 'core', 58, true),
	('mt', 'basic', 58, true),
	('mt', 'flagship', 59, true),
	('mt', 'vip', 59, true),
	('mt', 'core', 59, true),
	('mt', 'basic', 59, true),
	('mt', 'flagship', 60, true),
	('mt', 'vip', 60, true),
	('mt', 'core', 60, true),
	('mt', 'basic', 60, true),
	('mt', 'flagship', 61, true),
	('mt', 'vip', 61, false),
	('mt', 'core', 61, false),
	('mt', 'basic', 61, false),
	('mt', 'flagship', 62, true),
	('mt', 'vip', 62, false),
	('mt', 'core', 62, false),
	('mt', 'basic', 62, false),
	('mt', 'flagship', 63, true),
	('mt', 'vip', 63, false),
	('mt', 'core', 63, false),
	('mt', 'basic', 63, false),
	('mt', 'flagship', 64, true),
	('mt', 'vip', 64, true),
	('mt', 'core', 64, true),
	('mt', 'basic', 64, false),
	('mt', 'flagship', 65, true),
	('mt', 'vip', 65, true),
	('mt', 'core', 65, true),
	('mt', 'basic', 65, true),
	('kiosque_aboki', 'flagship', 66, true),
	('kiosque_aboki', 'vip', 66, true),
	('pushcart', 'basic', 37, true),
	('kiosque_aboki', 'core', 66, false),
	('kiosque_aboki', 'basic', 66, false),
	('boutique', 'basic', 2, false),
	('boutique', 'basic', 3, false),
	('boutique', 'core', 3, false),
	('boutique', 'core', 4, false),
	('boutique', 'basic', 10, false),
	('superette', 'basic', 19, false),
	('superette', 'vip', 20, false),
	('superette', 'vip', 21, false),
	('superette', 'basic', 24, false),
	('superette', 'vip', 26, false),
	('superette', 'core', 31, false),
	('pushcart', 'core', 37, true),
	('pushcart', 'vip', 37, true),
	('porridge', 'vip', 43, true),
	('porridge', 'core', 44, true),
	('kiosque_aboki', 'basic', 50, true),
	('kiosque_aboki', 'core', 50, true),
	('kiosque_aboki', 'vip', 50, true);
INSERT INTO public.territoire OVERRIDING SYSTEM VALUE VALUES
	(1, 'BIN', 'Bingerville', 'SOUTH1'),
	(2, 'COC 1', 'Cocody 1', 'SOUTH1'),
	(3, 'COC 2', 'Cocody 2', 'SOUTH1'),
	(4, 'TRE', 'Treichville', 'SOUTH1'),
	(5, 'MAR', 'Marcory', 'SOUTH1'),
	(6, 'KOU', 'koumassi', 'SOUTH1'),
	(7, 'PRB', 'Port bouet', 'SOUTH1'),
	(8, 'BAS', 'Bassam', 'SOUTH1'),
	(9, 'ABO', 'Aboisso', 'SOUTH1'),
	(10, 'PLA', 'Plateau', 'SOUTH1'),
	(11, 'YOP 1', 'Yopougon 1', 'SOUTH2'),
	(12, 'YOP 2', 'Yopougon 2', 'SOUTH2'),
	(13, 'YOP 3', 'Yopougon 3', 'SOUTH2'),
	(14, 'YOP 4', 'Yopougon 4', 'SOUTH2'),
	(15, 'DAB', 'Dabou', 'SOUTH2'),
	(16, 'ABO 1', 'Abobo 1', 'SOUTH2'),
	(17, 'ABO 2', 'Abobo 2', 'SOUTH2'),
	(18, 'ANY', 'Anyama', 'SOUTH2'),
	(19, 'ADJ', 'Adjame', 'SOUTH2'),
	(20, 'ADZ', 'Adzope', 'SOUTH2'),
	(21, 'AGB', 'Agboville', 'SOUTH2'),
	(22, 'ABEN', 'Abengourou', 'CNE'),
	(23, 'YAM', 'Yamoussoukro', 'CNE'),
	(24, 'DIM', 'Dimbokro', 'CNE'),
	(25, 'BKE 1', 'Bouake 1', 'CNE'),
	(26, 'BKE 2', 'Bouake 2', 'CNE'),
	(27, 'KAT', 'Katiola', 'CNE'),
	(28, 'KOR', 'Korhogo', 'CNE'),
	(29, 'FER', 'Ferke', 'CNE'),
	(30, 'BON', 'Bondoukou', 'CNE'),
	(31, 'DAL', 'Daloa', 'WEST'),
	(32, 'MNK', 'Mankono', 'WEST'),
	(33, 'MAN', 'Man', 'WEST'),
	(34, 'SOU', 'Soubre', 'WEST'),
	(35, 'SPD', 'San Pedro', 'WEST'),
	(36, 'GAG 2', 'Gagnoa 2', 'WEST'),
	(37, 'GAG 1', 'Gagnoa 1', 'WEST'),
	(38, 'DIV', 'Divo', 'WEST'),
	(39, 'GUI 1', 'Guiglo 1', 'WEST'),
	(40, 'GUI 2', 'Guiglo 2', 'WEST'),
	(41, 'ODI', 'Odienne', 'WEST'),
	(42, 'Boun', 'Bouna', 'CNE');
INSERT INTO public.territoire_alias VALUES
	('MARCORY TREICHVILLE', 'MAR', '2026-11-15 14:07:57.096148+00'),
	('PORT-BOUET', 'PRB', '2026-11-15 14:07:57.096148+00'),
	('ATTECOUBE', 'PLA', '2026-11-15 14:07:57.096148+00'),
	('ATTECOUBE-PLATEAU', 'PLA', '2026-11-15 14:07:57.096148+00'),
	('YOPOUGON', 'YOP 1', '2026-11-15 14:07:57.096148+00');
INSERT INTO public.territoire_distributeur VALUES
	(42, 1),
	(33, 4),
	(41, 5),
	(31, 6),
	(19, 7),
	(10, 7),
	(1, 11),
	(29, 12),
	(28, 12),
	(39, 13),
	(35, 14),
	(16, 15),
	(27, 16),
	(26, 17),
	(32, 19),
	(15, 21),
	(14, 21),
	(13, 21),
	(3, 24),
	(2, 24),
	(38, 27),
	(22, 28),
	(7, 29),
	(6, 31),
	(5, 31),
	(4, 31),
	(36, 33),
	(34, 33),
	(25, 35),
	(12, 36),
	(11, 36),
	(40, 37),
	(37, 38),
	(30, 40),
	(24, 41),
	(23, 41),
	(18, 42),
	(17, 42),
	(9, 42),
	(8, 42),
	(20, 43),
	(21, 44),
	(2, 23),
	(7, 30),
	(10, 45),
	(19, 45);
INSERT INTO public.type_action_commerciale VALUES
	('activation_ssr', 'Activation SSR', 10, true),
	('activation_ssm', 'Activation SSM', 20, true),
	('referencement_produit', 'Référencement produit', 30, true);
INSERT INTO public.type_pdv OVERRIDING SYSTEM VALUE VALUES
	(10, 6, 'Hypermarket', 'Hypermarché'),
	(28, 11, 'Supermarket A', 'Supermarché A'),
	(36, 15, 'Supermarket B', 'Supermarché B'),
	(35, 15, 'Supermarket C', 'Supermarché C'),
	(24, 9, 'Superettes A', 'Supérette A'),
	(23, 9, 'Superettes B', 'Supérette B'),
	(22, 9, 'Superettes C', 'Supérette C'),
	(32, 13, 'Boutique A', 'Boutique A'),
	(31, 13, 'Boutique B', 'Boutique B'),
	(30, 13, 'Boutique C', 'Boutique C'),
	(5, 3, 'Petrol Station', 'Station-service'),
	(27, 10, 'Pharmacy A', 'Pharmacie A'),
	(26, 10, 'Pharmacy B', 'Pharmacie B'),
	(25, 10, 'Pharmacy C', 'Pharmacie C'),
	(3, 1, 'Bakery A', 'Boulangerie A'),
	(2, 1, 'Bakery B', 'Boulangerie B'),
	(1, 1, 'Bakery C', 'Boulangerie C'),
	(39, 16, 'General Grocery stall', 'Étal d''épicerie générale'),
	(38, 16, 'Open Market Table Top', 'Table top de marché ouvert'),
	(37, 16, 'Tmamies (Oil spice & condiments)', 'Tmamies (huile, épices & condiments)'),
	(34, 14, 'Wholesalers', 'Grossistes'),
	(33, 14, 'Semi-Wholesalers', 'Demi-grossistes'),
	(41, 17, 'Cash & Carry A', 'Cash & Carry A'),
	(40, 17, 'Cash & Carry B', 'Cash & Carry B'),
	(4, 2, 'E-retailers', 'E-commerçants'),
	(29, 12, 'Home delivery', 'Livraison à domicile'),
	(9, 5, 'Chain Hotel', 'Hôtel de chaîne'),
	(8, 5, 'Independent Hotel', 'Hôtel indépendant'),
	(7, 4, 'International Restaurant', 'Restaurant international'),
	(6, 4, 'Local Restaurant', 'Restaurant local'),
	(19, 7, 'Aboki A', 'Aboki A'),
	(18, 7, 'Aboki B', 'Aboki B'),
	(17, 7, 'Kiosk A', 'Kiosque A'),
	(16, 7, 'Kiosk B', 'Kiosque B'),
	(15, 7, 'Pushcard A', 'Pushcart A (chariot ambulant)'),
	(14, 7, 'Pushcard B', 'Pushcart B (chariot ambulant)'),
	(13, 7, 'Horeca coffee', 'Café HORECA'),
	(12, 7, 'Porridge', 'Bouillie (porridge)'),
	(11, 7, 'Table Top', 'Table top'),
	(21, 8, 'Vending machine', 'Distributeur automatique'),
	(20, 8, 'Institutes/company sales', 'Ventes institutions / entreprises');
INSERT INTO public.version_app VALUES
	('android', 11, '1.0.9', NULL, 'Une nouvelle version de l''application est disponible. Installez-la pour continuer.', '2026-11-15 14:07:57.867759+00');
INSERT INTO public.visibility_standards VALUES
	('BOUTIQUE', 'FLAGSHIP', 'exterieure', 'poster', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'FLAGSHIP', 'exterieure', 'guirlande', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'FLAGSHIP', 'exterieure', 'sign_board', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'FLAGSHIP', 'exterieure', 'panneau_privilege', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'FLAGSHIP', 'exterieure', 'full_branding', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'FLAGSHIP', 'interieure', 'reglettes', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'FLAGSHIP', 'interieure', 'maison_bonnet_rouge', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'FLAGSHIP', 'interieure', 'hanger', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'FLAGSHIP', 'interieure', 'presentoirs', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'FLAGSHIP', 'interieure', 'tete_gondole', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'FLAGSHIP', 'interieure', 'merchandising', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'VIP', 'exterieure', 'poster', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'VIP', 'exterieure', 'guirlande', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'VIP', 'exterieure', 'sign_board', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'VIP', 'exterieure', 'panneau_privilege', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'VIP', 'interieure', 'reglettes', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'VIP', 'interieure', 'maison_bonnet_rouge', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'VIP', 'interieure', 'hanger', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'VIP', 'interieure', 'presentoirs', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'VIP', 'interieure', 'tete_gondole', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'VIP', 'interieure', 'merchandising', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'CORE', 'exterieure', 'poster', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'CORE', 'exterieure', 'guirlande', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'CORE', 'exterieure', 'sign_board', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'CORE', 'interieure', 'reglettes', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'CORE', 'interieure', 'maison_bonnet_rouge', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'CORE', 'interieure', 'hanger', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'CORE', 'interieure', 'merchandising', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'BASIC', 'exterieure', 'poster', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'BASIC', 'exterieure', 'guirlande', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'BASIC', 'interieure', 'reglettes', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'BASIC', 'interieure', 'maison_bonnet_rouge', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'BASIC', 'interieure', 'hanger', true, '2026-11-15 14:07:54.602174+00'),
	('BOUTIQUE', 'BASIC', 'interieure', 'merchandising', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'FLAGSHIP', 'exterieure', 'poster', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'FLAGSHIP', 'exterieure', 'sign_board', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'FLAGSHIP', 'exterieure', 'panneau_privilege', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'FLAGSHIP', 'interieure', 'reglettes', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'FLAGSHIP', 'interieure', 'maison_bonnet_rouge', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'FLAGSHIP', 'exterieure', 'guirlande', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'FLAGSHIP', 'interieure', 'presentoirs', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'FLAGSHIP', 'interieure', 'tete_gondole', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'FLAGSHIP', 'interieure', 'merchandising', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'VIP', 'exterieure', 'poster', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'VIP', 'exterieure', 'sign_board', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'VIP', 'exterieure', 'panneau_privilege', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'VIP', 'interieure', 'reglettes', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'VIP', 'interieure', 'maison_bonnet_rouge', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'VIP', 'exterieure', 'guirlande', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'VIP', 'interieure', 'presentoirs', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'VIP', 'interieure', 'tete_gondole', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'VIP', 'interieure', 'merchandising', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'CORE', 'exterieure', 'poster', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'CORE', 'interieure', 'reglettes', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'CORE', 'interieure', 'maison_bonnet_rouge', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'CORE', 'exterieure', 'guirlande', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'CORE', 'interieure', 'merchandising', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'BASIC', 'exterieure', 'poster', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'BASIC', 'interieure', 'reglettes', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'BASIC', 'interieure', 'maison_bonnet_rouge', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'BASIC', 'exterieure', 'guirlande', true, '2026-11-15 14:07:54.602174+00'),
	('MINI MARKET', 'BASIC', 'interieure', 'merchandising', true, '2026-11-15 14:07:54.602174+00'),
	('KIOSQUE', 'FLAGSHIP', 'exterieure', 'poster', true, '2026-11-15 14:07:54.602174+00'),
	('KIOSQUE', 'FLAGSHIP', 'interieure', 'maison_bonnet_rouge', true, '2026-11-15 14:07:54.602174+00'),
	('KIOSQUE', 'FLAGSHIP', 'exterieure', 'full_branding', true, '2026-11-15 14:07:54.602174+00'),
	('KIOSQUE', 'VIP', 'interieure', 'maison_bonnet_rouge', true, '2026-11-15 14:07:54.602174+00'),
	('KIOSQUE', 'CORE', 'interieure', 'maison_bonnet_rouge', true, '2026-11-15 14:07:54.602174+00');
INSERT INTO public.visite_perfect_store VALUES
	('FT-VIS-001', 'taux_vente', 1.00000000000000000000, 1.00000000000000000000, 10.00, 1, 0.00000000000000000000, NULL, 0.7000000000000000000000, '{"imp": {"eval": 5, "avail": 5}, "scm": {"eval": 2, "avail": 2}, "evap": {"eval": 6, "avail": 6}}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-002', 'taux_vente', NULL, NULL, 0.00, NULL, NULL, NULL, NULL, '{}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-003', 'taux_vente', NULL, NULL, 0.00, NULL, NULL, NULL, NULL, '{}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-004', 'taux_vente', 1.00000000000000000000, 1.00000000000000000000, 10.00, 1, 0.00000000000000000000, NULL, 0.7000000000000000000000, '{"imp": {"eval": 5, "avail": 5}, "scm": {"eval": 1, "avail": 1}, "evap": {"eval": 6, "avail": 6}}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-005', 'taux_vente', 1.00000000000000000000, 1.00000000000000000000, 10.00, 1, 0.00000000000000000000, NULL, 0.7000000000000000000000, '{"imp": {"eval": 5, "avail": 5}, "scm": {"eval": 1, "avail": 1}, "evap": {"eval": 6, "avail": 6}}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-006', 'taux_vente', 1.00000000000000000000, 1.00000000000000000000, 10.00, 1, 0.00000000000000000000, NULL, 0.7000000000000000000000, '{"imp": {"eval": 5, "avail": 5}, "scm": {"eval": 1, "avail": 1}, "evap": {"eval": 6, "avail": 6}}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-007', 'taux_vente', 1.00000000000000000000, 1.00000000000000000000, 10.00, 1, 0.00000000000000000000, NULL, 0.7000000000000000000000, '{"imp": {"eval": 4, "avail": 4}, "scm": {"eval": 1, "avail": 1}, "evap": {"eval": 6, "avail": 6}}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-008', 'taux_vente', 1.00000000000000000000, 1.00000000000000000000, 10.00, 1, 0.00000000000000000000, NULL, 0.7000000000000000000000, '{"imp": {"eval": 4, "avail": 4}, "scm": {"eval": 1, "avail": 1}, "evap": {"eval": 6, "avail": 6}}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-009', 'taux_vente', 1.00000000000000000000, 1.00000000000000000000, 10.00, 1, 0.00000000000000000000, NULL, 0.7000000000000000000000, '{"imp": {"eval": 4, "avail": 4}, "scm": {"eval": 1, "avail": 1}, "evap": {"eval": 6, "avail": 6}}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-010', 'taux_vente', 1.00000000000000000000, 1.00000000000000000000, 10.00, 1, 0.00000000000000000000, NULL, 0.7000000000000000000000, '{"imp": {"eval": 4, "avail": 4}, "scm": {"eval": 1, "avail": 1}, "evap": {"eval": 6, "avail": 6}}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-011', 'taux_vente', NULL, NULL, 0.00, NULL, NULL, NULL, NULL, '{}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-012', 'taux_vente', NULL, NULL, 0.00, NULL, NULL, NULL, NULL, '{}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-013', 'taux_vente', 0.00000000000000000000, 0.00000000000000000000, 0.00, 0.00000000000000000000, 0.00000000000000000000, NULL, 0.0000000000000000000000, '{"imp": {"eval": 4, "avail": 0}, "scm": {"eval": 1, "avail": 0}, "evap": {"eval": 6, "avail": 0}}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-014', 'taux_vente', NULL, NULL, 0.00, NULL, NULL, NULL, NULL, '{}', false, NULL, '2026-11-15 14:08:19.360439+00'),
	('FT-VIS-015', 'taux_vente', 0.00000000000000000000, 0.00000000000000000000, 0.00, 0.00000000000000000000, 0.00000000000000000000, NULL, 0.0000000000000000000000, '{"imp": {"eval": 5, "avail": 0}, "scm": {"eval": 1, "avail": 0}, "evap": {"eval": 6, "avail": 0}}', false, NULL, '2026-11-15 14:08:19.360439+00');
INSERT INTO public.visites VALUES
	('ad319135-46fb-4039-bf7a-fded72b7ca77', 'FT-VIS-001', 'FT-001', 'e3fd8415-d791-4164-80d3-2c3221ad27ca', '2026-11-14 10:07:00+00', 'Daouda Essai', 'merchandiser1@fieldtrack.demo', 5.3698, -3.9591, true, 6, '{"produits": {"imp": {"quantites": {"br_20g": 999, "br_375g": 999, "br_400g": 999, "br_900g": 999, "brd_15g": 999, "br_2_5kg": 999, "brd_350g": 999}}, "scm": {"quantites": {"br_1kg": 999, "pearl_1kg": 999}}, "evap": {"quantites": {"br_160g": 999, "br_400g": 999, "br_gold": 999, "brb_160g": 999, "brb_400g": 999, "pearl_400g": 999}}}, "visibilite": {"standards": {"tg": true, "fleche": true, "hanger": true, "wobler": true, "affiche": true, "hotesses": true, "reglette": true, "standard": true, "guirlande": true, "maison_br": true, "plaque_br": true, "presentoir": true, "sign_board": true, "degustation": true, "full_branding": true, "merchandising": true, "panneau_privilege": true}, "promotion_applicable": true}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('6c3b3abd-05c0-4a91-b20e-0aaf207797d7', 'FT-VIS-002', 'FT-002', 'e3fd8415-d791-4164-80d3-2c3221ad27ca', '2026-11-13 11:14:00+00', 'Daouda Essai', 'merchandiser1@fieldtrack.demo', 5.3582, -3.9713, true, 7, '{"produits": {"imp": {"quantites": {"br_20g": 999, "br_375g": 999, "br_400g": 999, "br_900g": 999, "brd_15g": 999, "br_2_5kg": 999, "brd_350g": 999}}, "scm": {"quantites": {"br_1kg": 999, "pearl_1kg": 999}}, "evap": {"quantites": {"br_160g": 999, "br_400g": 999, "br_gold": 999, "brb_160g": 999, "brb_400g": 999, "pearl_400g": 999}}}, "visibilite": {"standards": {"tg": true, "fleche": true, "wobler": true, "affiche": true, "hotesses": true, "reglette": true, "standard": true, "espace_br": true, "plaque_br": true, "presentoir": true, "sign_board": true, "degustation": true, "merchandising": true, "panneau_privilege": true}, "promotion_applicable": true}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('cc6d9a6f-8349-4196-a980-cbd57fae12bd', 'FT-VIS-003', 'FT-003', 'e3fd8415-d791-4164-80d3-2c3221ad27ca', '2026-11-12 12:21:00+00', 'Daouda Essai', 'merchandiser1@fieldtrack.demo', 5.3453, -4.0019, true, 8, '{"produits": {"imp": {"facings": {"br_20g": 999, "br_375g": 999, "br_400g": 999, "br_900g": 999, "brd_15g": 999, "br_2_5kg": 999, "brd_350g": 999}, "quantites": {"br_20g": 999, "br_375g": 999, "br_400g": 999, "br_900g": 999, "brd_15g": 999, "br_2_5kg": 999, "brd_350g": 999}}, "scm": {"facings": {"br_1kg": 999, "pearl_1kg": 999}, "quantites": {"br_1kg": 999, "pearl_1kg": 999}}, "evap": {"facings": {"br_160g": 999, "br_400g": 999, "br_gold": 999, "brb_160g": 999, "brb_400g": 999, "pearl_400g": 999}, "quantites": {"br_160g": 999, "br_400g": 999, "br_gold": 999, "brb_160g": 999, "brb_400g": 999, "pearl_400g": 999}}}, "visibilite": {"standards": {"tg": true, "bacs": true, "plot": true, "niche": true, "wobler": true, "hotesses": true, "reglette": true, "top_shelf": true}, "promotion_applicable": true}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('4c4eb96a-56da-477b-be03-6fbd7a400fb7', 'FT-VIS-004', 'FT-004', '745aabe3-9648-4aa1-9feb-7d60f93a032a', '2026-11-13 13:28:00+00', 'Fabrice Essai', 'merchandiser3@fieldtrack.demo', 5.3012, -3.9922, true, 9, '{"produits": {"imp": {"quantites": {"br_20g": 999, "br_375g": 999, "br_400g": 999, "br_900g": 999, "brd_15g": 999, "br_2_5kg": 999, "brd_350g": 999}}, "scm": {"quantites": {"br_1kg": 999, "pearl_1kg": 999}}, "evap": {"quantites": {"br_160g": 999, "br_400g": 999, "br_gold": 999, "brb_160g": 999, "brb_400g": 999, "pearl_400g": 999}}}, "visibilite": {"standards": {"tg": true, "fleche": true, "hanger": true, "wobler": true, "affiche": true, "hotesses": true, "reglette": true, "standard": true, "guirlande": true, "maison_br": true, "plaque_br": false, "presentoir": true, "sign_board": true, "degustation": true, "full_branding": false, "merchandising": true, "panneau_privilege": true}, "promotion_applicable": true}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('6b43542c-63bb-4be6-8c83-63a1d4a6fbfa', 'FT-VIS-005', 'FT-005', '745aabe3-9648-4aa1-9feb-7d60f93a032a', '2026-11-11 14:35:00+00', 'Fabrice Essai', 'merchandiser3@fieldtrack.demo', 5.3063, -3.9854, true, 5, '{"produits": {"imp": {"quantites": {"br_20g": 999, "br_375g": 999, "br_400g": 999, "br_900g": 999, "brd_15g": 999, "br_2_5kg": 999, "brd_350g": 999}}, "scm": {"quantites": {"br_1kg": 999, "pearl_1kg": 999}}, "evap": {"quantites": {"br_160g": 999, "br_400g": 999, "br_gold": 999, "brb_160g": 999, "brb_400g": 999, "pearl_400g": 999}}}, "visibilite": {"standards": {"tg": true, "fleche": true, "hanger": true, "wobler": true, "affiche": true, "hotesses": true, "reglette": true, "standard": true, "guirlande": true, "maison_br": true, "plaque_br": false, "presentoir": true, "sign_board": true, "degustation": true, "full_branding": false, "merchandising": true, "panneau_privilege": true}, "promotion_applicable": true}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('49543ca4-5145-4a93-a035-09a06ee75755', 'FT-VIS-006', 'FT-006', '745aabe3-9648-4aa1-9feb-7d60f93a032a', '2026-11-10 15:42:00+00', 'Fabrice Essai', 'merchandiser3@fieldtrack.demo', 5.2988, -3.9803, true, 6, '{"produits": {"imp": {"quantites": {"br_20g": 999, "br_375g": 999, "br_400g": 999, "br_900g": 999, "brd_15g": 999, "br_2_5kg": 999, "brd_350g": 999}}, "scm": {"quantites": {"br_1kg": 999, "pearl_1kg": 999}}, "evap": {"quantites": {"br_160g": 999, "br_400g": 999, "br_gold": 999, "brb_160g": 999, "brb_400g": 999, "pearl_400g": 999}}}, "visibilite": {"standards": {"tg": true, "fleche": true, "hanger": true, "wobler": true, "affiche": true, "hotesses": true, "reglette": true, "standard": true, "guirlande": true, "maison_br": true, "plaque_br": false, "presentoir": true, "sign_board": true, "degustation": true, "full_branding": false, "merchandising": true, "panneau_privilege": true}, "promotion_applicable": true}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('983d6529-81be-4495-8591-89dd23cea722', 'FT-VIS-007', 'FT-007', 'ba78d180-c6bd-44f0-bcb0-b0a76d818a47', '2026-11-12 09:49:00+00', 'Estelle Essai', 'merchandiser2@fieldtrack.demo', 5.3232, -4.0204, true, 7, '{"produits": {"imp": {"quantites": {"br_20g": 999, "br_375g": 999, "br_400g": 999, "br_900g": 999, "brd_15g": 999, "br_2_5kg": 999, "brd_350g": 999}}, "scm": {"quantites": {"br_1kg": 999, "pearl_1kg": 999}}, "evap": {"quantites": {"br_160g": 999, "br_400g": 999, "br_gold": 999, "brb_160g": 999, "brb_400g": 999, "pearl_400g": 999}}}, "visibilite": {"standards": {"tg": false, "fleche": true, "hanger": true, "wobler": true, "affiche": true, "hotesses": false, "reglette": true, "standard": true, "guirlande": true, "maison_br": true, "plaque_br": false, "presentoir": false, "sign_board": true, "degustation": false, "full_branding": false, "merchandising": true, "panneau_privilege": false}, "promotion_applicable": false}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('90ba0356-6d88-4267-9b65-acacd0e69a46', 'FT-VIS-008', 'FT-008', 'ba78d180-c6bd-44f0-bcb0-b0a76d818a47', '2026-11-09 10:56:00+00', 'Estelle Essai', 'merchandiser2@fieldtrack.demo', 5.3275, -4.0172, true, 8, '{"produits": {"imp": {"quantites": {"br_20g": 999, "br_375g": 999, "br_400g": 999, "br_900g": 999, "brd_15g": 999, "br_2_5kg": 999, "brd_350g": 999}}, "scm": {"quantites": {"br_1kg": 999, "pearl_1kg": 999}}, "evap": {"quantites": {"br_160g": 999, "br_400g": 999, "br_gold": 999, "brb_160g": 999, "brb_400g": 999, "pearl_400g": 999}}}, "visibilite": {"standards": {"tg": false, "fleche": true, "hanger": true, "wobler": true, "affiche": true, "hotesses": false, "reglette": true, "standard": true, "guirlande": true, "maison_br": true, "plaque_br": false, "presentoir": false, "sign_board": true, "degustation": false, "full_branding": false, "merchandising": true, "panneau_privilege": false}, "promotion_applicable": false}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('5276908e-7942-4bca-a495-2f1d16380040', 'FT-VIS-009', 'FT-009', 'ba78d180-c6bd-44f0-bcb0-b0a76d818a47', '2026-11-08 11:03:00+00', 'Estelle Essai', 'merchandiser2@fieldtrack.demo', 5.3303, -4.0237, true, 9, '{"produits": {"imp": {"quantites": {"br_20g": 999, "br_375g": 999, "br_400g": 999, "br_900g": 999, "brd_15g": 999, "br_2_5kg": 999, "brd_350g": 999}}, "scm": {"quantites": {"br_1kg": 999, "pearl_1kg": 999}}, "evap": {"quantites": {"br_160g": 999, "br_400g": 999, "br_gold": 999, "brb_160g": 999, "brb_400g": 999, "pearl_400g": 999}}}, "visibilite": {"standards": {"tg": false, "fleche": true, "hanger": true, "wobler": true, "affiche": true, "hotesses": false, "reglette": true, "standard": true, "guirlande": true, "maison_br": true, "plaque_br": false, "presentoir": false, "sign_board": true, "degustation": false, "full_branding": false, "merchandising": true, "panneau_privilege": false}, "promotion_applicable": false}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('9d75e67a-6248-4c9c-9bdd-0b6d3457247a', 'FT-VIS-010', 'FT-010', 'ecfef4e0-2429-4653-91aa-5a04eb14f1e0', '2026-11-11 12:10:00+00', 'Grâce Essai', 'merchandiser4@fieldtrack.demo', 5.2953, -4.0022, true, 5, '{"produits": {"imp": {"quantites": {"br_20g": 999, "br_375g": 999, "br_400g": 999, "br_900g": 999, "brd_15g": 999, "br_2_5kg": 999, "brd_350g": 999}}, "scm": {"quantites": {"br_1kg": 999, "pearl_1kg": 999}}, "evap": {"quantites": {"br_160g": 999, "br_400g": 999, "br_gold": 999, "brb_160g": 999, "brb_400g": 999, "pearl_400g": 999}}}, "visibilite": {"standards": {"tg": false, "fleche": true, "hanger": true, "wobler": true, "affiche": true, "hotesses": false, "reglette": true, "standard": true, "guirlande": true, "maison_br": true, "plaque_br": false, "presentoir": false, "sign_board": true, "degustation": false, "full_branding": false, "merchandising": true, "panneau_privilege": false}, "promotion_applicable": false}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('42db9b2b-f25d-40d5-a25f-50ba1907d9a0', 'FT-VIS-011', 'FT-011', 'ecfef4e0-2429-4653-91aa-5a04eb14f1e0', '2026-11-07 13:17:00+00', 'Grâce Essai', 'merchandiser4@fieldtrack.demo', 5.3004, -4.0083, true, 6, '{"produits": {"imp": {"quantites": {}}, "scm": {"quantites": {"pearl_1kg": 999}}, "evap": {"quantites": {"pearl_400g": 999}}}, "visibilite": {"standards": {"verre": false, "carafe": false, "affiche": false, "thermos": false, "chasuble": false, "maison_br": false, "promotion": false, "full_branding": false}, "promotion_applicable": false}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('d85c0bbf-ee9f-4e61-b00b-1490e4a325bb', 'FT-VIS-012', 'FT-012', 'ecfef4e0-2429-4653-91aa-5a04eb14f1e0', '2026-11-06 14:24:00+00', 'Grâce Essai', 'merchandiser4@fieldtrack.demo', 5.3052, -4.0044, true, 7, '{"produits": {"imp": {"quantites": {}}, "scm": {"quantites": {"pearl_1kg": 999}}, "evap": {"quantites": {"pearl_400g": 999}}}, "visibilite": {"standards": {"verre": false, "carafe": false, "affiche": false, "thermos": false, "chasuble": false, "maison_br": false, "promotion": false, "full_branding": false}, "promotion_applicable": false}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('ab7bb16e-e0a8-48ef-b1aa-bc64cd775db9', 'FT-VIS-013', 'FT-013', '5f7115ff-1868-49d3-917a-25797198941a', '2026-11-09 15:31:00+00', 'Hervé Essai', 'merchandiser5@fieldtrack.demo', 5.3413, -4.0704, true, 8, '{"produits": {"imp": {"quantites": {}}, "scm": {"quantites": {}}, "evap": {"quantites": {}}}, "visibilite": {"standards": {"tg": false, "fleche": false, "hanger": false, "wobler": false, "affiche": false, "hotesses": false, "reglette": false, "standard": false, "guirlande": false, "maison_br": false, "plaque_br": false, "presentoir": false, "sign_board": false, "degustation": false, "full_branding": false, "merchandising": false, "panneau_privilege": false}, "promotion_applicable": false}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('14e9768f-9d69-47bc-a528-a99104ad966d', 'FT-VIS-014', 'FT-014', '5f7115ff-1868-49d3-917a-25797198941a', '2026-11-05 09:38:00+00', 'Hervé Essai', 'merchandiser5@fieldtrack.demo', 5.3362, -4.0782, true, 9, '{"produits": {"imp": {"quantites": {}}, "scm": {"quantites": {}}, "evap": {"quantites": {}}}, "visibilite": {"standards": {"tg": false, "fleche": false, "wobler": false, "affiche": false, "hotesses": false, "reglette": false, "standard": false, "espace_br": false, "plaque_br": false, "presentoir": false, "sign_board": false, "degustation": false, "merchandising": false, "panneau_privilege": false}, "promotion_applicable": false}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00'),
	('37df3a9c-460b-4d06-8e29-20bd7caa4195', 'FT-VIS-015', 'FT-015', '5f7115ff-1868-49d3-917a-25797198941a', '2026-11-03 10:45:00+00', 'Hervé Essai', 'merchandiser5@fieldtrack.demo', 5.3305, -4.0853, true, 5, '{"produits": {"imp": {"quantites": {"br_20g": 2}}, "scm": {"quantites": {}}, "evap": {"quantites": {"br_160g": 2, "br_400g": 2}}}, "visibilite": {"standards": {"tg": false, "fleche": false, "hanger": false, "wobler": false, "affiche": true, "hotesses": false, "reglette": true, "standard": false, "guirlande": false, "maison_br": false, "plaque_br": false, "presentoir": false, "sign_board": false, "degustation": false, "full_branding": false, "merchandising": false, "panneau_privilege": false}, "promotion_applicable": false}}', '{}', 'synced', '2026-11-15 14:08:19.360439+00', '2026-11-15 14:08:19.360439+00', 'soumis', '2026-11-15 14:08:19.360439+00');
INSERT INTO public.zone OVERRIDING SYSTEM VALUE VALUES
	(1, 'NVEG', 'NOUVEAU GOUDRON/ FEH KESSE/ CITE SIR/ AKANDJE/ LAURIER 15/SANTE', 'BIN'),
	(2, 'BLAN', 'BLANCHON/PALMERAIE BINGERVILLE/ADJAME BINGERVILLE/ BREGBO/AKOUAI SANTE/AMAN/', 'BIN'),
	(3, 'BCIE', 'BASE CIE/ KOROCOBOUGOU/GBAGBA/BERLIN/SAVANE/MACHOU/SICOGI/MACHOUX/MARCHE/', 'BIN'),
	(4, 'ABAT', 'ABATTA/ABATTA VILLAGE/JULES VERNE/CITE DU PORT', 'BIN'),
	(5, 'BING', 'TOUT BINGERVILLE', 'BIN'),
	(6, 'LCET', 'LYCEE TECHNIQUE/VALLON/COLOMBIE', 'COC 1'),
	(7, 'MAHO', 'MAHOU COLOMBIE', 'COC 1'),
	(8, 'PERL', 'PERLE/MAHOU/ANGRE', 'COC 1'),
	(9, 'PALM', 'PALMERAIE/ATTOBAN /BONOUMIN', 'COC 1'),
	(10, 'PALM2', 'PALMERAIE2 COCOVICO', 'COC 1'),
	(11, 'ANGR', 'ANGRE 2PLATEAUX 7 TRANCHE', 'COC 1'),
	(12, 'DJOR', 'BESSIKOI/DJOROBITE', 'COC 1'),
	(13, 'DNGA', 'DANGA/COCODY CENTRE/BLAUKOSS', 'COC 2'),
	(14, 'BLKH', 'BLAUKOSS COCODY CENTRE', 'COC 2'),
	(15, 'RVER2', 'RIVIERA 2/ RIVIERA 3/ GOLF', 'COC 2'),
	(16, 'ANON', 'ANONO', 'COC 2'),
	(17, 'FAYB', 'FAYA BON PRIX/ABATTA', 'COC 2'),
	(18, 'CIAD', 'CIAD/MPOUTO/SYNACACI/FAYA (COTE ECHANGEUR)', 'COC 2'),
	(19, 'ARAS', 'ARAS/ BELLEVILLE/ BIAFRA/ QUARTIER APOLLO / ZONE 3', 'TRE'),
	(20, 'BIAF', 'ARAS/ BELLEVILLE/ BIAFRA/ QUARTIER APOLLO / ZONE 3', 'TRE'),
	(21, 'RSD', 'RÉSIDENTIEL / CHAMPROUX / GROUPEMENT/ HIBISCUS / MASSARANA', 'MAR'),
	(22, 'SICOG', 'SICOGI / REMBLAIS / ANOUMANBO/ SANS FIL / ZONE 4', 'MAR'),
	(23, 'HIBI', 'RÉSIDENTIEL / CHAMPROUX / GRPE/ HIBISCUS / MASSARANA / SICOGI / REMBLAIS /ANOUMANBO/ SANS FIL/ ZONE4', 'MAR'),
	(24, 'RBLA', 'REMBLAIS/MARAIS/ DIVO/ KOUMASSI 32/ TERM 05', 'KOU'),
	(25, 'CTE147', 'CITÉ 147/ PRODOMO/SOPIM/ CAMPEMENT/SOWETO/SICOGI', 'KOU'),
	(26, 'AHOU', 'AHOUSSABOUGOU/ 3 AMPOULES/ MARCHÉ DJE KONAN/SOLEIL/GELTI', 'KOU'),
	(27, 'KMSS32', 'REMBLAIS/MARAIS/ DIVO/ KOUMASSI 32/ TERM 05 /3 AMPOULES / AHOUSSABOUGOU', 'KOU'),
	(28, 'PRDM', 'CITÉ 147/ PRODOMO/SOPIM/ CAMPEMENT/SOWETO/SICOGI/ MARCHÉ DJE KONAN / SOLEIL', 'KOU'),
	(29, 'PRBC', 'PORT BOUET CENTRE/CITÉ POLICIÈRE/PETIT BASSAM/VRIDI', 'PRB'),
	(30, 'AERO', 'AÉROPORT/ ADJAWUI', 'PRB'),
	(31, 'JANF', 'JEAN FOLLY/ ADJOUFOU', 'PRB'),
	(32, 'TRCA', 'TERRE ROUGE/CORRIDOR/ANANI', 'PRB'),
	(33, 'PRBO', 'PORT BOUET', 'PRB'),
	(34, 'MOKE', 'MOCKEYVILLE/UNIVERSITÉ AMÉRICAINE/ EDOUKOU MIEZAN/QUARTIER ARTISANAL/MODESTE/ANANI/MOOSOU 1', 'BAS'),
	(35, 'VETO', 'VETOCO/MOOSOU2/IMPERIAL/DOS/QUARTIER FRANCE/DIOULABOUGOU/AZURETI', 'BAS'),
	(36, 'ANAN', 'ANANI/DOS/ DIOULABOUGO/PETIT MARCHÉ', 'BAS'),
	(37, '8KLO', '8 KILOS/ YAOU/CENTRE VILLE/BEGNERI/SAMO/ASSINIE', 'BAS'),
	(38, 'YAOU', '8 KILOS/ YAOU/CENTRE VILLE/BEGNERI/SAMO/ASSINIE', 'BAS'),
	(39, 'CTREV', '8 KILOS/ YAOU/CENTRE VILLE/BEGNERI', 'BAS'),
	(40, 'DJELI', 'DJELIBA /TP/ PARCERELLE/KONAN KAN/BOIS BLANC/ AYEBO/ADAOU', 'ABO'),
	(41, 'DIATEK', 'DIATEKRO/SOKORA/CCE/WATTVILLE/BELLEVILLE/SOS/DOSOBAH/CITÉ KOUMI/LYCÉE/ KRINDJABO/KOLAIWA/SANHOUMAN', 'ABO'),
	(42, 'AYME', 'AYAMÉ/EBIKRA/AKRESIE/N’ZIKRO/BABADOUGOU/EBOUÉ/ABY/ADJOUAN/MOYASSUÉ/AKAKRO/  V1/V2/KRINDJABO/KASSIKRO', 'ABO'),
	(43, 'ADKE', 'ADIAKÉ/ABOISSO/AYAMÉ/ KRINDJABO/ NOÉ/ ASSE/SOUMIÉ/N''ZIKRO/ KOFFIKRO/BABADOUGOU/ CARF AHENOUA/ADAOU', 'ABO'),
	(44, 'AGBA', 'AGBAN VILLAGE / CITE FERMONT / ATTECOUBE CENTRE / PLATEAU CENTRE / MARCHE DE FRUIT', 'PLA'),
	(45, 'CTEFER', 'AGBAN VILLAGE / CITE FERMONT / ATTECOUBE CENTRE / PLATEAU CENTRE / MARCHE DE FRUIT', 'PLA'),
	(46, 'ATTC', 'YOPOUGON 1 & 2', 'YOP 1'),
	(47, 'WASS', 'WASSAKARA /  SELMER / SICOGI', 'YOP 1'),
	(48, 'SELM', 'WASSAKARA /  SELMER / SICOGI', 'YOP 1'),
	(49, 'SBLE', 'YOPOUGON SABLE / MILLIONNAIRE / NOUVEAU QUARTIER', 'YOP 1'),
	(50, 'MILLI', 'YOPOUGON SABLE / MILLIONNAIRE / NOUVEAU QUARTIER', 'YOP 1'),
	(51, 'NGON', 'NIANGON NORD / SIDECI', 'YOP 1'),
	(52, 'TOROU', 'TOIT ROUGE / LOKODJRO / ATTECOUBE MOSSIKRO', 'YOP 1'),
	(53, 'LKOD', 'TOIT ROUGE / LOKODJRO / ATTECOUBE MOSSIKRO', 'YOP 1'),
	(54, 'NGOS', 'NIANGON SUD / AZITO', 'YOP 2'),
	(55, 'AZTO', 'NIANGON SUD/ AZITO', 'YOP 2'),
	(56, 'KTE', 'KOUTÉ/ PETIT TOIT ROUGE/ BÉAGO', 'YOP 2'),
	(57, 'BEAG', 'KOUTÉ/ PETIT TOIT ROUGE/ BÉAGO', 'YOP 2'),
	(58, 'KWEI', 'KOWEIT/ SANTÉ/ ABOBO DOUMÉ/ AGBAYATÉ', 'YOP 2'),
	(59, 'YOPS', 'KOWEIT/ YOPOUGON SANTÉ/ ABOBO DOUMÉ/ AGBAYATÉ', 'YOP 2'),
	(60, 'ADKOI', 'ANDOKOI/ UNIWAX/CRF ZONE /PRISON CIVILE/SODEFOR  ET CITÉ ADO', 'YOP 3'),
	(61, 'ZNEIND', 'ZONE INDUSTRIELLE/ MICAO/GESCO FOURRIÈRE/ PK22/SIKENSI/ATTINGUÉ', 'YOP 3'),
	(62, 'MCAO', 'ANDOKOI/ UNIWAX/ ZONE INDUSTRIELLE/ MICAO GESCO FOURRIÈRE/PRISON CIVILE/ SODEFOR/CITÉ ADO......', 'YOP 3'),
	(63, 'GSCO', 'ANDOKOI/UNIWAX/ ZONE INDUSTRIELLE/ MICAO/ GESCO FOURRIÈRE/ PRISON CIVILE/ SODEFOR ET CITÉ ADO....', 'YOP 3'),
	(64, 'SPOREXBANCO2/ ABOULAYE DIALLO/ ANANE', 'SIPOREX/ BANCO2/ ABOULAYE DIALLO/ ANANERAIE/ MAMIE ADJOUA/PORT BOUET 2/CRF CHU/MOSQUÉE KOUDOUS', 'YOP 3'),
	(65, 'PRTBOU', 'PORT BOUET 2/CRF CHU/MOSQUÉE KOUDOUS/ ANANERAIE/ FUSCOM PORT BOUET 2/RD POINT GESCO', 'YOP 3'),
	(66, 'AANERAIEANANERAI', 'ANANERAIE/ GESCO RD POINT/ BATIM/MAMIE ADJOUA', 'YOP 3'),
	(67, 'LBAFRIQUEJATARK', 'LUBAFRIQUE/ JATARK/ LOKOA/CITÉ VERTE/BAGNON/ LIÈVRE ROUGE/KM17/BIMBRESSO/', 'YOP 4'),
	(68, 'CNEO', 'MATY/CANARI /ANTENNE/ SICOGI ATTIÉ/NIANGON À DROITE/ NIANGON CONTINUE/ CITÉ EECI', 'YOP 4'),
	(69, 'KBIM', 'KM17/BIMBRESSO/  ́JATARK/LOKOA CITÉ VERTE/ LIÈVRE ROUGE', 'YOP 4'),
	(70, 'DCCO', 'SICOGI ATTIÉ/ST ANDRÉ CÔTÉ DROIT/ PMI/AIMÉ CESAIRE/BON PRIX/ CRF BOBY & POLICIER CÔTÉ DROIT/BAR ECLA', 'YOP 4'),
	(71, 'TRMINUSNUS', 'TERMINUS 47 SECTEUR DROIT/ SICOGI PMI/ TIKEN DJA/BMW/KIMI', 'YOP 4'),
	(72, 'AADÉMIEMIE', 'ACADÉMIE/ FIN GOUDRON/ PAYS BAS/CAISTAB/CITÉ LAURIER/ CITÉ VERTE', 'YOP 4'),
	(73, 'MROCAN', 'MAROC/ANANERAIE/ PORT BOUET 2/LUBAFRIQUE/ NIANGON À DROITE /TEXACO À DROITE', 'YOP 4'),
	(74, 'SNGONN', 'SONGON/N’DJEM/ CARREFOUR JACQUESVILLE/JACQUESVILLE VILLE/ DABOU/N’ZEKREZESSOU....', 'DAB'),
	(75, 'GANDLA', 'GRAND LAHOU/CRF GRAND LAHOU/CRF FRESCO/FRESCO VILLE ET PÉRIPHÉRIES', 'DAB'),
	(76, 'DBOUVI', 'DABOU VILLE/ SONGON/ CARREFOUR JACQUESVILLE....', 'DAB'),
	(77, 'SNGON', 'SONGON/ CARREFOUR JACQUESVILLE/ JACQUESVILLE/ DABOU/GRAND LAHOU/FRESCO/', 'DAB'),
	(78, 'DKUI', 'DOKUI / ANADOR / COCO SERVICE DERRIÈRE UNIVERSITÉ ABOBO/ADJAMÉ / ALEPE', 'ABO 1'),
	(154, 'ISSIA', 'Issia & Environs (mira, zobia, commerce, Saioua)', 'SOU'),
	(79, 'AOCATIERAVOCATIE', 'AVOCATIER / BC AUTOUTE / NOUVELLE GARE / AGNISSANKOI / BC', 'ABO 1'),
	(80, 'SMANKEKE', 'SAMANKE / KOLETCHA / ABOBO BAOULE / BIABOU', 'ABO 1'),
	(81, 'AEIKOIOI', 'AKEIKOI  / HABITAT  / AGBEKOI /  HOUPHOUT BOIGNY', 'ABO 1'),
	(82, 'LCEEMO', 'LYCEE MODERNE / ETOILE / GENDARMERIE / BON PRIX GENDARMERIE / CHATTONS', 'ABO 1'),
	(83, 'CTEPOL', 'CITE POLICIERE / CAMP COMMANDO / CNPS / AVENUE KAZA / COLATIER', 'ABO 1'),
	(84, 'AOBOGA', 'ABOBO GARE  / MAIRIE', 'ABO 1'),
	(85, 'MSQUEB', 'MOSQUE BLANCHE/ANOKOUA KOUTE/MARAHOUE/AGRIPAC', 'ABO 2'),
	(87, 'SDECIO', 'SODECI/ONUCI/SOTRAPIM/CARREFOUR DIALLO/TAXI BAGAGE', 'ABO 2'),
	(89, 'CACOCC', 'CMA/COCCINELLE/CONCORDE/BOIS SEC/DELICE DE FRANCE / ANCIEN MARCHE/UNICAFE/FEU ENCIENNE GENDARMERIE', 'ABO 2'),
	(90, 'ACIENNE', 'ANCIENNE GENDARMERIE/ BELLE VILLE MORGUE/ GARE /ADZOPE/AGBOVILLE', 'ANY'),
	(91, 'CÄTEAU', 'CHÄTEAU/MARCHE COLA/MARCHE D''ANYAMA/DON ORION/AZAGUIE/BILDA AZAGUIE AWA ATTINGUE', 'ANY'),
	(92, 'AYAMAP', 'ANYAMA/PLAQUE ARABE/ANYAMA RESIDENTIEL/EBIMPE/', 'ANY'),
	(93, 'CÄTEAU', 'CHÄTEAU/MARCHE COLA/MARCHE D''ANYAMA/DON ORION/ MACHE CHAKA KONE', 'ANY'),
	(94, 'AEAUTO', 'AXE AUTOROUTE N''DOTRE/ DANDI/COMPLEXE/MAIRIE', 'ANY'),
	(95, 'ANCGEN', 'ANCIENNE GENDARMERIE/ BELLE VILLE MORGUE/ GARE', 'ANY'),
	(96, 'BNDJIN1', 'BANDJI/N''DOTRE EXTENSION/CELESTE/NOUVELLE CASSE / ARC EN CIEL/DANDY/KOBAKRO/TERRE ROUGE/AKWABA', 'ANY'),
	(97, 'BNDJIN2', 'BANDJI/N''DOTRE EXTENSION/CELESTE/NOUVELLE CASSE / ARC EN CIEL/DANDY/KOBAKRO/TERRE ROUGE/AKWABA', 'ANY'),
	(98, '20LGTSLGTS', '220LGTS / LIBERTÉ / QUARTIER LATIN / BRACODI / TERRASSE/RENAULT', 'ADJ'),
	(99, 'WILLY', 'WILLIAMSVILLE/MACACI/ PAILLET/VIDANGE/ HMA', 'ADJ'),
	(100, 'SPEURP', 'SAPEUR POMPIER/ SAINT MICHEL/ QUARTIER EBRIÉ/DALLAS', 'ADJ'),
	(101, 'NNGUIA', 'NANGUI ABROGOUA / MARCHE GOURO / BLACK MARKET / MIRADOR / NOUVELLE GARE', 'ADJ'),
	(102, 'BRAMA', 'BRAMACOTÉ / DÉLÉGATION / CITÉ RAN / FORUM', 'ADJ'),
	(103, 'CNTREAD', 'TERRITOIRE ADJAMÉ', 'ADJ'),
	(104, 'AZOPEV', 'ADZOPE VILLE', 'ADZ'),
	(105, 'AKPEVI', 'AKOUPE / YAKASSE ATTOBROU / ANDE / YAKASSE ME', 'ADZ'),
	(106, 'AGBVIL', 'AGBOVILLE VILLE / N''DOUCI / SIKENSI', 'AGB'),
	(107, 'AZGUVIL', 'AZAGUIE / PETIT YAPO / GRAND YAPO / RUBINO / SECHI', 'AGB'),
	(108, 'CFETO', 'CAFETOUTOU/AGNIKRO/ADOUKOFFIKRO/GARE DE NIABLE /AFFALIKRO/ANGOUAKRO/DRAMANKRO/NIABLE/ADAOU/BAOULEKRO', 'ABEN'),
	(109, 'CMMER', 'COMMERCE/RELAIS/HKB/LOBIKRO/CAMP MILITAIRE/PLATEAU', 'ABEN'),
	(110, 'RSDT', 'RESIDENTIEL/120 LGMT/CHICAGO/BAOULEKRO/DIOULAKRO/GAGOU/OUELLE/GRAV D''OR/COMMERCE/KREGBE/SOSSOBOUGOU', 'ABEN'),
	(111, 'PLTEMI', 'ADAOU/ADOUKOFIKRO/BAOULEKRO/CAFETOU/AGNIKRO/CMP MILITAIRE/COMMERCE/DIOULAKRO/HKB/LOBKRO/PLATX/RELAIS', 'ABEN'),
	(112, 'GRELO', 'BONAHOUIN/ARRAH/BONGOUANOU/APRONPRON/ASSIKASSO/AGNIBILEKRO/ANDE/APKAOUSSOU/DAOUKRO/TANKESSE/ANUANSUE', 'ABEN'),
	(113, 'BNON', 'Bonon / Garango / Gobazra / Bouaflé / Zougoussou / Zambakro / Zuenoula', 'YAM'),
	(114, 'Spim', 'Sopim / Makora - Belleville / Kokrenou 1 / Kokrenou 2 / Kokrenou 3 / Kokenou 4', 'YAM'),
	(115, 'ASSAB', 'Assabou 1 - Djahakro - 50 & 227 logements - INPHB / Assabou 2 - 220 logements', 'YAM'),
	(116, 'DLABOU', 'Dioulabougou 1 / Dioulabougou 2 / Dioulabougou 3 / Dioulabougou 4 / Dioulabougou 5/ Dioulabougou 6', 'YAM'),
	(117, 'MROFE', 'Morofé / Morofé extention/ Morofé 2 / Morofé 3 -Habitat 1 / Habitat', 'YAM'),
	(118, 'TMOD', 'Toumodi', 'DIM'),
	(119, 'DMBKRV', 'Dimbokro ville', 'DIM'),
	(120, 'BCAND', 'Toumodi / Dimbokro / M''batto / Bocanda', 'DIM'),
	(121, 'SKOURA', 'Sokoura / Commerce / Centre Ivoire / Houphouet-Ville / Nimbo / Djamourou / Dare_Salam / Tola / Maroc', 'BKE 1'),
	(122, 'KOKO', 'Koko / Audjenekourani / Hypodrome / Beaufort / Zone / Gonvreville / Beaufort/ Habitat Gonvreville', 'BKE 1'),
	(123, 'ONADKH', 'Cmrce/Sokoura/Marche/Boniere/Bokala/Dare salam/Belle ville/Air Frce/Djanbourou/Zone/Sakasou/Tola', 'BKE 1'),
	(124, 'CMRCE', 'Commerce/Nguattakro/Ahougnansou/Houphouet ville/Broukro/Sicogi/Ndakro/Campus/Adje yaokro/Tchelekro', 'BKE 1'),
	(125, 'BKEVILL', 'Bouaké ville', 'BKE 1'),
	(126, 'GRDM', 'Grand marche / Nimbo / Kennedi / Sokoura', 'BKE 2'),
	(127, 'AIRFR', 'Air France 1,2,3 / Corridor sud', 'BKE 2'),
	(128, 'DRSAL', 'Dares salam Djambourou / Abattoir / Laraba / Corridor Nord', 'BKE 2'),
	(129, 'BLLVIL', 'Belle ville 1,2,3 / Campement', 'BKE 2'),
	(130, 'GRDMA', 'Grand marche / Satama Sokora / Brobo / M''bahiakro/ Niakara / Dabakala', 'KAT'),
	(131, 'KTLAVIL', 'Katiola ville', 'KAT'),
	(132, 'REBANQ', 'Commerce/Boulevard Ado/Voie kafoudal/Voie de Mbengue/Tarato/Siempurgo/Boundiali/Gbon/Kouto/Tengréla', 'KOR'),
	(133, 'QATAIRF', 'Quartier 14/Air France/ Sinistré/Sodepra/Cite des medecins/Tiékélézo/Prémafolo/Soba/Kassirimé', 'KOR'),
	(134, 'HSSADG', 'Haoussadougou / Petit Paris / Soba', 'KOR'),
	(135, 'NVEQUA', 'Nouveau Quartier / Sossorobougou / Cocody /Klofohakaha', 'KOR'),
	(136, 'BNDLI', 'Boundiali & Environs', 'FER'),
	(137, 'FRKESS', 'Ferkessedougou & Environs SICAF1 /SICAF2', 'FER'),
	(138, 'BNAD', 'Bouna / Doropo / Tanda', 'BON'),
	(139, 'BNDOK1', 'Bondoukou 1', 'BON'),
	(140, 'BNDOK2', 'Bondoukou 2', 'BON'),
	(141, 'Lbia', 'Labia/Mossibougou/Texas/Huberson/ Millionnaire/Soleil/Kenedy2/Suisse/Grand marche/ORLY / Flora', 'DAL'),
	(142, 'ABTT', 'Abattoir/Marche Manioc/Garage/Orly plateau/Dioulabougou', 'DAL'),
	(143, 'CMERCE 1', 'Commerce / Kani / Mankono / Serela / Kouenahiri', 'DAL'),
	(144, 'CMERCE 2', 'Commerce / Kani   / Mankona', 'MNK'),
	(145, 'DMDE', 'Diomande / Traoré / Rymer / Quartier Grarge / Garage Angola / Sifie / Kouego', 'MNK'),
	(146, 'SGULA', 'Séguéla/ Mankono / Kani / Dianra', 'MNK'),
	(147, 'MRCHE', 'Marche / Zele / Dayagoine / Municipal / Campus / Quartier thérèse /', 'MAN'),
	(148, 'CAFOP', 'Cafop / Camp SEA / Lycée club / Commerce / Koko / Libreville /', 'MAN'),
	(149, 'BKOUMA', 'Biankouma / Bafing / Touba / Koro / Complexe / Sangouine /', 'MAN'),
	(150, 'MANVI', 'Man ville', 'MAN'),
	(151, 'NBOUHI', 'Nanbouhi/Camp manoir/Chateau résidentiel/Gabon/Gbakalepa/Yabayo', 'SOU'),
	(152, 'ANMANB', 'Anoumanbo/Hibiscus/Sicogi/Sans fil/Zone 4/KBF', 'SOU'),
	(153, 'SBRE', 'Okrouyo- Guehio -Buyo -Bakayo-osserie-logboville-Dapea-lessirie-commerce-kpeiri-opouyo-cité ouvriere', 'SOU'),
	(155, 'MNGA', 'Monogaga / Dabiho / Marche / Doupoudou', 'SPD'),
	(156, 'GRDMRCH', 'Grand marche / Bereby / Commerce', 'SPD'),
	(157, 'CTE', 'Cité / Jule Ferry / Lac / Sewke / Bardot', 'SPD'),
	(158, 'JLESFE', 'Lac / Jules ferry / Zone industrielle / Bardot', 'SPD'),
	(159, 'CRDOR', 'Corridor / Gare / Sotref / Dafci', 'SPD'),
	(160, 'SLEIL', 'Zapata / Garahio / Babre / Soleil / Dioulabougou', 'GAG 2'),
	(161, 'CRDORS', 'Dares salam / Grarage Koffi / Garage Dosso / Corridor Sinfra', 'GAG 2'),
	(162, 'Ggnoa2', 'Gagnoa 2 / Guiberoua / Issia / Gueyo', 'GAG 2'),
	(163, 'CMRCE', 'Commerce / Gbakayo / Galebre / Tchedelei', 'GAG 1'),
	(164, 'SLEIL', 'Soleil / Delbo / Millionnaire / Commerce', 'GAG 1'),
	(165, 'GBKY', 'Dioulabougou / Katalina / Commerce / Gbakayo', 'GAG 1'),
	(166, 'SKOURA', 'Doukakou / Sokoura / Commerce / Bribore', 'DIV'),
	(167, 'LBANAIS', 'Konankro / Libanais / Jerusalem / Dialogue 2 / Dioulabougou', 'DIV'),
	(168, 'DLOGUE1', 'Commerce / Dialogue 1 / Gremian / Benoi', 'DIV'),
	(169, 'Giglo1N', 'Guiglo 1 nord', 'GUI 1'),
	(170, 'Giglo1S', 'Guiglo 1 sud', 'GUI 1'),
	(171, 'Giglo1DK', 'Guiglo 1 / Duekoué', 'GUI 1'),
	(172, 'Giglo2N', 'Guiglo 2 Nord', 'GUI 2'),
	(173, 'Giglo2S', 'Guiglo 2 sud', 'GUI 2'),
	(174, 'Giglo2TBA', 'Guiglo 2 / Touba', 'GUI 2'),
	(175, 'ODNE1', 'Odiénne 1', 'ODI'),
	(176, 'ODNE2', 'Odiénne 2', 'ODI'),
	(177, 'SMTIGLA', 'Odiénne / Tiémé / Madinani / Samatiguila', 'ODI'),
	(178, 'NIBLCAMA', 'NI3-BLONTIARA/DOROPO2-DASSIKELE/BOBOSSO-ZONGO/commerce /TEFRO-BOUNA2/CAMARASSO', 'Boun'),
	(179, 'BNGO', 'BOUNA /BROMAKOTE-VARALE/VARALE-DOROPO/AXE BOUNA-VONKORO/AXE BOUNA- MANGO', 'Boun');
INSERT INTO public.zone_distributeur VALUES
	(178, 1),
	(179, 1),
	(147, 4),
	(148, 4),
	(149, 4),
	(150, 4),
	(175, 5),
	(176, 5),
	(177, 5),
	(141, 6),
	(142, 6),
	(143, 6),
	(98, 7),
	(99, 7),
	(100, 7),
	(101, 7),
	(102, 7),
	(103, 7),
	(44, 7),
	(45, 7),
	(1, 11),
	(2, 11),
	(3, 11),
	(4, 11),
	(5, 11),
	(136, 12),
	(137, 12),
	(132, 12),
	(133, 12),
	(134, 12),
	(135, 12),
	(169, 13),
	(170, 13),
	(171, 13),
	(155, 14),
	(156, 14),
	(157, 14),
	(158, 14),
	(159, 14),
	(78, 15),
	(79, 15),
	(80, 15),
	(81, 15),
	(82, 15),
	(83, 15),
	(84, 15),
	(130, 16),
	(131, 16),
	(126, 17),
	(127, 17),
	(128, 17),
	(129, 17),
	(144, 19),
	(145, 19),
	(146, 19),
	(74, 21),
	(75, 21),
	(76, 21),
	(77, 21),
	(67, 21),
	(68, 21),
	(69, 21),
	(70, 21),
	(71, 21),
	(72, 21),
	(73, 21),
	(60, 21),
	(61, 21),
	(62, 21),
	(63, 21),
	(64, 21),
	(65, 21),
	(66, 21),
	(13, 24),
	(14, 24),
	(15, 24),
	(16, 24),
	(17, 24),
	(18, 24),
	(6, 24),
	(7, 24),
	(8, 24),
	(9, 24),
	(10, 24),
	(11, 24),
	(12, 24),
	(166, 27),
	(167, 27),
	(168, 27),
	(108, 28),
	(109, 28),
	(110, 28),
	(111, 28),
	(112, 28),
	(29, 29),
	(30, 29),
	(31, 29),
	(32, 29),
	(33, 29),
	(24, 31),
	(25, 31),
	(26, 31),
	(27, 31),
	(28, 31),
	(21, 31),
	(22, 31),
	(23, 31),
	(19, 31),
	(20, 31),
	(160, 33),
	(161, 33),
	(162, 33),
	(154, 33),
	(151, 33),
	(152, 33),
	(153, 33),
	(121, 35),
	(122, 35),
	(123, 35),
	(124, 35),
	(125, 35),
	(54, 36),
	(55, 36),
	(56, 36),
	(57, 36),
	(58, 36),
	(59, 36),
	(46, 36),
	(47, 36),
	(48, 36),
	(49, 36),
	(50, 36),
	(51, 36),
	(52, 36),
	(53, 36),
	(172, 37),
	(173, 37),
	(174, 37),
	(163, 38),
	(164, 38),
	(165, 38),
	(138, 40),
	(139, 40),
	(140, 40),
	(118, 41),
	(119, 41),
	(120, 41),
	(113, 41),
	(114, 41),
	(115, 41),
	(116, 41),
	(117, 41),
	(90, 42),
	(91, 42),
	(92, 42),
	(93, 42),
	(94, 42),
	(95, 42),
	(96, 42),
	(97, 42),
	(85, 42),
	(87, 42),
	(89, 42),
	(40, 42),
	(41, 42),
	(42, 42),
	(43, 42),
	(34, 42),
	(35, 42),
	(36, 42),
	(37, 42),
	(38, 42),
	(39, 42),
	(104, 43),
	(105, 43),
	(106, 44),
	(107, 44),
	(6, 23),
	(7, 23),
	(8, 23),
	(9, 23),
	(10, 23),
	(11, 23),
	(12, 23),
	(29, 30),
	(30, 30),
	(31, 30),
	(32, 30),
	(33, 30),
	(44, 45),
	(45, 45),
	(98, 45),
	(99, 45),
	(100, 45),
	(101, 45),
	(102, 45),
	(103, 45);
INSERT INTO public.zones_secteurs VALUES
	(16, 'Cocody 1', 'PALMERAIE', 'Daouda Essai', 'merchandiser1@fieldtrack.demo', 'Awa Démo', 'commercial1@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(17, 'Cocody 1', 'PERLE', 'Daouda Essai', 'merchandiser1@fieldtrack.demo', 'Awa Démo', 'commercial1@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(18, 'Cocody 1', 'LYCEE TECHNIQUE', 'Daouda Essai', 'merchandiser1@fieldtrack.demo', 'Awa Démo', 'commercial1@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(19, 'Marcory', 'RÉSIDENTIEL', 'Fabrice Essai', 'merchandiser3@fieldtrack.demo', 'Bakary Démo', 'commercial2@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(20, 'Marcory', 'SICOGI', 'Fabrice Essai', 'merchandiser3@fieldtrack.demo', 'Bakary Démo', 'commercial2@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(21, 'Marcory', 'HIBISCUS', 'Fabrice Essai', 'merchandiser3@fieldtrack.demo', 'Bakary Démo', 'commercial2@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(22, 'Plateau', 'PLATEAU CENTRE', 'Estelle Essai', 'merchandiser2@fieldtrack.demo', 'Awa Démo', 'commercial1@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(23, 'Plateau', 'CITE FERMONT', 'Estelle Essai', 'merchandiser2@fieldtrack.demo', 'Awa Démo', 'commercial1@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(24, 'Plateau', 'MARCHE DE FRUIT', 'Estelle Essai', 'merchandiser2@fieldtrack.demo', 'Awa Démo', 'commercial1@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(25, 'Treichville', 'ZONE 3', 'Grâce Essai', 'merchandiser4@fieldtrack.demo', 'Bakary Démo', 'commercial2@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(26, 'Treichville', 'ARAS', 'Grâce Essai', 'merchandiser4@fieldtrack.demo', 'Bakary Démo', 'commercial2@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(27, 'Treichville', 'BELLEVILLE', 'Grâce Essai', 'merchandiser4@fieldtrack.demo', 'Bakary Démo', 'commercial2@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(28, 'Yopougon 1', 'WASSAKARA', 'Hervé Essai', 'merchandiser5@fieldtrack.demo', 'Clarisse Démo', 'commercial3@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(29, 'Yopougon 1', 'YOPOUGON SABLE', 'Hervé Essai', 'merchandiser5@fieldtrack.demo', 'Clarisse Démo', 'commercial3@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00'),
	(30, 'Yopougon 1', 'TOIT ROUGE', 'Hervé Essai', 'merchandiser5@fieldtrack.demo', 'Clarisse Démo', 'commercial3@fieldtrack.demo', 'Abidjan', '2026-11-15 14:08:19.360439+00');
SELECT pg_catalog.setval('public.app_users_id_seq', 1, false);
SELECT pg_catalog.setval('public.canaux_routing_id_seq', 3, true);
SELECT pg_catalog.setval('public.categorie_pdv_id_seq', 17, true);
SELECT pg_catalog.setval('public.categorie_produit_id_seq', 3, true);
SELECT pg_catalog.setval('public.commerciaux_id_seq', 1, false);
SELECT pg_catalog.setval('public.distributeur_id_seq', 45, true);
SELECT pg_catalog.setval('public.element_visibilite_id_seq', 66, true);
SELECT pg_catalog.setval('public.frequence_visite_id_seq', 1, true);
SELECT pg_catalog.setval('public.geofence_zones_id_seq', 1, false);
SELECT pg_catalog.setval('public.jours_routing_id_seq', 24, true);
SELECT pg_catalog.setval('public.pays_id_seq', 1, true);
SELECT pg_catalog.setval('public.pdvs_id_seq', 1, false);
SELECT pg_catalog.setval('public.pos_types_id_seq', 1, false);
SELECT pg_catalog.setval('public.quartier_id_seq', 852, true);
SELECT pg_catalog.setval('public.reference_produit_id_seq', 15, true);
SELECT pg_catalog.setval('public.region_id_seq', 2, true);
SELECT pg_catalog.setval('public.routing_data_id_seq', 15, true);
SELECT pg_catalog.setval('public.sales_reps_id_seq', 25, true);
SELECT pg_catalog.setval('public.sous_region_id_seq', 4, true);
SELECT pg_catalog.setval('public.territoire_id_seq', 42, true);
SELECT pg_catalog.setval('public.type_pdv_id_seq', 41, true);
SELECT pg_catalog.setval('public.zone_id_seq', 179, true);
SELECT pg_catalog.setval('public.zones_secteurs_id_seq', 30, true);
ALTER TABLE ONLY public.action_commerciale
    ADD CONSTRAINT action_commerciale_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.app_users
    ADD CONSTRAINT app_users_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.appareil_push
    ADD CONSTRAINT appareil_push_pkey PRIMARY KEY (jeton);
ALTER TABLE ONLY public.assortment_standards
    ADD CONSTRAINT assortment_standards_pkey PRIMARY KEY (standard_group, tier);
ALTER TABLE ONLY public.availability_standards
    ADD CONSTRAINT availability_standards_pkey PRIMARY KEY (category, sku, standard_group, tier);
ALTER TABLE ONLY public.availability_weights
    ADD CONSTRAINT availability_weights_pkey PRIMARY KEY (category, trade_type, basis, sku);
ALTER TABLE ONLY public.canaux_routing
    ADD CONSTRAINT canaux_routing_canal_key UNIQUE (canal);
ALTER TABLE ONLY public.canaux_routing
    ADD CONSTRAINT canaux_routing_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.categorie_pdv
    ADD CONSTRAINT categorie_pdv_nom_key UNIQUE (nom);
ALTER TABLE ONLY public.categorie_pdv
    ADD CONSTRAINT categorie_pdv_nom_uk UNIQUE (nom);
ALTER TABLE ONLY public.categorie_pdv
    ADD CONSTRAINT categorie_pdv_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.categorie_produit
    ADD CONSTRAINT categorie_produit_code_key UNIQUE (code);
ALTER TABLE ONLY public.categorie_produit
    ADD CONSTRAINT categorie_produit_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.categorie_releve
    ADD CONSTRAINT categorie_releve_pkey PRIMARY KEY (code);
ALTER TABLE ONLY public.category_weights
    ADD CONSTRAINT category_weights_pkey PRIMARY KEY (category, trade_type);
ALTER TABLE ONLY public.commerciaux
    ADD CONSTRAINT commerciaux_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.correspondance_reference
    ADD CONSTRAINT correspondance_reference_pkey PRIMARY KEY (categorie_jsonb, sku_key);
ALTER TABLE ONLY public.distributeur
    ADD CONSTRAINT distributeur_nom_key UNIQUE (nom);
ALTER TABLE ONLY public.distributeur
    ADD CONSTRAINT distributeur_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.element_visibilite
    ADD CONSTRAINT element_visibilite_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.element_visibilite
    ADD CONSTRAINT element_visibilite_segment_nom_key UNIQUE (segment, nom);
ALTER TABLE ONLY public.engin_vente
    ADD CONSTRAINT engin_vente_pkey PRIMARY KEY (code);
ALTER TABLE ONLY public.field_coaching
    ADD CONSTRAINT field_coaching_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.field_coaching_transfert
    ADD CONSTRAINT field_coaching_transfert_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.frequence_visite
    ADD CONSTRAINT frequence_visite_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.frequence_visite
    ADD CONSTRAINT frequence_visite_zone_type_pdv_key UNIQUE NULLS NOT DISTINCT (zone, type_pdv);
ALTER TABLE ONLY public.geofence_zones
    ADD CONSTRAINT geofence_zones_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.jours_routing
    ADD CONSTRAINT jours_routing_jour_key UNIQUE (jour);
ALTER TABLE ONLY public.jours_routing
    ADD CONSTRAINT jours_routing_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.marque_concurrente
    ADD CONSTRAINT marque_concurrente_famille_code_key UNIQUE (famille, code);
ALTER TABLE ONLY public.marque_concurrente
    ADD CONSTRAINT marque_concurrente_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.marque_concurrente_sku
    ADD CONSTRAINT marque_concurrente_sku_marque_id_code_key UNIQUE (marque_id, code);
ALTER TABLE ONLY public.marque_concurrente_sku
    ADD CONSTRAINT marque_concurrente_sku_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.niveau_perfect_store
    ADD CONSTRAINT niveau_perfect_store_pkey PRIMARY KEY (code);
ALTER TABLE ONLY public.parametre_suivi
    ADD CONSTRAINT parametre_suivi_pkey PRIMARY KEY (cle);
ALTER TABLE ONLY public.pays
    ADD CONSTRAINT pays_code_key UNIQUE (code);
ALTER TABLE ONLY public.pays
    ADD CONSTRAINT pays_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.pdv
    ADD CONSTRAINT pdv_pdv_id_key UNIQUE (pdv_id);
ALTER TABLE ONLY public.pdv
    ADD CONSTRAINT pdv_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.pdvs
    ADD CONSTRAINT pdvs_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.perfect_store_score_config
    ADD CONSTRAINT perfect_store_score_config_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.perfect_store_tier_config
    ADD CONSTRAINT perfect_store_tier_config_pkey PRIMARY KEY (ps_tier);
ALTER TABLE ONLY public.poids_reference
    ADD CONSTRAINT poids_reference_pkey PRIMARY KEY (reference_produit_id, canal, base_calcul);
ALTER TABLE ONLY public.pos_standard_map
    ADD CONSTRAINT pos_standard_map_pkey PRIMARY KEY (sous_categorie_pdv);
ALTER TABLE ONLY public.pos_types
    ADD CONSTRAINT pos_types_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.position_tournee
    ADD CONSTRAINT position_tournee_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.quartier
    ADD CONSTRAINT quartier_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.quartier
    ADD CONSTRAINT quartier_zone_id_nom_key UNIQUE (zone_id, nom);
ALTER TABLE ONLY public.reference_produit
    ADD CONSTRAINT reference_produit_nom_key UNIQUE (nom);
ALTER TABLE ONLY public.reference_produit
    ADD CONSTRAINT reference_produit_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.region
    ADD CONSTRAINT region_code_key UNIQUE (code);
ALTER TABLE ONLY public.region
    ADD CONSTRAINT region_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.resultat_perfect_store
    ADD CONSTRAINT resultat_perfect_store_pkey PRIMARY KEY (visite_id);
ALTER TABLE ONLY public.role_section_access
    ADD CONSTRAINT role_section_access_pkey PRIMARY KEY (role, section);
ALTER TABLE ONLY public.routing_data
    ADD CONSTRAINT routing_data_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.routing_pdv
    ADD CONSTRAINT routing_pdv_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.routing_pdv
    ADD CONSTRAINT routing_pdv_routing_id_pdv_id_key UNIQUE (routing_id, pdv_id);
ALTER TABLE ONLY public.routing_template_exception
    ADD CONSTRAINT routing_template_exception_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.routing_template_pdv
    ADD CONSTRAINT routing_template_pdv_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.routing_template_pdv
    ADD CONSTRAINT routing_template_pdv_template_id_pdv_id_key UNIQUE (template_id, pdv_id);
ALTER TABLE ONLY public.routing_templates
    ADD CONSTRAINT routing_templates_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.routing_templates
    ADD CONSTRAINT routing_templates_user_id_day_of_week_key UNIQUE (user_id, day_of_week);
ALTER TABLE ONLY public.routings
    ADD CONSTRAINT routings_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.routings
    ADD CONSTRAINT routings_user_id_date_routing_key UNIQUE (user_id, date_routing);
ALTER TABLE ONLY public.sales_reps
    ADD CONSTRAINT sales_reps_nom_key UNIQUE (nom);
ALTER TABLE ONLY public.sales_reps
    ADD CONSTRAINT sales_reps_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.segment_grade_type_pdv
    ADD CONSTRAINT segment_grade_type_pdv_pkey PRIMARY KEY (type_pdv_id);
ALTER TABLE ONLY public.segment_visibilite_type_pdv
    ADD CONSTRAINT segment_visibilite_type_pdv_pkey PRIMARY KEY (type_pdv_id);
ALTER TABLE ONLY public.seuil_disponibilite_mt
    ADD CONSTRAINT seuil_disponibilite_mt_pkey PRIMARY KEY (reference_produit_id, segment_mt);
ALTER TABLE ONLY public.seuil_disponibilite
    ADD CONSTRAINT seuil_disponibilite_pkey PRIMARY KEY (reference_produit_id, segment, grade);
ALTER TABLE ONLY public.sku_thresholds
    ADD CONSTRAINT sku_thresholds_pkey PRIMARY KEY (category, sku);
ALTER TABLE ONLY public.sous_region
    ADD CONSTRAINT sous_region_code_key UNIQUE (code);
ALTER TABLE ONLY public.sous_region
    ADD CONSTRAINT sous_region_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.standard_assortiment
    ADD CONSTRAINT standard_assortiment_pkey PRIMARY KEY (segment, grade);
ALTER TABLE ONLY public.standard_visibilite
    ADD CONSTRAINT standard_visibilite_pkey PRIMARY KEY (niveau_perfect_store, element_visibilite_id);
ALTER TABLE ONLY public.territoire_alias
    ADD CONSTRAINT territoire_alias_pkey PRIMARY KEY (alias);
ALTER TABLE ONLY public.territoire
    ADD CONSTRAINT territoire_code_key UNIQUE (code);
ALTER TABLE ONLY public.territoire_distributeur
    ADD CONSTRAINT territoire_distributeur_pkey PRIMARY KEY (territoire_id, distributeur_id);
ALTER TABLE ONLY public.territoire
    ADD CONSTRAINT territoire_nom_key UNIQUE (nom);
ALTER TABLE ONLY public.territoire
    ADD CONSTRAINT territoire_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.type_action_commerciale
    ADD CONSTRAINT type_action_commerciale_pkey PRIMARY KEY (code);
ALTER TABLE ONLY public.type_pdv
    ADD CONSTRAINT type_pdv_nom_key UNIQUE (nom);
ALTER TABLE ONLY public.type_pdv
    ADD CONSTRAINT type_pdv_nom_uk UNIQUE (nom);
ALTER TABLE ONLY public.type_pdv
    ADD CONSTRAINT type_pdv_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.version_app
    ADD CONSTRAINT version_app_pkey PRIMARY KEY (plateforme);
ALTER TABLE ONLY public.version_installee
    ADD CONSTRAINT version_installee_pkey PRIMARY KEY (user_id);
ALTER TABLE ONLY public.visibility_standards
    ADD CONSTRAINT visibility_standards_pkey PRIMARY KEY (standard_group, ps_tier, zone, element_key);
ALTER TABLE ONLY public.visite_perfect_store
    ADD CONSTRAINT visite_perfect_store_pkey PRIMARY KEY (visite_id);
ALTER TABLE ONLY public.visites
    ADD CONSTRAINT visites_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.visites
    ADD CONSTRAINT visites_visite_id_key UNIQUE (visite_id);
ALTER TABLE ONLY public.zone_distributeur
    ADD CONSTRAINT zone_distributeur_pkey PRIMARY KEY (zone_id, distributeur_id);
ALTER TABLE ONLY public.zone
    ADD CONSTRAINT zone_nat_uk UNIQUE (territoire_code, code, nom);
ALTER TABLE ONLY public.zone
    ADD CONSTRAINT zone_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.zones_secteurs
    ADD CONSTRAINT zones_secteurs_pkey PRIMARY KEY (id);
CREATE UNIQUE INDEX element_visibilite_segment_code_uq ON public.element_visibilite USING btree (segment, code);
CREATE INDEX idx_action_commerciale_assigne ON public.action_commerciale USING btree (assigne_a, statut);
CREATE INDEX idx_action_commerciale_auteur ON public.action_commerciale USING btree (auteur_id, created_at DESC);
CREATE INDEX idx_action_commerciale_pdv ON public.action_commerciale USING btree (pdv_id, statut);
CREATE INDEX idx_appareil_push_user ON public.appareil_push USING btree (user_id);
CREATE INDEX idx_field_coaching_assigne ON public.field_coaching USING btree (assigne_a);
CREATE INDEX idx_field_coaching_auteur ON public.field_coaching USING btree (auteur_id, date_coaching DESC);
CREATE INDEX idx_field_coaching_date ON public.field_coaching USING btree (date_coaching DESC);
CREATE INDEX idx_field_coaching_pdv ON public.field_coaching USING btree (pdv_id, date_coaching DESC);
CREATE INDEX idx_field_coaching_transfert_coaching ON public.field_coaching_transfert USING btree (coaching_id, created_at DESC);
CREATE INDEX idx_pdv_active_nom ON public.pdv USING btree (nom_pdv) WHERE (is_active = true);
CREATE INDEX idx_pdv_active_region_nom ON public.pdv USING btree (region, nom_pdv) WHERE (is_active = true);
CREATE INDEX idx_pdv_active_secteur_nom ON public.pdv USING btree (quartier, nom_pdv) WHERE (is_active = true);
CREATE INDEX idx_pdv_active_zone_nom ON public.pdv USING btree (zone, nom_pdv) WHERE (is_active = true);
CREATE INDEX idx_pdv_adressage_trgm ON public.pdv USING gin (adressage public.gin_trgm_ops);
CREATE INDEX idx_pdv_area_code ON public.pdv USING btree (area_code);
CREATE INDEX idx_pdv_canal ON public.pdv USING btree (canal);
CREATE INDEX idx_pdv_geolocation ON public.pdv USING btree (geolocation_lat, geolocation_lng);
CREATE INDEX idx_pdv_mdm ON public.pdv USING btree (mdm);
CREATE INDEX idx_pdv_nom_trgm ON public.pdv USING gin (nom_pdv public.gin_trgm_ops);
CREATE INDEX idx_pdv_pdv_id ON public.pdv USING btree (pdv_id);
CREATE INDEX idx_pdv_pdvid_trgm ON public.pdv USING gin (pdv_id public.gin_trgm_ops);
CREATE INDEX idx_pdv_quartier ON public.pdv USING btree (quartier);
CREATE INDEX idx_pdv_region ON public.pdv USING btree (region);
CREATE INDEX idx_pdv_secteur ON public.pdv USING btree (quartier);
CREATE INDEX idx_pdv_territory_code ON public.pdv USING btree (territory_code);
CREATE INDEX idx_pdv_zone ON public.pdv USING btree (zone);
CREATE INDEX idx_pdv_zone_quartier ON public.pdv USING btree (zone, quartier);
CREATE INDEX idx_position_tournee_tournee ON public.position_tournee USING btree (tournee_id, captured_at);
CREATE INDEX idx_position_tournee_user_date ON public.position_tournee USING btree (user_id, captured_at DESC);
CREATE INDEX idx_profiles_commercial ON public.profiles USING btree (commercial_id);
CREATE INDEX idx_profiles_email ON public.profiles USING btree (email);
CREATE INDEX idx_profiles_role ON public.profiles USING btree (role);
CREATE INDEX idx_routing_exception_template ON public.routing_template_exception USING btree (template_id, date_debut, date_fin);
CREATE INDEX idx_routing_pdv_pdv ON public.routing_pdv USING btree (pdv_id);
CREATE INDEX idx_routing_pdv_routing ON public.routing_pdv USING btree (routing_id);
CREATE INDEX idx_routing_pdv_status ON public.routing_pdv USING btree (status);
CREATE INDEX idx_routing_template_pdv_pdv ON public.routing_template_pdv USING btree (pdv_id);
CREATE INDEX idx_routing_template_pdv_template ON public.routing_template_pdv USING btree (template_id);
CREATE INDEX idx_routing_templates_active ON public.routing_templates USING btree (is_active);
CREATE INDEX idx_routing_templates_day ON public.routing_templates USING btree (day_of_week);
CREATE INDEX idx_routing_templates_user ON public.routing_templates USING btree (user_id);
CREATE INDEX idx_routings_date ON public.routings USING btree (date_routing);
CREATE INDEX idx_routings_status ON public.routings USING btree (status);
CREATE INDEX idx_routings_user_date ON public.routings USING btree (user_id, date_routing);
CREATE INDEX idx_visites_data ON public.visites USING gin (data);
CREATE INDEX idx_visites_date ON public.visites USING btree (date_visite);
CREATE INDEX idx_visites_email ON public.visites USING btree (email);
CREATE INDEX idx_visites_pdv_date ON public.visites USING btree (pdv_id, date_visite DESC);
CREATE INDEX idx_visites_pdv_id ON public.visites USING btree (pdv_id);
CREATE INDEX idx_visites_status ON public.visites USING btree (status);
CREATE INDEX idx_visites_user_id ON public.visites USING btree (user_id);
CREATE INDEX idx_zones_secteurs_region ON public.zones_secteurs USING btree (region);
CREATE INDEX idx_zones_secteurs_zone ON public.zones_secteurs USING btree (zone);
CREATE INDEX marque_concurrente_sku_marque_idx ON public.marque_concurrente_sku USING btree (marque_id, ordre);
CREATE INDEX quartier_zone_idx ON public.quartier USING btree (zone_id);
CREATE UNIQUE INDEX mv_distribution_pdv_type_idx ON stats.mv_distribution_pdv USING btree (type);
CREATE UNIQUE INDEX mv_performance_commerciaux_id_idx ON stats.mv_performance_commerciaux USING btree (id);
CREATE UNIQUE INDEX mv_stats_visites_id_idx ON stats.mv_stats_visites USING btree (id);
CREATE UNIQUE INDEX mv_visites_par_jour_date_idx ON stats.mv_visites_par_jour USING btree (date);
CREATE TRIGGER profiles_prevent_escalation BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.prevent_profile_privilege_escalation();
CREATE TRIGGER set_updated_at_pdv BEFORE UPDATE ON public.pdv FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER set_updated_at_profiles BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER set_updated_at_visites BEFORE UPDATE ON public.visites FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER trg_action_commerciale_push AFTER INSERT OR UPDATE OF assigne_a ON public.action_commerciale FOR EACH ROW EXECUTE FUNCTION public.notifier_action_assignee();
CREATE TRIGGER trg_action_commerciale_touch BEFORE UPDATE ON public.action_commerciale FOR EACH ROW EXECUTE FUNCTION public.action_commerciale_touch();
CREATE TRIGGER trg_anonymiser_visites_du_profil BEFORE DELETE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.anonymiser_visites_du_profil();
CREATE TRIGGER trg_field_coaching_touch BEFORE UPDATE ON public.field_coaching FOR EACH ROW EXECUTE FUNCTION public.action_commerciale_touch();
CREATE TRIGGER trg_perfect_store AFTER INSERT OR UPDATE OF data, pdv_id ON public.visites FOR EACH ROW EXECUTE FUNCTION public.trg_calculer_perfect_store();
CREATE TRIGGER trg_profiles_commercial_id_valide BEFORE INSERT OR UPDATE OF commercial_id ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.profiles_commercial_id_valide();
CREATE TRIGGER trg_routing_pdv_updated_at BEFORE UPDATE ON public.routing_pdv FOR EACH ROW EXECUTE FUNCTION public.update_routing_updated_at();
CREATE TRIGGER trg_routing_template_pdv_updated_at BEFORE UPDATE ON public.routing_template_pdv FOR EACH ROW EXECUTE FUNCTION public.update_routing_updated_at();
CREATE TRIGGER trg_routing_templates_updated_at BEFORE UPDATE ON public.routing_templates FOR EACH ROW EXECUTE FUNCTION public.update_routing_updated_at();
CREATE TRIGGER trg_routings_updated_at BEFORE UPDATE ON public.routings FOR EACH ROW EXECUTE FUNCTION public.update_routing_updated_at();
CREATE TRIGGER trg_visites_garde_statut BEFORE UPDATE OF status ON public.visites FOR EACH ROW EXECUTE FUNCTION public.visites_garde_statut();
CREATE TRIGGER trg_visites_touch_synced_at BEFORE INSERT OR UPDATE ON public.visites FOR EACH ROW EXECUTE FUNCTION public.visites_touch_synced_at();
CREATE TRIGGER visites_perfect_store AFTER INSERT OR UPDATE OF data ON public.visites FOR EACH ROW EXECUTE FUNCTION public.trg_compute_perfect_store();
ALTER TABLE ONLY public.action_commerciale
    ADD CONSTRAINT action_commerciale_assigne_a_fkey FOREIGN KEY (assigne_a) REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.action_commerciale
    ADD CONSTRAINT action_commerciale_auteur_id_fkey FOREIGN KEY (auteur_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.action_commerciale
    ADD CONSTRAINT action_commerciale_pdv_id_fkey FOREIGN KEY (pdv_id) REFERENCES public.pdv(pdv_id) ON DELETE CASCADE;
ALTER TABLE ONLY public.action_commerciale
    ADD CONSTRAINT action_commerciale_type_code_fkey FOREIGN KEY (type_code) REFERENCES public.type_action_commerciale(code);
ALTER TABLE ONLY public.action_commerciale
    ADD CONSTRAINT action_commerciale_visite_id_fkey FOREIGN KEY (visite_id) REFERENCES public.visites(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.appareil_push
    ADD CONSTRAINT appareil_push_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.correspondance_reference
    ADD CONSTRAINT correspondance_reference_reference_produit_id_fkey FOREIGN KEY (reference_produit_id) REFERENCES public.reference_produit(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.field_coaching
    ADD CONSTRAINT field_coaching_assigne_a_fkey FOREIGN KEY (assigne_a) REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.field_coaching
    ADD CONSTRAINT field_coaching_auteur_id_fkey FOREIGN KEY (auteur_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.field_coaching
    ADD CONSTRAINT field_coaching_engin_code_fkey FOREIGN KEY (engin_code) REFERENCES public.engin_vente(code);
ALTER TABLE ONLY public.field_coaching
    ADD CONSTRAINT field_coaching_pdv_id_fkey FOREIGN KEY (pdv_id) REFERENCES public.pdv(pdv_id) ON DELETE CASCADE;
ALTER TABLE ONLY public.field_coaching
    ADD CONSTRAINT field_coaching_superviseur_id_fkey FOREIGN KEY (superviseur_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.field_coaching_transfert
    ADD CONSTRAINT field_coaching_transfert_coaching_id_fkey FOREIGN KEY (coaching_id) REFERENCES public.field_coaching(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.field_coaching_transfert
    ADD CONSTRAINT field_coaching_transfert_de_user_fkey FOREIGN KEY (de_user) REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.field_coaching_transfert
    ADD CONSTRAINT field_coaching_transfert_par_user_fkey FOREIGN KEY (par_user) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.field_coaching_transfert
    ADD CONSTRAINT field_coaching_transfert_vers_user_fkey FOREIGN KEY (vers_user) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.marque_concurrente_sku
    ADD CONSTRAINT marque_concurrente_sku_marque_id_fkey FOREIGN KEY (marque_id) REFERENCES public.marque_concurrente(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.pdv
    ADD CONSTRAINT pdv_gps_maj_par_fkey FOREIGN KEY (gps_maj_par) REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.poids_reference
    ADD CONSTRAINT poids_reference_reference_produit_id_fkey FOREIGN KEY (reference_produit_id) REFERENCES public.reference_produit(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.position_tournee
    ADD CONSTRAINT position_tournee_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_commercial_id_fkey FOREIGN KEY (commercial_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.quartier
    ADD CONSTRAINT quartier_zone_id_fkey FOREIGN KEY (zone_id) REFERENCES public.zone(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.reference_produit
    ADD CONSTRAINT reference_produit_categorie_produit_id_fkey FOREIGN KEY (categorie_produit_id) REFERENCES public.categorie_produit(id);
ALTER TABLE ONLY public.region
    ADD CONSTRAINT region_pays_code_fkey FOREIGN KEY (pays_code) REFERENCES public.pays(code);
ALTER TABLE ONLY public.resultat_perfect_store
    ADD CONSTRAINT resultat_perfect_store_niveau_fkey FOREIGN KEY (niveau) REFERENCES public.niveau_perfect_store(code);
ALTER TABLE ONLY public.resultat_perfect_store
    ADD CONSTRAINT resultat_perfect_store_visite_id_fkey FOREIGN KEY (visite_id) REFERENCES public.visites(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.routing_pdv
    ADD CONSTRAINT routing_pdv_pdv_id_fkey FOREIGN KEY (pdv_id) REFERENCES public.pdv(pdv_id) ON DELETE CASCADE;
ALTER TABLE ONLY public.routing_pdv
    ADD CONSTRAINT routing_pdv_routing_id_fkey FOREIGN KEY (routing_id) REFERENCES public.routings(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.routing_pdv
    ADD CONSTRAINT routing_pdv_visite_id_fkey FOREIGN KEY (visite_id) REFERENCES public.visites(visite_id);
ALTER TABLE ONLY public.routing_template_exception
    ADD CONSTRAINT routing_template_exception_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);
ALTER TABLE ONLY public.routing_template_exception
    ADD CONSTRAINT routing_template_exception_pdv_id_fkey FOREIGN KEY (pdv_id) REFERENCES public.pdv(pdv_id) ON DELETE CASCADE;
ALTER TABLE ONLY public.routing_template_exception
    ADD CONSTRAINT routing_template_exception_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.routing_templates(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.routing_template_pdv
    ADD CONSTRAINT routing_template_pdv_pdv_id_fkey FOREIGN KEY (pdv_id) REFERENCES public.pdv(pdv_id) ON DELETE CASCADE;
ALTER TABLE ONLY public.routing_template_pdv
    ADD CONSTRAINT routing_template_pdv_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.routing_templates(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.routing_templates
    ADD CONSTRAINT routing_templates_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);
ALTER TABLE ONLY public.routing_templates
    ADD CONSTRAINT routing_templates_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.routings
    ADD CONSTRAINT routings_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);
ALTER TABLE ONLY public.routings
    ADD CONSTRAINT routings_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.routing_templates(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.routings
    ADD CONSTRAINT routings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.segment_grade_type_pdv
    ADD CONSTRAINT segment_grade_type_pdv_type_pdv_id_fkey FOREIGN KEY (type_pdv_id) REFERENCES public.type_pdv(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.segment_visibilite_type_pdv
    ADD CONSTRAINT segment_visibilite_type_pdv_type_pdv_id_fkey FOREIGN KEY (type_pdv_id) REFERENCES public.type_pdv(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.seuil_disponibilite_mt
    ADD CONSTRAINT seuil_disponibilite_mt_reference_produit_id_fkey FOREIGN KEY (reference_produit_id) REFERENCES public.reference_produit(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.seuil_disponibilite
    ADD CONSTRAINT seuil_disponibilite_reference_produit_id_fkey FOREIGN KEY (reference_produit_id) REFERENCES public.reference_produit(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.sous_region
    ADD CONSTRAINT sous_region_region_code_fkey FOREIGN KEY (region_code) REFERENCES public.region(code);
ALTER TABLE ONLY public.standard_visibilite
    ADD CONSTRAINT standard_visibilite_element_visibilite_id_fkey FOREIGN KEY (element_visibilite_id) REFERENCES public.element_visibilite(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.territoire_alias
    ADD CONSTRAINT territoire_alias_territoire_code_fkey FOREIGN KEY (territoire_code) REFERENCES public.territoire(code) ON DELETE CASCADE;
ALTER TABLE ONLY public.territoire_distributeur
    ADD CONSTRAINT territoire_distributeur_distributeur_id_fkey FOREIGN KEY (distributeur_id) REFERENCES public.distributeur(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.territoire_distributeur
    ADD CONSTRAINT territoire_distributeur_territoire_id_fkey FOREIGN KEY (territoire_id) REFERENCES public.territoire(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.territoire
    ADD CONSTRAINT territoire_sous_region_code_fkey FOREIGN KEY (sous_region_code) REFERENCES public.sous_region(code);
ALTER TABLE ONLY public.type_pdv
    ADD CONSTRAINT type_pdv_categorie_pdv_id_fkey FOREIGN KEY (categorie_pdv_id) REFERENCES public.categorie_pdv(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.version_installee
    ADD CONSTRAINT version_installee_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.visite_perfect_store
    ADD CONSTRAINT visite_perfect_store_visite_id_fkey FOREIGN KEY (visite_id) REFERENCES public.visites(visite_id) ON DELETE CASCADE;
ALTER TABLE ONLY public.visites
    ADD CONSTRAINT visites_pdv_id_fkey FOREIGN KEY (pdv_id) REFERENCES public.pdv(pdv_id);
ALTER TABLE ONLY public.visites
    ADD CONSTRAINT visites_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.zone_distributeur
    ADD CONSTRAINT zone_distributeur_distributeur_id_fkey FOREIGN KEY (distributeur_id) REFERENCES public.distributeur(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.zone_distributeur
    ADD CONSTRAINT zone_distributeur_zone_id_fkey FOREIGN KEY (zone_id) REFERENCES public.zone(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.zone
    ADD CONSTRAINT zone_territoire_code_fkey FOREIGN KEY (territoire_code) REFERENCES public.territoire(code);
ALTER TABLE public.action_commerciale ENABLE ROW LEVEL SECURITY;
CREATE POLICY action_commerciale_delete ON public.action_commerciale FOR DELETE TO authenticated USING ((public.role_actif_courant() = 'admin'::text));
CREATE POLICY action_commerciale_insert ON public.action_commerciale FOR INSERT TO authenticated WITH CHECK (((auteur_id = auth.uid()) AND (public.role_actif_courant() = ANY (ARRAY['commercial'::text, 'admin'::text, 'superviseur'::text])) AND public.pdv_dans_perimetre(pdv_id)));
CREATE POLICY action_commerciale_select ON public.action_commerciale FOR SELECT TO authenticated USING (((auteur_id = auth.uid()) OR (assigne_a = auth.uid()) OR public.pdv_dans_perimetre(pdv_id)));
CREATE POLICY action_commerciale_update ON public.action_commerciale FOR UPDATE TO authenticated USING (((auteur_id = auth.uid()) OR (assigne_a = auth.uid()) OR (public.role_actif_courant() = ANY (ARRAY['admin'::text, 'superviseur'::text])))) WITH CHECK (((auteur_id = auth.uid()) OR (assigne_a = auth.uid()) OR (public.role_actif_courant() = ANY (ARRAY['admin'::text, 'superviseur'::text]))));
ALTER TABLE public.appareil_push ENABLE ROW LEVEL SECURITY;
CREATE POLICY appareil_push_delete_moi ON public.appareil_push FOR DELETE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));
CREATE POLICY appareil_push_insert_moi ON public.appareil_push FOR INSERT TO authenticated WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));
CREATE POLICY appareil_push_select_moi ON public.appareil_push FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));
CREATE POLICY appareil_push_update_moi ON public.appareil_push FOR UPDATE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));
CREATE POLICY ass_read ON public.assortment_standards FOR SELECT TO authenticated USING (true);
CREATE POLICY ass_write ON public.assortment_standards USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
ALTER TABLE public.assortment_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.availability_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.availability_weights ENABLE ROW LEVEL SECURITY;
CREATE POLICY avs_read ON public.availability_standards FOR SELECT TO authenticated USING (true);
CREATE POLICY avs_write ON public.availability_standards USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
CREATE POLICY avw_read ON public.availability_weights FOR SELECT TO authenticated USING (true);
CREATE POLICY avw_write ON public.availability_weights USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
ALTER TABLE public.canaux_routing ENABLE ROW LEVEL SECURITY;
CREATE POLICY canaux_routing_admin ON public.canaux_routing USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
CREATE POLICY canaux_routing_select ON public.canaux_routing FOR SELECT USING ((auth.role() = 'authenticated'::text));
ALTER TABLE public.categorie_pdv ENABLE ROW LEVEL SECURITY;
CREATE POLICY categorie_pdv_authenticated_read ON public.categorie_pdv FOR SELECT TO authenticated USING (true);
CREATE POLICY categorie_pdv_manager_write ON public.categorie_pdv TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.categorie_produit ENABLE ROW LEVEL SECURITY;
CREATE POLICY categorie_produit_authenticated_read ON public.categorie_produit FOR SELECT TO authenticated USING (true);
CREATE POLICY categorie_produit_manager_write ON public.categorie_produit TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.categorie_releve ENABLE ROW LEVEL SECURITY;
CREATE POLICY categorie_releve_read ON public.categorie_releve FOR SELECT TO authenticated USING (true);
CREATE POLICY categorie_releve_write ON public.categorie_releve TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.category_weights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.correspondance_reference ENABLE ROW LEVEL SECURITY;
CREATE POLICY correspondance_reference_authenticated_read ON public.correspondance_reference FOR SELECT TO authenticated USING (true);
CREATE POLICY correspondance_reference_manager_write ON public.correspondance_reference TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
CREATE POLICY cw_read ON public.category_weights FOR SELECT TO authenticated USING (true);
CREATE POLICY cw_write ON public.category_weights USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
ALTER TABLE public.distributeur ENABLE ROW LEVEL SECURITY;
CREATE POLICY distributeur_authenticated_read ON public.distributeur FOR SELECT TO authenticated USING (true);
CREATE POLICY distributeur_manager_write ON public.distributeur TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.element_visibilite ENABLE ROW LEVEL SECURITY;
CREATE POLICY element_visibilite_authenticated_read ON public.element_visibilite FOR SELECT TO authenticated USING (true);
CREATE POLICY element_visibilite_manager_write ON public.element_visibilite TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
CREATE POLICY element_visibilite_read ON public.element_visibilite FOR SELECT TO authenticated USING (true);
ALTER TABLE public.engin_vente ENABLE ROW LEVEL SECURITY;
CREATE POLICY engin_vente_read ON public.engin_vente FOR SELECT TO authenticated USING (true);
CREATE POLICY engin_vente_write ON public.engin_vente TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.field_coaching ENABLE ROW LEVEL SECURITY;
CREATE POLICY field_coaching_delete ON public.field_coaching FOR DELETE TO authenticated USING ((public.role_actif_courant() = 'admin'::text));
CREATE POLICY field_coaching_insert ON public.field_coaching FOR INSERT TO authenticated WITH CHECK (((auteur_id = auth.uid()) AND (public.role_actif_courant() = ANY (ARRAY['superviseur'::text, 'commercial'::text, 'admin'::text]))));
CREATE POLICY field_coaching_select ON public.field_coaching FOR SELECT TO authenticated USING (((auteur_id = auth.uid()) OR (assigne_a = auth.uid()) OR (superviseur_id = auth.uid()) OR ((public.role_actif_courant() = ANY (ARRAY['commercial'::text, 'superviseur'::text, 'admin'::text])) AND public.pdv_dans_perimetre(pdv_id))));
ALTER TABLE public.field_coaching_transfert ENABLE ROW LEVEL SECURITY;
CREATE POLICY field_coaching_transfert_insert ON public.field_coaching_transfert FOR INSERT TO authenticated WITH CHECK (((par_user = auth.uid()) AND (EXISTS ( SELECT 1
   FROM public.field_coaching c
  WHERE ((c.id = field_coaching_transfert.coaching_id) AND ((c.auteur_id = auth.uid()) OR (c.assigne_a = auth.uid()) OR (public.role_actif_courant() = ANY (ARRAY['admin'::text, 'superviseur'::text]))))))));
CREATE POLICY field_coaching_transfert_select ON public.field_coaching_transfert FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.field_coaching c
  WHERE (c.id = field_coaching_transfert.coaching_id))));
CREATE POLICY field_coaching_update ON public.field_coaching FOR UPDATE TO authenticated USING (((auteur_id = auth.uid()) OR (assigne_a = auth.uid()) OR (public.role_actif_courant() = ANY (ARRAY['admin'::text, 'superviseur'::text])))) WITH CHECK (((auteur_id = auth.uid()) OR (assigne_a = auth.uid()) OR (public.role_actif_courant() = ANY (ARRAY['admin'::text, 'superviseur'::text]))));
ALTER TABLE public.frequence_visite ENABLE ROW LEVEL SECURITY;
CREATE POLICY frequence_visite_read ON public.frequence_visite FOR SELECT TO authenticated USING (true);
CREATE POLICY frequence_visite_write ON public.frequence_visite TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.jours_routing ENABLE ROW LEVEL SECURITY;
CREATE POLICY jours_routing_admin ON public.jours_routing USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
CREATE POLICY jours_routing_select ON public.jours_routing FOR SELECT USING ((auth.role() = 'authenticated'::text));
ALTER TABLE public.marque_concurrente ENABLE ROW LEVEL SECURITY;
CREATE POLICY marque_concurrente_read ON public.marque_concurrente FOR SELECT TO authenticated USING (true);
ALTER TABLE public.marque_concurrente_sku ENABLE ROW LEVEL SECURITY;
CREATE POLICY marque_concurrente_sku_read ON public.marque_concurrente_sku FOR SELECT TO authenticated USING (true);
CREATE POLICY marque_concurrente_sku_write ON public.marque_concurrente_sku TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
CREATE POLICY marque_concurrente_write ON public.marque_concurrente TO authenticated USING (true) WITH CHECK (true);
ALTER TABLE public.niveau_perfect_store ENABLE ROW LEVEL SECURITY;
CREATE POLICY niveau_perfect_store_authenticated_read ON public.niveau_perfect_store FOR SELECT TO authenticated USING (true);
CREATE POLICY niveau_perfect_store_manager_write ON public.niveau_perfect_store TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.parametre_suivi ENABLE ROW LEVEL SECURITY;
CREATE POLICY parametre_suivi_read ON public.parametre_suivi FOR SELECT TO authenticated USING (true);
CREATE POLICY parametre_suivi_write ON public.parametre_suivi TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.pays ENABLE ROW LEVEL SECURITY;
CREATE POLICY pays_authenticated_read ON public.pays FOR SELECT TO authenticated USING (true);
CREATE POLICY pays_manager_write ON public.pays TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.pdv ENABLE ROW LEVEL SECURITY;
CREATE POLICY pdv_delete_admin ON public.pdv FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
CREATE POLICY pdv_insert_terrain ON public.pdv FOR INSERT WITH CHECK (public.peut_ecrire_terrain());
CREATE POLICY pdv_select_perimetre ON public.pdv FOR SELECT TO authenticated USING (((( SELECT public.role_actif_courant() AS role_actif_courant) = ANY (ARRAY['admin'::text, 'superviseur'::text])) OR (pdv_id IN ( SELECT public.pdv_ids_perimetre() AS pdv_ids_perimetre))));
CREATE POLICY pdv_update_admin ON public.pdv FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
CREATE POLICY pdv_update_terrain ON public.pdv FOR UPDATE USING (( SELECT public.peut_ecrire_terrain() AS peut_ecrire_terrain)) WITH CHECK (( SELECT public.peut_ecrire_terrain() AS peut_ecrire_terrain));
ALTER TABLE public.perfect_store_score_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.perfect_store_tier_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poids_reference ENABLE ROW LEVEL SECURITY;
CREATE POLICY poids_reference_authenticated_read ON public.poids_reference FOR SELECT TO authenticated USING (true);
CREATE POLICY poids_reference_manager_write ON public.poids_reference TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.pos_standard_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.position_tournee ENABLE ROW LEVEL SECURITY;
CREATE POLICY position_tournee_insert_own ON public.position_tournee FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));
CREATE POLICY position_tournee_select ON public.position_tournee FOR SELECT TO authenticated USING (((auth.uid() = user_id) OR public.est_gestionnaire_perfect_store()));
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY profiles_delete_admin ON public.profiles FOR DELETE USING ((( SELECT public.role_actif_courant() AS role_actif_courant) = 'admin'::text));
CREATE POLICY profiles_insert_admin ON public.profiles FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM public.profiles profiles_1
  WHERE ((profiles_1.id = auth.uid()) AND (profiles_1.role = 'admin'::text)))) OR (auth.uid() = id)));
CREATE POLICY profiles_select_authenticated ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY profiles_update_admin ON public.profiles FOR UPDATE USING ((( SELECT public.role_actif_courant() AS role_actif_courant) = 'admin'::text)) WITH CHECK ((( SELECT public.role_actif_courant() AS role_actif_courant) = 'admin'::text));
CREATE POLICY profiles_update_own ON public.profiles FOR UPDATE USING ((auth.uid() = id)) WITH CHECK (((auth.uid() = id) AND (role = ( SELECT p.role
   FROM public.profiles p
  WHERE (p.id = auth.uid()))) AND (is_active = ( SELECT p.is_active
   FROM public.profiles p
  WHERE (p.id = auth.uid()))) AND (NOT (zone_assignee IS DISTINCT FROM ( SELECT p.zone_assignee
   FROM public.profiles p
  WHERE (p.id = auth.uid())))) AND (NOT (territoires_assignes IS DISTINCT FROM ( SELECT p.territoires_assignes
   FROM public.profiles p
  WHERE (p.id = auth.uid())))) AND (NOT (quartiers_assignes IS DISTINCT FROM ( SELECT p.quartiers_assignes
   FROM public.profiles p
  WHERE (p.id = auth.uid())))) AND (NOT (commercial_id IS DISTINCT FROM ( SELECT p.commercial_id
   FROM public.profiles p
  WHERE (p.id = auth.uid())))) AND (NOT (email IS DISTINCT FROM ( SELECT p.email
   FROM public.profiles p
  WHERE (p.id = auth.uid()))))));
CREATE POLICY psm_read ON public.pos_standard_map FOR SELECT TO authenticated USING (true);
CREATE POLICY psm_write ON public.pos_standard_map USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
CREATE POLICY pssc_read ON public.perfect_store_score_config FOR SELECT TO authenticated USING (true);
CREATE POLICY pssc_write ON public.perfect_store_score_config USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
CREATE POLICY pstc_read ON public.perfect_store_tier_config FOR SELECT TO authenticated USING (true);
CREATE POLICY pstc_write ON public.perfect_store_tier_config USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
ALTER TABLE public.quartier ENABLE ROW LEVEL SECURITY;
CREATE POLICY quartier_authenticated_read ON public.quartier FOR SELECT TO authenticated USING (true);
CREATE POLICY quartier_manager_write ON public.quartier TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.reference_produit ENABLE ROW LEVEL SECURITY;
CREATE POLICY reference_produit_authenticated_read ON public.reference_produit FOR SELECT TO authenticated USING (true);
CREATE POLICY reference_produit_manager_write ON public.reference_produit TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.region ENABLE ROW LEVEL SECURITY;
CREATE POLICY region_authenticated_read ON public.region FOR SELECT TO authenticated USING (true);
CREATE POLICY region_manager_write ON public.region TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.resultat_perfect_store ENABLE ROW LEVEL SECURITY;
CREATE POLICY resultat_perfect_store_read ON public.resultat_perfect_store FOR SELECT TO authenticated USING (true);
ALTER TABLE public.role_section_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routing_data ENABLE ROW LEVEL SECURITY;
CREATE POLICY routing_exception_read ON public.routing_template_exception FOR SELECT TO authenticated USING (true);
CREATE POLICY routing_exception_write ON public.routing_template_exception TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY routing_manage_admin ON public.routing_data USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
ALTER TABLE public.routing_pdv ENABLE ROW LEVEL SECURITY;
CREATE POLICY routing_pdv_admin_policy ON public.routing_pdv USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
CREATE POLICY routing_pdv_user_read ON public.routing_pdv FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.routings
  WHERE ((routings.id = routing_pdv.routing_id) AND (routings.user_id = auth.uid())))));
CREATE POLICY routing_pdv_user_update ON public.routing_pdv FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.routings
  WHERE ((routings.id = routing_pdv.routing_id) AND (routings.user_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.routings
  WHERE ((routings.id = routing_pdv.routing_id) AND (routings.user_id = auth.uid())))));
CREATE POLICY routing_select ON public.routing_data FOR SELECT USING ((auth.role() = 'authenticated'::text));
ALTER TABLE public.routing_template_exception ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routing_template_pdv ENABLE ROW LEVEL SECURITY;
CREATE POLICY routing_template_pdv_admin_policy ON public.routing_template_pdv USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
CREATE POLICY routing_template_pdv_user_read ON public.routing_template_pdv FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.routing_templates
  WHERE ((routing_templates.id = routing_template_pdv.template_id) AND (routing_templates.user_id = auth.uid())))));
ALTER TABLE public.routing_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY routing_templates_admin_policy ON public.routing_templates USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
CREATE POLICY routing_templates_user_read ON public.routing_templates FOR SELECT USING ((user_id = auth.uid()));
ALTER TABLE public.routings ENABLE ROW LEVEL SECURITY;
CREATE POLICY routings_admin_policy ON public.routings USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
CREATE POLICY routings_user_read ON public.routings FOR SELECT USING ((user_id = auth.uid()));
CREATE POLICY routings_user_update ON public.routings FOR UPDATE USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));
CREATE POLICY rsa_admin_write ON public.role_section_access TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text) AND (profiles.is_active = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text) AND (profiles.is_active = true)))));
CREATE POLICY rsa_read ON public.role_section_access FOR SELECT TO authenticated USING (true);
ALTER TABLE public.sales_reps ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_reps_admin ON public.sales_reps USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
CREATE POLICY sales_reps_select ON public.sales_reps FOR SELECT USING ((auth.role() = 'authenticated'::text));
ALTER TABLE public.segment_grade_type_pdv ENABLE ROW LEVEL SECURITY;
CREATE POLICY segment_grade_type_pdv_authenticated_read ON public.segment_grade_type_pdv FOR SELECT TO authenticated USING (true);
CREATE POLICY segment_grade_type_pdv_manager_write ON public.segment_grade_type_pdv TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.segment_visibilite_type_pdv ENABLE ROW LEVEL SECURITY;
CREATE POLICY segment_visibilite_type_pdv_authenticated_read ON public.segment_visibilite_type_pdv FOR SELECT TO authenticated USING (true);
CREATE POLICY segment_visibilite_type_pdv_manager_write ON public.segment_visibilite_type_pdv TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
CREATE POLICY segment_visibilite_type_pdv_read ON public.segment_visibilite_type_pdv FOR SELECT TO authenticated USING (true);
ALTER TABLE public.seuil_disponibilite ENABLE ROW LEVEL SECURITY;
CREATE POLICY seuil_disponibilite_authenticated_read ON public.seuil_disponibilite FOR SELECT TO authenticated USING (true);
CREATE POLICY seuil_disponibilite_manager_write ON public.seuil_disponibilite TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.seuil_disponibilite_mt ENABLE ROW LEVEL SECURITY;
CREATE POLICY seuil_mt_read ON public.seuil_disponibilite_mt FOR SELECT TO authenticated USING (true);
CREATE POLICY seuil_mt_write ON public.seuil_disponibilite_mt USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
ALTER TABLE public.sku_thresholds ENABLE ROW LEVEL SECURITY;
CREATE POLICY sku_thresholds_read ON public.sku_thresholds FOR SELECT TO authenticated USING (true);
CREATE POLICY sku_thresholds_write ON public.sku_thresholds USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
ALTER TABLE public.sous_region ENABLE ROW LEVEL SECURITY;
CREATE POLICY sous_region_authenticated_read ON public.sous_region FOR SELECT TO authenticated USING (true);
CREATE POLICY sous_region_manager_write ON public.sous_region TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.standard_assortiment ENABLE ROW LEVEL SECURITY;
CREATE POLICY standard_assortiment_authenticated_read ON public.standard_assortiment FOR SELECT TO authenticated USING (true);
CREATE POLICY standard_assortiment_manager_write ON public.standard_assortiment TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.standard_visibilite ENABLE ROW LEVEL SECURITY;
CREATE POLICY standard_visibilite_authenticated_read ON public.standard_visibilite FOR SELECT TO authenticated USING (true);
CREATE POLICY standard_visibilite_manager_write ON public.standard_visibilite TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
CREATE POLICY standard_visibilite_read ON public.standard_visibilite FOR SELECT TO authenticated USING (true);
ALTER TABLE public.territoire ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.territoire_alias ENABLE ROW LEVEL SECURITY;
CREATE POLICY territoire_alias_read ON public.territoire_alias FOR SELECT TO authenticated USING (true);
CREATE POLICY territoire_alias_write ON public.territoire_alias TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
CREATE POLICY territoire_authenticated_read ON public.territoire FOR SELECT TO authenticated USING (true);
ALTER TABLE public.territoire_distributeur ENABLE ROW LEVEL SECURITY;
CREATE POLICY territoire_distributeur_authenticated_read ON public.territoire_distributeur FOR SELECT TO authenticated USING (true);
CREATE POLICY territoire_distributeur_manager_write ON public.territoire_distributeur TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
CREATE POLICY territoire_manager_write ON public.territoire TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.type_action_commerciale ENABLE ROW LEVEL SECURITY;
CREATE POLICY type_action_commerciale_read ON public.type_action_commerciale FOR SELECT TO authenticated USING (true);
CREATE POLICY type_action_commerciale_write ON public.type_action_commerciale TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.type_pdv ENABLE ROW LEVEL SECURITY;
CREATE POLICY type_pdv_authenticated_read ON public.type_pdv FOR SELECT TO authenticated USING (true);
CREATE POLICY type_pdv_manager_write ON public.type_pdv TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.version_app ENABLE ROW LEVEL SECURITY;
CREATE POLICY version_app_read ON public.version_app FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY version_app_write ON public.version_app TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
ALTER TABLE public.version_installee ENABLE ROW LEVEL SECURITY;
CREATE POLICY version_installee_insert_moi ON public.version_installee FOR INSERT TO authenticated WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));
CREATE POLICY version_installee_select ON public.version_installee FOR SELECT TO authenticated USING (((( SELECT auth.uid() AS uid) = user_id) OR (( SELECT public.role_actif_courant() AS role_actif_courant) = ANY (ARRAY['admin'::text, 'superviseur'::text]))));
CREATE POLICY version_installee_update_moi ON public.version_installee FOR UPDATE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));
CREATE POLICY vis_read ON public.visibility_standards FOR SELECT TO authenticated USING (true);
CREATE POLICY vis_write ON public.visibility_standards USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superviseur'::text]))))));
ALTER TABLE public.visibility_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visite_perfect_store ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visites ENABLE ROW LEVEL SECURITY;
CREATE POLICY visites_delete_admin ON public.visites FOR DELETE USING ((( SELECT public.role_actif_courant() AS role_actif_courant) = 'admin'::text));
CREATE POLICY visites_insert ON public.visites FOR INSERT WITH CHECK (((auth.uid() = user_id) AND public.peut_ecrire_terrain()));
CREATE POLICY visites_select ON public.visites FOR SELECT USING (((( SELECT auth.uid() AS uid) = user_id) OR (( SELECT public.role_actif_courant() AS role_actif_courant) = ANY (ARRAY['admin'::text, 'superviseur'::text]))));
CREATE POLICY visites_select_commercial ON public.visites FOR SELECT USING (((( SELECT public.role_actif_courant() AS role_actif_courant) = 'commercial'::text) AND (pdv_id IN ( SELECT public.pdv_ids_perimetre() AS pdv_ids_perimetre))));
CREATE POLICY visites_update ON public.visites FOR UPDATE USING ((( SELECT public.peut_ecrire_terrain() AS peut_ecrire_terrain) AND ((( SELECT auth.uid() AS uid) = user_id) OR (( SELECT public.role_actif_courant() AS role_actif_courant) = 'admin'::text)))) WITH CHECK ((( SELECT public.peut_ecrire_terrain() AS peut_ecrire_terrain) AND ((( SELECT auth.uid() AS uid) = user_id) OR (( SELECT public.role_actif_courant() AS role_actif_courant) = 'admin'::text))));
CREATE POLICY vps_read ON public.visite_perfect_store FOR SELECT TO authenticated USING (true);
CREATE POLICY vps_write ON public.visite_perfect_store TO authenticated USING (true) WITH CHECK (true);
ALTER TABLE public.zone ENABLE ROW LEVEL SECURITY;
CREATE POLICY zone_authenticated_read ON public.zone FOR SELECT TO authenticated USING (true);
ALTER TABLE public.zone_distributeur ENABLE ROW LEVEL SECURITY;
CREATE POLICY zone_distributeur_authenticated_read ON public.zone_distributeur FOR SELECT TO authenticated USING (true);
CREATE POLICY zone_distributeur_manager_write ON public.zone_distributeur TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
CREATE POLICY zone_manager_write ON public.zone TO authenticated USING (public.est_gestionnaire_perfect_store()) WITH CHECK (public.est_gestionnaire_perfect_store());
CREATE POLICY zones_manage_admin ON public.zones_secteurs USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
ALTER TABLE public.zones_secteurs ENABLE ROW LEVEL SECURITY;
CREATE POLICY zones_select ON public.zones_secteurs FOR SELECT USING ((auth.role() = 'authenticated'::text));
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;
GRANT USAGE ON SCHEMA stats TO authenticated;
GRANT USAGE ON SCHEMA stats TO service_role;
REVOKE ALL ON FUNCTION public.calculer_perfect_store(p_visite_id uuid, p_base_calcul text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.compter_visites_a_recalculer() TO authenticated;
REVOKE ALL ON FUNCTION public.compute_perfect_store(p_visite_id text, p_basis text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.est_gestionnaire_perfect_store() FROM PUBLIC;
GRANT ALL ON FUNCTION public.est_gestionnaire_perfect_store() TO authenticated;
REVOKE ALL ON FUNCTION public.geolocaliser_pdv(p_pdv_id text, p_lat double precision, p_lng double precision, p_precision integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.geolocaliser_pdv(p_pdv_id text, p_lat double precision, p_lng double precision, p_precision integer) TO authenticated;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.import_pdv_from_csv(p_pdv_id text, p_nom_pdv text, p_canal text, p_categorie_pdv text, p_sous_categorie_pdv text, p_autre_sous_categorie text, p_region text, p_zone text, p_secteur text, p_geolocation text, p_adressage text, p_image text, p_date text, p_ajoute_par text, p_jour_routing text, p_position_routing integer, p_canal_routing text, p_sales_rep_routing text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.import_visite_from_csv(p_data jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.import_zone_secteur(p_secteur_id integer, p_zone text, p_secteur text, p_merchandiser text, p_email text, p_sales_rep text, p_email_sales_rep text, p_region text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.maj_telephone_contact(p_id uuid, p_telephone text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.maj_telephone_contact(p_id uuid, p_telephone text) TO authenticated;
REVOKE ALL ON FUNCTION public.materialiser_routing_jour(p_user_id uuid, p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.materialiser_routing_jour(p_user_id uuid, p_date date) TO authenticated;
REVOKE ALL ON FUNCTION public.materialiser_routings_periode(p_user_id uuid, p_date_debut date, p_date_fin date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.materialiser_routings_periode(p_user_id uuid, p_date_debut date, p_date_fin date) TO authenticated;
REVOKE ALL ON FUNCTION public.notifier_action_assignee() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pdv_dans_perimetre(p_pdv_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pdv_dans_perimetre(p_pdv_id text) TO authenticated;
REVOKE ALL ON FUNCTION public.pdv_dans_perimetre_commercial(p_pdv_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pdv_dans_perimetre_commercial(p_pdv_id text) TO authenticated;
REVOKE ALL ON FUNCTION public.pdv_ids_perimetre() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pdv_ids_perimetre() TO authenticated;
GRANT ALL ON FUNCTION public.perfect_store_manques_filtre(p_division text, p_territoire text, p_area text, p_distributeur text, p_date_debut date, p_date_fin date, p_limit integer) TO authenticated;
REVOKE ALL ON FUNCTION public.peut_ecrire_terrain() FROM PUBLIC;
GRANT ALL ON FUNCTION public.peut_ecrire_terrain() TO authenticated;
REVOKE ALL ON FUNCTION public.prevent_profile_privilege_escalation() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.recalculer_perfect_store_lot(p_limit integer, p_offset integer, p_base_calcul text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.recalculer_perfect_store_lot(p_limit integer, p_offset integer, p_base_calcul text) TO authenticated;
REVOKE ALL ON FUNCTION public.recalculer_tous_perfect_store(p_base_calcul text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.recalculer_tous_perfect_store(p_base_calcul text) TO authenticated;
REVOKE ALL ON FUNCTION public.refresh_stats_dashboard() FROM PUBLIC;
GRANT ALL ON FUNCTION public.refresh_stats_dashboard() TO authenticated;
GRANT ALL ON FUNCTION public.refresh_stats_dashboard() TO service_role;
REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.role_actif_courant() FROM PUBLIC;
GRANT ALL ON FUNCTION public.role_actif_courant() TO authenticated;
GRANT ALL ON FUNCTION public.routing_regles_du_jour(p_user_id uuid, p_date date) TO authenticated;
GRANT ALL ON FUNCTION public.transferer_field_coaching(p_coaching_id uuid, p_vers uuid, p_motif text) TO authenticated;
REVOKE ALL ON FUNCTION public.visites_garde_statut() FROM PUBLIC;
GRANT SELECT ON TABLE stats.mv_distribution_pdv TO authenticated;
GRANT SELECT ON TABLE stats.mv_distribution_pdv TO service_role;
GRANT SELECT ON TABLE public.v_distribution_pdv TO authenticated;
GRANT SELECT ON TABLE public.v_distribution_pdv TO service_role;
GRANT SELECT ON TABLE public.v_perfect_store_liste TO authenticated;
GRANT SELECT ON TABLE public.v_perfect_store_liste_full TO authenticated;
GRANT SELECT ON TABLE stats.mv_performance_commerciaux TO authenticated;
GRANT SELECT ON TABLE stats.mv_performance_commerciaux TO service_role;
GRANT SELECT ON TABLE public.v_performance_commerciaux TO authenticated;
GRANT SELECT ON TABLE public.v_performance_commerciaux TO service_role;
GRANT SELECT ON TABLE stats.mv_stats_visites TO authenticated;
GRANT SELECT ON TABLE stats.mv_stats_visites TO service_role;
GRANT SELECT ON TABLE public.v_stats_visites TO authenticated;
GRANT SELECT ON TABLE public.v_stats_visites TO service_role;
GRANT SELECT ON TABLE stats.mv_visites_par_jour TO authenticated;
GRANT SELECT ON TABLE stats.mv_visites_par_jour TO service_role;
GRANT SELECT ON TABLE public.v_visites_par_jour TO authenticated;
GRANT SELECT ON TABLE public.v_visites_par_jour TO service_role;
GRANT SELECT ON TABLE public.version_app TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.version_app TO authenticated;
GRANT SELECT,INSERT,UPDATE ON TABLE public.version_installee TO authenticated;
REFRESH MATERIALIZED VIEW stats.mv_distribution_pdv;
REFRESH MATERIALIZED VIEW stats.mv_performance_commerciaux;
REFRESH MATERIALIZED VIEW stats.mv_stats_visites;
REFRESH MATERIALIZED VIEW stats.mv_visites_par_jour;
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
