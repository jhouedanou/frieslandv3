<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
  <ClientOnly>
    <LocationDisclosureModal />
    <MiseAJourObligatoire />
  </ClientOnly>
</template>

<script setup lang="ts">
// Nom de l'application : celui réglé dans Paramètres > Personnalisation.
const { marque } = useMarque()
useHead({
  title: () => marque.value.nom,
  htmlAttrs: { lang: 'fr' },
})
</script>
