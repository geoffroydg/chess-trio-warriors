import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyMove, customState, initialState, legalMoves, pieceAt, resign, status } from '../src/index.ts';
import type { CustomPiece, GameState, Mode } from '../src/index.ts';
import { mv, sorted, targets } from './helpers.ts';

const allMoves = (s: GameState) => sorted([...new Set(legalMoves(s).map((m) => `${m.from}-${m.to}`))]);

test('un coup qui laisse son roi en échec est illégal ; parer un échec', () => {
  let s = customState(
    'firstMate',
    [
      { cell: '0d1', type: 'K', owner: 0 },
      { cell: '0b3', type: 'R', owner: 0 },
      { cell: '0d5', type: 'R', owner: 1 },
      { cell: '1d1', type: 'K', owner: 1 },
      { cell: '2d1', type: 'K', owner: 2 },
    ],
    { turn: 1 },
  );
  s = applyMove(s, mv('0d5', '0d3'));
  assert.deepEqual(s.lastEvent?.checks, [{ player: 0, by: [1] }]);
  s = applyMove(s, mv('2d1', '2c1'));
  assert.equal(status(s).inCheck, true);
  // Fuir (0c1, 0c2, 0e1, 0e2), prendre avec la tour (0b3 → 0d3), ou s'interposer en 0d2 : non, la tour ne l'atteint pas.
  assert.deepEqual(allMoves(s), sorted(['0d1-0c1', '0d1-0c2', '0d1-0e1', '0d1-0e2', '0b3-0d3']));
  assert.throws(() => applyMove(s, mv('0b3', '0b4')));
});

const matePosition = (mode: Mode) =>
  customState(
    mode,
    [
      { cell: '0d1', type: 'K', owner: 0 },
      { cell: '0c2', type: 'P', owner: 0 },
      { cell: '0d2', type: 'P', owner: 0 },
      { cell: '0e2', type: 'P', owner: 0 },
      { cell: '0h3', type: 'R', owner: 1 },
      { cell: '1d1', type: 'K', owner: 1 },
      { cell: '2d1', type: 'K', owner: 2 },
      { cell: '0f5', type: 'N', owner: 2 },
    ],
    { turn: 1 },
  );

test('mat seulement au tour de l’équipe matée ; firstMate : fin, crédit à l’attaquant', () => {
  let s = applyMove(matePosition('firstMate'), mv('0h3', '0h1'));
  assert.deepEqual(s.lastEvent?.checks, [{ player: 0, by: [1] }]);
  assert.equal(s.result, null);
  assert.equal(s.turn, 2);
  s = applyMove(s, mv('2d1', '2c1'));
  assert.deepEqual(s.lastEvent?.mates, [{ player: 0, by: 1 }]);
  assert.deepEqual(s.result, { winner: 1, reason: 'mate' });
  assert.deepEqual(legalMoves(s), []);
});

test('mat par deux attaquants : crédit au dernier ayant joué', () => {
  let s = applyMove(matePosition('firstMate'), mv('0h3', '0h1'));
  s = applyMove(s, mv('0f5', '0e3'));
  assert.deepEqual(s.lastEvent?.mates, [{ player: 0, by: 2 }]);
  assert.deepEqual(s.result, { winner: 2, reason: 'mate' });
});

test('twoMates : l’équipe matée devient fossile (gelée, sans échec, prenable) ; la partie continue', () => {
  let s = applyMove(matePosition('twoMates'), mv('0h3', '0h1'));
  s = applyMove(s, mv('2d1', '2c1'));
  assert.equal(s.result, null);
  assert.deepEqual(s.active, [false, true, true]);
  assert.deepEqual(s.lastEvent?.eliminated, [0]);
  assert.deepEqual(s.eliminations, [{ player: 0, by: 1, reason: 'mate', ply: 2 }]);
  assert.deepEqual(s.hilts, [true, false, true]);
  assert.equal(s.turn, 1);
  // Les fossiles restent ; le roi fossile peut être pris (sans élimination supplémentaire).
  assert.equal(pieceAt(s, '0d1')?.type, 'K');
  const take = applyMove(s, mv('0h1', '0d1'));
  assert.deepEqual(take.lastEvent?.captured, { type: 'K', owner: 0, frozen: true, at: '0d1' });
  assert.equal(take.lastEvent?.kingCaptured, null);
  assert.equal(take.result, null);
  // Les pions fossiles ne donnent pas échec : le roi 2 peut aller en 0e3 / 0c3 attaquées par 0d2.
});

