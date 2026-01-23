# Article 9: Deep Dive 3 - DynamoDB (Managed Approach)

## Why DynamoDB?

The third approach trades operational complexity for AWS-managed simplicity.

**Philosophy**: Pay AWS to handle scaling, replication, backups.

---

## DynamoDB vs PostgreSQL vs Cassandra

### Comparison Matrix

| Factor | PostgreSQL Sharded | Cassandra | DynamoDB |
|--------|-------------------|-----------|----------|
| **Setup time** | 2 weeks | 1 week | 1 hour |
| **Operational cost** | $10K/month (DBAs) | $15K/month (DevOps) | $250/month |
| **Infrastructure cost** | $5K-8K/month | $6K-10K/month | $250/month |
| **Max RPS (without optimization)** | 1000 | 5000 | 10,000+ (unlimited) |
| **Scaling requires** | Code changes (sharding) | Operational work | Automatic |
| **Consistency** | Strong (tunable) | Eventual | Eventual (with option for strong) |
| **Query flexibility** | Full SQL | Limited | Very limited |
| **Operational burden** | High (backups, patches) | Very High | None (managed) |
| **Learning curve** | Easy | Hard | Easy |

### Cost Analysis (1B URLs, 600 RPS)

**PostgreSQL Sharded**:
```
Setup:
  ├─ 4 shards × 2 replicas each = 8 servers
  ├─ 2 DBA engineers ($200K/year each)
  └─ 500 hours consulting

Monthly:
  ├─ 8 × c5.2xlarge ($2,500/month) = $20K
  ├─ DBA salary (2 FTE): $33K
  ├─ Operational overhead: $5K
  └─ TOTAL: $58K/month
```

**Cassandra**:
```
Setup:
  ├─ 12 nodes cluster
  ├─ 3 DevOps engineers ($200K/year each)
  └─ 1000 hours consulting

Monthly:
  ├─ 12 × c5.2xlarge: $30K
  ├─ DevOps salary (3 FTE): $50K
  ├─ Operational overhead: $10K
  └─ TOTAL: $90K/month
```

**DynamoDB**:
```
On-Demand Pricing (automatic scaling):
  ├─ Write capacity: 12 RPS × 30 days = 31M writes = $39
  ├─ Read capacity: 600 RPS × 30 days = 1.5B reads = $375
  ├─ Storage: 1B URLs × 2KB = 2TB = $410
  └─ TOTAL: $825/month
  
Provisioned (if traffic predictable):
  ├─ Write: 50 WCU = $24.50/month
  ├─ Read: 600 RCU = $300/month
  ├─ Storage: $410
  └─ TOTAL: $735/month
```

**Winner by far: DynamoDB**

---

## DynamoDB Schema Design

### Table Design

```
Table: urls

Partition Key: short_code
  ├─ Unique identifier for each URL
  ├─ Distributes data evenly across partitions
  ├─ Example: "abc123"
  └─ Must be used in every query

Sort Key: (none)
  └─ Not needed because short_code is unique

Attributes:
  ├─ short_code (String) [PK]
  ├─ long_url (String)
  ├─ user_id (String)
  ├─ created_at (Number) [Unix timestamp]
  ├─ is_custom (Boolean)
  ├─ is_deleted (Boolean)
  ├─ expires_at (Number) [Unix timestamp, optional]
  ├─ title (String, optional)
  └─ content_hash (String) [for deduplication]
```

### Global Secondary Indexes (GSI)

```
GSI 1: user_id-created_at
  ├─ Partition Key: user_id
  ├─ Sort Key: created_at (DESC)
  ├─ Use case: "Get all links for user_id=123"
  ├─ Projection: All attributes
  └─ Cost: Same as reads from main table

GSI 2: created_at
  ├─ Partition Key: created_at (date)
  ├─ Sort Key: (none)
  ├─ Use case: "Get links created today"
  ├─ Projection: short_code only (minimal)
  └─ Cost: Sparse, only written once per link

GSI 3: content_hash
  ├─ Partition Key: content_hash (SHA256 of long_url)
  ├─ Sort Key: (none)
  ├─ Use case: "Is this URL already shortened?"
  ├─ Projection: short_code only
  └─ Cost: Query returns 1 item (fast)
```

### TTL Configuration

