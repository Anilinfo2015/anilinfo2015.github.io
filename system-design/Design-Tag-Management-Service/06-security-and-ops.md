# Part 6: Security & Production Readiness

## 1. Security: Trust No One

### Authentication & Authorization
Building a wall around the API isn't enough; we need internal checkpoints.

> **Reader path — 5. Deep dives (security, operations, and sizing):** [Separate scoped walkthrough](../interview-questions/tag-management.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Consistency](05-deep-dive-consistency.md) → production checks here → [patterns and evolution](07-patterns-and-evolution.md). Capacity estimates support shard and cache decisions after the [working baseline](02-basic-system-design.md).

*   **The Problem**: "Service A" calls "Tag Service". Should we trust it?
*   **The Zero Trust Solution**: Even internal services must present a token (JWT) signed by the Gateway.
*   **The Permission Check**: Before adding a tag, the Tag Service asks: *"Does this user actually own this Jira ticket?"* This check is slow, so we cache the "Yes/No" results for 5 minutes.

### Threat Models
*   **The "Tag Spammer"**: A malicious script adds 10,000 tags to a competitor's repo.
    *   *Defense*: **Rate Limiting**. We give each user a "bucket" of tokens. If they empty the bucket (too many writes), they get a 429 error. We also implement a hard cap: Max 100 tags per item.
*   **XSS via Tag Names**: A user names a tag `<script>alert('hacked')</script>`.
    *   *Defense*: **Sanitization**. We strictly whitelist tag characters (alphanumeric and hyphens only).

---

## 2. Observability: Flying Instrument Rules

You can't fix what you can't see. In production, we rely on the "Three Pillars":

### Metrics (The Dashboard)
*   `tag_write_latency`: If this goes over 200ms, wake up the on-call engineer.
*   `cache_hit_ratio`: If this drops below 80%, the DB is about to die.
*   `kafka_consumer_lag`: "How far behind is the trending tags list?"

### Logging (The Black Box)
*   Structured JSON logs are non-negotiable.
*   *Bad*: `Log.info("Tag added")` (Useless).
*   *Good*: `{"event":"tag_added", "user_id":"u1", "latency_ms": 12, "trace_id":"xyz"}`.

### Tracing (The X-Ray)
*   With Jaeger/OpenTelemetry, we can follow a single request as it jumps from Gateway -> Service -> DB -> Cache. This is the only way to debug "Why was that one request slow?"

---

## 3. Capacity Planning: The Math

**Assumptions**:
*   100M DAU.
*   User adds 1 tag/day on average -> 100M writes/day.
*   Write QPS = 100M / 86400 ≈ 1,150 (Avg) -> 50k (Peak Burst).
*   Storage: 100M rows/day * 100 bytes = 10GB/day = 3.6 TB/year.

**Hardware Sizing**:
*   **DB**: 3.6TB fits on modern SSDs, but IOPS is the bottleneck. Sharding solves the IOPS/CPU limit. 10 shards start.
*   **Cache**: 20% of hot data. 200GB Redis cluster (RAM is cheap).
