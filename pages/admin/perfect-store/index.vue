<template>
  <div />
</template>

<script setup lang="ts">
// Le dashboard de conformité est devenu la page d'accueil admin (/admin).
// On conserve cette route pour les anciens liens/favoris : redirection.
definePageMeta({ middleware: ['auth', 'admin'], layout: 'admin' })
await navigateTo('/admin', { replace: true })
</script>
