#!/usr/bin/env node
/**
 * Régénère tous les visuels de marque (logo web, icônes PWA, icônes et écrans
 * de démarrage Android) à partir de resources/logo.svg, resources/glyphe.svg
 * et resources/logo-bigfive.jpg.
 * Pour changer de marque : remplacer ces deux SVG et la couleur FOND, puis
 *   node scripts/generate-brand-assets.mjs
 * Les tailles Android sont relues sur les fichiers existants, jamais devinées.
 */
import { readdirSync, readFileSync, renameSync, statSync } from 'node:fs'
import { join } from 'node:path'
import sharp from 'sharp'

const FOND = '#603080'
const logo = readFileSync('resources/logo.svg')
const glyphe = readFileSync('resources/glyphe.svg')

const rendre = (svg, taille) => sharp(svg, { density: 300 }).resize(taille, taille).png().toBuffer()

async function carre(fichier, taille) {
  await sharp(await rendre(logo, taille)).toFile(fichier)
}

// Logo affiché dans l'application : le logo Big Five fourni (resources/logo-bigfive.jpg).
// Les icônes d'application gardent le repère sur fond violet : l'image fournie
// (200 px) est trop petite pour une icône nette.
await sharp('resources/logo-bigfive.jpg').resize(224, 224, { fit: 'contain', background: '#FFFFFF' }).png().toFile('assets/logo.png')
await carre('public/favicon.png', 224)
await carre('resources/icon.png', 1024)
for (const t of [72, 96, 128, 144, 152, 192, 384, 512]) await carre(`public/icons/icon-${t}x${t}.png`, t)

const res = 'android/app/src/main/res'
for (const dossier of readdirSync(res)) {
  const chemin = join(res, dossier)
  if (!statSync(chemin).isDirectory()) continue
  for (const f of readdirSync(chemin)) {
    if (!f.endsWith('.png')) continue
    const cible = join(chemin, f)
    const { width, height } = await sharp(cible).metadata()
    if (f === 'ic_launcher.png') {
      await sharp(await rendre(logo, width)).toFile(cible + '.tmp')
    }
    else if (f === 'ic_launcher_round.png') {
      const masque = Buffer.from(`<svg width="${width}" height="${width}"><circle cx="${width / 2}" cy="${width / 2}" r="${width / 2}"/></svg>`)
      const plein = await sharp({ create: { width, height: width, channels: 4, background: FOND } })
        .composite([{ input: await rendre(glyphe, width) }]).png().toBuffer()
      await sharp(plein).composite([{ input: masque, blend: 'dest-in' }]).png().toFile(cible + '.tmp')
    }
    else if (f === 'ic_launcher_background.png') {
      await sharp({ create: { width, height, channels: 4, background: FOND } }).png().toFile(cible + '.tmp')
    }
    else if (f === 'ic_launcher_foreground.png') {
      await sharp(await rendre(glyphe, width)).toFile(cible + '.tmp')
    }
    else if (f === 'splash.png') {
      const nuit = dossier.includes('night')
      const cote = Math.round(Math.min(width, height) * 0.28)
      await sharp({ create: { width, height, channels: 4, background: nuit ? '#111827' : '#FFFFFF' } })
        .composite([{ input: await rendre(logo, cote), gravity: 'centre' }]).png().toFile(cible + '.tmp')
    }
    else continue
    renameSync(cible + '.tmp', cible)
  }
}
console.log('Visuels de marque régénérés.')
