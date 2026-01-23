# Article 8: Deep Dive 2 - Async-Everything (Event-Driven)

## Philosophy: No Blocking

The async-everything approach eliminates all blocking operations from the critical path.

**Key principle**: User gets response before any database write completes.

---

## Async Architecture Overview

```
Synchronous (MVP):  user → db → wait → response
Async (This approach): user → queue → response (db works async)

Result: All operations complete in <5ms
```

### Technology Stack

```
API Servers → Kafka → Stream Processor
                ↓
          DynamoDB (eventual consistency)
                ↓
          Microservices (independently scale)
```

---

## Request Flows (Async)

### Create Link Flow (Async)

```
User submits: {long_url: "https://example.com/..."}

Step 1: API Server (1ms)
  ├─ Validate URL (format, length)
  ├─ Generate short_code (random or custom)
  ├─ Return 201 Created
  │  └─ Response: {short_code: "abc123"}
  └─ IMMEDIATELY return to user

Step 2: Publish to Kafka (asynchronous)
  ├─ Event: {
  │    type: "LinkCreated",
  │    short_code: "abc123",
  │    long_url: "https://...",
  │    user_id: "user123",
  │    timestamp: 1705329000
  │  }
  └─ Fire-and-forget (user already got response!)

Step 3: Database Consumer (1000ms later)
  ├─ Read event from Kafka
  ├─ Check for duplicates
  ├─ Write to DynamoDB
  ├─ Send confirmation webhook (if premium)
  └─ Mark event processed

Result:
  User gets 201 in 1ms
  Database update happens 1 second later
  If database fails, event still in Kafka (retry later)
```

### Redirect Flow (Async)

```
User clicks: GET /abc123

Step 1: Query Cache (1-5ms)
  ├─ Check Redis: Redis.get("url:abc123")
  ├─ If hit: Return 301 redirect
  └─ If miss: Continue

Step 2: Queue Read Request (1ms)
  ├─ Publish to Kafka: {type: "ReadRequest", code: "abc123"}
  ├─ Return immediately (don't wait!)
  └─ Use cached or stale value if available

Step 3: Async Read (1000ms later)
  ├─ Query DynamoDB
  ├─ Update cache with fresh value
  ├─ Ready for next request
  └─ No rush (previous request already served)

Result:
  User gets response in 1-5ms (from cache or stale)
  Fresh data available for future requests
  No latency penalty
```

---

## Kafka as Central Hub

### Event Schema Design

```python
# Define all event types as schema

{
  "LinkCreated": {
    "short_code": "string",
    "long_url": "string",
    "user_id": "string",
    "is_custom": "boolean",
    "created_at": "timestamp"
  },
  
  "LinkDeleted": {
    "short_code": "string",
    "user_id": "string",
    "deleted_at": "timestamp"
  },
  
  "LinkAccessed": {
    "short_code": "string",
    "ip": "string",
    "user_agent": "string",
    "referrer": "string",
    "timestamp": "timestamp"
  }
}

# Events are immutable facts (never change)
# Each event is independent (no ordering dependency)
```

### Kafka Topics & Partitioning

```
Topic: links-events
  Partitions: 10 (parallelism)
  Partition key: short_code (ensures all events for 1 URL go to 1 partition)
  
  Partition 0: short_codes with hash % 10 == 0
  Partition 1: short_codes with hash % 10 == 1
  ...
  Partition 9: short_codes with hash % 10 == 9
  
Benefits:
  ├─ Events for same URL stay ordered (in 1 partition)
  ├─ Multiple partitions allow parallel processing
  └─ Throughput scales linearly with partitions

Topic: analytics-events
  Partitions: 20 (high-volume)
  Partition key: short_code
  
  High volume because:
    ├─ 600 RPS × 86,400 sec/day = 51.8M events/day
    ├─ Need parallelism to process
    └─ Multiple consumers process in parallel
```

### Consumer Groups

```
Topic: links-events
  
Consumer Group: database-writer
  ├─ Consumer 1: Processes partition 0-3
  ├─ Consumer 2: Processes partition 4-7
  ├─ Consumer 3: Processes partition 8-9
  └─ Function: Write events to DynamoDB
  
Consumer Group: webhooks
  ├─ Single consumer: Processes all partitions
  └─ Function: Send webhook notifications (premium users)
  
Consumer Group: audit-log
  ├─ Single consumer: Processes all partitions
  └─ Function: Write to immutable audit log
```

---

## Kafka Configuration & Operational Tuning

### Partition Count Formula

**Formula**: `Partitions = max(Expected_RPS / 1000, Num_Consumers)`

**For our URL Shortener**:
- Expected RPS: 600 (MVP phase)
- Consumer count: 3
- **Result**: 10 partitions (from max(600/1000, 3))

