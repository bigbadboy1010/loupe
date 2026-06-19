import { buildServer } from "../src/server.js";
import { resolveSiteDir } from "../src/site/router.js";
import path from "node:path";
import os from "node:os";
import fs from "node:fs/promises";
import type { AppConfig } from "../src/config.js";
import type { AddressInfo } from "node:net";

const tmpWaitlist = path.join(os.tmpdir(), `loupe-waitlist-${Date.now()}.jsonl`);
await fs.mkdir(path.dirname(tmpWaitlist), { recursive: true });

const config: AppConfig = Object.freeze({
  HOST: "127.0.0.1",
  PORT: 0,
  LOG_LEVEL: "silent",
  TURN_SECRET: "smoke-test-secret-0123456789",
  TURN_HOST: "turn.test.local",
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
  WAITLIST_ADMIN_TOKEN: "smoke-admin-token-please-do-not-use-in-prod",
});

const app = await buildServer(config);
await app.listen({ host: "127.0.0.1", port: 0 });
const { port } = app.server.address() as AddressInfo;
const base = `http://127.0.0.1:${port}`;

const checks: Array<[string, boolean]> = [];

async function check(name: string, fn: () => Promise<boolean>): Promise<void> {
  try {
    const ok = await fn();
    checks.push([name, ok]);
  } catch (err: unknown) {
    checks.push([name + ` (threw: ${String(err)})`, false]);
  }
}

await check("GET / → 200 HTML", async () => {
  const r = await fetch(`${base}/`);
  const ct = r.headers.get("content-type") || "";
  const body = await r.text();
  return r.status === 200 && ct.includes("text/html") && body.includes("Loupe");
});

await check("GET /style.css → CSS", async () => {
  const r = await fetch(`${base}/style.css`);
  const ct = r.headers.get("content-type") || "";
  const body = await r.text();
  return r.status === 200 && ct.includes("text/css") && body.includes("--bg");
});

await check("GET /app.js → JS", async () => {
  const r = await fetch(`${base}/app.js`);
  const ct = r.headers.get("content-type") || "";
  const body = await r.text();
  return r.status === 200 && ct.includes("javascript") && body.includes("waitlist");
});

await check("GET /privacy.html", async () => {
  const r = await fetch(`${base}/privacy.html`);
  const body = await r.text();
  return r.status === 200 && body.includes("Privacy policy");
});

await check("GET /imprint.html", async () => {
  const r = await fetch(`${base}/imprint.html`);
  const body = await r.text();
  return r.status === 200 && body.includes("Imprint");
});

await check("GET /healthz still 200", async () => {
  const r = await fetch(`${base}/healthz`);
  const body = (await r.json()) as { status?: string };
  return r.status === 200 && body.status === "ok";
});

await check("POST /waitlist valid → 201", async () => {
  const r = await fetch(`${base}/waitlist`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "test@example.com", source: "smoke", referrer: "/smoke" }),
  });
  const body = (await r.json()) as { status?: string };
  return r.status === 201 && body.status === "ok";
});

await check("POST /waitlist duplicate → 409", async () => {
  const r = await fetch(`${base}/waitlist`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "test@example.com" }),
  });
  return r.status === 409;
});

await check("POST /waitlist bad email → 400", async () => {
  const r = await fetch(`${base}/waitlist`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "not-an-email" }),
  });
  return r.status === 400;
});

await check("POST /waitlist rate-limit kicks in", async () => {
  let limited = false;
  for (let i = 0; i < 30; i++) {
    const r = await fetch(`${base}/waitlist`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "spam@example.com" }),
    });
    if (r.status === 429) { limited = true; break; }
  }
  return limited;
});

await check("SPA route /some/spa/route → index", async () => {
  const r = await fetch(`${base}/some/spa/route`);
  const body = await r.text();
  return r.status === 200 && body.includes("Loupe");
});

await check("Missing asset /missing.css → 404", async () => {
  const r = await fetch(`${base}/missing.css`);
  return r.status === 404;
});

await check("GET /ws → 404 (correct, requires upgrade)", async () => {
  const r = await fetch(`${base}/ws`);
  return r.status === 404;
});

await check("GET /admin/waitlist.json without token → 401", async () => {
  const r = await fetch(`${base}/admin/waitlist.json`);
  return r.status === 401;
});

await check("GET /admin/waitlist.json with wrong token → 401", async () => {
  const r = await fetch(`${base}/admin/waitlist.json`, {
    headers: { authorization: "Bearer wrong-token" },
  });
  return r.status === 401;
});

await check("GET /admin/waitlist.json with valid token → 200 + count", async () => {
  const r = await fetch(`${base}/admin/waitlist.json`, {
    headers: { authorization: `Bearer ${config.WAITLIST_ADMIN_TOKEN}` },
  });
  const body = (await r.json()) as { count?: number; entries?: Array<{ email: string }> };
  const ok =
    r.status === 200 &&
    typeof body.count === "number" &&
    body.count >= 2 &&
    Array.isArray(body.entries) &&
    body.entries.some((e) => e.email === "test@example.com");
  return ok;
});

await check("GET /admin/waitlist.csv with valid token → 200 + CSV header", async () => {
  const r = await fetch(`${base}/admin/waitlist.csv`, {
    headers: { authorization: `Bearer ${config.WAITLIST_ADMIN_TOKEN}` },
  });
  const text = await r.text();
  const ct = r.headers.get("content-type") || "";
  const ok =
    r.status === 200 &&
    ct.includes("text/csv") &&
    text.startsWith("email,source,referrer,createdAt,ip,userAgent") &&
    text.includes("test@example.com");
  return ok;
});

await app.close();
await fs.unlink(tmpWaitlist).catch(() => {});

let allOk = true;
for (const [name, ok] of checks) {
  process.stdout.write(`${ok ? "✅" : "❌"} ${name}\n`);
  if (!ok) allOk = false;
}
process.stdout.write(allOk ? "SITE SMOKE PASSED\n" : "SITE SMOKE FAILED\n");
process.exit(allOk ? 0 : 1);
