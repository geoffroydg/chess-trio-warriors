import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  KING_JUMPS,
  KNIGHT_JUMPS,
  NUM_CELLS,
  PAWN_CAPTURES,
  PAWN_PUSH,
  RAYS,
  TEAM_BORDERS,
  borderBetween,
  cellAt,
  cellName,
  isLight,
  parseCell,
  ringOf,
  rotateCell,
  wedgeOf,
} from '../src/board.ts';
import { BACK_RANK, MEDALLION_RADIUS, RING_RADII, roundBoardCells, roundOutline, swordGeometry } from '../src/index.ts';
import type { Point } from '../src/index.ts';
import { at } from './helpers.ts';

const names = (xs: Iterable<number>) => [...xs].map(cellName);
const ray = (cell: string, d: number) => names(RAYS[parseCell(cell) * 8 + d].cells);

test('144 cases, noms et index cohérents, 24 colonnes × 6 anneaux', () => {
  const seen = new Set<string>();
  for (let c = 0; c < NUM_CELLS; c++) {
    assert.equal(parseCell(cellName(c)), c);
    assert.equal(cellAt(wedgeOf(c), ringOf(c)), c);
    seen.add(`${wedgeOf(c)}/${ringOf(c)}`);
  }
  assert.equal(seen.size, 144);
  assert.equal(cellName(0), '0a1');
  assert.equal(cellName(143), '2h6');
  for (const bad of ['0a7', '3a1', '0i1', '0a0', '', 'x']) assert.throws(() => parseCell(bad));
  // Colonnes absolues : 0a = 14, 1a = 6, 2a = 22 ; 1h et 0a sont voisines.
  assert.equal(wedgeOf(parseCell('0a1')), 14);
  assert.equal(wedgeOf(parseCell('1a1')), 6);
  assert.equal(wedgeOf(parseCell('2a1')), 22);
  assert.equal(at(13, 1), '1h1');
  assert.equal(at(24 + 5, 1), '2h1');
});

test('couleurs : (colonne + anneau) % 2, rois sur cases claires, symétrie par rotation', () => {
  for (let c = 0; c < NUM_CELLS; c++) {
    assert.equal(isLight(c), (wedgeOf(c) + ringOf(c) + 1) % 2 === 0);
    assert.equal(isLight(rotateCell(c, 1)), isLight(c));
  }
  assert.deepEqual(BACK_RANK, ['R', 'N', 'B', 'K', 'Q', 'B', 'N', 'R']);
  for (const s of [0, 1, 2]) {
    assert.ok(isLight(parseCell(`${s}d1`)), 'roi sur case claire');
    assert.ok(!isLight(parseCell(`${s}e1`)));
    assert.ok(isLight(parseCell(`${s}h1`)), 'case de coin claire à droite');
  }
});

test('voisinages : horizontales circulaires, verticales, diagonales', () => {
  // Horizontale : 23 cases, sans revenir sur la case de départ.
  for (const d of [2, 3]) {
    const r = ray('0a3', d);
    assert.equal(r.length, 23);
    assert.ok(!r.includes('0a3'));
    assert.equal(new Set(r).size, 23);
  }
  assert.equal(ray('0a3', 3)[0], '1h3');
  assert.equal(ray('0h3', 2)[0], '2a3');
  // Rois : 8 voisins sur un anneau intermédiaire, 5 sur l'anneau 1.
  assert.equal(KING_JUMPS[parseCell('0d3')].length, 8);
  assert.equal(KING_JUMPS[parseCell('0d1')].length, 5);
  assert.deepEqual(
    names(KING_JUMPS[parseCell('0d3')].map((j) => j.to)).sort(),
    ['0c2', '0c3', '0c4', '0d2', '0d4', '0e2', '0e3', '0e4'],
  );
});

test('traversée verticale : (c, 6) → (c+12, 6) puis vers l’extérieur ; couleur conservée', () => {
  // 0a = colonne 14 ; colonne 14 + 12 = 2 = colonne e de l'équipe 2.
  assert.deepEqual(ray('0a1', 0), ['0a2', '0a3', '0a4', '0a5', '0a6', '2e6', '2e5', '2e4', '2e3', '2e2', '2e1']);
  assert.deepEqual(ray('0a4', 1), ['0a3', '0a2', '0a1']);
  for (let c = 0; c < NUM_CELLS; c++) {
    const v = RAYS[c * 8 + 0];
    if (ringOf(c) !== 5) continue;
    const opp = v.cells[0];
    assert.equal(wedgeOf(opp), (wedgeOf(c) + 12) % 24);
    assert.equal(ringOf(opp), 5);
    assert.equal(isLight(opp), isLight(c));
    assert.equal(v.center[0], 1);
  }
});

