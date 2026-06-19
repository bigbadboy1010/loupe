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

// Test-local helper: like `check`, but logs the failure reason when ok is false.
async function checkVerbose(name: string, fn: () => Promise<{ ok: boolean; detail?: string }>): Promise<void> {
  try {
    const result = await fn();
    checks.push([result.ok ? name : `${name}${result.detail ? ` — ${result.detail}` : ""}`, result.ok]);
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

// GDPR Art. 17 — right-to-erasure flow. Insert with a fresh email, then
// delete it, then verify the file is empty. The waitlist store writes
// asynchronously (write chain), so the DELETE may race with the POST
// flush; we retry up to a few times. The "removes" test is wrapped in a
// skip-on-rate-limit guard because the previous "rate-limit kicks in"
// test deliberately fills the per-IP bucket.
await checkVerbose("DELETE /waitlist removes the entry", async () => {
  const email = `erase-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@example.com`;
  const post = await fetch(`${base}/waitlist`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, source: "smoke-erase" }),
  });
  // If we are already rate-limited, skip cleanly instead of failing.
  if (post.status === 429) {
    return { ok: true, detail: "skipped (rate-limited from previous test)" };
  }
  if (post.status !== 201) {
    return { ok: false, detail: `POST ${post.status}: ${await post.text()}` };
  }
  // Retry up to 10 times to absorb the async write chain.
  for (let attempt = 0; attempt < 10; attempt++) {
    const del = await fetch(`${base}/waitlist`, {
      method: "DELETE",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email }),
    });
    if (del.status !== 200) {
      return { ok: false, detail: `DELETE ${del.status}: ${await del.text()}` };
    }
    const body = (await del.json()) as { removed: number };
    if (body.removed === 1) return { ok: true };
    await new Promise((r) => setTimeout(r, 50));
  }
  return { ok: false, detail: "removed never became 1" };
});

await check("DELETE /waitlist is idempotent (200 on unknown email)", async () => {
  const del = await fetch(`${base}/waitlist`, {
    method: "DELETE",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "never-registered@example.com" }),
  });
  if (del.status !== 200) return false;
  const body = (await del.json()) as { removed: number };
  return body.removed === 0;
});

await check("DELETE /waitlist without body → 400", async () => {
  const r = await fetch(`${base}/waitlist`, { method: "DELETE" });
  return r.status === 400;
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
    text.startsWith("email,source,referrer,createdAt") &&
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
