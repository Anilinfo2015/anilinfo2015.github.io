# Article 12: Production Readiness

## What Makes a System "Production Ready"?

A system is production-ready when it can:
1. **Survive failures** without losing data
2. **Scale automatically** without manual intervention
3. **Alert operators** before users notice problems
4. **Recover quickly** from incidents
5. **Comply** with regulations and security requirements

---

## SLA vs. SLO vs. SLI

### Definitions

```
SLA (Service Level Agreement): Contract with users
  ├─ "We guarantee 99.9% uptime"
  ├─ Consequences if breached (credit, compensation)
  └─ Example: 4.3 hours downtime allowed per month

SLO (Service Level Objective): Internal target
  ├─ "We aim for 99.99% uptime" (more aggressive than SLA)
  ├─ No contractual obligation
  ├─ Buffer between SLA and actual performance
  └─ Example: 26 minutes downtime allowed per month

SLI (Service Level Indicator): Actual measurement
  ├─ "Actual uptime this month: 99.95%"
  ├─ Measured from user perspective
  ├─ Combined from multiple metrics
  └─ Example: (Successful requests) / (Total requests)
```

### For URL Shortener

```
SLA (offer to customers):
  ├─ 99.9% availability
  ├─ < 100ms p99 latency
  ├─ 0% data loss
  └─ Credits for breaches

SLO (internal target):
  ├─ 99.95% availability (more aggressive)
  ├─ < 50ms p99 latency (more aggressive)
  ├─ Full compliance with SLA requirements
  └─ Monitor and alert on SLO breaches

SLI (measured):
  ├─ (Successful 2xx responses) / (Total requests)
  ├─ p99 latency from user's perspective
  ├─ Errors/timeouts < 0.1%
  └─ Data durability verified weekly
```

---

## Monitoring: The 4 Golden Signals

### 1. Latency (Response Time)

```
Metrics:
  ├─ p50 (median): 20ms
  ├─ p95: 50ms
  ├─ p99: 100ms
  ├─ p999: 500ms
  └─ Max: < 2s (alert if exceeded)

Where to measure:
  ├─ API server processing time
  ├─ Database query time
  ├─ Cache lookup time
  ├─ End-to-end (from user request to response)

Alerting:
  ├─ If p99 > 200ms for 5 minutes: Warning
  ├─ If p99 > 500ms for 2 minutes: Critical
  └─ If p999 > 2s: Investigate
```

### 2. Traffic (Throughput)

```
Metrics:
  ├─ Requests per second (RPS)
  ├─ Bytes per second (bandwidth)
  ├─ Requests per day (volume)
  └─ Peak RPS

Baselines:
  ├─ Normal: 100-200 RPS
  ├─ High: 200-600 RPS
  ├─ Peak: 600-5000 RPS (viral)
  └─ Crisis: > 5000 RPS

Alerting:
  ├─ If RPS drops > 50% below baseline: Warning (client issue?)
  ├─ If RPS > 5000 for > 10 seconds: Warning (viral content)
  └─ Sustained > 10000: Critical (potential attack)
```

### 3. Errors (Error Rate)

```
Metrics:
  ├─ 4xx error rate: < 0.5% (client errors)
  ├─ 5xx error rate: < 0.01% (server errors)
  ├─ Timeout rate: < 0.001% (connection failures)
  └─ Error by type (404, 500, 503, etc.)

Breakdown by endpoint:
  ├─ GET /{code}: < 0.001% 5xx (most critical)
  ├─ POST /links: < 0.01% 5xx (can be slower)
  ├─ GET /links: < 0.01% 5xx (admin, not critical)

Alerting:
  ├─ If 5xx > 0.01% for 2 minutes: Critical
  ├─ If 4xx > 5%: Investigate (maybe DDoS)
  └─ If 503 (overload): Scale up immediately
```

### 4. Saturation (Resource Usage)

```
Metrics:
  ├─ CPU usage: target < 70%
  ├─ Memory usage: target < 80%
  ├─ Disk usage: target < 70%
  ├─ Network throughput: target < 80%
  ├─ Database connections: target < 70%
  └─ Redis memory: target < 70%

Alerting thresholds:
  ├─ CPU > 80% for 5 minutes: Warning (add capacity)
  ├─ Memory > 85% for 5 minutes: Warning
  ├─ Disk > 80%: Warning (free space needed for logs)
  ├─ Database at 90%+ capacity: Critical (upgrade needed)
  └─ Redis eviction rate high: Warning (cache too small)
```

