# System Design Bottlenecks: The Enterprise War Stories

This isn't a glossary. We assume you know what a Load Balancer is and what SQL stands for. This document details the specific, painful bottlenecks that only emerge at scale—the ones that wake engineers up at 3 AM.

These are the "War Stories" of distributed systems.

---

## 1. The "Justin Bieber" Effect (Extreme Fan-out)
**The Context:** You built a social network correctly. You used the "Push Model" (Fan-out-on-write) because reads are faster. When a user posts, you write that post ID to all their followers' feed timelines. It worked great for 5 years.

**The Bottleneck:** Then a celebrity (let's say Justin Bieber or Elon Musk) joins. They have 100 million followers.
A single tweet triggers 100 million writes to Redis lists. The "Fan-out" service creates a write storm that clogs the message queue for hours. Normal users' tweets are stuck behind the celebrity event. The site feels broken for everyone right when it's most active.

**The Lesson:**
*   **Uniformity is a Lie:** Data limits that apply to 99.9% of users (max 5k followers) don't apply to the 0.1% (Supernodes).
*   **The Fix:** **Hybrid Architecture**.
    *   **Normal Users:** Push model (Pre-compute feeds).
    *   **Celebrities:** Pull model (Fetch tweets at read-time).
    *   *Real-world example:* Twitter has publicly discussed shifting some work from writes to reads for high-fanout users.

---

## 2. The "Monday Morning" Storm (Thundering Herd)
**The Context:** You have a critical configuration cache or a specialized "Daily Deal" service. The cache TTL is set to 5 minutes.

**The Bottleneck:** At 9:00 AM, traffic spikes. At 9:05:00, the cache key expires.
In that exact millisecond, 10,000 requests arrive.
*   Request 1 checks cache -> miss -> goes to DB.
*   Request 2 checks cache -> miss -> goes to DB.
*   ...
*   Request 10,000 checks cache -> miss -> goes to DB.

The Database, capable of 1,000 QPS, receives 10,000 requests instantly. It crashes. The system reboots, cache is still empty, requests hit DB again. It crashes again. You are in a **death spiral**.

**The Lesson:**
*   **Synchronization is Dangerous:** Aligning expiries is fatal.
*   **The Fix:**
    *   **Jitter:** Add random variation to TTL (e.g., 5 min +/- 30s) so keys don't expire simultaneously.
    *   **Request Coalescing (Singleflight):** If 10,000 requests want key 'X', let the *first* one hit the DB. The other 9,999 wait for that one result.
    *   **Probabilistic Early Expiration:** Refresh the cache *before* it strictly expires.

---

## 3. The "Walmart" Tenant (Hot Partition / Data Skew)
**The Context:** You successfully sharded your SaaS database by `tenant_id`. It seemed logical. All queries are scoped to a tenant.

**The Bottleneck:** One of your customers is a massive enterprise (e.g., Walmart). The other 5,000 customers are small businesses.
*   Shard #1 holds Walmart.
*   Shards #2-#50 hold everyone else.

Shard #1 runs at 95% CPU utilization. The disk I/O is saturated. Shards #2-#50 are idling. You can't just "add more shards" because Walmart is a single tenant on a single shard. The "Shard Key" choice has backed you into a corner.

**The Lesson:**
*   **Laws of Physics:** You cannot fit a whale in a bathtub, no matter how many bathtubs you buy.
*   **The Fix:**
    *   **Virtual Sharding:** Break the large tenant into smaller "logical" buckets.
    *   **Salted Keys:** Append a suffix to the key (walmart_1, walmart_2) to spread their data across physical nodes, then aggregate on read.

---

## 4. The Microservice "Call Stack" (Latency Tail)
**The Context:** You decomposed the monolith. Now, to render the "Order Details" page, Service A calls Service B, which calls C, D, and E.

**The Bottleneck:** The **P99 Latency Multiplication Rule**.
If Service B, C, D, and E each have a 99th percentile latency of 100ms (meaning 1% of calls are slow), and you call them sequentially:
*   Your chance of hitting a slow request is no longer 1%. It compounds.
*   Total Latency = Latency(A) + Latency(B) + ... + Network Hops.
*   A 50ms average service creates a 2-second experience because one dependency stalled.

**The Lesson:**
*   **Dependencies define your floor:** You are only as fast as your slowest synchronous call.
*   **The Fix:**
    *   **Fan-out Parallelism:** Call B, C, D, E in parallel.
    *   **Hedging Requests:** Send the same request to two different replicas; use the one that replies first.
    *   **Timeout & Fallback:** If Service D takes >200ms, return "shipping info unavailable" instead of blocking the whole page.

---
## 5. The TCP Port Exhaustion (Connection Limits)
**The Context:** Your load balancer is robust. Your backend servers are powerful (64-core, 256GB RAM). You decide to open a new connection for every HTTP request because "connections are cheap."

**The Bottleneck:** Suddenly, the server throws "Address already in use" errors, even though RAM is free.
You ran out of **Ephemeral Ports**. On Linux, the default ephemeral port range is typically `32768-60999` (configurable).
If you open and close connections rapidly, ports can be tied up in states like `TIME_WAIT`, which caps outbound connection churn.

**The Lesson:**
*   **Network is not infinite:** TCP handshake overhead and port limits are hard constraints.
*   **The Fix:**
    *   **Connection Pooling:** Reuse existing TCP connections (Keep-Alive).
    *   **Local Port Range Expansion:** Allow a wider range of ephemeral ports.
    *   **Layer 4 vs Layer 7:** Understand where connections are terminated.

---

## 6. The "Split-Brain" Transaction (Network Partition)
**The Context:** You need strong consistency (e.g., a payment ledger). You run a primary DB in US-East and a standby in US-West.

**The Bottleneck:** The fiber optic cable between East and West gets cut (this happens).
*   US-East thinks: "I'm the leader."
*   US-West thinks: "I can't see the leader. I must become the leader." (Automatic Failover).

Now you have **two leaders**.
*   User A deposits $100 in US-East.
*   User B withdraws $100 in US-West.
*   The network heals. The databases try to sync. Who is right? You have corrupted the ledger. Money has been created out of thin air.

**The Lesson:**
*   **CAP Theorem is law:** You cannot have Consistency and High Availability effectively during a Partition.
*   **The Fix:**
    *   **Fencing Tokens:** If a new leader is elected, the old leader must be "fenced" (cut off) so it cannot accept writes.
    *   **Quorums:** Writes require acknowledgement from (N/2 + 1) nodes. If partitioned, the minority side simply stops working (sacrifices Availability for Consistency).

---

## 7. The Blob in the Database (Storage I/O)
**The Context:** "It's just a small profile picture." You decide to store user avatars as VARBINARY or BLOBs directly in the SQL Users table.

**The Bottleneck:**
The database engine is optimized for structured data (rows, B-Trees). It expects to keep "hot" pages in RAM.
When you mix 5MB JPEGs into the rows:
1.  **Buffer Pool Pollution:** Loading a user's metadata drags megabytes of image data into RAM, evicting useful index pages.
2.  **Backup/Restore Agony:** Your DB size balloons from 50GB to 5TB. Backups take days instead of hours.
3.  **Replication Lag:** Sending huge BLOBs over the wire slows down the replication stream for everyone.

**The Lesson:**
*   **Right Tool for the Job:** Databases are for relationships. Object Stores (S3) are for blobs.
*   **The Fix:** Store the image in S3/Blob Storage. Store only the URL (string) in the database.

---

## 8. The Metric Explosion (Cardinality)
**The Context:** You are logging metrics to Prometheus/Datadog. You decide to track http latency.
You add a tag: status_code. Good.
You add a tag: endpoint. Good (/api/v1/user).
Then an engineer adds a tag: user_id.

**The Bottleneck:**
Metrics systems are Time Series Databases (TSDB). They index every unique combination of tags.
If you have 1 million users, you just created **1 million new time series**.
Your TSDB explodes. Querying "average latency" now requires aggregating 1 million lines. The dashboard times out. The monitoring bill arrives, and it's higher than the infrastructure bill.

**The Lesson:**
*   **Cardinality Kills Observability:** Never put unbounded values (User IDs, Request IDs, Emails) into metric tags.
*   **The Fix:** Use Logs for high-cardinality data. Use Metrics for low-cardinality aggregates.

---

## Conclusion
System design isn't about memorizing diagrams. It's about predicting where the cracks will form. When in doubt, ask: **"What happens if this input grows 100x?"**

---

## Sources
- Fan-out and high-follower users (shifting some work from writes to reads for high-fanout accounts): https://highscalability.com/the-architecture-twitter-uses-to-deal-with-150m-active-users/
- Linux ephemeral port range defaults (`ip_local_port_range`) and related TCP sysctls: https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt
- Prometheus guidance on label cardinality (“Do not overuse labels”): https://prometheus.io/docs/practices/instrumentation/
- Practical guidance on high-cardinality metrics in Prometheus/Kubernetes: https://grafana.com/blog/how-to-manage-high-cardinality-metrics-in-prometheus-and-kubernetes/
- SQL Server guidance on moving BLOBs out of the main database server (RBS motivation): https://learn.microsoft.com/en-us/sql/relational-databases/blob/remote-blob-store-rbs-sql-server?view=sql-server-ver17
