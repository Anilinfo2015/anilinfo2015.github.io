# Article 3: REST API Design

## 3. API or system interface

### The Contract: How the World Talks to Us

Components and databases are useless if the outside world cannot interact with them. The API (Application Programming Interface) is the contract we sign with our users. It defines exactly what they can ask for and exactly what we promise to deliver.

> **Reader path — 3. API or system interface:** [Separate scoped walkthrough](../interview-questions/url-shortener.html#api) · [HLD template](../interview-template.html). Its assumptions and contracts may differ.
>
> **Series:** [Core entities](02-core-entities-components.md) → this API contract → [working baseline](04-basic-system-design.md). The operations below expand stage 3.

For our URL shortener, we will build a **RESTful API**. Why REST? Because it is cache-friendly, stateless, and universally understood by web browsers and HTTP clients. Simplicity is our goal.

#### API Overview
*   **Base URL**: `https://short.app/api/v1` (Versioning is crucial for future-proofing)
*   **Format**: JSON for everything (except the redirect itself)
*   **Security**: Bearer Tokens for ownership validation

---

<a id="1-the-creation-flow-write-operations"></a>
### The Creation Flow (Write Operations)

The first step in any user journey is creating content. This is where we validate, sanitize, and persist data.

#### Endpoint: Create a Short Link
This is our primary "Write" operation. It must handle two scenarios: creating a random link (fast) and requesting a custom alias (requires unique checks).

**Definition**
```http
POST /links
Content-Type: application/json
Authorization: Bearer <api_key>
```

**The Payload**
```json
{
  "long_url": "https://blog.example.com/post/123",
  "custom_code": "my-campaign",    // (Optional) The vanity URL user wants
  "expires_in_days": 30             // (Optional) Auto-cleanup
}
```

**The Success Response (201 Created)**
We return the full object so the client can immediately display it.
```json
{
  "short_code": "my-campaign",
  "short_url": "https://short.app/my-campaign",
  "long_url": "https://blog.example.com/post/123",
  "created_at": "2024-01-15T10:30:00Z"
}
```

**Key Design Decisions**:
1.  **Idempotency**: If a user submits the *exact same* `long_url` twice, should we create two short codes? For this design, **no**. We return the existing `short_code`. This saves database space.
2.  **Conflicts**: If `custom_code` is taken, we return a `409 Conflict` error immediately.

#### Endpoint: Manage Links (Update & Delete)
Users make mistakes. They need to fix titles or delete links that were posted in error.

**Update (PUT)**: Limited scope. We allow changing metadata (titles, tags) but **never** the `long_url` or `short_code`. Why? because changing the destination of a live link breaks the trust of the internet.

**Delete (DELETE)**: We perform a "Soft Delete". The API returns `204 No Content`, but the database row is just marked `is_deleted=true`. This allows us to restore accidental deletions if a support ticket is raised.

---

<a id="2-the-consumption-flow-read-operations"></a>
### The Consumption Flow (Read Operations)

This is where our system faces the fire. These endpoints must be optimized for speed.

#### Endpoint: The Redirect (Public)
This is the only endpoint that doesn't return JSON. It returns an HTTP redirection.

**Definition**
```http
GET /{short_code}
```

**The Response (301 Moved Permanently)**
```http
HTTP/1.1 301 Moved Permanently
Location: https://blog.example.com/post/123
Cache-Control: public, max-age=31536000
```
*   **Why 301?**: A 301 status code tells the browser "This link has moved forever." The browser will cache this mapping on its own disk. The next time the user types `short.app/abc`, the browser won't even talk to our server; it will just go straight to the destination. This saves us money and makes the user experience instant.

#### Endpoint: Get Analytics
Users love data. They want to know who clicked their links.

**Definition**
```http
GET /links/{short_code}/analytics
```

**The Response**
We provide aggregated data (counts), not raw logs (privacy).
```json
{
  "summary": {
    "total_clicks": 10523,
    "unique_users": 4231
  },
  "daily_series": [
    { "date": "2024-01-01", "clicks": 234 },
    { "date": "2024-01-02", "clicks": 541 }
  ]
}
```

---

<a id="3-dealing-with-failure-error-handling"></a>
### Dealing with Failure (Error Handling)

A good API tells you exactly what went wrong. We don't just return "Error". We return structured, actionable details.

#### Standardized Error Format
Every error follows this structure, allowing clients to show helpful UI messages.

```json
{
  "error": {
    "code": "CUSTOM_CODE_TAKEN",
    "message": "The alias 'summer-sale' is already in use.",
    "details": {
      "suggestion": "summer-sale-2024"
    }
  },
  "request_id": "req_87234" // Essential for debugging logs
}
```

#### Common HTTP Status Codes
*   **200 OK**: "Here is the data you asked for"
*   **201 Created**: "I successfully built the thing"
*   **204 No Content**: "I did it, but have nothing to say (e.g., Delete)"
*   **400 Bad Request**: "You sent invalid JSON or a bad URL"
*   **409 Conflict**: "That user/link already exists"
*   **429 Too Many Requests**: "Slow down! You hit the rate limit"

---

### Summary

Our API is designed to be:
1.  **Predictable**: Standard REST verbs and status codes.
2.  **Efficient**: Heavy use of HTTP caching headers.
3.  **Helpful**: Detailed error messages that guide the user to a fix.

With the contract defined, we can now move to the implementation details. In the next article, we will build the **Minimum Viable System**, connecting our API to the database.
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

#### Example 2: Redirect (Happy Path)

```
→ Request
GET /api/v1/x7k2p1 HTTP/1.1

← Response
HTTP/1.1 301 Moved Permanently
Location: https://example.com/article?id=123&utm=campaign
Cache-Control: public, max-age=31536000
```

#### Example 3: Create Link (Custom Code Taken)

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

#### Example 4: Rate Limit Exceeded

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

### Authentication & Authorization

#### API Key Authentication

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

#### Rate Limiting Headers

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

### Summary: API Design

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
