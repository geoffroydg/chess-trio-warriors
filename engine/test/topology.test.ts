import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  DIRS,
  KING_ADJ,
  KNIGHT_ADJ,
  NEIGHBORS,
  NUM_CELLS,
  OPPOSITE,
  PAWN_CAPTURES,
  PAWN_PUSH,
  cellName,
  parseCell,
  rotateCell,
  walkRay,
  dirIndex,
} from '../src/topology.ts';
import { boardCells } from '../src/index.ts';
import { sorted } from './helpers.ts';

const names = (cs: readonly number[]) => sorted(cs.map(cellName));

test('96 cases aux noms uniques et réversibles', () => {
  assert.equal(NUM_CELLS, 96);
  const seen = new Set<string>();
  for (let c = 0; c < NUM_CELLS; c++) {
    const n = cellName(c);
    assert.equal(parseCell(n), c);
    seen.add(n);
  }
  assert.equal(seen.size, 96);
  assert.throws(() => parseCell('3a1'));
  assert.throws(() => parseCell('0i1'));
  assert.throws(() => parseCell('0a5'));
});

test('nombres de voisins plausibles', () => {
  const orthoHist: Record<number, number> = {};
  for (let c = 0; c < NUM_CELLS; c++) {
    const ortho = [0, 1, 2, 3].reduce((n, d) => n + NEIGHBORS[c][d].length, 0);
    orthoHist[ortho] = (orthoHist[ortho] ?? 0) + 1;
    assert.ok(ortho >= 2 && ortho <= 4);
    for (let d = 0; d < 4; d++) assert.ok(NEIGHBORS[c][d].length <= 1);
    for (let d = 4; d < 8; d++) assert.ok(NEIGHBORS[c][d].length <= 2);
    assert.ok([3, 5, 8, 9].includes(KING_ADJ[c].length), `${cellName(c)} : ${KING_ADJ[c].length}`);
    assert.ok(KNIGHT_ADJ[c].length >= 2 && KNIGHT_ADJ[c].length <= 10);
  }
  // 6 coins (a1/h1), 36 cases de bord, 54 intérieures (aucun bord à la rangée 4 : elle donne sur un autre secteur).
  assert.deepEqual(orthoHist, { 2: 6, 3: 36, 4: 54 });
  // Les 6 cases centrales (d4/e4) ont 9 voisines : la diagonale centrale se dédouble.
  const nine = names(KING_ADJ.map((a, c) => (a.length === 9 ? c : -1)).filter((c) => c >= 0));
  assert.deepEqual(nine, ['0d4', '0e4', '1d4', '1e4', '2d4', '2e4']);
});

test('adjacences symétriques (pas, roi, cavalier)', () => {
  for (let c = 0; c < NUM_CELLS; c++) {
    for (let d = 0; d < 8; d++) {
      for (const st of NEIGHBORS[c][d]) {
        const arrive = st.flip ? OPPOSITE[d] : d;
        const back = NEIGHBORS[st.to][OPPOSITE[arrive]];
        assert.ok(
          back.some((b) => b.to === c && b.flip === st.flip),
          `retour manquant ${cellName(c)} -> ${cellName(st.to)} (dir ${d})`,
        );
      }
    }
    for (const k of KING_ADJ[c]) assert.ok(KING_ADJ[k].includes(c));
    for (const k of KNIGHT_ADJ[c]) assert.ok(KNIGHT_ADJ[k].includes(c));
  }
});

