// plugins/marque.client.ts
// Applique la marque (nom, logo, couleurs) dès l'ouverture : d'abord le
// dernier réglage connu sur l'appareil, puis celui de la base.
export default defineNuxtPlugin(() => {
  const { charger } = useMarque()
  void charger()
})
