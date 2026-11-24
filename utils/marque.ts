// utils/marque.ts
// Personnalisation de la marque (nom, logo, couleurs) depuis l'écran
// Paramètres > Personnalisation. Fonctions pures : la palette complète se
// déduit de deux couleurs, et s'applique par variables CSS (--marque-50…900)
// lues par Tailwind (classes fc-red-*).

export interface Marque {
  nom: string
  sous_titre: string | null
  /** Image en « data: » (redimensionnée avant enregistrement), ou null = logo par défaut. */
  logo_url: string | null
  couleur_principale: string
  couleur_secondaire: string
}

export const MARQUE_DEFAUT: Marque = {
  nom: 'Big Five Force',
  sous_titre: 'La force de vente maîtrisée',
  logo_url: null,
  couleur_principale: '#603080',
  couleur_secondaire: '#403080',
}

// Couleur principale en cours, pour le code qui ne passe pas par le CSS
// (graphiques sur canvas, tracés de carte). Mise à jour par useMarque.
let couleurCourante = MARQUE_DEFAUT.couleur_principale
export function definirCouleurMarque(hex: string) {
  if (estCouleurHex(hex)) couleurCourante = hex
}
/** Couleur de marque : « #RRGGBB », ou « rgba(…) » si une opacité est donnée. */
export function couleurMarque(opacite?: number): string {
  if (opacite === undefined) return couleurCourante
  return `rgba(${hexVersRvb(couleurCourante).join(',')}, ${opacite})`
}

export const NIVEAUX_PALETTE = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900] as const
type Rvb = [number, number, number]

export function estCouleurHex(v: unknown): v is string {
  return typeof v === 'string' && /^#[0-9a-f]{6}$/i.test(v)
}

export function hexVersRvb(hex: string): Rvb {
  const n = Number.parseInt(hex.slice(1), 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

export function rvbVersHex([r, v, b]: Rvb): string {
  return `#${[r, v, b].map(x => Math.max(0, Math.min(255, Math.round(x))).toString(16).padStart(2, '0')).join('')}`.toUpperCase()
}

const melanger = (a: Rvb, b: Rvb, part: number): Rvb => [0, 1, 2].map(i => a[i] + (b[i] - a[i]) * part) as Rvb
const BLANC: Rvb = [255, 255, 255]
const NOIR: Rvb = [0, 0, 0]

/**
 * Palette complète à partir de la couleur principale (niveau 500) et de la
 * secondaire (niveau 700, fin des dégradés). Valeurs « r v b » prêtes pour
 * `rgb(var(--marque-500) / <alpha>)`.
 */
export function paletteMarque(principale: string, secondaire?: string | null): Record<number, string> {
  const base = hexVersRvb(estCouleurHex(principale) ? principale : MARQUE_DEFAUT.couleur_principale)
  const fonce = estCouleurHex(secondaire) ? hexVersRvb(secondaire) : melanger(base, NOIR, 0.34)
  const teintes: Record<number, Rvb> = {
    50: melanger(base, BLANC, 0.93),
    100: melanger(base, BLANC, 0.84),
    200: melanger(base, BLANC, 0.66),
    300: melanger(base, BLANC, 0.42),
    400: melanger(base, BLANC, 0.2),
    500: base,
    600: melanger(base, NOIR, 0.2),
    700: fonce,
    800: melanger(fonce, NOIR, 0.38),
    900: melanger(fonce, NOIR, 0.68),
  }
  return Object.fromEntries(Object.entries(teintes).map(([k, v]) => [k, v.map(Math.round).join(' ')]))
}

/** Luminance relative (WCAG), de 0 (noir) à 1 (blanc). */
export function luminance(hex: string): number {
  const [r, v, b] = hexVersRvb(hex).map((c) => {
    const s = c / 255
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * r + 0.7152 * v + 0.0722 * b
}

/** Contraste d'un texte blanc sur cette couleur. Sous 4,5 : texte difficile à lire. */
export function contrasteAvecBlanc(hex: string): number {
  return Math.round((1.05 / (luminance(hex) + 0.05)) * 100) / 100
}

/**
 * Couleur dominante d'une image, pour proposer une palette à partir du logo.
 * `pixels` : données RGBA (canvas). Les pixels transparents, presque blancs,
 * presque noirs ou gris sont ignorés : on cherche la couleur « de marque ».
 * Renvoie jusqu'à deux couleurs, la plus présente d'abord, ou [] si le logo
 * n'a pas de couleur vive.
 */
export function couleursDominantes(pixels: ArrayLike<number>): string[] {
  const cases = new Map<string, { n: number; r: number; v: number; b: number }>()
  for (let i = 0; i + 3 < pixels.length; i += 4) {
    const [r, v, b, a] = [pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]]
    if (a < 128) continue
    const max = Math.max(r, v, b)
    const min = Math.min(r, v, b)
    if (max - min < 40) continue // gris, blanc ou noir
    if (max < 50 || min > 215) continue
    const cle = `${r >> 5}-${v >> 5}-${b >> 5}`
    const c = cases.get(cle) || { n: 0, r: 0, v: 0, b: 0 }
    c.n++; c.r += r; c.v += v; c.b += b
    cases.set(cle, c)
  }
  const triees = [...cases.values()].sort((x, y) => y.n - x.n)
  const total = triees.reduce((s, c) => s + c.n, 0)
  return triees
    .filter(c => c.n >= total * 0.08)
    .slice(0, 2)
    .map(c => rvbVersHex([c.r / c.n, c.v / c.n, c.b / c.n]))
}

/** Nettoie une marque venue de la base ou du cache : jamais de valeur invalide à l'écran. */
export function normaliserMarque(m: Partial<Marque> | null | undefined): Marque {
  const nom = String(m?.nom || '').trim().slice(0, 40)
  return {
    nom: nom || MARQUE_DEFAUT.nom,
    sous_titre: m?.sous_titre == null ? (nom ? null : MARQUE_DEFAUT.sous_titre) : String(m.sous_titre).trim().slice(0, 60) || null,
    logo_url: typeof m?.logo_url === 'string' && m.logo_url.startsWith('data:image/') ? m.logo_url : null,
    couleur_principale: estCouleurHex(m?.couleur_principale) ? m!.couleur_principale!.toUpperCase() : MARQUE_DEFAUT.couleur_principale,
    couleur_secondaire: estCouleurHex(m?.couleur_secondaire) ? m!.couleur_secondaire!.toUpperCase() : MARQUE_DEFAUT.couleur_secondaire,
  }
}
