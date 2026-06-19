import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import WebSocket from "ws";
import { buildServer } from "../src/server.js";
import type { AppConfig } from "../src/config.js";

/**
 * End-to-end smoke test: boots an ephemeral server, connects two WebSocket
 * peers, and verifies join announcement, SDP/ICE relay, and TURN credential
 * issuance. Run with `npm run test:smoke`.
 */

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
  SERVE_SITE: false,
});

function once(ws: WebSocket): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const onMessage = (data: WebSocket.RawData): void => {
      ws.off("error", onError);
      resolve(JSON.parse(data.toString("utf8")) as Record<string, unknown>);
    };
    const onError = (err: Error): void => reject(err);
    ws.once("message", onMessage);
    ws.once("error", onError);
  });
}

function connect(url: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.once("open", () => resolve(ws));
    ws.once("error", reject);
  });
}

async function run(): Promise<void> {
  const app = await buildServer(config);
  await app.listen({ host: config.HOST, port: 0 });
  const { port } = app.server.address() as AddressInfo;
  const url = `ws://127.0.0.1:${port}/ws`;
  const sessionId = "smoke-session-1";

  const unauth = await connect(url);
  unauth.send(JSON.stringify({ type: "turn-cred" }));
  const unauthError = await once(unauth);
  assert.equal(unauthError.type, "error");
  assert.equal(unauthError.code, "NOT_IN_SESSION");
  unauth.close();

  const host = await connect(url);
  const controller = await connect(url);

  // Host joins first.
  host.send(JSON.stringify({ type: "join", sessionId, peerId: "host-1", role: "host" }));
  const hostJoined = await once(host);
  assert.equal(hostJoined.type, "joined", "host should receive joined");

  // Controller joins; both sides should learn about each other.
  const hostPeerJoined = once(host);
  controller.send(JSON.stringify({ type: "join", sessionId, peerId: "ctrl-1", role: "controller" }));
  const ctrlJoined = await once(controller);
  assert.equal(ctrlJoined.type, "joined", "controller should receive joined");

  const hpj = await hostPeerJoined;
  assert.equal(hpj.type, "peer-joined", "host should be notified of controller");
  assert.equal(hpj.peerId, "ctrl-1");

  // Host is the only SDP offerer in Loupe's deterministic MVP negotiation model.
  const ctrlOffer = once(controller);
  host.send(
    JSON.stringify({ type: "offer", sessionId, payload: { type: "offer", sdp: "v=0 host-offer" } }),
  );
  const relayedOffer = await ctrlOffer;
  assert.equal(relayedOffer.type, "offer");
  assert.deepEqual(relayedOffer.payload, { type: "offer", sdp: "v=0 host-offer" });

  // Controller is the only SDP answerer.
  const hostAnswer = once(host);
  controller.send(
    JSON.stringify({ type: "answer", sessionId, payload: { type: "answer", sdp: "v=0 controller-answer" } }),
  );
  const relayedAnswer = await hostAnswer;
  assert.equal(relayedAnswer.type, "answer");
  assert.deepEqual(relayedAnswer.payload, { type: "answer", sdp: "v=0 controller-answer" });

  // A controller-originated offer must be rejected instead of being relayed to the host.
  controller.send(
    JSON.stringify({ type: "offer", sessionId, payload: { type: "offer", sdp: "v=0 rogue-offer" } }),
  );
  const roleError = await once(controller);
  assert.equal(roleError.type, "error");
  assert.equal(roleError.code, "ROLE_VIOLATION");

  // ICE relay host -> controller.
  const ctrlIce = once(controller);
  host.send(
    JSON.stringify({ type: "ice", sessionId, payload: { candidate: "candidate:1 1 udp", sdpMLineIndex: 0 } }),
  );
  const relayedIce = await ctrlIce;
  assert.equal(relayedIce.type, "ice");

  // TURN credentials.
  host.send(JSON.stringify({ type: "turn-cred" }));
  const cred = await once(host);
  assert.equal(cred.type, "turn-cred");
  const iceServers = cred.iceServers as Array<{ urls: string; username?: string; credential?: string }>;
  assert.ok(Array.isArray(iceServers) && iceServers.length === 3, "STUN plus two TURN servers expected");
  assert.equal(iceServers[0]!.urls, "stun:turn.test.local:3478");
  assert.match(iceServers[1]!.urls, /^turn:turn\.test\.local:3478/);
  assert.match(iceServers[1]!.username ?? "", /^\d+:host-1$/);
  assert.equal(typeof iceServers[1]!.credential, "string");

  // Invalid message must not crash the server and must return an error.
  host.send("not json");
  const err = await once(host);
  assert.equal(err.type, "error");
  assert.equal(err.code, "INVALID_MESSAGE");

  // Pairing code mint + resolve over HTTP.
  const base = `http://127.0.0.1:${port}`;
  const mintResponse = await fetch(`${base}/pairing`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ sessionId: "paired-session-1" }),
  });
  assert.equal(mintResponse.status, 200, "mint should succeed");
  const minted = (await mintResponse.json()) as { sessionId: string; code: string; expiresInSeconds: number };
  assert.equal(minted.sessionId, "paired-session-1");
  assert.match(minted.code, /^[A-Z0-9]{6}$/, "code should be 6 unambiguous chars");

  const resolveResponse = await fetch(`${base}/pairing/${minted.code}`);
  assert.equal(resolveResponse.status, 200);
  const resolved = (await resolveResponse.json()) as { sessionId: string };
  assert.equal(resolved.sessionId, "paired-session-1");

  // Codes are one-time-use and are consumed on successful resolve.
  const secondResolve = await fetch(`${base}/pairing/${minted.code}`);
  assert.equal(secondResolve.status, 404);

  const lowerMintResponse = await fetch(`${base}/pairing`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ sessionId: "paired-session-2" }),
  });
  const lowerMinted = (await lowerMintResponse.json()) as { sessionId: string; code: string; expiresInSeconds: number };
  const lowerResolve = await fetch(`${base}/pairing/${lowerMinted.code.toLowerCase()}`);
  assert.equal(lowerResolve.status, 200);

  const missingResolve = await fetch(`${base}/pairing/ZZZZZZ`);
  assert.equal(missingResolve.status, 404, "unknown code should 404");

  host.close();
  controller.close();
  await app.close();
  process.stdout.write("SMOKE TEST PASSED\n");
}

run().catch((error: unknown) => {
  process.stderr.write(`SMOKE TEST FAILED: ${String(error)}\n`);
  process.exit(1);
});
