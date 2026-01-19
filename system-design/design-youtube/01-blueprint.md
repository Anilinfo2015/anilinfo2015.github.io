---
layout: default
title: "The Blueprint: From Requirements to Architecture"
description: "Learn how to architect a YouTube-scale system from first principles, starting with requirements and moving through high-level design"
category: "System Design"
tags: ["youtube", "system-design", "architecture", "video-streaming", "scalability"]
date: 2026-01-19
---

# The Blueprint: From Requirements to Architecture

When you hit play on a YouTube video, thousands of engineers' work converges in your browser in about 2 seconds. From a creator uploading a 4K video on unreliable WiFi to you watching it across the globe with adaptive quality—the system behind YouTube is one of the most complex distributed systems ever built.

This is Part 1 of our deep dive: *The Blueprint*. We'll walk through how to architect a YouTube-scale system from first principles, starting with the brutal requirements, moving through the high-level design, and previewing the technical challenges that make each deep dive necessary.

Let's start with a reality check: **Why is YouTube actually hard?**

---

## Why YouTube is Hard: The Scale Numbers

YouTube serves 2.5 billion monthly active users. On an average day, 100 million of them use the platform. At peak hours (7-11 PM), 1-2 million people stream videos simultaneously. This sounds like a number until you actually think about what it means.

Imagine you're building a system where:

- **1 million people are watching videos right now.** Each one needs a unique stream at potentially different quality levels. That's 1 million concurrent requests, just for playback.
- **Every second, 1 million video views are recorded.** Your database can't handle writes at that rate. You need sharded counters in Redis.
- **500,000 hours of video are uploaded daily.** That's 57 hours uploaded every second. Each video needs transcoding into 6+ quality levels, 3+ codecs. The math: 500K hours × 6 qualities × 3 codecs = 9 million transcode jobs per day, or about 100 jobs per second.
- **Bandwidth dominates cost and failure modes.** The platform serves **5-30 petabits per second** at peak. A single byte of optimization saves millions in CDN costs annually.

Here's the kicker: YouTube **cannot afford to lose a frame**. When you click play, you expect video in 2 seconds. A 5-second startup time feels broken. In a system this massive, 1% of users is 1 million people. A single bug that adds 100ms of latency affects millions. Graceful degradation—serving *something* even when parts of the system fail—is not optional.

**The real challenge:** Every design decision ripples through the entire system. Use a single database for view counts? You're limited to ~10,000 writes per second. Need 1 million? You need sharding. Add sharding? Now you need eventual consistency, caching strategies, and reconciliation jobs. Each decision creates new problems to solve.

---

## Functional Requirements: What Users Actually Do

Let's ground this in three user journeys:

### Creator: Upload a Video

Sarah is a music producer. She records a 2-hour live session on her laptop (2GB file). Her internet is sketchy. She expects:

1. **Resume capability**: If her upload disconnects at 80%, she picks up where she left off, not from the start.
2. **Automatic transcoding**: Her one source video becomes watchable on everything—a 480p version for phone, 1080p for desktop, 2160p for the 1% with 4K screens.
3. **Multiple codecs**: Older browsers get H.264, modern ones get VP9 (smaller file size), and maybe AV1 if she waits an extra hour.
4. **Metadata**: Title, description, tags, thumbnail. The system must understand: this is music, searchable by song name and artist.
5. **Publishing control**: Draft, unlisted, public. Schedule publish date for tomorrow morning.
6. **Analytics**: Views, likes, watch time, retention curves. 24 hours after upload.
7. **Authentication & authorization**: Only Sarah can edit her video. Only authorized accounts can delete or modify metadata. API tokens secure uploads with per-user quotas.

**SLA**: Upload should complete within a reasonable time (a few hours for processing). If processing fails, she gets notified and can retry.

### Viewer: Find and Watch

Marcus wakes up, opens YouTube on his phone. He expects:

1. **Discovery**: Homepage shows personalized recommendations—videos he might like based on his history.
2. **Search**: He types "javascript tutorial", gets 100,000+ results in <200ms, sorted by relevance.
3. **Playback startup**: <2 seconds from click to video playing. Network adaptivity: if he's on LTE, he gets 720p; if on WiFi, 1080p.
4. **Smooth watching**: No buffering. The player downloads the next segment while current plays. If network drops, it degrades gracefully to lower quality instead of freezing.
5. **Real-time engagement**: He likes a video. Counter increments within a second. He scrolls to comments, sees the top 20. Sees "5.2M views"—updated in real-time.
6. **History**: Next time he opens YouTube, it remembers where he left off. History is searchable.
7. **Rate limiting**: Fair use policy prevents abuse (e.g., max 10,000 API calls per hour per user, burst allowance for legitimate apps).

**SLA**: Streaming must not buffer. Playback startup must be <5s p95. Search must be <200ms p95.

### Creator Analytics: Understand Audience

Sarah watches her analytics dashboard. She expects:

1. **Real-time metrics**: View count, like rate, comment rate. Updated live as her video gains traction.
2. **Retention graph**: Where do viewers drop off? 50% watch to 3 minutes, 20% to 10 minutes.
3. **Traffic sources**: Where do viewers come from? Search, recommendations, external links?
4. **Audience demographics**: What countries, devices, languages?
5. **Monetization**: Estimated revenue, ad impressions, clicks.

**SLA**: Analytics should be available within 60 seconds of a view being recorded (eventual consistency). Historical data should be queryable down to per-video, per-hour granularity.

---

## Non-Functional Requirements: The Hidden Complexity

Behind every user expectation lies a non-functional requirement:

| Requirement | Target | Why It Matters |
|---|---|---|
| **Availability** | 99.9% (streaming), 99.99% (metadata API) | 99% downtime = 87.6 hours/year. Users switch to TikTok. |
| **Latency (P95)** | Video startup <5s, search <200ms, API <1s | P99 latency often ignored; P95 is what users feel. |
| **Consistency** | Strong for metadata, eventual for counters | View counts 5 minutes stale is acceptable. Video titles must never be inconsistent. |
| **Scalability** | 1M concurrent viewers, 1M view QPS | No single point of failure. Horizontal scaling, not vertical. |
| **Durability** | 11 nines (99.999999999% durability in S3) | A user's upload is precious. Losing it is lawsuit-tier. |
| **Security** | DRM, geo-blocking, copyright protection, auth tokens | Piracy costs studios billions. DMCA compliance is legal requirement. Unauthorized access must be prevented. |
| **Cost** | $100-200M/year for infrastructure | Every architectural decision has $/month impact. |

---

## Authentication & Authorization Design

At YouTube's scale, authentication and authorization are critical. Every API call must verify "who is this user?" and "what are they allowed to do?"

### Authentication Strategy

**Token-Based Authentication with JWT (JSON Web Tokens)**

```javascript
// Client: Upload initiation
POST /api/v1/videos/upload/initiate
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Body: { fileName, fileSize, metadata }

// Server validation:
// 1. Extract token from Authorization header
// 2. Verify token signature using secret key
// 3. Decode payload: { userId, exp, iat, scopes }
// 4. Check expiration: if exp < now, token is invalid
// 5. Check scopes: if "upload:video" not in scopes, deny
// 6. Process request as userId
```

**JWT Advantages:**
- Stateless (no session database lookup for every request)
- Scales horizontally (any server can verify the signature)
- Expirable (short-lived tokens, e.g., 1 hour)
- Scope-based (fine-grained permissions)

**Key Management:**
- Signing key stored in secure vault (not source code)
- Rotated every 90 days
- Different keys for different services (upload, analytics, comments)
- Public key distributed to edge servers for verification

### Authorization: Per-User Quotas

Different users have different limits:

| User Type | Upload QPS | API Rate Limit | Storage Quota |
|---|---|---|---|
| **Regular user** | 0 (must use web UI) | 100 req/hour | 1 TB |
| **Creator (verified)** | 10 | 1,000 req/hour | 1 PB |
| **Partner (music label)** | 100 | 10,000 req/hour | Unlimited |
| **YouTube internal** | Unlimited | Unlimited | Unlimited |

**Implementation:**

```javascript
// Rate limiter middleware
async function checkRateLimit(userId, endpoint) {
  const quota = await getQuota(userId); // Redis lookup
  const key = `rate_limit:${userId}:${endpoint}`;
  const current = await redis.get(key);
  
  if (current >= quota.requestsPerHour) {
    throw new Error('Rate limit exceeded');
  }
  
  // Token bucket: refill 1 token per 3.6 seconds
  await redis.incr(key);
  await redis.expire(key, 3600); // Reset every hour
}
```

