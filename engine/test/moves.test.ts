import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyMove, customState, parseCell, initialState, legalMoves, pieceAt } from '../src/index.ts';
import type { CustomPiece, GameState } from '../src/index.ts';
import { at, mv, sorted, targets } from './helpers.ts';

const cellIndexOf = parseCell;
const KINGS: CustomPiece[] = [
  { cell: '0d1', type: 'K', owner: 0 },
  { cell: '1d1', type: 'K', owner: 1 },
  { cell: '2d1', type: 'K', owner: 2 },
];
const pos = (pieces: CustomPiece[], opts: Parameters<typeof customState>[2] = {}) =>
  customState('twoMates', [...KINGS, ...pieces], opts);

test('position initiale : T C F R D F C T, rois en d1, 20 coups par équipe', () => {
  const s = initialState('firstMate');
  assert.equal(s.board.length, 144);
  assert.equal(s.board.filter(Boolean).length, 48);
  for (const p of [0, 1, 2]) {
    assert.deepEqual(pieceAt(s, `${p}d1`), { type: 'K', owner: p });
    assert.deepEqual(pieceAt(s, `${p}e1`), { type: 'Q', owner: p });
    assert.deepEqual(pieceAt(s, `${p}a2`), { type: 'P', owner: p });
  }
  assert.equal(legalMoves(s).length, 20);
  assert.deepEqual(targets(s, '0b1'), ['0a3', '0c3']);
  assert.deepEqual(s.hilts, [false, false, false]);
});

test('tour : verticale à travers le centre, horizontale circulaire', () => {
  const s = pos([{ cell: '0a3', type: 'R', owner: 0 }]);
  const t = targets(s, '0a3');
  // Vers le centre puis colonne opposée (2e) jusqu'au bord ; vers l'extérieur : 0a2, 0a1.
  for (const c of ['0a4', '0a5', '0a6', '2e6', '2e5', '2e1', '0a2', '0a1']) assert.ok(t.includes(c), c);
  // Horizontale sur l'anneau 3 : les 23 autres cases de l'anneau.
  for (let w = 0; w < 24; w++) if (w !== 14) assert.ok(t.includes(at(w, 3)), at(w, 3));
  assert.equal(t.length, 3 + 6 + 2 + 23 - 1); // 2e3 est atteinte des deux façons
});

test('fou : diagonales, traversée du centre en gardant sa couleur, arrêt au bord', () => {
  const s = pos([{ cell: '0c5', type: 'B', owner: 0 }]);
  const t = targets(s, '0c5');
  // 0c5 = (16, 5) : vers le centre 0d6 / 0b6 puis traversée → (17+14, 6) = (7, 6) et (15+10, 6) = (1, 6).
  assert.ok(t.includes('0d6') && t.includes('0b6'));
  assert.ok(t.includes(at(7, 6)) && t.includes(at(8, 5)) && t.includes(at(1, 6)) && t.includes(at(0, 5)));
  // Vers l'extérieur : jusqu'à l'anneau 1, sans rebond.
  assert.ok(t.includes(at(20, 1)) && t.includes(at(12, 1)));
  assert.equal(t.length, 20);
});

test('dame et roi à travers le centre ; le roi ne se met pas en échec', () => {
  const s = pos([{ cell: '0e6', type: 'Q', owner: 0 }]);
  const t = targets(s, '0e6');
  assert.ok(t.includes(at(18 + 12, 6))); // verticale
  assert.ok(t.includes(at(18 + 14, 6)) && t.includes(at(18 + 10, 6))); // diagonales
  const k = customState('twoMates', [
    { cell: '0d6', type: 'K', owner: 0 },
    { cell: '1d1', type: 'K', owner: 1 },
    { cell: '2d1', type: 'K', owner: 2 },
  ]);
  const kt = targets(k, '0d6');
  assert.deepEqual(kt, sorted(['0c6', '0e6', '0c5', '0d5', '0e5', at(29, 6), at(31, 6), at(27, 6)]));
  // Une tour adverse sur la colonne opposée contrôle la case d'arrivée de la traversée.
  const k2 = customState('twoMates', [
    { cell: '0d6', type: 'K', owner: 0 },
    { cell: at(29, 2), type: 'R', owner: 1 },
    { cell: '1d1', type: 'K', owner: 1 },
    { cell: '2a1', type: 'K', owner: 2 },
  ]);
  // La tour attaque aussi 0d6 à travers le centre : échec.
  assert.ok(!targets(k2, '0d6').includes(at(29, 6)));
  assert.ok(!targets(k2, '0d6').includes('0d5'));
});

test('cavalier : les 8 sauts en L (2V+1H et 2H+1V), à travers le centre', () => {
  const s = pos([{ cell: '0d5', type: 'N', owner: 0 }]);
  assert.deepEqual(targets(s, '0d5'), sorted(['0c3', '0e3', '1a6', '2g6', '0b4', '0b6', '0f4', '0f6']));
  applyMove(s, mv('0d5', '1a6'));
  const after = applyMove(s, mv('0d5', '2g6'));
  assert.equal(after.lastEvent?.crossedCenter, true);
  // Le cavalier saute par-dessus les pièces.
  const j = initialState('twoMates');
  assert.deepEqual(targets(j, '0g1'), ['0f3', '0h3']);
});

