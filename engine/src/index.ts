// API publique du moteur de règles d'échecs à 3 joueurs (plateau rond « Chess for 3 »).
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
  BACK_RANK,
} from './rules.ts';
export type { CustomPiece, CustomOptions } from './rules.ts';
export { botMove, botDecision, isBotLevel, BOT_LEVELS, DEFAULT_BOT_CPU_MS, LEVEL_PROFILES, NODES_PER_MS } from './bot.ts';
export type { BotLevel, BotOptions, BotDecision, LevelProfile } from './bot.ts';
export {
  roundBoardCells,
  roundOutline,
  swordGeometry,
  RING_RADII,
  MEDALLION_RADIUS,
  sectorStartAngle,
  angularSector,
} from './round.ts';
export type { RoundCellGeometry, SwordGeometry, Point } from './round.ts';
export { cellName, parseCell, cellIndex, cellAt, wedgeOf, isLight, borderBetween, TEAM_BORDERS, NUM_CELLS, FILES } from './board.ts';
export type * from './types.ts';
