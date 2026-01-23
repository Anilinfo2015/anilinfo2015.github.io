# Article 10: Reusable Patterns & Cross-Cutting Concerns

## Patterns Transferable to Other Systems

The URL shortener teaches patterns applicable to many system design problems.

---

## Pattern 1: Read-Heavy Caching

**When applicable**: Any system where reads vastly outnumber writes.

```
Examples:
  ✓ News feed (read 1000x, write rarely)
  ✓ Product catalog (read 10000x, write daily)
  ✓ Video metadata (read always, write once)
  ✓ User profiles (read often, write occasionally)
  ✗ Chat system (read ≈ write)
  ✗ Transactions (write-heavy)
```

**Implementation**:
```
1. Cache layer between app and database
2. Set appropriate TTL (based on update frequency)
3. Invalidate on write (or accept eventual consistency)
4. Monitor hit rates (target: 80%+)

For URLs:
  - Cache layer: Redis (hot data)
  - TTL: 1 hour (balance between freshness and memory)
  - Hit rate: 60%+ (expected from Zipfian distribution)
```

**Lessons**:
- Multi-layer caching (CDN + in-memory + local) multiplies benefit
- Eventual consistency acceptable if writes rare
- Hotspot detection crucial (handle viral content)

---

## Pattern 2: Write Deamplification (Async Processing)

**When applicable**: When write operations are expensive or trigger cascades.

```
Examples:
  ✓ Analytics (expensive aggregations)
  ✓ Search indexing (slow to rebuild index)
  ✓ Email notifications (external API calls)
  ✓ Webhook delivery (unreliable)
  ✗ Financial transactions (must be synchronous)
  ✗ Core business logic (can't defer)
```

**Implementation**:
```
1. User action triggers event
2. Add event to queue (fast, < 1ms)
3. Return response immediately
4. Async consumer processes event
5. Side effects happen later (minutes/hours OK)

For URLs:
  - User creates link → return immediately
  - Async: write to database, update analytics
  - User won't notice delay
```

**Lessons**:
- Queue must be reliable (Kafka, not in-memory)
- Consumer must be idempotent (handle retries)
- User-facing response separate from async work
- Accept stale state (analytics delayed)

---

## Pattern 3: Idempotency (Exactly-Once Processing)

**When applicable**: APIs called over unreliable networks.

```
Problem: Network flakiness
  User creates link (POST /links)
    ├─ Server processes: generates code
    ├─ Server inserts: database writes
    ├─ Returns 201 to client
    ├─ Client never receives response (timeout)
    └─ Client retries request

Without idempotency:
  ├─ Retry creates second link
  ├─ Same URL → different short codes
  └─ Broken! (same URL has multiple codes)

With idempotency:
  ├─ Retry returns existing code
  ├─ Same URL → same short code (always)
  └─ Safe!
```

**Implementation**:
```python
def create_link(long_url, idempotency_key):
    """Create link idempotently"""
    
    # 1. Check if we've processed this request before
    cached = cache.get(f"idempotent:{idempotency_key}")
    if cached:
        return cached  # Return cached response
    
    # 2. Check if URL already shortened
    url_hash = hash(long_url)
    existing = db.query("SELECT short_code WHERE hash = ?", url_hash)
    if existing:
        short_code = existing
    else:
        short_code = generate_code()
        db.insert(short_code, long_url, hash)
    
    # 3. Cache the response
    response = {short_code: short_code}
    cache.set(f"idempotent:{idempotency_key}", response, ttl=3600)
    
    return response
```

**Lessons**:
- Idempotency key (from client headers)
- Cache responses temporarily
- Deduplication via URL hash

---

## Pattern 4: Circuit Breaker (Failure Isolation)

**When applicable**: Calling external services or dependencies.

```
Examples:
  ✓ Calling Safe Browsing API (external)
  ✓ Querying database (might fail)
  ✓ Writing to cache (might be down)
  ✓ Calling third-party service
  ✗ Pure computation (doesn't fail)
```