test('pion : simple et double pas, traversée du centre, puis avance vers l’extérieur', () => {
  let s = pos([
    { cell: '0e2', type: 'P', owner: 0 },
    { cell: '0b6', type: 'P', owner: 0 },
  ]);
  assert.deepEqual(targets(s, '0e2'), ['0e3', '0e4']);
  const opp = at(15 + 12, 6); // 0b = 15 → colonne 3
  assert.deepEqual(targets(s, '0b6'), [opp]);
  s = applyMove(s, mv('0b6', opp));
  assert.equal(s.lastEvent?.crossedCenter, true);
  assert.deepEqual(pieceAt(s, opp), { type: 'P', owner: 0, crossed: true });
  s = applyMove(s, mv('1d1', '1c1'));
  s = applyMove(s, mv('2d1', '2c1'));
  assert.deepEqual(targets(s, opp), [at(3, 5)]);
  // Pas de double pas après la traversée, même en passant par l'anneau 2.
  const t = pos([{ cell: at(3, 2), type: 'P', owner: 0, crossed: true }]);
  assert.equal(legalMoves(t).filter((m) => m.from === at(3, 2) && m.to === at(3, 1)).length, 4);
});

test('pion : prises diagonales vers l’avant, à travers le centre', () => {
  const s = pos([
    { cell: '0d6', type: 'P', owner: 0 },
    { cell: at(31, 6), type: 'N', owner: 1 },
    { cell: at(27, 6), type: 'N', owner: 2 },
    { cell: at(29, 6), type: 'B', owner: 1 },
  ]);
  // Bloqué devant (2h6 occupée), prises à travers le centre des deux côtés.
  assert.deepEqual(targets(s, '0d6'), sorted([at(31, 6), at(27, 6)]));
  const a = applyMove(s, mv('0d6', at(31, 6)));
  assert.equal(a.lastEvent?.crossedCenter, true);
  assert.equal(pieceAt(a, at(31, 6))?.crossed, true);
});

test('promotion au choix (dame, tour, fou, cavalier) en atteignant l’anneau 1 après le centre', () => {
  const s = pos([
    { cell: '2b2', type: 'P', owner: 0, crossed: true },
    { cell: '2c1', type: 'R', owner: 2 },
  ]);
  const promos = legalMoves(s).filter((m) => m.from === '2b2');
  assert.deepEqual(
    sorted(promos.map((m) => `${m.to}=${m.promotion}`)),
    sorted(['2b1=Q', '2b1=R', '2b1=B', '2b1=N', '2c1=Q', '2c1=R', '2c1=B', '2c1=N']),
  );
  assert.equal(pieceAt(applyMove(s, mv('2b2', '2b1', 'N')), '2b1')?.type, 'N');
  assert.equal(pieceAt(applyMove(s, mv('2b2', '2b1', 'B')), '2b1')?.type, 'B');
  const q = applyMove(s, mv('2b2', '2c1'));
  assert.equal(pieceAt(q, '2c1')?.type, 'Q');
  assert.equal(q.lastEvent?.promotion, 'Q');
  assert.equal(applyMove(s, mv('2b2', '2c1', 'R')).lastEvent?.promotion, 'R');
  assert.throws(() => applyMove(s, { from: '2b2', to: '2b1', promotion: 'K' as never }));
  // Un pion qui n'a pas traversé le centre n'est jamais promu.
  assert.ok(legalMoves(initialState('twoMates')).every((m) => !m.promotion));
});

test('prise en passant (une fois par adversaire, avant le prochain coup du pion)', () => {
  const base = (): GameState =>
    pos([
      { cell: '0e2', type: 'P', owner: 0 },
      { cell: '0f4', type: 'P', owner: 1, crossed: true },
      { cell: '0d4', type: 'P', owner: 2, crossed: true },
    ]);
  let s = applyMove(base(), mv('0e2', '0e4'));
  assert.deepEqual(s.enPassant, [{ target: '0e3', pawn: '0e4', owner: 0 }]);
  const ep = legalMoves(s).find((m) => m.from === '0f4' && m.to === '0e3');
  assert.ok(ep?.enPassant && ep.capture);
  const taken = applyMove(s, mv('0f4', '0e3'));
  assert.equal(pieceAt(taken, '0e4'), null);
  assert.equal(taken.lastEvent?.enPassant, true);
  assert.deepEqual(taken.lastEvent?.captured, { type: 'P', owner: 0, frozen: false, at: '0e4' });
  // Le joueur 1 ne prend pas : le joueur 2 le peut encore ; plus personne après le coup suivant de 0.
  s = applyMove(s, mv('1d1', '1c1'));
  assert.ok(targets(s, '0d4').includes('0e3'));
  s = applyMove(s, mv('2d1', '2c1'));
  s = applyMove(s, mv('0d1', '0c1'));
  assert.deepEqual(s.enPassant, []);
  s = applyMove(s, mv('1c1', '1d1'));
  assert.ok(!targets(s, '0d4').includes('0e3'));
});

