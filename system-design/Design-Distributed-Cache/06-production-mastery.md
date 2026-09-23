# Article 10: Battle-Tested Patterns & Production Mastery

**The difference between a system that works on a whiteboard and one that survives Black Friday.**

You have designed the system. Now comes the hardest part: **Day 2 Operations**.

> **Reader path — 5. Deep dives (reliability, security, and operations):** [Separate scoped walkthrough](../interview-questions/distributed-cache.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Specialized tiers](05-specialized-caching.md) → production checks here → [practice companion](staff-feedback-and-practice-plan.md). These checks expand the [working baseline](02-mvp-architecture.md) and selected scaling decisions.

This article covers the "unknown unknowns"—the reusable patterns for edge cases, the security layers for compliance, and the observability stack you need to sleep at night.

---

## 1. Five Timeless Patterns

These are not vendor features; they are logical patterns you implement in your cache client, cache service, or surrounding infrastructure.

### Pattern 1: Stampede Prevention (A Toolkit, Not One Trick)
**The Problem**: 1 million keys expire at exactly 12:00:00. Your database receives 1 million requests at 12:00:01.
This is a coordination failure: too many callers rebuild the same key at once.

**The Fix**: combine 2-3 of these.

**1) TTL jitter**: never use a fixed TTL.
```python
# Bad
cache.set(key, value, ttl=3600)

# Good (Jitter)
jitter = random.randint(-300, 300)
cache.set(key, value, ttl=3600 + jitter)
```
**Result**: Expirations are spread over 10 minutes. Database load is smoothed.

**2) Request coalescing (singleflight)**: one in-flight rebuild per key.
* On cache miss, acquire a per-key lock/lease so only one thread recomputes.
* Other concurrent misses wait briefly, or serve stale data if available.

**3) Serve stale while revalidating**: hide refresh latency.
* Keep a soft TTL + hard TTL.
* After soft TTL: serve stale and refresh asynchronously.
* After hard TTL: block and rebuild (or fail).

### Pattern 2: Circuit Breaker
**The Problem**: A cache node fails. The client retries. The retry fails. The client retries again. The retry storm takes down the network.
**The Fix**: Stop asking.
*   **State Closed (Normal)**: Requests flow.
*   **State Open (Broken)**: After 5 failures, block all requests for 10 seconds. Return "Cache Unavailable" instantly.
*   **State Half-Open**: After 10 seconds, let 1 request through. If it works, close the circuit.

**Upgrade: serve stale on error**
If your cache tier is flaky, it’s often better to serve slightly stale data than to fail hard. This is the same concept as HTTP caches’ `stale-if-error`.

### Pattern 3: Hot Key Replication
**The Problem**: "Justin Bieber" profile gets 100x more traffic than "User 1". One shard melts.
**The Fix**: Local Caching or Read Replicas.
*   **Detect**: "Key `user:bieber` > 1000 QPS".
*   **Action**: Cache `user:bieber` on the *Application Server* (L1 Cache) for 5 seconds.
*   **Result**: 0 network requests for the hottest key.

### Pattern 4: Multi-Tier Caching
**The Problem**: Network latency (1ms) is too slow for reading configuration flags 1000 times/sec.
**The Fix**:
1.  **L1**: In-process memory - ~100ns.
2.  **L2**: Distributed in-memory cache tier - ~1ms.
3.  **L3**: Database - ~20ms.

### Pattern 5: Cache Warming
**The Problem**: You restart your cache cluster. It is empty. 100% of requests hit the database. The database dies.
**The Fix**: Before switching traffic, replay the last 1 hour of hot-key access logs to the new cache, or preload from a snapshot/backup mechanism your system supports.

---

## 2. Security: Defense in Depth

Your cache contains user sessions, PII, and financial data. It is a high-value target.

### Authentication & Authorization
*   **VPC Isolation**: The first line of defense. Cache servers should *never* have public IPs.
*   **ACLs (Access Control Lists)**:
    *   `Service A` can read/write `session:*`.
    *   `Service B` can only read `config:*`.
    *   Build this into your cache front door (API gateway, sidecar, or the cache service itself).

