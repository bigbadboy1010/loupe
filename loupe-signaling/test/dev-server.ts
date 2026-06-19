import { buildServer } from "../src/server.js";
import { resolveSiteDir } from "../src/site/router.js";
import path from "node:path";
import os from "node:os";
import fs from "node:fs/promises";

const tmpWaitlist = path.join(os.tmpdir(), `loupe-waitlist-dev-${Date.now()}.jsonl`);
await fs.mkdir(path.dirname(tmpWaitlist), { recursive: true });

const app = await buildServer({
  HOST: "127.0.0.1",
  PORT: Number(process.env.PORT) || 4173,
  LOG_LEVEL: "info",
  TURN_SECRET: "dev-secret-12345678901234567890123456789012",
  TURN_HOST: "loupe.ddns.net",
  TURN_PORT: 3478,
  TURN_TTL_SECONDS: 3600,
  MAX_PEERS_PER_SESSION: 2,
  SESSION_IDLE_MS: 60_000,
  PAIRING_TTL_SECONDS: 300,
  PAIRING_CODE_LENGTH: 6,
  WS_MAX_MESSAGE_BYTES: 65_536,
  HTTP_RATE_LIMIT_MAX: 120,
  HTTP_RATE_LIMIT_WINDOW_MS: 60_000,
  WS_CONNECTION_RATE_LIMIT_MAX: 30,
  WS_MESSAGE_RATE_LIMIT_MAX: 300,
  WS_RATE_LIMIT_WINDOW_MS: 60_000,
  SERVE_SITE: true,
  SITE_DIR: resolveSiteDir(),
  WAITLIST_FILE: tmpWaitlist,
});
await app.listen({ host: "127.0.0.1", port: 4173 });
process.stdout.write("DEV SERVER: http://127.0.0.1:4173\n");
