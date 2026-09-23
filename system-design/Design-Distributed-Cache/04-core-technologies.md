# Articles 4-6: Reference Designs (Memcached, Redis, Hazelcast)

**Not a usage guide — a “what to steal” guide.**

If your goal were simply “get a cache working”, you would install Redis and move on.

> **Reader path — 5. Deep dives (reference trade-offs):** [Separate scoped walkthrough](../interview-questions/distributed-cache.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Scaling challenges](03-scaling-challenges.md) → reference designs here → [specialized caching](05-specialized-caching.md). These comparisons expand the [working baseline](02-mvp-architecture.md), not a new framework sequence.

But interviews (and real in-house platforms) often ask for something different: **design a cache service from scratch**.

So this chapter is explicitly *reference-only*: we study how real systems are built so we can borrow their best ideas.

---

## 1. Memcached: The Throughput King
**Reference Idea: Multi-threaded, shared-nothing shards**

If your goal is to serve 1 Billion QPS with the fewest servers possible, Memcached is the answer. It powers Meta (Facebook), Twitter, and Pinterest for a reason.

### The Physics of Speed
Memcached is faster than Redis. Why?
1.  **Multi-Threading**: Memcached uses all 64 cores of a modern server. Redis uses 1 core (mostly).
2.  **Simplicity**: It only supports Strings. No complex parsing, no iteration, no data structure overhead.

| Operation | Memcached Time | Redis Time |
|---|---|---|
| **Parse** | 1μs (ASCII) | 2μs (RESP) |
| **Logic** | 1μs (Hash lookup) | 10-50μs (Queue, Types) |
| **Total** | **~5μs** | **~30μs** |

**IMPACT**: A single Memcached node can handle **500,000+ QPS**.

### What to steal for our from-scratch cache
* **Sharded single-writer model** inside a node: route `key -> shard`, and each shard maintains its own map + eviction policy.
* **Keep server simple**: fewer features means fewer latency cliffs.

### The Scaling Secret: Consistent Hashing
Memcached servers don't know about each other. They provide no clustering. The **Client** does all the work.

**The Problem**: If you use `hash(key) % N_servers`, adding one server changes the result for **99%** of keys. The cache empties instantly.
**The Solution**: **Consistent Hashing** (Ring Topology).
*   Imagine a circle range 0-360.
*   Node A is at 0. Node B is at 120. Node C is at 240.
*   Key `user:1` hashes to 45. It walks clockwise to Node B.
*   **Adding Node D** at 60 only steals keys from 0-60. Keys at 200 are untouched.
*   **Result**: Only **1/N** keys move. The cache stays warm.

---

## 2. Redis: The Swiss Army Knife
**Reference Idea: Event loop + atomic execution model**

Redis is the default choice for 90% of startups. Why? Because it prevents you from writing code.

### The Power of Data Structures
In Memcached, a Timeline is a string. To add a tweet, you must:
1.  GET the timeline (1MB).
2.  Deserialize it.
3.  Add tweet.
4.  Serialize it.
5.  SET it back (1MB).

In Redis, you use a **List**:
`LPUSH timeline:user:1 "tweet:100"`
*   Data sent: 50 bytes.
*   Time taken: 5μs.
*   Concurrency: Safe (atomic).

### What to steal for our from-scratch cache
* **Atomicity model**: one request runs to completion without interleaving; it simplifies correctness dramatically.
* **Avoid chatty protocols**: server-side operations reduce bandwidth and tail latency.

### Clustering: Internal Sharding
Unlike Memcached, Redis Cluster manages itself.
*   **Hash Slots**: The key space is divided into **16,384 slots**.
*   **Topology**: Every node knows which node owns which slot.
*   **Redirects**: If you ask Node A for `user:1`, and Node B owns it, Node A replies: `MOVED 3999 192.168.1.55`.

### Persistence (The Safety Net)
Redis can save to disk.
*   **RDB**: "Snapshot the world every 5 minutes." (Fast restart, some data loss).
*   **AOF**: "Log every write." (Slower, zero data loss).

---

## 3. Hazelcast: The Bank Vault
**Reference Idea: CP semantics when correctness is the product**

Redis and Memcached are **AP** (Available). If the network splits, they keep serving reads, even if they might be stale.
Hazelcast is **CP** (Consistent). If the network splits, it **stops** to prevent a split-brain.

### The Use Case: Swedbank
Swedbank uses Hazelcast for real-time transaction ledgers.
*   **Requirement**: You cannot double-spend money.
*   **Mechanism**: Distributed ACID Transactions.
    1.  Lock Account A.
    2.  Lock Account B.
    3.  Debit A, Credit B.
    4.  Unlock.

### Impact of CP
*   **Latency**: Higher (must wait for Quorum/Majority acknowledgement).
*   **Uptime**: Lower (in a partition, the minority side goes down).
*   **Correctness**: Absolute.

---

## Summary: What These Systems Teach Us

* **Concurrency**: shard within a node or adopt an event-loop model; avoid global locks on the hot path.
* **Routing**: consistent hashing is the pragmatic default; decide client-side vs proxy vs internal routing.
* **Semantics**: caches are usually AP by design, but CP is appropriate when correctness outweighs latency.

**[Next: Specialized Layers (Flash, Edge, L1) →](05-specialized-caching.md)**
