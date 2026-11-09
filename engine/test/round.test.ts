import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { NEIGHBORS, NUM_CELLS, cellName, parseCell, rotateCell } from '../src/topology.ts';
import { roundBoardCells, roundOutline, MEDALLION_RADIUS, RING_RADII, sectorStartAngle } from '../src/index.ts';
import type { Point } from '../src/index.ts';

const cells = roundBoardCells();
const angDiff = (a: number, b: number) => {
  const d = (((a - b) % 360) + 540) % 360 - 180;
  return Math.abs(d);
};

function inside(poly: Point[], x: number, y: number): boolean {
  let ins = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) ins = !ins;
  }
  return ins;
}

test('plateau rond : 96 secteurs annulaires, centres à l’intérieur', () => {
  assert.equal(cells.length, 96);
  const seen = new Set<string>();
  for (const g of cells) {
    assert.equal(g.id, cellName(g.index));
    assert.equal(g.ring, g.rank);
    seen.add(`${g.wedge}/${g.ring}`);
    assert.equal(g.polygon.length, 16);
    assert.ok(inside(g.polygon, g.x, g.y), g.id);
    const rho = Math.hypot(g.x - 0.5, g.y - 0.5);
    assert.ok(rho > g.r0 && rho < g.r1 && g.r1 <= 0.5 + 1e-9 && g.r0 >= MEDALLION_RADIUS * 0.5 - 1e-9);
    // Aire positive (orientation homogène) et proche de l'aire exacte du secteur annulaire.
    let area = 0;
    const p = g.polygon;
    for (let i = 0; i < p.length; i++) area += p[i][0] * p[(i + 1) % p.length][1] - p[(i + 1) % p.length][0] * p[i][1];
    const exact = (Math.PI / 24) * (g.r1 * g.r1 - g.r0 * g.r0);
    assert.ok(Math.abs(Math.abs(area / 2) - exact) / exact < 0.02, g.id);
  }
  // Chaque (secteur angulaire, anneau) est occupé une fois : aucun chevauchement, disque pavé.
  assert.equal(seen.size, 96);
  // Pas de chevauchement : un échantillon de points n'appartient qu'à une case au plus.
  for (let i = 0; i < 4000; i++) {
    const a = (i * 137.508 * Math.PI) / 180;
    const rho = 0.5 * Math.sqrt((i + 0.5) / 4000);
    const x = 0.5 + rho * Math.cos(a);
    const y = 0.5 - rho * Math.sin(a);
    const n = cells.filter((g) => inside(g.polygon, x, y)).length;
    assert.ok(n <= 1, `${x},${y}`);
    if (rho > 0.112 && rho < 0.498) assert.equal(n, 1);
    if (rho < 0.108) assert.equal(n, 0); // médaillon
  }
  // Anneaux intérieurs plus épais, médaillon ≈ 22 % du rayon.
  for (let i = 0; i < 3; i++) assert.ok(RING_RADII[i] - RING_RADII[i + 1] < RING_RADII[i + 1] - RING_RADII[i + 2]);
  assert.ok(Math.abs(MEDALLION_RADIUS - 0.22) < 0.01);
  assert.equal(roundOutline().length, 96);
});

test('plateau rond : le joueur 0 en bas, colonnes a→h de gauche à droite, symétrie de rotation', () => {
  const g = (n: string) => cells[parseCell(n)];
  assert.ok(g('0e1').y > 0.9 && g('0d1').y > 0.9);
  assert.ok(g('0a1').x < g('0h1').x);
  assert.ok(g('2e1').x > 0.5 && g('1e1').x < 0.5); // 2 en haut à droite, 1 en haut à gauche
  for (const c of cells) {
    const h = cells[rotateCell(c.index, 1)];
    assert.ok(Math.abs(angDiff(h.angle, c.angle - 120)) < 1e-9);
    assert.equal(h.ring, c.ring);
  }
});

test('plateau rond : voisinage orthogonal = adjacence géométrique ou traversée du centre', () => {
  const adjacent = (a: (typeof cells)[number], b: (typeof cells)[number]) =>
    (a.ring === b.ring && Math.abs(angDiff(a.angle, b.angle) - 15) < 1e-9) ||
    (a.wedge === b.wedge && Math.abs(a.ring - b.ring) === 1);
  let crossings = 0;
  for (let c = 0; c < NUM_CELLS; c++) {
    for (let d = 0; d < 4; d++) {
      for (const st of NEIGHBORS[c][d]) {
        const a = cells[c];
        const b = cells[st.to];
        if (!st.flip) {
          assert.ok(adjacent(a, b), `${a.id} / ${b.id}`);
          continue;
        }
        crossings++;
        // Traversée du centre : rangée 4 → rangée 4, demi-secteur diamétralement opposé.
        assert.equal(a.ring, 4);
        assert.equal(b.ring, 4);
        const half = (x: typeof a) => Math.floor(((x.wedge + 22) % 24) / 4);
        assert.equal((half(a) + 3) % 6, half(b), `${a.id} / ${b.id}`);
        // Écart à la case exactement opposée (convention documentée dans round.ts) :
        // 45° pour les colonnes a, d, e, h ; 15° pour b, c, f, g.
        const dev = angDiff(b.angle, a.angle + 180);
        assert.equal(dev, [0, 3, 4, 7].includes(a.file) ? 45 : 15, `${a.id} / ${b.id}`);
        // Symétrie axiale par rapport au diamètre de la frontière entre les deux joueurs.
        const ad = a.file < 4 ? a : b;
        const wall = sectorStartAngle((ad.sector + 2) % 3); // frontière entre ad.sector et ad.sector-1
        assert.equal((a.angle + b.angle) % 360, (2 * wall) % 360, `${a.id} / ${b.id}`);
        // Une colonne du milieu se prolonge par une colonne du milieu, une du bord par une du bord.
        assert.equal(b.file, 7 - a.file);
      }
    }
  }
  assert.equal(crossings, 24);
  // Seules paires géométriquement adjacentes non voisines : h d'un joueur / a du suivant (3 frontières × 4 anneaux).
  let walls = 0;
  for (const a of cells) {
    for (const b of cells) {
      if (a.index >= b.index || !adjacent(a, b)) continue;
      const linked = [0, 1, 2, 3].some((d) => NEIGHBORS[a.index][d].some((st) => st.to === b.index));
      if (!linked) {
        walls++;
        assert.ok(a.sector !== b.sector && a.ring === b.ring && [a.file, b.file].sort().join() === '0,7', `${a.id} / ${b.id}`);
      }
    }
  }
  assert.equal(walls, 12);
});

test('geometry.json est à jour (npm run export-geometry)', () => {
  const j = JSON.parse(readFileSync(new URL('../geometry.json', import.meta.url), 'utf8'));
  assert.equal(j.shape, 'round');
  assert.deepEqual(j.cells, JSON.parse(JSON.stringify(cells)));
});
