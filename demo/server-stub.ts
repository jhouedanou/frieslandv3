// demo/server-stub.ts
// Mode démo : le module @nuxtjs/supabase n'est pas chargé. Les routes serveur
// qui l'importent doivent quand même compiler ; elles ne sont jamais appelées
// (demo/api.ts les remplace dans le navigateur).
const indisponible = (): never => {
  throw new Error('Supabase indisponible : application lancée en mode démo')
}
export const serverSupabaseUser = async (_event?: unknown) => indisponible()
export const serverSupabaseServiceRole = (_event?: unknown) => indisponible()
export const serverSupabaseClient = async (_event?: unknown) => indisponible()
export const serverSupabaseSession = async (_event?: unknown) => indisponible()
