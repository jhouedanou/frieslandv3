// demo/api.ts
// Mode démo : les routes serveur /api/* n'existent pas (aucun serveur). Elles
// sont rejouées ici, dans le navigateur, avec les mêmes règles et les mêmes
// messages que server/api/*.
import type { ClientDemo } from './client'

const ROLES = ['admin', 'superviseur', 'merchandiser', 'commercial']
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789'

function erreur(statusCode: number, statusMessage: string) {
  return Object.assign(new Error(statusMessage), { statusCode, statusMessage, data: { statusCode, statusMessage, message: statusMessage } })
}

const tableau = (v: any) => (Array.isArray(v) ? v : []).map((x: any) => String(x).trim()).filter(Boolean)

function motDePasseProvisoire(): string {
  const alea = new Uint32Array(8)
  crypto.getRandomValues(alea)
  const c = [...alea].map(n => ALPHABET[n % ALPHABET.length])
  return `FT-${c.slice(0, 4).join('')}-${c.slice(4).join('')}`
}

async function exigerAdmin(client: ClientDemo) {
  const moi = client.sessionCourante()?.user
  if (!moi) throw erreur(401, 'Session expirée, reconnectez-vous')
  const { data, error } = await client.service.from('profiles').select('role, is_active').eq('id', moi.id).single()
  if (error || data?.role !== 'admin' || data?.is_active === false) throw erreur(403, 'Action réservée aux administrateurs')
  return moi
}

async function creerCompte(client: ClientDemo, p: Record<string, any>) {
  const service = client.service
  const { data, error } = await service.auth.admin.createUser({
    email: p.email, password: p.password, user_metadata: { nom: p.nom, role: p.role },
  })
  if (error) {
    const existe = /already|exist/i.test(error.message || '')
    throw erreur(existe ? 409 : 400, existe ? 'Un compte existe déjà avec cet email' : error.message)
  }
  const id = data.user!.id
  const { data: profil, error: pe } = await service.from('profiles').upsert({
    id, email: p.email, nom: p.nom, role: p.role, telephone: p.telephone ?? null,
    zone_assignee: p.zone_assignee ?? null, commercial_id: p.commercial_id ?? null,
    territoires_assignes: p.territoires_assignes || [], quartiers_assignes: p.quartiers_assignes || [],
    region: p.region ?? null, is_active: true,
  }, { onConflict: 'id' }).select().single()
  if (pe) {
    await service.auth.admin.deleteUser(id)
    throw erreur(500, `Profil non enregistré : ${pe.message}`)
  }
  return profil
}

