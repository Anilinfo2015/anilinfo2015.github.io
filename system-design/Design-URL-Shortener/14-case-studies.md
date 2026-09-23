# Article 15: Case Studies - Bitly, TinyURL, & Twitter

## Learning from the Giants

We have designed our system. Now let's look at how the real-world giants solved these problems.

> **Reader path — 5. Deep dives (comparative trade-offs):** [Separate scoped walkthrough](../interview-questions/url-shortener.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Edge computing](13-deep-dive-4-edge-computing.md) → case studies here → [deployment](15-deployment-guide.md). Use these comparisons after the [working baseline](04-basic-system-design.md), not as additional framework stages.

---

## 1. Bitly (The Enterprise Analytics Platform)

Bitly isn't just a URL shortener; it's a **Marketing Analytics Platform**.
Companies pay Bitly not to "shorten" links, but to know *who clicked them*.

### Architecture Highlights
*   **Database**: They migrated from **MySQL** to **HBase** (Hadoop) to handle billions of writes.
*   **Queues**: Heavily reliant on **Kafka** (Pipe data to Hadoop, to Real-time dashboards, to billing).
*   **Lesson**: If "Data" is your product, your architecture must be "Start with Queue". Every click is an event.

---

## 2. TinyURL (The Simple Monolith)

TinyURL was the first. It ran for years on a very simple **LAMP Stack** (Linux, Apache, MySQL, PHP).

### Architecture Highlights (Classic)
*   **Database**: A massive, sharded MySQL setup.
*   **ID Generation**: They used the `Note.id` approach (Auto-Increment) in the early days.
*   **Lesson**: You don't always need Microservices. A well-tuned Monolith with a giant database can get you to millions of users.

---

## 3. Twitter (t.co) (The Security Gate)

Every link on Twitter is converted to `t.co`.
**Why?** Not to save characters (Twitter counts links as 23 chars regardless).
**Reason**: To protect users from Malware.

### Architecture Highlights
*   **The "Middleman" Strategy**: When you click a `t.co` link, you don't go to the destination. You go to Twitter's servers.
*   **Async Scanning**: Twitter scans the destination payload. If it detects a Phishing scam, it shows a "Warning: Unsafe Link" page instead of redirecting.
*   **Lesson**: A URL Shortener can be a firewall for the internet.

---

## Summary
*   **Bitly** optimizes for **Writes (Analytics)**.
*   **TinyURL** optimizes for **Simplicity**.
*   **Twitter** optimizes for **Safety**.

Your architecture depends on your business goal.
