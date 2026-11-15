// Mode démo : le faux client Supabase, sur la vraie base embarquée (PGlite).
import { readFileSync } from 'node:fs'
import { beforeAll, describe, expect, it } from 'vitest'
import { creerClientDemo, type ClientDemo } from '../demo/client'
import { MOT_DE_PASSE_DEMO } from '../demo/comptes'
import { ouvrirBase } from '../demo/db'

let client: ClientDemo

beforeAll(async () => {
  const seed = readFileSync('demo/seed.sql', 'utf8')
  client = creerClientDemo({ base: ouvrirBase(seed, 'memoire') as any })
  await client.pret
}, 60_000)

const connecter = async (email: string) => {
  const { error } = await client.auth.signInWithPassword({ email, password: MOT_DE_PASSE_DEMO })
  expect(error).toBeNull()
}

describe('mode démo — connexion', () => {
  it('refuse un mauvais mot de passe', async () => {
    const { error } = await client.auth.signInWithPassword({ email: 'admin@fieldtrack.demo', password: 'faux' })
    expect(error?.message).toBe('Invalid login credentials')
  })

  it('sans connexion, les PDV ne sont pas lisibles', async () => {
    await client.auth.signOut()
    const { data } = await client.from('pdv').select('pdv_id')
    expect(data ?? []).toHaveLength(0)
  })
})

describe('mode démo — lectures', () => {
  it("l'admin voit les 15 PDV et les 15 visites", async () => {
    await connecter('admin@fieldtrack.demo')
    const pdv = await client.from('pdv').select('pdv_id', { count: 'exact', head: true }).eq('is_active', true)
    expect(pdv.error).toBeNull()
    expect(pdv.count).toBe(15)
    const visites = await client.from('visites')
      .select('*, pdv:pdv_id(pdv_id, nom_pdv, zone), user:user_id(id, nom)', { count: 'exact' })
      .order('date_visite', { ascending: false }).range(0, 4)
    expect(visites.error).toBeNull()
    expect(visites.count).toBe(15)
    expect(visites.data).toHaveLength(5)
    expect(visites.data[0].pdv.nom_pdv).toBeTruthy()
    expect(visites.data[0].user.nom).toBeTruthy()
    expect(typeof visites.data[0].date_visite).toBe('string')
  })

  it('un merchandiser ne voit que son territoire', async () => {
    await connecter('merchandiser1@fieldtrack.demo')
    const { data, error } = await client.from('pdv').select('pdv_id, zone')
    expect(error).toBeNull()
    expect(data.length).toBe(3)
    expect(new Set(data.map((p: any) => p.zone))).toEqual(new Set(['Territoire Est']))
  })

  it('gère or(), ilike, in, not, single et maybeSingle', async () => {
    await connecter('admin@fieldtrack.demo')
    const ou = await client.from('pdv').select('pdv_id').or('nom_pdv.ilike.%baobab%,pdv_id.ilike.%FT-002%')
    expect(ou.data.map((p: any) => p.pdv_id).sort()).toEqual(['FT-001', 'FT-002'])
    const dans = await client.from('pdv').select('pdv_id').in('zone', ['Territoire Sud', 'Territoire Centre']).not('geolocation_lat', 'is', null)
    expect(dans.data).toHaveLength(6)
    const un = await client.from('pdv').select('nom_pdv').eq('pdv_id', 'FT-001').single()
    expect(un.data.nom_pdv).toBe('Boutique Le Baobab')
    const aucun = await client.from('pdv').select('nom_pdv').eq('pdv_id', 'ABSENT').maybeSingle()
    expect(aucun.error).toBeNull()
    expect(aucun.data).toBeNull()
    const trop = await client.from('pdv').select('nom_pdv').single()
    expect(trop.error?.code).toBe('PGRST116')
  })

  it('lit les vues du tableau de bord', async () => {
    await connecter('admin@fieldtrack.demo')
    for (const vue of ['v_stats_visites', 'v_visites_par_jour', 'v_perfect_store_global', 'v_perfect_store_liste', 'v_couverture_globale', 'v_distribution_pdv', 'v_performance_commerciaux']) {
      const r = await client.from(vue).select('*')
      expect(r.error, vue).toBeNull()
    }
    const liste = await client.from('v_perfect_store_liste').select('*', { count: 'exact' })
    expect(liste.count).toBeGreaterThan(0)
  })

  it('appelle une fonction de base (rpc)', async () => {
    await connecter('admin@fieldtrack.demo')
    const { error } = await client.rpc('compter_visites_a_recalculer')
    expect(error).toBeNull()
  })
})

