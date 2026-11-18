// utils/niveau.ts
// Nom affiché d'un niveau de conformité. La base garde ses codes d'origine
// (« FLAGSHIP STORE », « VIP PERFECT STORE »…), dont dépendent les calculs :
// seul l'affichage est raccourci.
export function libelleNiveau(code: string | null | undefined, vide = 'Non conforme'): string {
  if (!code) return vide
  const c = code.toUpperCase()
  if (c.startsWith('FLAGSHIP')) return 'Flagship'
  if (c.startsWith('VIP')) return 'VIP'
  if (c.startsWith('CORE')) return 'Core'
  if (c.startsWith('BASIC')) return 'Basic'
  return code
}