**Per-User Upload Quota:**

```javascript
// Creator uploads a video: check storage quota
const creator = await getCreator(userId);
const existingStorage = await S3.getSizeOfBucket(`creator-${userId}`);
const newFileSize = uploadedFile.size;

if (existingStorage + newFileSize > creator.storageQuota) {
  throw new Error('Storage quota exceeded');
}
```

### OAuth 2.0 for Third-Party Apps

YouTube creators use third-party tools (analytics, scheduling, editing). These tools need safe access without knowing the creator's password.

**OAuth flow:**
```
1. Creator authorizes app: "App X wants access to my videos"
2. YouTube issues token (scoped: "read:videos, write:metadata")
3. App uses token to call API: GET /videos?scope=read:videos
4. Token expires in 30 days
5. App refreshes token if needed
6. Creator can revoke app access anytime
```

**Benefits:**
- Creator's password never shared with third-party
- Token is revocable
- Permissions are granular
- Audit trail: which apps accessed what

---

## Rate Limiting & Quotas Strategy

At 1M QPS, protecting the system from abuse is critical.

### Token Bucket Algorithm

Each user gets a bucket. Bucket fills with tokens. Each request costs 1 token.

```
Bucket size: 100 tokens (burst capacity)
Refill rate: 1 token per 3.6 seconds (= 1000 tokens/hour)

User makes 150 requests at once:
  ├─ First 100: Success (use all bucket tokens)
  ├─ Requests 101-150: Fail (bucket empty, must wait)
  ├─ Wait time: 180 seconds (until 50 more tokens generated)
  └─ Result: User can burst, but is rate-limited over time
```

**Per-user quotas (Redis implementation):**

```javascript
async function acquireToken(userId, costPerRequest = 1) {
  const key = `quota:${userId}`;
  const tokensAvailable = await redis.get(key);
  
  if (!tokensAvailable) {
    // First request: initialize bucket
    await redis.setex(key, 3600, 100); // 100 tokens, 1-hour window
    return true;
  }
  
  if (tokensAvailable >= costPerRequest) {
    // Deduct cost
    await redis.decrby(key, costPerRequest);
    return true;
  }
  
  // No tokens: reject and tell client to retry
  throw new RateLimitError({
    retryAfter: Math.ceil(costPerRequest / (1000/3600)) // seconds
  });
}
```

### Global Rate Limiting

Prevent any single upstream source (like a botnet) from overwhelming the system.

```
Global threshold: 100K QPS across all users
├─ If aggregate QPS > 100K, reject bottom 1% of requests
├─ Prioritize authenticated users over anonymous
├─ Prioritize reads over writes
└─ Result: System never overloaded; graceful degradation
```

### Quota-Based Costs

Different operations cost different amounts (e.g., API calls, storage):

```javascript
// Search request: cheap (read-only)
async searchVideos(query) {
  await acquireToken(userId, cost = 1);
  return elasticsearch.search(query);
}

// Upload initiation: expensive (will consume resources)
async initiateUpload(fileSize) {
  await acquireToken(userId, cost = 10); // 10x more expensive
  return createUploadSession(fileSize);
}

// Transcode to AV1: very expensive (compute-intensive)
async requestAV1Transcode(videoId) {
  await acquireToken(userId, cost = 100); // 100x more expensive
  return prioritizeTranscodeJob(videoId, 'av1');
}
```

---

## High-Level Architecture: Control Plane vs Data Plane

At the highest level, YouTube's architecture splits into two planes:

### Control Plane: The Metadata API

This is the "slow" part. It handles metadata—video information, user data, comments, likes, search. Latency tolerance is higher (200ms is fine), but consistency is strict (your video title must never flicker). It's called "control" because it controls what gets served.

