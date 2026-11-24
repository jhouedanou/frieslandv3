import { describe, expect, it } from 'vitest'
import { MARQUE_DEFAUT, contrasteAvecBlanc, couleurMarque, couleursDominantes, definirCouleurMarque, estCouleurHex, normaliserMarque, paletteMarque } from '../utils/marque'

describe('palette de marque', () => {
  it('garde la couleur principale au niveau 500 et la secondaire au niveau 700', () => {
    const p = paletteMarque('#603080', '#403080')
    expect(p[500]).toBe('96 48 128')
    expect(p[700]).toBe('64 48 128')
  })

  it('va du plus clair (50) au plus foncé (900)', () => {
    const p = paletteMarque('#E11D48', '#9F1239')
    const somme = (n: number) => p[n].split(' ').map(Number).reduce((a, b) => a + b, 0)
    expect(somme(50)).toBeGreaterThan(somme(300))
    expect(somme(300)).toBeGreaterThan(somme(500))
    expect(somme(500)).toBeGreaterThan(somme(900))
  })

  it('retombe sur la couleur par défaut si la valeur est invalide', () => {
    expect(paletteMarque('rouge')[500]).toBe('96 48 128')
  })
})

describe('contrôles de saisie', () => {
  it('reconnaît une couleur hexadécimale', () => {
    expect(estCouleurHex('#603080')).toBe(true)
    expect(estCouleurHex('#60308')).toBe(false)
    expect(estCouleurHex('603080')).toBe(false)
  })

  it('signale une couleur trop claire pour du texte blanc', () => {
    expect(contrasteAvecBlanc('#603080')).toBeGreaterThan(4.5)
    expect(contrasteAvecBlanc('#FDE047')).toBeLessThan(3)
  })

  it('nettoie une marque incomplète ou invalide', () => {
    const m = normaliserMarque({ nom: '  Client Force  ', couleur_principale: 'bleu', logo_url: 'https://exemple.com/logo.png' })
    expect(m.nom).toBe('Client Force')
    expect(m.couleur_principale).toBe(MARQUE_DEFAUT.couleur_principale)
    expect(m.logo_url).toBeNull()
    expect(m.sous_titre).toBeNull()
    expect(normaliserMarque(null)).toEqual(MARQUE_DEFAUT)
  })
})

describe('couleurs du logo', () => {
  const pixels = (couleurs: [number, number, number, number, number][]) =>
    couleurs.flatMap(([r, v, b, a, n]) => Array.from({ length: n }, () => [r, v, b, a]).flat())

  it('ignore le blanc, le noir, le gris et le transparent', () => {
    const data = pixels([[255, 255, 255, 255, 500], [0, 0, 0, 255, 300], [128, 128, 128, 255, 100], [200, 30, 30, 0, 400], [96, 48, 128, 255, 60]])
    expect(couleursDominantes(data)).toEqual(['#603080'])
  })

  it('renvoie les deux couleurs les plus présentes', () => {
    const data = pixels([[220, 30, 40, 255, 300], [20, 90, 200, 255, 120]])
    expect(couleursDominantes(data)).toEqual(['#DC1E28', '#145AC8'])
  })

  it('ne propose rien pour un logo sans couleur', () => {
    expect(couleursDominantes(pixels([[0, 0, 0, 255, 100], [255, 255, 255, 255, 100]]))).toEqual([])
  })
})

describe('couleur pour les graphiques', () => {
  it('suit la marque en cours', () => {
    definirCouleurMarque('#0F766E')
    expect(couleurMarque()).toBe('#0F766E')
    expect(couleurMarque(0.5)).toBe('rgba(15,118,110, 0.5)')
    definirCouleurMarque(MARQUE_DEFAUT.couleur_principale)
  })
})
