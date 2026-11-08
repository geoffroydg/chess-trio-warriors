import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyMove, customState, initialState, legalMoves, pieceAt, resign, status } from '../src/index.ts';
import type { CustomPiece, GameState, Mode } from '../src/index.ts';
import { mv, sorted, targets } from './helpers.ts';

const allTargets = (s: GameState) => sorted(legalMoves(s).map((m) => `${m.from}-${m.to}`));

test('échec donné par le joueur 1 : seuls les coups qui parent sont légaux', () => {
  let s = customState(
    'firstMate',
    [
      { cell: '0e1', type: 'K', owner: 0 },
      { cell: '0c2', type: 'R', owner: 0 },
      { cell: '0a3', type: 'R', owner: 1 },
      { cell: '1h1', type: 'K', owner: 1 },
      { cell: '2d1', type: 'K', owner: 2 },
    ],
    { turn: 1 },
  );
  s = applyMove(s, mv('0a3', '0a1'));
  assert.deepEqual(s.lastEvent?.checks, [{ player: 0, by: [1] }]);
  s = applyMove(s, mv('2d1', '2c1'));
  assert.equal(s.turn, 0);
  assert.equal(status(s).inCheck, true);
  assert.deepEqual(allTargets(s), sorted(['0e1-0d2', '0e1-0e2', '0e1-0f2', '0c2-0c1']));
});

test('échec donné par le joueur 2 à travers le centre (diagonale dédoublée)', () => {
  let s = customState(
    'firstMate',
    [
      { cell: '0a1', type: 'K', owner: 0 },
      { cell: '0h2', type: 'R', owner: 0 },
      { cell: '1e1', type: 'B', owner: 2 },
      { cell: '1h1', type: 'K', owner: 1 },
      { cell: '2h1', type: 'K', owner: 2 },
    ],
    { turn: 2 },
  );
  s = applyMove(s, mv('1e1', '1c3'));
  assert.deepEqual(s.lastEvent?.checks, [{ player: 0, by: [2] }]);
  assert.equal(s.turn, 0);
  // Parades : déplacer le roi hors de la diagonale, ou interposer la tour en 0b2.
  assert.deepEqual(allTargets(s), sorted(['0a1-0a2', '0a1-0b1', '0h2-0b2']));
  // Un coup qui laisse le roi en échec est refusé.
  assert.throws(() => applyMove(s, mv('0h2', '0h3')));
});

const matePosition = (mode: Mode, extra: CustomPiece[] = []) =>
  customState(
    mode,
    [
      { cell: '0e1', type: 'K', owner: 0 },
      { cell: '0d2', type: 'P', owner: 0 },
      { cell: '0e2', type: 'P', owner: 0 },
      { cell: '0f2', type: 'P', owner: 0 },
      { cell: '0a3', type: 'R', owner: 1 },
      { cell: '1e1', type: 'K', owner: 1 },
      { cell: '2e1', type: 'K', owner: 2 },
      ...extra,
    ],
    { turn: 1 },
  );

test('mat simple (firstMate) : la partie se termine, le vainqueur est celui qui a fait mat', () => {
  let s = matePosition('firstMate');
  s = applyMove(s, mv('0a3', '0a1'));
  assert.equal(s.result, null);
  s = applyMove(s, mv('2e1', '2d1'));
  assert.deepEqual(s.result, { winner: 1, reason: 'mate' });
  assert.deepEqual(s.lastEvent?.mates, [{ player: 0, by: 1 }]);
  assert.deepEqual(s.lastEvent?.gameOver, { winner: 1, reason: 'mate' });
  assert.equal(status(s).over, true);
  assert.equal(status(s).turn, null);
  assert.deepEqual(legalMoves(s), []);
  assert.throws(() => applyMove(s, mv('1e1', '1d1')));
});

test('mat par deux attaquants : crédité au dernier à avoir joué', () => {
  let s = matePosition('firstMate', [{ cell: '0h3', type: 'R', owner: 2 }]);
  s = applyMove(s, mv('0a3', '0a1'));
  s = applyMove(s, mv('0h3', '0h1'));
  assert.deepEqual(s.lastEvent?.checks, [{ player: 0, by: [1, 2] }]);
  assert.deepEqual(s.lastEvent?.mates, [{ player: 0, by: 2 }]);
  assert.deepEqual(s.result, { winner: 2, reason: 'mate' });
});

