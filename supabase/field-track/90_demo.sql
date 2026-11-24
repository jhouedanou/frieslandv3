-- ============================================================================
-- Big Five Force — données de démonstration (marque blanche)
--   15 points de vente fictifs, 15 visites (une par PDV), équipes fictives,
--   découpage territorial générique (6 territoires).
--
-- À jouer sur une base Big Five Force NEUVE uniquement :
--   1. schéma (supabase/_archive + 00_prelude.sql + supabase/nouveau) ;
--   2. comptes (scripts/field-track-create-accounts.mjs) ;
--   3. ce fichier.
-- ⚠️ Il VIDE visites, pdv, tournées, REMPLACE le découpage territorial et
--    rebaptise les référentiels (produits, distributeurs, marques concurrentes). Ne jamais le jouer sur une base client.
-- Rejouable : même résultat à chaque passage.
-- ============================================================================
begin;

-- Garde-fous : base de démonstration, comptes déjà créés.
do $$
declare n int;
begin
  select count(*) into n from public.profiles where email like '%@bigfiveforce.demo';
  if n < 9 then
    raise exception 'Comptes Big Five Force absents (% trouvés, 9 attendus) : lancer d''abord scripts/field-track-create-accounts.mjs', n;
  end if;
  select count(*) into n from public.profiles where email not like '%@bigfiveforce.demo';
  if n > 0 then
    raise exception 'Cette base contient % compte(s) hors @bigfiveforce.demo : ce n''est pas une base de démonstration, arrêt.', n;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 1. Référentiels rebaptisés : plus aucun nom du client d'origine.
--    Les clés techniques (br_160g, maison_br…) restent : le calcul en dépend.
-- ----------------------------------------------------------------------------
update public.reference_produit set nom =
  replace(regexp_replace(regexp_replace(nom, '\mBRB\M', 'FTB', 'g'), '\mBR\M', 'FT', 'g'), 'Pearl', 'Opale')
where nom ~ '\m(BR|BRB)\M|Pearl';

update public.element_visibilite set nom = regexp_replace(nom, '\mBR\M', 'FT', 'g') where nom ~ '\mBR\M';

-- Gammes de produits : libellés génériques (les codes evap / imp / scm restent).
update public.categorie_produit set nom = v.nom
from (values ('EVAP', 'Gamme A'), ('IMP', 'Gamme B'), ('SCM', 'Gamme C')) as v(code, nom)
where categorie_produit.code = v.code;

update public.categorie_releve set libelle = v.libelle
from (values ('evap', 'Gamme A'), ('imp', 'Gamme B'), ('scm', 'Gamme C'), ('uht', 'Gamme D'), ('yaourt', 'Gamme E'), ('cereales', 'Gamme F')) as v(code, libelle)
where categorie_releve.code = v.code;

-- Distributeurs : noms fictifs, identifiants conservés (liens territoire intacts).
update public.distributeur set nom = 'Distributeur ' || lpad(id::text, 2, '0') where nom not like 'Distributeur __';

-- Marques concurrentes : une lettre par marque (même code = même lettre).
with lettres as (
  select code, chr(64 + dense_rank() over (order by code)::int) as lettre
  from (select distinct code from public.marque_concurrente) c
)
update public.marque_concurrente_sku s
set libelle = 'Concurrent ' || l.lettre || coalesce(' ' || s.grammage_g || 'g', '')
from public.marque_concurrente m join lettres l on l.code = m.code
where s.marque_id = m.id and s.libelle not like 'Concurrent %';

with lettres as (
  select code, chr(64 + dense_rank() over (order by code)::int) as lettre
  from (select distinct code from public.marque_concurrente) c
)
update public.marque_concurrente m set nom = 'Concurrent ' || l.lettre
from lettres l where l.code = m.code and m.nom not like 'Concurrent %';

-- ----------------------------------------------------------------------------
-- 2. Remise à zéro des données de terrain.
-- ----------------------------------------------------------------------------
delete from public.field_coaching;
delete from public.action_commerciale;
delete from public.position_tournee;
delete from public.routing_pdv;
delete from public.routings;
delete from public.routing_template_pdv;
delete from public.routing_templates;
delete from public.visites;
delete from public.pdv;
delete from public.zones_secteurs;
delete from public.routing_data;
delete from public.sales_reps;

