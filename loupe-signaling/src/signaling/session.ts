import type { OutboundMessage } from "./messages.js";
import { serialize } from "./messages.js";

/** Minimal transport abstraction so the registry is testable without a real socket. */
export interface PeerSocket {
  send(data: string): void;
  readonly id: string;
}

export interface Peer {
  readonly socket: PeerSocket;
  readonly peerId: string;
  readonly role: "host" | "controller";
}

export class SessionError extends Error {
  public override readonly name = "SessionError";
  public constructor(
    message: string,
    public readonly code: "SESSION_FULL" | "NOT_IN_SESSION",
  ) {
    super(message);
  }
}

interface Session {
  readonly id: string;
  readonly peers: Map<string, Peer>;
  idleTimer: NodeJS.Timeout | null;
}

/**
 * Tracks strictly point-to-point sessions (max two peers) and relays messages
 * between them. Holds no media and no durable state; empty sessions are
 * garbage-collected after `idleMs`.
 */
export class SessionRegistry {
  private readonly sessions = new Map<string, Session>();

  public constructor(
    private readonly maxPeers: 2,
    private readonly idleMs: number,
  ) {}

  /**
   * Adds a peer to a session, creating it on demand.
   * @throws {SessionError} with code SESSION_FULL if the session already holds maxPeers.
   * @returns the already-present peer (if any), so the caller can announce the join.
   */
  public join(sessionId: string, peer: Peer): { existingPeer: Peer | null } {
    const session = this.sessions.get(sessionId) ?? this.createSession(sessionId);

    if (session.peers.size >= this.maxPeers && !session.peers.has(peer.socket.id)) {
      throw new SessionError(`Session ${sessionId} is full`, "SESSION_FULL");
    }

    const existingPeer = this.firstOtherPeer(session, peer.socket.id);
    session.peers.set(peer.socket.id, peer);
    this.clearIdleTimer(session);
    return { existingPeer };
  }

  /**
   * Relays a message to the *other* peer in the session.
   * @throws {SessionError} NOT_IN_SESSION if the sender is not a member.
   * @returns true if a peer received the message, false if there was no counterpart.
   */
  public relay(sessionId: string, fromSocketId: string, message: OutboundMessage): boolean {
    const session = this.sessions.get(sessionId);
    if (!session || !session.peers.has(fromSocketId)) {
      throw new SessionError(`Socket ${fromSocketId} not in session ${sessionId}`, "NOT_IN_SESSION");
    }
    const target = this.firstOtherPeer(session, fromSocketId);
    if (!target) return false;
    target.socket.send(serialize(message));
    return true;
  }

  /** Removes a peer from a session and notifies the counterpart. Idempotent. */
  public leave(sessionId: string, socketId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    session.peers.delete(socketId);

    const remaining = this.firstOtherPeer(session, socketId);
    if (remaining) {
      remaining.socket.send(serialize({ type: "peer-left", sessionId }));
    }
    if (session.peers.size === 0) {
      this.scheduleIdleEviction(session);
    }
  }

  /** Removes a socket from every session it belongs to (e.g. on disconnect). */
  public dropSocket(socketId: string): void {
    for (const session of this.sessions.values()) {
      if (session.peers.has(socketId)) {
        this.leave(session.id, socketId);
      }
    }
  }

  public get activeSessionCount(): number {
    return this.sessions.size;
  }

  private createSession(sessionId: string): Session {
    const session: Session = { id: sessionId, peers: new Map(), idleTimer: null };
    this.sessions.set(sessionId, session);
    return session;
  }

  private firstOtherPeer(session: Session, exceptSocketId: string): Peer | null {
    for (const [socketId, peer] of session.peers) {
      if (socketId !== exceptSocketId) return peer;
    }
    return null;
  }

  private clearIdleTimer(session: Session): void {
    if (session.idleTimer) {
      clearTimeout(session.idleTimer);
      session.idleTimer = null;
    }
  }

  private scheduleIdleEviction(session: Session): void {
    this.clearIdleTimer(session);
    session.idleTimer = setTimeout(() => {
      if (session.peers.size === 0) {
        this.sessions.delete(session.id);
      }
    }, this.idleMs);
    // Do not keep the event loop alive solely for idle eviction.
    session.idleTimer.unref?.();
  }
}