describe('mode démo — écritures', () => {
  it('un merchandiser saisit une visite, le score est calculé', async () => {
    await connecter('merchandiser1@fieldtrack.demo')
    const moi = client.sessionCourante()!.user
    const { data, error } = await client.from('visites').insert({
      visite_id: 'TEST-VIS-1', pdv_id: 'FT-001', user_id: moi.id, date_visite: new Date().toISOString(),
      commercial: 'Daouda Essai', email: moi.email, geofence_validated: true,
      data: { produits: { evap: { quantites: { br_160g: 12 } } }, visibilite: { standards: { affiche: true } } },
      sync_status: 'synced',
    }).select().single()
    expect(error).toBeNull()
    expect(data.visite_id).toBe('TEST-VIS-1')
    expect(data.data.produits.evap.quantites.br_160g).toBe(12)
    const score = await client.service.from('resultat_perfect_store').select('visite_id').eq('visite_id', data.id)
    expect(score.data).toHaveLength(1)
  })

  it('met à jour, puis supprime', async () => {
    await connecter('admin@fieldtrack.demo')
    const maj = await client.from('pdv').update({ adressage: 'Nouvelle adresse' }).eq('pdv_id', 'FT-002').select('pdv_id, adressage')
    expect(maj.error).toBeNull()
    expect(maj.data[0].adressage).toBe('Nouvelle adresse')
    const sup = await client.from('visites').delete().eq('visite_id', 'TEST-VIS-1')
    expect(sup.error).toBeNull()
    const reste = await client.from('visites').select('id', { count: 'exact', head: true })
    expect(reste.count).toBe(15)
  })

  it('upsert sur une clé de conflit', async () => {
    await connecter('admin@fieldtrack.demo')
    const r = await client.service.from('territoire_alias').upsert({ alias: 'COCO TEST', territoire_code: 'T-EST' }, { onConflict: 'alias' })
    expect(r.error).toBeNull()
    const r2 = await client.service.from('territoire_alias').upsert({ alias: 'COCO TEST', territoire_code: 'T-CEN' }, { onConflict: 'alias' }).select()
    expect(r2.data[0].territoire_code).toBe('T-CEN')
  })
})

describe('mode démo — comptes', () => {
  it("crée un compte, s'y connecte, le supprime", async () => {
    const cree = await client.service.auth.admin.createUser({ email: 'nouveau@fieldtrack.demo', password: 'motdepasse1', user_metadata: { nom: 'Nouveau', role: 'merchandiser' } })
    expect(cree.error).toBeNull()
    const profil = await client.service.from('profiles').select('role').eq('id', cree.data.user!.id).single()
    expect(profil.data.role).toBe('merchandiser')
    const ok = await client.auth.signInWithPassword({ email: 'nouveau@fieldtrack.demo', password: 'motdepasse1' })
    expect(ok.error).toBeNull()
    await client.service.auth.admin.deleteUser(cree.data.user!.id)
    const parti = await client.service.from('profiles').select('id').eq('email', 'nouveau@fieldtrack.demo')
    expect(parti.data).toHaveLength(0)
  })
})

describe('mode démo — routes d\'administration rejouées dans le navigateur', () => {
  it('refuse un compte non admin', async () => {
    const { appelerApiDemo } = await import('../demo/api')
    await connecter('merchandiser1@fieldtrack.demo')
    await expect(appelerApiDemo(client, '/api/admin/users', { method: 'POST', body: {} })).rejects.toMatchObject({ statusCode: 403 })
  })

  it('crée un compte, réinitialise son mot de passe, compose une équipe, supprime', async () => {
    const { appelerApiDemo } = await import('../demo/api')
    await connecter('admin@fieldtrack.demo')
    const profil = await appelerApiDemo(client, '/api/admin/users', {
      method: 'POST',
      body: { email: 'Recrue@FieldTrack.demo', password: 'motdepasse1', nom: 'Recrue Essai', role: 'merchandiser', territoires_assignes: ['Territoire Sud'] },
    })
    expect(profil.email).toBe('recrue@fieldtrack.demo')
    expect(profil.zone_assignee).toBe('Territoire Sud')
    expect(profil.territoires_assignes).toEqual(['Territoire Sud'])

    await expect(appelerApiDemo(client, '/api/admin/users', {
      method: 'POST', body: { email: 'recrue@fieldtrack.demo', password: 'motdepasse1', nom: 'Doublon' },
    })).rejects.toMatchObject({ statusCode: 409 })

    const { password } = await appelerApiDemo(client, `/api/admin/users/${profil.id}/password`, { method: 'POST', body: {} })
    expect(password).toMatch(/^FT-.{4}-.{4}$/)

    const chef = (await client.service.from('profiles').select('id').eq('email', 'commercial3@fieldtrack.demo').single()).data
    const equipe = await appelerApiDemo(client, '/api/admin/equipes', { method: 'POST', body: { commercial_id: chef.id, merchandiser_ids: [profil.id] } })
    expect(equipe.assignes).toBe(1)
    // merchandiser5 était dans cette équipe : il en sort, la liste remplace l'ancienne.
    const m5 = (await client.service.from('profiles').select('commercial_id').eq('email', 'merchandiser5@fieldtrack.demo').single()).data
    expect(m5.commercial_id).toBeNull()

    await client.auth.signInWithPassword({ email: 'recrue@fieldtrack.demo', password })
    expect(client.sessionCourante()?.user.user_metadata.must_change_password).toBe(true)

    await connecter('admin@fieldtrack.demo')
    await appelerApiDemo(client, `/api/admin/users/${profil.id}`, { method: 'DELETE' })
    const reste = await client.service.from('profiles').select('id').eq('id', profil.id)
    expect(reste.data).toHaveLength(0)
  })
})
