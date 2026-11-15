// demo/db.ts
// Mode démo : ouvre la base embarquée (PGlite = PostgreSQL compilé pour le
// navigateur) et y charge demo/seed.sql au premier lancement. Les données
// restent ensuite sur l'appareil (IndexedDB) jusqu'à une réinitialisation.
import { PGlite } from '@electric-sql/pglite'
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm'
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto'
import { unaccent } from '@electric-sql/pglite/contrib/unaccent'
import { uuid_ossp } from '@electric-sql/pglite/contrib/uuid_ossp'

const PREFIXE = 'field-track-demo'

/** Version des données : change dès que demo/seed.sql change. */
export function versionSeed(seed: string): string {
  let h = 0
  for (let i = 0; i < seed.length; i += 97) h = (h * 31 + seed.charCodeAt(i)) | 0
  return `${seed.length}-${(h >>> 0).toString(36)}`
}

/**
 * @param seed     contenu de demo/seed.sql
 * @param stockage `idb` (navigateur, données conservées) ou `memoire` (tests)
 */
export async function ouvrirBase(seed: string, stockage: 'idb' | 'memoire' = 'idb'): Promise<PGlite> {
  const nom = `${PREFIXE}-${versionSeed(seed)}`
  const db = new PGlite({
    ...(stockage === 'idb' ? { dataDir: `idb://${nom}` } : {}),
    extensions: { pg_trgm, pgcrypto, unaccent, uuid_ossp },
    relaxedDurability: true,
  })
  await db.waitReady

  const deja = await db.query<{ ok: boolean }>(`select to_regclass('public.demo_meta') is not null as ok`)
  if (!deja.rows[0]?.ok) {
    await db.exec(seed)
    // Les visites sont datées par rapport au jour où le fichier a été fabriqué :
    // on les ramène à aujourd'hui pour que « cette semaine » ne soit jamais vide.
    const ref = seed.match(/Date de référence des visites : (\d{4}-\d{2}-\d{2})/)?.[1]
    await db.exec(`
      set search_path = public, extensions;
      set session_replication_role = replica;
      ${ref ? `update public.visites set
          date_visite = date_visite + make_interval(days => current_date - date '${ref}'),
          created_at = created_at + make_interval(days => current_date - date '${ref}'),
          updated_at = updated_at + make_interval(days => current_date - date '${ref}');
        update public.resultat_perfect_store set calcule_le = calcule_le + make_interval(days => current_date - date '${ref}');` : ''}
      set session_replication_role = origin;
      select public.refresh_stats_dashboard();
      create table public.demo_meta (charge_le timestamptz not null default now());
      insert into public.demo_meta default values;
    `)
  }
  if (stockage === 'idb') void nettoyerAnciennesBases(nom)
  return db
}

/** Supprime les bases d'une version précédente des données (au mieux). */
async function nettoyerAnciennesBases(courante: string) {
  try {
    const liste = await (indexedDB as any).databases?.()
    for (const d of liste || []) {
      if (d.name?.includes(PREFIXE) && !d.name.includes(courante)) indexedDB.deleteDatabase(d.name)
    }
  }
  catch { /* navigateur sans indexedDB.databases() : rien à faire */ }
}

/** Efface toutes les données de démonstration de cet appareil. */
export async function effacerBases() {
  const liste = await (indexedDB as any).databases?.().catch(() => []) || []
  await Promise.all(liste.filter((d: any) => d.name?.includes(PREFIXE)).map((d: any) => new Promise<void>((ok) => {
    const r = indexedDB.deleteDatabase(d.name)
    r.onsuccess = r.onerror = r.onblocked = () => ok()
  })))
}
