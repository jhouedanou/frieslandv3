<template>
  <div class="min-h-screen flex overflow-y-auto" @focusin="scrollIntoView">
    <!-- Left Panel - Branding -->
    <div class="hidden lg:flex lg:w-1/2 bg-gradient-to-br from-fc-red to-fc-red-700 relative overflow-hidden">
      <div class="absolute inset-0 opacity-10">
        <div class="absolute -top-20 -right-20 w-96 h-96 bg-white dark:bg-gray-800 rounded-full" />
        <div class="absolute -bottom-32 -left-32 w-[500px] h-[500px] bg-white dark:bg-gray-800 rounded-full" />
      </div>
      <div class="relative z-10 flex flex-col items-center justify-center w-full px-12">
        <div class="w-24 h-24 bg-white dark:bg-gray-800 rounded-2xl flex items-center justify-center mb-8 shadow-xl p-2">
          <img src="~/assets/logo.png" alt="Big Five Force" class="w-full h-full object-contain" />
        </div>
        <h1 class="text-4xl font-bold text-white mb-3">Big Five Force</h1>
        <h2 class="text-xl text-purple-200 mb-6">La force de vente maîtrisée</h2>
        <p class="text-purple-100 text-center max-w-sm leading-relaxed">
          Application de collecte de données terrain et de pilotage pour vos équipes commerciales.
        </p>
      </div>
    </div>

    <!-- Right Panel - Login Form -->
    <div class="w-full lg:w-1/2 flex items-center justify-center px-6 py-12 bg-gray-50 dark:bg-gray-900 transition-colors">
      <div class="w-full max-w-md">
        <!-- Mobile logo -->
        <div class="lg:hidden flex flex-col items-center mb-10">
          <div class="w-16 h-16 bg-white dark:bg-gray-800 rounded-xl flex items-center justify-center mb-4 shadow-sm p-1">
            <img src="~/assets/logo.png" alt="Big Five Force" class="w-full h-full object-contain" />
          </div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-gray-100">Big Five Force</h1>
          <p class="text-gray-500 dark:text-gray-400 text-sm">La force de vente maîtrisée</p>
        </div>

        <div class="bg-white dark:bg-gray-800 rounded-2xl shadow-sm border border-gray-100 dark:border-gray-700 p-8">
          <h2 class="text-2xl font-bold text-gray-900 dark:text-gray-100 mb-1">Connexion</h2>
          <p class="text-gray-500 dark:text-gray-400 text-sm mb-8">Entrez vos identifiants pour accéder à l'application</p>

          <form @submit.prevent="handleLogin">
            <div class="space-y-5">
              <UFormGroup label="Email" required>
                <UInput
                  v-model="email"
                  type="email"
                  placeholder="nom@entreprise.com"
                  size="lg"
                  icon="i-heroicons-envelope"
                  :disabled="loading"
                />
              </UFormGroup>

              <UFormGroup label="Mot de passe" required>
                <UInput
                  v-model="password"
                  :type="showPassword ? 'text' : 'password'"
                  placeholder="••••••••"
                  size="lg"
                  icon="i-heroicons-lock-closed"
                  :disabled="loading"
                  :ui="{ icon: { trailing: { pointer: '' } } }"
                >
                  <template #trailing>
                    <button
                      type="button"
                      class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                      @click="showPassword = !showPassword"
                    >
                      <UIcon :name="showPassword ? 'i-heroicons-eye-slash' : 'i-heroicons-eye'" class="w-5 h-5" />
                    </button>
                  </template>
                </UInput>
              </UFormGroup>

              <!-- Error Message -->
              <div
                v-if="errorMessage"
                class="bg-red-50 dark:bg-red-900/30 border border-red-200 dark:border-red-800 text-red-700 dark:text-red-400 px-4 py-3 rounded-lg text-sm flex items-center gap-2"
              >
                <UIcon name="i-heroicons-exclamation-triangle" class="w-5 h-5 text-red-500 flex-shrink-0" />
                {{ errorMessage }}
              </div>

              <UButton
                type="submit"
                block
                size="lg"
                :loading="loading"
                class="bg-fc-red hover:bg-fc-red-600"
              >
                Se connecter
              </UButton>
            </div>
          </form>
        </div>

        <!-- Mode démo : comptes fictifs, connexion en un clic -->
        <div v-if="modeDemo" class="mt-5 rounded-2xl border border-purple-100 bg-white p-5 shadow-sm dark:border-purple-900/40 dark:bg-gray-800">
          <div class="flex items-center justify-between gap-3">
            <h3 class="text-sm font-bold text-gray-900 dark:text-gray-100">Comptes de démonstration</h3>
            <span class="rounded-full bg-purple-50 px-2 py-0.5 text-[11px] font-semibold text-fc-red dark:bg-purple-950/40 dark:text-purple-200">Mode démo</span>
          </div>
          <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
            Données fictives, enregistrées sur cet appareil seulement. Mot de passe commun :
            <code class="font-semibold text-gray-700 dark:text-gray-200">{{ MOT_DE_PASSE_DEMO }}</code>
          </p>
          <div class="mt-3 grid gap-2 sm:grid-cols-2">
            <button
              v-for="c in COMPTES_DEMO"
              :key="c.email"
              type="button"
              class="touch-target rounded-xl border border-gray-200 px-3 py-2 text-left transition hover:border-fc-red hover:bg-purple-50 disabled:opacity-50 dark:border-gray-700 dark:hover:bg-purple-950/30"
              :disabled="loading"
              @click="connexionDemo(c.email)"
            >
              <span class="block text-sm font-semibold text-gray-900 dark:text-gray-100">{{ c.nom }}</span>
              <span class="block text-xs text-gray-500 dark:text-gray-400">{{ libelleRole(c.role) }} · {{ c.detail }}</span>
            </button>
          </div>
          <button
            type="button"
            class="mt-3 text-xs text-gray-500 underline hover:text-gray-700 dark:text-gray-400"
            :disabled="loading"
            @click="reinitialiserDemo"
          >
            Remettre les données de démonstration à zéro
          </button>
        </div>

        <p class="text-center text-xs text-gray-400 dark:text-gray-500 dark:text-gray-400 mt-6">
          Big Five Force © {{ new Date().getFullYear() }} ·
          <NuxtLink to="/politique-de-confidentialite" class="underline hover:text-gray-600">Politique de confidentialité</NuxtLink> ·
          <NuxtLink to="/suppression-de-compte" class="underline hover:text-gray-600">Supprimer mon compte</NuxtLink>
        </p>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { COMPTES_DEMO, MOT_DE_PASSE_DEMO } from '~/demo/comptes'
