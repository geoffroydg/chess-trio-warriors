import { DurableObject } from 'cloudflare:workers';
import { FcmClient } from './fcm.ts';
import { RoomLogic, parseBotCpuMs } from './room-logic.ts';
import type { RoomData } from './room-logic.ts';
import type { Env } from './index.ts';

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

export class Room extends DurableObject<Env> {
  private logic: RoomLogic;
  private fcm: FcmClient;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.fcm = new FcmClient(env.FCM_SERVICE_ACCOUNT);
    this.logic = new RoomLogic({
      now: () => Date.now(),
      rng: Math.random,
      load: async () => (await ctx.storage.get<RoomData>('room')) ?? null,
      save: (d) => ctx.storage.put('room', d),
      deleteAll: async () => {
        await ctx.storage.deleteAlarm();
        await ctx.storage.deleteAll();
        for (const ws of ctx.getWebSockets()) ws.close(1000, 'room closed');
      },
      setAlarm: async (at) => {
        if (at === null) await ctx.storage.deleteAlarm();
        else await ctx.storage.setAlarm(at);
      },
      isConnected: (id) => ctx.getWebSockets(`p${id}`).length > 0,
      send: (id, msg) => {
        const text = JSON.stringify(msg);
        for (const ws of ctx.getWebSockets(`p${id}`)) {
          try {
            ws.send(text);
          } catch {
            /* socket fermé */
          }
        }
      },
      notify: (msgs) => ctx.waitUntil(this.fcm.send(msgs)),
      botCpuMs: parseBotCpuMs(env.BOT_CPU_MS),
    });
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/init' && request.method === 'POST') {
      const { code, ...body } = (await request.json()) as { code: string };
      const r = await this.logic.create(code, body);
      return r.ok ? json(r.value, 201) : json({ error: r.error, message: r.message }, r.status);
    }
    if (url.pathname === '/join' && request.method === 'POST') {
      const r = await this.logic.join((await request.json()) as object);
      return r.ok ? json(r.value) : json({ error: r.error, message: r.message }, r.status);
    }
    if (url.pathname === '/ws') {
      if (request.headers.get('Upgrade') !== 'websocket') return json({ error: 'badRequest', message: 'WebSocket attendu.' }, 426);
      const playerId = await this.logic.authenticate(url.searchParams.get('token'));
      if (playerId === null) return json({ error: 'badToken', message: 'Jeton inconnu.' }, 401);
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1], [`p${playerId}`]);
      await this.logic.onConnect(playerId);
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    return json({ error: 'notFound', message: 'Introuvable.' }, 404);
  }

  private playerOf(ws: WebSocket): 0 | 1 | 2 | null {
    const tag = this.ctx.getTags(ws).find((t) => /^p[012]$/.test(t));
    return tag ? (Number(tag[1]) as 0 | 1 | 2) : null;
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const id = this.playerOf(ws);
    if (id === null || typeof message !== 'string' || message.length > 8192) return;
    await this.logic.onMessage(id, message);
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    const id = this.playerOf(ws);
    try {
      ws.close(code, reason);
    } catch {
      /* déjà fermé */
    }
    if (id !== null) await this.logic.onDisconnect(id);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    await this.webSocketClose(ws, 1011, 'error');
  }

  async alarm(): Promise<void> {
    await this.logic.onAlarm();
  }
}
