import type { Config } from 'tailwindcss'

const teinte = (n: number) => `rgb(var(--marque-${n}) / <alpha-value>)`
const paletteMarque = {
  50: teinte(50), 100: teinte(100), 200: teinte(200), 300: teinte(300), 400: teinte(400),
  500: teinte(500), 600: teinte(600), 700: teinte(700), 800: teinte(800), 900: teinte(900),
  DEFAULT: teinte(500),
}

export default <Config>{
  darkMode: 'class',
  content: [
    './components/**/*.{vue,js,ts}',
    './layouts/**/*.vue',
    './pages/**/*.vue',
    './composables/**/*.{js,ts}',
    './plugins/**/*.{js,ts}',
    './app.vue',
    // Nuxt UI runtime : ses classes (ps-*, pe-*, start-0, end-0, inset-y-0…)
    // ne sont générées que si Tailwind scanne ses fichiers. Sans ça, les icônes
    // des UInput sortent du champ et les paddings de positionnement disparaissent.
    './node_modules/@nuxt/ui/dist/runtime/**/*.{vue,mjs,js,ts}',
  ],
  theme: {
    extend: {
      colors: {
        // Couleur de marque : variables CSS posées par composables/useMarque.ts
        // (valeurs par défaut dans assets/css/main.css). Les deux noms sont
        // historiques et désignent la même palette.
        'fc-blue': paletteMarque,
        'fc-red': paletteMarque,
      },
      fontFamily: {
        sans: ['"Nunito Sans Variable"', 'ui-sans-serif', 'system-ui', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
