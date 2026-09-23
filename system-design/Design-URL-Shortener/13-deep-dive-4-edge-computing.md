# Article 14: Deep Dive - Edge Computing (The Multi-Region Future)

## The Physics Problem

We have optimized our database, our cache, and our code. But we still have a problem: **The Speed of Light**.

> **Reader path — 5. Deep dives (edge and multi-region):** [Separate scoped walkthrough](../interview-questions/url-shortener.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Production readiness](12-production-readiness.md) → edge trade-offs here → [case studies](14-case-studies.md). This is a geographic-latency expansion of the [working baseline](04-basic-system-design.md).

If our servers are in Virginia (`us-east-1`):
*   User in New York: 10ms latency.
*   User in Tokyo: 150ms latency.
*   User in Sydney: 200ms latency.

No amount of Redis optimization can fix the fact that light takes time to travel fiber optic cables under the ocean.

---

## 1. Moving Logic to the Edge

"Edge Computing" means running code in data centers that are physically close to the user (e.g., Cloudflare Workers, AWS Lambda@Edge).

### The "Edge" Architecture
Instead of:
`User (Tokyo) -> Internet -> Server (Virginia) -> Redis (Virginia)`

We do:
`User (Tokyo) -> Cloudflare Pop (Tokyo) -> KV Store (Tokyo)`

**Result**: 10ms latency for everyone, everywhere.

---

## 2. Implementation with Cloudflare Workers

We can write a tiny Javascript function that handles the redirect logic right at the edge.

```javascript
/* Worker Logic running in 200+ cities */
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const shortCode = url.pathname.slice(1);

    // 1. Check Edge Cache (KV Store)
    const longUrl = await env.URLS.get(shortCode);

    if (longUrl) {
      // 2. Return 301 Immediately (No Origin Hit)
      return Response.redirect(longUrl, 301);
    }

    // 3. Fallback: Hit Origin (Virginia)
    // Only happens on cache miss
    const originResponse = await fetch(`https://api.short.app/${shortCode}`);
    return originResponse;
  }
}
```

---

## 3. The Sync Challenge (Eventual Consistency)

If we create a link in Tokyo, how does it get to the Edge Node in London?

**Cloudflare KV** propagates data globally.
*   **Write**: Takes 100ms to hit the master.
*   **Propagate**: Takes 10-60 seconds to reach all 200 cities.

**Trade-off**:
*   **Redirects**: Extremely fast.
*   **"Read Your Own Write"**: Slower. If I create a link in Tokyo and invite my friend in London to click it *instantly*, it might 404 for him for 60 seconds.
*   **Fix**: Cache-Control headers or "Smart Routing" (sending new links to origin effectively).

---

## Summary
Edge Computing is the "Ferrari" of system design. It creates the ultimate user experience but introduces global consistency challenges.
For a mature URL shortener, moving the "Redirect" path to the Edge is the final optimization step to reach 10ms global latency.
