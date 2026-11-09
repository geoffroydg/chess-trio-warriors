// Règles du jeu d'échecs à 3 joueurs sur plateau rond « Chess for 3 » (voir docs/RULES.md).
import {
  BACK_CELLS,
  KING_ATTACKERS,
  KING_JUMPS,
  KNIGHT_ATTACKERS,
  KNIGHT_JUMPS,
  LINES,
  NUM_CELLS,
  NUM_DIRS,
  PAWN_ATTACKERS,
  PAWN_CAPTURES,
  PAWN_PUSH,
  RAYS,
  TEAM_BORDERS,
  cellIndex,
  cellName,
  parseCell,
  pawnCaptureOk,
  ringOf,
} from './board.ts';
import type {
  CastlingRights,
  CheckInfo,
  Elimination,
  EnPassant,
  GameEvent,
  GameResult,
  GameState,
  GameStatus,
  Mode,
  Move,
  Piece,
  PieceType,
  Player,
  PromotionType,
} from './types.ts';

type Board = (Piece | null)[];
type Active = readonly boolean[];

/** Coup interne (indices de cases) : utilisé par le moteur et le bot. */
export interface IMove {
  from: number;
  to: number;
  castle?: 'king' | 'queen';
  /** Le pion atteint l'anneau 1 après la traversée : promotion (au choix, dame par défaut). */
  promo: boolean;
  capture: boolean;
  /** Prise en passant : case du pion pris (−1 sinon). */
  ep: number;
  /** Le trajet traverse le médaillon central. */
  center: boolean;
  /** Avance de deux cases d'un pion (ouvre un droit de prise en passant). */
  double: boolean;
}

/** Droit de prise en passant (indices internes). */
interface IEnPassant {
  target: number;
  pawn: number;
  owner: Player;
}

const PLAYERS: readonly Player[] = [0, 1, 2];
/** Anneau 1, colonnes a → h : T C F R D F C T (roi sur une case claire, d1). */
export const BACK_RANK: readonly PieceType[] = ['R', 'N', 'B', 'K', 'Q', 'B', 'N', 'R'];
export const KING_FILE = 3;
const PROMOTIONS: readonly PromotionType[] = ['Q', 'R', 'B', 'N'];

/** Roques : petit roque ('king') côté a, grand roque ('queen') côté h. */
const CASTLES = {
  king: { rookFrom: 0, rookTo: 2, kingTo: 1, empty: [1, 2], safe: [2, 1] },
  queen: { rookFrom: 7, rookTo: 4, kingTo: 5, empty: [4, 5, 6], safe: [4, 5] },
} as const;

const SEEN = new Int32Array(NUM_CELLS);
let seenStamp = 0;