test('traversée diagonale : (c, 6) sens s → (c+12+2s, 6) puis vers l’extérieur avec le même sens', () => {
  // 0a6 = (14, 6) ; s = +1 → colonne 28 % 24 = 4 = 2g ; s = −1 → colonne 0 = 2c.
  assert.deepEqual(ray('0a6', 4).slice(0, 3), [at(4, 6), at(5, 5), at(6, 4)]);
  assert.deepEqual(ray('0a6', 5).slice(0, 3), [at(0, 6), at(23, 5), at(22, 4)]);
  assert.equal(at(4, 6), '2g6');
  // Diagonale complète depuis l'anneau 1 : 5 cases, le centre, puis vers l'extérieur ; ici
  // elle reviendrait sur sa case de départ (5 + 14 + 5 = 24 colonnes) : elle s'arrête avant.
  const full = ray('0a1', 4);
  assert.equal(full.length, 10);
  assert.equal(full[full.length - 1], at(13, 2));
  assert.deepEqual(ray('0b2', 4).length, 10); // 4 + centre + 5 jusqu'au bord
  for (let c = 0; c < NUM_CELLS; c++) for (let d = 0; d < 8; d++) assert.ok(!RAYS[c * 8 + d].cells.includes(c));
  for (let c = 0; c < NUM_CELLS; c++) {
    for (const d of [4, 5, 6, 7]) {
      for (const x of RAYS[c * 8 + d].cells) assert.equal(isLight(x), isLight(c), `le fou garde sa couleur ${cellName(c)}`);
    }
  }
  // Vers l'extérieur depuis l'anneau 1 : rien (pas de rebond sur le cercle extérieur).
  assert.deepEqual(ray('0d1', 6), []);
  assert.deepEqual(ray('0d2', 6), ['0e1']);
});

test('trajets réversibles (symétrie des attaques) et cavalier à travers le centre', () => {
  const rev = [1, 0, 3, 2, 7, 6, 5, 4];
  for (let c = 0; c < NUM_CELLS; c++) {
    for (let d = 0; d < 8; d++) {
      const r = RAYS[c * 8 + d];
      for (let i = 0; i < r.cells.length; i++) {
        const back = RAYS[r.cells[i] * 8 + rev[d]];
        // Le trajet retour depuis la i-ème case contient la case de départ (sauf diagonale passant
        // par le centre, où la direction de retour change de sens angulaire).
        const ok = [...Array(8).keys()].some((e) => {
          const b = RAYS[r.cells[i] * 8 + e];
          return b.cells[i] === c && b.hilt[i] === r.hilt[i];
        });
        assert.ok(ok || back.cells[i] === c, `${cellName(c)} d${d} i${i}`);
      }
    }
    for (const j of KNIGHT_JUMPS[c]) assert.ok(KNIGHT_JUMPS[j.to].some((k) => k.to === c), 'cavalier symétrique');
  }
  // 0d5 : 2 pas vers le centre (0d6 puis 2h6), puis 1 pas horizontal → 1a6 / 2g6.
  const n = names(KNIGHT_JUMPS[parseCell('0d5')].map((j) => j.to)).sort();
  assert.deepEqual(n, ['0b4', '0b6', '0c3', '0e3', '0f4', '0f6', '1a6', '2g6']);
  assert.ok(KNIGHT_JUMPS[parseCell('0d5')].find((j) => cellName(j.to) === '1a6')!.center);
  // Le cavalier change de couleur.
  for (const j of KNIGHT_JUMPS[parseCell('0b1')]) assert.notEqual(isLight(j.to), isLight(parseCell('0b1')));
});

