# Article 3: Scaling Challenges & Trade-offs

## Database overload and hit ratio

Here is the uncomfortable truth of system design: **Databases don't scale effortlessly. Your application traffic does.**

> **Reader path — 5. Deep dives (bottlenecks and scaling):** [Separate scoped walkthrough](../interview-questions/distributed-cache.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Working baseline and internals](02-mvp-architecture.md) → distributed trade-offs here → [reference technologies](04-core-technologies.md). Sizing supports routing, replication, and rebalancing decisions within stage 5.

Modern databases like PostgreSQL are miracles of engineering, capable of handling 10,000+ complex queries per second. But your "viral" application generates 100,000 requests per second, and 99% of them are asking for the exact same Profile Page.

### The Physics of the Problem
*   **Database (Disk)**: To read a row, the disk head moves (or SSD controller seeks). Cost: **millions of CPU cycles**.
*   **Cache (RAM)**: To read a key, the CPU follows a pointer. Cost: **hundreds of CPU cycles**.

The difference isn't percentage points. It's orders of magnitude.

### Real-World Stakes
*   **Meta**: Deploys 30,000+ Memcached servers. Without this layer, their databases would receive 1 *billion* requests per second instead of a manageable 50 million.
*   **Netflix**: Serves 500,000 request/sec from their EVCache (Redis/Memcached) tier. Their database tier handles a fraction of that. Without caching, Netflix would need 10x more database hardware—or simpler, it would just be down.

> **The Math is Brutal:**
> *   **Traffic**: 1,000,000 users/sec.
> *   **Database Capacity**: 5,000 QPS.
> *   **Without Cache**: 200x overload. Immediate collapse.
> *   **With 99% Hit Ratio Cache**: Database sees 10,000 QPS. Still 2x overload.
> *   **With 99.9% Hit Ratio Cache**: Database sees 1,000 QPS. Safe.
>
> **Takeaway**: A cache isn't an optimization; it is a structural necessity for survival.

### A Cautionary Tale: The Pinterest Incident

In 2013, Pinterest suffered a major outage during Black Friday. It wasn't a code bug. It was a cache failure.

1.  **The Trigger**: A configuration change made the cache cluster unstable.
2.  **The Drop**: Cache hit ratio dropped from **95%** to **40%**.
3.  **The Illusion**: 40% sounds okay, right? It's still caching almost half the traffic!
4.  **The Reality**: With 95% hit ratio, the DB takes 5% of traffic. With 40% hit ratio, the DB takes 60% of traffic. **That is a 12x load spike.**
5.  **The Result**: The databases melted. Pinterest was down for hours.

This series isn't about "making things fast." It is about **reliability engineering**.

---

**"Distributed Systems" is just a fancy way of saying "Now we have more problems."**

Moving from one node to two nodes changes everything. You don’t get “2× capacity”. You get routing, membership, rebalancing, and failure semantics that now live on the network.

This article maps the pain points of scaling **your own cache service**: how keys find nodes, how nodes agree on ownership, and how you stay available during failures.

---

## 1. The Five Horsemen of Cache Failure

As you scale from 1M to 100M users, your system will likely fail in one of these five specific ways. Recognizing them early saves weekends.

### Failure 1: The Cache Stampede (Thundering Herd)
**The Scenario**: You cache a trending news article for 60 minutes.
**The Event**: At `T=60m`, the key expires.
**The Impact**: 10,000 users request the article simultaneously.
*   Cache: "Miss!"
*   Database: Receives 10,000 queries in 100ms.
*   Result: **Database CPU spikes to 100%. Service goes down.**

The key insight is that stampedes are a **coordination failure under load**, not a “bug”.

**Mitigations (you usually combine 2-3):**

1) **TTL Jitter** (cheap, ubiquitous)
Never set exact TTLs. Instead of 60 minutes, set `60m + random(0-60s)`. This spreads expirations out so the database sees a trickle of refreshes, not a tsunami.

2) **Request Coalescing / Singleflight** (prevents redundant recompute)
Only one caller is allowed to rebuild `key=X` at a time.
* On a miss: acquire a **per-key lock/lease**; recompute; populate.
* Other concurrent misses: wait briefly, or serve a fallback.

3) **Serve stale while revalidating** (hide refresh latency)
Keep a “soft TTL” and a “hard TTL”. After soft TTL, serve stale and refresh in the background. After hard TTL, block and refresh.

4) **Probabilistic early refresh** (avoids synchronized expiry)
Refresh a little before expiry with a probability that increases as the key approaches its deadline.

