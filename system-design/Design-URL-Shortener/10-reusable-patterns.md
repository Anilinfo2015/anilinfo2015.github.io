# Article 11: The System Design Toolbox (Reusable Patterns)

## Beyond the URL Shortener

We've built a system that handles billions of clicks. But the real value isn't the URL shortener itself; it's the *patterns* we used to build it.
These are the "Lego Blocks" of scalable systems. If you master these, you can design Youtube, Twitter, or Uber.

> **Reader path — 5. Deep dives (reusable patterns):** [Separate scoped walkthrough](../interview-questions/url-shortener.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Database choices](09-deep-dive-3-dynamodb.md) → patterns here → [security](11-security.md). Select patterns for bottlenecks in the [working baseline](04-basic-system-design.md), rather than treating this list as another design sequence.

---

## 1. The Bloom Filter
**The Problem**: "Is this URL already in our database?"
Checking the database for every single click (100k/sec) is slow and expensive.

**The Pattern**: A probabilistic data structure that tells you:
1.  "Definitely No"
2.  "Maybe Yes"

**How we used it**: Before hitting the DB to check if `custom-alias` is taken, we check a Bloom Filter in memory. If it says "No", we return 200 OK immediately. Zero DB load.

**Where else to use it**:
*   **Web Crawlers**: "Have I already visited this page?"
*   **Username Registration**: "Is 'cool_guy_99' taken?"
*   **CDNs**: "Do I have this file in my cache?"

---

## 2. Consistent Hashing
**The Problem**: We have 10 Redis nodes. We need to store keys. `hash(key) % 10` works fine until Node 5 crashes. Then `hash(key) % 9` changes *every single mapping*. All cache keys become invalid. The database dies.

**The Pattern**: Map both Nodes and Keys to a "Ring" (0 to 360 degrees).
If Node 5 dies, its keys simply "fall forward" to Node 6. The other 8 modes are untouched.

**Where else to use it**:
*   **DynamoDB**: How it partitions data internally.
*   **Cassandra**: How it distributes data rings.
*   **Load Balancers**: Sticking specific users to specific servers.

---

## 3. Write-Back vs Write-Through Caching
**The Problem**: How do we keep the Cache and DB in sync?

| Strategy | Logic | Use Case |
| :--- | :--- | :--- |
| **Cache-Aside** | App checks Cache. If miss, App reads DB, updates Cache. | Most standard apps. |
| **Write-Through** | App writes to Cache. Cache writes to DB synchronously. | User Profiles (Read-your-own-write). |
| **Write-Back** | App writes to Cache. Cache writes to DB *later* (Async). | **Analytics Counters** (Our Use Case). |

**Our Choice**: For Analytics, we used **Write-Back**. We increment the counter in Redis, and flush to Postgres every 10 seconds.
**Risk**: If Redis crashes, we lose 10 seconds of clicks.
**Reward**: We handled 100x more write throughput.

---

## 4. The Circuit Breaker
**The Problem**: The "Analytics Service" is down. The "Redirect Service" calls it, waits 30 seconds for a timeout, and effectively hangs the user.

**The Pattern**: Wrap the call in a "Circuit Breaker".
*   If we see 5 failures in a row...
*   **Trip the Breaker**: Stop calling the service. Fail immediately (or return a fallback).
*   **Cool Down**: Wait 60 seconds.
*   **Half-Open**: Let 1 request through to test if it's back.

**Where else to use it**:
*   Any Microservice architecture.
*   Payment Gateways (PayPal is down -> Switch to Stripe).

---

## 5. Token Bucket (Rate Limiting)
**The Problem**: One user is sending 50,000 requests/sec, acting like a DDoS attack.

**The Pattern**: Everyone gets a "Bucket" of tokens.
*   Bucket holds 10 tokens.
*   Every request costs 1 token.
*   We add 1 token every second (refill rate).
*   If bucket is empty: **429 Too Many Requests**.

**Why it's great**: It allows *bursts*. You can make 10 requests instantly, but then you are throttled to the average rate.

---

## Summary
You don't invent scalable systems from scratch. You assemble them using these verified patterns.
*   Need to filter sets fast? **Bloom Filter**.
*   Need to distribute keys? **Consistent Hashing**.
*   Need to survive downstream failures? **Circuit Breaker**.
*   Need to handle massive writes? **Write-Back Cache**.