**Components**:
- **API Gateway**: Routes 50K QPS metadata requests from users to microservices
- **Video Metadata Service**: CRUD for video information (title, description, duration, codec info)
- **User Service**: Authentication, profiles, subscriptions
- **Search Service**: Full-text index on 100M+ videos, serves 350 search queries per second
- **Analytics API**: Returns aggregated view counts, likes, demographics
- **Cache Layer**: Redis caching metadata (title, duration) with 60s TTL; hit rate ~95%
- **Primary Database**: PostgreSQL storing all metadata; 100M videos, 1B users, 10B+ comments
- **Secondary Database**: Elasticsearch for full-text search; eventually consistent with 5-10 min lag

### Data Plane: Video Upload, Processing, Delivery

This is the "fast" part. It's where video flows: raw upload → transcoding → storage → CDN delivery. Throughput is king. Consistency is relaxed (eventual is fine; a view counter can lag).

**Components**:
- **Upload Service**: Receives 57 hours of video per second, 5-10MB chunks, handles resumable uploads
- **Transcoding Farm**: 4,166 GPU cores, converts source video into 6+ qualities × 3 codecs
- **Object Storage**: S3, 5,000+ PB, stores all transcoded video segments
- **Content Delivery Network (CDN)**: 500+ edge nodes globally, caches video segments, serves 90%+ of playback
- **Playback Service**: Generates manifest files (HLS/DASH playlists), handles quality negotiation
- **Analytics Engine**: Real-time event streaming (Kafka), aggregates view/like/comment events
- **Cache Layer**: Redis sharded counters for 1M QPS view updates; 100 shards × 10K QPS each

```mermaid
flowchart LR
    subgraph ControlPlane["CONTROL PLANE - Metadata & APIs"]
        Users["👥 Users<br/>2.5B MAU"]
        APIGw["API Gateway<br/>50K QPS<br/>Auth + Rate Limit"]
        MetadataService["Metadata Service<br/>Title, Duration, Codec"]
        UserService["User Service<br/>Auth, Profiles"]
        SearchService["Search Service<br/>350 QPS<br/>100M Videos"]
        AnalyticsAPI["Analytics API<br/>Views, Likes, Demographics"]
        RedisCache["Redis Cache<br/>60s TTL<br/>95% Hit Rate"]
        PostgreSQL[("PostgreSQL<br/>Primary DB<br/>100M Videos<br/>1B Users<br/>10B+ Comments")]
        Elasticsearch[("Elasticsearch<br/>Search Index<br/>5-10m Lag")]
    end
    
    subgraph DataPlane["DATA PLANE - Video Processing & Delivery"]
        Creators["🎬 Creators<br/>Upload 57hrs/sec<br/>Auth Required"]
        UploadService["Upload Service<br/>Resumable Uploads<br/>Per-user quotas<br/>5-10MB Chunks"]
        TranscodeFarm["Transcoding Farm<br/>4166 GPU Cores<br/>6 Qualities × 3 Codecs"]
        S3Storage[("S3 Storage<br/>5000+ PB<br/>All Transcoded Video")]
        CDN["CDN<br/>500+ Edges<br/>90% Hit Rate<br/>5-30 Pbps Peak"]
        PlaybackService["Playback Service<br/>HLS/DASH Manifest<br/>Quality Negotiation"]
        Watchers["👁️ Watchers<br/>1M Concurrent<br/>Rate Limited"]
    end
    
    subgraph Analytics["ANALYTICS PIPELINE"]
        Kafka["Kafka<br/>View/Like/Comment Events<br/>1000 Partitions<br/>1M QPS"]
        StreamProcessor["Stream Processor<br/>Real-time Aggregation<br/>10s Windows"]
        RedisAnalytics["Redis Shards<br/>100 Shards<br/>Counter Aggregation"]
        DataLake[("Data Lake<br/>S3 + BigQuery<br/>Historical Analysis")]
    end
    
    Users -->|"Query metadata<br/>50K QPS<br/>Auth + Quota Check"| APIGw
    APIGw -->|"Route requests"| MetadataService
    APIGw -->|"Search queries<br/>350 QPS"| SearchService
    APIGw -->|"Analytics queries"| AnalyticsAPI
    
    MetadataService -->|"Cache lookup"| RedisCache
    MetadataService -->|"Fetch/Update"| PostgreSQL
    SearchService -->|"Index queries"| Elasticsearch
    AnalyticsAPI -->|"Read counts"| RedisAnalytics
    
    PostgreSQL -.->|"CDC Change Events"| Elasticsearch
    
    Creators -->|"Upload video<br/>Auth tokens<br/>Per-user quota"| UploadService
    UploadService -->|"Store raw video"| S3Storage
    UploadService -->|"Create metadata"| PostgreSQL
    
    S3Storage -->|"Read source video"| TranscodeFarm
    TranscodeFarm -->|"Store transcoded<br/>H.264/VP9/AV1"| S3Storage
    
    S3Storage -->|"Cache<br/>90% requests"| CDN
    CDN -->|"Deliver video<br/>2s startup"| Watchers
    
    Watchers -->|"Record view/like<br/>Rate limited<br/>1M QPS"| Kafka
    Kafka -->|"Real-time events<br/>1M QPS"| StreamProcessor
    StreamProcessor -->|"Aggregated counts<br/>10s windows"| RedisAnalytics
    Kafka -->|"7-day retention"| DataLake
    
    style ControlPlane fill:#e1f5ff
    style DataPlane fill:#f0f4c3
    style Analytics fill:#ffe0b2
    style PostgreSQL fill:#81c784
    style Elasticsearch fill:#64b5f6
    style RedisCache fill:#ef5350
    style RedisAnalytics fill:#ef5350
    style CDN fill:#ba68c8
```