import { homePathForRole } from '~/utils/roles'
definePageMeta({ layout: false })

// Mode démo (FIELD_TRACK_DEMO=1) : aucune base distante, comptes fictifs.
const modeDemo = useRuntimeConfig().public.modeDemo as boolean
const libelleRole = (role: string) => ({ admin: 'Administrateur', commercial: 'Commercial', merchandiser: 'Merchandiser' }[role] || role)

function connexionDemo(compte: string) {
  email.value = compte
  password.value = MOT_DE_PASSE_DEMO
  return handleLogin()
}

async function reinitialiserDemo() {
  if (!window.confirm('Effacer toutes les saisies faites sur cet appareil et revenir aux données de départ ?')) return
  const { effacerBases } = await import('~/demo/db')
  try { localStorage.removeItem('field-track-demo-session') } catch { /* stockage indisponible */ }
  await effacerBases()
  window.location.reload()
}

const authStore = useAuthStore()
const router = useRouter()

// Android : le clavier réduit la fenêtre (adjustResize) ; on ramène le champ
// actif au-dessus du clavier, sinon le mot de passe reste caché.
function scrollIntoView(e: FocusEvent) {
  const el = e.target as HTMLElement | null
  if (!el || !['INPUT', 'TEXTAREA'].includes(el.tagName)) return
  setTimeout(() => el.scrollIntoView({ block: 'center', behavior: 'smooth' }), 250)
}

const email = ref('')
const password = ref('')
const showPassword = ref(false)
const loading = ref(false)
const errorMessage = ref('')

// Redirect if already logged in
watch(() => authStore.isAuthenticated, async (isAuth) => {
  if (!isAuth) {
    return
  }

  if (!authStore.profile) {
    await authStore.fetchProfile()
  }

  const redirect = homePathForRole(authStore.profile?.role)
  router.push(redirect)
}, { immediate: true })

async function handleLogin() {
  if (!email.value || !password.value) {
    errorMessage.value = 'Veuillez remplir tous les champs'
    return
  }

  loading.value = true
  errorMessage.value = ''

  try {
    await authStore.login(email.value, password.value)

    // Récupérer la géolocalisation de l'utilisateur après connexion
    const { initialize: initGeo } = useUserGeolocation()
    initGeo()

    // Wait for profile to load
    await nextTick()
    const redirect = homePathForRole(authStore.profile?.role)
    router.push(redirect)
  }
  catch (err: any) {
    errorMessage.value = authStore.error || 'Erreur de connexion'
  }
  finally {
    loading.value = false
  }
}
</script>
