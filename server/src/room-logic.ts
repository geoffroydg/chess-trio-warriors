// Logique pure d'un salon (aucune dépendance Cloudflare) : horloge, rng, stockage et envoi sont injectés.
import { applyMove, botMove, initialState, isBotLevel, legalMoves, randomMove, resign, status } from '../../engine/src/index.ts';
import type { BotLevel, GameEvent, GameState, Mode, Move, Player } from '../../engine/src/index.ts';

export const TURN_MS = 60_000;
export const FINISHED_TTL_MS = 24 * 3600_000;
export const INACTIVITY_TTL_MS = 7 * 24 * 3600_000;
export const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
/** Délai « naturel » avant le coup d'un bot : entre BOT_DELAY_MIN_MS et BOT_DELAY_MAX_MS. */
export const BOT_DELAY_MIN_MS = 1200;
export const BOT_DELAY_MAX_MS = 2500;
/** Noms de guerriers originaux donnés aux bots. */
export const BOT_NAMES = ['Maître Kaïro', 'Ryuna', 'Sensei Brakk', 'Zéphyra', 'Oboru', 'Kenzan', 'Miyra Tempête', 'Vaskor'];

export interface PlayerRecord {
  id: Player;
  pseudo: string;
  token: string;
  fcmToken?: string;
  /** Joueur artificiel joué par le serveur. */
  isBot?: boolean;
  botLevel?: BotLevel;
}

export interface RoomData {
  code: string;
  mode: Mode;
  createdAt: number;
  lastActivity: number;
  passwordHash: string;
  salt: string;
  players: PlayerRecord[];
  started: boolean;
  state: GameState | null;
  lastEvent: (GameEvent & { auto?: boolean }) | null;
  turnDeadline: number | null;
  /** Échéance du prochain coup d'un bot (null si ce n'est pas au tour d'un bot). */
  botMoveAt?: number | null;
  finishedAt: number | null;
}

export interface PushMessage {
  fcmToken: string;
  title: string;
  body: string;
  data: { roomCode: string; type: 'turn' | 'move' | 'resign' | 'gameOver' };
}

export interface RoomDeps {
  now: () => number;
  rng: () => number;
  load: () => Promise<RoomData | null>;
  save: (data: RoomData) => Promise<void>;
  deleteAll: () => Promise<void>;
  /** Programme l'alarme (timestamp ms) ou l'annule (null). */
  setAlarm: (at: number | null) => Promise<void>;
  isConnected: (playerId: Player) => boolean;
  send: (playerId: Player, message: ServerMessage) => void;
  notify: (messages: PushMessage[]) => void;
}

export type ServerMessage = Record<string, unknown> & { type: string };

export type HttpResult<T> = { ok: true; value: T } | { ok: false; status: number; error: string; message: string };

const fail = (status: number, error: string, message: string): { ok: false; status: number; error: string; message: string } => ({
  ok: false,
  status,
  error,
  message,
});

