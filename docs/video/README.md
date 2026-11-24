# Vidéo de présentation Big Five Force

Vidéo en motion design, 67 secondes, 1920 × 1080, avec voix off française.
Elle montre les avantages de l'application par de vraies manipulations : un curseur
clique sur les boutons et les écrans changent comme dans la démo.
Résultat : `docs/DEMO-BIG-FIVE-FORCE.mp4`.

## Fichiers

| Fichier | Rôle |
|---|---|
| `video.html` | L'animation : 9 scènes sur une seule ligne de temps, et les parcours du curseur (`LECTEURS`) |
| `rendre.mjs` | Capture la page image par image, puis assemble le MP4 avec ffmpeg |
| `captures/` | Écrans de l'application (mode démo) |
| `voix/` | Voix off, un fichier par scène, et son texte (`textes.txt`) |

Ouvrir `video.html` dans un navigateur lit l'animation en boucle, sans le son.

## Régénérer la vidéo

```bash
node docs/video/rendre.mjs                    # vidéo complète
node docs/video/rendre.mjs --apercu 2.8,34    # images fixes à 2,8 s et 34 s
```

Besoins : Playwright (Chromium) et ffmpeg.

## Modifier

- **Un texte ou un écran** : dans `video.html`. Chaque élément porte `--d`, la
  seconde où il apparaît.
- **La voix** : changer le texte dans `voix/textes.txt`, régénérer le fichier
  de la scène, puis ajuster sa seconde de départ dans `rendre.mjs` (tableau `VOIX`).
- **Les écrans** : refaire les captures depuis la démo, au format 2880 × 1800
  (ordinateur) et 780 × 1688 (téléphone).

## Voix off

Voix de synthèse produite avec Piper, voix `fr_FR-siwis-medium`.
La voix est entraînée sur le corpus SIWIS, sous licence CC-BY 4.0 : une vidéo
diffusée doit en porter la mention (« Voix : Piper, corpus SIWIS, CC-BY 4.0 »).

Quelques mots sont écrits comme ils se prononcent, pour guider la voix :
« Faïve » pour « Five », « merchandiseur », « G P S ».

```bash
python3 -m venv venv && ./venv/bin/pip install piper-tts
# puis charger la voix fr_FR-siwis-medium (dépôt rhasspy/piper-voices)
```
