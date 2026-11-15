// demo/client.ts
// Mode démo : faux client Supabase. Même surface que celle utilisée par
// l'application (from, rpc, auth, storage, channel), mais tout s'exécute dans
// la base embarquée. Indépendant de Nuxt et du navigateur (testé sous Node).
import { MOT_DE_PASSE_DEMO } from './comptes'
import { Requete, lireSchema, lit, sqlRpc, versErreur, type Schema } from './postgrest'

/** Base embarquée : exécute du SQL dans une transaction. */
export interface BaseDemo {
  transaction<T>(fn: (tx: { exec(sql: string): Promise<any>; query(sql: string): Promise<{ rows: any[] }> }) => Promise<T>): Promise<T>
}

export interface SessionDemo { access_token: string; refresh_token: string; expires_at: number; user: UtilisateurDemo }
export interface UtilisateurDemo { id: string; email: string; aud: string; role: string; user_metadata: Record<string, any>; app_metadata: Record<string, any>; created_at?: string }

export interface OptionsClient {
  /** Base prête (ouverture + chargement des données). */
  base: Promise<BaseDemo>
  /** Identifiant du compte connecté, mémorisé entre deux ouvertures. */
  lireSessionId?: () => string | null
  ecrireSessionId?: (id: string | null) => void
  /** Convertit un fichier en URL utilisable dans une balise <img>. */
  fichierVersUrl?: (fichier: any) => Promise<string>
}

// Tables dont dépendent les statistiques pré-calculées du tableau de bord.
const TABLES_STATS = new Set(['visites', 'pdv', 'profiles'])

