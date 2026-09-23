# Article 8: Deep Dive - The Caching Strategies

## The Speed Layer

In our system design, we established that a URL shortener is extremely **Read-Heavy** (100:1 to 1000:1 ratio). This makes caching our most powerful tool. If we can serve a redirect from memory without hitting the database, we can handle aggressive traffic spikes with minimal cost.

> **Reader path — 5. Deep dives (caching):** [Separate scoped walkthrough](../interview-questions/url-shortener.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [ID generation](07-deep-dive-id-generation.md) → caching here → [asynchronous processing](08-deep-dive-2-async-everything.md). Read the [working baseline](04-basic-system-design.md) before this latency and memory-sizing expansion.

This article details the "Caching-First" architecture.

---

## 1. The Multi-Layer Caching Strategy

We don't just put a cache "in front" of the database. We implement caching at multiple network boundaries.

### The Layers of Defense
1.  **Level 1: The Browser (The Client)**
    *   **Mechanism**: HTTP 301 Permanent Redirect.
    *   **Latency**: 0ms (Instant).
    *   **Cost**: $0.
    *   **Trade-off**: Once cached by the browser, you lose analytics visibility. The user doesn't even talk to you.
2.  **Level 2: The Edge (CDN)**
    *   **Mechanism**: A Content Delivery Network (like CloudFront or Cloudflare) caches the 301 response close to the user's city.
    *   **Latency**: 10-50ms.
    *   **Hit Rate**: High for global viral links.
3.  **Level 3: The Server (Redis)**
    *   **Mechanism**: A distributed Redis cluster in our data center.
    *   **Latency**: 1-5ms (internal network).
    *   **Purpose**: Protects the database from the "Thundering Herd" of requests that pass through the CDN (e.g., long-tail content).

### Architecture Diagram
```mermaid
graph TD
    User[User] -->|1. GET /abc| CDN
    
    subgraph "External Internet"
    CDN[CDN (Cloudflare)]
    end
    
    CDN -.->|Hit: Return 301| User
    CDN -->|Miss| LB[Load Balancer]
    
    subgraph "Our Data Center"
    LB --> API[API Server]
    API -->|2. Check| Redis[(Redis Cluster)]
    Redis -.->|Hit: Return URL| API
    Redis -.->|Miss| API
    API -->|3. Fetch| DB[(PostgreSQL)]
    end
    
    style CDN fill:#4ECDC4
    style Redis fill:#FFE66D
    style DB fill:#FF6B6B
```

---

## 2. Dealing with the "Thundering Herd"

A classic distributed system problem is the **Thundering Herd** (or **Cache Stampede**).

**The Scenario**:
1.  A Justin Bieber tweet goes out with a new link `short.app/jb`.
2.  10,000 users click it in the first second.
3.  The cache is empty (cold).
4.  All 10,000 requests miss the cache simultaneously.
5.  All 10,000 requests hit the Database at the exact same millisecond.
6.  **Database Crashes**.

**The Solution: Request Coalescing (or "Single-Flight")**
Instead of letting all requests hit the DB, the API server coordinates them.
*   **Request 1** comes in: "I need `jb`". API sees it's missing. It flags "I am fetching `jb`".
*   **Requests 2-10,000** come in: API checks the flag. "Oh, `jb` is being fetched. I will **wait** right here."
*   **Request 1** returns from DB with the URL.
*   API updates the cache and **notifies** the 9,999 waiting requests.
*   They all return the data without touching the DB.

We reduced 10,000 queries to **1 query**.

---

## 3. Cache Eviction Policies

We ran out of RAM! What do we delete?
Since we can't cache 10 billion links in RAM, we need a smart eviction policy.

### Strategy: LRU (Least Recently Used)
This is the standard. If a link hasn't been clicked in a while, it's dropped. Use `allkeys-lru` in Redis configuration.

### Strategy: The "20/80" Pre-loading
*   **The theory**: 20% of links drive 80% of traffic.
*   **The implementations**: We don't just wait for clicks. We run a daily job that queries our Analytics: "What were the top 100k links yesterday?" -> Load them into Redis *before* the traffic wakes up. This is called **Cache Warming**.

---

## 4. Operational Details (Redis)

### Memory Sizing Calculation
*   **Key**: `shortURL:abc1234` (15 bytes)
*   **Value**: `https://very-long-url.com...` (100 bytes avg)
*   **Total Entry**: ~150 bytes (with overhead).
*   **Capacity**: 16GB RAM can hold ~100 Million hot links.
    *   $(16 \times 10^9) / 150 \approx 106,666,666$ links.
*   **Verdict**: A single mid-sized Redis instance can handle the working set of even a massive startup.

### Resilience (Redis Sentinel)
Redis is fast, but if it dies, our database might die (see Thundering Herd). We use **Redis Sentinel** or **Cluster Mode** for high availability.
*   **Master**: Handles writes (setting new cache).
*   **Slaves**: Handle reads (lookups).
*   **Sentinel**: Watches the Master. If Master dies, it promotes a Slave to Master automatically within seconds.

---

## Summary
By implementing a robust 3-layer caching strategy and solving the "Thundering Herd" problem, we have effectively protected our database. Our system can now handle millions of reads per second.

But we still have one problem: **Writes**. Every time someone clicks, we need to count it. If we have 1M clicks/sec, we have 1M writes/sec. Our database can't handle that. 
In the next article, we solve this with **Asynchronous Processing**.
- **Typical Window**: Few milliseconds (most traffic hits cache)
- **How it works**:
  - API checks Redis for short code
  - If found: return cached long URL (5ms)
  - If not found: query PostgreSQL, update Redis, return
  - After 1 hour: Redis key expires, next request queries DB (refreshes)
- **Guarantee**: Within 1 hour of last access, data is consistent
- **Tradeoff**: Between 1-hour refreshes, URL metadata might change (rare)

**Layer 3: PostgreSQL (Source of Truth)**
- **Consistency Window**: Immediate (strong consistency)
- **How it works**:
  - All writes go directly to PostgreSQL (via transaction)
  - Immediate durable writes
  - Reads go through Redis/CDN first (async invalidation)
- **Guarantee**: Database is always correct; caches are eventually consistent

### Scenarios: How Consistency Works in Practice

**Scenario 1: User deletes a short link**

```
Timeline:
  T=0:    User clicks "Delete" for link /abc123
  T=1ms:  Database UPDATE: is_deleted = true
  T=2ms:  API returns 404 for /abc123 requests
  T=3ms:  CloudFront cache invalidation initiated
  T=100ms: CloudFront edge cache purged
  T=1min: All CDN PoPs cleared (eventual)

Result: Within 100ms to 1 minute, all users see 404 (worst case)
```

**Scenario 2: User updates destination URL**

```
Cannot happen! Short codes are immutable after creation.
If user wants to change destination: must delete + recreate link.
```

**Scenario 3: Database is down**

```
Timeline:
  T=0:    PostgreSQL becomes unavailable
  T=0-30s: Redis serves cached data (100% cache hit rate)
  T=30s:  CDN serves cached data (70% hit rate)
  T=30-3600s: CDN continues serving, data is 1h old

Result: If DB down for < 1 hour, users see no impact (cached)
        If DB down for > 1 hour, users see stale data
```

### Real-World Impact

| Operation | Consistency Guarantee | User Impact |
|-----------|----------------------|-------------|
| Create link | Immediate (DB written) | New link available after 1-2 seconds (CDN/Redis miss) |
| Redirect (exists) | 1 hour eventual (cached) | See correct URL from cache (< 30ms) |
| Update created link | N/A (immutable) | Not possible - must delete & recreate |
| Delete link | 100-3600s eventual | Stop working after cache expires (worst case 1h) |
| Database outage | Served from cache | Users see cached data for up to 1 hour |

### Acceptable Risk Assessment

✅ **Acceptable** (rare in practice):
- User deletes link, but CDN serves 301 for up to 1 hour
- Database is down, users see cached data from up to 1 hour ago

❌ **Not Acceptable** (implement differently):
- User expects real-time consistency (< 100ms) across all data
- Need GDPR right-to-be-forgotten (immediate deletion everywhere)

**Mitigation for strict requirements**:
- Add cache invalidation API: immediately purge CDN + Redis
- Cost: $0.005 per invalidation (5 deletions = $0.025)
- For high-volume deletions (100+/day): use bulk invalidation ($20/month)

---

## Cost Breakdown (Caching-First)

```
Component                Cost/Month    RPS Capacity
CloudFront (CDN)         $28           Unlimited (edge)
Redis (3 nodes)          $1,500        6,000 RPS
PostgreSQL              $150          500 RPS
Load Balancer           $50           Unlimited

TOTAL                   $1,728        600+ RPS ✓

Comparison:
  MVP (no cache): Database limited to 100-200 RPS
  With caching: 600+ RPS at same cost!
```

---

## Summary: Caching-First Approach

**Three layers**:
1. **CDN**: 70% hit, 10-50ms, $28/month
2. **Redis**: 60% of remainder, 1-5ms, $1,500/month
3. **Database**: Fallback + source of truth, 10-30ms, $150/month

**Key improvements**:
- Database load reduced 90% (2,900 RPS → 290 RPS)
- Latency improved (100ms → 15-20ms median)
- Cost-effective ($1,728/month for 600 RPS)
- Async analytics (no impact on redirect latency)

**Operational**:
- Monitor cache hit rate (60%+ expected)
- Detect and handle hotspots
- Warm cache on server restart
- Simple, proven approach

**Next**: Deep Dive 2 - Async-Everything (extreme performance).
