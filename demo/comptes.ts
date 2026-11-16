// demo/comptes.ts
// Comptes fictifs du mode démo. Aucun serveur : le mot de passe est en dur et
// ne protège rien, il sert seulement à garder le même écran de connexion.
export const MOT_DE_PASSE_DEMO = 'bigfive'

export const COMPTES_DEMO = [
  { email: 'admin@bigfiveforce.demo', nom: 'Admin Big Five', role: 'admin', detail: 'Tableau de bord complet' },
  { email: 'commercial1@bigfiveforce.demo', nom: 'Awa Démo', role: 'commercial', detail: 'Territoires Est et Centre' },
  { email: 'commercial2@bigfiveforce.demo', nom: 'Bakary Démo', role: 'commercial', detail: 'Territoires Sud et Lagune' },
  { email: 'commercial3@bigfiveforce.demo', nom: 'Clarisse Démo', role: 'commercial', detail: 'Territoire Ouest' },
  { email: 'merchandiser1@bigfiveforce.demo', nom: 'Daouda Essai', role: 'merchandiser', detail: 'Territoire Est' },
  { email: 'merchandiser2@bigfiveforce.demo', nom: 'Estelle Essai', role: 'merchandiser', detail: 'Territoire Centre' },
  { email: 'merchandiser3@bigfiveforce.demo', nom: 'Fabrice Essai', role: 'merchandiser', detail: 'Territoire Sud' },
  { email: 'merchandiser4@bigfiveforce.demo', nom: 'Grâce Essai', role: 'merchandiser', detail: 'Territoire Lagune' },
  { email: 'merchandiser5@bigfiveforce.demo', nom: 'Hervé Essai', role: 'merchandiser', detail: 'Territoire Ouest' },
] as const
