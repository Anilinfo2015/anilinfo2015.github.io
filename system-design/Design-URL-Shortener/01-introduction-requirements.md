# URL Shortener: Requirements

## Introduction: What is a URL Shortener?

A URL shortener is a service that converts long URLs into short aliases and redirects users when they click the alias.

> **Reader path — 1. Requirements:** [Separate scoped walkthrough](../interview-questions/url-shortener.html#requirements) · [HLD template](../interview-template.html). Its assumptions and contracts may differ from this series.
>
> **Series order:** requirements → [core entities](02-core-entities-components.md) → [API](03-api-design.md) → [working baseline](04-basic-system-design.md) → [deep dives](05-basic-design-details-tradeoffs.md). Article numbers identify chapters, not additional framework stages.

**Example**:
```
Long URL:  https://blog.example.com/posts/2024/01/15/system-design-interview-guide
Short URL: https://short.app/abc123
```

When a user clicks `short.app/abc123`, they're instantly redirected to the long URL.

### Why Build This?

URL shorteners are ubiquitous (Bitly, TinyURL, goo.gl) but the engineering is non-trivial:

1. **Massive read-write skew**: 99% redirects (reads), 1% link creation (writes)
2. **Global scale**: Billions of URLs, millions of users worldwide
3. **Extreme latency sensitivity**: Users expect instant redirects (<100ms)
4. **Diverse trade-offs**: Cost vs. consistency vs. reliability

## 1. Requirements

### Functional Requirements

**R1: Create Short Link**
```
User submits long URL → System generates short code → Returns short URL
Example: POST /links → returns {short_url: "short.app/abc123"}
```

**R2: Redirect to Long URL**
```
User clicks short URL → System retrieves long URL → HTTP 301 redirect
Example: GET /abc123 → redirects to original URL
```

**R3: Custom Short Codes**
```
Premium users can choose short codes
Example: POST /links with {custom_code: "my-campaign"}
```

**R4: Link Deletion**
```
Users can delete their links (soft delete)
Example: DELETE /links/abc123 → returns 204 No Content
```

**R5: Link Listing**
```
Users see all their created links
Example: GET /my-links → returns list with pagination
```

### Non-Functional Requirements

#### Performance (Speed)

```
Redirect Latency:
  ├─ p50 (median): 20ms
  ├─ p99: 100ms
  └─ p999: 500ms

Create Link Latency:
  ├─ p50: 50ms
  ├─ p99: 200ms
  └─ p999: 1s
```

**Why these numbers?**
- Global users experience 50-150ms network latency alone
- Database query adds 10-100ms
- Caching brings down to acceptable range

#### Availability (Uptime)

```
SLA: 99.9% uptime
  = 43 minutes downtime per month
  = 86 seconds downtime per day

Means:
  ├─ System continues during failures
  ├─ Automatic failover (< 60 seconds)
  ├─ No single point of failure
  └─ Multi-region redundancy
```

#### Throughput (Scale)

```
Traffic Profile (5-year projection):

Year 1: 1M URLs, 10M daily redirects = 115 RPS peak
Year 2: 10M URLs, 50M daily redirects = 580 RPS peak
Year 3: 100M URLs, 100M daily redirects = 1,160 RPS peak
Year 5: 1B URLs, 500M daily redirects = 5,800 RPS peak

For this guide, we'll design for Year 2: 580 RPS (with caching reduces to 50 RPS on database)
```

#### Consistency (Data Correctness)

```
Strong Consistency Requirements:
  ├─ User creates link → Immediately retrievable (no stale reads)
  ├─ User deletes link → Immediately returns 404 (no ghost redirects)
  └─ No user should see another user's links

Eventual Consistency OK for:
  ├─ Analytics/statistics
  ├─ Link popularity ranking
  └─ Admin dashboard updates
```

#### Durability (Data Loss)

```
Guarantee: Zero URL losses
  ├─ Multi-region replication (3 copies minimum)
  ├─ Automated backups (point-in-time recovery)
  └─ No single failure causes data loss

Recovery Time Objective (RTO):
  ├─ System unavailable: < 5 minutes
  └─ Data recovery: < 1 hour

Recovery Point Objective (RPO):
  ├─ Data loss: < 1 minute
  └─ Acceptable because links can be recreated
```

### Requirements Summary Table

| Requirement | Details | Notes |
|---|---|---|
| **Create Links** | User provides long URL, gets short code | Idempotent, optional custom code |
| **Redirect** | User clicks short code, redirected to long URL | <100ms p99 latency |
| **Delete** | User soft-deletes their links | Cascade delete if needed |
| **List Links** | Users see their own links with pagination | Sorted by creation date |
| **Availability** | 99.9% uptime SLA | <5 min failover time |
| **Throughput** | 580 RPS peak (year 2) | 1B URLs, 500M daily redirects (year 5) |
| **Latency** | 20ms p50, 100ms p99 | p999 acceptable up to 500ms |
| **Durability** | Zero data loss | 3-way replication minimum |
| **Consistency** | Strong for user data | Eventual OK for analytics |
| **Security** | HTTPS, auth, rate limiting | Malware detection, content scanning |
| **Cost** | < $500/month MVP | < $0.0001 per redirect at scale |


<a id="what-were-not-building"></a>
### Scope: What We're NOT Building

To keep scope manageable:

```
Out of scope:
  ├─ Advanced analytics dashboard
  ├─ Link expiration scheduling
  ├─ QR code generation
  ├─ Bulk URL import/export
  ├─ Webhooks/integrations
  └─ Mobile app (API only)

These are premium features, can be added post-MVP
```
