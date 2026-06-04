import { createHmac } from "node:crypto";
import type { AppConfig } from "../config.js";
import type { IceServerDto } from "../signaling/messages.js";

/**
 * Produces time-limited TURN credentials compatible with coturn's
 * `use-auth-secret` / `static-auth-secret` REST API mechanism.
 *
 * username = "<expiryUnixSeconds>:<peerId>"
 * credential = base64(HMAC-SHA1(username, sharedSecret))
 *
 * coturn validates these without any per-user database; the only shared state
 * is the secret. Credentials expire automatically at `expiry`.
 */
export interface TurnCredentialProvider {
  issue(peerId: string): { iceServers: readonly IceServerDto[]; ttlSeconds: number };
}

export function createTurnCredentialProvider(config: AppConfig): TurnCredentialProvider {
  return {
    issue(peerId: string) {
      const expiry = Math.floor(Date.now() / 1000) + config.TURN_TTL_SECONDS;
      const username = `${expiry}:${peerId}`;
      const credential = createHmac("sha1", config.TURN_SECRET)
        .update(username)
        .digest("base64");

      const base = `${config.TURN_HOST}:${config.TURN_PORT}`;
      const iceServers: readonly IceServerDto[] = [
        { urls: `stun:${base}` },
        { urls: `turn:${base}?transport=udp`, username, credential },
        { urls: `turn:${base}?transport=tcp`, username, credential },
      ];

      return { iceServers, ttlSeconds: config.TURN_TTL_SECONDS };
    },
  };
}
