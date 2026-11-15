// demo/comptes.ts
// Comptes fictifs du mode démo. Aucun serveur : le mot de passe est en dur et
// ne protège rien, il sert seulement à garder le même écran de connexion.
export const MOT_DE_PASSE_DEMO = 'fieldtrack'

export const COMPTES_DEMO = [
  { email: 'admin@fieldtrack.demo', nom: 'Admin Field Track', role: 'admin', detail: 'Tableau de bord complet' },
  { email: 'commercial1@fieldtrack.demo', nom: 'Awa Démo', role: 'commercial', detail: 'Cocody 1, Plateau' },
  { email: 'commercial2@fieldtrack.demo', nom: 'Bakary Démo', role: 'commercial', detail: 'Marcory, Treichville' },
  { email: 'commercial3@fieldtrack.demo', nom: 'Clarisse Démo', role: 'commercial', detail: 'Yopougon 1' },
  { email: 'merchandiser1@fieldtrack.demo', nom: 'Daouda Essai', role: 'merchandiser', detail: 'Cocody 1' },
  { email: 'merchandiser2@fieldtrack.demo', nom: 'Estelle Essai', role: 'merchandiser', detail: 'Plateau' },
  { email: 'merchandiser3@fieldtrack.demo', nom: 'Fabrice Essai', role: 'merchandiser', detail: 'Marcory' },
  { email: 'merchandiser4@fieldtrack.demo', nom: 'Grâce Essai', role: 'merchandiser', detail: 'Treichville' },
  { email: 'merchandiser5@fieldtrack.demo', nom: 'Hervé Essai', role: 'merchandiser', detail: 'Yopougon 1' },
] as const
