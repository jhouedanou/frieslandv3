import type { Config } from 'tailwindcss'

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
        'fc-blue': {
          50: '#F4EEF8',
          100: '#E6D9F0',
          200: '#CDB3E1',
          300: '#A983CB',
          400: '#8251B0',
          500: '#603080',
          600: '#4D2668',
          700: '#403080',
          800: '#2A1F55',
          900: '#16102E',
          DEFAULT: '#603080',
        },
        'fc-red': {
          50: '#F4EEF8',
          100: '#E6D9F0',
          200: '#CDB3E1',
          300: '#A983CB',
          400: '#8251B0',
          500: '#603080',
          600: '#4D2668',
          700: '#403080',
          800: '#2A1F55',
          900: '#16102E',
          DEFAULT: '#603080',
        },
      },
      fontFamily: {
        sans: ['"Nunito Sans Variable"', 'ui-sans-serif', 'system-ui', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
