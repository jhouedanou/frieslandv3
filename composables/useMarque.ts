// composables/useMarque.ts
// Marque affichée par l'application : nom, sous-titre, logo et couleurs.
// Réglée par un administrateur dans Paramètres > Personnalisation, lue par
// tous les écrans (y compris la connexion, avant toute session).
import logoDefaut from '~/assets/logo.png'
import { MARQUE_DEFAUT, NIVEAUX_PALETTE, definirCouleurMarque, normaliserMarque, paletteMarque, type Marque } from '~/utils/marque'

const CLE_CACHE = 'marque-app'

/** Pose la palette sur la page : toutes les classes de marque suivent aussitôt. */
function appliquer(m: Marque) {
  definirCouleurMarque(m.couleur_principale)
  if (!import.meta.client) return
  const palette = paletteMarque(m.couleur_principale, m.couleur_secondaire)
  const style = document.documentElement.style
  for (const n of NIVEAUX_PALETTE) style.setProperty(`--marque-${n}`, palette[n])
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', m.couleur_principale)
}

export function useMarque() {
  const marque = useState<Marque>('marque', () => ({ ...MARQUE_DEFAUT }))
  const logo = computed(() => marque.value.logo_url || logoDefaut)

  function poser(m: Partial<Marque> | null | undefined, memoriser = true) {
    marque.value = normaliserMarque(m)
    appliquer(marque.value)
    if (memoriser && import.meta.client) {
      try { localStorage.setItem(CLE_CACHE, JSON.stringify(marque.value)) } catch { /* stockage plein ou indisponible */ }
    }
  }

  /** Affichage immédiat depuis le dernier réglage connu, puis lecture en base. */
  async function charger() {
    if (import.meta.client) {
      try {
        const cache = localStorage.getItem(CLE_CACHE)
        if (cache) poser(JSON.parse(cache), false)
        else appliquer(marque.value)
      }
      catch { appliquer(marque.value) }
    }
    try {
      const { data, error } = await (useSupabaseClient().from('parametre_marque') as any)
        .select('nom, sous_titre, logo_url, couleur_principale, couleur_secondaire')
        .eq('id', 1)
        .maybeSingle()
      // Table absente (migration non jouée) ou hors ligne : on garde le réglage connu.
      if (!error && data) poser(data)
    }
    catch { /* hors ligne */ }
  }

  /** Enregistre le réglage (administrateur seulement, vérifié par la base). */
  async function enregistrer(m: Marque) {
    const propre = normaliserMarque(m)
    const { error } = await (useSupabaseClient().from('parametre_marque') as any)
      .upsert({ id: 1, ...propre, maj_le: new Date().toISOString() }, { onConflict: 'id' })
    if (error) throw new Error(error.message)
    poser(propre)
  }

  /** Aperçu sans enregistrer (écran de personnalisation). */
  const previsualiser = (m: Marque) => poser(m, false)

  return { marque, logo, charger, enregistrer, previsualiser, MARQUE_DEFAUT }
}
