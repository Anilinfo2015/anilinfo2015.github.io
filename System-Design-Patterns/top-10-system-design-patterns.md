# The Canonical 10 System Design Questions

These 10 questions are widely considered the fundamental building blocks of system design interviews. They cover roughly 90% of the concepts used in modern distributed systems. If you master the deep principles behind these, you can mix and match their components to solve almost any other system design problem.

---

## Essential System Design Patterns Catalog

### Data Partitioning & Distribution
| Pattern | 1-Liner |
|:--------|:--------|
| **Consistent Hashing** | Distribute data across nodes with minimal redistribution when nodes join/leave. |
| **Range-Based Sharding** | Partition data by key ranges (e.g., A-M, N-Z) for sequential access patterns. |
| **Hash-Based Sharding** | Partition data by hash of key for uniform distribution across shards. |
| **Geographic Sharding** | Partition data by region to reduce latency and comply with data residency laws. |
| **Directory-Based Sharding** | Use a lookup service to map keys to shards for flexible rebalancing. |

### Caching Patterns
| Pattern | 1-Liner |
|:--------|:--------|
| **Cache-Aside (Lazy Loading)** | App checks cache first; on miss, fetches from DB and populates cache. |
| **Read-Through** | Cache sits in front of DB; cache itself fetches on miss transparently. |
| **Write-Through** | Writes go to cache first, then cache synchronously writes to DB. |
| **Write-Behind (Write-Back)** | Writes go to cache, then asynchronously flushed to DB in batches. |
| **Refresh-Ahead** | Proactively refresh frequently accessed items before they expire. |

### Consistency & Replication
| Pattern | 1-Liner |
|:--------|:--------|
| **Leader-Follower (Master-Slave)** | Single leader handles writes; followers replicate and serve reads. |
| **Multi-Leader (Master-Master)** | Multiple nodes accept writes; conflicts resolved via vector clocks/LWW. |
| **Leaderless (Dynamo-style)** | Any node accepts reads/writes; quorum (R+W>N) ensures consistency. |
| **Quorum Consensus** | Require W writes and R reads where R+W > N for consistency guarantees. |
| **Vector Clocks** | Track causality across distributed nodes to detect/resolve conflicts. |
| **Gossip Protocol** | Nodes randomly exchange state to propagate updates eventually. |

### Distributed Coordination
| Pattern | 1-Liner |
|:--------|:--------|
| **Leader Election** | Elect a single coordinator (via Raft/Paxos/ZooKeeper) for consistency. |
| **Distributed Locking** | Acquire exclusive locks across nodes (Redis Redlock, ZooKeeper, etcd). |
| **Two-Phase Commit (2PC)** | Coordinator asks all to prepare, then commit; guarantees atomicity but blocks. |
| **Saga Pattern** | Chain of local transactions with compensating actions for rollback. |
| **Fencing Tokens** | Monotonic tokens to prevent stale leaders from corrupting data. |

### Messaging & Event-Driven
| Pattern | 1-Liner |
|:--------|:--------|
| **Pub/Sub** | Publishers emit events; subscribers receive based on topic subscriptions. |
| **Message Queue** | Point-to-point delivery with ordering and at-least-once semantics. |
| **Event Sourcing** | Store all state changes as immutable events; rebuild state by replay. |
| **CQRS** | Separate read (Query) and write (Command) models for optimization. |
| **Outbox Pattern** | Write events to DB outbox table, then relay to queue for reliability. |
| **Dead Letter Queue (DLQ)** | Route failed messages to a separate queue for inspection/retry. |

### Resilience & Fault Tolerance
| Pattern | 1-Liner |
|:--------|:--------|
| **Circuit Breaker** | Stop calling failing service; auto-recover after timeout (Fail-Fast). |
| **Bulkhead** | Isolate failures to a subset of resources (thread pools, connections). |
| **Retry with Exponential Backoff** | Retry failed requests with increasing delays to avoid thundering herd. |
| **Timeout** | Set max wait time for operations to prevent resource exhaustion. |
| **Fallback** | Provide degraded functionality when primary service fails. |
| **Rate Limiting** | Throttle requests to protect services (Token Bucket, Sliding Window). |
| **Backpressure** | Signal upstream to slow down when downstream is overwhelmed. |
| **Idempotency** | Design operations to be safely retryable (idempotency keys). |

