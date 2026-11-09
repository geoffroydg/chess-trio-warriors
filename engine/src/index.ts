// API publique du moteur de règles d'échecs à 3 joueurs.
export {
  initialState,
  legalMoves,
  applyMove,
  randomMove,
  resign,
  status,
  customState,
  pieceAt,
  isCellAttacked,
  nextPlayer,
} from './rules.ts';
export type { CustomPiece, CustomOptions } from './rules.ts';
export { botMove, botDecision, isBotLevel, BOT_LEVELS, DEFAULT_BOT_CPU_MS, LEVEL_PROFILES, NODES_PER_MS } from './bot.ts';
export type { BotLevel, BotOptions, BotDecision, LevelProfile } from './bot.ts';
export { boardCells, boardOutline } from './geometry.ts';
export type { CellGeometry, Point } from './geometry.ts';
export { roundBoardCells, roundOutline, RING_RADII, MEDALLION_RADIUS, sectorStartAngle, angularSector } from './round.ts';
export type { RoundCellGeometry } from './round.ts';
export { cellName, parseCell, NUM_CELLS, FILES } from './topology.ts';
export type * from './types.ts';
