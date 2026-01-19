---
layout: default
title: "Deep Dive 1: Real-Time Analytics at 1 Million QPS"
description: "Solve the core problem of recording 1 million view events per second, aggregating them, and displaying accurate counters to billions of users"
category: "System Design"
tags: ["youtube", "analytics", "real-time", "performance", "scalability"]
date: 2026-01-19
---

# Deep Dive 1: Real-Time Analytics at 1 Million QPS

The moment a user hits play on a YouTube video, the counter increments. Not eventually, not in 5 minutes—instantly. You refresh the page and see 1,000 more views than a moment ago. This feels like magic. It's actually one of the most technically intricate problems at YouTube's scale, and every design choice carries a $10M+ cost penalty if wrong.

In this part, we'll solve the core problem: **How do you record 1 million view events per second, aggregate them, and display accurate counters to billions of users?**

Let's start by exploring what *doesn't* work.

---

## The Problem: 1 Million Events Per Second

At peak, YouTube has 1 million concurrent viewers. Assume each viewer records a "view" event when the segment starts playing (roughly once per 6 seconds). That's:

```
1,000,000 concurrent viewers × 60 seconds / 6 seconds per segment = 10 million segment requests/sec
```

Segment requests ≠ view events, but they're related. A more conservative estimate for view events is:

```
1,000,000 concurrent viewers × 1 view event every 30 seconds = 33,333 view events/sec
```

Multiply by content types (not all views, but likes, comments, shares, completions) and you're easily approaching **1 million events per second** for all engagement metrics combined.

Let's focus on views:

**Raw data**: 1M view events/sec × 86,400 sec/day × 365 days/year = **31.5 trillion view events stored per year.**

Store each event as 1KB JSON? That's 31.5 petabytes of raw data annually. Even with compression (10:1), that's 3.15PB/year. Possible but expensive.

But here's the real issue: **aggregation.** A user visiting YouTube wants to see:
- Total views: 1.4 billion
- Today's views: 4.2 million
- Views in the last hour: 125K

Computing these on the fly from 1 trillion events is impossibly slow.

---

## Naive Approach #1: Single Counter in Database

The simplest design:

```sql
CREATE TABLE video_stats (
  video_id UUID PRIMARY KEY,
  view_count BIGINT,
  like_count BIGINT,
  comment_count BIGINT
);

-- On each view:
UPDATE video_stats SET view_count = view_count + 1 WHERE video_id = ?;
```

**Problem**: This is a single row, in a single database. At 1M QPS, you're writing to the same row a million times per second. PostgreSQL can handle maybe 10K writes/sec to the same row before locking becomes a bottleneck.

**Math**:
```
Available: 10K writes/sec
Required: 1M writes/sec
Ratio: 100x over capacity
Result: System completely saturated
```

**Why?** Every write acquires a lock on the row. While locked, other writes wait. At 1M QPS, the queue is 100-deep. Latency explodes. The database becomes the bottleneck.

**Outcome**: Dead on arrival. ❌

---

## Naive Approach #2: Single Counter in Redis

Redis is faster. Single-threaded, in-memory, can handle 100K+ QPS on a single key.

```javascript
// On each view event:
await redis.incr(`video:${videoId}:views`);

// To get count:
await redis.get(`video:${videoId}:views`);
```

**Problem**: Still a single key. You're now hitting the same key 1M times per second. Redis can handle this better than PostgreSQL, but you're still at the edge of a single instance.

**Math**:
```
Redis single instance: ~100K QPS capacity
Required: 1M QPS
Ratio: 10x over capacity
```

Also: **What if Redis crashes?** You lose all view counts in memory. Those 1M daily views? Gone.

**Outcome**: Better, but still fails at scale. Redis isn't meant for 1M QPS on a single key. ❌

---

## Sharded Counters Architecture

Instead of one counter, use **100 counters**. Each view event picks a random shard and increments it.

```javascript
function recordView(videoId) {
  const shardId = Math.floor(Math.random() * 100);  // Pick random shard 0-99
  const key = `video:${videoId}:shard:${shardId}`;
  redis.incr(key);
}
```

**Math**:
```
100 shards × 10K QPS per shard = 1M QPS total capacity
Redis capacity per key: 100K QPS
Safety margin: 10x (well under capacity)
```

Each shard handles only 10K QPS. Redis can do this comfortably, with tons of headroom.

**How to read the total?**