---

## Core Entity Model: The Data Structures

Every system is defined by its entities. In YouTube, the core entities are:

### Video

```json
{
  "video_id": "dQw4w9WgXcQ",
  "user_id": "UCfV36TX5AejfAGIbtwTc8Zw",
  "title": "Rick Astley - Never Gonna Give You Up",
  "description": "The official video for \"Never Gonna Give You Up\"...",
  "duration_seconds": 213,
  "status": "published",
  "visibility": "public",
  "upload_date": "2009-10-25T01:54:41Z",
  "view_count_snapshot": 1_400_000_000,
  "like_count_snapshot": 14_000_000,
  "comment_count_snapshot": 2_800_000,
  "tags": ["80s", "pop", "music video"],
  "category": "Music",
  "language": "en",
  "available_codecs": {
    "h264": [480, 720, 1080],
    "vp9": [720, 1080],
    "av1": [1080]
  },
  "s3_path": "s3://youtube-videos/dQw4w9WgXcQ/",
  "cdn_path": "https://cdn.example.com/videos/dQw4w9WgXcQ/"
}
```

Stored in PostgreSQL (strong consistency). Indexed for fast metadata lookups. Cached in Redis for 60s.

### User

```json
{
  "user_id": "UCfV36TX5AejfAGIbtwTc8Zw",
  "email": "rickastley@example.com",
  "username": "rickastley",
  "channel_name": "Rick Astley Official",
  "subscriber_count": 45_000_000,
  "is_verified": true,
  "created_at": "2009-01-21T00:00:00Z",
  "profile_picture_url": "https://cdn.example.com/avatars/..."
}
```

Stored in PostgreSQL. Session tokens cached in Redis (30-min TTL).

### View (Engagement Event)

```json
{
  "event_id": "evt_x9z2k1",
  "video_id": "dQw4w9WgXcQ",
  "user_id": "UCuser123",
  "timestamp": "2024-01-18T14:32:10.123Z",
  "watch_duration_seconds": 45,
  "quality_watched": "1080p",
  "codec_watched": "vp9"
}
```

This is NOT stored in a traditional database. Instead, it flows through Kafka (the event stream) into real-time aggregation and a data lake. Counts are sharded across Redis.

### Comment

```json
{
  "comment_id": "cmt_abc123",
  "video_id": "dQw4w9WgXcQ",
  "user_id": "UCuser456",
  "text": "Iconic video!",
  "likes": 12_345,
  "created_at": "2024-01-18T14:32:10Z",
  "status": "published"
}
```

Stored in PostgreSQL. Indexed by (video_id, created_at) for fast "top 20 comments" queries.