---

## Observability: Logging, Metrics, Tracing

### Structured Logging

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "INFO",
  "service": "url-shortener",
  "request_id": "req_abc123",
  "user_id": "user@example.com",
  "action": "create_link",
  "short_code": "xyz789",
  "status": "success",
  "latency_ms": 45
}
```

**Key fields**:
- `request_id`: Trace across services
- `user_id`: Correlate to user
- `action`: What operation
- `status`: Result (success/failure)
- `latency_ms`: How long

### Metrics (Prometheus)

```
# Redirect latency
url_shortener_redirect_latency_seconds_bucket{le="0.01"} 420000
url_shortener_redirect_latency_seconds_bucket{le="0.1"} 580000
url_shortener_redirect_latency_seconds_bucket{le="1"} 600000

# Error rate
url_shortener_errors_total{code="404"} 150
url_shortener_errors_total{code="500"} 3

# Cache hit rate
url_shortener_cache_hits_total 540000
url_shortener_cache_misses_total 60000
```

### Distributed Tracing (Jaeger)

```
Trace: request_id=req_abc123

Spans (operations):
  └─ GET /xyz789 (0ms)
     ├─ Cache lookup (1ms) [CACHE_HIT]
     └─ Return 301 (1ms)

Total latency: 2ms (fast!)

Compare to:
  GET /viral_code (0ms)
     ├─ Cache lookup (2ms) [CACHE_HIT]
     ├─ Update click count (25ms) [SLOW!]
     └─ Return 301 (1ms)
  Total: 28ms (slow due to click update)
```

---

## Alerting & On-Call

### Alert Types

```
Severity Levels:

Critical (Page On-Call):
  ├─ 5xx error rate > 1% (users affected)
  ├─ p99 latency > 1s (users experiencing slowness)
  ├─ Database unreachable (complete outage)
  ├─ Memory leak (approaching 100%)
  └─ Data loss detected

Warning (Create Ticket):
  ├─ CPU > 80% (scaling needed soon)
  ├─ 5xx error rate > 0.1% (minor issue)
  ├─ Cache hit rate < 50% (unexpected)
  ├─ Disk > 80% (cleanup needed)
  └─ Replication lag > 5s

Info (Log for Review):
  ├─ Unusual traffic pattern
  ├─ New error type appeared
  ├─ Performance degradation (minor)
  └─ Dependency slowness
```

### Alert Example

```
Alert: HighErrorRate

Condition:
  (5xx errors / total requests) > 0.001  for 2 minutes

Notification:
  └─ To on-call engineer via PagerDuty
  
Message:
  "URL Shortener: 5xx error rate is 0.15%
   Expected: < 0.01%
   
   Links:
   - Dashboard: https://grafana.company.com/dashboard/urls
   - Logs: https://kibana.company.com/logs?service=url-shortener
   
   Suggested actions:
   1. Check latest deployment
   2. Query error logs
   3. Check database health
   4. Consider rollback"
```

---

## Runbooks & Incident Response

### Runbook: Database Overload

```
Symptom:
  - p99 latency > 500ms
  - Error rate > 0.1%
  - Database CPU 90%+

Investigation (5 minutes):
  1. Check database monitoring
     → CloudWatch: CPU, connections, query count
  2. Check recent deployments
     → Did we deploy in last 30 minutes?
  3. Check traffic spike
     → Is traffic > 2x normal?

Quick fixes (5-10 minutes):
  1. If recent deployment: Rollback
  2. If traffic spike: Scale API servers
  3. If slow queries: Kill long-running queries

Long-term fix (hours):
  1. Optimize slow queries
  2. Add indexes
  3. Increase capacity
  4. Add caching layer
```

### Runbook: Cache Failure

```
Symptom:
  - Redis returning errors
  - p50 latency > 50ms (no cache)
  - Database connection count spike

Investigation:
  1. Check Redis health
     → Is Redis process running?
     → Memory usage normal?
  2. Check network
     → Can API reach Redis?
  3. Check monitoring
     → When did Redis errors start?

Quick fixes:
  1. Restart Redis (loses data, but recovers)
  2. Warm cache (pre-populate from database)
  3. Failover to backup node
  4. Scale database if needed

Long-term:
  1. Prevent: Set memory limits, LRU eviction
  2. Prevent: HA Redis cluster
  3. Monitor: Cache hit rate, memory usage
