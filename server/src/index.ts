import { generateCode } from './room-logic.ts';
import { Room } from './room.ts';

export { Room };

export interface Env {
  ROOM: DurableObjectNamespace<Room>;
  FCM_SERVICE_ACCOUNT?: string;
  /** Budget CPU d'un coup de bot en ms (défaut 8). */
  BOT_CPU_MS?: string;
}

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type',
  'access-control-max-age': '86400',
};

function respond(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', ...CORS } });
}

const err = (status: number, error: string, message: string) => respond({ error, message }, status);

async function readJson(request: Request): Promise<Record<string, unknown> | null> {
  const text = await request.text();
  if (text.length > 2048) return null;
  try {
    const v = JSON.parse(text);
    return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

async function forward(res: Response): Promise<Response> {
  return new Response(res.body, { status: res.status, headers: { 'content-type': 'application/json', ...CORS } });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    if (path === '/health') return respond({ ok: true });

    if (path === '/rooms' && request.method === 'POST') {
      const body = await readJson(request);
      if (!body) return err(400, 'badRequest', 'Corps JSON invalide ou trop gros.');
      for (let i = 0; i < 5; i++) {
        const code = generateCode();
        const stub = env.ROOM.get(env.ROOM.idFromName(code));
        const res = await stub.fetch('https://room/init', { method: 'POST', body: JSON.stringify({ ...body, code }) });
        if (res.status !== 409) return forward(res);
      }
      return err(500, 'codeCollision', 'Impossible de générer un code, réessaie.');
    }

    const m = path.match(/^\/rooms\/([A-Za-z0-9]{6})\/(join|ws)$/);
    if (m) {
      const code = m[1].toUpperCase();
      const stub = env.ROOM.get(env.ROOM.idFromName(code));
      if (m[2] === 'join' && request.method === 'POST') {
        const body = await readJson(request);
        if (!body) return err(400, 'badRequest', 'Corps JSON invalide ou trop gros.');
        return forward(await stub.fetch('https://room/join', { method: 'POST', body: JSON.stringify(body) }));
      }
      if (m[2] === 'ws' && request.method === 'GET') {
        // Salon inexistant : le DO répond 401 (jeton inconnu), sans créer de données.
        const res = await stub.fetch(`https://room/ws?token=${encodeURIComponent(url.searchParams.get('token') ?? '')}`, {
          headers: request.headers,
        });
        return res.status === 101 ? res : forward(res);
      }
    }
    return err(404, 'notFound', 'Introuvable.');
  },
} satisfies ExportedHandler<Env>;
