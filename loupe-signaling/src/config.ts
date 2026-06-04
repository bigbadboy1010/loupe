import { z } from "zod";

/**
 * Environment configuration, validated at startup.
 * Fails fast with a readable error if any required variable is missing or malformed.
 */
const envSchema = z.object({
  HOST: z.string().min(1).default("0.0.0.0"),
  PORT: z.coerce.number().int().min(1).max(65_535).default(8080),
  LOG_LEVEL: z
    .enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"])
    .default("info"),

  /** Shared secret used to derive time-limited TURN credentials (must match coturn `static-auth-secret`). */
  TURN_SECRET: z.string().min(32, "TURN_SECRET must be at least 32 characters"),
  /** Public hostname/IP of the coturn server advertised to clients. */
  TURN_HOST: z.string().min(1),
  /** TURN/STUN listening port. */
  TURN_PORT: z.coerce.number().int().min(1).max(65_535).default(3478),
  /** TTL in seconds for issued TURN credentials. */
  TURN_TTL_SECONDS: z.coerce.number().int().min(60).max(86_400).default(3600),

  /** Maximum peers per session. The protocol is strictly point-to-point. */
  MAX_PEERS_PER_SESSION: z.literal(2).default(2),
  /** Idle timeout after which an empty session is garbage-collected. */
  SESSION_IDLE_MS: z.coerce.number().int().min(1000).default(60_000),

  /** TTL for short pairing codes (manual-entry fallback). */
  PAIRING_TTL_SECONDS: z.coerce.number().int().min(30).max(3600).default(300),
  /** Length of the generated pairing code. */
  PAIRING_CODE_LENGTH: z.coerce.number().int().min(4).max(12).default(6),

  /** Maximum accepted WebSocket frame size. SDP fits comfortably below this. */
  WS_MAX_MESSAGE_BYTES: z.coerce.number().int().min(1024).max(262_144).default(65_536),
  /** Per-IP HTTP fixed-window limit. */
  HTTP_RATE_LIMIT_MAX: z.coerce.number().int().min(1).max(10_000).default(120),
  HTTP_RATE_LIMIT_WINDOW_MS: z.coerce.number().int().min(1000).max(3_600_000).default(60_000),
  /** Per-IP WebSocket connection/message fixed-window limits. */
  WS_CONNECTION_RATE_LIMIT_MAX: z.coerce.number().int().min(1).max(10_000).default(30),
  WS_MESSAGE_RATE_LIMIT_MAX: z.coerce.number().int().min(1).max(100_000).default(300),
  WS_RATE_LIMIT_WINDOW_MS: z.coerce.number().int().min(1000).max(3_600_000).default(60_000),
});

export type AppConfig = Readonly<z.infer<typeof envSchema>>;

export class ConfigError extends Error {
  public override readonly name = "ConfigError";
  public constructor(message: string) {
    super(message);
  }
}

/**
 * Parses and freezes configuration from `process.env`.
 * @throws {ConfigError} if validation fails.
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const result = envSchema.safeParse(env);
  if (!result.success) {
    const issues = result.error.issues
      .map((issue) => `  - ${issue.path.join(".") || "(root)"}: ${issue.message}`)
      .join("\n");
    throw new ConfigError(`Invalid environment configuration:\n${issues}`);
  }
  return Object.freeze(result.data);
}
