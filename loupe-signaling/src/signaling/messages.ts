import { z } from "zod";

/**
 * Wire protocol between peers and the signaling server.
 * All inbound and outbound messages are validated against these schemas;
 * anything that does not parse is rejected without mutating server state.
 */

const sessionId = z
  .string()
  .min(6)
  .max(128)
  .regex(/^[A-Za-z0-9_-]+$/, "sessionId must be URL-safe");

/** SDP payload (offer/answer). The server treats the SDP body as opaque. */
const sdpSchema = z.object({
  type: z.enum(["offer", "answer"]),
  sdp: z.string().min(1).max(256_000),
});

/** ICE candidate. Opaque to the server, relayed verbatim to the peer. */
const iceCandidateSchema = z.object({
  candidate: z.string().max(4096),
  sdpMid: z.string().max(128).nullable().optional(),
  sdpMLineIndex: z.number().int().nonnegative().nullable().optional(),
});

// ---- Inbound (client -> server) ------------------------------------------

const joinMessage = z.object({
  type: z.literal("join"),
  sessionId,
  /** Stable identifier of the device, used for trust pinning on the peer side. */
  peerId: z.string().min(1).max(128),
  role: z.enum(["host", "controller"]),
});

const offerMessage = z.object({
  type: z.literal("offer"),
  sessionId,
  payload: sdpSchema,
});

const answerMessage = z.object({
  type: z.literal("answer"),
  sessionId,
  payload: sdpSchema,
});

const iceMessage = z.object({
  type: z.literal("ice"),
  sessionId,
  payload: iceCandidateSchema,
});

const turnCredMessage = z.object({
  type: z.literal("turn-cred"),
});

const leaveMessage = z.object({
  type: z.literal("leave"),
  sessionId,
});

export const inboundMessageSchema = z.discriminatedUnion("type", [
  joinMessage,
  offerMessage,
  answerMessage,
  iceMessage,
  turnCredMessage,
  leaveMessage,
]);

export type InboundMessage = z.infer<typeof inboundMessageSchema>;
export type JoinMessage = z.infer<typeof joinMessage>;

// ---- Outbound (server -> client) -----------------------------------------

export interface IceServerDto {
  readonly urls: string;
  readonly username?: string;
  readonly credential?: string;
}

export type OutboundMessage =
  | { readonly type: "joined"; readonly sessionId: string; readonly role: "host" | "controller" }
  | { readonly type: "peer-joined"; readonly sessionId: string; readonly peerId: string }
  | { readonly type: "peer-left"; readonly sessionId: string }
  | { readonly type: "offer"; readonly sessionId: string; readonly payload: z.infer<typeof sdpSchema> }
  | { readonly type: "answer"; readonly sessionId: string; readonly payload: z.infer<typeof sdpSchema> }
  | { readonly type: "ice"; readonly sessionId: string; readonly payload: z.infer<typeof iceCandidateSchema> }
  | { readonly type: "turn-cred"; readonly iceServers: readonly IceServerDto[]; readonly ttlSeconds: number }
  | { readonly type: "error"; readonly code: SignalingErrorCode; readonly message: string };

export type SignalingErrorCode =
  | "INVALID_MESSAGE"
  | "SESSION_FULL"
  | "NOT_IN_SESSION"
  | "NO_PEER"
  | "ROLE_VIOLATION"
  | "RATE_LIMITED"
  | "INTERNAL";

export function serialize(message: OutboundMessage): string {
  return JSON.stringify(message);
}