```mermaid
erDiagram
    USER ||--o{ VIDEO : creates
    USER ||--o{ VIEW : records
    USER ||--o{ LIKE : gives
    USER ||--o{ COMMENT : posts
    VIDEO ||--o{ VIEW : "has"
    VIDEO ||--o{ LIKE : receives
    VIDEO ||--o{ COMMENT : "has"
    VIDEO ||--o{ VIDEOMETADATA : "has metadata"
    
    USER {
        string user_id PK
        string email UK
        string username UK
        string channel_name
        int subscriber_count
        boolean is_verified
        timestamp created_at
        string profile_picture_url
    }
    
    VIDEO {
        string video_id PK
        string user_id FK
        string title
        string description
        int duration_seconds
        string status
        string visibility
        timestamp upload_date
        bigint view_count_snapshot
        bigint like_count_snapshot
        bigint comment_count_snapshot
        string[] tags
        string category
        string language
    }
    
    VIDEOMETADATA {
        string video_id PK
        string s3_path
        string cdn_path
        json available_codecs
        string[] quality_tiers
    }
    
    VIEW {
        string event_id PK
        string video_id FK
        string user_id FK
        timestamp timestamp
        int watch_duration_seconds
        string quality_watched
        string codec_watched
    }
    
    LIKE {
        string like_id PK
        string video_id FK
        string user_id FK
        timestamp created_at
    }
    
    COMMENT {
        string comment_id PK
        string video_id FK
        string user_id FK
        string text
        int likes
        timestamp created_at
        string status
    }
```

---

## API Examples: The Contract

The API defines how the front-end talks to the back-end. Here are the critical paths:

### Upload Initiation

```
POST /api/v1/videos/upload/initiate

Headers:
  Authorization: Bearer <JWT_TOKEN>

Request:
{
  "fileName": "my_video.mp4",
  "fileSize": 1073741824,  // 1 GB
  "videoMetadata": {
    "title": "My Video",
    "description": "...",
    "tags": ["tutorial", "coding"],
    "visibility": "draft"
  }
}

Response:
{
  "uploadSessionId": "sess_abc123def456",
  "chunkSize": 5242880,  // 5 MB
  "totalChunks": 205,
  "storageUrl": "https://upload.example.com/upload/sess_abc123def456"
}

Latency: 50ms (create session in DB, generate session ID)
Auth: Verified JWT, checked per-user upload quota
Rate Limit: Creator quota = 10 uploads/hour
```

### Upload Chunk

```
POST /api/v1/videos/upload/sess_abc123def456/chunk/0

Headers:
  Authorization: Bearer <JWT_TOKEN>
  X-Chunk-Index: 0
  X-Total-Chunks: 205

Body: Raw binary data (5 MB)

Response:
{
  "chunkIndex": 0,
  "status": "uploaded",
  "etag": "abc123xyz"  // For retry/resume
}

Latency: 100-500ms (depends on upload speed)
Auth: Token-based, idempotency key in session ID
Rate Limit: Applies to total upload throughput
```

### Get Video Info

```
GET /api/v1/videos/dQw4w9WgXcQ

Headers:
  Authorization: Bearer <JWT_TOKEN> (optional; public videos don't require auth)

Response:
{
  "video_id": "dQw4w9WgXcQ",
  "title": "Rick Astley - Never Gonna Give You Up",
  "description": "...",
  "duration_seconds": 213,
  "view_count": 1_400_000_000,
  "like_count": 14_000_000,
  "comments": [
    { "user": "user1", "text": "Classic!" },
    { "user": "user2", "text": "Best song ever" }
  ]
}

Latency: 50-200ms (cache hit from Redis, or DB query)
Rate Limit: 1000 requests/hour for anonymous, 10K for authenticated
```

### Get Playback Manifest

```
GET /api/v1/videos/dQw4w9WgXcQ/manifest?device=mobile&network=4g

Headers:
  Authorization: Bearer <JWT_TOKEN> (if video is private)

Response: (HLS M3U8 format)
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:6.0,
https://cdn.example.com/videos/dQw4w9WgXcQ/480p/segment-0.ts
#EXTINF:6.0,
https://cdn.example.com/videos/dQw4w9WgXcQ/480p/segment-1.ts

Latency: 20-100ms (CDN cache or origin)
Rate Limit: 100 manifests/hour per user (to prevent segment enumeration attacks)
```

### Record View/Like

