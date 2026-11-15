#!/usr/bin/env node
/**
 * Field Track — comptes fictifs de la base de démonstration.
 *   1 admin, 3 commerciaux, 5 merchandisers, tous en @fieldtrack.demo.
 * Rejouable : un compte existant est mis à jour, jamais dupliqué.
 * Les équipes et les territoires sont posés ensuite par
 * supabase/field-track/90_demo.sql.
 *
 * .env attendu (celui de la base Field Track, jamais celui d'un client) :
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
 *   FIELD_TRACK_DEMO_PASSWORD (12 caractères au moins, jamais affiché).
 *
 * Usage : node scripts/field-track-create-accounts.mjs
 */
import { createClient } from '@supabase/supabase-js'
import { config } from 'dotenv'
config()

const URL = process.env.SUPABASE_URL
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY
const PASSWORD = process.env.FIELD_TRACK_DEMO_PASSWORD
if (!URL || !SERVICE || !PASSWORD) {
  console.error('SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY et FIELD_TRACK_DEMO_PASSWORD requis dans .env')
  process.exit(1)
}
if (PASSWORD.length < 12) {
  console.error('FIELD_TRACK_DEMO_PASSWORD : 12 caractères au moins.')
  process.exit(1)
}

const COMPTES = [
  { email: 'admin@fieldtrack.demo', nom: 'Admin Field Track', role: 'admin', telephone: '+225 01 00 00 00 01' },
  { email: 'commercial1@fieldtrack.demo', nom: 'Awa Démo', role: 'commercial', telephone: '+225 01 00 00 00 11' },
  { email: 'commercial2@fieldtrack.demo', nom: 'Bakary Démo', role: 'commercial', telephone: '+225 01 00 00 00 12' },
  { email: 'commercial3@fieldtrack.demo', nom: 'Clarisse Démo', role: 'commercial', telephone: '+225 01 00 00 00 13' },
  { email: 'merchandiser1@fieldtrack.demo', nom: 'Daouda Essai', role: 'merchandiser', telephone: '+225 01 00 00 00 21' },
  { email: 'merchandiser2@fieldtrack.demo', nom: 'Estelle Essai', role: 'merchandiser', telephone: '+225 01 00 00 00 22' },
  { email: 'merchandiser3@fieldtrack.demo', nom: 'Fabrice Essai', role: 'merchandiser', telephone: '+225 01 00 00 00 23' },
  { email: 'merchandiser4@fieldtrack.demo', nom: 'Grâce Essai', role: 'merchandiser', telephone: '+225 01 00 00 00 24' },
  { email: 'merchandiser5@fieldtrack.demo', nom: 'Hervé Essai', role: 'merchandiser', telephone: '+225 01 00 00 00 25' },
]

const admin = createClient(URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } })

// Garde-fou : une base qui contient déjà d'autres comptes n'est pas une base de démonstration.
const { data: liste, error: le } = await admin.auth.admin.listUsers({ perPage: 1000 })
if (le) { console.error('❌ lecture des comptes :', le.message); process.exit(1) }
const etrangers = liste.users.filter(u => !u.email?.toLowerCase().endsWith('@fieldtrack.demo'))
if (etrangers.length) {
  console.error(`❌ ${etrangers.length} compte(s) hors @fieldtrack.demo dans cette base : ce n'est pas une base de démonstration, arrêt.`)
  process.exit(1)
}

for (const c of COMPTES) {
  let user = liste.users.find(u => u.email?.toLowerCase() === c.email)
  const meta = { nom: c.nom, role: c.role, must_change_password: false }
  if (!user) {
    const { data, error } = await admin.auth.admin.createUser({
      email: c.email, password: PASSWORD, email_confirm: true, user_metadata: meta,
    })
    if (error) { console.error('❌', c.email, error.message); process.exit(1) }
    user = data.user
  }
  else {
    const { error } = await admin.auth.admin.updateUserById(user.id, {
      password: PASSWORD, user_metadata: { ...user.user_metadata, ...meta },
    })
    if (error) { console.error('❌', c.email, error.message); process.exit(1) }
  }
  const { error: pe } = await admin.from('profiles').upsert({
    id: user.id, email: c.email, nom: c.nom, role: c.role, telephone: c.telephone, is_active: true,
  }, { onConflict: 'id' })
  if (pe) { console.error('❌ profil', c.email, pe.message); process.exit(1) }
  console.log(`✅ ${c.role.padEnd(12)} ${c.email}  (${c.nom})`)
}
console.log('\nMot de passe commun : FIELD_TRACK_DEMO_PASSWORD du .env.')
