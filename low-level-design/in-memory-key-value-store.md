---
title: "LLD Walkthrough: Design an In-Memory Key-Value Store (the 45-minute way)"
series: "Low-Level Design Interview Playbook"
readingTime: "~24 minutes"
difficulty: Advanced
date: 2026-07-10
topics: ["Low-Level Design", "Key-Value Store", "TTL", "Transactions", "Concurrency", "Redis", "Dynamo"]
---

# LLD Walkthrough: Design an In-Memory Key-Value Store

> Self-contained walkthrough. It shows how to design an in-memory key-value store with TTL and simple transactions without accidentally designing a database kernel.

This prompt is dangerous because it sounds small and then invites every database topic: MVCC, WAL, compaction, snapshot isolation, distributed consensus, range indexes, replication. Do not take the bait.

Say this out loud:

> "I will build a single-process in-memory store with `get/put/delete`, TTL, and simple transactions over touched keys. I will name stronger database features as extensions, not implement them live."

That is the senior move: concrete core, bounded database vocabulary.

---

## Minute 0-7: Clarify and fence the scope

Ask questions that prevent database sprawl:

- **Data model?** → String keys, opaque values/bytes or generic values.
- **Operations?** → `get`, `put`, `delete`, `begin`, `commit`, `rollback`.
- **TTL?** → Optional TTL per key; expired keys behave as missing.
- **Transactions?** → Single-process, single-store transactions; no distributed transactions.
- **Isolation?** → Read-your-writes inside a transaction; simple committed view outside.
- **Persistence?** → Out of scope unless asked.
- **Concurrency?** → Concurrent clients possible; start with simple locking.

Say the fence out loud:

> "In scope: an in-memory map-backed store, optional TTL, lazy expiry on read, and simple transactions using a write-set or undo log. Out of scope: disk durability, replication, range scans, SQL, and full serializable MVCC."

Be explicit about transaction semantics:

> "A transaction buffers writes until commit. Reads inside the transaction see their own writes first, then the committed store."

That is understandable, testable, and not a dissertation.

---

## Minute 7-13: Core entities

List the objects. Keep it small. The map is the data structure; transactions are the behavior seam.

| Object | Responsibility (one line) |
|---|---|
| `Store<K,V>` | Public interface for key-value operations and transaction creation. |
| `InMemoryStore<K,V>` | Owns the committed map, lock, clock, and expiry behavior. |
| `Entry<V>` | Holds value plus optional expiry timestamp. |
| `Transaction<K,V>` | Buffers reads/writes and commits or rolls back as one unit. |
| `WriteSet<K,V>` | Tracks pending puts and deletes for a transaction. |
| `ExpiryPolicy` | Determines expiry timestamps and whether entries are expired. |
| `ExpirySweeper` | Optional background cleanup seam; correctness does not depend on it. |
| `Clock` | Supplies time for TTL and deterministic tests. |

Eight objects. No `Database`, `Table`, `Page`, `Segment`, or `QueryPlanner`. This is a key-value store.

```mermaid
classDiagram
    class Store {
        <<interface>>
    }
    class InMemoryStore
    class Entry
    class Transaction
    class WriteSet
    class ExpirySweeper
    class Clock
    Store <|.. InMemoryStore
    InMemoryStore --> Entry
    InMemoryStore --> Clock
    InMemoryStore --> ExpirySweeper
    Transaction --> WriteSet
    Transaction --> InMemoryStore
```

State the main invariant:

> "The committed map only contains the latest committed value for a key; a transaction's write-set shadows that map until commit."

Then stop. Do not invent storage pages.

---

## Minute 13-20: The spine (API + varying interfaces)

Define the outside API:

```text
interface Store<K, V> {
  Optional<V> get(K key)
  void put(K key, V value)
  void put(K key, V value, Duration ttl)
  boolean delete(K key)
  Transaction<K,V> begin()
}
```

Transaction API:

```text
interface Transaction<K, V> {
  Optional<V> get(K key)
  void put(K key, V value)
  void put(K key, V value, Duration ttl)
  boolean delete(K key)
  void commit()
  void rollback()
}
```

Behavior that varies goes behind seams:

```text
interface ExpiryPolicy<V> {
  Instant expiresAt(Duration ttl, Clock clock)
  boolean isExpired(Entry<V> entry, Instant now)
}

interface ExpirySweeper {
  void start()
  void stop()
}
```

The expiry mechanism is deliberately boring:

- lazy expiry on `get` is required;
- background sweeping is optional;
- expired means "behaves as absent."

For transactions, keep the implementation simple:

```text
WriteSet:
  puts: Map<K, Entry<V>>
  deletes: Set<K>
```

This is copy-on-write for touched keys. You are not copying the whole store.

Say this out loud:

> "I am using a write-set transaction: reads check pending writes/deletes first, and commit applies the write-set under the store lock."

That is the whole transaction algorithm for this scope.

---

## Minute 20-33: Walk the happy path

First walk plain `put` and `get`.

```mermaid
sequenceDiagram
    participant C as Client
    participant S as Store
    participant M as Map
    participant CL as Clock
    C->>S: put("a", "1", ttl)
    S->>CL: now()
    S->>M: store Entry(value, expiresAt)
    C->>S: get("a")
    S->>M: lookup("a")
    S-->>C: "1"
```

Narrate it:

- "`put` computes expiry from `clock.now()` plus TTL."
- "The committed map stores an `Entry`, not the raw value."
- "`get` checks the map, then checks expiry."
- "If expired, it removes the key and returns empty."
- "If live, it returns the value."

Plain operation pseudocode:

```text
put(key, value, ttl):
  lock write
  map[key] = Entry(value, expiresAt(ttl))

get(key):
  lock read-or-write
  entry = map.get(key)
  if entry == null:
    return empty
  if entry.isExpired(clock.now()):
    remove key
    return empty
  return entry.value
```

For lazy expiry, a write lock may be needed during `get` if you physically remove expired entries. Or you can return empty and let a sweeper remove later. Pick one and state it.

Now walk a transaction:

```mermaid
sequenceDiagram
    participant C as Client
    participant T as Txn
    participant WS as WriteSet
    participant S as Store
    participant M as Map
    C->>T: put("a", "2")
    T->>WS: record put
    C->>T: get("a")
    T-->>C: "2"
    C->>T: commit()
    T->>S: apply(writeSet)
    S->>M: upsert "a"
```

Transaction read path:

```text
txn.get(key):
  if writeSet.deletes contains key:
    return empty
  if writeSet.puts contains key:
    return live value from writeSet
  return store.getCommitted(key)
```

Commit path:

```text
commit():
  lock store for write
  for key in deletes:
    map.remove(key)
  for (key, entry) in puts:
    if entry is not expired at commit time:
      map[key] = entry
  mark transaction closed
```

Rollback path:

```text
rollback():
  clear writeSet
  mark transaction closed
```

The important bounded transaction statement:

> "This gives read-your-writes and atomic commit for one in-process store. I am not claiming snapshot isolation or serializable MVCC unless we add version checks."

That honesty scores.

---

## Minute 33-42: Stretch and edges

Common curveballs and bounded answers:

- **"What isolation level is this?"** With a single write lock at commit and reads from committed state plus local write-set, call it read committed with read-your-writes inside a transaction. If we need repeatable reads, add versions and capture a transaction start version. Do not build full MVCC unless asked.

- **"What if two transactions write the same key?"** First cut: commits are serialized by the store write lock; last commit wins. If product needs conflict detection, store per-key versions and fail commit when a touched key changed since transaction start.

- **"How do TTL and transactions interact?"** TTL is evaluated using the transaction's entry expiry. A key written with TTL may expire before commit; on commit, skip expired writes or store them and let read treat them as absent. I would skip them at commit.

- **"Do we need a background sweeper?"** Not for correctness. Lazy expiry on read is enough. A sweeper is an optimization behind `ExpirySweeper` to reclaim memory for cold expired keys.

- **"How do you make it concurrent?"** Start with a read-write lock on the committed map and a single writer lock for commits. Transactions build write-sets without holding the store lock. For higher write throughput, move to per-key locks or versioned optimistic commit.

- **"Can transaction rollback use an undo log instead?"** Yes. For this design, a write-set is simpler because uncommitted changes never touch the committed map. Undo log is better if you apply changes eagerly, which I am not doing.

A tiny state diagram is natural for transaction lifecycle:

```mermaid
stateDiagram-v2
    [*] --> Active
    Active --> Committed: commit()
    Active --> RolledBack: rollback()
    Committed --> [*]
    RolledBack --> [*]
```

Name the edges: negative TTL, zero TTL, deleting a missing key, using a closed transaction, sweeper/get races, and large values when capacity is not part of the prompt.

Anti-patterns to call out:

- "I would not implement a WAL or replication unless persistence is in scope."
- "I would not call this serializable unless I add version checks."
- "I would not copy the entire map per transaction; I copy only touched keys into the write-set."

---

## Minute 42-45: Wrap up

> "The design has a `Store<K,V>` API, an `InMemoryStore` backed by a committed map of `Entry(value, expiry)`, lazy TTL expiry on read, and optional background sweeping behind a seam. Transactions are simple write-sets: reads check local writes/deletes first, commit applies touched keys under the store write lock, and rollback discards the write-set. Concurrency starts with a read-write lock and can evolve to per-key or versioned optimistic commits."

