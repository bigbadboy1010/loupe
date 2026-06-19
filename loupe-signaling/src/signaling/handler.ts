import type { FastifyBaseLogger } from "fastify";
import { inboundMessageSchema, serialize } from "./messages.js";
import type { InboundMessage, OutboundMessage } from "./messages.js";
import { SessionError, SessionRegistry } from "./session.js";
import type { Peer, PeerSocket } from "./session.js";
import type { TurnCredentialProvider } from "../turn/credentials.js";
import type { FixedWindowRateLimiter } from "../security/rateLimiter.js";

/**
 * Per-connection signaling logic, decoupled from the Fastify/WebSocket
 * transport for testability. One instance is created per socket.
 */
export class ConnectionHandler {
  private joinedSessionId: string | null = null;
  private peerId: string | null = null;
  private role: Peer["role"] | null = null;

  public constructor(
    private readonly socket: PeerSocket,
    private readonly registry: SessionRegistry,
    private readonly turn: TurnCredentialProvider,
    private readonly logger: FastifyBaseLogger,
    private readonly messageLimiter: FixedWindowRateLimiter,
    private readonly rateLimitKey: string,
  ) {}

  /** Handles one raw inbound frame. Never throws; protocol errors are reported to the client. */
  public handleRaw(raw: string): void {
    const rate = this.messageLimiter.check(this.rateLimitKey);
    if (!rate.allowed) {
      this.send({ type: "error", code: "RATE_LIMITED", message: `Rate limited. Retry after ${rate.retryAfterSeconds}s` });
      return;
    }

    let parsedJson: unknown;
    try {
      parsedJson = JSON.parse(raw);
    } catch {
      this.send({ type: "error", code: "INVALID_MESSAGE", message: "Malformed JSON" });
      return;
    }

    const result = inboundMessageSchema.safeParse(parsedJson);
    if (!result.success) {
      this.send({ type: "error", code: "INVALID_MESSAGE", message: result.error.issues[0]?.message ?? "Invalid message" });
      return;
    }

    try {
      this.dispatch(result.data);
    } catch (error) {
      if (error instanceof SessionError) {
        this.send({ type: "error", code: error.code, message: error.message });
        return;
      }
      this.logger.error({ err: error }, "Unexpected error handling message");
      this.send({ type: "error", code: "INTERNAL", message: "Internal error" });
    }
  }

  /** Cleans up registry state when the socket closes. */
  public handleClose(): void {
    this.registry.dropSocket(this.socket.id);
    this.joinedSessionId = null;
    this.peerId = null;
    this.role = null;
  }

  private dispatch(message: InboundMessage): void {
    switch (message.type) {
      case "join": {
        const peer: Peer = { socket: this.socket, peerId: message.peerId, role: message.role };
        const { existingPeer } = this.registry.join(message.sessionId, peer);
        this.joinedSessionId = message.sessionId;
        this.peerId = message.peerId;
        this.role = message.role;

        this.send({ type: "joined", sessionId: message.sessionId, role: message.role });
        if (existingPeer) {
          this.send({ type: "peer-joined", sessionId: message.sessionId, peerId: existingPeer.peerId });
          existingPeer.socket.send(
            serialize({ type: "peer-joined", sessionId: message.sessionId, peerId: message.peerId }),
          );
        }
        return;
      }

      case "offer": {
        this.requireSession(message.sessionId);
        this.requireRole("host", "Only the host may create SDP offers");
        const delivered = this.registry.relay(message.sessionId, this.socket.id, message as OutboundMessage);
        if (!delivered) {
          this.send({ type: "error", code: "NO_PEER", message: "No peer connected yet" });
        }
        return;
      }

      case "answer": {
        this.requireSession(message.sessionId);
        this.requireRole("controller", "Only the controller may create SDP answers");
        const delivered = this.registry.relay(message.sessionId, this.socket.id, message as OutboundMessage);
        if (!delivered) {
          this.send({ type: "error", code: "NO_PEER", message: "No peer connected yet" });
        }
        return;
      }

      case "ice": {
        this.requireSession(message.sessionId);
        const delivered = this.registry.relay(message.sessionId, this.socket.id, message as OutboundMessage);
        if (!delivered) {
          this.send({ type: "error", code: "NO_PEER", message: "No peer connected yet" });
        }
        return;
      }

      case "turn-cred": {
        const peerId = this.requireJoinedPeerId();
        const { iceServers, ttlSeconds } = this.turn.issue(peerId);
        this.send({ type: "turn-cred", iceServers, ttlSeconds });
        return;
      }

      case "leave": {
        this.registry.leave(message.sessionId, this.socket.id);
        if (this.joinedSessionId === message.sessionId) {
          this.joinedSessionId = null;
          this.peerId = null;
          this.role = null;
        }
        return;
      }
    }
  }

  private requireSession(sessionId: string): void {
    if (this.joinedSessionId !== sessionId) {
      throw new SessionError(`Not joined to session ${sessionId}`, "NOT_IN_SESSION");
    }
  }

  private requireRole(expected: Peer["role"], message: string): void {
    if (this.role !== expected) {
      throw new SessionError(message, "ROLE_VIOLATION");
    }
  }

  private requireJoinedPeerId(): string {
    if (!this.joinedSessionId || !this.peerId) {
      throw new SessionError("TURN credentials require a joined session", "NOT_IN_SESSION");
    }
    return this.peerId;
  }

  private send(message: OutboundMessage): void {
    this.socket.send(serialize(message));
  }
}
