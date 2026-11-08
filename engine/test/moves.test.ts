import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyMove, customState, initialState, legalMoves, pieceAt } from '../src/index.ts';
import type { CustomPiece } from '../src/index.ts';
import { mv, sorted, targets } from './helpers.ts';

const KINGS: CustomPiece[] = [
  { cell: '0h1', type: 'K', owner: 0 },
  { cell: '1h1', type: 'K', owner: 1 },
  { cell: '2h1', type: 'K', owner: 2 },
];
const withKings = (pieces: CustomPiece[]) => [...KINGS.filter((k) => !pieces.some((p) => p.cell === k.cell)), ...pieces];

test('position initiale : 20 coups par joueur, symétrique', () => {
  let s = initialState('firstMate');
  assert.equal(legalMoves(s).length, 20);
  assert.deepEqual(targets(s, '0b1'), ['0a3', '0c3']);
  assert.deepEqual(targets(s, '0e2'), ['0e3', '0e4']);
  s = applyMove(s, mv('0e2', '0e4'));
  assert.equal(s.turn, 1);
  assert.equal(legalMoves(s).length, 20);
  assert.ok(legalMoves(s).every((m) => m.from.startsWith('1')));
});

test('tour : la colonne d se prolonge en colonne e du secteur voisin', () => {
  const s = customState('firstMate', withKings([{ cell: '0d1', type: 'R', owner: 0 }]));
  assert.deepEqual(
    targets(s, '0d1'),
    sorted(['0a1', '0b1', '0c1', '0e1', '0f1', '0g1', '0d2', '0d3', '0d4', '2e4', '2e3', '2e2', '2e1']),
  );
});

test('tour : prise et blocage à travers le centre', () => {
  const s = customState(
    'firstMate',
    withKings([
      { cell: '0d1', type: 'R', owner: 0 },
      { cell: '2e3', type: 'N', owner: 2 },
    ]),
  );
  assert.deepEqual(
    targets(s, '0d1').filter((c) => !c.endsWith('1') || c.startsWith('2')),
    sorted(['0d2', '0d3', '0d4', '2e4', '2e3']),
  );
});

test('fou : la diagonale centrale se dédouble', () => {
  const s = customState('firstMate', withKings([{ cell: '0a1', type: 'B', owner: 0 }]));
  assert.deepEqual(
    targets(s, '0a1'),
    sorted(['0b2', '0c3', '0d4', '1d4', '1c3', '1b2', '1a1', '2d4', '2c3', '2b2', '2a1']),
  );
});

test('dame au centre', () => {
  const s = customState('firstMate', withKings([{ cell: '0d4', type: 'Q', owner: 0 }]));
  const t = targets(s, '0d4');
  for (const c of ['0a4', '0h4', '0d1', '2e1', '1d4', '2d4', '1a1', '2a1', '0a1', '2f4', '2h2', '0g1']) {
    assert.ok(t.includes(c), c);
  }
  assert.ok(!t.includes('1e4'));
});

test('cavalier : coin, centre et saut entre secteurs', () => {
  const s = customState(
    'firstMate',
    withKings([
      { cell: '0a1', type: 'N', owner: 0 },
      { cell: '0d4', type: 'N', owner: 0 },
      { cell: '0c3', type: 'N', owner: 0 },
    ]),
  );
  assert.deepEqual(targets(s, '0a1'), ['0b3', '0c2']);
  assert.deepEqual(targets(s, '0c3'), sorted(['0b1', '0d1', '0a2', '0e2', '0a4', '0e4', '2e4', '2g4']));
  assert.deepEqual(
    targets(s, '0d4'),
    sorted(['0c2', '0e2', '0b3', '0f3', '1d3', '1c4', '2d3', '2f3', '2c4', '2g4']),
  );
});

test('roi : 9 cases au centre', () => {
  const s = customState('firstMate', [
    { cell: '0d4', type: 'K', owner: 0 },
    { cell: '1h1', type: 'K', owner: 1 },
    { cell: '2h1', type: 'K', owner: 2 },
  ]);
  assert.deepEqual(targets(s, '0d4'), sorted(['0c3', '0d3', '0e3', '0c4', '0e4', '1d4', '2d4', '2e4', '2f4']));
});

test('pion : avance, double pas, traversée du centre, prises', () => {
  let s = customState(
    'firstMate',
    withKings([
      { cell: '0c2', type: 'P', owner: 0 },
      { cell: '0d4', type: 'P', owner: 0 },
      { cell: '1d4', type: 'B', owner: 1 },
      { cell: '2d4', type: 'B', owner: 2 },
      { cell: '2f4', type: 'B', owner: 2 },
      { cell: '0e3', type: 'P', owner: 0 },
      { cell: '2c3', type: 'P', owner: 0 },
    ]),
  );
  assert.deepEqual(targets(s, '0c2'), ['0c3', '0c4']);
  assert.deepEqual(targets(s, '0d4'), sorted(['2e4', '1d4', '2d4', '2f4']));
  // Un pion dans le secteur adverse avance vers la rangée 1 de ce secteur.
  assert.deepEqual(targets(s, '2c3'), ['2c2']);
  // Pion bloqué par sa propre pièce ? 0e3 -> 0e4 libre.
  assert.deepEqual(targets(s, '0e3'), ['0e4']);
  s = applyMove(s, mv('0d4', '2e4'));
  assert.equal(pieceAt(s, '2e4')?.type, 'P');
});

test('pas de double pas hors de la rangée 2 initiale, pas de prise en passant', () => {
  let s = customState(
    'firstMate',
    withKings([
      { cell: '0e3', type: 'P', owner: 0 },
      { cell: '1d2', type: 'P', owner: 1 },
      { cell: '0b2', type: 'P', owner: 0 },
      { cell: '1e4', type: 'P', owner: 0 },
      { cell: '2a2', type: 'P', owner: 2 },
    ]),
    { turn: 1 },
  );
  s = applyMove(s, mv('1d2', '1d4'));
  s = applyMove(s, mv('2a2', '2a3'));
  // Le pion 1d2 a sauté 1d3 à côté du pion blanc 1e4 : pas de prise en passant.
  assert.deepEqual(targets(s, '1e4'), ['1e3']);
  assert.deepEqual(targets(s, '0e3'), ['0e4']);
});

test('promotion automatique en dame sur la rangée 1 adverse', () => {
  let s = customState('firstMate', withKings([{ cell: '2e2', type: 'P', owner: 0 }]));
  const m = legalMoves(s).find((x) => x.from === '2e2');
  assert.deepEqual(m, { from: '2e2', to: '2e1', promotion: 'Q' });
  s = applyMove(s, mv('2e2', '2e1'));
  assert.deepEqual(pieceAt(s, '2e1'), { type: 'Q', owner: 0 });
  assert.equal(s.lastEvent?.promotion, 'Q');
  assert.equal(s.lastEvent?.piece, 'P');
});

test('coup illégal : erreur', () => {
  const s = initialState('firstMate');
  assert.throws(() => applyMove(s, mv('0e2', '0e5')));
  assert.throws(() => applyMove(s, mv('0e2', '0e1')));
  assert.throws(() => applyMove(s, mv('1e2', '1e4')));
});