### Encryption
*   **In-Transit (TLS)**: Mandatory. Without TLS, a packet sniffer can read `session_token` off the wire.
*   **At-Rest (Disk)**: If you use persistence (RDB/AOF), encrypt the disk (LUKS or AWS KMS).

### Compliance (GDPR/PCI)
*   **Right to be Forgotten**: When a user deletes their account, you must delete their cached data. Don't wait for TTL.
*   **Card Data**: Never cache PAN (Primary Account Numbers).

### Abuse & DoS Edge Cases
*   **Hash collision / HashDoS**: if an attacker can force many keys into the same hash buckets, latency can degrade dramatically. Use hardened hash tables and consider adding a small amount of randomness in admission/eviction decisions so the cache can’t be gamed deterministically.

---

## 3. Production Readiness: The Stack

### The Four Golden Signals
If you only monitor four things, monitor these:
1.  **Latency**: p99 and p50. (Is it slow?)
2.  **Traffic**: Request rate. (Is it spiking?)
3.  **Errors**: Connection refused, timeouts. (Is it broken?)
4.  **Saturation**: Memory usage, CPU usage. (Is it full?)

### Distributed Tracing
**Critically Important and often forgotten.**
When a request takes 500ms, *where* was the time spent?
*   App logic?
*   Network?
*   Cache queue?
*   Serialization?

**Tooling**: OpenTelemetry (Jaeger/Zipkin).
**Implementation**: Pass a `Trace-ID` with every cache request.
**Visual**: unique waterfall chart showing `App -> Redis (SET) -> 2ms`.

### SLOs (Service Level Objectives)
Define success mathematically.
*   **Availability**: 99.9% (max 43m downtime/month).
*   **Latency**: 99% of requests < 5ms.
*   **Hit Ratio**: > 90%.

---

## 4. Operational Runbooks

When the pager goes off at 3 AM, don't think. Read.

### Scenario: High Latency
1.  **Check Saturation**: Is CPU > 80%? If yes, shed load or add read replicas.
2.  **Check Slow Operations**: Look for expensive commands (e.g., full key scans, large payload serialization, synchronous eviction work).
3.  **Check Network**: Is packet loss high?

### Scenario: Low Hit Ratio
1.  **Check TTLs**: Did someone deploy code that sets `TTL=0`?
2.  **Check Eviction**: Is memory full? If `used_memory_human` is near `maxmemory`, you are evicting keys to make room. **Scale up RAM.**

### Scenario: Cascading Failure
1.  **Enable Circuit Breakers**: Stop the bleeding.
2.  **Disable Heavy Features**: Turn off "Recommendations" or "Search".
3.  **Restart with Backoff**: Don't restart everything at once.

### Scenario: Users See Stale Data After Writes
1.  **Check invalidation ordering**: commit to the source of truth before invalidating.
2.  **Check for invalidation races**: reads between commit and delete can repopulate stale data.
3.  **Mitigate**: add lease tokens (reject cache population if invalidated since lease issued) or move to event-driven invalidation for correctness-sensitive data.

---

## 5. Final Interview Wisdom

You are now ready.

*   **Design**: You know how to start simple (MVP) and scale to Billions (Sharding).
*   **Choose**: You know why to pick Memcached (Speed), Redis (Features), or Hazelcast (Consistency).
*   **Deep Dive**: You know about Flash storage (Aerospike) and L1 caching (Caffeine).
*   **Survive**: You know about Circuit Breakers and Runbooks.

**Go build something independent of the database.**

---

## References / Further Reading

* Request coalescing (“one lock per cache key”): https://github.com/ZiggyCreatures/FusionCache/discussions/263
* Cache stampede background + mitigation options: https://en.wikipedia.org/wiki/Cache_stampede
* HTTP stale content directives (`stale-while-revalidate`, `stale-if-error`): https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cache-Control
* HashDoS / admission jitter discussion in a production cache design: https://github.com/ben-manes/caffeine/wiki/Design
* Commit-before-invalidate + lease tokens: https://www.systemoverflow.com/learn/caching/cache-invalidation/write-path-patterns-write-through-write-behind-and-cache-aside-with-delete-on-write

---
**[Back to Requirements, Entities, and Interface](01-introduction-and-requirements.md)**