```

---

## Reliability Targets by Component

```
Component          Target      How Measured
────────────────────────────────────────────
Redirect endpoint  99.9%       5xx error rate < 0.1%
Create link        99.9%       5xx error rate < 0.1%
Database           99.99%      Replication lag < 1s
Cache              99.95%      Availability checked
API servers        99.9%       Application errors < 0.1%

Combined system:   99.9%       All endpoints together

Formula:
  99.9% = (1 - (1 - 0.999) * (1 - 0.999) * (1 - 0.9999))
  = 0.9989 = 99.89% (meets target!)
```

---

## Deployment Safety

### Blue-Green Deployment

```
Current (Blue):
  └─ Version 1.5.2 (stable)
  └─ 10 instances, 100% traffic

New (Green):
  └─ Version 1.5.3 (new code)
  └─ 10 instances, 0% traffic (warming up)

Timeline:

T0: Deploy Green
   ├─ New instances launch
   ├─ Health checks pass
   └─ Ready but no traffic

T5: Start traffic shift
   ├─ Blue 90%, Green 10%
   ├─ Monitor error rate, latency
   └─ No issues? Continue

T10: Increase to 50/50

T15: Complete shift
   ├─ Blue 0%, Green 100%
   ├─ Blue instances still running
   └─ If problems: Instant rollback

T20: Verify stable

T25: Tear down Blue
   ├─ Delete old instances
   └─ Save cost
```

### Rollback Plan

```
If issues detected during Green deployment:

Automatic rollback triggered if:
  ├─ Error rate > 1%
  ├─ p99 latency > 1s
  ├─ Database errors spike
  └─ Any critical alert fires

Manual rollback:
  └─ Operations team runs: rollback-deployment.sh
  └─ Immediately routes 100% traffic back to Blue
  └─ Takes < 30 seconds
```

---

## Disaster Recovery

### Recovery Time Objective (RTO)

```
RTO: Maximum acceptable downtime

For URL Shortener: 30 minutes

Scenarios:

Scenario 1: Single server failure
  RTO: < 1 minute (auto-failover)
  Action: LB routes to healthy server

Scenario 2: Database failover
  RTO: < 5 minutes (replica promotion)
  Action: Promote read replica to master

Scenario 3: Regional failure
  RTO: < 30 minutes (manual failover to other region)
  Action: Update DNS, verify data consistency

Scenario 4: Datacenter fire
  RTO: < 1 hour (restore from backup)
  Action: Restore database, re-deploy application
```

### Recovery Point Objective (RPO)

```
RPO: Maximum acceptable data loss

For URL Shortener: 1 minute

Backup strategy:
  ├─ Continuous replication (0 RPO)
  ├─ Daily snapshots (kept 30 days)
  ├─ Weekly backups (kept 1 year)
  └─ Test restore quarterly
```

---

## Operational Disaster Recovery Procedures

### Monthly DR Drill Schedule

**Every first Thursday of the month, 2 PM UTC**:

**1. Failover Database (30 minutes)**
```bash
Timeline:
  T=0:    Declare DR drill start in #incidents Slack
  T=1:    Stop writes to primary database
  T=2:    Verify replica is caught up (lag < 100ms)
  T=3:    Promote read replica to new primary
  T=5:    Update connection strings in app servers
  T=8:    Restart app servers (rolling restart)
  T=15:   Monitor error rates (should stay < 0.01%)
  T=25:   Verify traffic flowing normally
  T=30:   Failback to original primary
  T=35:   Declare drill complete, post summary
```

**Runbook: Database Promotion**:
```sql
-- Step 1: Check replica lag
SELECT EXTRACT(EPOCH FROM (now() - pg_last_wal_receive_lsn() IS NULL)::timestamp);
-- Expected: < 100ms

-- Step 2: Promote replica (on replica server)
SELECT pg_promote();

-- Step 3: Verify new primary
SELECT now(), txid_current();

-- Step 4: Update connection string
# In app config: primary_host = replica-prod-2.internal
# Deploy via: ansible-playbook update-db-config.yaml

-- Step 5: Monitor for errors
-- Watch CloudWatch: RDS/CPUUtilization, DB/WriteLatency
```

**Success Criteria**:
```
✓ Replica promoted in < 5 minutes
✓ App reconnected in < 2 minutes
✓ Error rate stayed < 0.01%
✓ No user impact (read-only spike acceptable)
✓ No data corruption detected
```

---

**2. Redis Failover (15 minutes)**
```bash
Timeline:
  T=0:    Clear all Redis data (controlled)
  T=1:    Monitor hit rate (expected to drop briefly)
  T=3:    Refill cache from database
  T=10:   Verify cache serving requests
  T=15:   Declare complete