test('mode twoMates : le mat élimine, la partie continue, le dernier restant gagne', () => {
  let s = matePosition('twoMates', [{ cell: '1a2', type: 'R', owner: 1 }]);
  s = applyMove(s, mv('0a3', '0a1'));
  s = applyMove(s, mv('2e1', '2d1'));
  assert.equal(s.result, null);
  assert.deepEqual(s.active, [false, true, true]);
  assert.deepEqual(s.lastEvent?.eliminated, [0]);
  assert.deepEqual(s.eliminations.map((e) => [e.player, e.by, e.reason]), [[0, 1, 'mate']]);
  assert.equal(s.turn, 1);
  // Les pièces du joueur éliminé restent sur le plateau.
  assert.deepEqual(pieceAt(s, '0e1'), { type: 'K', owner: 0 });
  // Deuxième mat : le joueur 1 mate le joueur 2 → victoire du joueur 1.
  let t = customState(
    'twoMates',
    [
      { cell: '0h1', type: 'K', owner: 0 },
      { cell: '2e1', type: 'K', owner: 2 },
      { cell: '2d2', type: 'P', owner: 2 },
      { cell: '2e2', type: 'P', owner: 2 },
      { cell: '2f2', type: 'P', owner: 2 },
      { cell: '2a3', type: 'R', owner: 1 },
      { cell: '1e1', type: 'K', owner: 1 },
    ],
    { turn: 1, active: [false, true, true] },
  );
  t = applyMove(t, mv('2a3', '2a1'));
  assert.deepEqual(t.result, { winner: 1, reason: 'lastStanding' });
  assert.deepEqual(t.lastEvent?.mates, [{ player: 2, by: 1 }]);
  assert.deepEqual(t.lastEvent?.eliminated, [2]);
});

test('pat : le joueur passe son tour sans être éliminé', () => {
  let s = customState(
    'twoMates',
    [
      { cell: '0a1', type: 'K', owner: 0 },
      { cell: '0b4', type: 'R', owner: 1 },
      { cell: '0h2', type: 'R', owner: 1 },
      { cell: '1h1', type: 'K', owner: 1 },
      { cell: '2c1', type: 'K', owner: 2 },
    ],
    { turn: 2 },
  );
  s = applyMove(s, mv('2c1', '2d1'));
  assert.deepEqual(s.lastEvent?.passes, [0]);
  assert.equal(s.turn, 1);
  assert.deepEqual(s.active, [true, true, true]);
  assert.equal(s.result, null);
  // Le joueur 1 libère une case : le joueur 0 rejoue normalement.
  s = applyMove(s, mv('0h2', '0h3'));
  s = applyMove(s, mv('2d1', '2c1'));
  assert.equal(s.turn, 0);
  assert.deepEqual(targets(s, '0a1'), ['0a2']);
});

test('pièces gelées : sans échec, bloquent les lignes, capturables (roi compris)', () => {
  const s = customState(
    'twoMates',
    [
      { cell: '1e1', type: 'K', owner: 1 },
      { cell: '1d1', type: 'N', owner: 1 },
      { cell: '1e3', type: 'Q', owner: 0 },
      { cell: '1f2', type: 'K', owner: 0 },
      { cell: '1e4', type: 'R', owner: 2 },
      { cell: '2h1', type: 'K', owner: 2 },
    ],
    { turn: 1, active: [false, true, true] },
  );
  // La dame gelée en 1e3 ne met pas en échec et bloque la tour 2 en 1e4.
  assert.deepEqual(status(s).checks, []);
  assert.ok(targets(s, '1e1').includes('1e2'));
  assert.ok(targets(s, '1e1').includes('1f2'));
  assert.ok(targets(s, '1d1').includes('1e3'));
  const a = applyMove(s, mv('1d1', '1e3'));
  assert.deepEqual(a.lastEvent?.captured, { type: 'Q', owner: 0, frozen: true, at: '1e3' });
  const b = applyMove(s, mv('1e1', '1f2'));
  assert.deepEqual(b.lastEvent?.captured, { type: 'K', owner: 0, frozen: true, at: '1f2' });
  assert.equal(b.result, null);
  // Les pièces gelées ne jouent jamais : seuls les joueurs actifs ont le trait.
  let c = b;
  for (let i = 0; i < 6; i++) {
    assert.notEqual(c.turn, 0);
    c = applyMove(c, legalMoves(c)[0]);
  }
});