```
POST /api/v1/videos/dQw4w9WgXcQ/watch

Headers:
  Authorization: Bearer <JWT_TOKEN>

Request:
{
  "watchDurationSeconds": 45,
  "qualityWatched": "1080p",
  "codecWatched": "vp9"
}

Response:
{ "success": true }

Latency: <50ms (write to Kafka, return immediately)
Note: View count increments asynchronously via Redis shards
Auth: User must be authenticated; quota applies (1M total QPS system-wide)
Rate Limit: 1 event per 5 seconds per user per video (anti-abuse)
```

### Search

```
GET /api/v1/search?q=javascript+tutorial&limit=20

Headers:
  Authorization: Bearer <JWT_TOKEN> (optional)

Response:
{
  "results": [
    {
      "video_id": "vid1",
      "title": "JavaScript Tutorial for Beginners",
      "channel": "Code Masters",
      "views": 5_000_000,
      "uploadDate": "2023-01-15",
      "duration": 3600
    },
    ...
  ],
  "totalResults": 145_000,
  "executionTimeMs": 87
}

Latency: <200ms p95 (Elasticsearch query)
Rate Limit: 100 searches/hour for anonymous, 10K for authenticated
```

---

## Deployment Model: Multi-Region Global Architecture

YouTube isn't in one data center. It's everywhere.

### Region Strategy

The system deploys to multiple regions for:
1. **Latency**: Users in Europe hit EU servers, not US servers
2. **Availability**: If US-East data center burns down, EU and APAC keep serving
3. **Data sovereignty**: GDPR requires user data stored in EU data centers
4. **Load distribution**: Spread 1M concurrent viewers across regions

**Regions:**
- **US-East** (primary): 400M DAU, metadata + video cache
- **EU-West**: 300M DAU, metadata + video cache, GDPR compliance
- **APAC**: 200M DAU, metadata + video cache
- **SAM** (South America): 100M DAU, video cache + fallback

Each region has:
- Complete copy of metadata database (read replicas for availability)
- CDN edge nodes for local video serving
- Local Redis cache layer
- Elasticsearch search cluster

**Replication:**
- **Metadata**: Primary writes in US-East, async replicas to EU/APAC (2-5 sec lag)
- **Videos**: Uploaded to nearest region's S3, replicated globally via S3 cross-region replication
- **Search index**: Pushed from US to EU/APAC daily (batch replication)

```mermaid
graph TB
    Internet["🌍 Global Internet Users<br/>2.5B Monthly Active"]
    
    Internet -->|"DNS routes to<br/>nearest region"| Router["Geo-Routing<br/>Latency-based"]
    
    Router -->|"US-East users"| USEast
    Router -->|"EU users"| EU
    Router -->|"APAC users"| APAC
    Router -->|"SAM users"| SAM
    
    subgraph USEast["🗽 US-East-1 (Primary)<br/>400M DAU"]
        USAPI["API Layer<br/>100 instances"]
        USPG["PostgreSQL<br/>Primary DB<br/>All writes"]
        USCache["Redis Cache<br/>100 shards"]
        USES["Elasticsearch<br/>Full index"]
        USCDN["CDN Edges<br/>50 nodes<br/>90% hit rate"]
    end
    
    subgraph EU["🇪🇺 EU-West-1<br/>300M DAU"]
        EUAPI["API Layer<br/>80 instances"]
        EUPG["PostgreSQL<br/>Read Replica<br/>2-5s lag"]
        EUCache["Redis Cache<br/>hot keys"]
        EUES["Elasticsearch<br/>Replica"]
        EUCDN["CDN Edges<br/>40 nodes"]
    end
    
    subgraph APAC["🌏 AP-Southeast-1<br/>200M DAU"]
        APACAPI["API Layer<br/>60 instances"]
        APACPG["PostgreSQL<br/>Read Replica"]
        APACCache["Redis Cache"]
        APACES["Elasticsearch<br/>Replica"]
        APACCDN["CDN Edges<br/>30 nodes"]
    end
    
    subgraph SAM["🇧🇷 SA-East-1<br/>100M DAU"]
        SAMAPI["API Layer<br/>30 instances"]
        SAMCDN["CDN Edges<br/>20 nodes"]
    end
    
    USAPI --> USPG
    USAPI --> USCache
    USAPI --> USES
    USAPI --> USCDN
    
    EUAPI --> EUPG
    EUAPI --> EUCache
    EUAPI --> EUES
    EUAPI --> EUCDN
    
    APACAPI --> APACPG
    APACAPI --> APACCache
    APACAPI --> APACES
    APACAPI --> APACCDN
    
    SAMAPI --> SAMCDN
    
    USPG -->|"Async replication<br/>WAL stream"| EUPG
    USPG -->|"Async replication"| APACPG
    
    USES -->|"Daily batch<br/>push index"| EUES
    USES -->|"Daily batch"| APACES
    
    USCache -->|"Invalidation<br/>via CDC"| EUCache
    USCache -->|"Invalidation"| APACCache
    
    style USEast fill:#bbdefb
    style EU fill:#c8e6c9
    style APAC fill:#ffe0b2
    style SAM fill:#f8bbd0
    style USPG fill:#81c784
    style EUPG fill:#64b5f6
    style APACPG fill:#64b5f6
    style Internet fill:#f0f4c3
```