### Data Structures for Scale
| Pattern | 1-Liner |
|:--------|:--------|
| **Bloom Filter** | Probabilistic set membership; false positives possible, no false negatives. |
| **Count-Min Sketch** | Probabilistic frequency estimation with bounded error. |
| **HyperLogLog** | Estimate cardinality (unique counts) with minimal memory. |
| **Trie (Prefix Tree)** | Efficient prefix lookups for autocomplete/typeahead. |
| **Inverted Index** | Map terms to documents for full-text search. |
| **LSM Tree** | Write-optimized structure; sequential writes, periodic compaction. |
| **B+ Tree** | Read-optimized index; balanced tree with sorted keys. |
| **Merkle Tree** | Hash tree for efficient data integrity verification and sync. |
| **Quadtree / Geohash** | Spatial indexing for location-based queries. |

### Storage Patterns
| Pattern | 1-Liner |
|:--------|:--------|
| **Write-Ahead Log (WAL)** | Log writes before applying to ensure durability and crash recovery. |
| **Append-Only Log** | Immutable sequential writes for durability; foundation of Kafka. |
| **Chunking / Block Storage** | Split large files into fixed-size blocks for parallel transfer/dedup. |
| **Data Tiering** | Move cold data to cheaper storage (S3 Glacier, HDD vs SSD). |
| **Compaction** | Merge and clean up old data (LSM compaction, log compaction). |

### Communication Patterns
| Pattern | 1-Liner |
|:--------|:--------|
| **Request-Response (REST/RPC)** | Synchronous call-and-wait; simple but couples caller to callee. |
| **Async Messaging** | Fire-and-forget via queues; decouples sender from receiver. |
| **WebSocket** | Persistent bidirectional connection for real-time updates. |
| **Long Polling** | Client polls server; server holds request until data available. |
| **Server-Sent Events (SSE)** | Server pushes updates over persistent HTTP connection (unidirectional). |
| **gRPC / Protobuf** | Binary protocol with schema; efficient for inter-service communication. |

### Deployment & Infrastructure
| Pattern | 1-Liner |
|:--------|:--------|
| **Sidecar** | Co-locate helper container with main service (logging, proxy, TLS). |
| **Service Mesh** | Infrastructure layer for service-to-service communication (Istio, Linkerd). |
| **API Gateway** | Single entry point for routing, auth, rate limiting, and aggregation. |
| **Load Balancer** | Distribute traffic across instances (Round Robin, Least Connections, Consistent Hash). |
| **CDN (Edge Caching)** | Cache static content at edge locations near users. |
| **Blue-Green Deployment** | Two identical environments; switch traffic for zero-downtime deploys. |
| **Canary Release** | Gradually roll out changes to a subset of users before full rollout. |
| **Feature Flags** | Toggle features on/off without deployment. |

### Monitoring & Observability
| Pattern | 1-Liner |
|:--------|:--------|
| **Heartbeat** | Periodic signals to detect node/service liveness. |
| **Health Checks** | Endpoint to report service readiness and health status. |
| **Distributed Tracing** | Track request flow across services (Jaeger, Zipkin, X-Ray). |
| **Metrics Aggregation** | Collect and roll up metrics (Prometheus, StatsD, Datadog). |
| **Centralized Logging** | Aggregate logs from all services (ELK Stack, Splunk). |

---

## Top 10 Prompts & Core Lessons

### 1. The Core Data & Access Patterns
**Questions:** Design a URL Shortener (TinyURL, Bitly)
- **Core Lesson:** Unique ID generation (Collision handling), Hash vs. Counter strategies.
- **Key Trade-offs:** Read-Heavy vs. Write-Heavy optimization.
- **Patterns:** Caching patterns (Cache-Aside, Read-Through), redirection methods (301 vs 302).

### 2. Fan-out & Social Graphs
**Questions:** Design Twitter/X, Instagram Newsfeed
- **Core Lesson:** The **"Fan-out" problem**. Handling millions of followers (hot users) where a single write triggers millions of reads.
- **Key Trade-offs:** Push (Fan-out-on-write) vs. Pull (Fan-out-on-read) models.
- **Patterns:** Hybrid approach for celebrities vs normal users, Relational vs. Graph data modeling.

### 3. Consistency & Storage Models
**Questions:** Design Dropbox / Google Drive
- **Core Lesson:** **ACID & Synchronization**. Unlike social apps (eventual consistency), file sync needs strong consistency and versioning.
- **Key Concepts:** Block-level storage (chunking files), differential sync (rsync), ACID compliance, and Client-side coordination.