test('roi emprisonné : en échec hors de son tour, l’équipe au trait peut le capturer', () => {
  const build = (mode: Mode) =>
    customState(mode, [
      { cell: '0d1', type: 'K', owner: 0 },
      { cell: '2h4', type: 'N', owner: 0 },
      { cell: '1a4', type: 'R', owner: 1 },
      { cell: '1d1', type: 'K', owner: 1 },
      { cell: '2g4', type: 'K', owner: 2 },
      { cell: '2f4', type: 'P', owner: 2 },
      { cell: '2h1', type: 'N', owner: 2 },
    ]);
  for (const mode of ['twoMates', 'firstMate'] as Mode[]) {
    const s0 = build(mode);
    assert.deepEqual(status(s0).checks, []);
    assert.deepEqual(s0.hilts, [false, false, false]);
    // L'équipe 0 dégage la ligne de la tour de l'équipe 1 : le roi 2 est en échec, mais c'est au tour de 1.
    const s = applyMove(s0, mv('2h4', '1a6'));
    assert.equal(s.turn, 1);
    assert.deepEqual(s.lastEvent?.checks, [{ player: 2, by: [1] }]);
    assert.ok(targets(s, '1a4').includes('2g4'));
    const t = applyMove(s, mv('1a4', '2g4'));
    assert.equal(t.lastEvent?.kingCaptured, 2);
    assert.deepEqual(t.lastEvent?.mates, [{ player: 2, by: 1 }]);
    if (mode === 'firstMate') {
      assert.deepEqual(t.result, { winner: 1, reason: 'mate' });
    } else {
      assert.equal(t.result, null);
      assert.deepEqual(t.active, [true, true, false]);
      assert.deepEqual(t.eliminations, [{ player: 2, by: 1, reason: 'mate', ply: 2 }]);
      assert.deepEqual(t.lastEvent?.eliminated, [2]);
      assert.deepEqual(t.lastEvent?.hiltsOpened, [1, 2]);
      assert.equal(t.turn, 0);
      assert.equal(pieceAt(t, '2f4')?.owner, 2); // fossile
    }
  }
});

test('pat : l’équipe sans coup légal (hors échec) passe son tour', () => {
  let s = customState('twoMates', [
    { cell: '0d1', type: 'K', owner: 0 },
    { cell: '1a1', type: 'K', owner: 1 },
    { cell: '1b6', type: 'R', owner: 2 },
    { cell: '1e2', type: 'R', owner: 2 },
    { cell: '2d1', type: 'K', owner: 2 },
  ]);
  assert.deepEqual(status(s).checks, []);
  s = applyMove(s, mv('0d1', '0c1'));
  assert.deepEqual(s.lastEvent?.passes, [1]);
  assert.equal(s.turn, 2);
  assert.equal(s.quietTurns, 2);
  assert.equal(s.result, null);
});

test('aucune équipe ne peut jouer : à 3 l’équipe au trait perd, à 2 partie nulle', () => {
  const build = (mode: Mode) =>
    customState(mode, [
      { cell: '0a5', type: 'P', owner: 0 },
      { cell: '2e6', type: 'P', owner: 0 },
    ]);
  assert.deepEqual(targets(build('firstMate'), '0a5'), ['0a6']);
  const f = applyMove(build('firstMate'), mv('0a5', '0a6'));
  assert.deepEqual(f.lastEvent?.passes, [1, 2, 0]);
  assert.deepEqual(f.lastEvent?.blocked, { player: 1, by: 0 });
  assert.deepEqual(f.result, { winner: 0, reason: 'blockade' });
  const t = applyMove(build('twoMates'), mv('2e6', '0a6'));
  assert.equal(t.lastEvent?.crossedCenter, true);
  assert.deepEqual(t.eliminations, [{ player: 1, by: 0, reason: 'blocked', ply: 1 }]);
  assert.deepEqual(t.lastEvent?.passes, [1, 2, 0, 2, 0]);
  assert.deepEqual(t.result, { winner: null, reason: 'stalemate' });
});

test('abandon : éliminé sans crédit, tour suivant ; dernier restant vainqueur', () => {
  let s = initialState('twoMates');
  s = resign(s, 0);
  assert.equal(s.turn, 1);
  assert.deepEqual(s.eliminations, [{ player: 0, by: null, reason: 'resign', ply: 0 }]);
  assert.deepEqual(s.hilts, [true, false, true]);
  assert.throws(() => resign(s, 0));
  s = resign(s, 2);
  assert.deepEqual(s.result, { winner: 1, reason: 'lastStanding' });
  assert.throws(() => applyMove(s, mv('1e2', '1e3')));
});

test('règle des 50 coups (50 × équipes actives) et triple répétition', () => {
  const kings: CustomPiece[] = [
    { cell: '0d1', type: 'K', owner: 0 },
    { cell: '0a1', type: 'R', owner: 0 },
    { cell: '1d1', type: 'K', owner: 1 },
    { cell: '2d1', type: 'K', owner: 2 },
  ];
  let s = customState('twoMates', kings);
  const cycle = [mv('0d1', '0c1'), mv('1d1', '1c1'), mv('2d1', '2c1'), mv('0c1', '0d1'), mv('1c1', '1d1'), mv('2c1', '2d1')];
  for (let i = 0; i < 12; i++) {
    assert.equal(s.result, null);
    s = applyMove(s, cycle[i % 6]);
  }
  assert.deepEqual(s.result, { winner: null, reason: 'repetition' });
  assert.equal(s.ply, 12);
  const f = { ...customState('twoMates', kings), quietTurns: 149 };
  assert.equal(status(f).fiftyMoveLimit, 150);
  assert.deepEqual(applyMove(f, mv('0a1', '0a2')).result, { winner: null, reason: 'fiftyMoves' });
  // Un coup de pion remet le compteur à zéro.
  const p = { ...customState('twoMates', [...kings, { cell: '0e2', type: 'P', owner: 0 }]), quietTurns: 149 };
  const after = applyMove(p, mv('0e2', '0e3'));
  assert.equal(after.result, null);
  assert.equal(after.quietTurns, 0);
});

test('états sérialisables en JSON et rejouables', () => {
  let s = initialState('twoMates');
  s = applyMove(s, mv('0e2', '0e4'));
  const back = JSON.parse(JSON.stringify(s)) as GameState;
  assert.deepEqual(legalMoves(back), legalMoves(s));
  assert.deepEqual(back.enPassant, [{ target: '0e3', pawn: '0e4', owner: 0 }]);
  assert.equal(back.version, 2);
});
