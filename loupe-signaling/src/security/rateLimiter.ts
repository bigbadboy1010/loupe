export interface RateLimitDecision {
  readonly allowed: boolean;
  readonly remaining: number;
  readonly retryAfterSeconds: number;
}

interface Bucket {
  count: number;
  resetAt: number;
}

/**
 * Small fixed-window limiter for the signaling service. It intentionally avoids
 * external state and dependencies; deploy behind an edge limiter for internet-facing use.
 */
export class FixedWindowRateLimiter {
  private readonly buckets = new Map<string, Bucket>();

  public constructor(
    private readonly maxRequests: number,
    private readonly windowMs: number,
    private readonly now: () => number = Date.now,
  ) {}

  public check(key: string): RateLimitDecision {
    const current = this.now();
    this.prune(current);

    const existing = this.buckets.get(key);
    if (!existing || existing.resetAt <= current) {
      this.buckets.set(key, { count: 1, resetAt: current + this.windowMs });
      return { allowed: true, remaining: Math.max(this.maxRequests - 1, 0), retryAfterSeconds: 0 };
    }

    if (existing.count >= this.maxRequests) {
      return {
        allowed: false,
        remaining: 0,
        retryAfterSeconds: Math.max(Math.ceil((existing.resetAt - current) / 1000), 1),
      };
    }

    existing.count += 1;
    return {
      allowed: true,
      remaining: Math.max(this.maxRequests - existing.count, 0),
      retryAfterSeconds: 0,
    };
  }

  public get size(): number {
    this.prune(this.now());
    return this.buckets.size;
  }

  private prune(current: number): void {
    for (const [key, bucket] of this.buckets) {
      if (bucket.resetAt <= current) {
        this.buckets.delete(key);
      }
    }
  }
}