```javascript
async function getViewCount(videoId) {
  // Try cache first (aggregate result cached)
  const cacheKey = `video:${videoId}:views:cached`;
  let count = await redis.get(cacheKey);
  if (count) return parseInt(count);
  
  // Cache miss: read all 100 shards and sum
  const shardKeys = [];
  for (let i = 0; i < 100; i++) {
    shardKeys.push(`video:${videoId}:shard:${i}`);
  }
  
  // Read all shards in parallel
  const shardCounts = await redis.mget(shardKeys);
  
  // Sum results
  const totalCount = shardCounts.reduce((sum, val) => {
    return sum + (parseInt(val) || 0);
  }, 0);
  
  // Cache result for 30 seconds (aggregate is stale but cheap)
  await redis.setex(cacheKey, 30, totalCount.toString());
  
  return totalCount;
}
```

**Cost of reading:**
- 100 parallel reads from Redis: ~50ms
- Summation: <1ms
- **Total latency: <100ms**

This is acceptable. Aggregation is infrequent (mostly on video info page load, not during playback).

**Durability problem**: If Redis dies, view counts are lost.

**Solution**: Dual-write to Redis + Kafka.

```javascript
async function recordView(videoId, userId, watchDuration) {
  // 1. Increment shard (fast, in-memory)
  const shardId = Math.floor(Math.random() * 100);
  redis.incr(`video:${videoId}:shard:${shardId}`).catch(err => {
    logger.error('Redis write failed', err);
  });
  
  // 2. Also publish to Kafka (persistent, for batch processing)
  await kafka.publish('view-events', {
    eventId: uuidv4(),
    videoId,
    userId,
    timestamp: new Date(),
    watchDuration
  });
  
  // Return immediately (Redis write is async, best-effort)
  return { success: true };
}
```

Now you have:
- **Redis shards**: Fast, for real-time counts (eventual consistency, refreshed every 30s)
- **Kafka**: Durable, for batch analytics (reconciliation, cold storage)

If Redis crashes, you rebuild from Kafka. Views aren't lost; they're slightly delayed.

---

## Event Streaming: Kafka as the Event Backbone

View events flow through Kafka. Kafka is a distributed message queue: durable, ordered, partitioned.

