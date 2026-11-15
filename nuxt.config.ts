// https://nuxt.com/docs/api/configuration/nuxt-config
import { fileURLToPath } from 'node:url'

const isProduction = process.env.NODE_ENV === 'production'
const devtoolsEnabled = process.env.NUXT_DEVTOOLS === 'true'
// Build natif Capacitor : SPA statique, sans service worker PWA
// (un SW dans la WebView provoque des caches fantômes après mise à jour d'APK).
const isCapacitor = process.env.CAPACITOR_BUILD === '1'
// Mode démo Field Track : aucune base Supabase. Les données vivent dans une
// base embarquée dans le navigateur (dossier demo/). Voir README-FIELD-TRACK.md.
const isDemo = process.env.FIELD_TRACK_DEMO === '1'
const stubServeurDemo = fileURLToPath(new URL('./demo/server-stub.ts', import.meta.url))

export default defineNuxtConfig({
  // Démo : les données sont dans le navigateur, rien à rendre côté serveur.
  ssr: !isCapacitor && !isDemo,

  // buildDir isolé pour le build natif : évite d'écraser le .nuxt du
  // serveur `nuxt dev` (schéma corrompu si un build APK tourne en parallèle).
  ...(isCapacitor ? { buildDir: '.nuxt-native' } : {}),

  devtools: { enabled: devtoolsEnabled },

  modules: [
    '@nuxt/ui',
    ...(isDemo ? [] : ['@nuxtjs/supabase']),
    '@pinia/nuxt',
    ...(isProduction && !isCapacitor ? ['@vite-pwa/nuxt'] : []),
  ],

  css: ['~/assets/css/main.css'],

  // Mode démo : faux composables Supabase, plugin d'ouverture de la base, et
  // remplaçant de '#supabase/server' pour que les routes serveur compilent.
  ...(isDemo
    ? {
        imports: { dirs: ['demo/composables'] },
        plugins: ['~/demo/plugins/demo.client.ts'],
        alias: { '#supabase/server': stubServeurDemo },
      }
    : {}),

  colorMode: {
    preference: 'light',
    fallback: 'light',
    classSuffix: '',
  },

  supabase: {
    url: process.env.SUPABASE_URL,
    key: process.env.SUPABASE_KEY,
    // Utilisée uniquement par les routes serveur /api/admin/* (bypass RLS).
    // Le module attend SUPABASE_SERVICE_KEY par défaut : on mappe notre variable.
    serviceKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
    redirect: false,
    redirectOptions: {
      login: '/login',
      callback: '/confirm',
      exclude: ['/login'],
    },
    cookieOptions: {
      maxAge: 60 * 60 * 24 * 30, // 30 days
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
    },
    clientOptions: {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
      },
    },
  },

  pinia: {
    storesDirs: ['./stores/**'],
  },

  pwa: {
    registerType: 'autoUpdate',
    manifest: {
      name: 'Field Track',
      short_name: 'Field Track',
      description: 'Application de collecte terrain Field Track',
      theme_color: '#1D4ED8',
      background_color: '#ffffff',
      display: 'standalone',
      orientation: 'portrait',
      start_url: '/',
      icons: [
        { src: '/icons/icon-72x72.png', sizes: '72x72', type: 'image/png' },
        { src: '/icons/icon-96x96.png', sizes: '96x96', type: 'image/png' },
        { src: '/icons/icon-128x128.png', sizes: '128x128', type: 'image/png' },
        { src: '/icons/icon-144x144.png', sizes: '144x144', type: 'image/png' },
        { src: '/icons/icon-152x152.png', sizes: '152x152', type: 'image/png' },
        { src: '/icons/icon-192x192.png', sizes: '192x192', type: 'image/png' },
        { src: '/icons/icon-384x384.png', sizes: '384x384', type: 'image/png' },
        { src: '/icons/icon-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'any maskable' },
      ],
    },
    workbox: {
      navigateFallback: '/',
      // Démo : la base embarquée (wasm, données, extensions) doit aussi être
      // disponible hors ligne.
      globPatterns: [isDemo ? '**/*.{js,css,html,png,svg,ico,woff2,wasm,data,gz}' : '**/*.{js,css,html,png,svg,ico,woff2}'],
      ...(isDemo ? { maximumFileSizeToCacheInBytes: 20 * 1024 * 1024 } : {}),
      // Pas de cache sur /rest/v1 : les réponses dépendent de l'utilisateur
      // (RLS) mais le cache est indexé par URL seule — sur un navigateur
      // partagé, B hors ligne recevait les données de A. Le hors-ligne passe
      // par IndexedDB (useOfflineData). L'ancien cache « supabase-api-cache »
      // est purgé à la déconnexion (stores/auth.ts).
      runtimeCaching: [
        {
          urlPattern: /^https:\/\/[a-z0-9]+\.supabase\.co\/storage\/.*/i,
          handler: 'CacheFirst',
          options: {
            cacheName: 'supabase-storage-cache',
            expiration: { maxEntries: 200, maxAgeSeconds: 60 * 60 * 24 * 30 },
            cacheableResponse: { statuses: [0, 200] },
          },
        },
      ],
    },
    client: {
      installPrompt: true,
    },
    devOptions: {
      enabled: false,
      type: 'module',
    },
  },

  app: {
    head: {
      title: 'Field Track',
      meta: [
        { name: 'description', content: 'Application de collecte terrain Field Track' },
        { name: 'theme-color', content: '#1D4ED8' },
        { name: 'mobile-web-app-capable', content: 'yes' },
        { name: 'apple-mobile-web-app-capable', content: 'yes' },
        { name: 'apple-mobile-web-app-status-bar-style', content: 'black-translucent' },
        { name: 'referrer', content: 'strict-origin-when-cross-origin' },
        // Note: X-Frame-Options / X-Content-Type-Options sont servis en en-têtes HTTP (voir nitro.routeRules)
      ],
      link: [
        { rel: 'icon', type: 'image/png', href: '/favicon.png' },
        { rel: 'apple-touch-icon', href: '/icons/icon-192x192.png' },
      ],
    },
  },

  runtimeConfig: {
    public: {
      // Vrai dans le bundle de l'APK. Connu dès la compilation, donc utilisable
      // au prérendu : un écran réservé au web n'apparaît jamais, même le temps
      // d'une hydratation (voir composables/usePlateforme.ts).
      buildNatif: isCapacitor,
      // Vrai quand l'application tourne sans Supabase, sur la base embarquée.
      modeDemo: isDemo,
      geofenceRadius: 200, // TODO confirmer client (valeur réunion : 200 m)
      gpsMinAccuracy: 10,
      // Précision maximale acceptée pour enregistrer la position d'un PDV sans
      // GPS depuis le terrain (RPC geolocaliser_pdv, même seuil côté base).
      gpsPdvPrecisionMax: 30,
      // Tracking de tournée (app native) : échantillonnage GPS régulier,
      // filtre distance mini entre points, envoi groupé par batch.
      // Intervalle à 2 min = compromis autonomie batterie / finesse du trajet.
      trackingIntervalMs: 120_000,
      trackingDistanceM: 15,
      trackingFlushMs: 5 * 60_000,
      trackingBatchMax: 200,
    },
  },

  // Désactive le manifeste d'app (évite l'erreur dev "#app-manifest" / 404 builds/meta/*.json).
  // L'app n'utilise pas les route rules basées sur le manifeste client.
  experimental: {
    appManifest: false,
  },

  // En-têtes de sécurité servis en HTTP (X-Frame-Options ne fonctionne pas en <meta>).
  nitro: {
    ...(isDemo ? { alias: { '#supabase/server': stubServeurDemo } } : {}),
    routeRules: {
      '/**': {
        headers: {
          'X-Frame-Options': 'DENY',
          'X-Content-Type-Options': 'nosniff',
        },
      },
    },
  },

  // Dossiers hors application, mais présents dans l'arborescence : sans cette
  // exclusion le watcher du serveur de dev ouvre un descripteur par fichier
  // (images-source contient ~47 000 photos AppSheet) et sature la limite macOS
  // par processus → EMFILE, puis "spawn EBADF" sur le pool de forks du CLI.
  ignore: [
    'images-source/**',
    '.claude/worktrees/**',
    'scripts/out/**',
  ],

  watchers: {
    chokidar: {
      ignored: [
        '**/images-source/**',
        '**/.claude/worktrees/**',
        '**/scripts/out/**',
      ],
    },
  },

  vite: {
    // PGlite charge son wasm par URL relative : le pré-bundling de Vite la casse.
    optimizeDeps: { exclude: ['@electric-sql/pglite'] },
    server: {
      watch: {
        ignored: [
          '**/images-source/**',
          '**/.claude/worktrees/**',
          '**/scripts/out/**',
        ],
      },
    },
  },

  compatibilityDate: '2025-01-01',
})