**Scaling Examples**:
```
1K RPS:   Partitions = max(1, 3) = 3
5K RPS:   Partitions = max(5, 5) = 5
10K RPS:  Partitions = max(10, 8) = 10
50K RPS:  Partitions = max(50, 12) = 50
```

**Why this formula?**
- 1 partition can handle ~1000 RPS (single-threaded)
- More consumers = more parallelism needed
- Size partitions for 80% utilization

### Consumer Lag Monitoring

**What to watch** (real-time metrics):

```
Consumer Group: database-writer
  Max Lag: 50ms (HEALTHY)
  ├─ Lag per partition: [2ms, 5ms, 8ms, 3ms, 10ms, ...]
  └─ All < 100ms ✓

  Max Lag: 5000ms (WARNING)
  ├─ Some partition lag > 1s
  ├─ Indicates consumer slowdown
  └─ Action: Check consumer logs + increase instances
  
  Max Lag: 30000ms (CRITICAL)
  ├─ Events queued for 30 seconds
  ├─ Users seeing 30s delays
  └─ Action: Page on-call engineer, scale consumers
```

**Kafka Broker Metrics to Monitor**:
```
- Under-Replicated Partitions: 0 (should always be)
- Offline Partitions: 0 (must be zero)
- Leader Election Rate: < 1 per 5 minutes
- Disk Usage: < 80% capacity
```

**CloudWatch/Prometheus Dashboard**:
```yaml
Metrics:
  - kafka.consumer.lag (track lag per partition)
  - kafka.topic.bytes_in (incoming throughput)
  - kafka.broker.disk_used (disk capacity)
  - messages_consumed_rate (actual throughput)
  
Alarms:
  - lag > 5000ms → WARNING
  - lag > 30000ms → CRITICAL
  - under_replicated_partitions > 0 → CRITICAL
  - offline_partitions > 0 → CRITICAL
```

### Auto-Scaling Strategy

**Monitor**: Consumer lag per partition

**Rules**:
```
IF max_lag > 5000ms for 5 minutes:
  Action: Add 1 consumer instance
  Rebalance: Kafka automatically redistributes partitions
  Max instances: (Partition Count) - only up to # of partitions
  
IF max_lag < 1000ms for 15 minutes:
  Action: Remove 1 consumer instance
  Cooldown: Wait 5 minutes before next scale-down
  Min instances: 1 (for resilience)
```

**Example Scaling Flow**:
```
T=0:      3 consumers, 10 partitions
          Each handles ~3 partitions
          Lag: 200ms ✓

T=60s:    Traffic spike 600 RPS → 2000 RPS
          Lag increases to 8000ms ⚠️

T=65s:    Auto-scaler triggers
          Launches 4th consumer instance
          Lag drops to 2000ms

T=300s:   5th consumer launched (lag still high)
          Now 5 consumers / 10 partitions
          Each handles 2 partitions
          Lag returns to 100ms ✓

T=3600s:  Traffic returns to 600 RPS
          5 consumers overkill
          Auto-scaler removes 2 instances over 15 min
          Back to 3 consumers
```

**Cost Impact**:
```
Each consumer instance: $0.10/hour (t3.small)

Normal: 3 instances = $0.30/hour
Spike:  5 instances = $0.50/hour (temporary)

Monthly impact: +$50-100 during peak seasons
```

### Dead Letter Queue (DLQ) Configuration

**Why DLQ?**
```
Consumer processes event
├─ Success: Commit offset, move to next
├─ Failure (temporary): Retry 3x, then continue
├─ Failure (permanent): Send to DLQ
└─ DLQ: Investigate later manually
```

**Configuration**:
```yaml
Topic: links-events
Topic: links-events-dlq (dead letter queue)

Consumer Config:
  max.poll.records: 100
  max.poll.interval.ms: 300000 (5 minutes per batch)
  
Failure Handling:
  1st failure: Retry immediately
  2nd failure: Wait 5 seconds, retry
  3rd failure: Wait 30 seconds, retry
  4th failure: Send to DLQ
  
Monitor DLQ:
  - Slack alert if any message lands in DLQ
  - Investigate within 1 hour
  - Common causes: Invalid data, downstream service down
```

**Monitoring**:
```
DLQ Message Count:
  0-5/hour:   ✓ Normal (occasional failures)
  5-50/hour:  ⚠️ Warning (increased failures)
  >50/hour:   🔴 Critical (major issue)
  
Action if 50+/hour:
  1. Page on-call
  2. Check downstream service health
  3. Stop consumers (prevent more sends to DLQ)
  4. Fix root cause
  5. Replay from DLQ once resolved
```

---

## Eventual Consistency Model

### Problem: Stale Data

```
Scenario:
  User creates link at T0
  Database write happens at T1000 (1 second later)
  
  User tries to access own link at T500 (before write completes)
  ├─ Query DynamoDB
  ├─ Link not found yet! (still processing)
  └─ Returns 404 (wrong!)
```

