# Article 10: Deep Dive - Database Choice (SQL vs NoSQL)

## The Scaling Wall

In the previous system design steps, we started with PostgreSQL. It’s a great choice for reliable, relational data. But as we scale to billions of URLs, we hit a wall.

> **Reader path — 5. Deep dives (database choice):** [Separate scoped walkthrough](../interview-questions/url-shortener.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Asynchronous processing](08-deep-dive-2-async-everything.md) → storage trade-offs here → [reusable patterns](10-reusable-patterns.md). Evaluate these alternatives against the [working baseline](04-basic-system-design.md).

**The PostgreSQL Problem:**
1.  **Writes**: A single Primary node can only handle ~5,000 writes/second.
2.  **Sharding**: To go beyond that, we have to "shard" (split) the database.
    *   Shard 1: URLs starting with A-M.
    *   Shard 2: URLs starting with N-Z.
    *   **Operational Nightmare**: What if Shard 1 fills up? Resharding involves moving terabytes of data while the system is live. It requires a team of DBAs.

## Enter NoSQL and DynamoDB

For a URL shortener, our data model is incredibly simple: **Key-Value**.
*   **Key**: `abc1234`
*   **Value**: `{ long_url: "...", owner: "user1" }`

 We don't need complex JOINs. We don't need huge transactions. We just need to read and write keys fast. This is the perfect use case for NoSQL.

---

## 1. Why DynamoDB?

DynamoDB is AWS's managed NoSQL database. It solves the "Operational Nightmare" of sharding.

*   **Infinite Scaling**: Under the hood, DynamoDB shards itself. If you write more, it splits partitions automatically. It can handle 10 TPS or 10,000,000 TPS.
*   **Serverless**: No servers to patch. No backups to manage (Point-in-Time Recovery is a checkbox).
*   **Consistent Performance**: It guarantees single-digit millisecond latency at any scale.

### The Cost Equation
"Is DynamoDB expensive?"
It can be, if you use it wrong. But for a URL shortener, it's often cheaper than a cluster of Postgres servers.

*   **Postgres Cluster**: 3 dedicated servers (Master + 2 Replicas) = **$500/mo** minimum.
*   **DynamoDB**: Pay per request.
    *   10M reads/month: **$1.30**
    *   Storage: **$0.25/GB**
    *   For a startup, DynamoDB is often effectively **free**.

---

## 2. Schema Design (Single Table)

In NoSQL, we design for *access patterns*, not for data purity.

**Table Name**: `Urls`

| Partition Key (PK) | Attributes |
| :--- | :--- |
| `short_code` (String) | `long_url`, `created_at`, `user_id`, `clicks` |

### Access Pattern 1: Redirect (Read)
*   **Query**: `GetItem(PK="abc1234")`
*   **Speed**: 2ms.
*   **Cost**: 1 Read Unit.

### Access Pattern 2: "My Links" (Query)
We need to see all links belonging to `user_1`.
Since DynamoDB partitions by `short_code`, we can't efficiently query by `user_id` without an index.

**Global Secondary Index (GSI)**:
*   **PK**: `user_id`
*   **Sort Key**: `created_at`

Now we can say: "Give me the last 10 links for `user_1`".

---

## 3. Handling Concurrency

**The Counter Problem**:
If 100 people click a link at the same time, we need to increment `clicks`.
*   **Bad**: Read `clicks=10`, generic code adds 1, write `clicks=11`. (100 writes fight, 99 fail).
*   **Good**: Atomic Updates.
    `UPDATE Urls SET clicks = clicks + 1 WHERE short_code = 'abc'`
    DynamoDB supports atomic counters. It handles the locking internally.

---

## 4. DynamoDB vs Redis vs Postgres

| Feature | Redis (Cache) | Postgres (SQL) | DynamoDB (NoSQL) |
| :--- | :--- | :--- | :--- |
| **Speed** | 0.5ms (RAM) | 5-10ms (Disk) | 2-5ms (SSD) |
| **Durability** | Low (Volatile) | High | High |
| **Scaling** | Cluster (Hard) | Sharding (Very Hard) | Auto (Easy) |
| **Cost** | High ($/GB) | Medium | Usage-based |

**The Winning Architecture**:
*   **Redis** for the "Hot" links (top 20%).
*   **DynamoDB** as the durable "Source of Truth" for all links.
*   **Postgres**: Not used (or strictly for User/Billing data, not high-volume links).

---

## Summary
By choosing DynamoDB, we effectively outsourced the hardest problem in distributed systems: **Database Sharding**. 

We trade "SQL Flexibility" (which we didn't need anyway) for "Operational Peace of Mind".
