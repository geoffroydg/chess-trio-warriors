// Écrit engine/geometry.json : géométrie des 96 cases pour le client Flutter.
// Usage : node --experimental-strip-types scripts/export-geometry.ts
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { boardCells, boardOutline } from '../src/index.ts';

const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'geometry.json');
const data = {
  version: 1,
  description:
    "Plateau d'échecs à 3 joueurs : coordonnées normalisées (x à droite, y vers le bas, hexagone de centre (0.5,0.5) et rayon 0.5). Joueur 0 en bas.",
  outline: boardOutline(),
  cells: boardCells(),
};
writeFileSync(out, JSON.stringify(data, null, 1) + '\n');
console.log(`geometry.json écrit (${data.cells.length} cases) : ${out}`);
