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
  title: 'Field Track',
  htmlAttrs: { lang: 'fr' },
})
</script>