### Solution: Write-Through Cache

```python
def create_link(long_url, custom_code=None):
    """Create link with write-through cache"""
    
    # Step 1: Generate code (synchronous)
    if custom_code:
        short_code = custom_code
    else:
        short_code = generate_short_code()
    
    # Step 2: Write to CACHE FIRST (immediate)
    cache.set(f"url:{short_code}", long_url, ttl=3600)
    
    # Step 3: Return to user (response sent!)
    response = {
        "short_code": short_code,
        "short_url": f"https://short.app/{short_code}"
    }
    
    # Step 4: Publish to Kafka (async, after response)
    kafka_producer.send_async('links-events', {
        "type": "LinkCreated",
        "short_code": short_code,
        "long_url": long_url,
        "timestamp": time.time()
    })
    
    return response

# Result:
#   User: Gets response immediately ✓
#   User's own access: Hits cache (sees own link) ✓
#   Other users: Eventually see link (after DB processes) ✓
```

### Consistency Windows (CRITICAL TIMING)

**Timeline for Link Creation**:
- T=0ms: User sends POST /api/links
- T=1ms: short_code generated, Cache.set() called (IMMEDIATE)
- T=20ms: Response sent to user 
- T=25ms: Kafka.produce() finishes
- T=35ms: Kafka consumer receives message
- T=50ms: DynamoDB.put() completes (DB now consistent)
- T=50-100ms: Read replicas updated (all nodes consistent)

**Consistency Guarantees**:
- User → Cache: Immediate (<1ms)
- User → Other clients: Eventual (50-100ms typical, <500ms worst-case)
- Analytics: ~100ms typical

| Metric | Guarantee |
|--------|-----------|
| Response latency | <50ms (cache write + response) |
| Read-your-own-writes | Immediate (cache hit) |
| Global consistency | 50-100ms (Kafka + Consumer + DB) |
| Worst-case consistency | <5s (if consumer crashes) |

### Handling Inconsistency

```
Edge case: User deletes link, then immediately clicks it

Timeline:
  T0: DELETE /links/abc123 → publish LinkDeleted event
  T1: User clicks short.app/abc123
  T2: Cache has expired (or cleared) but DB hasn't processed delete
  
Solution:
  ├─ Cache stores deletion marker: cache.set("deleted:abc123", True)
  ├─ On redirect: check if deleted (even if URL still in cache)
  ├─ Return 410 Gone (not 301)
  └─ Delete event processes in background
```

### Handling Inconsistency (original)---

## Event Sourcing Pattern

### What is Event Sourcing?

```
Traditional: Store current state
  links table:
    short_code | long_url | is_deleted
    abc123     | https:// | false

Event Sourcing: Store events, derive state
  events table:
    event_id | type        | data                     | timestamp
    1        | LinkCreated | {code, url, user_id}     | T0
    2        | LinkDeleted | {code, user_id}          | T1000
    
  Current state derived by:
    1. Load event 1: is_deleted = false
    2. Load event 2: is_deleted = true
    3. Final state: is_deleted = true
```

### Benefits of Event Sourcing

```
✅ Complete audit trail (every change recorded)
✅ Time-travel debugging (see state at any point)
✅ Replaying events (rebuild state from scratch)
✅ Perfect for compliance (GDPR, SOC2)
✅ Decoupling (new consumers added without affecting others)

❌ Complexity (harder to understand)
❌ Storage (all events stored, not just current)
❌ Consistency (must handle out-of-order events)
```

### Implementation (Kafka-Based)

```python
class LinkService:
    def __init__(self):
        self.kafka = KafkaProducer()
        self.event_store = DynamoDB(table='events')
    
    def create_link(self, long_url, user_id, custom_code=None):
        """Create link via event sourcing"""
        
        short_code = custom_code or generate_short_code()
        
        # 1. Publish event
        event = {
            "event_id": uuid4(),
            "type": "LinkCreated",
            "aggregate_id": short_code,  # Used for grouping
            "data": {
                "short_code": short_code,
                "long_url": long_url,
                "user_id": user_id,
                "timestamp": time.time()
            }
        }
        
        self.kafka.send('link-events', value=json.dumps(event))
        
        # 2. Store in event store (append-only)
        self.event_store.put_item(Item=event)
        
        # 3. Update cache for this user's view
        cache.set(f"link:{short_code}", event['data'])
        
        return short_code
    
    def rebuild_state(self, short_code):
        """Rebuild current state from events"""
        
        events = self.event_store.query(
            KeyConditionExpression='aggregate_id = :id',
            ExpressionAttributeValues={':id': short_code}
        )
        
        # Replay all events
        state = None
        for event in sorted(events, key=lambda e: e['timestamp']):
            if event['type'] == 'LinkCreated':
                state = {
                    'short_code': event['data']['short_code'],
                    'long_url': event['data']['long_url'],
                    'is_deleted': False
                }
            elif event['type'] == 'LinkDeleted':
                state['is_deleted'] = True
        
        return state
```