### 4. High Volume Content & CDN
**Questions:** Design YouTube / Netflix
- **Core Lesson:** **BLOB Storage & CDN optimization**. Efficiently storing massive static files vs. metadata.
- **Key Concepts:** Adaptive Bitrate Streaming (HLS/DASH), Edge caching, CDN cost optimization, Pre-signed URLs for secure direct uploads.

### 5. Real-Time & Stateful Connections
**Questions:** Design Chat App (WhatsApp/Telegram/Discord)
- **Core Lesson:** **Stateful connections**. Managing long-lived connections in a stateless HTTP world.
- **Key Concepts:** WebSockets vs. Long Polling, "Presence" (Online/Offline status), Message ordering (Sequence IDs), Local storage (SQLite) for offline support.

### 6. Asynchronous Processing
**Questions:** Design a Notification System
- **Core Lesson:** **Decoupling**. Separating the trigger (producer) from the action (consumer).
- **Key Concepts:** Message Queues (Kafka/RabbitMQ), Fan-out patterns (Pub/Sub), Retry mechanisms (Exponential backoff), avoiding "thundering herd".

### 7. Search & Indexing
**Questions:** Design a Search System / Typeahead
- **Core Lesson:** **Sharding & Indexing**. Splitting a massive dataset across machines specifically for precise retrieval (Inverted Index).
- **Key Concepts:** Tries (Prefix trees) for typeahead, Scatter/Gather search architecture, Relevance ranking & scoring.

### 8. Distributed Counting & Throttling
**Questions:** Design an API Rate Limiter
- **Core Lesson:** **Distributed State**. How to count accurately across a cluster without locking databases to death.
- **Key Concepts:** Sliding Window vs. Token Bucket algorithms, Redis Lua scripts for atomicity, handling race conditions in distributed counters.

### 9. Distributed Scheduling
**Questions:** Design a Web Crawler
- **Core Lesson:** **Frontier Management**. Managing a queue of billions of tasks (URLs) that grows dynamically.
- **Key Concepts:** Politeness (rate limiting per domain), Deduplication (Bloom Filters), Handling cycles in graphs, DNS resolution at scale.

## The Missing 10% (Specialized Systems)
While the top 10 cover general web apps, these 3 additional questions test specialized knowledge essential for Fintech, Big Data, and Gaming.

### 11. Strict Transactional Systems (Fintech)
**Questions:** Design a Payment Switch / Digital Wallet / Stock Exchange
- **Core Lesson:** **Accuracy over Availability**. You cannot lose money or double-charge.
- **Key Concepts:** Distributed Transactions (2PC vs Sagas), Idempotency Keys (deduplication), Double-entry bookkeeping ledger, Auditor services.
- **Contrast:** Unlike Twitter (AP), this is strictly CP (Consistency/Partition Tolerance).

### 12. Heavy Write & Real-Time Analytics
**Questions:** Design a Metrics System (Datadog/Prometheus) / Ad-Click Aggregator
- **Core Lesson:** **Write-Heavy Ingestion**. Handling millions of writes per second where of raw events.
- **Key Concepts:** Time-Series Databases (TSDB), Stream Processing (Kafka + Flink/Spark Streaming), Data Rollups (Pre-aggregating 1s -> 1m -> 1h buckets), Batch Layer vs Speed Layer (Lambda Architecture).

### 13. Ultra-Low Latency & State Sync
**Questions:** Design a Multiplayer Game Server / Real-time Collaboration (Google Docs)
- **Core Lesson:** **State Synchronization**. Keeping multiple clients in perfect sync with <50ms latency.
- **Key Concepts:** UDP vs TCP, Operational Transformation (OT) or CRDTs (Conflict-free Replicated Data Types), Game Loops, "Lockstep" vs "State Interpolation".

## Concept Mapping Matrix
Here is how specific requirements map to the canonical questions:

