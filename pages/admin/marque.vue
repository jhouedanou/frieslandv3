<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-gray-900 dark:text-gray-100">Personnalisation</h1>
      <p class="mt-1 max-w-3xl text-sm text-gray-500 dark:text-gray-400">
        Mettez l'application aux couleurs de votre client : son nom, son logo et ses couleurs
        s'affichent sur l'écran de connexion, le tableau de bord et l'application mobile.
        L'aperçu suit vos réglages ; rien n'est appliqué aux autres utilisateurs avant l'enregistrement.
      </p>
    </div>

    <div class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <!-- Réglages -->
      <form class="admin-surface space-y-6 p-5" @submit.prevent="enregistrerMarque">
        <section class="space-y-4">
          <h2 class="text-sm font-bold uppercase tracking-wide text-gray-500 dark:text-gray-400">Nom</h2>
          <UFormGroup label="Nom de l'application" required :error="erreurNom">
            <UInput v-model="brouillon.nom" maxlength="40" placeholder="Ex. Client Force" size="lg" />
          </UFormGroup>
          <UFormGroup label="Sous-titre" help="Une ligne courte sous le nom. Facultatif.">
            <UInput v-model="sousTitre" maxlength="60" placeholder="Ex. Pilotage des équipes terrain" />
          </UFormGroup>
        </section>

        <section class="space-y-3">
          <h2 class="text-sm font-bold uppercase tracking-wide text-gray-500 dark:text-gray-400">Logo</h2>
          <div class="flex flex-wrap items-center gap-4">
            <div class="flex h-20 w-20 items-center justify-center rounded-2xl border border-gray-200 bg-white p-2 dark:border-gray-700">
              <img :src="brouillon.logo_url || logoDefaut" alt="Logo actuel" class="h-full w-full object-contain">
            </div>
            <div class="space-y-2">
              <input ref="champFichier" type="file" accept="image/png,image/jpeg,image/webp,image/svg+xml" class="hidden" @change="choisirLogo">
              <div class="flex flex-wrap gap-2">
                <UButton type="button" color="gray" icon="i-heroicons-arrow-up-tray" :loading="lectureLogo" @click="champFichier?.click()">
                  Choisir un logo
                </UButton>
                <UButton v-if="brouillon.logo_url" type="button" color="gray" variant="ghost" icon="i-heroicons-trash" @click="retirerLogo">
                  Retirer
                </UButton>
              </div>
              <p class="text-xs text-gray-500 dark:text-gray-400">PNG, JPEG, WebP ou SVG. L'image est réduite à 256 pixels avant l'enregistrement.</p>
            </div>
          </div>
          <p v-if="erreurLogo" class="text-sm text-red-600 dark:text-red-400">{{ erreurLogo }}</p>
          <div v-if="couleursLogo.length" class="rounded-xl bg-gray-50 p-3 dark:bg-gray-700/40">
            <p class="text-xs font-semibold text-gray-700 dark:text-gray-200">Couleurs trouvées dans le logo</p>
            <div class="mt-2 flex flex-wrap items-center gap-3">
              <span v-for="c in couleursLogo" :key="c" class="inline-flex items-center gap-1.5 text-xs text-gray-600 dark:text-gray-300">
                <span class="h-5 w-5 rounded-full border border-black/10" :style="{ background: c }" />{{ c }}
              </span>
              <UButton type="button" size="xs" color="gray" icon="i-heroicons-swatch" @click="reprendreCouleursLogo">
                Utiliser ces couleurs
              </UButton>
            </div>
          </div>
        </section>

        <section class="space-y-4">
          <h2 class="text-sm font-bold uppercase tracking-wide text-gray-500 dark:text-gray-400">Couleurs</h2>
          <div class="grid gap-4 sm:grid-cols-2">
            <UFormGroup label="Couleur principale" help="Boutons, menus, graphiques.">
              <div class="flex items-center gap-2">
                <input v-model="brouillon.couleur_principale" type="color" class="h-10 w-12 cursor-pointer rounded border border-gray-300 bg-white p-0.5 dark:border-gray-600" aria-label="Couleur principale">
                <UInput v-model="brouillon.couleur_principale" maxlength="7" class="flex-1 font-mono" />
              </div>
            </UFormGroup>
            <UFormGroup label="Couleur secondaire" help="Fin des dégradés, teintes foncées.">
              <div class="flex items-center gap-2">
                <input v-model="brouillon.couleur_secondaire" type="color" class="h-10 w-12 cursor-pointer rounded border border-gray-300 bg-white p-0.5 dark:border-gray-600" aria-label="Couleur secondaire">
                <UInput v-model="brouillon.couleur_secondaire" maxlength="7" class="flex-1 font-mono" />
              </div>
            </UFormGroup>
          </div>
          <p v-if="erreurCouleur" class="text-sm text-red-600 dark:text-red-400">{{ erreurCouleur }}</p>
          <p v-else-if="alerteContraste" class="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-800 dark:bg-amber-900/30 dark:text-amber-200">
            {{ alerteContraste }}
          </p>
          <div class="flex overflow-hidden rounded-lg border border-gray-200 dark:border-gray-700" aria-hidden="true">
            <span v-for="n in NIVEAUX_PALETTE" :key="n" class="h-6 flex-1" :style="{ background: `rgb(${palette[n]})` }" />
          </div>
        </section>

        <div class="flex flex-wrap items-center gap-3 border-t border-gray-100 pt-4 dark:border-gray-700">
          <UButton type="submit" class="bg-fc-red hover:bg-fc-red-600" :loading="enregistrement" :disabled="!valide || !modifie">
            Enregistrer
          </UButton>
          <UButton type="button" color="gray" variant="ghost" :disabled="!modifie || enregistrement" @click="annuler">
            Annuler les changements
          </UButton>
          <UButton type="button" color="gray" variant="ghost" icon="i-heroicons-arrow-uturn-left" :disabled="enregistrement" @click="revenirParDefaut">
            Revenir à Big Five Force
          </UButton>
        </div>
        <p v-if="confirmation" class="rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-200" role="status">
          {{ confirmation }}
        </p>
        <p v-if="erreurEnregistrement" class="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-900/30 dark:text-red-300" role="alert">
          {{ erreurEnregistrement }}
        </p>
      </form>

      <!-- Aperçu -->
      <section class="admin-surface space-y-4 p-5" aria-label="Aperçu">
        <h2 class="text-sm font-bold uppercase tracking-wide text-gray-500 dark:text-gray-400">Aperçu</h2>

        <div class="overflow-hidden rounded-2xl border border-gray-200 dark:border-gray-700">
          <div class="flex flex-col items-center bg-gradient-to-br from-fc-red to-fc-red-700 px-6 py-8 text-center">
            <div class="mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-white p-1.5 shadow-lg">
              <img :src="brouillon.logo_url || logoDefaut" alt="" class="h-full w-full object-contain">
            </div>
            <p class="text-2xl font-bold text-white">{{ brouillon.nom || 'Nom de l\'application' }}</p>
            <p v-if="sousTitre" class="mt-1 text-sm text-fc-red-200">{{ sousTitre }}</p>
          </div>
          <div class="space-y-3 bg-white p-4 dark:bg-gray-800">
            <p class="text-xs font-semibold uppercase tracking-wide text-gray-400">Écran de connexion</p>
            <span class="block rounded-lg bg-fc-red px-4 py-2.5 text-center text-sm font-semibold text-white">Se connecter</span>
          </div>
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <div class="rounded-2xl border border-gray-200 p-3 dark:border-gray-700">
            <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-400">Menu</p>
            <div class="flex items-center gap-2">
              <span class="flex h-9 w-9 items-center justify-center rounded-lg border border-fc-red-100 bg-white p-1">
                <img :src="brouillon.logo_url || logoDefaut" alt="" class="h-full w-full object-contain">
              </span>
              <span class="min-w-0">
                <span class="block truncate text-sm font-bold text-gray-900 dark:text-white">{{ brouillon.nom }}</span>
                <span class="block truncate text-[10px] font-semibold uppercase text-fc-red">{{ sousTitre }}</span>
              </span>
            </div>
            <span class="mt-3 block rounded-lg bg-fc-red-50 px-3 py-2 text-sm font-semibold text-fc-red">Conformité</span>
            <span class="mt-1 block px-3 py-2 text-sm text-gray-600 dark:text-gray-300">Visites</span>
          </div>
          <div class="overflow-hidden rounded-2xl border border-gray-200 dark:border-gray-700">
            <div class="flex items-center gap-2 bg-fc-red px-3 py-2.5">
              <img :src="brouillon.logo_url || logoDefaut" alt="" class="h-6 w-6 rounded bg-white/90 object-contain p-0.5">
              <span class="truncate text-sm font-semibold text-white">Visites</span>
            </div>
            <div class="space-y-2 bg-white p-3 dark:bg-gray-800">
              <p class="text-xs font-semibold uppercase tracking-wide text-gray-400">Application mobile</p>
              <span class="inline-block rounded-lg bg-fc-red px-3 py-1.5 text-xs font-semibold text-white">+ Nouvelle visite</span>
            </div>
          </div>
        </div>

        <p class="text-xs text-gray-500 dark:text-gray-400">
          Le nom et l'icône de l'application installée sur un téléphone ne changent pas ici :
          ils sont fixés au moment où l'application est construite.
        </p>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import logoDefaut from '~/assets/logo.png'
