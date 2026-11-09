import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyMove, initialState, legalMoves, randomMove, resign, status } from '../src/index.ts';
import type { GameState, Player } from '../src/index.ts';
import { rngFrom } from './helpers.ts';

function checkInvariants(s: GameState, prev: GameState) {
  assert.equal(s.board.length, 144);
  assert.ok(s.board.filter(Boolean).length <= prev.board.filter(Boolean).length);
  for (const p of [0, 1, 2] as Player[]) {
    if (s.active[p] && !s.result) assert.equal(s.board.filter((x) => x?.type === 'K' && x.owner === p).length, 1, `roi ${p}`);
    if (prev.hilts[p]) assert.ok(s.hilts[p], 'une poignée ouverte le reste');
    if (!prev.active[p]) assert.ok(!s.active[p]);
  }
  for (const pc of s.board) if (pc?.crossed) assert.equal(pc.type, 'P');
  if (!s.result) {
    assert.ok(s.active[s.turn]);
    // L'équipe au trait n'a jamais son roi en échec sans coup légal.
    assert.ok(legalMoves(s).length > 0);
  }
}

test('200 parties aléatoires complètes sans exception, invariants respectés', () => {
  const reasons: Record<string, number> = {};
  let promotions = 0;
  let centers = 0;
  let kingCaptures = 0;
  let eps = 0;
  for (let g = 0; g < 200; g++) {
    const rng = rngFrom(1000 + g);
    let s = initialState(g % 2 ? 'twoMates' : 'firstMate');
    while (!s.result) {
      const prev = s;
      if (rng() < 0.0005) {
        s = resign(s, s.turn);
      } else {
        const m = randomMove(s, rng);
        // Variante de promotion au hasard quand elle existe.
        const variants = legalMoves(s).filter((x) => x.from === m.from && x.to === m.to);
        assert.ok(variants.length >= 1);
        const pick = variants[Math.floor(rng() * variants.length)];
        s = applyMove(s, pick);
        const ev = s.lastEvent!;
        if (ev.promotion) promotions++;
        if (ev.crossedCenter) centers++;
        if (ev.kingCaptured !== null && ev.kingCaptured !== undefined) kingCaptures++;
        if (ev.enPassant) eps++;
      }
      checkInvariants(s, prev);
      assert.ok(s.ply < 5000);
    }
    reasons[s.result.reason] = (reasons[s.result.reason] ?? 0) + 1;
    assert.ok(status(s).over);
    assert.deepEqual(legalMoves(s), []);
  }
  // Les règles particulières apparaissent bien dans des parties réelles.
  // (La prise en passant est rare au hasard : elle est couverte par moves.test.ts.)
  assert.ok(promotions > 0 && centers > 0 && kingCaptures > 0, JSON.stringify({ promotions, centers, eps, kingCaptures, reasons }));
});
