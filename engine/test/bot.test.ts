import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  applyMove,
  botDecision,
  botMove,
  cellName,
  customState,
  initialState,
  isCellAttacked,
  legalMoves,
  randomMove,
  DEFAULT_BOT_CPU_MS,
  NODES_PER_MS,
} from '../src/index.ts';
import type { BotLevel, GameState, Move, Player } from '../src/index.ts';
import { rngFrom } from './helpers.ts';

const LEVELS: BotLevel[] = ['facile', 'moyen', 'difficile'];
const isLegal = (s: GameState, m: Move) => legalMoves(s).some((x) => x.from === m.from && x.to === m.to);

test('les bots jouent toujours un coup légal (parties complètes facile/moyen, positions variées en difficile)', () => {
  for (let g = 0; g < 6; g++) {
    const rng = rngFrom(10 + g);
    let s = initialState(g % 2 ? 'twoMates' : 'firstMate');
    const levels: BotLevel[] = g < 3 ? ['facile', 'moyen', 'facile'] : ['moyen', 'facile', 'moyen'];
    while (!s.result && s.ply < 600) {
      const m = botMove(s, levels[s.turn], { rng });
      assert.ok(isLegal(s, m), `coup illégal ${m.from}-${m.to}`);
      s = applyMove(s, m);
    }
  }
  const rng = rngFrom(99);
  let s = initialState('twoMates');
  for (let i = 0; i < 40 && !s.result; i++) {
    const m = i % 4 === 0 ? botMove(s, 'difficile', { rng, maxNodes: 400 }) : randomMove(s, rng);
    assert.ok(isLegal(s, m));
    s = applyMove(s, m);
  }
});

test('déterministe avec un rng injecté', () => {
  let s = initialState('firstMate');
  const r = rngFrom(5);
  for (let i = 0; i < 12; i++) s = applyMove(s, randomMove(s, r));
  for (const level of LEVELS) {
    const a = botDecision(s, level, { rng: rngFrom(7), now: () => 0 });
    const b = botDecision(s, level, { rng: rngFrom(7), now: () => 0 });
    assert.deepEqual(a, b, level);
  }
});

/** Positions (issues de parties aléatoires) où le joueur au trait peut mater en un coup. */
function mateInOnePositions(count: number): GameState[] {
  const out: GameState[] = [];
  for (let seed = 1; out.length < count && seed < 400; seed++) {
    const rng = rngFrom(seed);
    let s = initialState('firstMate');
    while (!s.result && out.length < count) {
      const ms = legalMoves(s);
      if (ms.some((m) => applyMove(s, m).result?.winner === s.turn)) {
        out.push(s);
        break;
      }
      s = applyMove(s, randomMove(s, rng));
    }
  }
  return out;
}

test('moyen et difficile privilégient le mat', () => {
  const positions = mateInOnePositions(5);
  assert.ok(positions.length >= 3);
  for (const s of positions) {
    for (const level of ['moyen', 'difficile'] as BotLevel[]) {
      const m = botMove(s, level, { rng: rngFrom(1), now: () => 0 });
      assert.equal(applyMove(s, m).result?.winner, s.turn, `${level} doit mater`);
    }
  }
});

test('facile prend une pièce gratuite (quand son tirage le décide)', () => {
  const s = customState('firstMate', [
    { cell: '0e1', type: 'K', owner: 0 },
    { cell: '0a1', type: 'R', owner: 0 },
    { cell: '0a4', type: 'Q', owner: 1 },
    { cell: '1e1', type: 'K', owner: 1 },
    { cell: '2e1', type: 'K', owner: 2 },
  ]);
  assert.deepEqual(botMove(s, 'facile', { rng: () => 0.1 }), { from: '0a1', to: '0a4', capture: true });
  // Sinon, coup aléatoire (légal).
  assert.ok(isLegal(s, botMove(s, 'facile', { rng: () => 0.9 })));
});

