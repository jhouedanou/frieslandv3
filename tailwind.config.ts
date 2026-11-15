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
          50: '#EFF6FF',
          100: '#DBEAFE',
          200: '#BFDBFE',
          300: '#93C5FD',
          400: '#3B82F6',
          500: '#1D4ED8',
          600: '#1E40AF',
          700: '#1E3A8A',
          800: '#172554',
          900: '#0B1535',
          DEFAULT: '#1D4ED8',
        },
        'fc-red': {
          50: '#EFF6FF',
          100: '#DBEAFE',
          200: '#BFDBFE',
          300: '#93C5FD',
          400: '#3B82F6',
          500: '#1D4ED8',
          600: '#1E40AF',
          700: '#1E3A8A',
          800: '#172554',
          900: '#0B1535',
          DEFAULT: '#1D4ED8',
        },
      },
      fontFamily: {
        sans: ['"Nunito Sans Variable"', 'ui-sans-serif', 'system-ui', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
