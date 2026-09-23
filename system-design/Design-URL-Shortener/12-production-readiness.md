# Article 13: Production Readiness (SRE)

## The Sleep-Well Architecture

You can have the best architecture on paper, but if it wakes you up at 3 AM every night, it's a failure.
"Production Readiness" is about Observability, Alerting, and Disaster Recovery.

> **Reader path — 5. Deep dives (reliability and operations):** [Separate scoped walkthrough](../interview-questions/url-shortener.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Security](11-security.md) → operational readiness here → [edge computing](13-deep-dive-4-edge-computing.md). Apply these checks to the [working baseline](04-basic-system-design.md) and its selected scaling changes.

---

## 1. Defining SLAs, SLOs, and SLIs

For a URL Shortener, not all requests are created equal.

### The Redirect Service (Critical)
If this is down, Twitter users see 404s. The company loses money.
*   **SLO (Objective)**: 99.99% Availability.
*   **Latency Target**: P99 < 50ms (Redirects must be instant).

### The Analytics Service (Non-Critical)
If this is down, the dashboard is stale. Users probably won't notice for an hour.
*   **SLO (Objective)**: 99.9% Availability.
*   **Latency Target**: P99 < 5 seconds (Dashboards can be slow).

**Key Takeaway**: We alert aggressively on Redirect latency, but we sleep through an Analytics delay.

---

## 2. The 4 Golden Signals
We monitor 4 things:

1.  **Latency**: "How long does a redirect take?"
    *   *Alert*: If P99 > 200ms for 5 minutes.
2.  **Traffic**: "How many requests/sec?"
    *   *Alert*: If Traffic drops to 0 (Global Outage).
    *   *Alert*: If Traffic spikes 10x (DDoS or Viral).
3.  **Errors**: "How many 500s?"
    *   *Alert*: If > 1% of requests fail.
4.  **Saturation**: "How full is the CPU/RAM?"
    *   *Alert*: If Redis Memory > 80%.

---

## 3. Deployment Strategy (Canary)

We never deploy to 100% of servers at once.

**The Canary Rollout**:
1.  Deploy new code to **1 Server** (The Canary).
2.  Route 1% of traffic to Canary.
3.  Wait 5 minutes.
4.  Check: Did Error Rate spike? Did Latency increase?
5.  If Green: Deploy to remaining 99 servers.
6.  If Red: **Auto-Rollback**.

---

## 4. Disaster Recovery (The "Oh No" Button)

**Scenario 1: Redis Crash**
*   **Impact**: Redirects become slow (DB hit), but they *still work*.
*   **Plan**: Auto-restart Redis. The system absorbs the load using the Postgres Read Replicas (Article 5).

**Scenario 2: Primary DB Crash**
*   **Impact**: Writes (Creating links) fail. Reads (Redirects) still work!
*   **Plan**: Auto-promote Read Replica to Primary. (30 seconds downtime for writes, 0 downtime for reads).

**Scenario 3: Region Outage (us-east-1 goes down)**
*   **Impact**: Everything in US East is dead.
*   **Plan**: Route DNS to `eu-west-1` (Global Tables ensure data is there).

---

## Summary
A Senior Engineer doesn't just build features; they build **safety nets**.
By splitting our SLAs (Critical vs Non-Critical) and automating our Rollouts, we ensure reliability without burnout.