test('moyen ne laisse pas sa dame en prise', () => {
  const s = customState('firstMate', [
    { cell: '0e1', type: 'K', owner: 0 },
    { cell: '0d3', type: 'Q', owner: 0 },
    { cell: '0a2', type: 'P', owner: 0 },
    { cell: '0h2', type: 'P', owner: 0 },
    { cell: '0c4', type: 'P', owner: 1 },
    { cell: '1e1', type: 'K', owner: 1 },
    { cell: '2e1', type: 'K', owner: 2 },
  ]);
  assert.ok(isCellAttacked(s, '0d3', 1));
  for (let seed = 0; seed < 5; seed++) {
    const m = botMove(s, 'moyen', { rng: rngFrom(seed) });
    const after = applyMove(s, m);
    const q = after.board.findIndex((p) => p?.type === 'Q' && p.owner === 0);
    assert.ok(q >= 0, 'la dame est toujours là');
    const cell = cellName(q);
    assert.ok(!isCellAttacked(after, cell, 1) && !isCellAttacked(after, cell, 2), `dame en prise après ${m.from}-${m.to}`);
  }
});

test('budget de temps respecté, repli sur un coup légal, garde-fou si l\'horloge est figée', () => {
  const rng = rngFrom(3);
  let s = initialState('firstMate');
  let worst = 0;
  for (let i = 0; i < 30 && !s.result; i++) {
    if (i % 3 === 1) {
      for (const level of LEVELS) {
        const t = performance.now();
        const d = botDecision(s, level, { rng });
        const dt = performance.now() - t;
        worst = Math.max(worst, dt);
        assert.ok(isLegal(s, d.move));
      }
      // Horloge figée (cas d'un Worker) : le plafond de nœuds borne la recherche.
      const frozen = botDecision(s, 'difficile', { rng, now: () => 0 });
      assert.ok(frozen.nodes <= DEFAULT_BOT_CPU_MS * NODES_PER_MS, `nœuds : ${frozen.nodes}`);
      // Budget nul ou déjà dépassé : repli immédiat, toujours légal.
      let tick = 0;
      for (const level of LEVELS) {
        const d = botDecision(s, level, { rng, now: () => (tick += 100) });
        assert.ok(isLegal(s, d.move), level);
        assert.ok(d.nodes <= 1);
      }
    }
    s = applyMove(s, randomMove(s, rng));
  }
  // Budget de 8 ms (+ dépassement d'au plus un nœud et marge pour les machines lentes).
  assert.ok(worst < DEFAULT_BOT_CPU_MS + 25, `pire temps ${worst.toFixed(1)} ms`);
  const custom = botDecision(initialState('twoMates'), 'difficile', { rng, timeBudgetMs: 3, now: () => 0 });
  assert.ok(custom.nodes <= 3 * NODES_PER_MS);
});

test('2 bots difficiles contre 1 facile : le facile gagne rarement', () => {
  const VAL: Record<string, number> = { P: 1, N: 3, B: 3, R: 5, Q: 9, K: 0 };
  let weakWins = 0;
  let strongWins = 0;
  const N = 20;
  for (let g = 0; g < N; g++) {
    const rng = rngFrom(100 + g);
    const weak = (g % 3) as Player;
    let s = initialState(g % 2 ? 'twoMates' : 'firstMate');
    // Parties courtes (90 demi-coups), budget par défaut (8 ms) avec horloge figée comme dans
    // un Worker : seul le plafond de nœuds joue, ce qui rend le test déterministe.
    while (!s.result && s.ply < 90) {
      s = applyMove(s, botMove(s, s.turn === weak ? 'facile' : 'difficile', { rng, now: () => 0 }));
    }
    let winner: Player | null = s.result ? s.result.winner : null;
    if (!s.result) {
      // Arbitrage au matériel des joueurs encore en jeu.
      const m = [0, 0, 0];
      s.board.forEach((pc) => {
        if (pc && s.active[pc.owner]) m[pc.owner] += VAL[pc.type];
      });
      for (const p of [0, 1, 2]) if (!s.active[p]) m[p] = -1;
      winner = m.indexOf(Math.max(...m)) as Player;
    }
    if (winner === weak) weakWins++;
    else if (winner !== null) strongWins++;
  }
  assert.ok(weakWins <= 3, `le facile a gagné ${weakWins} parties`);
  assert.ok(strongWins >= N * 0.7, `les difficiles n'ont gagné que ${strongWins} parties`);
});