test('roque : petit roque côté a, grand roque côté h ; cases contrôlées interdites', () => {
  const rights = { castling: [{ king: true, queen: true }, { king: false, queen: false }, { king: false, queen: false }] as GameState['castling'] };
  const s = customState(
    'twoMates',
    [
      { cell: '0d1', type: 'K', owner: 0 },
      { cell: '0a1', type: 'R', owner: 0 },
      { cell: '0h1', type: 'R', owner: 0 },
      { cell: '1d1', type: 'K', owner: 1 },
      { cell: '2d1', type: 'K', owner: 2 },
    ],
    rights,
  );
  const castles = legalMoves(s).filter((m) => m.castle);
  assert.deepEqual(sorted(castles.map((m) => `${m.castle}:${m.to}`)), ['king:0b1', 'queen:0f1']);
  const k = applyMove(s, mv('0d1', '0b1'));
  assert.equal(pieceAt(k, '0c1')?.type, 'R');
  assert.equal(pieceAt(k, '0a1'), null);
  assert.deepEqual(k.lastEvent?.castle, { side: 'king', rookFrom: '0a1', rookTo: '0c1' });
  const q = applyMove(s, mv('0d1', '0f1'));
  assert.equal(pieceAt(q, '0e1')?.type, 'R');
  assert.deepEqual(q.castling[0], { king: false, queen: false });
  // Une case de passage contrôlée (0e1 par une tour adverse venant du centre) interdit le grand roque.
  const t = customState(
    'twoMates',
    [
      { cell: '0d1', type: 'K', owner: 0 },
      { cell: '0a1', type: 'R', owner: 0 },
      { cell: '0h1', type: 'R', owner: 0 },
      { cell: '0e5', type: 'R', owner: 1 },
      { cell: '1d1', type: 'K', owner: 1 },
      { cell: '2d1', type: 'K', owner: 2 },
    ],
    rights,
  );
  assert.deepEqual(legalMoves(t).filter((m) => m.castle).map((m) => m.castle), ['king']);
  // Une tour déplacée perd son droit.
  const moved = applyMove(s, mv('0a1', '0a2'));
  assert.deepEqual(moved.castling[0], { king: false, queen: true });
});

const knight = (cell: string, extra: CustomPiece[] = [], opts: Parameters<typeof customState>[2] = {}) =>
  pos([{ cell, type: 'N', owner: 0 }, ...extra], opts);

test('cavalier : nombre de destinations (centre du secteur, anneau 1, anneau 6 avec centre)', () => {
  // Centre du secteur : 8 sauts, les deux formes de L.
  assert.deepEqual(targets(knight('0d3'), '0d3'), sorted(['0b2', '0b4', '0c1', '0c5', '0e1', '0e5', '0f2', '0f4']));
  // Anneau 1 près d'une épée (poignée fermée) : les sauts qui la franchissent sont interdits.
  assert.deepEqual(targets(knight('0a1'), '0a1'), ['0b3', '0c2']);
  assert.deepEqual(targets(knight('0h1'), '0h1'), ['0f2', '0g3']);
  // Anneau 6 : 8 sauts dont 4 à travers le centre.
  const t6 = targets(knight('0d6'), '0d6');
  assert.equal(t6.length, 8);
  assert.deepEqual(t6, sorted(['0b5', '0c4', '0e4', '0f5', '1a5', '1b6', '2f6', '2g5']));
});

test('cavalier : poignée ouverte, le franchissement passe mais ne prend pas', () => {
  const open: [boolean, boolean, boolean] = [true, true, true];
  const free = knight('0a1', [], { hilts: open });
  assert.equal(targets(free, '0a1').length, 4);
  assert.ok(targets(free, '0a1').includes('1h3'));
  // Une pièce adverse derrière la poignée ne peut pas être prise.
  const blocked = knight('0a1', [{ cell: '1h3', type: 'P', owner: 1 }], { hilts: open });
  assert.ok(!targets(blocked, '0a1').includes('1h3'));
  // Un saut sans poignée peut prendre une pièce adverse, jamais une pièce de son équipe.
  const cap = knight('0d3', [
    { cell: '0b4', type: 'P', owner: 1 },
    { cell: '0f4', type: 'P', owner: 0 },
  ]);
  assert.ok(targets(cap, '0d3').includes('0b4'));
  assert.ok(!targets(cap, '0d3').includes('0f4'));
});

test('cavalier : aucune prise adverse au premier coup depuis la position initiale', () => {
  const s = initialState('twoMates');
  const caps = legalMoves(s).filter((m) => s.board[cellIndexOf(m.to)] !== null);
  assert.deepEqual(caps, []);
  for (const p of [0, 1, 2] as const) {
    const t = initialState('twoMates');
    const st = { ...t, turn: p };
    for (const m of legalMoves(st)) assert.equal(st.board[cellIndexOf(m.to)], null);
  }
  // Les cavaliers de départ n'ont que les sauts vers l'avant.
  assert.deepEqual(targets(s, '0b1'), ['0a3', '0c3']);
  assert.deepEqual(targets(s, '0g1'), ['0f3', '0h3']);
});