import {
  MARQUE_DEFAUT, NIVEAUX_PALETTE, contrasteAvecBlanc, couleursDominantes, estCouleurHex,
  luminance, normaliserMarque, paletteMarque, type Marque,
} from '~/utils/marque'

// Réglage réservé aux administrateurs (la base refuse aussi l'écriture aux autres rôles).
definePageMeta({
  layout: 'admin',
  middleware: [
    'auth',
    'admin',
    () => {
      const authStore = useAuthStore()
      if (!authStore.isAdmin) return navigateTo('/admin')
    },
  ],
})

const { marque, enregistrer, previsualiser } = useMarque()

// Réglage enregistré, pour annuler et pour savoir s'il y a des changements.
const enregistree = ref<Marque>({ ...marque.value })
const brouillon = reactive<Marque>({ ...marque.value })
const sousTitre = computed({
  get: () => brouillon.sous_titre || '',
  set: (v: string) => { brouillon.sous_titre = v },
})

const champFichier = ref<HTMLInputElement | null>(null)
const lectureLogo = ref(false)
const erreurLogo = ref('')
const couleursLogo = ref<string[]>([])
const enregistrement = ref(false)
// Message affiché dans la page : l'application n'a pas de zone de notification.
const confirmation = ref('')
const erreurEnregistrement = ref('')