```

**Runbook: Redis Cluster Recovery**:
```bash
# Step 1: Identify unhealthy node
redis-cli -h redis-prod-1.internal --cluster info
# Output: nodes down, slots unassigned, etc.

# Step 2: Remove bad node
redis-cli -h redis-prod-1.internal --cluster del-node <node-id>

# Step 3: Add replacement
redis-cli -h redis-prod-1.internal --cluster add-node <new-host>:6379

# Step 4: Rebalance
redis-cli -h redis-prod-1.internal --cluster rebalance <any-host>:6379

# Step 5: Warm cache (async)
python scripts/warm_cache.py --full-refresh
```

**Success Criteria**:
```
✓ Failover detected in < 30 seconds
✓ All 3 nodes healthy again
✓ Slots redistribution complete (< 2 min)
✓ Cache hit rate > 80% after refill
```

---

**3. API Server Rolling Restart (10 minutes)**
```bash
Timeline:
  T=0:    Enter "drain" mode on server 1 (stop new requests)
  T=1:    Wait for in-flight requests (max 5s timeout)
  T=6:    Restart service
  T=7:    Health check (must pass within 30s)
  T=8:    Resume traffic to server 1
  T=10:   Repeat for servers 2-3
```

**Kubernetes Rolling Update**:
```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0        # Never down
      maxSurge: 1              # One extra during update
  template:
    spec:
      terminationGracePeriodSeconds: 30
      containers:
      - name: api
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 15"]  # Give LB time to drain
```

**Success Criteria**:
```
✓ Zero dropped requests during restart
✓ Error rate stayed < 0.01%
✓ p99 latency < 150ms (slightly elevated OK)
✓ All 3 servers back to healthy state
```

---

**4. Backup Restore Test (1 hour)**
```bash
Timeline:
  T=0:    Select yesterday's backup
  T=5:    Spin up staging database
  T=15:   Restore from backup
  T=30:   Run consistency checks
  T=45:   Spot-check random URLs exist
  T=50:   Tear down staging
  T=60:   Document any issues
```

**Restore Procedure**:
```bash
# 1. Get backup ID
aws rds describe-db-snapshots --query 'DBSnapshots[0].DBSnapshotIdentifier'

# 2. Create staging DB from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier url-shortener-staging-restore \
  --db-snapshot-identifier url-shortener-backup-2024-01-25-03-00

# 3. Wait for available (5-15 min)
aws rds describe-db-instances --query 'DBInstances[0].DBInstanceStatus'

# 4. Run consistency checks
psql -h staging.internal -U admin -d urlshortener -c \
  "SELECT COUNT(*) as total_urls FROM links; \
   SELECT COUNT(DISTINCT short_code) as unique_codes FROM links; \
   SELECT COUNT(*) as corrupted FROM links WHERE long_url IS NULL;"

# 5. Verify backups are point-in-time recoverable
aws rds describe-db-backup-recovery-point-for-db-instance \
  --db-instance-identifier url-shortener-prod
```

**Success Criteria**:
```
✓ Restore from backup completes successfully
✓ Row count matches expected value (±1%)
✓ No NULL URLs in dataset
✓ Backup is incremental (< 2GB delta daily)
✓ Recovery process documented for team
```

---

### Incident Response Runbooks

**Runbook 1: Database Down (Complete Outage)**

```
INCIDENT: Database unreachable, all write requests failing

SEVERITY: P1 (Critical)
PAGE: On-call DBA

DETECTION:
  Alert fires: "RDS Connection Refused"
  App logs show: "Connection timeout to db.internal:5432"

IMMEDIATE ACTIONS (1 minute):
  [ ] Page on-call DBA
  [ ] Post in #incidents: "DB down, investigating"
  [ ] Check AWS Health Dashboard (is it AWS issue?)
  
  If AWS issue:
    -> Wait for AWS to fix, monitor status page
    
  If our issue:
    -> Continue to diagnosis

DIAGNOSIS (2-3 minutes):
  [ ] SSH to RDS proxy server
  [ ] Check connectivity: `telnet db.internal 5432`
  [ ] Check RDS console: Is instance still running?
  [ ] Check security groups: Is traffic allowed?
  [ ] Check replication lag: Is replica up?

RECOVERY OPTIONS:

Option A: Restart database (fastest if just hung)
  aws rds reboot-db-instance --db-instance-identifier url-shortener-prod
  Wait: 2-5 minutes for restart
  Risk: Momentary additional outage

Option B: Failover to read replica
  aws rds failover --db-cluster-identifier url-shortener-prod
  Wait: 30 seconds to 1 minute
  Impact: Read-only briefly, then normal

Option C: Restore from backup (data loss risk)
  Use if database is corrupted
  RTO: 30 minutes

RECOMMENDED: Try Option A first (usually 3-min total outage)

VERIFICATION (every 30 seconds):
  [ ] Can we connect to database?
  [ ] Are queries returning data?
  [ ] Error rate back to < 0.01%?
  
COMMUNICATION:
  T=0:    "#incidents: Database down"
  T=3:    "#incidents: Restarting database"
  T=5:    "#incidents: Database back online"
  T=5:    "#incidents: Investigating root cause"

ROOT CAUSE ANALYSIS (within 24 hours):
  [ ] Check database logs for what caused it
  [ ] Common causes: OOM (max connections), slow query, disk full
  [ ] Implement monitoring to detect earlier next time
  [ ] Document lesson in postmortem
```

**Runbook 2: Redis Down (Graceful Degradation)**

```
INCIDENT: Redis unreachable, cache misses, slower responses

SEVERITY: P2 (Serious, not critical)
PAGE: On-call backend engineer

DETECTION:
  Alert fires: "Redis connection timeout"
  Metrics show: Cache hit rate dropped from 85% to 0%
  
  APP BEHAVIOR: Still working! (reads go to database)
  P99 latency increased to ~300ms (was 50ms)
  Database CPU spiked to 70%

IMMEDIATE ACTIONS:
  [ ] Page on-call (but not emergency page)
  [ ] Post in #incidents: "Redis down, service degraded"
  [ ] Users will notice slower redirects
  [ ] No data loss, no user-facing errors

DIAGNOSIS:
  [ ] Can we connect? `redis-cli ping`
  [ ] Is node running? `systemctl status redis` or `docker ps | grep redis`
  [ ] Check memory: `redis-cli INFO memory`
  [ ] Check replication: `redis-cli INFO replication`

RECOVERY OPTIONS:

Option A: Restart Redis
  systemctl restart redis
  or: docker restart redis-container
  Wait: 10-30 seconds
  Risk: Brief additional slowness while warming
  Recommended if: Redis ran out of memory, got stuck

Option B: Failover to replica (if using cluster)
  redis-cli FAILOVER
  Wait: < 2 seconds
  Risk: Minimal
  Recommended if: Single node down in cluster

Option C: Take outage, rebuild from snapshot
  Risk: Data loss from last snapshot
  Only use if: Corrupted data detected

RECOMMENDED: Try Option A (restart)

VERIFICATION:
  [ ] `redis-cli PING` returns PONG
  [ ] `redis-cli DBSIZE` returns expected size
  [ ] Cache hit rate climbing back to 85%+
  [ ] Database CPU returning to normal

COMMUNICATION:
  T=0:    "#incidents: Redis down, service degraded"
  T=1:    "#incidents: Restarting Redis"
  T=2:    "#incidents: Redis online, recovering cache"
  T=5:    "#incidents: Back to normal performance"

WARMING CACHE:
  After Redis comes back, cache is empty
  Request traffic will refill it over 5 minutes
  Can optionally warm manually:
    python scripts/warm_cache.py --popular-only
```

**Runbook 3: High Error Rate (5xx Errors)**

```
INCIDENT: Error rate spiking to 1%+, users seeing failures

SEVERITY: P2 (needs quick response)
PAGE: On-call backend engineer

DETECTION:
  Alert: "Error rate > 1% for 1 minute"
  Metrics show: 5xx errors at 2%
  
  User impact: 1 in 50 requests failing

IMMEDIATE DIAGNOSIS:
  1. Check if specific endpoint affected:
     curl https://api.shortener.com/api/shorten -v
     curl https://api.shortener.com/r/abc123 -v
  
  2. Check recent deployments:
     kubectl rollout history deployment/api
     
  3. Check error logs:
     kubectl logs -f deployment/api --tail=100