If there is time, name tests: put/get, delete, TTL expiry, read-your-writes, rollback, atomic commit, closed-transaction rejection, and the documented conflict behavior.

That is enough. You built a key-value store, not a pretend database product.

---

## How real systems solve this

Redis is the closest production analogy to the scoped interview design. It executes commands on a single thread, so individual commands are atomic without per-key locking in the command path. It also keeps the data model broader than a raw string map: strings, lists, sets, hashes, and sorted sets all sit behind a key-based API.

Redis TTL behavior is also more nuanced than a toy map. Correctness can rely on lazy expiry when a key is accessed, while active random sampling reclaims cold expired keys in the background. Durability is a separate concern: Redis can persist with RDB snapshots and an append-only file, but the in-memory LLD should keep persistence behind a seam rather than mixing it into `get` and `put`.

Dynamo pushes the same key-value idea into a distributed system. It uses consistent hashing with virtual nodes for distribution and minimal rebalancing, stores N replicas, and lets clients tune quorum reads and writes with the `R + W > N` rule. Concurrent versions are detected with vector clocks and returned as siblings for application reconciliation.

The important interview distinction is that Redis-style command atomicity and Dynamo-style eventual consistency solve different problems. The single-process store needs a map, TTL, and a lock. A distributed store adds partitioning, replication, hinted handoff for temporary failures, and Merkle-tree anti-entropy. Those are real extensions, not changes to the basic `Store<K,V>` API.

## Reference implementation

This Python core shows a thread-safe in-memory store with per-key TTL and lazy expiry on read.

```python
from __future__ import annotations

from dataclasses import dataclass
from threading import RLock
from time import monotonic
from typing import Any

@dataclass(frozen=True)
class Entry:
    value: Any
    expires_at: float | None

class InMemoryKV:
    def __init__(self) -> None:
        self._data: dict[str, Entry] = {}
        self._lock = RLock()

    def put(self, key: str, value: Any, ttl_seconds: float | None = None) -> None:
        if ttl_seconds is not None and ttl_seconds < 0:
            raise ValueError("ttl_seconds must be non-negative")
        expires_at = None if ttl_seconds is None else monotonic() + ttl_seconds
        with self._lock:
            self._data[key] = Entry(value, expires_at)

    def get(self, key: str) -> Any | None:
        with self._lock:
            entry = self._data.get(key)
            if entry is None:
                return None
            if entry.expires_at is not None and entry.expires_at <= monotonic():
                self._data.pop(key, None)
                return None
            return entry.value

    def delete(self, key: str) -> bool:
        with self._lock:
            return self._data.pop(key, None) is not None

    def size(self) -> int:
        with self._lock:
            for key in list(self._data.keys()):
                self.get(key)  # lazy cleanup under re-entrant lock
            return len(self._data)
```

## Complexity and trade-offs

| Operation | Time | Space | Notes |
|---|---:|---:|---|
| `put` | O(1) average | O(1) per key | Stores value plus optional expiry timestamp. |
| `get` live key | O(1) average | O(1) | Checks expiry before returning. |
| `get` expired key | O(1) average | Frees one entry | Lazy expiry removes on access. |
| `delete` | O(1) average | Frees one entry | Idempotent for missing keys. |
| Transaction read from write-set | O(1) average | O(touched keys) | Checks pending deletes/puts before committed map. |
| Commit write-set | O(k) | O(1) extra | Applies k touched keys under the store write lock. |

- Lazy expiry is correct and simple, but cold expired keys can occupy memory until read or sampled by a sweeper.
- A single lock is easy to reason about; per-key locks or optimistic versions only matter after contention is measured.
- Write-set transactions avoid rollback complexity because uncommitted writes never modify the committed map.
- Distributed KV stores add conflict detection and repair; do not imply the in-memory design has Dynamo-style availability.

## Further reading

- [Dynamo: Amazon's Highly Available Key-value Store](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf) — Canonical paper on consistent hashing, quorum reads/writes, vector clocks, hinted handoff, and anti-entropy.
- *Designing Data-Intensive Applications* — Martin Kleppmann — Clear treatment of replication, partitioning, consistency, and log-based storage trade-offs.
- [Redis eviction policies](https://redis.io/docs/latest/develop/reference/eviction/) — Helpful companion for TTL, memory pressure, and key eviction behavior in an in-memory system.

---

## What separated a pass from a fail here

- You fenced the problem before it turned into Redis, RocksDB, or Postgres.
- You modeled TTL as `Entry(value, expiry)` with lazy read cleanup, which is simple and correct.
- You kept transactions bounded with a write-set over touched keys, not a full MVCC engine.
- You named the isolation level honestly instead of overselling it.
- You made concurrency concrete: commits are serialized first, then optimized if needed.

The pass is not "can say MVCC." The pass is "can design the smallest transactional store that actually runs."