-- ----------------------------------------------------------------------------
-- 2 bis. Découpage territorial générique : il remplace celui du client d'origine
--        (régions, territoires, zones, quartiers, rattachement des distributeurs).
-- ----------------------------------------------------------------------------
delete from public.territoire_alias;
delete from public.zone_distributeur;
delete from public.territoire_distributeur;
delete from public.quartier;
delete from public.zone;
delete from public.territoire;
delete from public.sous_region;
delete from public.region;
delete from public.distributeur where id not in (select id from public.distributeur order by id limit 6);
update public.distributeur d set nom = 'Distributeur ' || lpad(r.rang::text, 2, '0')
from (select id, row_number() over (order by id) as rang from public.distributeur) r where r.id = d.id;

insert into public.region(code, nom, nom_affichage, pays_code)
select v.code, v.nom, v.nom, (select code from public.pays order by id limit 1)
from (values ('SUD', 'Région Sud'), ('NORD', 'Région Nord')) as v(code, nom);

insert into public.sous_region(code, nom, nom_affichage, region_code) values
  ('SUD-1', 'Secteur Sud 1', 'Sud 1', 'SUD'),
  ('NORD-1', 'Secteur Nord 1', 'Nord 1', 'NORD');

insert into public.territoire(code, nom, sous_region_code) values
  ('T-EST', 'Territoire Est', 'SUD-1'),
  ('T-CEN', 'Territoire Centre', 'SUD-1'),
  ('T-SUD', 'Territoire Sud', 'SUD-1'),
  ('T-LAG', 'Territoire Lagune', 'SUD-1'),
  ('T-OUE', 'Territoire Ouest', 'SUD-1'),
  ('T-NOR', 'Territoire Nord', 'NORD-1');

-- Une zone par territoire, trois quartiers par zone.
insert into public.zone(code, nom, territoire_code)
select replace(code, 'T-', 'Z-'), replace(nom, 'Territoire', 'Zone'), code from public.territoire order by id;

insert into public.quartier(zone_id, nom, ordre)
select z.id, replace(z.nom, 'Zone', 'Quartier') || ' ' || n, n
from public.zone z cross join generate_series(1, 3) as n
order by z.id, n;

-- Un distributeur par territoire, dans l'ordre.
insert into public.territoire_distributeur(territoire_id, distributeur_id)
select t.id, d.id
from (select id, row_number() over (order by id) as rang from public.territoire) t
join (select id, row_number() over (order by id) as rang from public.distributeur) d using (rang);

insert into public.zone_distributeur(zone_id, distributeur_id)
select z.id, td.distributeur_id
from public.zone z
join public.territoire t on t.code = z.territoire_code
join public.territoire_distributeur td on td.territoire_id = t.id;

-- ----------------------------------------------------------------------------
-- 3. Équipes : chaque commercial encadre ses merchandisers, par territoire.
-- ----------------------------------------------------------------------------
update public.profiles p set
  zone_assignee = v.zone, territoires_assignes = to_jsonb(v.territoires), quartiers_assignes = '[]'::jsonb, region = 'Région Sud',
  commercial_id = (select c.id from public.profiles c where c.email = v.chef)
from (values
  ('commercial1@bigfiveforce.demo',   'Territoire Est',    array['Territoire Est','Territoire Centre'],      null),
  ('commercial2@bigfiveforce.demo',   'Territoire Sud',     array['Territoire Sud','Territoire Lagune'],   null),
  ('commercial3@bigfiveforce.demo',   'Territoire Ouest',  array['Territoire Ouest'],              null),
  ('merchandiser1@bigfiveforce.demo', 'Territoire Est',    array['Territoire Est'],    'commercial1@bigfiveforce.demo'),
  ('merchandiser2@bigfiveforce.demo', 'Territoire Centre',     array['Territoire Centre'],     'commercial1@bigfiveforce.demo'),
  ('merchandiser3@bigfiveforce.demo', 'Territoire Sud',     array['Territoire Sud'],     'commercial2@bigfiveforce.demo'),
  ('merchandiser4@bigfiveforce.demo', 'Territoire Lagune', array['Territoire Lagune'], 'commercial2@bigfiveforce.demo'),
  ('merchandiser5@bigfiveforce.demo', 'Territoire Ouest',  array['Territoire Ouest'],  'commercial3@bigfiveforce.demo')
) as v(email, zone, territoires, chef)
where p.email = v.email;