test('symétrie de rotation entre les 3 joueurs', () => {
  for (let c = 0; c < NUM_CELLS; c++) {
    for (const k of [1, 2]) {
      const rc = rotateCell(c, k);
      for (let d = 0; d < 8; d++) {
        const a = NEIGHBORS[c][d].map((s) => `${rotateCell(s.to, k)}/${s.flip}`).sort();
        const b = NEIGHBORS[rc][d].map((s) => `${s.to}/${s.flip}`).sort();
        assert.deepEqual(a, b);
      }
      assert.deepEqual(KING_ADJ[c].map((x) => rotateCell(x, k)).sort((x, y) => x - y), [...KING_ADJ[rc]]);
      assert.deepEqual(KNIGHT_ADJ[c].map((x) => rotateCell(x, k)).sort((x, y) => x - y), [...KNIGHT_ADJ[rc]]);
      for (let p = 0; p < 3; p++) {
        const q = (p + k) % 3;
        assert.deepEqual(
          PAWN_CAPTURES[p][c].map((x) => rotateCell(x, k)).sort((x, y) => x - y),
          [...PAWN_CAPTURES[q][rc]],
        );
        const push = PAWN_PUSH[p][c];
        assert.equal(push < 0 ? -1 : rotateCell(push, k), PAWN_PUSH[q][rc]);
      }
    }
  }
});

test('traversée du centre : colonnes prolongées et diagonale dédoublée', () => {
  const at = (n: string, df: number, dr: number) => names(NEIGHBORS[parseCell(n)][dirIndex(df, dr)].map((s) => s.to));
  assert.deepEqual(at('0d4', 0, 1), ['2e4']);
  assert.deepEqual(at('0e4', 0, 1), ['1d4']);
  assert.deepEqual(at('0a4', 0, 1), ['2h4']);
  assert.deepEqual(at('0d4', 1, 1), ['1d4', '2d4']);
  assert.deepEqual(at('0e4', -1, 1), ['1e4', '2e4']);
  assert.deepEqual(at('0c4', 1, 1), ['2e4']);
  assert.deepEqual(at('0h4', 1, 1), []);
  const ray = (n: string, d: number) => {
    const out: number[] = [];
    walkRay(parseCell(n), d, (c) => (out.push(c), true));
    return names(out);
  };
  assert.deepEqual(ray('0d1', 0), names(['0d2', '0d3', '0d4', '2e4', '2e3', '2e2', '2e1'].map(parseCell)));
  assert.deepEqual(
    ray('0a1', 4),
    names(['0b2', '0c3', '0d4', '1d4', '1c3', '1b2', '1a1', '2d4', '2c3', '2b2', '2a1'].map(parseCell)),
  );
  assert.equal(DIRS.length, 8);
});

test('géométrie cohérente avec la topologie', () => {
  const cells = boardCells();
  assert.equal(cells.length, 96);
  const key = (p: [number, number]) => `${p[0].toFixed(6)},${p[1].toFixed(6)}`;
  const vset = cells.map((g) => new Set(g.polygon.map(key)));
  for (const g of cells) {
    assert.equal(g.id, cellName(g.index));
    assert.ok(g.x > 0 && g.x < 1 && g.y > 0 && g.y < 1);
    // Aire non nulle, orientation homogène.
    const p = g.polygon;
    let area = 0;
    for (let i = 0; i < 4; i++) area += p[i][0] * p[(i + 1) % 4][1] - p[(i + 1) % 4][0] * p[i][1];
    assert.ok(Math.abs(area) > 1e-4);
  }
  for (let c = 0; c < NUM_CELLS; c++) {
    for (let d = 0; d < 8; d++) {
      for (const st of NEIGHBORS[c][d]) {
        const common = [...vset[c]].filter((v) => vset[st.to].has(v)).length;
        assert.equal(common, d < 4 ? 2 : 1, `${cellName(c)} / ${cellName(st.to)}`);
      }
    }
  }
  // Rotation de 120° (sens trigonométrique à l'écran, y vers le bas) : secteur p → p+1.
  const rot = (x: number, y: number): [number, number] => {
    const a = (2 * Math.PI) / 3;
    const dx = x - 0.5;
    const dy = -(y - 0.5);
    return [0.5 + dx * Math.cos(a) - dy * Math.sin(a), 0.5 - (dx * Math.sin(a) + dy * Math.cos(a))];
  };
  for (const g of cells) {
    const [x, y] = rot(g.x, g.y);
    const h = cells[rotateCell(g.index, 1)];
    assert.ok(Math.abs(x - h.x) < 1e-6 && Math.abs(y - h.y) < 1e-6, g.id);
  }
});