COMMON CAUSES:
  
  A) Bad deployment (most common)
     [ ] Rollback: kubectl rollout undo deployment/api
     [ ] Verify: Error rate drops
     [ ] Impact: Takes 2 min, no data loss
     
  B) Downstream service down (Redis, DB)
     [ ] Check connection status
     [ ] See appropriate runbook (Database Down, Redis Down)
     
  C) Resource exhaustion
     [ ] Check CPU/memory: kubectl top pods
     [ ] Scale up: kubectl scale deployment api --replicas=5
     [ ] Watch load balance across new replicas
     
  D) DDoS or traffic spike
     [ ] Check traffic volume: 10x normal?
     [ ] Enable rate limiting: apply rate-limit-config.yaml
     [ ] Scale horizontally: kubectl scale deployment api --replicas=10

RECOMMENDED ACTION ORDER:
  1. Rollback deployment (takes 2 min)
  2. If still failing: Scale up pods (takes 1 min)
  3. If still failing: Check downstream services
  4. If still failing: Page on-call manager

VERIFICATION:
  [ ] Error rate < 0.1%
  [ ] All endpoints responding
  [ ] Response times normal
  [ ] User reports of errors stop

COMMUNICATION:
  T=0:    "#incidents: Error spike detected, investigating"
  T=2:    "#incidents: Rolling back recent deployment"
  T=5:    "#incidents: Error rate back to normal"
  T=10:   "#incidents: Incident closed, will investigate root cause"
```

---

### DR Metrics & Reporting

**Monthly DR Report Template**:

```
Date: January 31, 2024
Conducted by: On-call team

DRILLS COMPLETED:
  [x] Database failover (30 min)
  [x] Redis restart (15 min)
  [x] API rolling restart (10 min)
  [x] Backup restore test (60 min)
  TOTAL TIME: 115 minutes
  SCHEDULE: Thursday 2 PM UTC

ISSUES FOUND:
  1. Database recovery took 7 min (target: 5 min)
     - Cause: Replica lag was 500ms at drill start
     - Fix: Tighten replication lag alert threshold
     
  2. Backup restore failed on first try
     - Cause: Old backup had missing indexes
     - Fix: Rebuilt indexes, will recreate older backups

INCIDENTS THIS MONTH:
  - Database hung (1 incident, resolved in 4 min)
  - Redis crash (1 incident, resolved in 2 min)
  Total downtime: 6 minutes (99.92% uptime vs 99.9% target)

FAILURES IN TESTING:
  - Database failover: PASS
  - Redis failover: PASS (but one replica had issues)
  - App server rolling restart: PASS
  - Backup restore: PASS (after rebuild)
  
UPTIME METRICS:
  Target SLA: 99.9% (4.3 hours downtime/month)
  Actual: 99.92% (3.5 hours downtime/month)
  Status: ✓ MET

RECOMMENDATIONS FOR NEXT MONTH:
  1. Tighten replication lag alert to 200ms
  2. Rebuild older backups to ensure recoverability
  3. Practice multi-region failover (not done yet)
```

---

## Summary: Production Readiness

**Key concepts**:
- SLA (contract) vs. SLO (internal goal) vs. SLI (measurement)
- 4 Golden Signals: Latency, Traffic, Errors, Saturation
- Observability: Logs, metrics, traces (LMT)
- Alerting: Right severity, right channel, right time
- Runbooks: Documented recovery procedures
- Deployment: Safe practices (canary, blue-green)
- Disaster recovery: RTO/RPO targets

**Reliability targets**:
- 99.9% uptime (4.3 hours downtime/month)
- < 100ms p99 latency
- < 0.01% 5xx error rate
- Zero data loss (3-way replication)

**Before production launch**:
- ☑ Monitoring dashboards built
- ☑ Alerts configured and tested
- ☑ Runbooks written for common failures
- ☑ Disaster recovery tested
- ☑ SLA documented and agreed
- ☑ On-call rotation scheduled
- ☑ Incident response process defined

---

## Final Notes

A URL shortener starts simple (one table, one server) but teaches profound lessons:

**On Scale**:
- Database bottlenecks appear at 100 RPS (not millions)
- Caching multiplies capacity by 90%
- Async processing eliminates latency

**On Reliability**:
- Single points of failure kill SLAs
- Circuit breakers prevent cascades
- Observability is non-negotiable

**On Operations**:
- Runbooks save lives (and sleep)
- Safe deployments prevent incidents
- Honest SLOs build trust

**On Design**:
- Trade-offs exist in every dimension
- Simplicity scales better than cleverness
- Managed services beat self-hosted

Build systems you can operate. That's the real skill.

---

**End of Series**: You now understand how to design, scale, and operate a production system.

The patterns here apply to news feeds, e-commerce, social networks, and beyond.

Master the fundamentals. The rest is variation.