insert into public.sales_reps(nom)
select nom from public.profiles where role = 'commercial' order by email;

-- ----------------------------------------------------------------------------
-- 4. Les 15 points de vente.
-- ----------------------------------------------------------------------------
insert into public.pdv(pdv_id, nom_pdv, canal, categorie_pdv, sous_categorie_pdv, region, zone, territory_code,
                       quartier, geolocation_lat, geolocation_lng, rayon_geofence, adressage, objectif_perfect_store,
                       gps_source, ajoute_par, is_active)
values
  ('FT-001','Boutique Le Baobab','General trade','Point de vente détail','Boutique A','Région Sud','Territoire Est','T-EST',
   'Quartier Est 1',5.3697,-3.959,200,'Rue du Marché, face à la pharmacie','FLAGSHIP','admin','admin@bigfiveforce.demo',true),
  ('FT-002','Superette Les Flamboyants','General trade','Point de vente détail','Superettes A','Région Sud','Territoire Est','T-EST',
   'Quartier Est 2',5.3581,-3.9712,200,'Avenue des Jardins, près du rond-point','FLAGSHIP','admin','admin@bigfiveforce.demo',true),
  ('FT-003','Supermarché Horizon','Modern trade','Point de vente détail','Supermarket A','Région Sud','Territoire Est','T-EST',
   'Quartier Est 3',5.3452,-4.0018,200,'Boulevard principal, galerie commerciale','FLAGSHIP','admin','admin@bigfiveforce.demo',true),
  ('FT-004','Boutique Chez Tantie Rose','General trade','Point de vente détail','Boutique B','Région Sud','Territoire Sud','T-SUD',
   'Quartier Sud 1',5.3011,-3.9921,200,'Rue du Canal, à côté de la boulangerie','VIP','admin','admin@bigfiveforce.demo',true),
  ('FT-005','Boutique La Confiance','General trade','Point de vente détail','Boutique B','Région Sud','Territoire Sud','T-SUD',
   'Quartier Sud 2',5.3062,-3.9853,200,'Place du marché, allée centrale','VIP','admin','admin@bigfiveforce.demo',true),
  ('FT-006','Boutique Le Bon Coin','General trade','Point de vente détail','Boutique B','Région Sud','Territoire Sud','T-SUD',
   'Quartier Sud 3',5.2987,-3.9802,200,'Résidence des Fleurs, entrée principale','VIP','admin','admin@bigfiveforce.demo',true),
  ('FT-007','Boutique Le Palmier','General trade','Point de vente détail','Boutique C','Région Sud','Territoire Centre','T-CEN',
   'Quartier Centre 1',5.3231,-4.0203,200,'Avenue du Commerce, immeuble Les Arcades','CORE','admin','admin@bigfiveforce.demo',true),
  ('FT-008','Boutique Étoile du Matin','General trade','Point de vente détail','Boutique C','Région Sud','Territoire Centre','T-CEN',
   'Quartier Centre 2',5.3274,-4.0171,200,'Cité administrative, bloc B','CORE','admin','admin@bigfiveforce.demo',true),
  ('FT-009','Boutique Aux Trois Frères','General trade','Point de vente détail','Boutique C','Région Sud','Territoire Centre','T-CEN',
   'Quartier Centre 3',5.3302,-4.0236,200,'Marché central, rangée 2','CORE','admin','admin@bigfiveforce.demo',true),
  ('FT-010','Boutique La Lagune','General trade','Point de vente détail','Boutique C','Région Sud','Territoire Lagune','T-LAG',
   'Quartier Lagune 1',5.2952,-4.0021,200,'Rue des Pêcheurs, près du quai','CORE','admin','admin@bigfiveforce.demo',true),
  ('FT-011','Kiosque du Carrefour','General trade','Point de vente détail','Kiosk A','Région Sud','Territoire Lagune','T-LAG',
   'Quartier Lagune 2',5.3003,-4.0082,200,'Carrefour de la gare','BASIC','admin','admin@bigfiveforce.demo',true),
  ('FT-012','Kiosque Le Rendez-vous','General trade','Point de vente détail','Kiosk A','Région Sud','Territoire Lagune','T-LAG',
   'Quartier Lagune 3',5.3051,-4.0043,200,'Rue de l''École, face à l''école primaire','BASIC','admin','admin@bigfiveforce.demo',true),
  ('FT-013','Boutique Petit Marché','General trade','Point de vente détail','Boutique C','Région Sud','Territoire Ouest','T-OUE',
   'Quartier Ouest 1',5.3412,-4.0703,200,'Rue du Terminus','CORE','admin','admin@bigfiveforce.demo',true),
  ('FT-014','Supermarché Bel Air','Modern trade','Point de vente détail','Supermarket C','Région Sud','Territoire Ouest','T-OUE',
   'Quartier Ouest 2',5.3361,-4.0781,200,'Boulevard de l''Ouest','CORE','admin','admin@bigfiveforce.demo',true),
  ('FT-015','Boutique du Rond-Point','General trade','Point de vente détail','Boutique B','Région Sud','Territoire Ouest','T-OUE',
   'Quartier Ouest 3',5.3304,-4.0852,200,'Derrière la station-service','VIP','admin','admin@bigfiveforce.demo',true);

