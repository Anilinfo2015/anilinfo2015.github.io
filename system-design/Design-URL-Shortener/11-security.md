# Article 12: Security & Abuse Prevention

## The Dark Side of URL Shorteners

Building the system is half the battle. Protecting it is the other half.

> **Reader path — 5. Deep dives (security):** [Separate scoped walkthrough](../interview-questions/url-shortener.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Patterns](10-reusable-patterns.md) → abuse prevention here → [production readiness](12-production-readiness.md). This expands the trust boundaries of the [working baseline](04-basic-system-design.md).

URL Shorteners are a favorite tool for attackers. Why?
*   **Phishing**: `short.app/login` looks safer than `attacker.com/steal-creds`.
*   **Malware**: `short.app/update` hides `virus.exe`.
*   **Spam**: Sending 100k SMS messages with a short link is cheap.

If we don't handle this, our domain will be blacklisted by Gmail, Outlook, and Twitter within a week.

---

## 1. Malicious Content Detection

We cannot blindly redirect users. We are responsible for where we send them.

### Step 1: Sync Filtering (The "No-Fly List")
Before creating a link, we check the domain against a local blacklist.
*   `baddomain.com` -> **403 Forbidden**.
*   `virus-site.net` -> **403 Forbidden**.

### Step 2: Async Scanning (Google Safe Browsing)
We can't scan every URL in real-time (it adds 500ms latency).
Instead, we use our **Async Architecture** (from Article 9).
1.  **User Create**: Return 201 OK immediately.
2.  **Worker**: Pick up the URL.
3.  **Scan**: API call to *Google Safe Browsing* or *VirusTotal*.
4.  **Action**: If malicious, ban the link (mark `is_active=false`).

**The Lag**: There is a 2-second window where the link is live. This is an acceptable trade-off for performance.

---

## 2. Iteration Attacks (Enumeration)

**The Attack**: A competitor writes a script to request `/aaaa`, `/aaab`, `/aaac`... effectively scraping our entire database.
They can find private links, analyze our growth, or clone our data.

### Defense 1: High Entropy
We chose Base62, but if we use a counter (1, 2, 3...), the IDs are predictable.
This is why **Snowflake IDs** or **Randomized Hashing** (Article 7) are superior. Calculating the "Next ID" from `aZb9` is much harder than `1001`.

### Defense 2: Honey Pots
We inject "fake" short codes into the potential ID space. If an IP hits 10 non-existent links in 1 minute, they are scanning. **Ban the IP.**

---

## 3. Rate Limiting (Abuse)

We need multiple layers of Rate Limiting (Token Buckets).

| Layer | Limit | Purpose |
| :--- | :--- | :--- |
| **IP Address** | 100 Creates / hour | Stop Spam Bots. |
| **User Account** | 10,000 Creates / day | Stop Account Takeovers. |
| **Global** | 10,000 Redirs / sec | Stop DDoS hitting the origin. |

**The 429 Strategy**: When a limit is hit, return HTTP 429. Do not burn CPU cycles rendering a "Sorry" page. Just drop the connection or send the header.

---

## 4. The 302 Redirect Trap

**The Vulnerability**: Open Redirects.
If we allow parameters like `short.app/login?redirect=evil.com`, we are vulnerable.
In our design, strict validation of the `long_url` is mandatory.
We only redirect to the URL stored in the DB, never to a URL passed in the query string.

---

## Summary
Security in a URL shortener isn't just about SSL (which is mandatory). It's about **Reputation Management**.
If we allow 1% of links to be malware, valid users will stop clicking.
By implementing Async Scanning and Rate Limiting, we protect both our infrastructure and our users.
