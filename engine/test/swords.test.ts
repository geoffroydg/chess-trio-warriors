import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyMove, customState, isCellAttacked, legalMoves, resign, status } from '../src/index.ts';
import type { CustomPiece } from '../src/index.ts';
import { mv, targets } from './helpers.ts';

const KINGS: CustomPiece[] = [
  { cell: '0d1', type: 'K', owner: 0 },
  { cell: '1d1', type: 'K', owner: 1 },
  { cell: '2d1', type: 'K', owner: 2 },
];

const calm = (s: ReturnType<typeof customState>) => assert.deepEqual(status(s).checks, [], 'position sans échec');

test('poignée fermée : aucun pas horizontal ou diagonal ne la franchit sur l’anneau 1', () => {
  const s = customState('twoMates', [
    ...KINGS,
    { cell: '0a1', type: 'R', owner: 0 },
    { cell: '0a2', type: 'Q', owner: 0 },
    { cell: '0b3', type: 'P', owner: 0 },
  ]);
  calm(s);
  assert.deepEqual(s.hilts, [false, false, false]);
  // Tour : l'horizontale vers 1h1 est barrée ; dans l'autre sens elle s'arrête au roi.
  assert.deepEqual(targets(s, '0a1'), ['0b1', '0c1']);
  // Dame : pas de diagonale 0a2 → 1h1 ; l'horizontale de l'anneau 2 (lame) reste libre.
  assert.ok(!targets(s, '0a2').includes('1h1'));
  assert.ok(targets(s, '0a2').includes('1h2'));
  // Cavalier en 0a1 : 0a1 → 1h3 se décompose en « 1 horizontal (anneau 1, poignée) + 2 verticaux » : interdit.
  const n = customState('twoMates', [...KINGS, { cell: '0a1', type: 'N', owner: 0 }]);
  assert.deepEqual(targets(n, '0a1'), ['0b3']);
  const n3 = customState('twoMates', [...KINGS, { cell: '0a3', type: 'N', owner: 0 }]);
  assert.ok(!targets(n3, '0a3').includes('1h1'));
  assert.ok(targets(n3, '0a3').includes('1h5')); // loin de l'anneau 1 : pas de poignée
  // Le roi en 0a1 non plus ne passe pas.
  const k = customState('twoMates', [
    { cell: '0a1', type: 'K', owner: 0 },
    { cell: '1d1', type: 'K', owner: 1 },
    { cell: '2d1', type: 'K', owner: 2 },
  ]);
  assert.deepEqual(targets(k, '0a1'), ['0a2', '0b1', '0b2']);
});

test('poignées ouvertes quand une équipe n’a plus de pièce sur son anneau 1 (définitivement)', () => {
  let s = customState(
    'twoMates',
    [
      { cell: '0d1', type: 'K', owner: 0 },
      { cell: '0a1', type: 'R', owner: 0 },
      { cell: '1d2', type: 'K', owner: 1 },
      { cell: '1g1', type: 'N', owner: 1 },
      { cell: '1b1', type: 'N', owner: 1 },
      { cell: '2d1', type: 'K', owner: 2 },
    ],
    { turn: 1 },
  );
  calm(s);
  assert.deepEqual(s.hilts, [false, false, false]);
  s = applyMove(s, mv('1g1', '1f3'));
  assert.deepEqual(s.hilts, [false, false, false]);
  assert.deepEqual(s.lastEvent?.hiltsOpened, []);
  s = applyMove(s, mv('2d1', '2c1'));
  s = applyMove(s, mv('0d1', '0c1'));
  s = applyMove(s, mv('1b1', '1c3'));
  // Plus aucune pièce de l'équipe 1 sur son anneau 1 : ses deux poignées (frontières 0 et 1) s'ouvrent.
  assert.deepEqual(s.hilts, [true, true, false]);
  assert.deepEqual(s.lastEvent?.hiltsOpened, [0, 1]);
  s = applyMove(s, mv('2c1', '2d1'));
  // La tour franchit les poignées ouvertes (cases vides) mais ne prend pas le roi 2d1 ni ne lui donne échec.
  const t = targets(s, '0a1');
  for (const c of ['1h1', '1g1', '1a1', '2h1', '2e1']) assert.ok(t.includes(c), c);
  assert.ok(!t.includes('2d1'));
  calm(s);
  // Replacer une pièce sur l'anneau 1 ne referme pas les poignées.
  s = applyMove(s, mv('0a1', '0b1'));
  s = applyMove(s, mv('1c3', '1b1'));
  assert.deepEqual(s.lastEvent?.hiltsOpened, []);
  assert.deepEqual(s.hilts, [true, true, false]);
});

