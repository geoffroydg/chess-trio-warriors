// Notifications FCM HTTP v1 (jeton OAuth2 obtenu par JWT RS256 signé avec WebCrypto).
import type { PushMessage } from './room-logic.ts';

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

const b64url = (data: ArrayBuffer | string): string => {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

export class FcmClient {
  private sa: ServiceAccount | null = null;
  private cached: { token: string; expires: number } | null = null;

  private fetchFn: typeof fetch;
  private now: () => number;

  constructor(serviceAccountJson: string | undefined, fetchFn: typeof fetch = (input, init) => fetch(input, init), now: () => number = Date.now) {
    this.fetchFn = fetchFn;
    this.now = now;
    if (serviceAccountJson) {
      try {
        this.sa = JSON.parse(serviceAccountJson);
      } catch {
        console.log('FCM_SERVICE_ACCOUNT illisible : push désactivé');
      }
    } else {
      console.log('FCM_SERVICE_ACCOUNT absent : push désactivé');
    }
  }

  get enabled(): boolean {
    return this.sa !== null;
  }

  private async accessToken(): Promise<string> {
    const sa = this.sa!;
    const now = this.now();
    if (this.cached && now < this.cached.expires) return this.cached.token;
    const iat = Math.floor(now / 1000);
    const tokenUri = sa.token_uri ?? 'https://oauth2.googleapis.com/token';
    const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = b64url(
      JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: tokenUri, iat, exp: iat + 3600 }),
    );
    const key = await crypto.subtle.importKey('pkcs8', pemToDer(sa.private_key), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
    const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`));
    const res = await this.fetchFn(tokenUri, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${header}.${claims}.${b64url(sig)}` }),
    });
    if (!res.ok) throw new Error(`OAuth2 ${res.status}`);
    const json = (await res.json()) as { access_token: string };
    this.cached = { token: json.access_token, expires: now + 55 * 60_000 };
    return json.access_token;
  }

  /** Envoie les messages ; renvoie les jetons que FCM déclare invalides (UNREGISTERED / 404). */
  async send(messages: PushMessage[]): Promise<string[]> {
    const invalid: string[] = [];
    if (!this.sa || messages.length === 0) return invalid;
    try {
      const token = await this.accessToken();
      const url = `https://fcm.googleapis.com/v1/projects/${this.sa.project_id}/messages:send`;
      await Promise.all(
        messages.map(async (m) => {
          const res = await this.fetchFn(url, {
            method: 'POST',
            headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
            body: JSON.stringify({
              message: {
                token: m.fcmToken,
                // Data-only : l'app affiche elle-même la notification (et peut la filtrer).
                data: { ...m.data, title: m.title, body: m.body },
                android: { priority: 'high' },
              },
            }),
          });
          if (!res.ok) {
            const text = await res.text();
            console.log(`FCM ${res.status}: ${text.slice(0, 200)}`);
            if (res.status === 404 || text.includes('UNREGISTERED')) invalid.push(m.fcmToken);
          }
        }),
      );
    } catch (e) {
      console.log(`FCM erreur : ${String(e)}`);
    }
    return invalid;
  }
}
