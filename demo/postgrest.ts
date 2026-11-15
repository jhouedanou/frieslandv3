// demo/postgrest.ts
// Mode démo : traduit les requêtes « façon Supabase » (from/select/eq/insert…)
// en SQL, exécuté par la base embarquée (PGlite). Le but est que les écrans
// n'aient rien à changer : même syntaxe de select, mêmes filtres, mêmes
// réponses { data, error, count }.
//
// Ce fichier ne dépend ni de Nuxt ni du navigateur : il est testé sous Node
// (tests/demoClient.spec.ts).

export interface Schema {
  /** table -> colonne -> type Postgres (udt_name) */
  colonnes: Record<string, Record<string, string>>
  /** clés étrangères du schéma public */
  fks: { table: string; colonne: string; cible: string; cibleColonne: string; nom: string }[]
  /** table -> colonnes de clé primaire */
  pks: Record<string, string[]>
}

export interface ErreurPg { message: string; code?: string; details?: string | null; hint?: string | null }

/** Exécute une requête SQL et renvoie les lignes. Fourni par demo/db.ts. */
export type Executeur = (sql: string) => Promise<any[]>

// ---------------------------------------------------------------------------
// Littéraux et identifiants
// ---------------------------------------------------------------------------
export const ident = (nom: string) => `"${String(nom).replace(/"/g, '""')}"`

/** Littéral SQL non typé : Postgres le convertit au type de la colonne, comme PostgREST. */
export function lit(v: any): string {
  if (v === null || v === undefined) return 'NULL'
  if (typeof v === 'boolean') return v ? `'true'` : `'false'`
  if (v instanceof Date) return `'${v.toISOString()}'`
  if (typeof v === 'object') return `'${JSON.stringify(v).replace(/'/g, `''`)}'`
  return `'${String(v).replace(/'/g, `''`)}'`
}