5) **Pre-warm known hot keys**
If you can predict demand, proactively refresh popular keys before they expire.

### Failure 2: The Hot Key
**The Scenario**: Justin Bieber tweets.
**The Event**: 1 million people request his profile (`user:bieber`) instantly.
**The Impact**:
*   All requests hash to the *same* physical node (Partition #42).
*   That single node receives 1M QPS.
*   Node melts. The other 99 nodes are idle.

**The Mitigation**: **Local L1 Caching** or **Replication**.
Give the hottest keys to *everyone*. Cache `user:bieber` locally on the app servers for 5 seconds.

### Failure 3: Cascading Failures
**The Scenario**: Node A acts overloaded.
**The Event**: The load balancer dutifully moves Node A's traffic to Node B.
**The Impact**: Node B was already at 80% capacity. The 20% extra load kills Node B. Traffic moves to Node C. Node C dies.
**The Result**: **Domino Effect.** The entire cluster collapses.

**The Mitigation**: **Circuit Breakers**.
If a node is failing, *fail fast*. Don't retry endlessly. Don't shift 100% load instantly. Shed load to save the system.

### Failure 4: Replication Lag
**The Scenario**: User updates profile in New York (Primary).
**The Event**: User immediately refreshes page from London (Replica).
**The Impact**: London replica hasn't received the update yet (speed of light is slow).
**The Result**: User sees old data. "I just changed this! Why is it broken?"

**The Mitigation**: **Sticky Sessions** or **Acceptance**.
Either force the user to read from NY for 1 second, or accept that this is part of the "Eventual Consistency" contract.

### Failure 5: Cache Invalidation Races (When Cache-Aside Isn’t Atomic)

Most teams start with **cache-aside + delete-on-write**:
1. write to DB
2. delete cache key
3. reads repopulate lazily

This is generally the right default, but there’s a nasty race:
* If a read happens **between** “DB commit” and “cache delete”, it can repopulate stale data.
* Worse: if you invalidate **before** committing, a read can cache old origin data and keep it indefinitely.

**Mitigations:**
* **Commit before invalidate** (mandatory ordering)
* **Lease tokens**: on miss, cache grants a short-lived token; `SET` is rejected if an invalidation happened since the lease was issued
* **Event-driven invalidation** for strong freshness: publish invalidations after commit; partition by entity ID; include version numbers and make handlers idempotent

---

## 2. The Core Scaling Problem: Key → Node Routing

When you scale out, every request begins with one question:

> **Which node owns this key right now?**

There are two broad approaches:

### Option A: Client-side routing (stateless servers)
* Clients compute ownership locally using a shared topology map.
* Pros: cache nodes are simple; no extra hop.
* Cons: topology updates must be distributed to every client; harder operationally.

### Option B: Proxy / router tier
* Clients talk to a stable endpoint; routers forward to the correct node.
* Pros: topology changes are centralized.
* Cons: extra hop; routers can become bottlenecks (must scale too).

Either way, the routing function typically uses **consistent hashing**.

---

## 3. Consistent Hashing (and Why “mod N” Fails)

`hash(key) % N` breaks because adding/removing a node remaps most keys, causing a cache wipeout.

Consistent hashing fixes that by mapping nodes and keys to a ring and only moving ~1/N of keys on membership changes.

Design details that matter in interviews:
* **Virtual nodes (vnodes)**: avoid load imbalance; a node owns many points on the ring.
* **Weighted nodes**: bigger machines get more vnodes.
* **Rebalancing speed limits**: move keys gradually to avoid saturating network/DB.

---

## 4. Replication Model (What Happens When a Node Dies?)

You need to pick semantics:

### Primary/Replica (common in practice)
* Writes go to a **primary**; **replicas** catch up (often async).
* Reads may be stale (bounded by replication lag).
* During a partition: if clients can’t reach the primary for that shard, **writes may fail** until failover (or you explicitly design multi-primary).

### Leaderless / Quorum (Dynamo-style)
* Writes go to $W$ replicas; reads go to $R$ replicas (with $R+W>N$ for quorum).
* Higher availability under partitions, but you now own conflict handling (versions, LWW, read-repair).
* Latency increases (multiple replicas per request).

For a cache, the usual answer is: **prefer availability**, accept bounded staleness, and rely on the source of truth (DB) for correctness.

---

## 5. Membership & Failure Detection (The “Who Is Alive?” Problem)

Your cluster needs a way to agree on the node list:
* Heartbeats + timeouts
* Leader election or a coordination service
* Anti-entropy: periodically reconcile topology views

The core trade-off:
* Detect failures too fast → false positives, flapping
* Detect failures too slow → long tail latency, retries

### Deep Dive: Where Do “Ring Details” Live at Massive Scale?

At small scale, you can hardcode a node list in config and call it a day.

At massive scale (hundreds/thousands of cache nodes, frequent scaling, failures, rebalancing), you need a **control plane** that answers:
* What nodes exist and are healthy?
* What is the current topology version (epoch)?
* Which virtual ranges/vnodes does each node own right now?
* How do clients/routers learn changes safely?

This is where teams use a **coordination store** (examples: ZooKeeper / etcd / Consul). Importantly:

> The coordination store is **not** on the hot `GET/SET` data path. It stores *metadata* (membership + assignments) and clients/routers **watch** it.

Typical pattern:
* Cache nodes maintain **leases/ephemeral registrations** so dead nodes disappear automatically.
* A cluster manager writes a **versioned ring/topology** (e.g., `topology_v42`).
* Clients/routers watch the topology key and update in-memory routing tables.
* Rebalancing publishes a new topology, then traffic shifts gradually (to avoid DB + network spikes).

```mermaid
flowchart LR
	subgraph DataPlane[Data Plane]
		App[App Servers / Clients]
		Router[Router Tier (optional)]
		Cache[Cache Nodes]

		App -->|GET/SET| Router
		Router -->|forward| Cache
		App -->|GET/SET (client-side routing)| Cache
	end

	subgraph ControlPlane[Control Plane]
		Store[(Coordination Store\netcd / ZooKeeper / Consul)]
		Manager[Cluster Manager\nAllocator + Rebalancer]
		Agent[Node Agent\nHealth + Heartbeats]

		Cache -->|health, stats| Agent
		Agent -->|register/lease| Store
		Manager -->|write topology\n(vnodes, weights, epoch)| Store
		App -.->|watch topology| Store
		Router -.->|watch topology| Store
	end
```

If you don’t want a hard dependency on an external store, you can push toward gossip-based membership + eventual convergence, but you still need an answer for “who is allowed to publish topology changes” and “how do we prevent split brain topology updates?”. A strongly consistent store makes those failure modes easier to reason about.

---

## 6. Rebalancing Without Melting the Database

When ownership changes, moving keys naively causes two disasters:
1. **Cache cold start**: misses spike → DB overload
2. **Network saturation**: migration traffic competes with production traffic

Battle-tested mitigations:
* Limit migration bandwidth and concurrent movers
* Warm the destination node (preload hottest keys)
* Use write-through / write-behind carefully to avoid correctness surprises


---

## 7. Scale by the Numbers

What does "Big" mean?

| Users | QPS | Architecture |
|---|---|---|
| **< 1M** | 10k | **Single Node (MVP)**. Don't overengineer. |
| **1M - 10M** | 100k | **Replicated Cluster**. 3-5 nodes. One primary, read replicas. |
| **10M - 100M**| 1M+ | **Sharded Cluster**. Data partitioned across 50 nodes. |
| **100M+** | 10M+ | **Tiered Federated**. L1 Local + L2 Regional + L3 Global. |

In the next section, we will do a deep dive into the three titans: Memcached, Redis, and Hazelcast.

Those systems are not the “solution” here — they are reference designs. Studying them helps you justify your own choices: event loop vs multi-threading, client-side routing vs internal routing, and AP vs CP semantics.

**[Next: The Core Technologies Deep Dive →](04-core-technologies.md)**

---

## References / Further Reading

* Cache stampede overview + mitigation patterns: https://en.wikipedia.org/wiki/Cache_stampede
* Request coalescing explained as “one lock per cache key”: https://github.com/ZiggyCreatures/FusionCache/discussions/263
* Stampede mitigation examples (stale-while-revalidate, jitter, pre-warm): https://scalardynamic.com/resources/articles/22-the-cache-stampede-problem
* Cache invalidation write-path patterns + lease tokens + commit-before-invalidate: https://www.systemoverflow.com/learn/caching/cache-invalidation/write-path-patterns-write-through-write-behind-and-cache-aside-with-delete-on-write
* Event-driven invalidation patterns (partitioning, idempotency, versions, commit-then-invalidate): https://www.systemoverflow.com/learn/caching/cache-invalidation/event-driven-invalidation-pushing-changes-to-caches-for-strong-freshness