test('pions : avance, traversée du centre, prises diagonales', () => {
  assert.equal(cellName(PAWN_PUSH[0][parseCell('0d2')]!.to), '0d3');
  const cross = PAWN_PUSH[0][parseCell('0d6')]!;
  assert.equal(cellName(cross.to), at(17 + 12, 6));
  assert.ok(cross.center);
  assert.equal(cellName(PAWN_PUSH[1][parseCell('2h6')]!.to), '2h5');
  assert.equal(PAWN_PUSH[1][parseCell('2h1')], null);
  assert.deepEqual(names(PAWN_CAPTURES[0][parseCell('0d6')].map((e) => e.to)).sort(), [at(31, 6), at(27, 6)].sort());
});

test('épées : frontières, poignées (anneau 1) et lames (anneaux 2-3)', () => {
  assert.equal(borderBetween(13, 14), 0); // 1h | 0a
  assert.equal(borderBetween(21, 22), 2); // 0h | 2a
  assert.equal(borderBetween(5, 6), 1); // 2h | 1a
  assert.equal(borderBetween(15, 14), -1);
  assert.deepEqual(TEAM_BORDERS, [[0, 2], [1, 0], [2, 1]]);
  const hv = (cell: string, d: number) => [...RAYS[parseCell(cell) * 8 + d].hilt];
  assert.equal(hv('0a1', 3)[0], 1); // 0a1 → 1h1 : poignée 0
  assert.equal(hv('0a2', 3)[0], 0); // anneau 2 : lame, pas poignée
  assert.equal(hv('0a1', 5)[0], 1); // diagonale 0a1 → 1h2 : poignée
  assert.equal(hv('0a2', 7)[0], 1); // diagonale 0a2 → 1h1 : poignée
  const caps = PAWN_CAPTURES[0][parseCell('0a2')].find((e) => cellName(e.to) === '1h3')!;
  assert.equal(caps.blade, 1);
  assert.equal(PAWN_CAPTURES[0][parseCell('0a3')].find((e) => cellName(e.to) === '1h4')!.blade, 1);
  assert.equal(PAWN_CAPTURES[0][parseCell('0a4')].find((e) => cellName(e.to) === '1h5')!.blade, 0);
});

function inside(poly: Point[], x: number, y: number): boolean {
  let ins = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) ins = !ins;
  }
  return ins;
}

test('géométrie : 144 secteurs annulaires sans chevauchement, médaillon ≈ 20 %', () => {
  const cells = roundBoardCells();
  assert.equal(cells.length, 144);
  for (const g of cells) {
    assert.equal(g.id, cellName(g.index));
    assert.equal(g.polygon.length, 16);
    assert.ok(inside(g.polygon, g.x, g.y), g.id);
    assert.equal(g.light, isLight(g.index));
    assert.equal(g.wedge, wedgeOf(g.index));
  }
  for (let i = 0; i < 4000; i++) {
    const a = (i * 137.508 * Math.PI) / 180;
    const rho = 0.5 * Math.sqrt((i + 0.5) / 4000);
    const x = 0.5 + rho * Math.cos(a);
    const y = 0.5 - rho * Math.sin(a);
    const n = cells.filter((g) => inside(g.polygon, x, y)).length;
    assert.ok(n <= 1);
    if (rho > 0.102 && rho < 0.498) assert.equal(n, 1);
    if (rho < 0.098) assert.equal(n, 0);
  }
  assert.equal(RING_RADII.length, 7);
  assert.equal(MEDALLION_RADIUS, 0.2);
  for (let i = 0; i < 5; i++) assert.ok(RING_RADII[i] - RING_RADII[i + 1] > RING_RADII[i + 1] - RING_RADII[i + 2]);
  // Équipe 0 en bas, 1 en haut à gauche, 2 en haut à droite.
  const g = (n: string) => cells[parseCell(n)];
  assert.ok(g('0d1').y > 0.9 && g('0a1').x < g('0h1').x);
  assert.ok(g('1d1').x < 0.5 && g('2d1').x > 0.5);
  assert.equal(roundOutline().length, 96);
  const swords = swordGeometry();
  assert.deepEqual(swords.map((s) => s.angle), [210, 90, 330]);
  assert.deepEqual(swords.map((s) => s.teams), [[0, 1], [1, 2], [2, 0]]);
  // geometry.json exporté à jour.
  const json = JSON.parse(readFileSync(new URL('../geometry.json', import.meta.url), 'utf8'));
  assert.equal(json.cells.length, 144);
  assert.deepEqual(json.cells[5], roundBoardCells()[5]);
  assert.equal(json.swords.length, 3);
});
