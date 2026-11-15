// demo/comptes.ts
// Comptes fictifs du mode démo. Aucun serveur : le mot de passe est en dur et
// ne protège rien, il sert seulement à garder le même écran de connexion.
export const MOT_DE_PASSE_DEMO = 'fieldtrack'

export const COMPTES_DEMO = [
  { email: 'admin@fieldtrack.demo', nom: 'Admin Field Track', role: 'admin', detail: 'Tableau de bord complet' },
  { email: 'commercial1@fieldtrack.demo', nom: 'Awa Démo', role: 'commercial', detail: 'Territoires Est et Centre' },
  { email: 'commercial2@fieldtrack.demo', nom: 'Bakary Démo', role: 'commercial', detail: 'Territoires Sud et Lagune' },
  { email: 'commercial3@fieldtrack.demo', nom: 'Clarisse Démo', role: 'commercial', detail: 'Territoire Ouest' },
  { email: 'merchandiser1@fieldtrack.demo', nom: 'Daouda Essai', role: 'merchandiser', detail: 'Territoire Est' },
  { email: 'merchandiser2@fieldtrack.demo', nom: 'Estelle Essai', role: 'merchandiser', detail: 'Territoire Centre' },
  { email: 'merchandiser3@fieldtrack.demo', nom: 'Fabrice Essai', role: 'merchandiser', detail: 'Territoire Sud' },
  { email: 'merchandiser4@fieldtrack.demo', nom: 'Grâce Essai', role: 'merchandiser', detail: 'Territoire Lagune' },
  { email: 'merchandiser5@fieldtrack.demo', nom: 'Hervé Essai', role: 'merchandiser', detail: 'Territoire Ouest' },
] as const
