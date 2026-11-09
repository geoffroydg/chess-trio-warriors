// Écrit engine/geometry.json (et sa copie app/assets/geometry.json) : géométrie du plateau
// ROND (96 cases) pour le client Flutter.
// Usage : node --experimental-strip-types scripts/export-geometry.ts
import { writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { MEDALLION_RADIUS, RING_RADII, roundBoardCells, roundOutline, sectorStartAngle } from '../src/index.ts';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const data = {
  version: 2,
  shape: 'round',
  description:
    "Plateau rond d'échecs à 3 joueurs : coordonnées normalisées (x à droite, y vers le bas, disque de centre (0.5,0.5) et rayon 0.5). Angles en degrés, sens trigonométrique vu à l'écran (x = 0.5 + r cos a, y = 0.5 - r sin a). Joueur 0 en bas, 2 en haut à droite, 1 en haut à gauche ; rangée 1 = anneau extérieur.",
  center: [0.5, 0.5],
  radius: 0.5,
  rings: RING_RADII.map((r) => r * 0.5),
  medallion: MEDALLION_RADIUS * 0.5,
  sectorStart: [0, 1, 2].map(sectorStartAngle),
  outline: roundOutline(),
  cells: roundBoardCells(),
};
const text = JSON.stringify(data) + '\n';
for (const out of [join(root, 'geometry.json'), join(root, '..', 'app', 'assets', 'geometry.json')]) {
  if (out.includes('app') && !existsSync(dirname(out))) continue;
  writeFileSync(out, text);
  console.log(`geometry.json écrit (${data.cells.length} cases) : ${out}`);
}
