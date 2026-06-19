import path from "node:path";
import { promises as fs } from "node:fs";
import { fileURLToPath } from "node:url";
import { timingSafeEqual } from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import { WaitlistStore, normaliseEmail, type WaitlistEntry } from "../waitlist/store.js";
import type { Mailer } from "../waitlist/mailer.js";
import { FixedWindowRateLimiter } from "../security/rateLimiter.js";

/**
 * Registers the public marketing site (static files) and the waitlist endpoint on a
 * Fastify instance. Guarded behind a single `register` call so the production signaling
 * container can opt in (via env flag) without touching protocol code.
 */
export interface SiteOptions {
  readonly siteDir: string;
  readonly waitlistFile: string;
  readonly waitlistMailer: Mailer;
  readonly trustProxy: boolean;
  readonly adminToken?: string;
}

const STATIC_FILE_BY_ROUTE: ReadonlyArray<readonly [string, string, string]> = [
  ["/", "index.html", "text/html; charset=utf-8"],
  ["/index.html", "index.html", "text/html; charset=utf-8"],
  ["/style.css", "style.css", "text/css; charset=utf-8"],
  ["/app.js", "app.js", "application/javascript; charset=utf-8"],
  ["/favicon.svg", "favicon.svg", "image/svg+xml"],
  ["/privacy.html", "privacy.html", "text/html; charset=utf-8"],
  ["/imprint.html", "imprint.html", "text/html; charset=utf-8"],
  ["/docs/pricing.html", "docs/pricing.html", "text/html; charset=utf-8"],
  ["/docs/self-host.html", "docs/self-host.html", "text/html; charset=utf-8"],
];

export async function registerSite(app: FastifyInstance, opts: SiteOptions): Promise<void> {
  const waitlist = new WaitlistStore(opts.waitlistFile);
  const ipLimiter = new FixedWindowRateLimiter(5, 60_000);
  const emailLimiter = new FixedWindowRateLimiter(10, 60_000);

  const waitlistBody = z.object({
    email: z.string().trim().min(3).max(254),
    source: z.string().max(64).optional(),
    referrer: z.string().max(2048).optional(),
  });

  app.post("/waitlist", async (request: FastifyRequest, reply: FastifyReply) => {
    const ip = clientIp(request, opts.trustProxy);

    if (!ipLimiter.check(`ip:${ip}`).allowed) {
      reply.header("retry-after", "60");
      return reply.code(429).send({
        error: "RATE_LIMITED",
        message: "Too many signups from this network. Try again in a minute.",
      });
    }

    const parsed = waitlistBody.safeParse(request.body ?? {});
    if (!parsed.success) {
      const first = parsed.error.issues[0]?.message ?? "Invalid payload";
      return reply
        .code(400)
        .send({ error: "INVALID_BODY", message: humaniseZodMessage(first) });
    }

    const email = normaliseEmail(parsed.data.email);
    if (!isLikelyEmail(email)) {
      return reply
        .code(400)
        .send({ error: "INVALID_EMAIL", message: "That doesn't look like a valid email address." });
    }

    if (!emailLimiter.check(`email:${email}`).allowed) {
      return reply.code(429).send({
        error: "RATE_LIMITED",
        message: "Too many signups for this email. Try again in a minute.",
      });
    }

    const entry: WaitlistEntry = {
      email,
      source: parsed.data.source ?? "unknown",
      referrer: parsed.data.referrer ?? "",
      createdAt: new Date().toISOString(),
      ip,
      userAgent: (request.headers["user-agent"] ?? "").toString().slice(0, 256),
    };

    const { duplicate } = await waitlist.append(entry);
    if (duplicate) {
      return reply.code(409).send({
        status: "duplicate",
        message: "You're already on the list. We'll be in touch.",
      });
    }

    void opts.waitlistMailer.sendConfirmation(entry).catch((err) => {
      app.log.warn({ err }, "waitlist mailer failed (non-fatal)");
    });

    return reply.code(201).send({
      status: "ok",
      message: "You're on the list. We'll be in touch.",
    });
  });

  if (opts.adminToken) {
    const adminLimiter = new FixedWindowRateLimiter(30, 60_000);

    const requireAdmin = async (request: FastifyRequest, reply: FastifyReply): Promise<boolean> => {
      const ipKey = `admin:${clientIp(request, opts.trustProxy)}`;
      if (!adminLimiter.check(ipKey).allowed) {
        reply.header("retry-after", "60");
        void reply.code(429).send({ error: "RATE_LIMITED" });
        return false;
      }
      const provided = extractBearerToken(request);
      if (!provided || !constantTimeEquals(provided, opts.adminToken!)) {
        void reply.code(401).send({ error: "UNAUTHORIZED" });
        return false;
      }
      return true;
    };

    app.get("/admin/waitlist.json", async (request, reply) => {
      if (!(await requireAdmin(request, reply))) return;
      const entries = await waitlist.readAll();
      return reply.send({ count: entries.length, entries });
    });

    app.get("/admin/waitlist.csv", async (request, reply) => {
      if (!(await requireAdmin(request, reply))) return;
      const entries = await waitlist.readAll();
      reply.header("content-type", "text/csv; charset=utf-8");
      reply.header("content-disposition", 'attachment; filename="waitlist.csv"');
      reply.header("cache-control", "no-store");
      void reply.send(renderWaitlistCsv(entries));
    });
  }

  for (const [route, fileName, contentType] of STATIC_FILE_BY_ROUTE) {
    app.get(route, async (_req: FastifyRequest, reply: FastifyReply) => {
      const absolute = path.join(opts.siteDir, fileName);
      try {
        const buffer = await fs.readFile(absolute);
        reply.header("content-type", contentType);
        reply.header("cache-control", cacheControlFor(route));
        return reply.send(buffer);
      } catch (err) {
        if (isMissingFile(err)) {
          return reply.code(404).send({ error: "NOT_FOUND" });
        }
        throw err;
      }
    });
  }

  app.setNotFoundHandler(async (request: FastifyRequest, reply: FastifyReply) => {
    if (request.method !== "GET" || hasFileExtension(request.url)) {
      return reply.code(404).send({ error: "NOT_FOUND" });
    }
    try {
      const buffer = await fs.readFile(path.join(opts.siteDir, "index.html"));
      reply.header("content-type", "text/html; charset=utf-8");
      reply.header("cache-control", "no-cache");
      return reply.code(200).send(buffer);
    } catch (err) {
      if (isMissingFile(err)) {
        return reply.code(404).send({ error: "NOT_FOUND" });
      }
      throw err;
    }
  });
}