**Implementation**:
```python
from circuitbreaker import circuit

@circuit(
    failure_threshold=5,  # Fail after 5 consecutive errors
    recovery_timeout=60   # Retry after 60 seconds
)
def check_url_safety(url):
    """Check URL with Safe Browsing API"""
    # If this fails 5 times, circuit opens
    # New calls immediately raise CircuitBreakerOpenException
    return safe_browsing_api.check(url)

def create_link(long_url):
    try:
        if not check_url_safety(long_url):
            return 403, "URL blocked"
    except CircuitBreakerOpenException:
        # Service is down, allow anyway (or reject based on policy)
        warn("Safe Browsing API down, allowing URL")
        return allow_unsafe_url(long_url)
    
    return create_link_impl(long_url)
```

**Lessons**:
- Fail fast (don't retry endlessly)
- Automatic recovery (tries again after timeout)
- Graceful degradation (system still works partially)

---

## Pattern 5: Bulkheads (Resource Isolation)

**When applicable**: Multiple workloads competing for resources.

```
Examples:
  ✓ API endpoints (some slow, some fast)
  ✓ Database reads vs. writes
  ✓ User services vs. background jobs
  ✗ Single simple endpoint
```

**Implementation**:
```python
from concurrent.futures import ThreadPoolExecutor

# Separate pools for different workloads
fast_pool = ThreadPoolExecutor(max_workers=20)
slow_pool = ThreadPoolExecutor(max_workers=5)
background_pool = ThreadPoolExecutor(max_workers=10)

def handle_redirect(code):
    """Fast operation, many workers"""
    return fast_pool.submit(redirect_impl, code).result(timeout=1.0)

def check_url_safety(url):
    """Slow operation, few workers"""
    return slow_pool.submit(safety_check_impl, url).result(timeout=10.0)

def background_cleanup():
    """Background job, separate pool"""
    return background_pool.submit(cleanup_impl)

# Benefits:
#  - If safety_check is slow, doesn't block redirects
#  - If redirect gets traffic spike, doesn't starve cleanup
#  - Each workload has guaranteed resources
```

**Lessons**:
- Isolate resource pools per service
- Fast operations get many workers
- Slow operations get few workers
- Prevents cascading failures

---

## Pattern 6: Token Bucket Rate Limiting

**When applicable**: Enforcing quotas, preventing abuse.

```
Examples:
  ✓ API rate limits (free vs. premium)
  ✓ Per-user quotas (100 requests/hour)
  ✓ DDoS protection (1000 requests/IP/minute)
  ✓ Database throttling (max 1000 queries/sec)
  ✗ Bandwidth limits (use different algorithm)
```

**Implementation**:
```python
class TokenBucket:
    def __init__(self, capacity, refill_rate):
        self.capacity = capacity
        self.refill_rate = refill_rate  # tokens/sec
        self.tokens = capacity
        self.last_refill = time.time()
    
    def allow(self, tokens_needed=1):
        now = time.time()
        elapsed = now - self.last_refill
        
        # Add tokens from elapsed time
        self.tokens = min(
            self.capacity,
            self.tokens + self.refill_rate * elapsed
        )
        self.last_refill = now
        
        # Check if allowed
        if self.tokens >= tokens_needed:
            self.tokens -= tokens_needed
            return True
        return False

# For users:
#  - Free: 100 tokens/month = 0.00077 tokens/sec
#  - Premium: 10000 tokens/month = 0.077 tokens/sec

# For API:
#  - 1000 requests/min = 16.67 requests/sec
```

**Lessons**:
- Smooth throttling (no hard cutoffs)
- Burst handling (can exceed average briefly)
- Fair to users (each gets equal capacity)

---

## Pattern 7: Exponential Backoff + Jitter

**When applicable**: Retrying after transient failures.

```
Examples:
  ✓ Temporary database timeouts
  ✓ Network errors (retry later)
  ✓ API rate limits (backoff then retry)
  ✗ Permanent errors (don't retry)
```

**Implementation**:
```python
import random
import time

def retry_with_backoff(func, max_retries=3):
    """Retry with exponential backoff + jitter"""
    
    for attempt in range(max_retries):
        try:
            return func()
        except TemporaryError as e:
            if attempt == max_retries - 1:
                raise  # Give up
            
            # Exponential backoff: 1s, 2s, 4s
            backoff = 2 ** attempt
            
            # Add jitter: ±10% randomness
            jitter = random.uniform(0, backoff * 0.1)
            wait_time = backoff + jitter
            
            print(f"Attempt {attempt + 1} failed, retry in {wait_time:.1f}s")
            time.sleep(wait_time)

# Benefits:
#  ✓ Avoids thundering herd (all retrying at same time)
#  ✓ Gives system time to recover
#  ✓ Fair distribution of retry load
```

**Lessons**:
- Exponential: 1, 2, 4, 8, 16 seconds
- Jitter: ±10% random variation
- Max retries: 3-5 (don't retry forever)
- Timeouts: set per request (prevent hanging)

---

## Pattern 8: Eventual Consistency + Write-Through Cache

**When applicable**: Systems that can tolerate stale reads temporarily.

```
Examples:
  ✓ Analytics (delayed updates OK)
  ✓ User profiles (read-your-own write)
  ✓ Social feeds (eventual consistency fine)
  ✗ Money transfers (strong consistency required)
  ✗ Inventory (can't double-sell)
```

**Implementation**:
```python
def create_link(long_url):
    """Create with write-through cache"""
    
    short_code = generate_code()
    
    # 1. Write to cache immediately
    cache.set(f"url:{short_code}", long_url, ttl=3600)
    
    # 2. Return to user (they see their own write!)
    response = {short_code: short_code}
    
    # 3. Write to database asynchronously
    # (user doesn't wait)
    queue.publish('link_created', {
        'short_code': short_code,
        'long_url': long_url
    })
    
    return response

# Benefits:
#  ✓ User sees their own link immediately (cache)
#  ✓ Other users see eventually (after DB processes)
#  ✓ No waiting for synchronous DB write
```

**Lessons**:
- Cache is source of truth for user
- Database is source of truth for others
- Accept lag (other users see ~1 sec delay)
- Works only for non-critical data

---

## Pattern 9: Denormalization for Performance

**When applicable**: Read-heavy queries over multiple tables.

```
Examples:
  ✓ User view needs user + profile + settings
  ✓ Link view needs link + analytics
  ✓ Feed needs post + user + like count
  ✗ Transactional data (needs normalization)
```

**Implementation**:
```sql
-- Normalized (3 tables, slow to query):
SELECT l.short_code, l.long_url, u.username, a.clicks
FROM links l
JOIN users u ON l.user_id = u.user_id
JOIN daily_analytics a ON l.short_code = a.short_code
WHERE l.short_code = 'abc123'

-- Denormalized (1 table, fast to query):
CREATE TABLE link_view (
  short_code VARCHAR(10) PRIMARY KEY,
  long_url TEXT,
  user_id UUID,
  username VARCHAR(100),
  creator_email VARCHAR(100),
  created_at TIMESTAMP,
  total_clicks INTEGER,
  last_click TIMESTAMP
);

-- Single query:
SELECT * FROM link_view WHERE short_code = 'abc123'

-- Trade-off:
#  ✓ Fast reads (single table)
#  ✗ Slow writes (update multiple fields)
#  ✗ Consistency (must keep in sync)
```

**Lessons**:
- Denormalize for read performance
- Use batch processes to sync
- Acceptable eventual consistency
- Simpler queries, better caching

---

## Summary: Transferable Patterns

| Pattern | Primary Benefit | Where to Use |
|---------|-----------------|--------------|
| **Caching** | Latency reduction (10x) | All read-heavy systems |
| **Async Writing** | Decoupling, user latency | Analytics, side effects |
| **Idempotency** | Safety on retries | All APIs, especially over unreliable networks |
| **Circuit Breaker** | Failure isolation | External service calls |
| **Bulkheads** | Resource isolation | Mixed workload systems |
| **Token Bucket** | Fair rate limiting | Quota enforcement, DDoS prevention |
| **Exponential Backoff** | Graceful degradation | Transient failure recovery |
| **Write-Through Cache** | Best of both worlds | Eventual consistency acceptable |
| **Denormalization** | Read speed | Complex multi-table queries |

Each pattern solves a specific problem. Combine them based on needs.

---

## Next: Security & Production Readiness
