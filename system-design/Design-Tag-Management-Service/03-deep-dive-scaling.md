# Part 3: Deep Dive - Scaling Reads & Writes

## 1. Introduction: Hitting the Wall
Our MVP worked great in development. But at 50,000 writes per second, the single PostgreSQL instance is screaming. CPU is at 100%, and latencies are drifting into seconds.

> **Reader path — 5. Deep dives (partitioning and hot tags):** [Separate scoped walkthrough](../interview-questions/tag-management.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Working baseline](02-basic-system-design.md) → scaling here → [analytics](04-deep-dive-analytics.md). The numbered topics expand stage 5 rather than replace the delivery sequence.

We have two choices: buy a bigger machine (a surprisingly valid option, until it isn't), or **distribute the data**. This article explores how we shard our database to survive the scale, and the painful trade-offs we accept to get there.

---

## 2. The Sharding Dilemma

We need to split our tables across multiple servers. But how do we decide which server gets which data? This decision dictates our system's performance for years.

### Option A: Sharding by Tag ID
"Put all 'Urgent' tags on Server 1."

*   **The Trap**: It sounds logical, but it fails in practice.
    *   **Hot Partitions**: If the "Bug" tag is popular, Server 1 melts down while Server 2 is idle.
    *   **The "Scatter-Gather" Problem**: Loading a Jira issue (FR3) is the most common operation. An issue has 5 tags. If those tags are on 5 different servers, we have to query *all of them* just to show one page. This kills performance.

**Verdict**: ❌ Rejected. The Scatter-Gather penalty on the critical path is too high.

---

## 3. Option B: Sharding by Content ID (Recommended)
"Put all tags for 'Issue-123' on Server 1."

This approach groups data by the *parent entity*.

*   **Why it wins**:
    *   **Colocation**: When a user loads Issue-123, we go to Server 1 and get *everything*. One query, one server. Fast.
    *   **Isolation**: A viral tag doesn't create a hot partition, because the specific *links* to that tag are spread across millions of content items (and thus millions of shards).
*   **The Price**:
    *   **Search is Hard**: "Show me all content with Tag 'Bug'". Now, *that* data is everywhere. We have to search every shard.
    *   *The Fix*: We accept that the primary DB is bad at search. We'll solve FR4 with a dedicated Search Index (Elasticsearch) later.

```mermaid
graph TD
    API[Tag Service] --> Router
    Router -->|hash(content_id)| Shard1[DB Shard 1]
    Router -->|hash(content_id)| Shard2[DB Shard 2]
    Router -->|...| ShardN[DB Shard N]

    Shard1 -- Async Replication --> SearchIndex[Search Service / ES]
    Shard2 -- Async Replication --> SearchIndex
    ShardN -- Async Replication --> SearchIndex
```

---

## 4. The "Justin Bieber" Problem: Viral Tags

What happens when a tag like `#superbowl` or `#bug` gets associated with 50 million items?

### The Challenge
1.  **Infinite Lists**: You cannot store 50 million IDs in a single database row or Redis key.
2.  **Write Hotspots**: 10,000 writes/sec to the "Superbowl" index entry will lock the database.

### The Solution: Time-Based Partitioning & Truncation
We don't store one giant list. We slice it.

*   **Twitter's Strategy (Time Buckets)**: In our Search Index, we don't just index by `TagID`. We index by `TagID_TimeBucket`.
    *   `#superbowl_2026_01_24_10am`
    *   `#superbowl_2026_01_24_11am`
    *   Writes are spread across different buckets over time.
    *   Reads merge the most recent buckets.

*   **Posting List Truncation (Instagram)**:
    *   For the "Hot Cache" (Redis), we usually only need the *most recent* 1,000 items.
    *   We store a capped list: `if list.size > 1000: pop_tail()`.
    *   Accessing item #50,001 is a slow path that hits "Cold Storage" (S3/HDFS), because almost nobody scrolls that far.

---

## 5. Feature Check: Merging & Renaming Tags

"We need to merge #bug and #defect." This sounds simple, but rewriting 10 million rows is a system-killer.

### The "Alias" Pattern (Zero Downtime)
We borrow a page from Wikipedia's redirects.

1.  **The Alias Table**: We add a `target_id` column to our `TAG` table.
    *   `Tag A`: {id: 1, name: "bug", target_id: NULL}
    *   `Tag B`: {id: 2, name: "defect", target_id: 1} ("defect" redirects to "bug")
2.  **Read-Time Resolution**:
    *   User searches for "defect".
    *   System sees `target_id: 1`.
    *   System transparently executes search for "bug".
3.  **Async Migration**:
    *   A background worker slowly (over days) finds all content linked to ID 2 and changes it to ID 1.
    *   Once done, Tag B is hard-deleted.

---

## 6. Advanced Caching Strategies

To hit < 200ms latency, we cannot hit the DB for every read.

### 4.1 Two-Layer Cache
1.  **L1 (Local Memory)**: Tiny, short-lived cache (seconds) for super-hot metadata.
2.  **L2 (Redis Cluster)**: Partitioned Redis cluster.

### 4.2 Handling Thundering Herds
When a popular page loads, 10,000 users might request `GET /content/abc/tags` simultaneously. If the cache expires, they all crash the DB.

**Solutions:**
1.  **Request Coalescing**: The application server queues identical requests and fires only one to the backend.
2.  **Probabilistic Early Expiration**:
    ```python
    if (ttl < random_gap + compute_time):
        trigger_refresh_async()
    return cached_value
    ```

---

## 7. Scaling Summary
By combining **Content-ID Sharding** (for writes and lookups) with a **Dedicated Search Index** (for tag queries) and **Multi-layer Caching**, we can meet the 100k QPS read and 50k QPS write targets.