const castlePos = (extra: CustomPiece[] = []) =>
  customState(
    'firstMate',
    [
      { cell: '0e1', type: 'K', owner: 0 },
      { cell: '0a1', type: 'R', owner: 0 },
      { cell: '0h1', type: 'R', owner: 0 },
      { cell: '1e1', type: 'K', owner: 1 },
      { cell: '2e1', type: 'K', owner: 2 },
      ...extra,
    ],
    {
      castling: [
        { king: true, queen: true },
        { king: false, queen: false },
        { king: false, queen: false },
      ],
    },
  );

test('roque : petit et grand roque', () => {
  const s = castlePos();
  const ks = legalMoves(s).filter((m) => m.castle);
  assert.deepEqual(sorted(ks.map((m) => `${m.to}:${m.castle}`)), ['0c1:queen', '0g1:king']);
  const a = applyMove(s, mv('0e1', '0g1'));
  assert.deepEqual(pieceAt(a, '0f1'), { type: 'R', owner: 0 });
  assert.equal(pieceAt(a, '0h1'), null);
  assert.deepEqual(a.lastEvent?.castle, { side: 'king', rookFrom: '0h1', rookTo: '0f1' });
  assert.deepEqual(a.castling[0], { king: false, queen: false });
  const b = applyMove(s, mv('0e1', '0c1'));
  assert.deepEqual(pieceAt(b, '0d1'), { type: 'R', owner: 0 });
  assert.equal(pieceAt(b, '0a1'), null);
});

test("roque interdit en échec ou à travers une case attaquée par n'importe quel adversaire", () => {
  // Tour du joueur 2 qui contrôle 0f1 : pas de petit roque.
  let s = castlePos([{ cell: '0f4', type: 'R', owner: 2 }]);
  assert.deepEqual(legalMoves(s).filter((m) => m.castle).map((m) => m.castle), ['queen']);
  // Fou du joueur 1 qui contrôle 0d1 (diagonale 0a4-0d1) : pas de grand roque.
  s = castlePos([{ cell: '0a4', type: 'B', owner: 1 }]);
  assert.deepEqual(legalMoves(s).filter((m) => m.castle).map((m) => m.castle), ['king']);
  // Roi en échec (tour du joueur 1 sur la colonne e) : aucun roque.
  s = castlePos([{ cell: '0e4', type: 'R', owner: 1 }]);
  assert.deepEqual(legalMoves(s).filter((m) => m.castle), []);
  // Case occupée entre roi et tour.
  s = castlePos([{ cell: '0b1', type: 'N', owner: 0 }]);
  assert.deepEqual(legalMoves(s).filter((m) => m.castle).map((m) => m.castle), ['king']);
});

test('roque : droit perdu après un mouvement de tour', () => {
  let s = castlePos();
  s = applyMove(s, mv('0h1', '0h2'));
  s = applyMove(s, mv('1e1', '1d1'));
  s = applyMove(s, mv('2e1', '2d1'));
  s = applyMove(s, mv('0h2', '0h1'));
  s = applyMove(s, mv('1d1', '1e1'));
  s = applyMove(s, mv('2d1', '2e1'));
  assert.deepEqual(legalMoves(s).filter((m) => m.castle).map((m) => m.castle), ['queen']);
});

