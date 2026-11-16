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
useHead({
  title: 'Big Five Force',
  htmlAttrs: { lang: 'fr' },
})
</script>
