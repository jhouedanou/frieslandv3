// demo/plugins/demo.client.ts
// Mode démo : ouvre la base embarquée avant le premier écran, reprend la
// session mémorisée, et redirige les appels /api/* vers demo/api.ts.
import { appelerApiDemo } from '../api'
import { clientDemo } from '../composables/supabase'

export default defineNuxtPlugin({
  name: 'field-track-demo',
  enforce: 'pre',
  async setup() {
    const client = clientDemo()
    const utilisateur = useSupabaseUser()
    const session = useSupabaseSession()

    client.auth.onAuthStateChange((_evenement, s) => {
      utilisateur.value = s?.user ?? null
      session.value = s
    })

    try {
      await client.pret
    }
    catch (err) {
      console.error('[démo] ouverture de la base impossible', err)
    }
    utilisateur.value = client.sessionCourante()?.user ?? null
    session.value = client.sessionCourante()

    const origine: any = globalThis.$fetch
    const fetchDemo = (requete: any, options?: any) =>
      typeof requete === 'string' && requete.startsWith('/api/')
        ? appelerApiDemo(client, requete, options)
        : origine(requete, options)
    ;(globalThis as any).$fetch = Object.assign(fetchDemo, origine)
  },
})