test('même ouverte, une poignée ne laisse ni prendre ni donner échec', () => {
  const s = customState(
    'twoMates',
    [
      { cell: '0d2', type: 'K', owner: 0 },
      { cell: '0a1', type: 'R', owner: 0 },
      { cell: '0a2', type: 'Q', owner: 0 },
      { cell: '0b3', type: 'P', owner: 0 },
      { cell: '1h1', type: 'K', owner: 1 },
      { cell: '1h2', type: 'N', owner: 1 },
      { cell: '2d1', type: 'K', owner: 2 },
    ],
    { hilts: [true, false, false] },
  );
  // La tour et la dame visent le roi 1h1 à travers la poignée ouverte : ni échec ni prise.
  calm(s);
  assert.ok(!isCellAttacked(s, '1h1', 0));
  assert.ok(!targets(s, '0a1').includes('1h1'));
  assert.ok(!targets(s, '0a2').includes('1h1'));
  // Sur l'anneau 2 (pas de poignée), la dame prend 1h2.
  assert.ok(targets(s, '0a2').includes('1h2'));
  assert.ok(isCellAttacked(s, '1h2', 0));
  // Le roi 1h1 peut traverser vers 0a1 ? Non : la case est occupée et la prise traverserait la poignée.
  const k = customState(
    'twoMates',
    [
      { cell: '0d1', type: 'K', owner: 0 },
      { cell: '1h1', type: 'K', owner: 1 },
      { cell: '2d1', type: 'K', owner: 2 },
    ],
    { turn: 1, hilts: [true, false, false] },
  );
  assert.ok(targets(k, '1h1').includes('0a1')); // case vide : passage permis
});

test('une équipe éliminée ouvre ses deux poignées ; ses fossiles restent sur le plateau', () => {
  let s = customState('twoMates', [
    { cell: '0d1', type: 'K', owner: 0 },
    { cell: '0a1', type: 'R', owner: 0 },
    { cell: '1d1', type: 'K', owner: 1 },
    { cell: '1h1', type: 'N', owner: 1 },
    { cell: '2d1', type: 'K', owner: 2 },
  ]);
  s = resign(s, 1);
  assert.deepEqual(s.hilts, [true, true, false]);
  assert.deepEqual(s.lastEvent?.hiltsOpened, [0, 1]);
  // Le cavalier fossile en 1h1 est derrière une poignée : la tour ne peut pas le prendre.
  assert.ok(!targets(s, '0a1').includes('1h1'));
  assert.equal(s.board.filter((p) => p?.owner === 1).length, 2);
});

test('lames : un pion qui n’a pas traversé le centre ne prend pas à travers avant l’anneau 4', () => {
  const s = customState('twoMates', [
    ...KINGS,
    { cell: '0a2', type: 'P', owner: 0 },
    { cell: '1h3', type: 'P', owner: 1 },
    { cell: '0b3', type: 'P', owner: 2 },
    { cell: '0h3', type: 'P', owner: 0 },
    { cell: '2a4', type: 'P', owner: 1 },
    { cell: '0a4', type: 'P', owner: 0 },
    { cell: '1h5', type: 'P', owner: 2 },
  ]);
  calm(s);
  // 0a2 : prise de 0b3 (même côté de la frontière) oui, de 1h3 (à travers la lame) non.
  assert.deepEqual(targets(s, '0a2'), ['0a3', '0b3']);
  // 0h3 → 2a4 : depuis l'anneau 3, encore la lame.
  assert.deepEqual(targets(s, '0h3'), ['0h4']);
  // 0a4 (anneau 4, « fin du cours d'eau ») → 1h5 : prise permise.
  assert.deepEqual(targets(s, '0a4'), ['0a5', '1h5']);
  // Pas d'attaque (ni d'échec) à travers la lame.
  assert.ok(!isCellAttacked(s, '1h3', 0));
  assert.ok(isCellAttacked(s, '1h5', 0));
});

test('lames : après la traversée du centre, le pion les ignore (mais pas les poignées)', () => {
  const s = customState(
    'twoMates',
    [
      ...KINGS,
      { cell: '0a3', type: 'P', owner: 1, crossed: true },
      { cell: '1h2', type: 'P', owner: 2 },
      { cell: '0a2', type: 'P', owner: 1, crossed: true },
      { cell: '1h1', type: 'N', owner: 2 },
      { cell: '0b1', type: 'N', owner: 0 },
    ],
    { turn: 1 },
  );
  calm(s);
  assert.deepEqual(targets(s, '0a3'), ['1h2']);
  // 0a2 → 1h1 franchirait la poignée : interdit ; 0a1 (avance) et 0b1 (prise) avec promotion.
  assert.deepEqual(targets(s, '0a2'), ['0a1', '0b1']);
  assert.equal(legalMoves(s).filter((m) => m.from === '0a2').length, 8);
});