```python
# DynamoDB auto-deletes expired items

attribute: expires_at (Unix timestamp, optional)

# Example:
{
  "short_code": "abc123",
  "long_url": "https://...",
  "expires_at": 1705415400  # Jan 16, 2024 10:30 AM UTC
}

# DynamoDB behavior:
#   ├─ At TTL expiry (±48 hours): Item deleted
#   ├─ Before actual deletion: Item still accessible
#   ├─ After deletion: Query returns not found
#   └─ No cost for deletion (automatic)

# Configure TTL:
table.ttl_attribute_name = 'expires_at'

# For links without expiry:
# Don't set expires_at field (null/missing is OK)
```

---

## DynamoDB Pricing Model

DynamoDB offers two billing modes, each optimized for different scenarios:

### 1. On-Demand Pricing (Recommended for MVP & Variable Traffic)

**Billing Model**:
- **Reads**: $0.25 per 1M read capacity units (RCUs) consumed
- **Writes**: $1.25 per 1M write capacity units (WCUs) consumed  
- **Storage**: $0.25 per GB per month

**Key Characteristics**:
- Auto-scales up and down instantly
- No capacity planning needed
- Pay only for what you consume
- No throttling (unlimited burst capacity)
- Better for unpredictable or bursty traffic

**When to Use**: Early stages, unpredictable traffic, tolerance for higher variable costs

---

### 2. Provisioned Pricing (Recommended for Production & Predictable Scale)

**Billing Model**:
- **Write Capacity**: $1.25 per WCU per month (fixed commitment)
- **Read Capacity**: $0.25 per RCU per month (fixed commitment)
- **Storage**: $0.25 per GB per month
- **Auto-scaling**: Optional (no extra cost, but can overscale if misconfigured)

**Key Characteristics**:
- Fixed monthly cost regardless of usage below capacity
- Better cost for sustained, predictable traffic
- Burst capacity: 4x reserved capacity for 300 seconds
- Beyond burst: requests throttled (HTTP 400 ProvisionedThroughputExceededException)
- Must pre-plan capacity

**When to Use**: Production, predictable traffic, cost optimization focus

---

### Cost Comparison Example

**Scenario**: URL Shortener at 600 RPS (peak), serving ~10B redirects/month

#### Calculation Methodology

First, understand request costs:
- **One redirect request** (read 4KB link metadata) = **1 RCU**
- **One create-link request** (write 1KB) = **1 WCU**
- Assume: 80% redirects (reads), 20% creates (writes)

Traffic pattern:
- Peak: 600 RPS
- Average: 150 RPS (25% of peak - typical pattern)
- Daily: 10B redirects = 115,740 RPS average (if evenly distributed)

**Choose "realistic average" scenario**:

Monthly redirects: 10B = 115,740 RPS average
  ├─ Reads needed: 115,740 RPS × 1 RCU = 115,740 RCUs required
  └─ But this is unrealistic sustained load

More realistic (traffic spikes during business hours):
- 8 peak hours/day: 600 RPS = 600 RCU required
- 8 normal hours/day: 150 RPS = 150 RCU required  
- 8 low hours/day: 50 RPS = 50 RCU required
- Average: ~300 RPS = 300 RCUs required

#### Option A: On-Demand Pricing

```
Reads per month:  300 RPS (average) × 86,400 sec/day × 30 days = 777.6B reads
  Billing: 777.6B RCUs / 1,000,000 × $0.25 = $194,400 ❌ EXPENSIVE

Problem: On-demand prices reads individually, so sustained traffic is very costly
```

**Verdict**: ❌ On-demand unsuitable for sustained 600 RPS

#### Option B: Provisioned Pricing (Recommended)

```
Provisioned for 300 RPS (to handle spikes up to 600 RPS):
  Writes: 60 RPS (20% of 300) = 60 WCU × $1.25/month = $75/month
  Reads:  240 RPS (80% of 300) = 240 RCU × $0.25/month = $60/month
  Storage: 1B URLs × 1KB average = 1TB = 1000 GB × $0.25 = $250/month
  
  TOTAL: $385/month ✓ REASONABLE

With auto-scaling enabled:
  - Scales to 600 RCU during peak hours
  - Returns to 300 RCU during normal
  - Still $385/month base (scaling costs included)
```

**Verdict**: ✅ Provisioned 300 RCU/60 WCU is cost-effective

#### Option C: Provisioned Pricing at Lower Scale