function hex(buf: ArrayBuffer | Uint8Array): string {
  return [...new Uint8Array(buf instanceof Uint8Array ? buf : buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function randomHex(bytes: number): string {
  return hex(crypto.getRandomValues(new Uint8Array(bytes)));
}

export async function hashPassword(password: string, salt: string): Promise<string> {
  return hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${salt}:${password}`)));
}

export function generateCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return [...bytes].map((b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join('');
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

export function validatePseudo(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const p = v.trim();
  return p.length >= 1 && p.length <= 16 ? p : null;
}

export function validatePassword(v: unknown): string | null {
  return typeof v === 'string' && v.length >= 1 && v.length <= 64 ? v : null;
}

const CELL_RE = /^[0-2][a-h][1-4]$/;

export class RoomLogic {
  private data: RoomData | null = null;
  private loaded = false;

  private deps: RoomDeps;

  constructor(deps: RoomDeps) {
    this.deps = deps;
  }

  private async ensure(): Promise<RoomData | null> {
    if (!this.loaded) {
      this.data = await this.deps.load();
      this.loaded = true;
    }
    return this.data;
  }

  get exists(): boolean {
    return this.data !== null;
  }

  async isInitialised(): Promise<boolean> {
    return (await this.ensure()) !== null;
  }

  // ---------- HTTP ----------

  async create(
    code: string,
    body: { pseudo?: unknown; password?: unknown; mode?: unknown; bots?: unknown },
  ): Promise<HttpResult<{ code: string; playerId: Player; playerToken: string }>> {
    if (await this.ensure()) return fail(409, 'codeTaken', 'Ce code existe déjà.');
    const pseudo = validatePseudo(body.pseudo);
    if (!pseudo) return fail(400, 'badRequest', 'Pseudo : 1 à 16 caractères.');
    let bots: BotLevel[] = [];
    if (body.bots !== undefined) {
      if (!Array.isArray(body.bots) || body.bots.length < 1 || body.bots.length > 2) return fail(400, 'badRequest', 'bots : 1 ou 2 bots.');
      for (const b of body.bots) {
        const level = b && typeof b === 'object' ? (b as { level?: unknown }).level : undefined;
        if (!isBotLevel(level)) return fail(400, 'badRequest', 'Niveau de bot invalide (facile, moyen ou difficile).');
        bots.push(level);
      }
    }
    // Partie solo (2 bots) : personne ne peut rejoindre, le mot de passe est facultatif.
    const solo = bots.length === 2;
    const password = solo && (body.password === undefined || body.password === '') ? randomHex(16) : validatePassword(body.password);
    if (!password) return fail(400, 'badRequest', 'Mot de passe : 1 à 64 caractères.');
    if (body.mode !== 'firstMate' && body.mode !== 'twoMates') return fail(400, 'badRequest', 'Mode invalide.');
    const now = this.deps.now();
    const salt = randomHex(16);
    const token = randomHex(24);
    this.data = {
      code,
      mode: body.mode,
      createdAt: now,
      lastActivity: now,
      passwordHash: await hashPassword(password, salt),
      salt,
      players: [{ id: 0, pseudo, token }],
      started: false,
      state: null,
      lastEvent: null,
      turnDeadline: null,
      botMoveAt: null,
      finishedAt: null,
    };
    bots.forEach((level, i) => this.seatBot(this.data!, (i + 1) as Player, level));
    if (this.data.players.length === 3) this.startGame(this.data);
    await this.persist();
    return { ok: true, value: { code, playerId: 0, playerToken: token } };
  }

  async join(body: { pseudo?: unknown; password?: unknown }): Promise<HttpResult<{ code: string; playerId: Player; playerToken: string }>> {
    const d = await this.ensure();
    if (!d) return fail(404, 'roomNotFound', 'Salon introuvable.');
    const pseudo = validatePseudo(body.pseudo);
    const password = validatePassword(body.password);
    if (!pseudo || !password) return fail(400, 'badRequest', 'Pseudo (1 à 16 car.) et mot de passe requis.');
    if (!timingSafeEqual(await hashPassword(password, d.salt), d.passwordHash)) return fail(403, 'wrongPassword', 'Mot de passe incorrect.');
    if (d.started) return fail(409, 'alreadyStarted', 'La partie a déjà commencé.');
    const id = this.freeSeat(d);
    if (id === null) return fail(409, 'roomFull', 'Le salon est complet.');
    const token = randomHex(24);
    this.addPlayer(d, { id, pseudo, token });
    d.lastActivity = this.deps.now();
    await this.persist();
    this.broadcastRoom();
    return { ok: true, value: { code: d.code, playerId: id, playerToken: token } };
  }

  /** Renvoie l'id du joueur correspondant au jeton, ou null. */
  async authenticate(token: string | null): Promise<Player | null> {
    const d = await this.ensure();
    if (!d || !token) return null;
    const p = d.players.find((x) => !x.isBot && timingSafeEqual(x.token, token));
    return p ? p.id : null;
  }

  // ---------- WebSocket ----------

  /** À appeler quand un socket du joueur vient d'être accepté (ou après un réveil). */
  async onConnect(playerId: Player): Promise<void> {
    const d = await this.ensure();
    if (!d) return;
    d.lastActivity = this.deps.now();
    await this.persist();
    this.deps.send(playerId, this.roomMessage(playerId));
    if (d.started) this.deps.send(playerId, this.gameMessage());
    this.broadcastRoom(playerId);
  }

  async onDisconnect(_playerId: Player): Promise<void> {
    if (!(await this.ensure())) return;
    this.broadcastRoom();
  }

  async onMessage(playerId: Player, raw: string): Promise<void> {
    const d = await this.ensure();
    if (!d) return;
    const err = (code: string, message: string) => this.deps.send(playerId, { type: 'error', code, message });
    let msg: any;
    try {
      msg = JSON.parse(raw);
    } catch {
      return err('badMessage', 'JSON invalide.');
    }
    if (!msg || typeof msg !== 'object' || typeof msg.type !== 'string') return err('badMessage', 'Message invalide.');
    switch (msg.type) {
      case 'ping':
        this.deps.send(playerId, { type: 'pong', now: this.deps.now() });
        return;
      case 'registerPush': {
        if (typeof msg.fcmToken !== 'string' || msg.fcmToken.length < 1 || msg.fcmToken.length > 4096) return err('badMessage', 'fcmToken invalide.');
        const me = d.players.find((p) => p.id === playerId);
        if (!me) return;
        me.fcmToken = msg.fcmToken;
        await this.persist();
        this.broadcastRoom();
        return;
      }
      case 'start': {
        if (playerId !== 0) return err('notHost', "Seul l'hôte peut lancer la partie.");
        if (d.started) return err('alreadyStarted', 'La partie a déjà commencé.');
        if (d.players.length < 3) return err('notEnoughPlayers', 'Il faut 3 joueurs.');
        this.startGame(d);
        await this.persist();
        this.broadcastRoom();
        this.broadcastGame();
        return;
      }
      case 'addBot': {
        if (playerId !== 0) return err('notHost', "Seul l'hôte peut ajouter un bot.");
        if (d.started) return err('alreadyStarted', 'La partie a déjà commencé.');
        const level = msg.level === undefined ? 'moyen' : msg.level;
        if (!isBotLevel(level)) return err('badMessage', 'Niveau invalide (facile, moyen ou difficile).');
        let seat: Player | null;
        if (msg.seat === undefined || msg.seat === null) seat = this.freeSeat(d);
        else {
          if (msg.seat !== 1 && msg.seat !== 2) return err('badMessage', 'Siège invalide (1 ou 2).');
          if (d.players.some((p) => p.id === msg.seat)) return err('seatTaken', 'Ce siège est déjà occupé.');
          seat = msg.seat as Player;
        }
        if (seat === null) return err('roomFull', 'Le salon est complet.');
        this.seatBot(d, seat, level);
        d.lastActivity = this.deps.now();
        await this.persist();
        this.broadcastRoom();
        return;
      }
      case 'removeBot': {
        if (playerId !== 0) return err('notHost', "Seul l'hôte peut retirer un bot.");
        if (d.started) return err('alreadyStarted', 'La partie a déjà commencé.');
        const bot = d.players.find((p) => p.id === msg.seat);
        if (!bot || !bot.isBot) return err('notBot', "Il n'y a pas de bot sur ce siège.");
        d.players = d.players.filter((p) => p !== bot);
        d.lastActivity = this.deps.now();
        await this.persist();
        this.broadcastRoom();
        return;
      }
      case 'move': {
        if (!d.started || !d.state) return err('notStarted', "La partie n'a pas commencé.");
        if (d.state.result) return err('gameOver', 'La partie est terminée.');
        if (d.state.turn !== playerId) return err('notYourTurn', "Ce n'est pas ton tour.");
        if (typeof msg.from !== 'string' || typeof msg.to !== 'string' || !CELL_RE.test(msg.from) || !CELL_RE.test(msg.to)) return err('illegalMove', 'Coup invalide.');
        const move = legalMoves(d.state).find((m) => m.from === msg.from && m.to === msg.to);
        if (!move) return err('illegalMove', 'Coup illégal.');
        d.lastActivity = this.deps.now();
        await this.play(move, false);
        return;
      }
      case 'resign': {
        if (!d.started || !d.state) return err('notStarted', "La partie n'a pas commencé.");
        if (d.state.result) return err('gameOver', 'La partie est terminée.');
        if (!d.state.active[playerId]) return err('notActive', "Tu n'es plus en jeu.");
        const prevTurn = d.state.turn;
        d.state = resign(d.state, playerId);
        d.lastEvent = d.state.lastEvent;
        d.lastActivity = this.deps.now();
        if (d.state.result) this.finish(d);
        else if (d.state.turn !== prevTurn) d.turnDeadline = this.deps.now() + TURN_MS;
        this.scheduleBot(d);
        await this.persist();
        this.broadcastGame();
        this.pushAfter(d.lastEvent!, false);
        return;
      }
      default:
        return err('badMessage', `Type inconnu : ${String(msg.type).slice(0, 32)}`);
    }
  }

  // ---------- Alarme ----------

  async onAlarm(): Promise<void> {
    const d = await this.ensure();
    if (!d) return;
    const now = this.deps.now();
    if (now >= this.cleanupAt(d)) {
      this.data = null;
      await this.deps.deleteAll();
      return;
    }
    if (d.started && d.state && !d.state.result) {
      const bot = this.botAt(d, d.state.turn);
      const botDue = bot && d.botMoveAt != null && now >= d.botMoveAt;
      if (bot && (botDue || (d.turnDeadline !== null && now >= d.turnDeadline))) {
        await this.play(botMove(d.state, bot.botLevel ?? 'moyen', { rng: this.deps.rng }), false);
        return;
      }
      if (d.turnDeadline !== null && now >= d.turnDeadline) {
        await this.play(randomMove(d.state, this.deps.rng), true);
        return;
      }
      // Bot au trait sans échéance programmée (ancienne donnée) : on la programme.
      if (bot && d.botMoveAt == null) this.scheduleBot(d);
    }
    await this.persist();
  }

  // ---------- Interne ----------

  private async play(move: Move, auto: boolean): Promise<void> {
    const d = this.data!;
    const now = this.deps.now();
    d.state = applyMove(d.state!, move);
    d.lastEvent = { ...(d.state.lastEvent as GameEvent), ...(auto ? { auto: true } : {}) };
    if (d.state.result) this.finish(d);
    else d.turnDeadline = now + TURN_MS;
    this.scheduleBot(d);
    await this.persist();
    this.broadcastGame();
    this.pushAfter(d.lastEvent, auto);
  }

  private finish(d: RoomData): void {
    d.turnDeadline = null;
    d.botMoveAt = null;
    d.finishedAt = this.deps.now();
  }

  private startGame(d: RoomData): void {
    const now = this.deps.now();
    d.started = true;
    d.state = initialState(d.mode);
    d.lastEvent = null;
    d.turnDeadline = now + TURN_MS;
    d.lastActivity = now;
    this.scheduleBot(d);
  }

  /** Programme le coup du bot au trait (délai naturel), ou annule l'échéance. */
  private scheduleBot(d: RoomData): void {
    const st = d.state;
    if (!d.started || !st || st.result || !this.botAt(d, st.turn)) {
      d.botMoveAt = null;
      return;
    }
    d.botMoveAt = this.deps.now() + BOT_DELAY_MIN_MS + Math.floor(this.deps.rng() * (BOT_DELAY_MAX_MS - BOT_DELAY_MIN_MS));
  }

  private botAt(d: RoomData, id: Player): PlayerRecord | null {
    const p = d.players.find((x) => x.id === id);
    return p && p.isBot ? p : null;
  }

  private freeSeat(d: RoomData): Player | null {
    for (const id of [0, 1, 2] as Player[]) if (!d.players.some((p) => p.id === id)) return id;
    return null;
  }

  private addPlayer(d: RoomData, p: PlayerRecord): void {
    d.players.push(p);
    d.players.sort((a, b) => a.id - b.id);
  }

  private seatBot(d: RoomData, id: Player, level: BotLevel): void {
    const used = new Set(d.players.map((p) => p.pseudo));
    const free = BOT_NAMES.filter((n) => !used.has(n));
    const pool = free.length ? free : BOT_NAMES;
    const pseudo = pool[Math.min(pool.length - 1, Math.floor(this.deps.rng() * pool.length))];
    this.addPlayer(d, { id, pseudo, token: '', isBot: true, botLevel: level });
  }

  private cleanupAt(d: RoomData): number {
    return d.finishedAt !== null ? d.finishedAt + FINISHED_TTL_MS : d.lastActivity + INACTIVITY_TTL_MS;
  }

  private async persist(): Promise<void> {
    const d = this.data;
    if (!d) return;
    await this.deps.save(d);
    const times = [this.cleanupAt(d)];
    if (d.turnDeadline !== null && !d.state?.result) times.push(d.turnDeadline);
    // Une seule alarme par DO : la plus proche des échéances (bot, minuteur, nettoyage).
    if (d.botMoveAt != null && !d.state?.result) times.push(d.botMoveAt);
    await this.deps.setAlarm(Math.min(...times));
  }

  private playersInfo() {
    const d = this.data!;
    return d.players.map((p) =>
      p.isBot
        ? { id: p.id, pseudo: p.pseudo, connected: true, push: false, isBot: true, level: p.botLevel ?? 'moyen' }
        : { id: p.id, pseudo: p.pseudo, connected: this.deps.isConnected(p.id), push: !!p.fcmToken, isBot: false },
    );
  }

  private roomMessage(you: Player): ServerMessage {
    const d = this.data!;
    return { type: 'room', code: d.code, mode: d.mode, players: this.playersInfo(), ready: d.players.length === 3, started: d.started, you };
  }

  private broadcastRoom(only?: Player): void {
    const d = this.data;
    if (!d) return;
    for (const p of d.players) if (p.id !== only && !p.isBot) this.deps.send(p.id, this.roomMessage(p.id));
  }

  private gameMessage(): ServerMessage {
    const d = this.data!;
    const st = d.state!;
    const s = status(st);
    return {
      type: 'game',
      state: st,
      lastEvent: d.lastEvent,
      turn: s.turn,
      legalMoves: s.over ? [] : legalMoves(st),
      turnDeadline: d.turnDeadline,
      over: s.over,
      result: st.result,
      players: this.playersInfo(),
    };
  }

  private broadcastGame(): void {
    const d = this.data!;
    const msg = this.gameMessage();
    for (const p of d.players) if (!p.isBot) this.deps.send(p.id, msg);
  }

  private pushAfter(ev: GameEvent, auto: boolean): void {
    const d = this.data!;
    const st = d.state!;
    const name = (id: Player) => d.players.find((p) => p.id === id)?.pseudo ?? `Joueur ${id + 1}`;
    const code = d.code;
    const out: PushMessage[] = [];
    const add = (p: PlayerRecord, title: string, body: string, type: PushMessage['data']['type']) => {
      if (p.fcmToken && !p.isBot) out.push({ fcmToken: p.fcmToken, title, body, data: { roomCode: code, type } });
    };
    const desc =
      ev.kind === 'move' && ev.move
        ? `${name(ev.player)} : ${ev.move.from} → ${ev.move.to}${ev.captured ? ' (prise)' : ''}${auto ? ' (coup automatique)' : ''}`
        : `${name(ev.player)} a abandonné`;
    if (st.result) {
      const r = st.result;
      const body = r.winner === null ? 'Partie nulle.' : `${name(r.winner)} remporte la partie !`;
      for (const p of d.players) add(p, 'Partie terminée', body, 'gameOver');
    } else if (ev.kind === 'resign') {
      for (const p of d.players) {
        if (p.id === ev.player) continue;
        if (p.id === st.turn) add(p, "C'est ton tour !", desc, 'turn');
        else add(p, `${name(ev.player)} a abandonné`, desc, 'resign');
      }
    } else {
      for (const p of d.players) {
        if (p.id === ev.player) continue;
        if (p.id === st.turn) add(p, "C'est ton tour !", desc, 'turn');
        else add(p, `${name(ev.player)} a joué`, desc, 'move');
      }
    }
    if (out.length) this.deps.notify(out);
  }
}