**Topic: `view-events`**
- **Partition strategy**: Hash by `video_id` (all views for a video go to the same partition, preserving order)
- **Partitions**: 1000 partitions (scale horizontally; each partition is a separate queue)
- **Retention**: 7 days (time to process/archive events)
- **Throughput**: 1M events/sec ÷ 1000 partitions = 1K events/sec per partition
- **Replication**: 3x (durability; any broker crash doesn't lose data)

**Kafka cluster:**
- **Brokers**: 10 machines
- **Storage**: 1M events/sec × 86,400 sec/day × 7 days × 1KB/event = 600GB/day → 4.2TB/week
- **Cost**: ~$30K/month (machines + storage)

**Partition example:**

```
video:dQw4w9WgXcQ → Partition 4
├─ Event 1: {videoId: dQw4w9WgXcQ, userId: user1, timestamp: 14:32:10}
├─ Event 2: {videoId: dQw4w9WgXcQ, userId: user2, timestamp: 14:32:11}
├─ Event 3: {videoId: dQw4w9WgXcQ, userId: user3, timestamp: 14:32:12}
└─ ... 1000 more events per second
```

Because all views for a video go to one partition, the stream is ordered by video.

---

## Stream Processing: Real-Time Aggregation

Raw events are useless. You need aggregates: "views per video", "views per hour", "like rate", "watch completion rate".

### Stream Processor: Kafka Streams or Flink

A stream processor continuously reads from Kafka, applies transformations, and outputs results.

**Example: Views per video, aggregated every 10 seconds**

```python
# Using Flink (pseudocode)

kafka_source = kafka.source('view-events')

# Parse events
events = kafka_source.map(lambda event: {
  'video_id': event['videoId'],
  'timestamp': event['timestamp']
})

# Tumbling window: 10-second buckets
windowed = events \
  .keyBy('video_id') \
  .window(TumblingEventTimeWindow(10_seconds))

# Count views in each window
aggregated = windowed.apply(lambda views: {
  'video_id': views[0]['video_id'],
  'window_start': window.start(),
  'window_end': window.end(),
  'view_count': len(views),
  'timestamp': now()
})

# Output to Redis + Data lake
aggregated.sink(redis_sink('video_analytics_10sec'))  # Real-time
aggregated.sink(s3_sink('video_analytics_lake'))      # Historical
```

**What this produces:**

```
video:dQw4w9WgXcQ:views:10sec:14:32:00
  └─ views: 125000  (125K views in the 10-sec window starting at 14:32:00)

video:dQw4w9WgXcQ:views:10sec:14:32:10
  └─ views: 128000

video:dQw4w9WgXcQ:views:10sec:14:32:20
  └─ views: 121000
```

**From these 10-second windows, derive:**

```
Hour totals: 125K + 128K + 121K + ... (360 windows) = 43M views in that hour
Day totals: 43M × 24 hours = 1.032B views today
```

These aggregates are cached in Redis or served from the data lake.

### Scaling Stream Processing

**Topology:**

```
Kafka (view-events)
  ├─ 1000 partitions
  └─ Flink cluster reads all partitions in parallel
     ├─ TaskManager 1: reads partitions 0-99
     ├─ TaskManager 2: reads partitions 100-199
     └─ ... 10 TaskManagers total
```

Each TaskManager handles 100K events/sec (1M total ÷ 10). Flink parallelism scales linearly.

**Cost**: ~$25K/month for Flink cluster (machines + storage)

---

## Batch Analytics: Data Lake for Historical Analysis

Real-time analytics lag. Tomorrow's report (retention curves, traffic sources, device breakdowns) comes from batch processing.

**Architecture:**

```
Kafka (7-day window)
  └─ Daily batch job:
     1. Read all view events from past 24 hours
     2. Group by (video_id, hour, device_type, country)
     3. Compute aggregates: views, watch_duration, drop_off_rate
     4. Write to S3 Data Lake
     5. Load into BigQuery for SQL queries

Result: video_analytics_2024_01_18
├─ video_id | hour | country | device | views | watch_duration_total
├─ dQw4w9WgXcQ | 14 | US | desktop | 45000 | 2340000 (total seconds)
├─ dQw4w9WgXcQ | 14 | US | mobile | 32000 | 945000
└─ ...
```

**Retention Analysis:**

```
Video: dQw4w9WgXcQ (213 seconds duration)
Watch duration histogram:
├─ Watched 0-30 sec: 80% of viewers (dropped off in intro)
├─ Watched 30-60 sec: 60% of viewers
├─ Watched 60-120 sec: 40% of viewers
├─ Watched 120-213 sec (complete): 15% of viewers
└─ Inference: Viewers love the chorus (seconds 120-180) but the intro is weak

Recommendation: Re-edit intro or focus future content there
```

**Cost**: BigQuery + storage costs ~$15K/month

---

## Metrics & Consistency Model

### Freshness Guarantees

| Metric | Freshness | How |
|--------|-----------|-----|
| **Real-time counter** (what you see on video) | 30-60 seconds | Redis shards, periodically aggregated + cached |
| **Analytics dashboard** (hourly views) | 5-10 minutes | Stream processor output cached in Redis |
| **Historical data lake** (daily reports) | 24 hours | Batch job runs nightly |

**Why these lags are acceptable:**

```
Real-time counter (30s): Users don't expect instant counters. YouTube's official counts lag by minutes.
Analytics dashboard (5-10 min): Creators refreshing hourly. 5 min lag is imperceptible.
Data lake (24 hours): Historical analysis. Old data by definition.
```

### Consistency Trade-offs

YouTube uses **eventual consistency** for counters because:
1. Users don't notice a 30-second delay
2. Eventual consistency can scale to 1M QPS
3. Strong consistency cannot scale to 1M QPS

**The math:**
```
Strong consistency: 1M QPS → requires distributed lock → ~10ms latency per write → queue grows → system overloads
Eventual consistency: 1M QPS → write to random shard → <1ms latency → queue stays small → system stable
```

---

## Failure Scenarios & Recovery

### Scenario 1: Redis Shard Crashes

**Impact:**
- Writes to shard 42 fail (50K events/sec affected)
- New views don't increment shard 42
- Total count drops by 10M

**Recovery:**
```
1. Alert fires: Shard 42 unhealthy
2. Operations team: Restart Redis shard 42 instance
3. Restart takes: 30 seconds
4. Redis loads from RDB checkpoint (snapshot from 30 seconds ago)
5. Missing views: 50K events/sec × 30 sec = 1.5M views
6. These 1.5M views were written to Kafka (durable)
7. Reconciliation job: Compare Redis vs Kafka, repair shard 42
8. RTO (recovery time): 5-10 minutes
```

**Why Kafka helps:** Kafka is durable. Lost views are temporarily inaccurate, but can be recovered.

### Scenario 2: Kafka Broker Goes Down

**Impact:**
- Can't write new view events
- Stream processing stops
- Real-time analytics lag

**Recovery:**
```
Kafka has 10 brokers, replication factor 3.
├─ Broker 5 crashes
├─ Its partition leader elections fail over to replicas (30 sec)
├─ No data loss (redundant replicas on brokers 1,2,3)
├─ System resumes
RTO: <1 minute
```

### Scenario 3: Stream Processor (Flink) Crashes

**Impact:**
- Real-time aggregation stops
- Counters stop updating

**Recovery:**
```
1. Flink checkpoint failure detected
2. Cluster manager restarts Flink job
3. Flink resumes from last checkpoint (every 5 seconds)
4. Max loss: 5 seconds of aggregations
5. Result: Analytics lag by 5 seconds longer
RTO: 30 seconds
```

---

## Monitoring: Detecting Problems Before They Explode

At 1M QPS, you can't wait for users to report issues. Problems must be detected automatically.

### Key Metrics to Monitor

**1. Shard Skew Detection**

```
Expected: Each shard receives 10K QPS
Actual (healthy): Shard 0-99 each receive 9.8K-10.2K QPS (2% variance)
Actual (skewed): Shard 42 receives 50K QPS, shard 5 receives 2K QPS

Alert: If any shard deviates >20% from average, page on-call engineer
Reason: Skew means inconsistent hashing or one shard is a hot key
```

**2. Kafka Lag**

```
Lag = (latest offset in topic) - (latest offset consumer processed)

If lag > 5 minutes, stream processor is falling behind
└─ Indicates: Consumer too slow, broker issues, or spike in event volume
```

**3. Redis Latency**

```
Track: P50, P95, P99 latency for redis.incr() and redis.get()
Healthy: P99 < 10ms
Alert: P99 > 50ms (indicates congestion, shard overload)
```

**4. Counter Divergence**

```
Every hour, compare:
├─ Redis aggregate (sum of 100 shards)
├─ Kafka event count (events from data lake)
Divergence > 1% → Alert (Kafka events not reaching Redis, data loss)
```

---

## Cost Breakdown: Why This Matters

At YouTube's scale, every million QPS costs real money.

**Annual cost for 1M QPS view analytics:**

| Component | Cost |
|-----------|------|
| **Redis cluster** (100 shards, 2TB memory) | $25,000/month = $300K/year |
| **Kafka cluster** (10 brokers, 4.2TB/week storage) | $30,000/month = $360K/year |
| **Stream processor** (Flink, 10 TaskManagers) | $20,000/month = $240K/year |
| **BigQuery** (batch analytics, storage + queries) | $15,000/month = $180K/year |
| **Monitoring** (Prometheus, ELK, alerts) | $10,000/month = $120K/year |
| **Total** | ~$100K/month = **$1.2M/year** |

**But the ROI is massive:**
- Users see accurate view counts → engagement increases
- Analytics enable creators to optimize → watch time increases
- Every 1% increase in watch time = $5-10M in ad revenue

A $1.2M/year system that drives $50M+ in incremental revenue is a no-brainer.

---

## Optimization: Reducing Costs

### Option 1: Reduce Granularity

Instead of 100 shards, use 50 shards. Each shard now handles 20K QPS (Redis can handle this).

**Cost reduction**: -$50K/year
**Risk**: Less headroom. One shard outage affects more videos.

### Option 2: Longer Cache TTL

Instead of caching aggregates for 30 seconds, cache for 5 minutes.

**Benefit**: Fewer aggregate reads, fewer Kafka events.
**Cost reduction**: -$20K/year
**Risk**: Counters lag more; users notice if they refresh quickly.

### Option 3: Batch View Recording

Instead of recording every view event, batch 10 views into one event every second.

**Cost reduction**: 90% fewer Kafka events = -$270K/year
**Risk**: Real-time dashboard becomes less real-time (lag increases to 10s)

**Real YouTube does variants of all three**, tuned for the balance between real-time accuracy and cost.

---

## Conclusion: The Hidden Complexity of "Simple" Counters

What looks like a simple counter—a number incrementing—requires:

- **Sharding** for horizontal scale
- **Eventual consistency** for throughput
- **Caching** for latency
- **Event streaming** for durability
- **Stream processing** for real-time analytics
- **Batch jobs** for historical analysis
- **Monitoring** for detection
- **Redundancy** for reliability

Miss any piece, and the system fails. Add all pieces, and you can handle 1M QPS reliably and cost-effectively.

In the next part, we tackle a different hard problem: **transcoding at scale**. 500K hours uploaded daily means 2.5M-5M transcode jobs. Codec choice directly determines whether this costs $2M/month or $4M/month. Economics meets encoding.

---

**Key Takeaways:**
- 1M view events/sec requires sharded counters (100 shards × 10K QPS each)
- Kafka provides durable event stream; Redis provides fast aggregation
- Stream processors compute real-time aggregates (views per 10-second window)
- Eventual consistency (30s lag) enables 100x scale vs strong consistency
- Monitoring detects shard skew, Kafka lag, and counter divergence
- Total cost: ~$1.2M/year for 1M QPS analytics infrastructure