/** Littéral de tableau Postgres : '{"a","b"}' */
const litTableau = (vals: any[]) =>
  lit(`{${vals.map(x => (x === null ? 'NULL' : `"${String(x).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`)).join(',')}}`)

// ---------------------------------------------------------------------------
// Analyse d'une chaîne select : "a, b, alias:col, rel(x, y), autre:fk!inner(*)"
// ---------------------------------------------------------------------------
interface NoeudColonne { type: 'col'; expr: string; alias?: string }
interface NoeudEmbed { type: 'embed'; cible: string; alias: string; indice?: string; inner: boolean; enfants: Noeud[] }
type Noeud = NoeudColonne | NoeudEmbed

function decouper(s: string): string[] {
  const out: string[] = []
  let prof = 0, guillemets = false, cur = ''
  for (const c of s) {
    if (c === '"') guillemets = !guillemets
    if (!guillemets && c === '(') prof++
    if (!guillemets && c === ')') prof--
    if (!guillemets && prof === 0 && c === ',') { out.push(cur); cur = ''; continue }
    cur += c
  }
  if (cur.trim()) out.push(cur)
  return out.map(x => x.trim()).filter(Boolean)
}

export function analyserSelect(s: string): Noeud[] {
  return decouper(s || '*').map((item): Noeud => {
    const par = item.indexOf('(')
    if (par > -1 && item.endsWith(')')) {
      let tete = item.slice(0, par).trim()
      const corps = item.slice(par + 1, -1)
      let alias: string | undefined
      const deux = tete.indexOf(':')
      if (deux > -1 && tete[deux + 1] !== ':') { alias = tete.slice(0, deux).trim(); tete = tete.slice(deux + 1).trim() }
      const morceaux = tete.split('!')
      const cible = morceaux[0]
      const inner = morceaux.includes('inner')
      const indice = morceaux.slice(1).find(m => m !== 'inner' && m !== 'left')
      return { type: 'embed', cible, alias: alias || cible, indice, inner, enfants: analyserSelect(corps) }
    }
    const deux = item.indexOf(':')
    if (deux > -1 && item[deux + 1] !== ':' && item[deux - 1] !== ':') {
      return { type: 'col', alias: item.slice(0, deux).trim(), expr: item.slice(deux + 1).trim() }
    }
    return { type: 'col', expr: item }
  })
}

// ---------------------------------------------------------------------------
// Colonnes : "col", "col->cle", "col->>cle", "col::type"
// ---------------------------------------------------------------------------
function exprColonne(t: string, chemin: string): { sql: string; nom: string } {
  let cast = ''
  const c = chemin.indexOf('::')
  if (c > -1) { cast = chemin.slice(c); chemin = chemin.slice(0, c) }
  const parts = chemin.split(/(->>|->)/)
  let sql = `${t}.${ident(parts[0].trim())}`
  let nom = parts[0].trim()
  for (let i = 1; i < parts.length; i += 2) {
    const cle = parts[i + 1].trim()
    sql += `${parts[i]}${/^\d+$/.test(cle) ? cle : lit(cle)}`
    nom = cle
  }
  return { sql: sql + cast, nom }
}

// ---------------------------------------------------------------------------
// Filtres
// ---------------------------------------------------------------------------
type Filtre =
  | { type: 'op'; col: string; op: string; val: any; non?: boolean }
  | { type: 'brut'; logique: 'or' | 'and'; texte: string }

function listeBrute(v: string): string[] {
  const interieur = v.trim().replace(/^\(/, '').replace(/\)$/, '')
  return decouper(interieur).map(x => (x.startsWith('"') && x.endsWith('"') ? x.slice(1, -1).replace(/\\"/g, '"') : x))
}

function sqlOperation(schema: Schema, table: string, t: string, col: string, op: string, val: any, brut: boolean): string {
  const { sql: c } = exprColonne(t, col)
  const typeCol = schema.colonnes[table]?.[col]
  switch (op) {
    case 'eq': return `${c} = ${lit(val)}`
    case 'neq': return `${c} <> ${lit(val)}`
    case 'gt': return `${c} > ${lit(val)}`
    case 'gte': return `${c} >= ${lit(val)}`
    case 'lt': return `${c} < ${lit(val)}`
    case 'lte': return `${c} <= ${lit(val)}`
    case 'like': return `${c}::text like ${lit(brut ? String(val).replace(/\*/g, '%') : val)}`
    case 'ilike': return `${c}::text ilike ${lit(brut ? String(val).replace(/\*/g, '%') : val)}`
    case 'is': {
      const v = val === null ? 'null' : String(val).toLowerCase()
      if (v === 'null') return `${c} is null`
      if (v === 'true' || v === 'false') return `${c} is ${v}`
      return `${c} is null`
    }
    case 'in': {
      const vals = Array.isArray(val) ? val : listeBrute(String(val))
      return vals.length ? `${c} in (${vals.map(lit).join(',')})` : 'false'
    }
    case 'cs':
    case 'ov': {
      const signe = op === 'cs' ? '@>' : '&&'
      if (typeCol === 'jsonb' || typeCol === 'json') {
        const v = typeof val === 'string' && brut ? listeBrute(val.replace(/^\{/, '(').replace(/\}$/, ')')) : val
        return `${c} ${signe} ${lit(typeof v === 'string' ? v : JSON.stringify(v))}::jsonb`
      }
      if (Array.isArray(val)) return `${c} ${signe} ${litTableau(val)}`
      return `${c} ${signe} ${lit(val)}`
    }
    default:
      throw Object.assign(new Error(`Opérateur non géré en mode démo : ${op}`), { code: 'PGRST100' })
  }
}

/** "a.eq.1,b.ilike.%x%,and(c.is.null,d.in.(1,2))" -> SQL */
function sqlBrut(schema: Schema, table: string, t: string, texte: string, logique: 'or' | 'and'): string {
  const morceaux = decouper(texte).map((m) => {
    const groupe = m.match(/^(not\.)?(and|or)\((.*)\)$/s)
    if (groupe) {
      const s = sqlBrut(schema, table, t, groupe[3], groupe[2] as any)
      return groupe[1] ? `not (${s})` : s
    }
    const p1 = m.indexOf('.')
    const col = m.slice(0, p1)
    let reste = m.slice(p1 + 1)
    let non = false
    if (reste.startsWith('not.')) { non = true; reste = reste.slice(4) }
    const p2 = reste.indexOf('.')
    const op = p2 > -1 ? reste.slice(0, p2) : reste
    let val: any = p2 > -1 ? reste.slice(p2 + 1) : ''
    if (typeof val === 'string' && val.startsWith('"') && val.endsWith('"') && val.length > 1) val = val.slice(1, -1)
    const s = sqlOperation(schema, table, t, col, op, val, true)
    return non ? `not (${s})` : s
  })
  return morceaux.length ? `(${morceaux.join(` ${logique} `)})` : 'true'
}

// ---------------------------------------------------------------------------
// Constructeur de requête
// ---------------------------------------------------------------------------
interface Etat {
  table: string
  action: 'select' | 'insert' | 'update' | 'upsert' | 'delete'
  select?: string
  filtres: Filtre[]
  /** filtres portant sur une ressource imbriquée : alias -> filtres */
  filtresEmbed: Record<string, Filtre[]>
  ordres: { col: string; asc: boolean; nullsFirst?: boolean; embed?: string }[]
  limite?: number
  decalage?: number
  unique?: 'single' | 'maybeSingle'
  compter?: boolean
  tete?: boolean
  valeurs?: any
  conflit?: string
  ignorerDoublons?: boolean
}

export class Requete implements PromiseLike<any> {
  private e: Etat
  private compteur = 0

  constructor(private schema: Schema, private executer: Executeur, table: string, private apresEcriture?: (table: string) => void) {
    this.e = { table, action: 'select', filtres: [], filtresEmbed: {}, ordres: [] }
  }

  // --- actions -------------------------------------------------------------
  select(cols = '*', opts: { count?: string; head?: boolean } = {}) {
    this.e.select = cols.replace(/\s+/g, ' ').trim() || '*'
    if (opts.count) this.e.compter = true
    if (opts.head) this.e.tete = true
    return this
  }
  insert(valeurs: any) { this.e.action = 'insert'; this.e.valeurs = valeurs; return this }
  update(valeurs: any) { this.e.action = 'update'; this.e.valeurs = valeurs; return this }
  upsert(valeurs: any, opts: { onConflict?: string; ignoreDuplicates?: boolean } = {}) {
    this.e.action = 'upsert'; this.e.valeurs = valeurs
    this.e.conflit = opts.onConflict; this.e.ignorerDoublons = opts.ignoreDuplicates
    return this
  }
  delete() { this.e.action = 'delete'; return this }

  // --- filtres -------------------------------------------------------------
  private ajouter(col: string, op: string, val: any, non = false) {
    const point = col.indexOf('.')
    // "alias.colonne" : filtre sur une ressource imbriquée (sauf chemin JSON).
    if (point > -1 && !col.includes('->')) {
      const alias = col.slice(0, point)
      ;(this.e.filtresEmbed[alias] ||= []).push({ type: 'op', col: col.slice(point + 1), op, val, non })
    }
    else this.e.filtres.push({ type: 'op', col, op, val, non })
    return this
  }
  eq(c: string, v: any) { return this.ajouter(c, 'eq', v) }
  neq(c: string, v: any) { return this.ajouter(c, 'neq', v) }
  gt(c: string, v: any) { return this.ajouter(c, 'gt', v) }
  gte(c: string, v: any) { return this.ajouter(c, 'gte', v) }
  lt(c: string, v: any) { return this.ajouter(c, 'lt', v) }
  lte(c: string, v: any) { return this.ajouter(c, 'lte', v) }
  like(c: string, v: any) { return this.ajouter(c, 'like', v) }
  ilike(c: string, v: any) { return this.ajouter(c, 'ilike', v) }
  is(c: string, v: any) { return this.ajouter(c, 'is', v) }
  in(c: string, v: any[]) { return this.ajouter(c, 'in', v) }
  contains(c: string, v: any) { return this.ajouter(c, 'cs', v) }
  overlaps(c: string, v: any) { return this.ajouter(c, 'ov', v) }
  not(c: string, op: string, v: any) { return this.ajouter(c, op, v, true) }
  filter(c: string, op: string, v: any) {
    if (op.startsWith('not.')) return this.ajouter(c, op.slice(4), v, true)
    return this.ajouter(c, op, v)
  }
  match(obj: Record<string, any>) { for (const [k, v] of Object.entries(obj)) this.eq(k, v); return this }
  or(texte: string, opts: { referencedTable?: string; foreignTable?: string } = {}) {
    const embed = opts.referencedTable || opts.foreignTable
    const f: Filtre = { type: 'brut', logique: 'or', texte }
    if (embed) (this.e.filtresEmbed[embed] ||= []).push(f)
    else this.e.filtres.push(f)
    return this
  }

  // --- tri, pagination, forme du résultat ----------------------------------
  order(col: string, opts: { ascending?: boolean; nullsFirst?: boolean; referencedTable?: string; foreignTable?: string } = {}) {
    this.e.ordres.push({ col, asc: opts.ascending !== false, nullsFirst: opts.nullsFirst, embed: opts.referencedTable || opts.foreignTable })
    return this
  }
  limit(n: number) { this.e.limite = n; return this }
  range(de: number, a: number) { this.e.decalage = de; this.e.limite = a - de + 1; return this }
  single() { this.e.unique = 'single'; return this }
  maybeSingle() { this.e.unique = 'maybeSingle'; return this }
  abortSignal() { return this }
  returns() { return this }
  throwOnError() { return this }

  // --- génération SQL ------------------------------------------------------
  private alias() { return `t${this.compteur++}` }

  private sqlFiltres(table: string, t: string, filtres: Filtre[]): string[] {
    return filtres.map((f) => {
      if (f.type === 'brut') return sqlBrut(this.schema, table, t, f.texte, f.logique)
      const brut = f.non === true && typeof f.val === 'string'
      const s = sqlOperation(this.schema, table, t, f.col, f.op, f.val, brut)
      return f.non ? `not (${s})` : s
    })
  }

  /** Relation entre la table parente et la ressource imbriquée demandée. */
  private relation(parent: string, n: NoeudEmbed): { table: string; versUn: boolean; colParent: string; colEnfant: string } {
    const { fks, colonnes } = this.schema
    // 1. « alias:colonne_fk(...) » : la cible est une colonne de la table parente.
    if (colonnes[parent]?.[n.cible]) {
      const fk = fks.find(f => f.table === parent && f.colonne === n.cible)
      if (fk) return { table: fk.cible, versUn: true, colParent: fk.colonne, colEnfant: fk.cibleColonne }
    }
    // 2. « table(...) » ou « alias:table!indice(...) ».
    const candidats = [
      ...fks.filter(f => f.table === parent && f.cible === n.cible).map(f => ({ table: n.cible, versUn: true, colParent: f.colonne, colEnfant: f.cibleColonne, nom: f.nom, col: f.colonne })),
      ...fks.filter(f => f.table === n.cible && f.cible === parent).map(f => ({ table: n.cible, versUn: false, colParent: f.cibleColonne, colEnfant: f.colonne, nom: f.nom, col: f.colonne })),
    ]
    const choisi = n.indice ? candidats.find(c => c.nom === n.indice || c.col === n.indice) : candidats[0]
    if (!choisi) {
      throw Object.assign(new Error(`Relation introuvable entre ${parent} et ${n.cible}`), { code: 'PGRST200' })
    }
    return choisi
  }

  /** Projection d'un niveau ; ajoute à `existe` les conditions des jointures !inner. */
  private projection(table: string, t: string, noeuds: Noeud[], existe: string[]): string {
    const cols: string[] = []
    for (const n of noeuds) {
      if (n.type === 'col') {
        if (n.expr === '*') { cols.push(`${t}.*`); continue }
        const { sql, nom } = exprColonne(t, n.expr)
        cols.push(`${sql} as ${ident(n.alias || nom)}`)
        continue
      }
      const rel = this.relation(table, n)
      const te = this.alias()
      const lien = `${te}.${ident(rel.colEnfant)} = ${t}.${ident(rel.colParent)}`
      const conds = [lien, ...this.sqlFiltres(rel.table, te, this.e.filtresEmbed[n.alias] || [])]
      const existeEnfant: string[] = []
      const estCompte = n.enfants.length === 1 && n.enfants[0].type === 'col' && n.enfants[0].expr === 'count'
      const source = `public.${ident(rel.table)} ${te}`
      if (estCompte) {
        cols.push(`(select jsonb_build_array(jsonb_build_object('count', count(*))) from ${source} where ${conds.join(' and ')}) as ${ident(n.alias)}`)
      }
      else {
        const proj = this.projection(rel.table, te, n.enfants, existeEnfant)
        const ou = [...conds, ...existeEnfant].join(' and ')
        const tri = this.e.ordres.filter(o => o.embed === n.alias).map(o => this.sqlOrdre(te, o)).join(', ')
        const sous = `select ${proj} from ${source} where ${ou}${tri ? ` order by ${tri}` : ''}`
        cols.push(rel.versUn
          ? `(select to_jsonb(s) from (${sous} limit 1) s) as ${ident(n.alias)}`
          : `(select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb) from (${sous}) s) as ${ident(n.alias)}`)
      }
      if (n.inner) existe.push(`exists (select 1 from ${source} where ${conds.join(' and ')})`)
    }
    return cols.join(', ')
  }

  private sqlOrdre(t: string, o: { col: string; asc: boolean; nullsFirst?: boolean }) {
    const nulls = o.nullsFirst === undefined ? '' : (o.nullsFirst ? ' nulls first' : ' nulls last')
    return `${exprColonne(t, o.col).sql} ${o.asc ? 'asc' : 'desc'}${nulls}`
  }

  private queue(t: string): string {
    const tri = this.e.ordres.filter(o => !o.embed).map(o => this.sqlOrdre(t, o)).join(', ')
    return `${tri ? ` order by ${tri}` : ''}${this.e.limite !== undefined ? ` limit ${Number(this.e.limite)}` : ''}${this.e.decalage ? ` offset ${Number(this.e.decalage)}` : ''}`
  }

  private colonnesValeurs(lignes: any[]): string[] {
    const cles = new Set<string>()
    for (const l of lignes) for (const k of Object.keys(l || {})) cles.add(k)
    return [...cles]
  }

  /** SQL de l'écriture (sans RETURNING). */
  private sqlEcriture(t: string): string {
    const { table, action } = this.e
    const cible = `public.${ident(table)}`
    if (action === 'delete') {
      const ou = this.sqlFiltres(table, t, this.e.filtres)
      return `delete from ${cible} ${t}${ou.length ? ` where ${ou.join(' and ')}` : ''}`
    }
    if (action === 'update') {
      const cols = Object.keys(this.e.valeurs || {})
      if (!cols.length) throw Object.assign(new Error('Aucune colonne à mettre à jour'), { code: 'PGRST100' })
      const ou = this.sqlFiltres(table, t, this.e.filtres)
      return `update ${cible} ${t} set ${cols.map(c => `${ident(c)} = r_.${ident(c)}`).join(', ')} `
        + `from jsonb_populate_record(null::${cible}, ${lit(this.e.valeurs)}::jsonb) r_${ou.length ? ` where ${ou.join(' and ')}` : ''}`
    }
    const lignes = Array.isArray(this.e.valeurs) ? this.e.valeurs : [this.e.valeurs]
    const cols = this.colonnesValeurs(lignes)
    const liste = cols.map(ident).join(', ')
    let sql = cols.length
      ? `insert into ${cible} as ${t} (${liste}) select ${liste} from jsonb_populate_recordset(null::${cible}, ${lit(lignes)}::jsonb)`
      : `insert into ${cible} as ${t} default values`
    if (action === 'upsert') {
      const conflit = (this.e.conflit ? this.e.conflit.split(',').map(x => x.trim()) : this.schema.pks[table] || []).filter(Boolean)
      const maj = cols.filter(c => !conflit.includes(c))
      if (!conflit.length) throw Object.assign(new Error(`upsert sans clé de conflit sur ${table}`), { code: 'PGRST100' })
      sql += ` on conflict (${conflit.map(ident).join(', ')}) `
        + (this.e.ignorerDoublons || !maj.length ? 'do nothing' : `do update set ${maj.map(c => `${ident(c)} = excluded.${ident(c)}`).join(', ')}`)
    }
    return sql
  }

  private async lancer(): Promise<{ data: any; error: ErreurPg | null; count: number | null; status: number; statusText: string }> {
    const { table, action } = this.e
    this.compteur = 0
    const t = this.alias()
    let lignes: any[] | null = null
    let count: number | null = null

    if (action === 'select') {
      const existe: string[] = []
      const proj = this.projection(table, t, analyserSelect(this.e.select || '*'), existe)
      const ou = [...this.sqlFiltres(table, t, this.e.filtres), ...existe]
      const base = `from public.${ident(table)} ${t}${ou.length ? ` where ${ou.join(' and ')}` : ''}`
      if (this.e.compter) {
        const r = await this.executer(`select count(*)::int as n ${base}`)
        count = r[0]?.n ?? 0
      }
      if (!this.e.tete) {
        const r = await this.executer(
          `select coalesce(jsonb_agg(to_jsonb(q_)), '[]'::jsonb) as d from (select ${proj} ${base}${this.queue(t)}) q_`)
        lignes = r[0]?.d ?? []
      }
    }
    else {
      const ecriture = this.sqlEcriture(t)
      if (this.e.select) {
        const proj = this.projection(table, 'm_', analyserSelect(this.e.select), [])
        const r = await this.executer(
          `with m_ as (${ecriture} returning ${t}.*) select coalesce(jsonb_agg(to_jsonb(q_)), '[]'::jsonb) as d from (select ${proj} from m_) q_`)
        lignes = r[0]?.d ?? []
      }
      else await this.executer(ecriture)
      this.apresEcriture?.(table)
    }

    let data: any = lignes
    if (this.e.unique && lignes) {
      if (lignes.length === 1) data = lignes[0]
      else if (lignes.length === 0 && this.e.unique === 'maybeSingle') data = null
      else {
        return {
          data: null, count, status: 406, statusText: 'Not Acceptable',
          error: { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned', details: `The result contains ${lignes.length} rows`, hint: null },
        }
      }
    }
    return { data, error: null, count, status: 200, statusText: 'OK' }
  }

  then<A = any, B = never>(ok?: ((v: any) => A | PromiseLike<A>) | null, ko?: ((r: any) => B | PromiseLike<B>) | null): PromiseLike<A | B> {
    return this.lancer()
      .catch((err: any) => {
        // Trace utile en démo : une requête que le traducteur ne sait pas faire se voit tout de suite.
        console.warn(`[démo] ${this.e.action} ${this.e.table} : ${err?.message || err}`, this.e.select || '')
        return { data: null, count: null, status: 400, statusText: 'Bad Request', error: versErreur(err) }
      })
      .then(ok, ko)
  }
}

export function versErreur(err: any): ErreurPg {
  return {
    message: err?.message || String(err),
    code: err?.code || 'DEMO',
    details: err?.detail ?? err?.details ?? null,
    hint: err?.hint ?? null,
  }
}

// ---------------------------------------------------------------------------
// Appel de fonction (rpc)
// ---------------------------------------------------------------------------
export function sqlRpc(nom: string, args: Record<string, any> = {}): string {
  const params = Object.entries(args)
    .filter(([, v]) => v !== undefined)
    .map(([k, v]) => `${ident(k)} => ${Array.isArray(v) && v.every(x => typeof x !== 'object' || x === null) ? `${litTableau(v)}` : lit(v)}`)
  return `select to_jsonb(f_) as r from public.${ident(nom)}(${params.join(', ')}) f_`
}

// ---------------------------------------------------------------------------
// Lecture du schéma (une fois, à l'ouverture de la base)
// ---------------------------------------------------------------------------
export async function lireSchema(executer: Executeur): Promise<Schema> {
  const cols = await executer(`select table_name t, column_name c, udt_name u from information_schema.columns where table_schema = 'public'`)
  const fks = await executer(`
    select con.conname nom, cl.relname "table", a.attname colonne, cl2.relname cible, a2.attname "cibleColonne"
    from pg_constraint con
    join pg_class cl on cl.oid = con.conrelid
    join pg_namespace n on n.oid = cl.relnamespace and n.nspname = 'public'
    join pg_class cl2 on cl2.oid = con.confrelid
    join pg_attribute a on a.attrelid = con.conrelid and a.attnum = con.conkey[1]
    join pg_attribute a2 on a2.attrelid = con.confrelid and a2.attnum = con.confkey[1]
    where con.contype = 'f' and array_length(con.conkey, 1) = 1`)
  const pks = await executer(`
    select cl.relname t, a.attname c
    from pg_constraint con
    join pg_class cl on cl.oid = con.conrelid
    join pg_namespace n on n.oid = cl.relnamespace and n.nspname = 'public'
    join pg_attribute a on a.attrelid = con.conrelid and a.attnum = any(con.conkey)
    where con.contype = 'p' order by array_position(con.conkey, a.attnum)`)
  const schema: Schema = { colonnes: {}, fks: fks as any, pks: {} }
  for (const r of cols) (schema.colonnes[r.t] ||= {})[r.c] = r.u
  for (const r of pks) (schema.pks[r.t] ||= []).push(r.c)
  return schema
}
