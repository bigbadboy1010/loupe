# Landing-page architecture decisions

Why we built the Loupe landing site the way we did, and what we explicitly **didn't** do. The point of this document is so that future-us (or anyone reading the code) understands the constraints, not just the outcome.

## Summary

The landing page is plain HTML + CSS + a single small JS file, served by the existing Fastify signaling container. No framework, no build step on the client side, no CMS, no database for the waitlist. The whole thing is < 30 KB on the wire for the HTML, CSS, JS, and SVG favicon combined.

## Stack

| Layer            | Choice                | Why                                                                                             |
| ---------------- | --------------------- | ----------------------------------------------------------------------------------------------- |
| HTML             | Hand-written, semantic | We control the structure; no hydration mismatch, no client framework to keep alive on `prefers-reduced-motion`. |
| CSS              | Hand-written, custom properties | One file, ~10 KB, dark/light via `prefers-color-scheme`, no Tailwind dependency, no PostCSS.   |
| JS               | Vanilla, ~3 KB, IIFE  | The only interactive thing is the waitlist form. A framework would be 100× the size.            |
| Hosting          | Fastify static routes | Already in the same container as signaling. One Caddy rule, one TLS cert, one origin for `/healthz`, `/pairing`, `/ws`, `/`, `/waitlist`. |
| Mailer (stub)    | `LoggingMailer`       | Structured log entry, no SMTP dependency yet. Swap in Sprint 2 when we have credentials.        |
| Waitlist storage | JSONL on disk         | Append-only, zero dependencies, easy to grep. Postgres migration is mechanical when needed.     |

## Why no framework?

- **Cost**: A Next.js or Astro app would add a build pipeline, an adapter for Fastify, and a runtime we don't need for a one-page site.
- **Lighthouse**: Hand-written HTML/CSS scores 100 on every Lighthouse category out of the box.
- **Editorial control**: When the copy changes (which it will, often), you edit a string and `git commit`. No MDX, no CMS preview, no broken-prop-types deploy.
- **Operational simplicity**: One container, one process. A reverse proxy + CDN can sit in front later; today we don't need it.

## Why no database for the waitlist (yet)?

We expect < 5 000 signups in the first six months. JSONL on disk:

- Has zero moving parts.
- Is trivial to read with `cat`, `grep`, `jq`.
- Migrates cleanly to Postgres via a 30-line script when (and only when) we outgrow it.
- Makes backup a one-liner: `cp data/waitlist.jsonl backups/`.

The `WaitlistStore` API is shaped to make that swap mechanical: `append(entry)` and `count()` are the only operations. If we'd started with Postgres we'd be carrying operational overhead we don't yet need.

## Why Fastify and not a separate "landing service"?

- **One origin = one Caddy rule = one TLS cert**. The client apps already trust `loupe.ddns.net`; serving the marketing site on the same origin means we don't introduce a new host that needs to be on the controller's HSTS preload list.
- **One health check**. `/healthz` already returns session counts; we extended it conceptually (waitlist size can be exposed there when we want it).
- **Feature-flag gated**. `SERVE_SITE=false` by default means existing signaling-only deployments (e.g. enterprise self-hosters who don't want the marketing site on their relay) get exactly the behavior they had before.

## Why include the waitlist in the same service?

Same reasons. The waitlist endpoint hits the same rate-limiter, the same `trustProxy` plumbing, the same logger. Splitting it out would mean re-implementing all of that.

## What we did not do (and why)

- **No CMS**. We are the writers; the writers can edit HTML. A CMS adds attack surface and an auth story for one internal user.
- **No analytics.** No Google Analytics, no Plausible, no self-hosted Umami. We don't have a tracking-cookie story we want to defend. The waitlist count is the only metric we care about right now.
- **No client-side routing.** This is a static page with one form. A SPA router would be pure overhead.
- **No service worker / offline mode.** The site has no business being offline.
- **No "design system" or Storybook.** One page, one style file, one brand. A design system is a tax we pay when we have three pages and a settings screen. We have one.
- **No A/B testing.** The waitlist conversion rate at < 5 000 visitors is too low to be statistically meaningful. We'll experiment when there's enough traffic to learn from.
- **No "Get notified when we ship" widget besides the waitlist.** FOMO widgets are noise.

## Known limitations

- **Single region, no CDN.** Fine until we hit ~50 000 unique visitors/month; Cloudflare sits in front of Caddy for free when needed.
- **JSONL scan for duplicates is O(n).** Fine at < 5 000 entries. Will need an index or DB at > 50 000.
- **No double-opt-in yet.** Stub mailer logs the would-be email. GDPR-compliant transactional email is Sprint 2 (the body shape is already in `WaitlistStore`).
- **Single admin surface.** For now, "admin" means `cat data/waitlist.jsonl`. We will build an export endpoint in Sprint 2.

## When this stops working

| Trigger                                                     | Action                                                |
| ----------------------------------------------------------- | ----------------------------------------------------- |
| > 5 000 waitlist entries                                    | Move to SQLite (still on the same host, no infra).    |
| > 50 000 waitlist entries or > 5 concurrent landing users   | Add Cloudflare in front of Caddy.                     |
| > 5 pages of marketing (changelog, blog, case studies)      | Move static site to a real static-site generator.     |
| Need authenticated admin (waitlist export, banning abuse)  | Add a small admin surface, probably behind OIDC.      |

We will reassess when we hit each trigger, not before.