```
If traffic is actually only 100 RPS average (from Analytics article):
  Writes: 20 WCU × $1.25 = $25/month
  Reads:  80 RCU × $0.25 = $20/month  
  Storage: 1TB × $0.25 = $250/month
  
  TOTAL: $295/month ✓ EXCELLENT
```

**Key Takeaway**: DynamoDB cost depends heavily on your **actual sustained traffic**, not peak. At 100 RPS sustained = $295/month. At 600 RPS sustained = $385/month. Far better than provisioned PostgreSQL ($500+/month ops).

---

### Cost-Benefit Analysis Across Solutions

| Solution | Traffic | Monthly Cost | Cost per Redirect | Notes |
|----------|---------|-------------|-------------------|-------|
| PostgreSQL MVP | 100 RPS | $226 | $0.24 | Single point of failure |
| DynamoDB | 100 RPS | $295 | $0.03 | Managed, auto-scales |
| DynamoDB | 600 RPS | $385 | $0.004 | Still managed |
| Caching-First | 600 RPS | $1,728 | $0.17 | Operational complexity |
| Edge Computing | 600 RPS | $500-700 | $0.06 | Vendor lock-in |

**Insight**: DynamoDB becomes cheaper than caching solutions when you can tolerate eventual consistency and don't need real-time analytics.

---

---

## Query Patterns in DynamoDB

### Pattern 1: Get Single URL (Primary Key Query)

```python
# Fastest: Direct lookup by primary key
response = dynamodb.get_item(
    TableName='urls',
    Key={'short_code': 'abc123'}
)

# Cost: 1 read unit ($0.00013 per hour if provisioned)
# Latency: 10-30ms
# Consistent read: True (always latest)

result = response.get('Item')
if result:
    return result['long_url']
else:
    return None  # Not found
```

### Pattern 2: List User's Links (GSI Query)

```python
# Query by user_id (via GSI)
response = dynamodb.query(
    TableName='urls',
    IndexName='user_id-created_at',
    KeyConditionExpression='user_id = :uid',
    ExpressionAttributeValues={
        ':uid': 'user@example.com'
    },
    ScanIndexForward=False,  # DESC order (newest first)
    Limit=20
)

# Cost: 1 read unit per 4KB returned
#       If 20 items × 2KB each = 10KB = 3 read units
# Latency: 20-50ms
# Consistency: Eventually consistent (can add ConsistentRead=True)

items = response.get('Items', [])
return items
```

### Pattern 3: Check for Duplicates (GSI Query)

```python
# Query by content_hash to detect duplicates
url_hash = hashlib.sha256(long_url.encode()).hexdigest()

response = dynamodb.query(
    TableName='urls',
    IndexName='content_hash',
    KeyConditionExpression='content_hash = :hash',
    ExpressionAttributeValues={
        ':hash': url_hash
    },
    ProjectionExpression='short_code'
)

# Cost: 1 read unit (sparse query, small result)
# Latency: 15-30ms
# Note: Sparse index (only for duplicate detection, rarely used)

items = response.get('Items', [])
if items:
    return items[0]['short_code']  # Existing code
else:
    return None  # New URL
```

### Pattern 4: Scan (Avoid in Production!)

```python
# ❌ DON'T DO THIS IN PRODUCTION

# Scan reads EVERY item (very expensive)
response = dynamodb.scan(TableName='urls')

# Cost: 1 read unit per 4KB scanned
#       1B URLs × 2KB = 500 read units needed
#       = Extremely expensive!
# Latency: Seconds to minutes
# Use case: Offline analytics only

# Better alternative:
# - Export to S3 (one-time, batch operation)
# - Use Athena for queries
# - Maintain separate analytics table
```

---

## Scaling Strategy

### Auto-Scaling (On-Demand)

```
DynamoDB automatic response to traffic changes:

Traffic: 100 RPS
  → Provisioned capacity: 100 RCU, 100 WCU

Traffic spike to 500 RPS (5x)
  → Within 1 minute: 500 RCU, 500 WCU
  → Handles spike seamlessly
  → No latency impact

Traffic drops back to 100 RPS
  → Within 5 minutes: 100 RCU, 100 WCU
  → Scales down automatically
  → Reduces cost

Billing: Pay for actual consumed capacity
  ├─ Peak hour: 500 RCU × $0.25 = $125 that hour
  ├─ Normal hour: 100 RCU × $0.25 = $25 that hour
  └─ Average cost: adjusts automatically
```

### Handling Hot Partitions