const erreurNom = computed(() => (brouillon.nom.trim() ? '' : 'Le nom est obligatoire.'))
const erreurCouleur = computed(() =>
  estCouleurHex(brouillon.couleur_principale) && estCouleurHex(brouillon.couleur_secondaire)
    ? ''
    : 'Une couleur s\'écrit avec # suivi de 6 chiffres ou lettres de A à F, par exemple #603080.')
const valide = computed(() => !erreurNom.value && !erreurCouleur.value)
const modifie = computed(() => JSON.stringify(normaliserMarque(brouillon)) !== JSON.stringify(normaliserMarque(enregistree.value)))
const palette = computed(() => paletteMarque(brouillon.couleur_principale, brouillon.couleur_secondaire))
const alerteContraste = computed(() => {
  if (!estCouleurHex(brouillon.couleur_principale)) return ''
  return contrasteAvecBlanc(brouillon.couleur_principale) < 3
    ? 'Cette couleur principale est claire : le texte blanc des boutons sera difficile à lire. Choisissez une teinte plus foncée.'
    : ''
})

// L'aperçu et toute la page suivent le brouillon, sans rien enregistrer.
watch(brouillon, () => {
  confirmation.value = ''
  if (valide.value) previsualiser({ ...brouillon })
}, { deep: true })