test('abandon : élimination sans crédit', () => {
  // twoMates : deux abandons → le dernier gagne.
  let s = initialState('twoMates');
  s = resign(s, 1);
  assert.equal(s.turn, 0);
  assert.deepEqual(s.lastEvent?.eliminated, [1]);
  assert.deepEqual(s.eliminations.map((e) => [e.player, e.by, e.reason]), [[1, null, 'resign']]);
  assert.throws(() => resign(s, 1));
  s = applyMove(s, mv('0e2', '0e4'));
  assert.equal(s.turn, 2);
  s = resign(s, 2);
  assert.deepEqual(s.result, { winner: 0, reason: 'lastStanding' });
  assert.throws(() => resign(s, 0));
  // Abandon du joueur au trait : le trait passe au suivant actif.
  let t = resign(initialState('twoMates'), 0);
  assert.equal(t.turn, 1);
  assert.ok(legalMoves(t).every((m) => m.from.startsWith('1')));
  // firstMate : après un abandon, la partie continue à deux jusqu'au mat suivant.
  let u = matePosition('firstMate');
  u = resign(u, 2);
  assert.equal(u.result, null);
  assert.equal(u.turn, 1);
  u = applyMove(u, mv('0a3', '0a1'));
  assert.deepEqual(u.result, { winner: 1, reason: 'mate' });
});

test('triple répétition : partie nulle', () => {
  let s = customState('firstMate', [
    { cell: '0h1', type: 'K', owner: 0 },
    { cell: '1h1', type: 'K', owner: 1 },
    { cell: '2h1', type: 'K', owner: 2 },
    { cell: '0b1', type: 'N', owner: 0 },
  ]);
  const cycle = ['0h1-0g1', '1h1-1g1', '2h1-2g1', '0g1-0h1', '1g1-1h1', '2g1-2h1'];
  for (let n = 0; n < 2; n++) {
    for (const c of cycle) {
      assert.equal(s.result, null);
      const [f, t] = c.split('-');
      s = applyMove(s, mv(f, t));
    }
  }
  assert.deepEqual(s.result, { winner: null, reason: 'repetition' });
});

test('règle des 50 coups : 50 tours complets sans prise ni mouvement de pion', () => {
  const base = customState('firstMate', [
    { cell: '0h1', type: 'K', owner: 0 },
    { cell: '0b2', type: 'P', owner: 0 },
    { cell: '1h1', type: 'K', owner: 1 },
    { cell: '2h1', type: 'K', owner: 2 },
  ]);
  assert.equal(status(base).fiftyMoveLimit, 150);
  const s: GameState = { ...base, quietTurns: 149 };
  assert.equal(applyMove(s, mv('0b2', '0b3')).result, null);
  assert.equal(applyMove(s, mv('0b2', '0b3')).quietTurns, 0);
  assert.deepEqual(applyMove(s, mv('0h1', '0g1')).result, { winner: null, reason: 'fiftyMoves' });
});

test("évènement de prise à travers le centre et état sérialisable en JSON", () => {
  let s = initialState('twoMates');
  s = applyMove(s, mv('0e2', '0e4'));
  s = applyMove(s, mv('1e2', '1e4'));
  s = applyMove(s, mv('2b1', '2c3'));
  const json = JSON.parse(JSON.stringify(s)) as GameState;
  assert.deepEqual(json, s);
  assert.deepEqual(legalMoves(json), legalMoves(s));
  assert.ok(legalMoves(s).some((m) => m.from === '0e4' && m.to === '1e4' && m.capture));
  s = applyMove(s, mv('0e4', '1e4'));
  assert.deepEqual(s.lastEvent?.captured, { type: 'P', owner: 1, frozen: false, at: '1e4' });
  assert.equal(s.lastEvent?.piece, 'P');
  assert.equal(s.lastEvent?.kind, 'move');
  assert.equal(s.quietTurns, 0);
  // Le pion blanc, désormais dans le secteur 1, avance vers la rangée 1 de ce secteur.
  s = applyMove(s, mv('1d2', '1d3'));
  s = applyMove(s, mv('2c3', '2b1'));
  // Avance vers 1e3, ou prise en diagonale « vers l'avant » (vers la rangée 1 du secteur 1).
  assert.deepEqual(targets(s, '1e4'), ['1d3', '1e3']);
});
