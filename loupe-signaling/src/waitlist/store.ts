import { promises as fs } from "node:fs";
import path from "node:path";

export interface WaitlistEntry {
  readonly email: string;
  readonly source: string;
  readonly referrer: string;
  readonly createdAt: string;
  // Note: we deliberately do NOT store IP address or User-Agent here.
  // The signaling server logs them temporarily for abuse prevention (rate
  // limiting), but they are not persisted with the waitlist entry. This keeps
  // the on-disk data minimal (Art. 5(1)(c) GDPR — data minimisation) and
  // matches the wording of the public privacy policy.
}

/**
 * Append-only JSONL store for waitlist signups.
 *
 * Intentionally simple: each submission is one line of JSON, no SQLite, no external
 * services. Reasoning is documented in `docs/pricing.md` and `docs/landing-decisions.md`:
 * we expect < 5 000 signups in the first 6 months, and jsonl is trivial to migrate to
 * Postgres when (and only when) we outgrow it.
 */
export class WaitlistStore {
  private readonly filePath: string;
  private writeChain: Promise<void> = Promise.resolve();

  public constructor(filePath: string) {
    this.filePath = filePath;
  }

  public async append(entry: WaitlistEntry): Promise<{ duplicate: boolean }> {
    const normalised = normaliseEmail(entry.email);

    const existing = await this.scanDuplicates(normalised);
    if (existing) {
      return { duplicate: true };
    }

    const line =
      JSON.stringify({
        ...entry,
        email: normalised,
        createdAt: entry.createdAt || new Date().toISOString(),
      }) + "\n";

    this.writeChain = this.writeChain.then(() => this.writeLine(line));
    await this.writeChain;
    return { duplicate: false };
  }

  public async count(): Promise<number> {
    try {
      const text = await fs.readFile(this.filePath, "utf8");
      if (!text) return 0;
      return text.split("\n").filter((line: string) => line.trim().length > 0).length;
    } catch (err) {
      if (isMissingFile(err)) return 0;
      throw err;
    }
  }

  /**
   * Reads every entry as a parsed array, newest-first. Caller controls any
   * additional filtering. Returns [] if the file does not exist yet.
   */
  public async readAll(): Promise<WaitlistEntry[]> {
    let text: string;
    try {
      text = await fs.readFile(this.filePath, "utf8");
    } catch (err) {
      if (isMissingFile(err)) return [];
      throw err;
    }
    if (!text) return [];
    const out: WaitlistEntry[] = [];
    for (const raw of text.split("\n")) {
      const trimmed = raw.trim();
      if (!trimmed) continue;
      try {
        const parsed = JSON.parse(trimmed) as WaitlistEntry;
        if (parsed && parsed.email) out.push(parsed);
      } catch (parseErr: unknown) {
        void parseErr;
      }
    }
    out.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    return out;
  }

  private async writeLine(line: string): Promise<void> {
    await fs.mkdir(path.dirname(this.filePath), { recursive: true });
    await fs.appendFile(this.filePath, line, { encoding: "utf8", mode: 0o600 });
  }

  private async scanDuplicates(normalisedEmail: string): Promise<boolean> {
    try {
      const text = await fs.readFile(this.filePath, "utf8");
      if (!text) return false;
      for (const raw of text.split("\n")) {
        const trimmed = raw.trim();
        if (!trimmed) continue;
        try {
          const parsed = JSON.parse(trimmed) as Partial<WaitlistEntry>;
          if (parsed && parsed.email && normaliseEmail(parsed.email) === normalisedEmail) {
            return true;
          }
        } catch (parseErr: unknown) {
          // Skip corrupt lines; in production we should re-emit a structured log entry here.
          void parseErr;
        }
      }
      return false;
    } catch (err) {
      if (isMissingFile(err)) return false;
      throw err;
    }
  }

  /**
   * Removes any entries whose email matches the normalised form.
   *
   * Used by the GDPR Art. 17 right-to-erasure flow: a user replies to
   * the confirmation email (or hits `DELETE /waitlist` with their address)
   * and we scrub every line that mentions that email.
   *
   * Returns the count of removed entries. Safe to call when the file
   * does not exist (returns 0). Rewrite is atomic via temp-file + rename.
   */
  public async removeByEmail(email: string): Promise<{ removed: number }> {
    const normalised = normaliseEmail(email);
    let removed = 0;
    let text: string;
    try {
      text = await fs.readFile(this.filePath, "utf8");
    } catch (err) {
      if (isMissingFile(err)) return { removed: 0 };
      throw err;
    }
    if (!text) return { removed: 0 };

    const surviving: string[] = [];
    for (const raw of text.split("\n")) {
      const trimmed = raw.trim();
      if (!trimmed) continue;
      try {
        const parsed = JSON.parse(trimmed) as Partial<WaitlistEntry>;
        if (parsed && parsed.email && normaliseEmail(parsed.email) === normalised) {
          removed += 1;
          continue; // drop this line
        }
      } catch {
        // Keep lines we cannot parse; we never want to silently destroy data.
      }
      surviving.push(raw);
    }
    if (removed === 0) return { removed: 0 };

    // Atomic rewrite: write to a sibling temp file, then rename.
    const tmp = `${this.filePath}.tmp`;
    const payload = surviving.length === 0 ? "" : surviving.join("\n") + "\n";
    await fs.writeFile(tmp, payload, { encoding: "utf8", mode: 0o600 });
    await fs.rename(tmp, this.filePath);
    // Preserve mode 0600 on the final file (rename keeps source mode, but
    // be explicit anyway).
    await fs.chmod(this.filePath, 0o600);
    return { removed };
  }
}

export function normaliseEmail(email: string): string {
  return email.trim().toLowerCase();
}

function isMissingFile(err: unknown): boolean {
  return (
    typeof err === "object" &&
    err !== null &&
    "code" in err &&
    (err as { code?: string }).code === "ENOENT"
  );
}
