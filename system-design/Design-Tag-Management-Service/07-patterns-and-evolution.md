# Part 7: Future Proofing & Patterns

## 1. Reusable Design Patterns

The architecture we've built uses standard patterns. Memorize these; they appear in almost every system design interview.

> **Reader path — 5. Deep dives (patterns and evolution):** [Separate scoped walkthrough](../interview-questions/tag-management.html#deep-dives) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Security and operations](06-security-and-ops.md) → optional evolution here → [requirements recap](01-requirements-and-domain.md). Roadmap phases extend the [working baseline](02-basic-system-design.md), not the framework's five delivery stages.

1.  **The "Sharding by Affinity" Pattern** (What we used for Tags):
    *   *The Concept*: Group data by its parent (User, Post, Issue) to make the read-path fast.
    *   *Where to use it*: Chat apps (Messages by Thread), Comments (Comments by Post).

2.  **The "CQRS" Pattern** (Command Query Responsibility Segregation):
    *   *The Concept*: Use a database for writing (Postgres) and a different specialized system for reading (Elasticsearch/Redis).
    *   *Where to use it*: Any system with complex search requirements (Hotels, E-commerce).

3.  **The "Hybrid Compute" Pattern**:
    *   *The Concept*: Do the simple stuff consistently (DB). Do the hard math asynchronously (Streams).
    *   *Where to use it*: View counts, "Who viewed your profile", Rate limiting.

---

## 2. Evolution Roadmap

No system is static. How does this platform look in 3 years?

### Phase 1: The "Active-Passive" Safety Net
*   *Problem*: "What if the entire US-East region goes offline due to a hurricane?"
*   *Solution*: We replicate all data to `US-West` asynchronously. If East dies, we flip the switch. We accept 5 minutes of data loss for survival.

### Phase 2: The "Active-Active" Global Scale
*   *Problem*: "Users in Europe complain about latency."
*   *Solution*: We accept writes in both EU and US.
    *   *The Challenge*: Conflict. What if I edit a tag in US while you delete it in EU?
    *   *The Resolution*: **Last-Writer-Wins (LWW)** using timestamps. For tags, simplicity beats perfect consistency.

### Phase 3: The GraphQL Federation
*   *Problem*: Frontend teams hate making 5 API calls ("Get Issue", "Get Tags", "Get Author").
*   *Solution*: We wrap our Tag Service in a generic GraphQL Federation layer. Now the frontend makes one query, and the graph layer stitches the data together.

---

## 3. Summary: What We Built

We didn't just build a "Tagging Service". We built a system that balances multiple conflicting forces:
*   We chose **Sharding by Content** to optimize typical loading times, at the cost of Search complexity.
*   We chose **Async Analytics** to protect our database from heavy math.
*   We chose **Eventual Consistency** for search to keep writes fast.

This is the essence of System Design: **Picking your pain** to satisfy your users.
