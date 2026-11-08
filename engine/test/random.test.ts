import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyMove, initialState, isCellAttacked, legalMoves, randomMove, resign, status } from '../src/index.ts';
import type { GameState, Mode, Player } from '../src/index.ts';
import { KING_ADJ, KNIGHT_ADJ, NUM_CELLS, PAWN_CAPTURES, cellName, walkRay } from '../src/topology.ts';
import { rngFrom } from './helpers.ts';

/** Attaques calculées « vers l'avant » depuis chaque pièce (référence indépendante de la recherche inverse). */
function forwardAttacks(s: GameState, by: Player): Set<number> {
  const out = new Set<number>();
  if (!s.active[by]) return out;
  s.board.forEach((pc, c) => {
    if (!pc || pc.owner !== by) return;
    const rays = (dirs: number[]) => {
      for (const d of dirs) walkRay(c, d, (t) => (out.add(t), s.board[t] === null));
    };
    if (pc.type === 'P') PAWN_CAPTURES[by][c].forEach((t) => out.add(t));
    else if (pc.type === 'N') KNIGHT_ADJ[c].forEach((t) => out.add(t));
    else if (pc.type === 'K') KING_ADJ[c].forEach((t) => out.add(t));
    else if (pc.type === 'R') rays([0, 1, 2, 3]);
    else if (pc.type === 'B') rays([4, 5, 6, 7]);
    else rays([0, 1, 2, 3, 4, 5, 6, 7]);
  });
  return out;
}

function playRandomGame(seed: number, mode: Mode, checkAttacks: boolean): GameState {
  const rng = rngFrom(seed);
  let s = initialState(mode);
  for (let i = 0; i < 20000 && !s.result; i++) {
    // De temps en temps, un abandon (déconnexion).
    if (rng() < 0.0015) {
      const actives = ([0, 1, 2] as Player[]).filter((p) => s.active[p]);
      s = resign(s, actives[Math.floor(rng() * actives.length)]);
      continue;
    }
    const legal = legalMoves(s);
    assert.ok(legal.length > 0, 'le joueur au trait doit avoir un coup');
    const m = randomMove(s, rng);
    assert.ok(legal.some((x) => x.from === m.from && x.to === m.to), 'randomMove doit être légal');
    const before = s;
    s = applyMove(s, m);
    // Aucun roi actif n'est jamais pris, et le joueur qui vient de jouer n'est pas en échec.
    const kings = s.board.filter((p) => p?.type === 'K').length;
    assert.equal(kings, before.board.filter((p) => p?.type === 'K').length - (s.lastEvent?.captured?.type === 'K' ? 1 : 0));
    if (s.lastEvent?.captured?.type === 'K') assert.equal(before.active[s.lastEvent.captured.owner], false);
    if (!s.result) {
      assert.ok(!status(s).checks.some((c) => c.player === before.turn && s.active[before.turn]));
      assert.ok(s.active[s.turn]);
    }
    if (checkAttacks && i % 7 === 0) {
      for (const p of [0, 1, 2] as Player[]) {
        const ref = forwardAttacks(s, p);
        for (let c = 0; c < NUM_CELLS; c++) {
          assert.equal(isCellAttacked(s, cellName(c), p), ref.has(c), `attaque ${p} sur ${cellName(c)}`);
        }
      }
    }
  }
  return s;
}

test('200 parties aléatoires jouées jusqu’au bout sans exception', () => {
  const reasons: Record<string, number> = {};
  for (let g = 0; g < 200; g++) {
    const mode: Mode = g % 2 === 0 ? 'firstMate' : 'twoMates';
    const s = playRandomGame(1000 + g, mode, g < 10);
    assert.ok(s.result, `partie ${g} non terminée`);
    reasons[`${mode}:${s.result.reason}`] = (reasons[`${mode}:${s.result.reason}`] ?? 0) + 1;
    assert.deepEqual(legalMoves(s), []);
    assert.throws(() => randomMove(s));
  }
  // Toutes les issues observées sont des fins valides.
  for (const k of Object.keys(reasons)) assert.match(k, /^(firstMate|twoMates):(mate|lastStanding|fiftyMoves|repetition|stalemate)$/);
});

test('randomMove est déterministe avec un rng injecté', () => {
  const s = initialState('firstMate');
  const a = randomMove(s, rngFrom(42));
  const b = randomMove(s, rngFrom(42));
  assert.deepEqual(a, b);
  assert.deepEqual(randomMove(s, () => 0), legalMoves(s)[0]);
  assert.deepEqual(randomMove(s, () => 0.999999), legalMoves(s).at(-1));
});
