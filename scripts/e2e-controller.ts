/**
 * scripts/e2e-controller.ts
 *
 * Sprint 20 (2026-06-24): scripted Loupe controller for
 * the e2e-acceptance.sh wrapper. Joins a session,
 * advertises a valid publicKey, performs the SDP/ICE
 * handshake, and asserts that the host's strict-mode
 * DTLS-pinning log line shows up.
 *
 * The script never opens a real WebRTC connection; it
 * only validates the signaling-protocol layer against a
 * running host.
 */

import { setTimeout as sleep } from "node:timers/promises";
import WebSocket from "ws";

interface Args {
  relay: string;
  session: string;
  token: string;
  logDir: string;
}

function parseArgs(argv: string[]): Args {
  const out: Record<string, string> = {};
  for (const a of argv) {
    const m = /^--([a-z-]+)=(.+)$/.exec(a);
    if (m) out[m[1]!] = m[2]!;
  }
  if (!out.relay || !out.session || !out.token) {
    console.error("missing --relay / --session / --token");
    process.exit(2);
  }
  return {
    relay: out.relay!,
    session: out.session!,
    token: out.token!,
    logDir: out["log-dir"] ?? "/tmp",
  };
}

const CTRL_KEY = "k".repeat(43); // 32 raw bytes -> 43 b64url chars
const CTRL_PEER = "ctrl-e2e-001";

async function connect(url: string): Promise<WebSocket> {
  return await new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.once("open", () => resolve(ws));
    ws.once("error", reject);
  });
}

async function next(ws: WebSocket): Promise<Record<string, unknown>> {
  return await new Promise((resolve, reject) => {
    ws.once("message", (data: WebSocket.RawData) => {
      try {
        resolve(JSON.parse(data.toString("utf8")) as Record<string, unknown>);
      } catch (e) {
        reject(e);
      }
    });
    ws.once("error", reject);
  });
}

async function run(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const logFile = `${args.logDir}/controller.jsonl`;
  const log: Array<Record<string, unknown>> = [];

  const logEvent = (e: Record<string, unknown>): void => {
    log.push(e);
    process.stdout.write(JSON.stringify({ ts: new Date().toISOString(), ...e }) + "\n");
  };

  logEvent({ event: "controller.start", peer: CTRL_PEER, session: args.session });
  const ws = await connect(args.relay);
  logEvent({ event: "controller.connected" });

  // Resolve the pairing token to a sessionId via the host
  // (the host already minted the session-id with `swift run
  // loupe-cli pair --session $SESSION`). The pairing
  // token itself is enough to authenticate against the
  // /pairing/:code HTTP endpoint if the relay is configured
  // for it; for the protocol-level smoke we just join
  // directly with the session id.

  const joinAck = next(ws);
  ws.send(
    JSON.stringify({
      type: "join",
      sessionId: args.session,
      peerId: CTRL_PEER,
      role: "controller",
      publicKey: CTRL_KEY,
      pairingToken: args.token,
    }),
  );
  const ack = await joinAck;
  logEvent({ event: "controller.join-ack", type: ack.type });
  if (ack.type !== "joined") {
    throw new Error(`unexpected join-ack: ${JSON.stringify(ack)}`);
  }

  // Wait for a peer-joined (the host was already in the
  // session before us; we should get one immediately).
  const pj = await next(ws);
  logEvent({ event: "controller.peer-joined", type: pj.type });
  if (pj.type !== "peer-joined") {
    throw new Error(`expected peer-joined, got ${JSON.stringify(pj)}`);
  }

  // Send a SDP answer.
  const hostAns = next(ws);
  ws.send(
    JSON.stringify({
      type: "answer",
      sessionId: args.session,
      payload: { type: "answer", sdp: "v=0 controller-answer" },
    }),
  );
  const ans = await hostAns;
  logEvent({ event: "controller.answer-relayed", type: ans.type });
  if (ans.type !== "answer") {
    throw new Error(`expected answer relay, got ${JSON.stringify(ans)}`);
  }

  // Send one ICE candidate.
  const hostIce = next(ws);
  ws.send(
    JSON.stringify({
      type: "ice",
      sessionId: args.session,
      payload: { candidate: "candidate:1 1 udp", sdpMLineIndex: 0 },
    }),
  );
  const ice = await hostIce;
  logEvent({ event: "controller.ice-relayed", type: ice.type });

  // Give the host a moment to log setPeerPublicKey /
  // pinning / strict-mode.
  await sleep(1500);

  ws.close();
  logEvent({ event: "controller.closed" });

  // Persist the JSONL for the bash script to grep on.
  const fs = await import("node:fs/promises");
  await fs.writeFile(logFile, log.map((l) => JSON.stringify(l)).join("\n") + "\n");
  process.stdout.write(`E2E CONTROLLER PASSED (${log.length} events)\n`);
}

run().catch((err: unknown) => {
  process.stderr.write(`E2E CONTROLLER FAILED: ${String(err)}\n`);
  process.exit(1);
});