-- Distributeur : celui du territoire (le premier, par nom).
update public.pdv p set distributor_name = (
  select d.nom from public.territoire t
  join public.territoire_distributeur td on td.territoire_id = t.id
  join public.distributeur d on d.id = td.distributeur_id
  where t.code = p.territory_code order by d.nom limit 1);

-- Référentiel zone / quartier / équipe lu par l'application mobile.
insert into public.zones_secteurs(zone, secteur, merchandiser, email_merchandiser, sales_rep, email_sales_rep, region)
select p.zone, p.quartier, m.nom, m.email, c.nom, c.email, 'Région Sud'
from public.pdv p
join public.profiles m on m.role = 'merchandiser' and m.zone_assignee = p.zone
join public.profiles c on c.id = m.commercial_id
order by p.pdv_id;

-- ----------------------------------------------------------------------------
-- 5. Les 15 visites : une par PDV, par le merchandiser du territoire, étalées
--    sur les 12 derniers jours (jamais aujourd'hui : aucune date future). Les relevés couvrent tous les niveaux Perfect
--    Store : 3 Flagship, 3 VIP, 4 Core et 5 PDV sous le niveau Core.
-- ----------------------------------------------------------------------------
insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-001','FT-001', u.id, date_trunc('day', now()) - interval '1 days' + interval '10 hours 7 minutes',
       u.nom, u.email, 5.3698, -3.9591, true, 6,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('br_gold',999,'br_160g',999,'brb_160g',999,'br_400g',999,'brb_400g',999,'pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object('br_20g',999,'brd_15g',999,'br_375g',999,'br_900g',999,'br_2_5kg',999,'brd_350g',999,'br_400g',999)),'scm',jsonb_build_object('quantites',jsonb_build_object('br_1kg',999,'pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',true,'standards',jsonb_build_object('affiche',true,'fleche',true,'guirlande',true,'sign_board',true,'panneau_privilege',true,'full_branding',true,'reglette',true,'maison_br',true,'hanger',true,'wobler',true,'presentoir',true,'tg',true,'plaque_br',true,'merchandising',true,'standard',true,'hotesses',true,'degustation',true))),
  'synced'
from public.profiles u where u.email = 'merchandiser1@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-002','FT-002', u.id, date_trunc('day', now()) - interval '2 days' + interval '11 hours 14 minutes',
       u.nom, u.email, 5.3582, -3.9713, true, 7,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('br_gold',999,'br_160g',999,'brb_160g',999,'br_400g',999,'brb_400g',999,'pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object('br_20g',999,'brd_15g',999,'br_375g',999,'br_900g',999,'br_2_5kg',999,'brd_350g',999,'br_400g',999)),'scm',jsonb_build_object('quantites',jsonb_build_object('br_1kg',999,'pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',true,'standards',jsonb_build_object('affiche',true,'fleche',true,'sign_board',true,'panneau_privilege',true,'reglette',true,'espace_br',true,'wobler',true,'presentoir',true,'tg',true,'plaque_br',true,'merchandising',true,'standard',true,'hotesses',true,'degustation',true))),
  'synced'
from public.profiles u where u.email = 'merchandiser1@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-003','FT-003', u.id, date_trunc('day', now()) - interval '3 days' + interval '12 hours 21 minutes',
       u.nom, u.email, 5.3453, -4.0019, true, 8,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('br_gold',999,'br_160g',999,'brb_160g',999,'br_400g',999,'brb_400g',999,'pearl_400g',999),'facings',jsonb_build_object('br_gold',999,'br_160g',999,'brb_160g',999,'br_400g',999,'brb_400g',999,'pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object('br_20g',999,'brd_15g',999,'br_375g',999,'br_900g',999,'br_2_5kg',999,'brd_350g',999,'br_400g',999),'facings',jsonb_build_object('br_20g',999,'brd_15g',999,'br_375g',999,'br_900g',999,'br_2_5kg',999,'brd_350g',999,'br_400g',999)),'scm',jsonb_build_object('quantites',jsonb_build_object('br_1kg',999,'pearl_1kg',999),'facings',jsonb_build_object('br_1kg',999,'pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',true,'standards',jsonb_build_object('niche',true,'wobler',true,'top_shelf',true,'bacs',true,'reglette',true,'tg',true,'plot',true,'hotesses',true))),
  'synced'
from public.profiles u where u.email = 'merchandiser1@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-004','FT-004', u.id, date_trunc('day', now()) - interval '2 days' + interval '13 hours 28 minutes',
       u.nom, u.email, 5.3012, -3.9922, true, 9,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('br_gold',999,'br_160g',999,'brb_160g',999,'br_400g',999,'brb_400g',999,'pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object('br_20g',999,'brd_15g',999,'br_375g',999,'br_900g',999,'br_2_5kg',999,'brd_350g',999,'br_400g',999)),'scm',jsonb_build_object('quantites',jsonb_build_object('br_1kg',999,'pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',true,'standards',jsonb_build_object('affiche',true,'fleche',true,'guirlande',true,'sign_board',true,'panneau_privilege',true,'full_branding',false,'reglette',true,'maison_br',true,'hanger',true,'wobler',true,'presentoir',true,'tg',true,'plaque_br',false,'merchandising',true,'standard',true,'hotesses',true,'degustation',true))),
  'synced'
from public.profiles u where u.email = 'merchandiser3@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-005','FT-005', u.id, date_trunc('day', now()) - interval '4 days' + interval '14 hours 35 minutes',
       u.nom, u.email, 5.3063, -3.9854, true, 5,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('br_gold',999,'br_160g',999,'brb_160g',999,'br_400g',999,'brb_400g',999,'pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object('br_20g',999,'brd_15g',999,'br_375g',999,'br_900g',999,'br_2_5kg',999,'brd_350g',999,'br_400g',999)),'scm',jsonb_build_object('quantites',jsonb_build_object('br_1kg',999,'pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',true,'standards',jsonb_build_object('affiche',true,'fleche',true,'guirlande',true,'sign_board',true,'panneau_privilege',true,'full_branding',false,'reglette',true,'maison_br',true,'hanger',true,'wobler',true,'presentoir',true,'tg',true,'plaque_br',false,'merchandising',true,'standard',true,'hotesses',true,'degustation',true))),
  'synced'
from public.profiles u where u.email = 'merchandiser3@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-006','FT-006', u.id, date_trunc('day', now()) - interval '5 days' + interval '15 hours 42 minutes',
       u.nom, u.email, 5.2988, -3.9803, true, 6,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('br_gold',999,'br_160g',999,'brb_160g',999,'br_400g',999,'brb_400g',999,'pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object('br_20g',999,'brd_15g',999,'br_375g',999,'br_900g',999,'br_2_5kg',999,'brd_350g',999,'br_400g',999)),'scm',jsonb_build_object('quantites',jsonb_build_object('br_1kg',999,'pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',true,'standards',jsonb_build_object('affiche',true,'fleche',true,'guirlande',true,'sign_board',true,'panneau_privilege',true,'full_branding',false,'reglette',true,'maison_br',true,'hanger',true,'wobler',true,'presentoir',true,'tg',true,'plaque_br',false,'merchandising',true,'standard',true,'hotesses',true,'degustation',true))),
  'synced'
from public.profiles u where u.email = 'merchandiser3@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-007','FT-007', u.id, date_trunc('day', now()) - interval '3 days' + interval '9 hours 49 minutes',
       u.nom, u.email, 5.3232, -4.0204, true, 7,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('br_gold',999,'br_160g',999,'brb_160g',999,'br_400g',999,'brb_400g',999,'pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object('br_20g',999,'brd_15g',999,'br_375g',999,'br_900g',999,'br_2_5kg',999,'brd_350g',999,'br_400g',999)),'scm',jsonb_build_object('quantites',jsonb_build_object('br_1kg',999,'pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',false,'standards',jsonb_build_object('affiche',true,'fleche',true,'guirlande',true,'sign_board',true,'panneau_privilege',false,'full_branding',false,'reglette',true,'maison_br',true,'hanger',true,'wobler',true,'presentoir',false,'tg',false,'plaque_br',false,'merchandising',true,'standard',true,'hotesses',false,'degustation',false))),
  'synced'
from public.profiles u where u.email = 'merchandiser2@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-008','FT-008', u.id, date_trunc('day', now()) - interval '6 days' + interval '10 hours 56 minutes',
       u.nom, u.email, 5.3275, -4.0172, true, 8,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('br_gold',999,'br_160g',999,'brb_160g',999,'br_400g',999,'brb_400g',999,'pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object('br_20g',999,'brd_15g',999,'br_375g',999,'br_900g',999,'br_2_5kg',999,'brd_350g',999,'br_400g',999)),'scm',jsonb_build_object('quantites',jsonb_build_object('br_1kg',999,'pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',false,'standards',jsonb_build_object('affiche',true,'fleche',true,'guirlande',true,'sign_board',true,'panneau_privilege',false,'full_branding',false,'reglette',true,'maison_br',true,'hanger',true,'wobler',true,'presentoir',false,'tg',false,'plaque_br',false,'merchandising',true,'standard',true,'hotesses',false,'degustation',false))),
  'synced'
from public.profiles u where u.email = 'merchandiser2@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-009','FT-009', u.id, date_trunc('day', now()) - interval '7 days' + interval '11 hours 3 minutes',
       u.nom, u.email, 5.3303, -4.0237, true, 9,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('br_gold',999,'br_160g',999,'brb_160g',999,'br_400g',999,'brb_400g',999,'pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object('br_20g',999,'brd_15g',999,'br_375g',999,'br_900g',999,'br_2_5kg',999,'brd_350g',999,'br_400g',999)),'scm',jsonb_build_object('quantites',jsonb_build_object('br_1kg',999,'pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',false,'standards',jsonb_build_object('affiche',true,'fleche',true,'guirlande',true,'sign_board',true,'panneau_privilege',false,'full_branding',false,'reglette',true,'maison_br',true,'hanger',true,'wobler',true,'presentoir',false,'tg',false,'plaque_br',false,'merchandising',true,'standard',true,'hotesses',false,'degustation',false))),
  'synced'
from public.profiles u where u.email = 'merchandiser2@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-010','FT-010', u.id, date_trunc('day', now()) - interval '4 days' + interval '12 hours 10 minutes',
       u.nom, u.email, 5.2953, -4.0022, true, 5,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('br_gold',999,'br_160g',999,'brb_160g',999,'br_400g',999,'brb_400g',999,'pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object('br_20g',999,'brd_15g',999,'br_375g',999,'br_900g',999,'br_2_5kg',999,'brd_350g',999,'br_400g',999)),'scm',jsonb_build_object('quantites',jsonb_build_object('br_1kg',999,'pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',false,'standards',jsonb_build_object('affiche',true,'fleche',true,'guirlande',true,'sign_board',true,'panneau_privilege',false,'full_branding',false,'reglette',true,'maison_br',true,'hanger',true,'wobler',true,'presentoir',false,'tg',false,'plaque_br',false,'merchandising',true,'standard',true,'hotesses',false,'degustation',false))),
  'synced'
from public.profiles u where u.email = 'merchandiser4@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-011','FT-011', u.id, date_trunc('day', now()) - interval '8 days' + interval '13 hours 17 minutes',
       u.nom, u.email, 5.3004, -4.0083, true, 6,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object()),'scm',jsonb_build_object('quantites',jsonb_build_object('pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',false,'standards',jsonb_build_object('affiche',false,'thermos',false,'verre',false,'carafe',false,'maison_br',false,'chasuble',false,'full_branding',false,'promotion',false))),
  'synced'
from public.profiles u where u.email = 'merchandiser4@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-012','FT-012', u.id, date_trunc('day', now()) - interval '9 days' + interval '14 hours 24 minutes',
       u.nom, u.email, 5.3052, -4.0044, true, 7,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('pearl_400g',999)),'imp',jsonb_build_object('quantites',jsonb_build_object()),'scm',jsonb_build_object('quantites',jsonb_build_object('pearl_1kg',999))),
    'visibilite', jsonb_build_object('promotion_applicable',false,'standards',jsonb_build_object('affiche',false,'thermos',false,'verre',false,'carafe',false,'maison_br',false,'chasuble',false,'full_branding',false,'promotion',false))),
  'synced'
from public.profiles u where u.email = 'merchandiser4@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-013','FT-013', u.id, date_trunc('day', now()) - interval '6 days' + interval '15 hours 31 minutes',
       u.nom, u.email, 5.3413, -4.0704, true, 8,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object()),'imp',jsonb_build_object('quantites',jsonb_build_object()),'scm',jsonb_build_object('quantites',jsonb_build_object())),
    'visibilite', jsonb_build_object('promotion_applicable',false,'standards',jsonb_build_object('affiche',false,'fleche',false,'guirlande',false,'sign_board',false,'panneau_privilege',false,'full_branding',false,'reglette',false,'maison_br',false,'hanger',false,'wobler',false,'presentoir',false,'tg',false,'plaque_br',false,'merchandising',false,'standard',false,'hotesses',false,'degustation',false))),
  'synced'
from public.profiles u where u.email = 'merchandiser5@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-014','FT-014', u.id, date_trunc('day', now()) - interval '10 days' + interval '9 hours 38 minutes',
       u.nom, u.email, 5.3362, -4.0782, true, 9,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object()),'imp',jsonb_build_object('quantites',jsonb_build_object()),'scm',jsonb_build_object('quantites',jsonb_build_object())),
    'visibilite', jsonb_build_object('promotion_applicable',false,'standards',jsonb_build_object('affiche',false,'fleche',false,'sign_board',false,'panneau_privilege',false,'reglette',false,'espace_br',false,'wobler',false,'presentoir',false,'tg',false,'plaque_br',false,'merchandising',false,'standard',false,'hotesses',false,'degustation',false))),
  'synced'
from public.profiles u where u.email = 'merchandiser5@bigfiveforce.demo';

insert into public.visites(visite_id, pdv_id, user_id, date_visite, commercial, email, geolocation_lat, geolocation_lng,
                           geofence_validated, precision_gps, data, sync_status)
select 'FT-VIS-015','FT-015', u.id, date_trunc('day', now()) - interval '12 days' + interval '10 hours 45 minutes',
       u.nom, u.email, 5.3305, -4.0853, true, 5,
  jsonb_build_object('produits', jsonb_build_object('evap',jsonb_build_object('quantites',jsonb_build_object('br_160g',2,'br_400g',2)),'imp',jsonb_build_object('quantites',jsonb_build_object('br_20g',2)),'scm',jsonb_build_object('quantites',jsonb_build_object())),
    'visibilite', jsonb_build_object('promotion_applicable',false,'standards',jsonb_build_object('affiche',true,'fleche',false,'guirlande',false,'sign_board',false,'panneau_privilege',false,'full_branding',false,'reglette',true,'maison_br',false,'hanger',false,'wobler',false,'presentoir',false,'tg',false,'plaque_br',false,'merchandising',false,'standard',false,'hotesses',false,'degustation',false))),
  'synced'
from public.profiles u where u.email = 'merchandiser5@bigfiveforce.demo';

-- Le déclencheur a déjà calculé les scores à l'insertion ; on garantit l'état final.
do $$ begin perform public.calculer_perfect_store(id, 'taux_vente') from public.visites; end $$;

commit;
