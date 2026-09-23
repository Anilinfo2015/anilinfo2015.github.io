# Articles 7-9: Specialized Caching Layers

**Beyond the standard RAM architecture.**

> **Reader path — 5. Deep dives (cache tiers):** [Separate scoped walkthrough](../interview-questions/distributed-cache.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Reference technologies](04-core-technologies.md) → specialized tiers here → [production mastery](06-production-mastery.md). Choose tiers to address bottlenecks in the [working baseline](02-mvp-architecture.md).

Sometimes, “just run a distributed in-memory cache” isn’t enough.
*   What if you need to store **200TB** of data? (RAM is too expensive).
*   What if **1ms** latency is too slow? (Network is the bottleneck).
*   What if your users are in **Tokyo** and your server is in **Virginia**? (Speed of light is the bottleneck).

This article explores the specialized tiers and how you’d design them **from scratch**:

* **L1 (Local / in-process)**: a cache inside the application process.
* **L3 (Flash-backed / hybrid)**: extend capacity beyond DRAM while staying low-latency.
* **L4 (Edge)**: serve content near users and shield your origin.

---

## 1. L1 In-Process Cache: The Sub-Millisecond Layer

**Problem**: Even an in-memory network cache is still a network call. If you call it 500 times in a request, you can manufacture 500ms of latency.
**Solution**: Cache it **inside** your application process (heap/off-heap).

### What you build
An in-process cache is a library, not a server. The core pieces mirror L2, but optimized for single-host speed:

* **Key index**: hash map (often segmented) keyed by string/bytes.
* **Value storage**: object reference, byte buffer, or off-heap slab.
* **TTL**: per-entry expiry, plus a periodic cleanup.
* **Eviction**: capacity-based policy (not necessarily strict LRU).

Expected profile:
* **Latency**: ~100ns–1µs (no network, no syscalls)
* **Throughput**: bounded by CPU + GC behavior

### Why strict LRU is usually the wrong goal
Strict LRU sounds ideal, but it punishes you under two very common workloads:
* **Scans**: one-time reads of large datasets will evict your real hot keys.
* **Concurrency**: strict LRU turns `GET` into a contended write (covered in Article 2).

A practical approach is **admission + approximate eviction**:
* Maintain a tiny **window** that behaves like LRU (captures sudden bursts).
* Maintain a main segment that behaves like LFU-ish (retains long-term hot keys).
* Use a **frequency sketch** (e.g., Count-Min Sketch) so you can say: “is this new key worth admitting?”

Reference implementations: Caffeine (Java) and Ristretto (Go) are good examples of this approach.

> **Trade-off**: **Consistency**.
> If Server A updates `config:1`, Server B doesn't know.
> **Fix**: Use short TTLs (e.g., 5 seconds), or build an invalidation channel (Pub/Sub) for explicit busts.

### The real L1 problem: invalidation
The hardest part of L1 isn’t data structures — it’s deciding when it’s safe to serve cached data.

Common patterns:
* **TTL-only**: simplest, acceptable for configs/feature flags.
* **Versioned keys**: `profile:{userId}:{version}`; bump version on write.
* **Write-through invalidation**: the writer publishes “invalidate key K” events.

---

## 2. Flash-Backed Tier (L3): The Hybrid Memory Design

**Problem**: You have 100TB of user profile data.
*   **Redis Cost**: 100TB RAM ≈ **$2M / month**. (Prohibitive).
*   **Database Cost**: Cheap, but too slow (10ms+).

**Goal**: Get “close to RAM” latency at “close to disk” cost.

### The key idea: Index in RAM, data on SSD
To keep lookups fast, you keep a small, fixed-size structure in DRAM that tells you where the value lives on SSD.

1.  **RAM (Index)**: Stores the map of `Key Hash` → `Disk Address`.
    *   *Constraint*: RAM limits the **Number of Objects** you can store.
2.  **SSD (Data)**: Stores the actual JSON/Blob.
    *   *Constraint*: SSD limits the **Size/Volume** of data.

Design implications:
* The index must be compact (hash -> pointer/offset + metadata).
* Writes should be sequential where possible (SSD-friendly).
* Reads should avoid page cache thrash and unpredictable IO.

### IO model: predictable performance beats peak performance
One common approach is to bypass the filesystem page cache and control IO patterns yourself:
* Use direct IO / raw devices to avoid double-caching.
* Use fixed-size blocks or log-structured segments.
* Keep compaction/defragmentation as a background activity with strict rate limits.

Reference implementation: Aerospike is a well-known example of this hybrid design.

**Cost Impact**:
*   100TB RAM: $2M/mo.
*   100TB NVMe SSD: ~$150k/mo.
*   **Savings**: **$>90%**.

### Eviction becomes “which bytes?” not “which keys?”
In a flash-backed tier, capacity pressure happens in two places:
* **DRAM index** fills (too many objects)
* **SSD store** fills (too many bytes)

So your eviction/accounting needs both:
* object count limits
* byte size limits

---

## 3. Edge Caching (L4): The User-Facing Shield

**Problem**: Speed of Light. A user in Sydney requesting data from Virginia faces ~200ms round-trip latency.

**Solution**: Push cacheable content close to users, and shield your origin.

### What you build
Edge caching is usually delivered via a CDN (or a reverse-proxy fleet). Conceptually, it’s a cache with a few extra constraints:
* multi-tenant security boundaries
* aggressive request collapsing (to protect origin)
* cache key normalization (headers, cookies, query params)

Reference implementations: Varnish/Nginx at the edge; CDNs like Cloudflare/Akamai/Fastly.

CDN nodes sit miles from the user.
*   **Cache-Control Headers**: You tell the CDN how to behave.
    *   `s-maxage=3600`: "CDN, hold this for 1 hour."
    *   `Vary: Authorized-User`: "Cache a different version for each user." (Dangerous, low hit ratio).

### Origin Shielding
Without a shield, 100 cache misses from 100 cities hit your database 100 times.
**With Shielding**:
1.  Sydney User misses local CDN.
2.  Local CDN asks "California Shield" CDN. (Hit?)
3.  Only if Shield misses does request go to your Database.
**Impact**: Massive reduction in total load.

---

## Summary: The Complete Hierarchy

| Tier | Layer | Latency | Capacity | Cost | Best For |
|---|---|---|---|---|---|
| **L1** | **In-process cache** | **100 ns–1µs** | ~GBs | $ | Hot loops, Config |
| **L2** | **Distributed cache service (ours)** | **~1 ms** | ~TBs | $$ | Shared sessions, profiles, feed objects |
| **L3** | **Flash-backed hybrid tier** | **~1–2 ms** | ~PBs | $ | Large profiles, history, large value sets |
| **L4** | **Edge cache / CDN** | **20–50 ms*** | Global | $ | HTML, images, public API |
| **L5** | **Database** | **10-50 ms** | ∞ | $$ | Source of Truth |

*\*20ms to user, effectively 0ms to backend.*

**[Next: Production Mastery & Patterns →](06-production-mastery.md)**
