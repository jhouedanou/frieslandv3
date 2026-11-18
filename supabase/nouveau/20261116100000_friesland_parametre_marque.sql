-- ============================================================================
-- Personnalisation de la marque : nom, sous-titre, logo et couleurs affichés
-- par l'application. Une seule ligne (id = 1), réglée par un administrateur
-- depuis Paramètres > Personnalisation.
--
-- Lecture ouverte à tous, y compris sans connexion : l'écran de connexion
-- affiche déjà le nom, le logo et les couleurs. La ligne ne contient rien de
-- confidentiel. Écriture : administrateurs seulement.
-- Rejouable sans effet.
-- ============================================================================
begin;

create table if not exists public.parametre_marque (
  id                 smallint primary key default 1 check (id = 1),
  nom                text not null default 'Big Five Force' check (char_length(nom) between 1 and 40),
  sous_titre         text check (sous_titre is null or char_length(sous_titre) <= 60),
  -- Image en « data:image/… », redimensionnée par l'écran avant envoi.
  logo_url           text check (logo_url is null or (logo_url like 'data:image/%' and char_length(logo_url) <= 400000)),
  couleur_principale text not null default '#603080' check (couleur_principale ~ '^#[0-9A-Fa-f]{6}$'),
  couleur_secondaire text not null default '#403080' check (couleur_secondaire ~ '^#[0-9A-Fa-f]{6}$'),
  maj_le             timestamptz not null default now()
);

comment on table public.parametre_marque is
  'Marque affichée par l''application (nom, logo, couleurs). Une seule ligne, id = 1.';

insert into public.parametre_marque (id, sous_titre)
values (1, 'La force de vente maîtrisée')
on conflict (id) do nothing;

alter table public.parametre_marque enable row level security;

drop policy if exists parametre_marque_lecture on public.parametre_marque;
create policy parametre_marque_lecture on public.parametre_marque
  for select to anon, authenticated using (true);

drop policy if exists parametre_marque_ecriture on public.parametre_marque;
create policy parametre_marque_ecriture on public.parametre_marque
  for all to authenticated
  using ((select public.role_actif_courant()) = 'admin')
  with check ((select public.role_actif_courant()) = 'admin');

revoke all on public.parametre_marque from anon, authenticated;
grant select on public.parametre_marque to anon, authenticated;
grant insert, update on public.parametre_marque to authenticated;

commit;
