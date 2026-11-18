// demo/composables/supabase.ts
// Mode démo : remplace les composables du module @nuxtjs/supabase. Les écrans
// continuent d'appeler useSupabaseClient() / useSupabaseUser() sans rien savoir.
import { creerClientDemo, type ClientDemo, type UtilisateurDemo } from '../client'
import { ouvrirBase } from '../db'
import seed from '../seed.sql?raw'

const CLE_SESSION = 'field-track-demo-session'
let client: ClientDemo | null = null

function fichierVersUrl(fichier: Blob): Promise<string> {
  return new Promise((ok, ko) => {
    const lecteur = new FileReader()
    lecteur.onload = () => ok(String(lecteur.result))
    lecteur.onerror = () => ko(lecteur.error)
    lecteur.readAsDataURL(fichier)
  })
}

export function clientDemo(): ClientDemo {
  if (!client) {
    client = creerClientDemo({
      base: ouvrirBase(seed, 'idb') as any,
      lireSessionId: () => { try { return localStorage.getItem(CLE_SESSION) } catch { return null } },
      ecrireSessionId: (id) => {
        try { id ? localStorage.setItem(CLE_SESSION, id) : localStorage.removeItem(CLE_SESSION) } catch { /* stockage indisponible */ }
      },
      fichierVersUrl,
    })
  }
  return client
}

export const useSupabaseClient = () => clientDemo() as any
export const useSupabaseUser = () => useState<UtilisateurDemo | null>('supabase_user', () => null)
export const useSupabaseSession = () => useState<any>('supabase_session', () => null)