export function resolveSiteDir(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  // dist/site/router.js -> ../site
  return path.resolve(here, "..", "..", "site");
}

function clientIp(request: FastifyRequest, trustProxy: boolean): string {
  if (trustProxy) {
    const forwarded = request.headers["x-forwarded-for"];
    if (typeof forwarded === "string" && forwarded.length > 0) {
      const first = forwarded.split(",")[0]?.trim();
      if (first) return first;
    }
    const real = request.headers["x-real-ip"];
    if (typeof real === "string" && real.length > 0) return real;
  }
  return request.ip;
}

function isLikelyEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value);
}

function humaniseZodMessage(message: string): string {
  if (/invalid email/i.test(message)) return "Please enter a valid email address.";
  return message;
}

function hasFileExtension(url: string): boolean {
  const pathname = url.split("?")[0] ?? url;
  const lastSlash = pathname.lastIndexOf("/");
  const lastSegment = lastSlash >= 0 ? pathname.slice(lastSlash + 1) : pathname;
  return /\.[a-z0-9]{2,5}$/i.test(lastSegment);
}

function cacheControlFor(route: string): string {
  if (
    route === "/" ||
    route === "/index.html" ||
    route === "/privacy.html" ||
    route === "/imprint.html" ||
    route.startsWith("/docs/")
  ) {
    return "public, max-age=60, stale-while-revalidate=300";
  }
  if (route.endsWith(".css") || route.endsWith(".js") || route.endsWith(".svg")) {
    return "public, max-age=300, stale-while-revalidate=600";
  }
  return "public, max-age=60";
}

function isMissingFile(err: unknown): boolean {
  return (
    typeof err === "object" &&
    err !== null &&
    "code" in err &&
    (err as { code?: string }).code === "ENOENT"
  );
}

function extractBearerToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  if (typeof header !== "string" || header.length === 0) return null;
  const match = /^Bearer\s+(\S+)$/.exec(header);
  return match && match[1] ? match[1] : null;
}

function constantTimeEquals(provided: string, expected: string): boolean {
  const a = Buffer.from(provided, "utf8");
  const b = Buffer.from(expected, "utf8");
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

function renderWaitlistCsv(entries: ReadonlyArray<WaitlistEntry>): string {
  const header = ["email", "source", "referrer", "createdAt", "ip", "userAgent"];
  const rows = [header.join(",")];
  for (const entry of entries) {
    rows.push(
      [
        csvEscape(entry.email),
        csvEscape(entry.source),
        csvEscape(entry.referrer),
        csvEscape(entry.createdAt),
        csvEscape(entry.ip),
        csvEscape(entry.userAgent),
      ].join(","),
    );
  }
  return rows.join("\n") + "\n";
}

function csvEscape(value: string): string {
  if (value === undefined || value === null) return "";
  const needsQuoting = /[",\n\r]/.test(value);
  const escaped = value.replace(/"/g, '""');
  return needsQuoting ? `"${escaped}"` : escaped;
}
