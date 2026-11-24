#!/usr/bin/env node
/**
 * Rend docs/video/video.html en MP4 (1920 × 1080, 30 images/s) avec la voix off.
 *
 *   node docs/video/rendre.mjs                  # vidéo complète -> docs/DEMO-BIG-FIVE-FORCE.mp4
 *   node docs/video/rendre.mjs --apercu 2.5,17  # images fixes aux secondes données
 *
 * Besoins : Playwright (Chromium) et ffmpeg. La page est avancée image par
 * image (window.aller) : le rendu ne dépend pas de la vitesse de la machine.
 */
import { execFileSync } from 'node:child_process'
import { mkdirSync, rmSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const { chromium } = createRequire(import.meta.url)('playwright')
const ICI = dirname(fileURLToPath(import.meta.url))
const IPS = 30
const SORTIE = join(ICI, '..', 'DEMO-BIG-FIVE-FORCE.mp4')
const IMAGES = process.env.IMAGES_DIR || join(ICI, '.images')

// Voix off : fichier et seconde de départ (mêmes repères que les scènes de video.html).
const VOIX = [['v01', 1.0], ['v02', 5.9], ['v03', 11.0], ['v04', 21.0], ['v05', 28.9], ['v06', 37.0], ['v07', 45.9], ['v08', 53.2], ['v09', 62.3]]

async function ouvrir(navigateur) {
  const page = await navigateur.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 })
  await page.goto(`file://${join(ICI, 'video.html')}?rendu=1`)
  await page.evaluate(async () => {
    await document.fonts.ready
    await Promise.all([...document.images].map(i => i.decode().catch(() => {})))
  })
  return page
}

const navigateur = await chromium.launch()
const apercu = process.argv.indexOf('--apercu')

if (apercu > -1) {
  const page = await ouvrir(navigateur)
  for (const t of process.argv[apercu + 1].split(',').map(Number)) {
    await page.evaluate(x => window.aller(x), t)
    await page.screenshot({ path: join(IMAGES, '..', `apercu-${String(t).padStart(5, '0')}.jpg`), type: 'jpeg', quality: 80 })
  }
  await navigateur.close()
  process.exit(0)
}

rmSync(IMAGES, { recursive: true, force: true })
mkdirSync(IMAGES, { recursive: true })
const duree = await (await ouvrir(navigateur)).evaluate(() => window.DUREE)
const total = Math.round(duree * IPS)
const OUVRIERS = 4
await Promise.all(Array.from({ length: OUVRIERS }, async (_, o) => {
  const page = await ouvrir(navigateur)
  for (let i = o; i < total; i += OUVRIERS) {
    await page.evaluate(x => window.aller(x), i / IPS)
    await page.screenshot({ path: join(IMAGES, `${String(i).padStart(5, '0')}.jpg`), type: 'jpeg', quality: 95 })
  }
}))
await navigateur.close()

// Assemblage : images -> H.264, voix posées à leur seconde, niveau sonore normalisé.
const entrees = VOIX.flatMap(([f]) => ['-i', join(ICI, 'voix', `${f}.wav`)])
const filtres = VOIX.map(([, t], i) => `[${i + 1}:a]adelay=${Math.round(t * 1000)}:all=1[a${i}]`).join(';')
  + `;${VOIX.map((_, i) => `[a${i}]`).join('')}amix=inputs=${VOIX.length}:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11,apad[voix]`
execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(IPS), '-i', join(IMAGES, '%05d.jpg'), ...entrees,
  '-filter_complex', filtres, '-map', '0:v', '-map', '[voix]', '-t', String(duree),
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '160k', '-ar', '48000',
  '-movflags', '+faststart', SORTIE], { stdio: 'inherit' })
rmSync(IMAGES, { recursive: true, force: true })
console.log(`Vidéo : ${SORTIE} (${total} images, ${duree} s)`)
