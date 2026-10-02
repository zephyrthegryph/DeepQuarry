// Mints a viewer link from the host, without the game: `bun run mint <ckey> [hours]`.
// The link carries full viewer rights (+ADMIN +SERVER +DEBUG).

import { mintToken, R_ADMIN, R_DEBUG, R_SERVER } from './auth';
import { config } from './config';

const [ckey = 'host', hours = '12'] = process.argv.slice(2);
if (!config.secret) {
  console.error('VIEWER_SECRET is not set.');
  process.exit(1);
}
const token = mintToken(
  ckey,
  R_ADMIN | R_SERVER | R_DEBUG,
  Date.now() / 1000 + Number(hours) * 3600,
  config.secret,
);
console.log(
  `http://${config.host}:${config.port}/auth?token=${encodeURIComponent(token)}`,
);