export async function appelerApiDemo(client: ClientDemo, url: string, options: { method?: string; body?: any } = {}): Promise<any> {
  await client.pret
  const methode = (options.method || 'GET').toUpperCase()
  const chemin = url.split('?')[0].replace(/\/$/, '')
  const body = options.body || {}
  const service = client.service
  let m: RegExpMatchArray | null

  // --- Demande de suppression de compte (publique) --------------------------
  if (chemin === '/api/account/deletion-request' && methode === 'POST') {
    const email = String(body.email || '').trim().toLowerCase()
    if (!EMAIL_RE.test(email)) throw erreur(400, 'Adresse e-mail invalide')
    if (body.confirm !== true) throw erreur(400, 'Veuillez confirmer la demande')
    let id = client.sessionCourante()?.user.id || null
    if (!id) id = (await service.from('profiles').select('id').eq('email', email).limit(1).maybeSingle()).data?.id || null
    if (id) {
      const { data } = await service.auth.admin.getUserById(id)
      await service.auth.admin.updateUserById(id, {
        user_metadata: {
          ...(data.user?.user_metadata || {}),
          deletion_requested_at: new Date().toISOString(),
          deletion_reason: String(body.reason || '').trim().substring(0, 500) || null,
          deletion_contact_email: email,
        },
      })
    }
    return { success: true }
  }

  const moi = await exigerAdmin(client)

  // --- Comptes --------------------------------------------------------------
  if (chemin === '/api/admin/users' && methode === 'POST') {
    const email = String(body.email || '').trim().toLowerCase()
    const password = String(body.password || '')
    const nom = String(body.nom || '').trim().substring(0, 100)
    const role = body.role || 'merchandiser'
    if (!email || !password || !nom) throw erreur(400, 'Email, mot de passe et nom sont requis')
    if (!EMAIL_RE.test(email)) throw erreur(400, 'Format d\'email invalide')
    if (password.length < 8) throw erreur(400, 'Le mot de passe doit contenir au moins 8 caractères')
    if (!ROLES.includes(role)) throw erreur(400, 'Rôle invalide')
    const territoires = tableau(body.territoires_assignes)
    return creerCompte(client, {
      email, password, nom, role,
      telephone: body.telephone ? String(body.telephone).trim().substring(0, 50) : null,
      zone_assignee: body.zone_assignee ? String(body.zone_assignee) : (territoires[0] || null),
      commercial_id: body.commercial_id ? String(body.commercial_id) : null,
      territoires_assignes: territoires, quartiers_assignes: tableau(body.quartiers_assignes),
      region: body.region ? String(body.region) : null,
    })
  }

  if (chemin === '/api/admin/users/deletion-requests' && methode === 'GET') {
    const { data } = await service.auth.admin.listUsers()
    return data.users
      .filter(u => u.user_metadata?.deletion_requested_at)
      .map(u => ({
        id: u.id, email: u.email || u.user_metadata?.deletion_contact_email || '',
        requested_at: String(u.user_metadata.deletion_requested_at), reason: u.user_metadata?.deletion_reason || null,
      }))
      .sort((a, b) => a.requested_at.localeCompare(b.requested_at))
  }

  if (chemin === '/api/admin/users/import' && methode === 'POST') {
    const lignes: any[] = Array.isArray(body.rows) ? body.rows : []
    if (!lignes.length) throw erreur(400, 'Aucune ligne à importer')
    if (lignes.length > 500) throw erreur(400, `Maximum 500 lignes par import (${lignes.length} reçues)`)
    const { data: existants } = await service.from('profiles').select('id, email')
    const idParEmail = new Map<string, string>((existants || []).map((p: any) => [String(p.email || '').toLowerCase(), p.id]))
    const vus = new Set<string>()
    const errors: { line: number; email: string; message: string }[] = []
    let created = 0, updated = 0
    for (const [i, l] of lignes.entries()) {
      const line = Number(l?.line) || i + 2
      const email = String(l?.email || '').trim().toLowerCase()
      const echec = (message: string) => errors.push({ line, email, message })
      if (!email || !EMAIL_RE.test(email)) { echec('Email manquant ou invalide'); continue }
      if (vus.has(email)) { echec('Email en double dans le fichier (première occurrence traitée)'); continue }
      vus.add(email)
      const nom = String(l?.nom || '').trim().substring(0, 100)
      const role = String(l?.role || '').trim().toLowerCase()
      if (role && !ROLES.includes(role)) { echec(`Rôle invalide : ${role}`); continue }
      const actifBrut = String(l?.is_active ?? '').trim().toLowerCase()
      const actif = ['true', '1', 'oui', 'yes', 'actif'].includes(actifBrut) ? true : ['false', '0', 'non', 'no', 'inactif'].includes(actifBrut) ? false : null
      if (actifBrut && actif === null) { echec(`Valeur is_active invalide : ${actifBrut}`); continue }
      const territoires = tableau(l?.territoires_assignes)
      const quartiers = tableau(l?.quartiers_assignes)
      const telephone = l?.telephone ? String(l.telephone).trim().substring(0, 50) : ''
      const zone = String(l?.zone_assignee || '').trim()
      const region = String(l?.region || '').trim()
      const chef = String(l?.commercial || '').trim().toLowerCase()
      const idExistant = idParEmail.get(email)
      if (idExistant) {
        const maj: Record<string, any> = {}
        if (nom) maj.nom = nom
        if (role) maj.role = role
        if (telephone) maj.telephone = telephone
        if (actif !== null) maj.is_active = actif
        if (territoires.length) maj.territoires_assignes = territoires
        if (quartiers.length) maj.quartiers_assignes = quartiers
        if (zone || territoires.length) maj.zone_assignee = zone || territoires[0]
        if (region) maj.region = region
        if (chef) {
          const cid = idParEmail.get(chef)
          if (!cid) { echec(`Commercial responsable inconnu : ${chef}`); continue }
          maj.commercial_id = cid
        }
        if (!Object.keys(maj).length) { echec('Aucun champ à mettre à jour'); continue }
        const { error } = await service.from('profiles').update(maj).eq('id', idExistant)
        if (error) { echec(error.message); continue }
        updated++
      }
      else {
        const password = String(l?.mot_de_passe || '').trim()
        if (!nom) { echec('Le nom est requis pour créer un compte'); continue }
        if (password.length < 8) { echec('Le mot de passe doit contenir au moins 8 caractères'); continue }
        try {
          const profil = await creerCompte(client, {
            email, password, nom, role: role || 'merchandiser', telephone: telephone || null,
            zone_assignee: zone || territoires[0] || null, territoires_assignes: territoires, quartiers_assignes: quartiers,
            region: region || null, commercial_id: chef ? (idParEmail.get(chef) || null) : null,
          })
          idParEmail.set(email, profil.id)
          created++
        }
        catch (e: any) { echec(e?.statusMessage || e?.message || 'Création impossible') }
      }
    }
    return { created, updated, errors }
  }

  if ((m = chemin.match(/^\/api\/admin\/users\/([^/]+)\/password$/)) && methode === 'POST') {
    const fourni = String(body.password || '').trim()
    if (fourni && fourni.length < 8) throw erreur(400, 'Le mot de passe doit contenir au moins 8 caractères')
    const password = fourni || motDePasseProvisoire()
    const { data: existant, error: ge } = await service.auth.admin.getUserById(m[1])
    if (ge || !existant.user) throw erreur(404, 'Compte de connexion introuvable pour cet utilisateur')
    const { error } = await service.auth.admin.updateUserById(m[1], {
      password, user_metadata: { ...(existant.user.user_metadata || {}), must_change_password: true },
    })
    if (error) throw erreur(500, error.message)
    return { success: true, password }
  }

  if ((m = chemin.match(/^\/api\/admin\/users\/([^/]+)$/)) && methode === 'DELETE') {
    if (m[1] === moi.id) throw erreur(400, 'Impossible de supprimer votre propre compte')
    const { error } = await service.auth.admin.deleteUser(m[1])
    if (error) throw erreur(500, error.message)
    await service.from('profiles').delete().eq('id', m[1])
    return { success: true }
  }

  // --- Équipes --------------------------------------------------------------
  if (chemin === '/api/admin/equipes' && methode === 'POST') {
    const commercialId = String(body.commercial_id || '').trim()
    const ids: string[] = Array.isArray(body.merchandiser_ids) ? body.merchandiser_ids.map(String) : []
    if (!commercialId) throw erreur(400, 'Commercial non précisé')
    if (![commercialId, ...ids].every(id => UUID_RE.test(id))) throw erreur(400, 'Identifiant invalide')
    const { data: commercial, error: ce } = await service.from('profiles').select('id, role, nom').eq('id', commercialId).maybeSingle()
    if (ce) throw erreur(500, ce.message)
    if (!commercial) throw erreur(404, 'Commercial introuvable')
    if (!['commercial', 'admin'].includes(commercial.role)) throw erreur(400, 'Le responsable doit être un commercial')
    let assignes = 0
    if (ids.length) {
      const { data, error } = await service.from('profiles').update({ commercial_id: commercialId }).in('id', ids).eq('role', 'merchandiser').select('id')
      if (error) throw erreur(500, error.message)
      assignes = data?.length || 0
    }
    let libere = service.from('profiles').update({ commercial_id: null }).eq('commercial_id', commercialId)
    if (ids.length) libere = libere.not('id', 'in', `(${ids.join(',')})`)
    const { error: le } = await libere
    if (le) throw erreur(500, le.message)
    return { commercial: commercial.nom, assignes }
  }

  // --- Alias de territoire --------------------------------------------------
  if (chemin === '/api/admin/territoire-alias' && methode === 'POST') {
    const alias = String(body.alias || '').trim()
    const code = String(body.territoire_code || '').trim()
    if (!alias || !code) throw erreur(400, 'alias et territoire_code sont requis')
    const { data: terr, error: te } = await service.from('territoire').select('code, nom').eq('code', code).maybeSingle()
    if (te) throw erreur(500, te.message)
    if (!terr) throw erreur(404, 'Territoire introuvable')
    const { error: ae } = await service.from('territoire_alias').upsert({ alias, territoire_code: code }, { onConflict: 'alias' })
    if (ae) throw erreur(500, ae.message)
    const reel = String(terr.nom).toUpperCase()
    const norm = (v: string) => (v || '').trim().toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
    const cible = norm(alias)
    const { data: profils, error: pe } = await service.from('profiles').select('id, territoires_assignes, zone_assignee')
    if (pe) throw erreur(500, pe.message)
    let modifies = 0
    for (const p of profils || []) {
      const terrs: string[] = Array.isArray(p.territoires_assignes) ? p.territoires_assignes : []
      const touche = terrs.some(t => norm(t) === cible) || norm(p.zone_assignee || '') === cible
      if (!touche) continue
      const nouveaux = [...new Set(terrs.map(t => (norm(t) === cible ? reel : t)))]
      const zone = norm(p.zone_assignee || '') === cible ? reel : p.zone_assignee
      const { error } = await service.from('profiles').update({ territoires_assignes: nouveaux, zone_assignee: zone }).eq('id', p.id)
      if (error) throw erreur(500, error.message)
      modifies++
    }
    return { alias, territoire: terr.nom, profils: modifies }
  }

  throw erreur(404, `Route indisponible en mode démo : ${methode} ${chemin}`)
}
