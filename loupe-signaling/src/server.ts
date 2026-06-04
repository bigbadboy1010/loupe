import { randomUUID } from "node:crypto";
import Fastify from "fastify";
import type { FastifyInstance } from "fastify";
import websocket from "@fastify/websocket";
import { z } from "zod";
import { ConfigError, loadConfig } from "./config.js";
import type { AppConfig } from "./config.js";
import { SessionRegistry } from "./signaling/session.js";
import type { PeerSocket } from "./signaling/session.js";
import { ConnectionHandler } from "./signaling/handler.js";
import { createTurnCredentialProvider } from "./turn/credentials.js";
import { PairingCodeStore } from "./pairing/codeStore.js";
import { FixedWindowRateLimiter } from "./security/rateLimiter.js";

/**
 * Builds the Fastify instance with the signaling WebSocket route and a health
 * endpoint. Exported so tests can boot an ephemeral server.
 */
export async function buildServer(config: AppConfig): Promise<FastifyInstance> {
  const app = Fastify({
    logger: { level: config.LOG_LEVEL },
    bodyLimit: config.WS_MAX_MESSAGE_BYTES,
    trustProxy: true,
  });
  const registry = new SessionRegistry(config.MAX_PEERS_PER_SESSION, config.SESSION_IDLE_MS);
  const turn = createTurnCredentialProvider(config);
  const pairing = new PairingCodeStore(config.PAIRING_TTL_SECONDS, config.PAIRING_CODE_LENGTH);
  const httpLimiter = new FixedWindowRateLimiter(config.HTTP_RATE_LIMIT_MAX, config.HTTP_RATE_LIMIT_WINDOW_MS);
  const wsConnectionLimiter = new FixedWindowRateLimiter(
    config.WS_CONNECTION_RATE_LIMIT_MAX,
    config.WS_RATE_LIMIT_WINDOW_MS,
  );
  const wsMessageLimiter = new FixedWindowRateLimiter(config.WS_MESSAGE_RATE_LIMIT_MAX, config.WS_RATE_LIMIT_WINDOW_MS);

  await app.register(websocket, {
    options: {
      maxPayload: config.WS_MAX_MESSAGE_BYTES,
    },
  });

  app.addHook("onRequest", async (request, reply) => {
    if (request.url === "/healthz") return;
    const decision = httpLimiter.check(`http:${request.ip}`);
    reply.header("x-ratelimit-remaining", String(decision.remaining));
    if (!decision.allowed) {
      reply.header("retry-after", String(decision.retryAfterSeconds));
      await reply.code(429).send({ error: "RATE_LIMITED", retryAfterSeconds: decision.retryAfterSeconds });
    }
  });

  app.get("/healthz", async () => ({
    status: "ok",
    activeSessions: registry.activeSessionCount,
    pairingCodes: pairing.size,
    rateLimitBuckets: {
      http: httpLimiter.size,
      wsConnections: wsConnectionLimiter.size,
      wsMessages: wsMessageLimiter.size,
    },
  }));

  // Mint a short pairing code (manual-entry fallback to the QR flow, ADR-003).
  const mintBody = z.object({ sessionId: z.string().min(6).max(128).optional() });
  app.post("/pairing", async (request, reply) => {
    const parsed = mintBody.safeParse(request.body ?? {});
    if (!parsed.success) {
      return reply.code(400).send({ error: "INVALID_BODY", message: parsed.error.issues[0]?.message });
    }
    return pairing.mint(parsed.data.sessionId);
  });

  // Resolve and consume a pairing code to its session ID. Codes are one-time-use.
  const codeParams = z.object({ code: z.string().min(4).max(12) });
  app.get("/pairing/:code", async (request, reply) => {
    const parsed = codeParams.safeParse(request.params);
    if (!parsed.success) {
      return reply.code(400).send({ error: "INVALID_CODE" });
    }
    const sessionId = pairing.consume(parsed.data.code);
    if (!sessionId) {
      return reply.code(404).send({ error: "NOT_FOUND" });
    }
    return { sessionId };
  });

  app.register(async (instance) => {
    instance.get("/ws", { websocket: true }, (connection, request) => {
      const socketId = randomUUID();
      const rateKey = `ws:${request.ip}`;
      const decision = wsConnectionLimiter.check(rateKey);
      if (!decision.allowed) {
        connection.close(1008, `Rate limited. Retry after ${decision.retryAfterSeconds}s`);
        return;
      }

      const socket: PeerSocket = {
        id: socketId,
        send: (data) => connection.send(data),
      };
      const handler = new ConnectionHandler(socket, registry, turn, app.log, wsMessageLimiter, rateKey);

      connection.on("message", (raw: Buffer) => handler.handleRaw(raw.toString("utf8")));
      connection.on("close", () => handler.handleClose());
      connection.on("error", (err) => {
        app.log.warn({ err, socketId }, "WebSocket error");
        handler.handleClose();
      });
    });
  });

  return app;
}

async function main(): Promise<void> {
  let config: AppConfig;
  try {
    config = loadConfig();
  } catch (error) {
    if (error instanceof ConfigError) {
      process.stderr.write(`${error.message}\n`);
      process.exit(1);
    }
    throw error;
  }

  const app = await buildServer(config);

  const shutdown = async (signal: string): Promise<void> => {
    app.log.info({ signal }, "Shutting down");
    await app.close();
    process.exit(0);
  };
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
  process.on("SIGINT", () => void shutdown("SIGINT"));

  try {
    await app.listen({ host: config.HOST, port: config.PORT });
  } catch (error) {
    app.log.error({ err: error }, "Failed to start server");
    process.exit(1);
  }
}

// Boot only when run directly, not when imported by tests.
const isMain = process.argv[1] !== undefined && import.meta.url === `file://${process.argv[1]}`;
if (isMain) {
  void main();
}
