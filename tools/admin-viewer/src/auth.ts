// Staff links are signed by the game (code/modules/metrics/metrics_viewer.dm) as
//   "<ckey>|<rights>|<expires unix>|<signature>"
// with signature = sha256(secret + sha256(secret + payload)) in lowercase hex. rust-g has no
// HMAC, so this nested keyed hash stands in for one: the outer hash blocks length extension.

import { createHash, timingSafeEqual } from 'node:crypto';

/** Admin rights bits (code/__defines/admin.dm). */
export const R_ADMIN = 1 << 1;
export const R_SERVER = 1 << 4;
export const R_DEBUG = 1 << 5;
/** Every page needs one of these; the staff page needs R_ADMIN. */
export const R_VIEWER = R_ADMIN | R_SERVER | R_DEBUG;

export type Session = { ckey: string; rights: number; expires: number };

const sha256 = (text: string) =>
  createHash('sha256').update(text, 'utf8').digest('hex');

export function sign(payload: string, secret: string): string {
  return sha256(secret + sha256(secret + payload));
}

export function mintToken(
  ckey: string,
  rights: number,
  expires: number,
  secret: string,
): string {
  const payload = `${ckey}|${rights}|${Math.floor(expires)}`;
  return `${payload}|${sign(payload, secret)}`;
}

export function verifyToken(
  token: string | null | undefined,
  secret: string,
  now = Date.now() / 1000,
): Session | null {
  if (!token || !secret) return null;
  const parts = token.split('|');
  if (parts.length !== 4) return null;
  const [ckey, rightsText, expiresText, signature] = parts;
  const expected = sign(`${ckey}|${rightsText}|${expiresText}`, secret);
  if (
    signature.length !== expected.length ||
    !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))
  )
    return null;
  const rights = Number(rightsText);
  const expires = Number(expiresText);
  if (!Number.isFinite(rights) || !Number.isFinite(expires) || expires <= now)
    return null;
  if (!(rights & R_VIEWER)) return null;
  return { ckey, rights, expires };
}
