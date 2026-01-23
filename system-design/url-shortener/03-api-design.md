# Article 3: API Design

## API Overview

The API provides RESTful endpoints for link management and redirection.

```
Base URL: https://short.app/api/v1

Authentication:
  ├─ Web users: Cookie + session (OAuth 2.0)
  ├─ API clients: Bearer token (API key)
  └─ Rate limits: Enforced per user/tier
```

---

## Core Endpoints

### 1. Create Short Link

```
POST /links
Content-Type: application/json
Authorization: Bearer <api_key>

Request:
{
  "long_url": "https://blog.example.com/post/123",
  "custom_code": "my-campaign",    // optional
  "title": "My article",            // optional
  "expires_in_days": 30             // optional
}

Response (201 Created):
{
  "short_code": "my-campaign",
  "short_url": "https://short.app/my-campaign",
  "long_url": "https://blog.example.com/post/123",
  "created_at": "2024-01-15T10:30:00Z",
  "is_custom": true,
  "expires_at": "2024-02-14T10:30:00Z"
}

Errors:
{
  "400": "Invalid URL format",
  "401": "Unauthorized",
  "409": "Custom code already taken",
  "429": "Rate limit exceeded"
}
```

**Behavior**:
- If `long_url` was already shortened: return existing `short_code` (idempotent)
- If `custom_code` provided: check availability (must be unique)
- If neither: generate random 6-char base62 code
- Default expiration: never (or 365 days for free tier)

### 2. Redirect to Long URL

```
GET /{short_code}
(No authentication needed - public redirect)

Response (301 Moved Permanently):
Location: https://blog.example.com/post/123
Cache-Control: public, max-age=31536000

Errors:
{
  "404": "Link not found",
  "410": "Link has been deleted",
  "500": "Internal server error"
}
```

**Special Header**: 
- `Cache-Control: max-age=31536000` tells CDN/browser to cache for 1 year
- This is safe because short codes are immutable

**Tracking**:
- User's IP, User-Agent logged to analytics (async, fire-and-forget)
- No wait for logging (< 1ms latency impact)

### 3. Get Single Link Details

```
GET /links/{short_code}
Authorization: Bearer <api_key>

Response (200 OK):
{
  "short_code": "my-campaign",
  "long_url": "https://blog.example.com/post/123",
  "user_id": "user@example.com",
  "created_at": "2024-01-15T10:30:00Z",
  "is_custom": true,
  "is_deleted": false,
  "expires_at": "2024-02-14T10:30:00Z",
  "title": "My article",
  "analytics": {
    "total_clicks": 1523,
    "unique_users": 412,
    "clicks_today": 23,
    "last_click_at": "2024-01-15T15:45:00Z"
  }
}

Errors:
{
  "401": "Unauthorized",
  "404": "Link not found",
  "403": "You don't own this link"
}
```

**Authorization**: 
- Users can only see their own links
- Admins can see any link

### 4. List My Links

```
GET /links?page=1&limit=20&sort=created_at&order=desc
Authorization: Bearer <api_key>

Response (200 OK):
{
  "links": [
    {
      "short_code": "abc123",
      "long_url": "https://...",
      "created_at": "2024-01-15T10:30:00Z",
      "clicks_total": 523,
      "is_deleted": false
    },
    // ... more links
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 145,
    "total_pages": 8
  }
}

Query Parameters:
  - page: 1-indexed page number (default: 1)
  - limit: results per page, 1-100 (default: 20)
  - sort: "created_at" or "clicks" (default: created_at)
  - order: "asc" or "desc" (default: desc)
```

### 5. Update Link

```
PUT /links/{short_code}
Authorization: Bearer <api_key>

Request:
{
  "title": "Updated title",
  "custom_code": "new-code"  // Can't change existing code
}

Response (200 OK):
{ /* Updated link object */ }

Errors:
{
  "403": "Can't modify custom codes",
  "404": "Link not found",
  "409": "New code already taken"
}
```

**Limitations**:
- Can update: `title`, expiration
- Can't update: `long_url`, `short_code` (create new one instead)
- Changing URL would invalidate all shared links

### 6. Delete Link

```
DELETE /links/{short_code}
Authorization: Bearer <api_key>

Response (204 No Content)

Errors:
{
  "404": "Link not found",
  "403": "You don't own this link"
}
```

**Behavior**:
- Soft delete (keep for audits, return 404 to users)
- Not immediately removed from cache (may take 1 hour)
- Can be permanently purged after 30 days (compliance)

### 7. Get Analytics

```
GET /links/{short_code}/analytics?start_date=2024-01-01&end_date=2024-01-31
Authorization: Bearer <api_key>

Response (200 OK):
{
  "short_code": "abc123",
  "period": {
    "start_date": "2024-01-01",
    "end_date": "2024-01-31"
  },
  "summary": {
    "total_clicks": 10523,
    "unique_users": 4231,
    "average_clicks_per_day": 339
  },
  "daily_breakdown": [
    {
      "date": "2024-01-01",
      "clicks": 234,
      "unique_users": 123
    },
    // ... more days
  ],
  "top_referrers": [
    { "referrer": "twitter.com", "clicks": 3245 },
    { "referrer": "reddit.com", "clicks": 2156 },
    { "referrer": "(direct)", "clicks": 5122 }
  ],
  "device_breakdown": {
    "desktop": 0.65,
    "mobile": 0.32,
    "other": 0.03
  }
}

Query Parameters:
  - start_date: YYYY-MM-DD (default: 30 days ago)
  - end_date: YYYY-MM-DD (default: today)
```