// Pièces partagées (immuables) pour limiter les allocations.
const PIECES: Record<string, Piece> = {};
export function piece(type: PieceType, owner: Player, crossed = false): Piece {
  const k = type + owner + (crossed ? 'x' : '');
  return (PIECES[k] ??= Object.freeze(crossed && type === 'P' ? { type, owner, crossed: true } : { type, owner }) as Piece);
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

const hiltMask = (h: readonly boolean[]) => (h[0] ? 1 : 0) | (h[1] ? 2 : 0) | (h[2] ? 4 : 0);
const hiltArray = (m: number): [boolean, boolean, boolean] => [(m & 1) !== 0, (m & 2) !== 0, (m & 4) !== 0];

// ---------------------------------------------------------------------------
// Attaques
// ---------------------------------------------------------------------------

/**
 * Le joueur `attacker` (supposé actif) attaque-t-il la case x ? Un trajet qui franchit une
 * poignée (ouverte ou fermée) n'attaque jamais.
 */
export function attacks(board: Board, x: number, attacker: Player): boolean {
  for (const y of PAWN_ATTACKERS[0][x]) {
    const pc = board[y];
    if (pc !== null && pc.owner === attacker && pc.type === 'P' && !pc.crossed) return true;
  }
  for (const y of PAWN_ATTACKERS[1][x]) {
    const pc = board[y];
    if (pc !== null && pc.owner === attacker && pc.type === 'P' && pc.crossed) return true;
  }
  for (const y of KNIGHT_ATTACKERS[x]) {
    const pc = board[y];
    if (pc !== null && pc.owner === attacker && pc.type === 'N') return true;
  }
  for (const y of KING_ATTACKERS[x]) {
    const pc = board[y];
    if (pc !== null && pc.owner === attacker && pc.type === 'K') return true;
  }
  const base = x * NUM_DIRS;
  for (let d = 0; d < NUM_DIRS; d++) {
    const ray = RAYS[base + d];
    const cells = ray.cells;
    const slider = d < 4 ? 'R' : 'B';
    for (let i = 0; i < cells.length; i++) {
      if (ray.hilt[i] !== 0) break;
      const pc = board[cells[i]];
      if (pc === null) continue;
      if (pc.owner === attacker && (pc.type === slider || pc.type === 'Q')) return true;
      break;
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

interface Ctx {
  board: Board;
  active: Active;
  player: Player;
  /** Masque des poignées ouvertes. */
  open: number;
  ep: readonly IEnPassant[];
}

function mk(from: number, to: number, capture: boolean, center: boolean, promo = false, ep = -1, double = false): IMove {
  return { from, to, promo, capture, ep, center, double };
}

export function pseudoMoves(ctx: Ctx): IMove[] {
  const { board, player, open } = ctx;
  const closed = ~open & 7;
  const out: IMove[] = [];
  for (let c = 0; c < NUM_CELLS; c++) {
    const pc = board[c];
    if (pc === null || pc.owner !== player) continue;
    switch (pc.type) {
      case 'P': {
        const cr = pc.crossed ? 1 : 0;
        const one = PAWN_PUSH[cr][c];
        if (one !== null && board[one.to] === null) {
          out.push(mk(c, one.to, false, one.center, cr === 1 && ringOf(one.to) === 0));
          if (cr === 0 && ringOf(c) === 1) {
            const two = PAWN_PUSH[0][one.to];
            if (two !== null && board[two.to] === null) out.push(mk(c, two.to, false, false, false, -1, true));
          }
        }
        for (const e of PAWN_CAPTURES[cr][c]) {
          if (!pawnCaptureOk(e, cr)) continue;
          const t = board[e.to];
          if (t !== null) {
            if (t.owner !== player) out.push(mk(c, e.to, true, e.center, cr === 1 && ringOf(e.to) === 0));
          } else {
            for (const ent of ctx.ep) {
              if (ent.target !== e.to || ent.owner === player) continue;
              const victim = board[ent.pawn];
              if (victim !== null && victim.type === 'P' && victim.owner === ent.owner) {
                out.push(mk(c, e.to, true, e.center, false, ent.pawn));
                break;
              }
            }
          }
        }
        break;
      }
      case 'N':
      case 'K': {
        const jumps = pc.type === 'N' ? KNIGHT_JUMPS[c] : KING_JUMPS[c];
        for (const j of jumps) {
          const t = board[j.to];
          if (t === null) {
            if ((j.mask & closed) === 0) out.push(mk(c, j.to, false, j.center));
          } else if (t.owner !== player && j.mask === 0) {
            out.push(mk(c, j.to, true, j.center));
          }
        }
        break;
      }
      default: {
        const d0 = pc.type === 'B' ? 4 : 0;
        const d1 = pc.type === 'R' ? 4 : 8;
        // Marquage par tampon : plusieurs rayons peuvent mener à la même case.
        if (seenStamp > 2e9) (SEEN.fill(0), (seenStamp = 0));
        const stamp = ++seenStamp;
        for (let d = d0; d < d1; d++) {
          const ray = RAYS[c * NUM_DIRS + d];
          const cells = ray.cells;
          for (let i = 0; i < cells.length; i++) {
            const mask = ray.hilt[i];
            if ((mask & closed) !== 0) break; // poignée fermée : infranchissable
            const t = cells[i];
            const tp = board[t];
            if (tp === null) {
              if (SEEN[t] !== stamp) {
                SEEN[t] = stamp;
                out.push(mk(c, t, false, ray.center[i] === 1));
              }
              continue;
            }
            // Une prise exige un trajet qui ne traverse aucune poignée.
            if (tp.owner !== player && mask === 0 && SEEN[t] !== stamp) {
              SEEN[t] = stamp;
              out.push(mk(c, t, true, ray.center[i] === 1));
            }
            break;
          }
        }
      }
    }
  }
  return out;
}

function castlingMoves(ctx: Ctx, rights: CastlingRights): IMove[] {
  const { board, active, player } = ctx;
  const out: IMove[] = [];
  if (!rights.king && !rights.queen) return out;
  const kc = cellIndex(player, KING_FILE, 0);
  const king = board[kc];
  if (!king || king.type !== 'K' || king.owner !== player) return out;
  if (isAttackedByAny(board, active, kc, player)) return out;
  const sq = (f: number) => cellIndex(player, f, 0);
  for (const side of ['king', 'queen'] as const) {
    if (!rights[side]) continue;
    const k = CASTLES[side];
    const rook = board[sq(k.rookFrom)];
    if (!rook || rook.type !== 'R' || rook.owner !== player) continue;
    if (k.empty.some((f) => board[sq(f)] !== null)) continue;
    if (k.safe.some((f) => isAttackedByAny(board, active, sq(f), player))) continue;
    out.push({ ...mk(kc, sq(k.kingTo), false, false), castle: side });
  }
  return out;
}

function legalFor(ctx: Ctx, rights: CastlingRights): IMove[] {
  const { board, active, player } = ctx;
  if (!active[player]) return [];
  const out: IMove[] = [];
  const kingCell = findKing(board, player);
  const inCheck = kingCell >= 0 && isAttackedByAny(board, active, kingCell, player);
  // Roi hors échec : un coup d'une autre pièce ne peut exposer le roi qu'en ouvrant une ligne,
  // donc seulement si la pièce part d'une case située sur une ligne du roi.
  const lines = kingCell >= 0 && !inCheck ? LINES[kingCell] : null;
  const b = board.slice();
  let reduced: boolean[] | null = null;
  for (const m of pseudoMoves(ctx)) {
    const taken = b[m.to];
    // Prise d'un roi « emprisonné » : son équipe est matée, ses pièces cessent d'attaquer.
    const kingTaken = taken !== null && taken.type === 'K' && active[taken.owner];
    if (lines !== null && m.from !== kingCell && m.ep < 0 && !kingTaken && lines[m.from] === 0) {
      out.push(m);
      continue;
    }
    let act: Active = active;
    if (kingTaken) {
      reduced = [...active];
      reduced[taken.owner] = false;
      act = reduced;
    }
    const moved = b[m.from];
    const epPiece = m.ep >= 0 ? b[m.ep] : null;
    b[m.from] = null;
    b[m.to] = moved;
    if (m.ep >= 0) b[m.ep] = null;
    const k = m.from === kingCell ? m.to : kingCell;
    if (k < 0 || !isAttackedByAny(b, act, k, player)) out.push(m);
    b[m.from] = moved;
    b[m.to] = taken;
    if (m.ep >= 0) b[m.ep] = epPiece;
  }
  for (const m of castlingMoves(ctx, rights)) out.push(m);
  return out;
}

export function toPublic(m: IMove, promotion: PromotionType = 'Q'): Move {
  const out: Move = { from: cellName(m.from), to: cellName(m.to) };
  if (m.castle) out.castle = m.castle;
  if (m.promo) out.promotion = promotion;
  if (m.capture) out.capture = true;
  if (m.ep >= 0) out.enPassant = true;
  return out;
}

const epCache = new WeakMap<GameState, IEnPassant[]>();
const NO_EP: IEnPassant[] = [];
function epInternal(s: GameState): IEnPassant[] {
  if (!s.enPassant || s.enPassant.length === 0) return NO_EP;
  let e = epCache.get(s);
  if (!e) {
    e = s.enPassant.map((x) => ({ target: parseCell(x.target), pawn: parseCell(x.pawn), owner: x.owner }));
    epCache.set(s, e);
  }
  return e;
}
const epPublic = (es: readonly IEnPassant[]): EnPassant[] =>
  es.map((e) => ({ target: cellName(e.target), pawn: cellName(e.pawn), owner: e.owner }));

function ctxOf(state: GameState): Ctx {
  return { board: state.board, active: state.active, player: state.turn, open: hiltMask(state.hilts), ep: epInternal(state) };
}

// Cache des coups légaux par état (les états sont immuables).
const legalCache = new WeakMap<GameState, IMove[]>();

/** Coups légaux internes (mis en cache, ne pas modifier). Une seule entrée par promotion. */
export function legalInternal(state: GameState): IMove[] {
  if (state.result) return [];
  let ms = legalCache.get(state);
  if (!ms) {
    ms = legalFor(ctxOf(state), state.castling[state.turn]);
    legalCache.set(state, ms);
  }
  return ms;
}

// ---------------------------------------------------------------------------
// Construction des états
// ---------------------------------------------------------------------------

const CODES = new Map<Piece, string>();
function pieceCode(pc: Piece): string {
  let k = CODES.get(pc);
  if (k === undefined) {
    k = (pc.crossed ? 'x' : pc.type) + pc.owner;
    if (Object.isFrozen(pc)) CODES.set(pc, k);
  }
  return k;
}

function positionKey(
  board: Board,
  turn: Player,
  active: Active,
  castling: readonly CastlingRights[],
  open: number,
  ep: readonly IEnPassant[],
): string {
  const parts: string[] = new Array(NUM_CELLS);
  for (let c = 0; c < NUM_CELLS; c++) {
    const pc = board[c];
    parts[c] = pc === null ? '.' : pieceCode(pc);
  }
  let s = parts.join('');
  s += '|' + turn + '|' + active.map((a) => (a ? 1 : 0)).join('') + '|' + open;
  s += '|' + castling.map((r) => (r.king ? 'K' : '-') + (r.queen ? 'Q' : '-')).join('');
  s += '|' + ep.map((e) => `${e.target}:${e.owner}`).join(',');
  return s;
}

/** Ouvre les poignées des équipes actives qui n'ont plus aucune pièce sur leur anneau 1. */
function refreshHilts(board: Board, active: Active, open: number): number {
  for (const s of PLAYERS) {
    if (!active[s]) continue;
    const [b1, b2] = TEAM_BORDERS[s];
    if ((open & (1 << b1)) !== 0 && (open & (1 << b2)) !== 0) continue;
    let any = false;
    for (const c of BACK_CELLS[s]) {
      const pc = board[c];
      if (pc !== null && pc.owner === s) {
        any = true;
        break;
      }
    }
    if (!any) open |= (1 << b1) | (1 << b2);
  }
  return open;
}

const teamHilts = (s: Player) => (1 << TEAM_BORDERS[s][0]) | (1 << TEAM_BORDERS[s][1]);

export interface CustomPiece {
  cell: string;
  type: PieceType;
  owner: Player;
  /** Pion ayant déjà traversé le centre. */
  crossed?: boolean;
}

export interface CustomOptions {
  turn?: Player;
  active?: [boolean, boolean, boolean];
  castling?: [CastlingRights, CastlingRights, CastlingRights];
  /** Poignées ouvertes ; par défaut déduites de la position (arrières vides, équipes éliminées). */
  hilts?: [boolean, boolean, boolean];
  enPassant?: EnPassant[];
}

/** Construit un état à partir d'une liste de pièces (tests, puzzles, reprise). */
export function customState(mode: Mode, pieces: CustomPiece[], opts: CustomOptions = {}): GameState {
  if (mode !== 'firstMate' && mode !== 'twoMates') throw new Error(`mode inconnu : ${mode}`);
  const board: Board = new Array(NUM_CELLS).fill(null);
  for (const p of pieces) {
    const c = parseCell(p.cell);
    if (board[c]) throw new Error(`case ${p.cell} déjà occupée`);
    board[c] = piece(p.type, p.owner, p.type === 'P' && !!p.crossed);
  }
  const active: [boolean, boolean, boolean] = opts.active ? [...opts.active] : [true, true, true];
  const castling = (opts.castling ?? [0, 1, 2].map(() => ({ king: false, queen: false }))).map((r) => ({ ...r })) as [
    CastlingRights,
    CastlingRights,
    CastlingRights,
  ];
  const turn = opts.turn ?? 0;
  let open: number;
  if (opts.hilts) open = hiltMask(opts.hilts);
  else {
    open = 0;
    for (const s of PLAYERS) if (!active[s]) open |= teamHilts(s);
    open = refreshHilts(board, active, open);
  }
  const ep = (opts.enPassant ?? []).map((e) => ({ target: parseCell(e.target), pawn: parseCell(e.pawn), owner: e.owner }));
  return {
    version: 2,
    mode,
    board,
    hilts: hiltArray(open),
    enPassant: epPublic(ep),
    turn,
    active,
    castling,
    ply: 0,
    quietTurns: 0,
    lastMoveAt: [-1, -1, -1],
    repetitions: { [positionKey(board, turn, active, castling, open, ep)]: 1 },
    eliminations: [],
    result: null,
    lastEvent: null,
  };
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

/** Coups légaux du joueur au trait (liste vide si la partie est finie) ; une variante par promotion. */
export function legalMoves(state: GameState): Move[] {
  const out: Move[] = [];
  for (const m of legalInternal(state)) {
    if (m.promo) for (const p of PROMOTIONS) out.push(toPublic(m, p));
    else out.push(toPublic(m));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Résolution des tours
// ---------------------------------------------------------------------------

interface Work {
  mode: Mode;
  board: Board;
  active: [boolean, boolean, boolean];
  castling: readonly CastlingRights[];
  lastMoveAt: readonly number[];
  open: number;
  ep: IEnPassant[];
  eliminations: Elimination[];
  ply: number;
  mates: { player: Player; by: Player }[];
  eliminated: Player[];
  passes: Player[];
  opened: number[];
  blocked: { player: Player; by: Player } | null;
  result: GameResult | null;
}

function openHilts(w: Work, mask: number): void {
  for (let b = 0; b < 3; b++) {
    const bit = 1 << b;
    if ((mask & bit) !== 0 && (w.open & bit) === 0) {
      w.open |= bit;
      w.opened.push(b);
    }
  }
}

function eliminate(w: Work, q: Player, by: Player | null, reason: Elimination['reason']): void {
  w.active[q] = false;
  w.eliminations.push({ player: q, by, reason, ply: w.ply });
  w.eliminated.push(q);
  w.ep = w.ep.filter((e) => e.owner !== q);
  openHilts(w, teamHilts(q));
}

function lastStanding(w: Work): boolean {
  if (activeCount(w.active) !== 1) return false;
  const winner = PLAYERS.find((p) => w.active[p])!;
  w.result = { winner, reason: 'lastStanding' };
  return true;
}

/**
 * Détermine l'équipe au trait à partir de `candidate` : une équipe sans coup légal est mate
 * (en échec) ou pate (elle passe). Si aucune équipe ne peut jouer : à 3, l'équipe au trait
 * perd ; à 2, partie nulle. Renvoie l'équipe au trait et ses coups légaux.
 */
function resolveTurn(w: Work, candidate: Player): { turn: Player; moves: IMove[] } {
  if (lastStanding(w)) return { turn: w.result!.winner!, moves: [] };
  let cur = candidate;
  let streak: Player[] = [];
  for (let guard = 0; guard < 20; guard++) {
    w.open = refreshHilts(w.board, w.active, w.open);
    const moves = legalFor({ board: w.board, active: w.active, player: cur, open: w.open, ep: w.ep }, w.castling[cur]);
    if (moves.length > 0) return { turn: cur, moves };
    const k = findKing(w.board, cur);
    const by = k >= 0 ? attackersOf(w.board, w.active, k, cur) : [];
    if (by.length > 0) {
      // Mat : crédité à l'attaquant ayant joué le plus récemment.
      let credit = by[0];
      for (const q of by) if (w.lastMoveAt[q] > w.lastMoveAt[credit]) credit = q;
      w.mates.push({ player: cur, by: credit });
      if (w.mode === 'firstMate') {
        w.result = { winner: credit, reason: 'mate' };
        return { turn: cur, moves: [] };
      }
      eliminate(w, cur, credit, 'mate');
      streak = [];
      if (lastStanding(w)) return { turn: w.result!.winner!, moves: [] };
      cur = nextActive(w.active, cur);
      continue;
    }
    // Pat : l'équipe passe son tour (son droit de prise en passant expire).
    w.passes.push(cur);
    w.ep = w.ep.filter((e) => e.owner !== cur);
    streak.push(cur);
    if (streak.length >= activeCount(w.active)) {
      if (activeCount(w.active) >= 3) {
        // Aucune équipe ne peut jouer : l'équipe au trait perd, au profit de la dernière à avoir joué.
        const loser = streak[0];
        let credit: Player = nextActive(w.active, loser);
        for (const q of PLAYERS) if (q !== loser && w.active[q] && w.lastMoveAt[q] > w.lastMoveAt[credit]) credit = q;
        w.blocked = { player: loser, by: credit };
        if (w.mode === 'firstMate') {
          w.result = { winner: credit, reason: 'blockade' };
          return { turn: loser, moves: [] };
        }
        eliminate(w, loser, credit, 'blocked');
        streak = [];
        if (lastStanding(w)) return { turn: w.result!.winner!, moves: [] };
        cur = nextActive(w.active, loser);
        continue;
      }
      w.result = { winner: null, reason: 'stalemate' };
      return { turn: cur, moves: [] };
    }
    cur = nextActive(w.active, cur);
  }
  throw new Error('résolution du tour impossible');
}

function newWork(state: GameState, board: Board, castling: readonly CastlingRights[], lastMoveAt: readonly number[], ply: number, ep: IEnPassant[]): Work {
  return {
    mode: state.mode,
    board,
    active: [...state.active] as [boolean, boolean, boolean],
    castling,
    lastMoveAt,
    open: hiltMask(state.hilts),
    ep,
    eliminations: state.eliminations.slice(),
    ply,
    mates: [],
    eliminated: [],
    passes: [],
    opened: [],
    blocked: null,
    result: null,
  };
}

type BaseEvent = Omit<GameEvent, 'checks' | 'mates' | 'eliminated' | 'passes' | 'gameOver' | 'hiltsOpened' | 'blocked'>;

function finalize(
  prev: GameState,
  w: Work,
  turn: Player,
  moves: IMove[],
  castling: [CastlingRights, CastlingRights, CastlingRights],
  quietTurns: number,
  lastMoveAt: [number, number, number],
  irreversible: boolean,
  base: BaseEvent,
): GameState {
  let result = w.result;
  quietTurns += w.passes.length;
  // Poignées ouvertes par cet évènement (élimination ou arrières vidés).
  const newly = w.open & ~hiltMask(prev.hilts);
  w.opened = [0, 1, 2].filter((b) => (newly & (1 << b)) !== 0);
  const repetitions: Record<string, number> = irreversible ? {} : { ...prev.repetitions };
  if (!result) {
    const key = positionKey(w.board, turn, w.active, castling, w.open, w.ep);
    const n = (repetitions[key] ?? 0) + 1;
    repetitions[key] = n;
    if (n >= 3) result = { winner: null, reason: 'repetition' };
    else if (quietTurns >= 50 * activeCount(w.active)) result = { winner: null, reason: 'fiftyMoves' };
  }
  const event: GameEvent = {
    ...base,
    checks: checksOn(w.board, w.active),
    mates: w.mates,
    eliminated: w.eliminated,
    passes: w.passes,
    hiltsOpened: w.opened,
    blocked: w.blocked,
    gameOver: result,
  };
  const state: GameState = {
    version: 2,
    mode: prev.mode,
    board: w.board,
    hilts: hiltArray(w.open),
    enPassant: epPublic(w.ep),
    turn,
    active: w.active,
    castling,
    ply: w.ply,
    quietTurns,
    lastMoveAt,
    repetitions,
    eliminations: w.eliminations,
    result,
    lastEvent: event,
  };
  legalCache.set(state, result ? [] : moves);
  return state;
}

/**
 * Applique un coup légal du joueur au trait. Lève une erreur si le coup est illégal.
 * Promotion : `move.promotion` (Q, R, B ou N), dame si absent.
 */
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
  let promo: PromotionType = 'Q';
  if (m.promo && move.promotion !== undefined && move.promotion !== null) {
    if (!PROMOTIONS.includes(move.promotion)) throw new Error(`promotion invalide : ${String(move.promotion)}`);
    promo = move.promotion;
  }
  return applyInternal(state, m, promo);
}

/** Applique un coup interne issu de legalInternal(state) (sans vérification). */
export function applyInternal(state: GameState, m: IMove, promotion: PromotionType = 'Q'): GameState {
  const { from, to } = m;
  const player = state.turn;
  const moved = state.board[from]!;
  const takenAt = m.ep >= 0 ? m.ep : to;
  const capturedPiece = state.board[takenAt];
  const board = state.board.slice();
  board[from] = null;
  if (m.ep >= 0) board[m.ep] = null;
  let placed = moved;
  if (moved.type === 'P') {
    if (m.promo) placed = piece(promotion, player);
    else if (m.center && !moved.crossed) placed = piece('P', player, true);
  }
  board[to] = placed;
  let rookFrom = -1;
  let rookTo = -1;
  if (m.castle) {
    rookFrom = cellIndex(player, CASTLES[m.castle].rookFrom, 0);
    rookTo = cellIndex(player, CASTLES[m.castle].rookTo, 0);
    board[rookTo] = board[rookFrom];
    board[rookFrom] = null;
  }

  const castling = state.castling.map((r) => ({ ...r })) as [CastlingRights, CastlingRights, CastlingRights];
  if (moved.type === 'K') castling[player] = { king: false, queen: false };
  for (const p of PLAYERS) {
    for (const c of [from, to]) {
      if (c === cellIndex(p, CASTLES.king.rookFrom, 0)) castling[p].king = false;
      if (c === cellIndex(p, CASTLES.queen.rookFrom, 0)) castling[p].queen = false;
      if (c === cellIndex(p, KING_FILE, 0)) castling[p] = { king: false, queen: false };
    }
  }

  const ply = state.ply + 1;
  const lastMoveAt = [...state.lastMoveAt] as [number, number, number];
  lastMoveAt[player] = ply;
  const irreversible = moved.type === 'P' || capturedPiece !== null;
  const quietTurns = irreversible ? 0 : state.quietTurns + 1;

  // Droits de prise en passant : ceux du joueur expirent quand il rejoue.
  const ep = epInternal(state).filter((e) => e.owner !== player);
  if (m.double) ep.push({ target: PAWN_PUSH[0][from]!.to, pawn: to, owner: player });

  const w = newWork(state, board, castling, lastMoveAt, ply, ep);
  // Roi « emprisonné » capturé : son équipe est matée, au profit du preneur.
  const kingCaptured = capturedPiece !== null && capturedPiece.type === 'K' && state.active[capturedPiece.owner] ? capturedPiece.owner : null;
  let res: { turn: Player; moves: IMove[] };
  if (kingCaptured !== null) {
    w.mates.push({ player: kingCaptured, by: player });
    if (state.mode === 'firstMate') {
      w.result = { winner: player, reason: 'mate' };
      w.open = refreshHilts(w.board, w.active, w.open);
      res = { turn: player, moves: [] };
    } else {
      eliminate(w, kingCaptured, player, 'mate');
      res = resolveTurn(w, nextActive(w.active, player));
    }
  } else {
    res = resolveTurn(w, nextActive(w.active, player));
  }
  return finalize(state, w, res.turn, res.moves, castling, quietTurns, lastMoveAt, irreversible, {
    kind: 'move',
    player,
    move: { from: cellName(from), to: cellName(to) },
    piece: moved.type,
    captured: capturedPiece
      ? { type: capturedPiece.type, owner: capturedPiece.owner, frozen: !state.active[capturedPiece.owner], at: cellName(takenAt) }
      : null,
    promotion: m.promo ? promotion : null,
    castle: m.castle ? { side: m.castle, rookFrom: cellName(rookFrom), rookTo: cellName(rookTo) } : null,
    crossedCenter: m.center,
    enPassant: m.ep >= 0,
    kingCaptured,
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
  const w = newWork(state, state.board, state.castling, state.lastMoveAt, state.ply, epInternal(state));
  eliminate(w, player, null, 'resign');
  const candidate = state.turn === player ? nextActive(w.active, player) : state.turn;
  const res = resolveTurn(w, candidate);
  return finalize(state, w, res.turn, res.moves, state.castling.map((r) => ({ ...r })) as GameState['castling'], state.quietTurns, [...state.lastMoveAt], false, {
    kind: 'resign',
    player,
  });
}

/** Coup légal aléatoire pour le joueur au trait (timeout ; promotion en dame). rng renvoie un réel dans [0, 1). */
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
    hilts: [...state.hilts] as [boolean, boolean, boolean],
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