| Requirement | Key Question | Patterns & Tech |
|:------------|:-------------|:----------------|
| **High Read Volume** | URL Shortener / Twitter | Cache-Aside, Read Replicas, CDN, Consistent Hashing |
| **High Write Volume** | Metrics / Notification | LSM Trees, Kafka, Write-Behind, Sharding |
| **Real-time Interaction** | Chat App / Game | WebSockets, Pub/Sub, Long Polling, SSE |
| **Complex Search** | Search Engine | Inverted Index, Trie, Scatter-Gather, TF-IDF |
| **Geography Based** | Uber / Yelp | Quadtree, Geohash, Geographic Sharding |
| **Queues / Async** | Notification System | Pub/Sub, DLQ, Outbox Pattern, Backpressure |
| **Strong Consistency** | Dropbox / Payments | 2PC, Leader Election, WAL, Fencing Tokens |
| **Eventual Consistency** | Twitter / DNS | Gossip Protocol, Vector Clocks, Quorum |
| **Low Latency** | Rate Limiter / Gaming | Bloom Filter, Redis, In-Memory Cache, UDP |
| **High Availability** | Any production system | Circuit Breaker, Bulkhead, Failover, Multi-Region |
| **Deduplication** | Crawler / Payments | Bloom Filter, Idempotency Keys, Content Hashing |
| **Ordering Guarantees** | Chat / Event Logs | Sequence IDs, Kafka Partitions, Vector Clocks |

---

## Pattern Selection Cheat Sheet

### By NFR (Non-Functional Requirement)
| NFR | Primary Patterns |
|:----|:-----------------|
| **Scalability** | Sharding, Consistent Hashing, Load Balancer, Stateless Services |
| **Availability** | Replication, Circuit Breaker, Failover, Multi-Region |
| **Durability** | WAL, Replication, Quorum Writes, Append-Only Logs |
| **Consistency** | Leader Election, 2PC, Saga, Fencing Tokens |
| **Low Latency** | Caching, CDN, In-Memory DBs, Edge Computing |
| **Throughput** | Async Messaging, Batching, Write-Behind, Partitioning |

### By Problem Type
| Problem | Go-To Patterns |
|:--------|:---------------|
| **"Too many reads"** | Cache-Aside, Read Replicas, CDN |
| **"Too many writes"** | Kafka Buffer, LSM Trees, Write-Behind, Sharding |
| **"Single point of failure"** | Leader Election, Replication, Circuit Breaker |
| **"Data too big for one machine"** | Sharding, Consistent Hashing, Tiered Storage |
| **"Need real-time updates"** | WebSocket, Pub/Sub, SSE, Long Polling |
| **"Cross-service transactions"** | Saga Pattern, Outbox Pattern, Idempotency |
| **"Hot partition / Celebrity problem"** | Hybrid Fan-out, Separate Hot/Cold paths, Caching |
| **"Counting at scale"** | HyperLogLog, Count-Min Sketch, Redis Lua |
| **"Membership check"** | Bloom Filter (probabilistic), Hash Set (exact) |

---

## Evaluation Criteria (Senior/Staff)
- **Requirements & Scope:** Can you identify the MVP vs extensions?
- **Data Model:** Do you choose the right DB (SQL vs NoSQL) based on read/write patterns?
- **Bottlenecks:** Can you identify where the system breaks (DB CPU, Bandwidth, Latency)?
- **Trade-offs:** Can you justify *why* you chose Eventual Consistency over Strong Consistency?

---

## Quick Reference: CAP & PACELC

| Theorem | Meaning |
|:--------|:--------|
| **CAP** | During partition (P), choose Consistency (CP) or Availability (AP). |
| **PACELC** | If Partition → C or A; Else → Latency or Consistency trade-off. |

**CP Systems:** ZooKeeper, etcd, HBase, MongoDB (default), Spanner  
**AP Systems:** Cassandra, DynamoDB, CouchDB, Riak  

---

## The 5 Numbers Everyone Should Know
| Metric | Value | Use Case |
|:-------|:------|:---------|
| L1 cache ref | ~1 ns | In-memory hot path |
| RAM ref | ~100 ns | Application state |
| SSD random read | ~100 µs | Database index |
| HDD seek | ~10 ms | Cold storage |
| Cross-continent RTT | ~150 ms | Global distribution |

---

## Database Selection Guide
| Requirement | Database Type | Examples |
|:------------|:--------------|:---------|
| ACID transactions | Relational | PostgreSQL, MySQL, CockroachDB |
| Key-Value lookups | KV Store | Redis, DynamoDB, etcd |
| Wide-column / Time-series | Column Store | Cassandra, HBase, InfluxDB |
| Full-text search | Search Engine | Elasticsearch, Solr, Meilisearch |
| Graph relationships | Graph DB | Neo4j, Neptune, TigerGraph |
| Document flexibility | Document Store | MongoDB, CouchDB, Firestore |
| Blob storage | Object Store | S3, GCS, Azure Blob |
