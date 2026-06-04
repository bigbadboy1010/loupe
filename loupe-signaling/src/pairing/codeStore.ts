import { randomBytes, randomUUID } from "node:crypto";

/**
 * Maps short, human-enterable pairing codes to session IDs with a TTL.
 * The QR-code flow carries the full session ID directly; this store backs the
 * manual-entry fallback (see ADR-003). It holds no keys and no media — only the
 * code↔session mapping for a short window.
 */

/** Unambiguous alphabet: no 0/O/1/I to avoid manual-entry confusion. */
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export interface PairingEntry {
  readonly sessionId: string;
  readonly expiresAt: number;
}

export interface MintResult {
  readonly sessionId: string;
  readonly code: string;
  readonly expiresInSeconds: number;
}

export class PairingCodeStore {
  private readonly byCode = new Map<string, PairingEntry>();

  public constructor(
    private readonly ttlSeconds: number,
    private readonly codeLength: number,
    private readonly now: () => number = Date.now,
  ) {}

  /**
   * Mints a pairing code for the given session (or a fresh session ID if none
   * is supplied). Retries on the rare collision before giving up.
   */
  public mint(sessionId?: string): MintResult {
    this.prune();
    const resolvedSession = sessionId ?? `s_${randomUUID()}`;
    const expiresAt = this.now() + this.ttlSeconds * 1000;

    let code = "";
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const candidate = this.generateCode();
      if (!this.byCode.has(candidate)) {
        code = candidate;
        break;
      }
    }
    if (code === "") {
      throw new PairingError("Failed to allocate a unique pairing code");
    }

    this.byCode.set(code, { sessionId: resolvedSession, expiresAt });
    return { sessionId: resolvedSession, code, expiresInSeconds: this.ttlSeconds };
  }

  /** Resolves and consumes a code, or returns null if unknown/expired. */
  public consume(code: string): string | null {
    this.prune();
    const normalized = code.toUpperCase();
    const entry = this.byCode.get(normalized);
    if (!entry) return null;
    this.byCode.delete(normalized);
    if (entry.expiresAt <= this.now()) {
      return null;
    }
    return entry.sessionId;
  }

  public get size(): number {
    this.prune();
    return this.byCode.size;
  }

  private generateCode(): string {
    const bytes = randomBytes(this.codeLength);
    let out = "";
    for (let i = 0; i < this.codeLength; i += 1) {
      const byte = bytes[i] as number;
      out += ALPHABET[byte % ALPHABET.length];
    }
    return out;
  }

  private prune(): void {
    const t = this.now();
    for (const [code, entry] of this.byCode) {
      if (entry.expiresAt <= t) this.byCode.delete(code);
    }
  }
}

export class PairingError extends Error {
  public override readonly name = "PairingError";
  public constructor(message: string) {
    super(message);
  }
}
