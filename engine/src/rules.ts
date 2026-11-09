import {
  KING_ADJ,
  KNIGHT_ADJ,
  NUM_CELLS,
  PAWN_ATTACKERS,
  PAWN_CAPTURES,
  PAWN_PUSH,
  RAYS,
  cellIndex,
  cellName,
  parseCell,
  rankOf,
  sectorOf,
} from './topology.ts';
import type {
  CastlingRights,
  CheckInfo,
  Elimination,
  GameEvent,
  GameResult,
  GameState,
  GameStatus,
  Mode,
  Move,
  Piece,
  PieceType,
  Player,
} from './types.ts';

type Board = (Piece | null)[];
type Active = readonly boolean[];

/** Coup interne (indices de cases) : utilisé par le moteur et le bot. */
export interface IMove {
  from: number;
  to: number;
  castle?: 'king' | 'queen';
  promo: boolean;
  capture: boolean;
}

const PLAYERS: readonly Player[] = [0, 1, 2];
const BACK_RANK: readonly PieceType[] = ['R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R'];
const ORTHO_DIRS = [0, 1, 2, 3];
const DIAG_DIRS = [4, 5, 6, 7];

// Pièces partagées (immuables) pour limiter les allocations.
const PIECES: Record<string, Piece> = {};
function piece(type: PieceType, owner: Player): Piece {
  const k = type + owner;
  return (PIECES[k] ??= Object.freeze({ type, owner }) as Piece);
}

export function nextPlayer(p: Player): Player {
  return ((p + 1) % 3) as Player;
}

function activeCount(active: Active): number {
  return (active[0] ? 1 : 0) + (active[1] ? 1 : 0) + (active[2] ? 1 : 0);
}

function nextActive(active: Active, p: Player): Player {
  let q = nextPlayer(p);
  for (let i = 0; i < 3; i++) {
    if (active[q]) return q;
    q = nextPlayer(q);
  }
  return p;
}

// ---------------------------------------------------------------------------
// Attaques
// ---------------------------------------------------------------------------

function isAttacker(pc: Piece | null, attacker: Player, types: string): boolean {
  return pc !== null && pc.owner === attacker && types.includes(pc.type);
}

/** Le joueur `attacker` (supposé actif) attaque-t-il la case x ? */
export function attacks(board: Board, x: number, attacker: Player): boolean {
  for (const y of PAWN_ATTACKERS[attacker][x]) if (isAttacker(board[y], attacker, 'P')) return true;
  for (const y of KNIGHT_ADJ[x]) if (isAttacker(board[y], attacker, 'N')) return true;
  for (const y of KING_ADJ[x]) if (isAttacker(board[y], attacker, 'K')) return true;
  const rays = RAYS[x];
  for (let d = 0; d < 8; d++) {
    const slider = d < 4 ? 'R' : 'B';
    for (const path of rays[d]) {
      for (let i = 0; i < path.length; i++) {
        const pc = board[path[i]];
        if (pc === null) continue;
        if (pc.owner === attacker && (pc.type === slider || pc.type === 'Q')) return true;
        break;
      }
    }
  }
  return false;
}

/** Adversaires actifs de `player` qui attaquent la case x. */
function attackersOf(board: Board, active: Active, x: number, player: Player): Player[] {
  const out: Player[] = [];
  for (const q of PLAYERS) if (q !== player && active[q] && attacks(board, x, q)) out.push(q);
  return out;
}

export function isAttackedByAny(board: Board, active: Active, x: number, player: Player): boolean {
  for (const q of PLAYERS) if (q !== player && active[q] && attacks(board, x, q)) return true;
  return false;
}

export function findKing(board: Board, player: Player): number {
  for (let c = 0; c < NUM_CELLS; c++) {
    const pc = board[c];
    if (pc !== null && pc.type === 'K' && pc.owner === player) return c;
  }
  return -1;
}