// En quittant la page sans enregistrer, on revient au réglage en vigueur.
onBeforeUnmount(() => previsualiser(enregistree.value))

function chargerImage(src: string): Promise<HTMLImageElement> {
  return new Promise((ok, ko) => {
    const img = new Image()
    img.onload = () => ok(img)
    img.onerror = () => ko(new Error('image illisible'))
    img.src = src
  })
}

async function choisirLogo(e: Event) {
  const fichier = (e.target as HTMLInputElement).files?.[0]
  ;(e.target as HTMLInputElement).value = ''
  if (!fichier) return
  erreurLogo.value = ''
  if (fichier.size > 5 * 1024 * 1024) {
    erreurLogo.value = 'Ce fichier dépasse 5 Mo. Choisissez une image plus légère.'
    return
  }
  lectureLogo.value = true
  try {
    const source = await new Promise<string>((ok, ko) => {
      const lecteur = new FileReader()
      lecteur.onload = () => ok(String(lecteur.result))
      lecteur.onerror = () => ko(lecteur.error)
      lecteur.readAsDataURL(fichier)
    })
    const img = await chargerImage(source)
    // Réduction à 256 px de côté au plus, en PNG (fond transparent conservé).
    const cote = 256
    const echelle = Math.min(1, cote / Math.max(img.naturalWidth || cote, img.naturalHeight || cote))
    const largeur = Math.max(1, Math.round((img.naturalWidth || cote) * echelle))
    const hauteur = Math.max(1, Math.round((img.naturalHeight || cote) * echelle))
    const canvas = document.createElement('canvas')
    canvas.width = largeur
    canvas.height = hauteur
    const ctx = canvas.getContext('2d')!
    ctx.drawImage(img, 0, 0, largeur, hauteur)
    brouillon.logo_url = canvas.toDataURL('image/png')
    couleursLogo.value = couleursDominantes(ctx.getImageData(0, 0, largeur, hauteur).data)
  }
  catch {
    erreurLogo.value = 'Ce fichier n\'a pas pu être lu comme une image. Essayez un PNG ou un JPEG.'
  }
  finally {
    lectureLogo.value = false
  }
}

function retirerLogo() {
  brouillon.logo_url = null
  couleursLogo.value = []
}

function reprendreCouleursLogo() {
  const [a, b] = couleursLogo.value
  if (!a) return
  brouillon.couleur_principale = a
  // La secondaire sert aux teintes foncées : on ne prend la deuxième couleur du
  // logo que si elle est au moins aussi sombre ; sinon, une version foncée de la première.
  const foncee = `#${paletteMarque(a)[700].split(' ').map(x => Number(x).toString(16).padStart(2, '0')).join('')}`.toUpperCase()
  brouillon.couleur_secondaire = b && luminance(b) <= luminance(a) * 1.15 ? b : foncee
}

function annuler() {
  Object.assign(brouillon, enregistree.value)
  couleursLogo.value = []
}

function revenirParDefaut() {
  Object.assign(brouillon, MARQUE_DEFAUT)
  couleursLogo.value = []
}

async function enregistrerMarque() {
  if (!valide.value) return
  enregistrement.value = true
  confirmation.value = ''
  erreurEnregistrement.value = ''
  try {
    await enregistrer({ ...brouillon, nom: brouillon.nom.trim() })
    enregistree.value = { ...marque.value }
    Object.assign(brouillon, marque.value)
    await nextTick()
    confirmation.value = 'Personnalisation enregistrée. Les autres utilisateurs la verront à leur prochaine ouverture.'
  }
  catch (err: any) {
    erreurEnregistrement.value = `Enregistrement impossible : ${err?.message || 'réessayez dans un instant.'}`
  }
  finally {
    enregistrement.value = false
  }
}
</script>