```
Problem: Viral URL (5000 RPS for single code)
         DynamoDB assumes even distribution
         This URL's partition becomes bottleneck

Solution 1: DynamoDB auto-detects and rebalances
  ├─ Adds more resources to that partition
  ├─ Automatic (you don't manage)
  └─ Small latency increase temporarily

Solution 2: Application-level caching
  ├─ Detect: hits to code > 1000/sec
  ├─ Cache locally in API server
  ├─ Serves <1ms without querying database
  └─ Reduces database load to acceptable level

Solution 3: Partition key design
  ├─ Add random prefix: code = "a_abc123"
  ├─ Use 10 prefixes (0-9)
  ├─ Distributes viral URL across 10 partitions
  ├─ Trade-off: Complicates queries
  └─ Only use if truly massive scale
```

---

## Global Tables (Multi-Region)

### Setup for 99.99% Availability

```
Primary region: us-east-1
Replica regions: eu-west-1, ap-southeast-1

Configuration:
  DynamoDB Global Tables
  ├─ Automatically replicates writes
  ├─ Replication latency: < 1 second
  ├─ Automatic failover (no manual intervention)
  └─ All regions can read and write

Cost:
  ├─ Primary region: $250/month (reads + writes)
  ├─ Replica 1: $200/month (reads + replicated writes)
  ├─ Replica 2: $200/month (reads + replicated writes)
  └─ TOTAL: $650/month for 3-region redundancy
```

### Consistency Guarantees

```
Reads from same region: Strong consistency available
  response = dynamodb.get_item(
    ...,
    ConsistentRead=True  # Strongly consistent
  )

Reads across regions: Eventually consistent
  ├─ Read from us-east-1: Strong consistent
  ├─ Read from eu-west-1: May see 100ms-old data
  ├─ Acceptable for most queries
  └─ For critical: Always read from primary

Writes:
  ├─ Write to any region (auto-routes to primary)
  ├─ Replicated to other regions (< 1 sec)
  └─ Immediately readable in source region
```

---

## DynamoDB vs Others: Final Comparison

### When DynamoDB is Best Choice

✓ No operational burden (AWS managed)
✓ Cost-effective at scale ($250-1000/month)
✓ Automatic scaling (no capacity planning)
✓ Global tables (multi-region out-of-the-box)
✓ Fast to implement (< 1 day)
✓ Point-in-time recovery (backups automatic)

### When PostgreSQL is Better

✓ Need complex queries (SQL JOINs)
✓ Have DB team already
✓ Want to avoid vendor lock-in
✓ Need strong consistency everywhere
✓ Have very large object data

### When Cassandra is Better

✓ Need extreme scale (100K+ RPS)
✓ Have DevOps expertise
✓ Want to avoid vendor lock-in
✓ Operating entirely on-premises
✓ Need time-series specific optimizations

---

## Cost Optimization Tips

```
1. Use sparse indexes
   └─ Only index fields used in queries
   └─ Saves storage and replication costs

2. Use projections
   └─ Only fetch attributes you need
   └─ Reduces read units consumed
   Example: ProjectionExpression='short_code,long_url'
   instead of fetching all attributes

3. Batch operations
   └─ BatchGetItem, BatchWriteItem
   └─ Cheaper than individual requests
   └─ 25 items per batch

4. TTL for automatic cleanup
   └─ Expired items auto-deleted
   └─ No manual cleanup cost
   └─ Free operation

5. Use on-demand for unpredictable
   └─ Provisioned if traffic is predictable
   └─ On-demand if traffic varies wildly
   └─ Switch based on actual patterns
```

---

## Summary: Deep Dive 3 (DynamoDB)

**Philosophy**: Pay AWS to handle complexity.

**Key advantages**:
- Operational simplicity (no DBAs needed)
- Cost-effective ($250-650/month for MVP+)
- Automatic scaling (no capacity planning)
- Global tables (multi-region HA)
- Fast implementation (< 1 day)

**Design principles**:
- Use short_code as partition key (unique, even distribution)
- Create GSIs for common queries (user_id, created_at)
- TTL for automatic expiration
- On-demand pricing for variable traffic

**Scaling**:
- Auto-scales to 100K+ RPS
- Handles hot partitions automatically
- Global tables for multi-region

**Best for**: Startups, cost-conscious teams, rapid scaling needs.

---

Next: Reusable patterns, security, and production readiness.