function checksOn(board: Board, active: Active): CheckInfo[] {
  const out: CheckInfo[] = [];
  for (const p of PLAYERS) {
    if (!active[p]) continue;
    const k = findKing(board, p);
    if (k < 0) continue;
    const by = attackersOf(board, active, k, p);
    if (by.length) out.push({ player: p, by });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Génération des coups
// ---------------------------------------------------------------------------

function canCapture(pc: Piece, player: Player, active: Active): boolean {
  // Un roi actif ne peut jamais être pris (il est mis en échec) ; un roi gelé, si.
  return pc.owner !== player && !(pc.type === 'K' && active[pc.owner]);
}

function isPromotion(player: Player, to: number): boolean {
  return sectorOf(to) !== player && rankOf(to) === 0;
}

export function pseudoMoves(board: Board, active: Active, player: Player): IMove[] {
  const out: IMove[] = [];
  const add = (from: number, to: number, promo = false) => {
    const t = board[to];
    if (t === null) out.push({ from, to, promo, capture: false });
    else if (canCapture(t, player, active)) out.push({ from, to, promo, capture: true });
  };
  for (let c = 0; c < NUM_CELLS; c++) {
    const pc = board[c];
    if (pc === null || pc.owner !== player) continue;
    switch (pc.type) {
      case 'P': {
        const one = PAWN_PUSH[player][c];
        if (one >= 0 && board[one] === null) {
          out.push({ from: c, to: one, promo: isPromotion(player, one), capture: false });
          if (sectorOf(c) === player && rankOf(c) === 1) {
            const two = PAWN_PUSH[player][one];
            if (two >= 0 && board[two] === null) out.push({ from: c, to: two, promo: false, capture: false });
          }
        }
        for (const t of PAWN_CAPTURES[player][c]) {
          const tp = board[t];
          if (tp !== null && canCapture(tp, player, active)) {
            out.push({ from: c, to: t, promo: isPromotion(player, t), capture: true });
          }
        }
        break;
      }
      case 'N':
        for (const t of KNIGHT_ADJ[c]) add(c, t);
        break;
      case 'K':
        for (const t of KING_ADJ[c]) add(c, t);
        break;
      default: {
        const dirs = pc.type === 'R' ? ORTHO_DIRS : pc.type === 'B' ? DIAG_DIRS : [...ORTHO_DIRS, ...DIAG_DIRS];
        const seen = new Set<number>();
        for (const d of dirs) {
          for (const path of RAYS[c][d]) {
            for (const t of path) {
              if (!seen.has(t)) {
                seen.add(t);
                add(c, t);
              }
              if (board[t] !== null) break;
            }
          }
        }
      }
    }
  }
  return out;
}

function castlingMoves(board: Board, active: Active, player: Player, rights: CastlingRights): IMove[] {
  const out: IMove[] = [];
  const e1 = cellIndex(player, 4, 0);
  const king = board[e1];
  if (!king || king.type !== 'K' || king.owner !== player) return out;
  if (!rights.king && !rights.queen) return out;
  if (isAttackedByAny(board, active, e1, player)) return out;
  const sq = (f: number) => cellIndex(player, f, 0);
  const isRook = (c: number) => {
    const p = board[c];
    return p !== null && p.type === 'R' && p.owner === player;
  };
  if (rights.king && isRook(sq(7)) && board[sq(5)] === null && board[sq(6)] === null) {
    if (!isAttackedByAny(board, active, sq(5), player) && !isAttackedByAny(board, active, sq(6), player)) {
      out.push({ from: e1, to: sq(6), castle: 'king', promo: false, capture: false });
    }
  }
  if (rights.queen && isRook(sq(0)) && board[sq(1)] === null && board[sq(2)] === null && board[sq(3)] === null) {
    if (!isAttackedByAny(board, active, sq(3), player) && !isAttackedByAny(board, active, sq(2), player)) {
      out.push({ from: e1, to: sq(2), castle: 'queen', promo: false, capture: false });
    }
  }
  return out;
}

/** Applique un coup sur un plateau (copie) ; renvoie le nouveau plateau. */
function playOnBoard(board: Board, m: IMove, player: Player): Board {
  const b = board.slice();
  const pc = b[m.from]!;
  b[m.from] = null;
  b[m.to] = m.promo ? piece('Q', player) : pc;
  if (m.castle) {
    const rf = cellIndex(player, m.castle === 'king' ? 7 : 0, 0);
    const rt = cellIndex(player, m.castle === 'king' ? 5 : 3, 0);
    b[rt] = b[rf];
    b[rf] = null;
  }
  return b;
}

function legalFor(board: Board, active: Active, player: Player, rights: CastlingRights): IMove[] {
  if (!active[player]) return [];
  const out: IMove[] = [];
  const kingCell = findKing(board, player);
  for (const m of pseudoMoves(board, active, player)) {
    const b = playOnBoard(board, m, player);
    const k = m.from === kingCell ? m.to : kingCell;
    if (k < 0 || !isAttackedByAny(b, active, k, player)) out.push(m);
  }
  for (const m of castlingMoves(board, active, player, rights)) out.push(m);
  return out;
}

export function toPublic(m: IMove): Move {
  const out: Move = { from: cellName(m.from), to: cellName(m.to) };
  if (m.castle) out.castle = m.castle;
  if (m.promo) out.promotion = 'Q';
  if (m.capture) out.capture = true;
  return out;
}

// Cache des coups légaux par état (les états sont immuables).
const legalCache = new WeakMap<GameState, IMove[]>();

/** Coups légaux internes (mis en cache, ne pas modifier). */
export function legalInternal(state: GameState): IMove[] {
  if (state.result) return [];
  let ms = legalCache.get(state);
  if (!ms) {
    ms = legalFor(state.board, state.active, state.turn, state.castling[state.turn]);
    legalCache.set(state, ms);
  }
  return ms;
}

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

function positionKey(board: Board, turn: Player, active: Active, castling: readonly CastlingRights[]): string {
  let s = '';
  for (let c = 0; c < NUM_CELLS; c++) {
    const pc = board[c];
    s += pc === null ? '.' : pc.type + pc.owner;
  }
  s += '|' + turn + '|' + active.map((a) => (a ? 1 : 0)).join('');
  s += '|' + castling.map((r) => (r.king ? 'K' : '-') + (r.queen ? 'Q' : '-')).join('');
  return s;
}

export interface CustomPiece {
  cell: string;
  type: PieceType;
  owner: Player;
}

export interface CustomOptions {
  turn?: Player;
  active?: [boolean, boolean, boolean];
  castling?: [CastlingRights, CastlingRights, CastlingRights];
}

/** Construit un état à partir d'une liste de pièces (tests, puzzles, reprise). */
export function customState(mode: Mode, pieces: CustomPiece[], opts: CustomOptions = {}): GameState {
  if (mode !== 'firstMate' && mode !== 'twoMates') throw new Error(`mode inconnu : ${mode}`);
  const board: Board = new Array(NUM_CELLS).fill(null);
  for (const p of pieces) {
    const c = parseCell(p.cell);
    if (board[c]) throw new Error(`case ${p.cell} déjà occupée`);
    board[c] = piece(p.type, p.owner);
  }
  const active: [boolean, boolean, boolean] = opts.active ? [...opts.active] : [true, true, true];
  const castling = (opts.castling ?? [0, 1, 2].map(() => ({ king: false, queen: false }))).map((r) => ({ ...r })) as [
    CastlingRights,
    CastlingRights,
    CastlingRights,
  ];
  const turn = opts.turn ?? 0;
  const state: GameState = {
    version: 1,
    mode,
    board,
    turn,
    active,
    castling,
    ply: 0,
    quietTurns: 0,
    lastMoveAt: [-1, -1, -1],
    repetitions: { [positionKey(board, turn, active, castling)]: 1 },
    eliminations: [],
    result: null,
    lastEvent: null,
  };
  return state;
}

export function initialState(mode: Mode): GameState {
  const pieces: CustomPiece[] = [];
  for (const p of PLAYERS) {
    for (let f = 0; f < 8; f++) {
      pieces.push({ cell: cellName(cellIndex(p, f, 0)), type: BACK_RANK[f], owner: p });
      pieces.push({ cell: cellName(cellIndex(p, f, 1)), type: 'P', owner: p });
    }
  }
  return customState(mode, pieces, {
    castling: [
      { king: true, queen: true },
      { king: true, queen: true },
      { king: true, queen: true },
    ],
  });
}

/** Coups légaux du joueur au trait (liste vide si la partie est finie). */
export function legalMoves(state: GameState): Move[] {
  return legalInternal(state).map(toPublic);
}

interface Resolution {
  turn: Player;
  active: [boolean, boolean, boolean];
  eliminations: Elimination[];
  result: GameResult | null;
  mates: { player: Player; by: Player }[];
  eliminated: Player[];
  passes: Player[];
  /** Coups légaux du joueur au trait final (pour le cache). */
  moves: IMove[];
}

/**
 * Détermine le joueur au trait à partir de `candidate` : un joueur sans coup légal
 * est mat (en échec) ou pat (il passe). Gère éliminations et fins de partie.
 */
function resolveTurn(
  mode: Mode,
  board: Board,
  activeIn: Active,
  castling: readonly CastlingRights[],
  lastMoveAt: readonly number[],
  candidate: Player,
  elimsIn: Elimination[],
  ply: number,
): Resolution {
  const active = [...activeIn] as [boolean, boolean, boolean];
  const eliminations = elimsIn.slice();
  const mates: { player: Player; by: Player }[] = [];
  const eliminated: Player[] = [];
  const passes: Player[] = [];
  let result: GameResult | null = null;
  let cur = candidate;
  let consecutivePasses = 0;

  if (activeCount(active) === 1) {
    const winner = PLAYERS.find((p) => active[p])!;
    return { turn: winner, active, eliminations, result: { winner, reason: 'lastStanding' }, mates, eliminated, passes, moves: [] };
  }

  for (let guard = 0; guard < 10; guard++) {
    const moves = legalFor(board, active, cur, castling[cur]);
    if (moves.length > 0) return { turn: cur, active, eliminations, result, mates, eliminated, passes, moves };
    const k = findKing(board, cur);
    const by = k >= 0 ? attackersOf(board, active, k, cur) : [];
    if (by.length > 0) {
      // Mat : crédité à l'attaquant ayant joué le plus récemment.
      let credit = by[0];
      for (const q of by) if (lastMoveAt[q] > lastMoveAt[credit]) credit = q;
      mates.push({ player: cur, by: credit });
      if (mode === 'firstMate') {
        result = { winner: credit, reason: 'mate' };
        return { turn: cur, active, eliminations, result, mates, eliminated, passes, moves: [] };
      }
      active[cur] = false;
      eliminations.push({ player: cur, by: credit, reason: 'mate', ply });
      eliminated.push(cur);
      consecutivePasses = 0;
      if (activeCount(active) === 1) {
        const winner = PLAYERS.find((p) => active[p])!;
        result = { winner, reason: 'lastStanding' };
        return { turn: winner, active, eliminations, result, mates, eliminated, passes, moves: [] };
      }
      cur = nextActive(active, cur);
    } else {
      // Pat : le joueur passe son tour.
      passes.push(cur);
      consecutivePasses++;
      if (consecutivePasses >= activeCount(active)) {
        result = { winner: null, reason: 'stalemate' };
        return { turn: cur, active, eliminations, result, mates, eliminated, passes, moves: [] };
      }
      cur = nextActive(active, cur);
    }
  }
  throw new Error('résolution du tour impossible');
}

function finalize(
  prev: GameState,
  board: Board,
  castling: [CastlingRights, CastlingRights, CastlingRights],
  res: Resolution,
  ply: number,
  quietTurns: number,
  lastMoveAt: [number, number, number],
  irreversible: boolean,
  base: Omit<GameEvent, 'checks' | 'mates' | 'eliminated' | 'passes' | 'gameOver'>,
): GameState {
  let result = res.result;
  quietTurns += res.passes.length;
  let repetitions: Record<string, number> = irreversible ? {} : { ...prev.repetitions };
  if (!result) {
    const key = positionKey(board, res.turn, res.active, castling);
    const n = (repetitions[key] ?? 0) + 1;
    repetitions[key] = n;
    if (n >= 3) result = { winner: null, reason: 'repetition' };
    else if (quietTurns >= 50 * activeCount(res.active)) result = { winner: null, reason: 'fiftyMoves' };
  }
  const event: GameEvent = {
    ...base,
    checks: checksOn(board, res.active),
    mates: res.mates,
    eliminated: res.eliminated,
    passes: res.passes,
    gameOver: result,
  };
  const state: GameState = {
    version: 1,
    mode: prev.mode,
    board,
    turn: res.turn,
    active: res.active,
    castling,
    ply,
    quietTurns,
    lastMoveAt,
    repetitions,
    eliminations: res.eliminations,
    result,
    lastEvent: event,
  };
  legalCache.set(state, result ? [] : res.moves);
  return state;
}

/** Applique un coup légal du joueur au trait. Lève une erreur si le coup est illégal. */
export function applyMove(state: GameState, move: Move): GameState {
  if (state.result) throw new Error('la partie est terminée');
  let from: number;
  let to: number;
  try {
    from = parseCell(move.from);
    to = parseCell(move.to);
  } catch {
    throw new Error(`coup illégal : ${move?.from}-${move?.to}`);
  }
  const m = legalInternal(state).find((x) => x.from === from && x.to === to);
  if (!m) throw new Error(`coup illégal : ${move.from}-${move.to}`);
  return applyInternal(state, m);
}

/** Applique un coup interne issu de legalInternal(state) (sans vérification). */
export function applyInternal(state: GameState, m: IMove): GameState {
  const from = m.from;
  const to = m.to;
  const player = state.turn;
  const moved = state.board[from]!;
  const capturedPiece = state.board[to];
  const board = playOnBoard(state.board, m, player);

  const castling = state.castling.map((r) => ({ ...r })) as [CastlingRights, CastlingRights, CastlingRights];
  if (moved.type === 'K') castling[player] = { king: false, queen: false };
  for (const p of PLAYERS) {
    for (const c of [from, to]) {
      if (c === cellIndex(p, 0, 0)) castling[p].queen = false;
      if (c === cellIndex(p, 7, 0)) castling[p].king = false;
      if (c === cellIndex(p, 4, 0)) castling[p] = { king: false, queen: false };
    }
  }

  const ply = state.ply + 1;
  const lastMoveAt = [...state.lastMoveAt] as [number, number, number];
  lastMoveAt[player] = ply;
  const irreversible = moved.type === 'P' || capturedPiece !== null;
  const quietTurns = irreversible ? 0 : state.quietTurns + 1;

  const res = resolveTurn(
    state.mode,
    board,
    state.active,
    castling,
    lastMoveAt,
    nextActive(state.active, player),
    state.eliminations,
    ply,
  );

  return finalize(state, board, castling, res, ply, quietTurns, lastMoveAt, irreversible, {
    kind: 'move',
    player,
    move: { from: cellName(from), to: cellName(to) },
    piece: moved.type,
    captured: capturedPiece
      ? { type: capturedPiece.type, owner: capturedPiece.owner, frozen: !state.active[capturedPiece.owner], at: cellName(to) }
      : null,
    promotion: m.promo ? 'Q' : null,
    castle: m.castle
      ? {
          side: m.castle,
          rookFrom: cellName(cellIndex(player, m.castle === 'king' ? 7 : 0, 0)),
          rookTo: cellName(cellIndex(player, m.castle === 'king' ? 5 : 3, 0)),
        }
      : null,
  });
}

/**
 * Abandon (ou déconnexion) : le joueur est éliminé comme s'il était mat, sans que
 * personne ne soit crédité. Ses pièces restent sur le plateau, gelées.
 */
export function resign(state: GameState, player: Player): GameState {
  if (state.result) throw new Error('la partie est terminée');
  if (player !== 0 && player !== 1 && player !== 2) throw new Error(`joueur invalide : ${player}`);
  if (!state.active[player]) throw new Error(`le joueur ${player} n'est plus en jeu`);
  const active = [...state.active] as [boolean, boolean, boolean];
  active[player] = false;
  const eliminations = [...state.eliminations, { player, by: null, reason: 'resign' as const, ply: state.ply }];
  const candidate = state.turn === player ? nextActive(active, player) : state.turn;
  const res = resolveTurn(state.mode, state.board, active, state.castling, state.lastMoveAt, candidate, eliminations, state.ply);
  res.eliminated.unshift(player);
  return finalize(state, state.board, state.castling, res, state.ply, state.quietTurns, state.lastMoveAt, false, {
    kind: 'resign',
    player,
  });
}

/** Coup légal aléatoire pour le joueur au trait (timeout). rng renvoie un réel dans [0, 1). */
export function randomMove(state: GameState, rng: () => number = Math.random): Move {
  const ms = legalInternal(state);
  if (ms.length === 0) throw new Error('aucun coup légal');
  let i = Math.floor(rng() * ms.length);
  if (!(i >= 0)) i = 0;
  if (i >= ms.length) i = ms.length - 1;
  return toPublic(ms[i]);
}

export function status(state: GameState): GameStatus {
  const checks = checksOn(state.board, state.active);
  const over = state.result !== null;
  return {
    mode: state.mode,
    over,
    result: state.result,
    turn: over ? null : state.turn,
    activePlayers: PLAYERS.filter((p) => state.active[p]),
    inCheck: !over && checks.some((c) => c.player === state.turn),
    checks,
    eliminations: state.eliminations,
    ply: state.ply,
    quietTurns: state.quietTurns,
    fiftyMoveLimit: 50 * activeCount(state.active),
  };
}

/** Pièce sur une case (nom textuel), ou null. */
export function pieceAt(state: GameState, cell: string): Piece | null {
  return state.board[parseCell(cell)];
}

/** Le joueur `by` (actif) attaque-t-il la case ? Utile pour l'aide visuelle. */
export function isCellAttacked(state: GameState, cell: string, by: Player): boolean {
  return state.active[by] && attacks(state.board, parseCell(cell), by);
}