---

## Error Handling

### HTTP Status Codes

```
2xx - Success
  200 OK: Request succeeded
  201 Created: Link created
  204 No Content: Delete succeeded

4xx - Client Error
  400 Bad Request: Invalid input (malformed JSON, bad URL format)
  401 Unauthorized: Missing/invalid authentication
  403 Forbidden: Permission denied (don't own resource)
  404 Not Found: Resource doesn't exist
  409 Conflict: Custom code already taken
  429 Too Many Requests: Rate limit exceeded

5xx - Server Error
  500 Internal Server Error: Unexpected error
  503 Service Unavailable: System overloaded/maintenance
```

### Error Response Format

```json
{
  "error": {
    "code": "CUSTOM_CODE_TAKEN",
    "message": "The custom code 'my-campaign' is already in use",
    "details": {
      "requested_code": "my-campaign",
      "suggestions": ["my-campaign-2", "my-campaign-v2"]
    }
  },
  "request_id": "req_12345abc",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Key fields**:
- `code`: Machine-readable error (for clients to handle)
- `message`: Human-readable explanation
- `details`: Context-specific info (suggestions, required fields, etc.)
- `request_id`: For debugging (correlate to logs)

---

## Request/Response Examples

### Example 1: Create Link (Happy Path)

```
→ Request
POST /api/v1/links HTTP/1.1
Authorization: Bearer abc123xyz
Content-Type: application/json

{
  "long_url": "https://example.com/article?id=123&utm=campaign"
}

← Response
HTTP/1.1 201 Created
Content-Type: application/json

{
  "short_code": "x7k2p1",
  "short_url": "https://short.app/x7k2p1",
  "long_url": "https://example.com/article?id=123&utm=campaign",
  "created_at": "2024-01-15T10:30:00Z",
  "expires_at": null
}
```

### Example 2: Redirect (Happy Path)

```
→ Request
GET /api/v1/x7k2p1 HTTP/1.1

← Response
HTTP/1.1 301 Moved Permanently
Location: https://example.com/article?id=123&utm=campaign
Cache-Control: public, max-age=31536000
```

### Example 3: Create Link (Custom Code Taken)

```
→ Request
POST /api/v1/links HTTP/1.1
Authorization: Bearer abc123xyz
Content-Type: application/json

{
  "long_url": "https://example.com/article",
  "custom_code": "my-link"
}

← Response
HTTP/1.1 409 Conflict
Content-Type: application/json

{
  "error": {
    "code": "CODE_ALREADY_EXISTS",
    "message": "The code 'my-link' is already taken",
    "details": {
      "suggestions": ["my-link-2024", "my-link-v2", "my-link-backup"]
    }
  },
  "request_id": "req_xyz789"
}
```

### Example 4: Rate Limit Exceeded

```
→ Request (100th request this hour for free tier)
POST /api/v1/links HTTP/1.1
Authorization: Bearer abc123xyz

← Response
HTTP/1.1 429 Too Many Requests
Retry-After: 3600
Content-Type: application/json

{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "You've reached your limit of 100 links per hour",
    "details": {
      "limit": 100,
      "window": "1 hour",
      "retry_after_seconds": 3600,
      "upgrade_url": "https://short.app/upgrade"
    }
  }
}
```

---

## Authentication & Authorization

### API Key Authentication

```
Header-based:
Authorization: Bearer sk_live_abc123xyz

API key stored as bcrypt hash in database
Prefix indicates environment:
  - sk_live_*: Production key
  - sk_test_*: Testing key

Rotation:
  - Users can generate new keys
  - Old keys can be revoked
  - Webhook notification on rotation
```

### Rate Limiting Headers

Every response includes quota info:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 42
X-RateLimit-Reset: 1705329000

Means:
  - Limit: 100 requests per hour
  - Remaining: 42 requests left
  - Reset: Resets at Unix timestamp 1705329000
```

---

## Summary: API Design

**7 Core Endpoints**:
1. `POST /links` - Create short link
2. `GET /{short_code}` - Redirect
3. `GET /links/{short_code}` - Get link details
4. `GET /links` - List user's links
5. `PUT /links/{short_code}` - Update link
6. `DELETE /links/{short_code}` - Delete link
7. `GET /links/{short_code}/analytics` - Get stats

**Authentication**: Bearer token (API key) for protected endpoints

**Error Handling**:
- Standard HTTP status codes (2xx, 4xx, 5xx)
- Consistent error JSON with code, message, details
- Request IDs for debugging

**Rate Limiting**: Enforced via token bucket, exposed in response headers

**Next Article**: Basic system design (MVP without scale concerns).