export function creerClientDemo(options: OptionsClient) {
  let session: SessionDemo | null = null
  let schema: Promise<Schema> | null = null
  const ecouteurs = new Set<(evenement: string, s: SessionDemo | null) => void>()
  const fichiers = new Map<string, string>()
  let rafraichissement: Promise<void> | null = null

  /** Exécute en tant que superutilisateur (service) ou que le compte connecté (RLS appliquée). */
  async function executer(sql: string, service: boolean): Promise<any[]> {
    const base = await options.base
    return base.transaction(async (tx) => {
      await tx.exec('set local search_path = public, extensions')
      if (!service) {
        const uid = session?.user.id || ''
        const role = uid ? 'authenticated' : 'anon'
        await tx.exec(
          `select set_config('request.jwt.claim.sub', ${lit(uid)}, true), set_config('request.jwt.claim.role', ${lit(role)}, true); set local role ${role}`)
      }
      return (await tx.query(sql)).rows
    })
  }

  const lireSchemaUneFois = () => (schema ||= lireSchema(sql => executer(sql, true)))

  function apresEcriture(table: string) {
    if (!TABLES_STATS.has(table) || rafraichissement) return
    rafraichissement = executer('select public.refresh_stats_dashboard()', true)
      .then(() => {}, () => {})
      .finally(() => { rafraichissement = null })
  }

  function versUtilisateur(u: any): UtilisateurDemo {
    return {
      id: u.id, email: u.email, aud: 'authenticated', role: 'authenticated',
      user_metadata: u.raw_user_meta_data || {}, app_metadata: u.raw_app_meta_data || {}, created_at: u.created_at,
    }
  }

  function poserSession(u: any | null, evenement: string) {
    session = u
      ? { access_token: `demo-${u.id}`, refresh_token: `demo-${u.id}`, expires_at: Math.floor(Date.now() / 1000) + 365 * 86400, user: versUtilisateur(u) }
      : null
    options.ecrireSessionId?.(session?.user.id ?? null)
    for (const e of ecouteurs) e(evenement, session)
    return session
  }

  const lireCompte = async (condition: string) =>
    (await executer(`select id, email, encrypted_password, raw_user_meta_data, raw_app_meta_data, created_at from auth.users where ${condition} limit 1`, true))[0] || null

  const erreurAuth = (message: string, status = 400) => ({ name: 'AuthApiError', message, status })

  function fabrique(service: boolean) {
    const from = (table: string) => {
      // Le schéma est lu à la première requête : on enveloppe pour rester synchrone.
      const attente: any[] = []
      let reelle: Requete | null = null
      const proxy: any = new Proxy({}, {
        get(_, prop: string) {
          if (prop === 'then') {
            return (ok: any, ko: any) => lireSchemaUneFois()
              .then((s) => {
                reelle = new Requete(s, sql => executer(sql, service), table, apresEcriture)
                for (const [m, args] of attente) (reelle as any)[m](...args)
                // Une Requete est « thenable » : la renvoyer ici donne directement son résultat.
                return reelle
              })
              .catch(err => ({ data: null, count: null, status: 500, statusText: 'Erreur', error: versErreur(err) }))
              .then(ok, ko)
          }
          return (...args: any[]) => { attente.push([prop, args]); return proxy }
        },
      })
      return proxy
    }

    // Comme supabase-js : le résultat d'une fonction se pagine (.range, .limit)
    // et se réduit (.single). L'appel part quand on attend le résultat.
    function rpc(nom: string, args: Record<string, any> = {}) {
      let decalage = 0
      let limite: number | undefined
      let unique: 'single' | 'maybeSingle' | undefined

      async function lancer() {
        try {
          const meta = (await executer(
            `select p.proretset, p.provolatile, p.prorettype::regtype::text as type from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = ${lit(nom)} limit 1`, true))[0]
          if (!meta) return { data: null, error: { code: 'PGRST202', message: `Fonction introuvable : ${nom}`, details: null, hint: null } }
          const queue = `${limite !== undefined ? ` limit ${Number(limite)}` : ''}${decalage ? ` offset ${Number(decalage)}` : ''}`
          const lignes = (await executer(sqlRpc(nom, args) + queue, service)).map(r => r.r)
          // Une fonction qui écrit (recalcul, géolocalisation…) : les statistiques suivent.
          if (meta.provolatile === 'v') apresEcriture('visites')
          if (meta.type === 'void') return { data: null, error: null }
          if (!meta.proretset) return { data: lignes[0] ?? null, error: null }
          if (!unique) return { data: lignes, error: null }
          if (lignes.length === 1) return { data: lignes[0], error: null }
          if (!lignes.length && unique === 'maybeSingle') return { data: null, error: null }
          return { data: null, error: { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned', details: null, hint: null } }
        }
        catch (err: any) {
          console.warn(`[démo] rpc ${nom} : ${err?.message || err}`)
          return { data: null, error: versErreur(err) }
        }
      }

      const appel: any = {
        range(de: number, a: number) { decalage = de; limite = a - de + 1; return appel },
        limit(n: number) { limite = n; return appel },
        single() { unique = 'single'; return appel },
        maybeSingle() { unique = 'maybeSingle'; return appel },
        select() { return appel },
        abortSignal() { return appel },
        then(ok: any, ko: any) { return lancer().then(ok, ko) },
      }
      return appel
    }

    return { from, rpc }
  }

  const utilisateur = fabrique(false)
  const serviceBase = fabrique(true)

  const auth = {
    async getSession() { await pret; return { data: { session }, error: null } },
    async getUser() { await pret; return { data: { user: session?.user ?? null }, error: null } },
    async signInWithPassword({ email, password }: { email: string; password: string }) {
      await pret
      const u = await lireCompte(`lower(email) = ${lit(String(email || '').trim().toLowerCase())}`)
      const attendu = u?.encrypted_password || MOT_DE_PASSE_DEMO
      if (!u || password !== attendu) return { data: { user: null, session: null }, error: erreurAuth('Invalid login credentials') }
      const s = poserSession(u, 'SIGNED_IN')
      return { data: { user: s!.user, session: s }, error: null }
    },
    async signOut() { poserSession(null, 'SIGNED_OUT'); return { error: null } },
    async refreshSession() {
      await pret
      if (!session) return { data: { session: null, user: null }, error: null }
      const u = await lireCompte(`id = ${lit(session.user.id)}`)
      const s = poserSession(u, 'TOKEN_REFRESHED')
      return { data: { session: s, user: s?.user ?? null }, error: null }
    },
    async setSession({ access_token }: { access_token: string; refresh_token?: string }) {
      await pret
      const id = String(access_token || '').replace(/^demo-/, '')
      const u = /^[0-9a-f-]{36}$/i.test(id) ? await lireCompte(`id = ${lit(id)}`) : null
      const s = poserSession(u, 'SIGNED_IN')
      return { data: { session: s, user: s?.user ?? null }, error: u ? null : erreurAuth('Session invalide', 401) }
    },
    async updateUser(maj: { password?: string; data?: Record<string, any> }) {
      await pret
      if (!session) return { data: { user: null }, error: erreurAuth('Session expirée', 401) }
      const { data, error } = await admin.updateUserById(session.user.id, { password: maj.password, user_metadata: maj.data ? { ...session.user.user_metadata, ...maj.data } : undefined })
      if (error) return { data: { user: null }, error }
      session = { ...session, user: data.user! }
      for (const e of ecouteurs) e('USER_UPDATED', session)
      return { data: { user: session.user }, error: null }
    },
    async signUp() { return { data: { user: null, session: null }, error: erreurAuth('Inscription désactivée en mode démo') } },
    onAuthStateChange(fn: (evenement: string, s: SessionDemo | null) => void) {
      ecouteurs.add(fn)
      return { data: { subscription: { unsubscribe: () => ecouteurs.delete(fn) } } }
    },
  }

  // API d'administration des comptes (réservée au client « service »).
  const admin = {
    async createUser(p: { email: string; password?: string; user_metadata?: Record<string, any> }) {
      try {
        const u = (await executer(
          `insert into auth.users(email, encrypted_password, raw_user_meta_data, email_confirmed_at) values (${lit(p.email)}, ${lit(p.password ?? null)}, ${lit(p.user_metadata || {})}::jsonb, now()) returning *`, true))[0]
        return { data: { user: versUtilisateur(u) }, error: null }
      }
      catch (err: any) {
        const doublon = err?.code === '23505'
        return { data: { user: null }, error: erreurAuth(doublon ? 'User already registered' : err.message, doublon ? 422 : 400) }
      }
    },
    async deleteUser(id: string) {
      try { await executer(`delete from auth.users where id = ${lit(id)}`, true); return { data: {}, error: null } }
      catch (err: any) { return { data: null, error: erreurAuth(err.message, 500) } }
    },
    async getUserById(id: string) {
      const u = await lireCompte(`id = ${lit(id)}`)
      return u ? { data: { user: versUtilisateur(u) }, error: null } : { data: { user: null }, error: erreurAuth('User not found', 404) }
    },
    async updateUserById(id: string, maj: { password?: string; user_metadata?: Record<string, any> }) {
      try {
        const sets: string[] = []
        if (maj.password) sets.push(`encrypted_password = ${lit(maj.password)}`)
        if (maj.user_metadata) sets.push(`raw_user_meta_data = ${lit(maj.user_metadata)}::jsonb`)
        if (sets.length) await executer(`update auth.users set ${sets.join(', ')} where id = ${lit(id)}`, true)
        return admin.getUserById(id)
      }
      catch (err: any) { return { data: { user: null }, error: erreurAuth(err.message, 500) } }
    },
    async listUsers() {
      const lignes = await executer('select id, email, raw_user_meta_data, raw_app_meta_data, created_at from auth.users order by email', true)
      return { data: { users: lignes.map(versUtilisateur) }, error: null }
    },
  }

  // Photos : pas de serveur, l'image devient une URL « data: » enregistrée telle quelle.
  const storage = {
    from(bucket: string) {
      return {
        async upload(chemin: string, fichier: any) {
          try {
            const url = options.fichierVersUrl ? await options.fichierVersUrl(fichier) : ''
            fichiers.set(`${bucket}/${chemin}`, url)
            return { data: { path: chemin, fullPath: `${bucket}/${chemin}` }, error: null }
          }
          catch (err: any) { return { data: null, error: { message: err?.message || 'Envoi impossible' } } }
        },
        getPublicUrl(chemin: string) { return { data: { publicUrl: fichiers.get(`${bucket}/${chemin}`) || '' } } },
        async remove(chemins: string[]) { for (const c of chemins || []) fichiers.delete(`${bucket}/${c}`); return { data: [], error: null } },
      }
    },
  }

  // Temps réel : sans serveur, rien n'arrive d'ailleurs. Canal inerte.
  function channel(_nom: string) {
    const canal: any = { on: () => canal, subscribe: () => canal, unsubscribe: async () => 'ok' }
    return canal
  }

  // Reprise de la session mémorisée, une fois la base ouverte.
  const pret: Promise<void> = options.base.then(async () => {
    const id = options.lireSessionId?.()
    if (id && /^[0-9a-f-]{36}$/i.test(id)) {
      const u = await lireCompte(`id = ${lit(id)}`).catch(() => null)
      if (u) poserSession(u, 'INITIAL_SESSION')
    }
  })

  return {
    ...utilisateur,
    auth,
    storage,
    channel,
    removeChannel: async () => 'ok',
    removeAllChannels: async () => [],
    /** Résolu quand la base est ouverte et la session reprise. */
    pret,
    /** Session courante, lecture synchrone (après `pret`). */
    sessionCourante: () => session,
    /** Client sans restriction d'accès : remplace les routes serveur d'administration. */
    service: { ...serviceBase, auth: { admin } },
    /** SQL direct en superutilisateur (initialisation, tests). */
    sql: (requete: string) => executer(requete, true),
  }
}

export type ClientDemo = ReturnType<typeof creerClientDemo>