---

## Stream Processing (Analytics at Scale)

### Kafka Streams / Apache Flink

```python
# Process analytics in real-time using Kafka Streams

from kafka import KafkaConsumer

class AnalyticsProcessor:
    def process(self):
        """Aggregate analytics from stream"""
        
        consumer = KafkaConsumer(
            'analytics-events',
            bootstrap_servers=['localhost:9092'],
            group_id='analytics-group'
        )
        
        # Aggregate by (short_code, date)
        aggregates = {}
        
        for message in consumer:
            event = json.loads(message.value)
            key = (event['short_code'], event['date'])
            
            if key not in aggregates:
                aggregates[key] = {
                    'clicks': 0,
                    'unique_users': set()
                }
            
            aggregates[key]['clicks'] += 1
            aggregates[key]['unique_users'].add(event['ip'])
            
            # Every minute, flush to database
            if time.time() % 60 == 0:
                for (short_code, date), data in aggregates.items():
                    db.update_daily_analytics(
                        short_code, date,
                        clicks=data['clicks'],
                        unique_users=len(data['unique_users'])
                    )
                aggregates = {}

processor = AnalyticsProcessor()
processor.process()  # Runs forever
```

---

## Consistency Guarantees

### Exactly-Once Processing

```
Challenge:
  Consumer processes event "LinkCreated"
  ├─ Writes to database
  ├─ Network fails before sending ack to Kafka
  ├─ Kafka doesn't mark offset complete
  ├─ Consumer restarts
  ├─ Reprocesses same event
  ├─ Duplicate write!

Solution: Idempotent writes

def process_link_created(event):
    # Use event_id as deduplication key
    if database.exists('processed_events', event['event_id']):
        return  # Already processed, skip
    
    # Write to database
    database.insert('links', event['data'])
    
    # Mark as processed
    database.insert('processed_events', {
        'event_id': event['event_id'],
        'processed_at': time.time()
    })
    
    # Only now ack to Kafka
    consumer.commit()
```

---

## Operational Complexity

### Challenges

```
❌ Harder to debug
   - Request flows across multiple services
   - No single transaction (distributed)
   - Eventual consistency makes timing hard

❌ Operational burden
   - Kafka cluster management
   - Consumer lag monitoring
   - Rebalancing during deployments
   - Dead-letter queue for failed events

❌ Team maturity needed
   - Requires experience with distributed systems
   - Debugging skills (traces, logs, metrics)
   - On-call readiness for async failures
```

### Monitoring

```python
def monitor_kafka():
    """Check async system health"""
    
    # Monitor 1: Consumer lag
    lag = kafka_admin.get_consumer_group_offset_lag('database-writer')
    if lag > 10000:  # More than 10K events behind
        alert("Database consumer falling behind")
    
    # Monitor 2: Topic throughput
    metrics = kafka.get_metrics('links-events')
    if metrics['messages_in_rate'] < 100:  # Should be 600+ RPS
        alert("Analytics events not flowing")
    
    # Monitor 3: Error rate
    errors = db.count_where('processed_events', error_type='!= null')
    error_rate = errors / total_events
    if error_rate > 0.001:  # > 0.1%
        alert("Too many processing errors")
```

---

## Cost Breakdown (Async-Everything)

```
Component                Cost/Month    Throughput
Kafka (MSK)              $500          10,000+ msg/sec
DynamoDB                 $250          Auto-scales
Stream Processor (Flink) $200          10,000+ events/sec
API Servers             $500          Minimal load
TOTAL                   $1,450        10,000+ RPS ✓

Benefits:
  ├─ Can handle 10x scale at 1.5x cost
  ├─ Scales linearly (add partitions)
  └─ Automatic recovery from failures
```

---

## When to Use Async-Everything

✓ When absolute maximum performance needed (<5ms latency)
✓ When scaling to millions of events/second
✓ When decoupling services is critical
✓ When team has distributed systems expertise

❌ When simplicity is priority
❌ When team is small (< 10 engineers)
❌ When startup phase (pre-scale)

---

## Summary: Deep Dive 2

**Async approach**:
- All writes async via Kafka
- Users get response in <5ms
- Database updates happen asynchronously
- Eventual consistency model

**Key patterns**:
- Event sourcing (complete audit trail)
- Exactly-once processing (deduplication)
- Write-through cache (read-your-own-write)
- Stream processing (real-time analytics)

**Trade-offs**:
- Extreme performance ✓
- Extreme complexity ❌
- High operational burden ❌
- Requires expertise ❌

**Next**: Deep Dive 3 - DynamoDB (best operational).