---

## Preview: The Deep Dives Ahead

Each section above hides complexity. This series goes deeper:

### Part 2: Real-Time Analytics at 1 Million QPS

View counters seem simple until you face 1 million updates per second. Single Redis counter? Bottleneck. Sharded counters? 100 shards × 10K QPS each. But now you need consistent aggregation, freshness guarantees, and fallbacks when shards fail. We'll explore Kafka event streaming, stream processing for real-time rollups, and cost analysis of analytics infrastructure.

### Part 3: Transcoding Economics — Why AV1 Costs Less

500K hours uploaded daily = 2.5M-5M transcode jobs daily. The codec choice (H.264 vs VP9 vs AV1) determines whether this costs $2M/month or $4M/month. H.264 is fast but bandwidth-heavy. AV1 compresses 50% better but takes 100x longer to encode. We'll do the math: when does AV1's compression savings pay for the compute cost? Spoiler: for 4K+ content, instantly.

### Part 4: Metadata Consistency — Keeping Search in Sync

PostgreSQL is your source of truth. Elasticsearch is your search index. Problem: updating both atomically is hard. If you update PostgreSQL and Elasticsearch fails, search becomes stale. Solution: Change Data Capture (CDC), Kafka, and the Outbox pattern. We'll explore the tension between strong consistency (API reads always fresh) and eventual consistency (search lags 5 minutes).

### Part 5: Production Readiness — Operating YouTube at Scale

Beautiful architecture means nothing if it crashes at 3 AM. SLOs: 99.9% availability, <500ms API latency p95. Incident response: mean time to repair (MTTR) should be <5 minutes. Observability: 2000+ Prometheus metrics, ELK logging, distributed tracing. We'll walk through disaster recovery (RTO 15 min, RPO 5 min), circuit breakers, and scaling scenarios (World Cup = 10x traffic spike).

---

## Conclusion: The Design Philosophy

YouTube's architecture rests on a few principles:

1. **Eventual consistency is good enough.** View counts lag 5 minutes. That's fine. Video metadata is instant; that matters.
2. **Sharding solves scale.** 1M QPS → 100 shards × 10K QPS. Every large system shards somewhere.
3. **Caching is mandatory.** Redis caches, CDN caches, browser caches. Cache misses cascade into failures.
4. **Observability wins incidents.** You can't fix what you don't measure. Metrics, logs, traces.
5. **Cost and performance are inseparable.** A 30% bandwidth reduction saves $76M/year in CDN costs. That's not optimization; it's survival.
6. **Security & quotas protect the system.** Auth tokens, per-user quotas, and rate limiting prevent abuse at billion-scale.

In the next part, we dive into the hardest real-time problem: recording 1 million view events per second, aggregating them, and displaying counts that feel instant to billions of users. This is where the chaos begins.

---

**Key Takeaways:**
- YouTube serves 100M DAU, 1M concurrent viewers, 500K hours uploaded daily
- Control Plane (metadata API, PostgreSQL, Elasticsearch) handles ~50K QPS with strong consistency
- Data Plane (upload, transcode, CDN) handles high throughput (5-30 Pbps peak bandwidth)
- Authentication via JWT tokens; authorization via scopes and per-user quotas
- Rate limiting via token bucket; per-user quotas prevent abuse
- Multi-region deployment for latency, availability, and data sovereignty
- Sharding, caching, and eventual consistency enable billion-scale systems

