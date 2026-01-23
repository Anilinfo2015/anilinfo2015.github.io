# Article 11: Security

## Security Layers

```
        User
          ↓
    ┌─────────────┐
    │ HTTPS/TLS   │ - Encryption in transit
    └─────┬───────┘
          ↓
    ┌─────────────────┐
    │ Authentication  │ - Who are you?
    └────────┬────────┘
             ↓
    ┌──────────────────┐
    │ Authorization    │ - What can you do?
    └────────┬─────────┘
             ↓
    ┌────────────────────┐
    │ Input Validation   │ - Is this safe?
    └────────┬───────────┘
             ↓
    ┌───────────────────┐
    │ Rate Limiting     │ - Abuse prevention
    └────────┬──────────┘
             ↓
       Database
```

---

## Layer 1: Encryption in Transit (HTTPS/TLS)

### Requirement

```
ALL traffic must be HTTPS
  ├─ No HTTP allowed
  ├─ No unencrypted connections
  └─ Upgrade HTTP to HTTPS automatically
```

### Implementation

```
API Server:
  ├─ Bind to :443 (HTTPS)
  ├─ Bind to :80 (HTTP only for redirect)
  ├─ All :80 requests → 301 to https://

SSL/TLS Certificate:
  ├─ Let's Encrypt (free, automated renewal)
  ├─ Wildcard cert: *.short.app
  ├─ Auto-renewal: 90 days before expiry
  └─ Monitoring: Alert if < 30 days to expiry

TLS 1.2 minimum:
  ├─ TLS 1.0, 1.1: deprecated (remove)
  ├─ TLS 1.2: standard
  ├─ TLS 1.3: preferred (faster handshake)
  └─ Disable weak ciphers (SSL Labs A rating)
```

### Verification

```
Test with curl:
  curl -v https://short.app/abc123
  
Look for:
  ├─ TLS 1.2 or 1.3
  ├─ Certificate valid
  ├─ No warnings
  └─ Chain complete (root, intermediate, server)
```

---

## Layer 2: Authentication

### Web Users (OAuth 2.0)

```
Flow:
  1. User clicks "Sign In"
  2. Redirect to: https://auth.short.app/oauth/authorize
  3. User logs in with email/password
  4. Redirect back to: https://short.app?code=abc123
  5. Server exchanges code for access_token
  6. Set secure, httpOnly cookie

Cookie configuration:
  Set-Cookie: session_id=xyz; 
              Path=/; 
              Domain=.short.app;
              Secure;     ← HTTPS only
              HttpOnly;   ← No JavaScript access
              SameSite=Strict;  ← CSRF protection
              Max-Age=86400  ← 24 hours
```

### API Users (Bearer Token)

```
Request:
  Authorization: Bearer sk_live_abc123xyz

Token format:
  ├─ sk_live_* : Production token
  ├─ sk_test_* : Testing token (doesn't charge)
  └─ Random 32 chars for security

Storage:
  ├─ Hash token in database (bcrypt)
  ├─ Never store plaintext
  ├─ Generate new token: use crypto.random_bytes(32)
  └─ Display to user only once (copy to clipboard)

Rotation:
  ├─ Users can revoke old tokens
  ├─ System warns if token is old (> 1 year)
  ├─ Webhook notification on rotation
  └─ Old tokens still work (don't break immediately)
```

### Multi-Factor Authentication (MFA)

```
For sensitive operations:
  ├─ Change password: Require MFA
  ├─ Rotate API key: Require MFA
  ├─ Delete links: Require MFA
  └─ Upgrade plan: Require MFA

Implementation:
  ├─ TOTP (Time-based One-Time Password)
  ├─ User scans QR code with authenticator app
  ├─ App generates 6-digit code every 30 seconds
  ├─ User enters code during sensitive operation
  └─ Backup codes for recovery (store offline)
```

---

## Layer 3: Authorization

### Role-Based Access Control (RBAC)

```
User Roles:
  ├─ User (default)
  │  └─ Can manage own links
  │  └─ Can't see other users' links
  │
  ├─ Admin
  │  └─ Can delete any link
  │  └─ Can view analytics dashboard
  │  └─ Can manage users (ban, promote)
  │
  └─ Support
     └─ Can override rate limits
     └─ Can view user account
     └─ Can help with issues
```

### Resource-Level Authorization

```python
def get_link_details(short_code, current_user):
    """Check authorization before returning link"""
    
    link = db.get_link(short_code)
    if not link:
        return 404
    
    # Check authorization
    if current_user.role == 'admin':
        return link  # Admins see everything
    
    if current_user.id == link.user_id:
        return link  # Users see their own links
    
    # Regular user trying to access other user's link
    return 403  # Forbidden
```

---

## Layer 4: Input Validation

### URL Validation

```python
def validate_url(url):
    """Comprehensive URL validation"""
    
    # 1. Format check
    try:
        parsed = urllib.parse.urlparse(url)
    except:
        raise ValidationError("Invalid URL format")
    
    # 2. Scheme check (only http/https)
    if parsed.scheme not in ['http', 'https']:
        raise ValidationError("Only HTTP/HTTPS allowed")
    
    # 3. Length check
    if len(url) > 2048:
        raise ValidationError("URL too long")
    
    # 4. Hostname check
    if not parsed.netloc:
        raise ValidationError("URL must have a hostname")
    
    # 5. Block internal IPs (SSRF prevention)
    ip = socket.gethostbyname(parsed.netloc)
    if ip.startswith('192.168.') or ip.startswith('10.'):
        raise ValidationError("Private IP not allowed")
    
    # 6. Block localhost
    if parsed.netloc in ['localhost', '127.0.0.1', '::1']:
        raise ValidationError("Localhost not allowed")
    
    return parsed
```

### SQL Injection Prevention

```python
# ❌ VULNERABLE
query = f"SELECT * FROM links WHERE short_code = '{code}'"
db.execute(query)  # If code="abc' OR '1'='1", extracts all links!

# ✅ SAFE (Parameterized queries)
query = "SELECT * FROM links WHERE short_code = ?"
db.execute(query, [code])  # Database driver escapes code

# Note: All ORMs (SQLAlchemy, Django ORM) use parameterized queries
# Use raw SQL only if absolutely necessary
```

### Custom Code Validation

```python
def validate_custom_code(code):
    """Prevent reserved/dangerous codes"""
    
    # Length
    if len(code) < 1 or len(code) > 100:
        raise ValidationError("Code length must be 1-100")
    
    # Characters (alphanumeric + dash + underscore)
    if not re.match(r'^[a-zA-Z0-9_-]+$', code):
        raise ValidationError("Code can only contain letters, numbers, - and _")
    
    # Reserved words
    reserved = ['api', 'admin', 'support', 'www', 'mail', 'ftp', 'blog']
    if code.lower() in reserved:
        raise ValidationError(f"Code '{code}' is reserved")
    
    # Profanity filter
    if contains_profanity(code):
        raise ValidationError("Code contains inappropriate language")
    
    return code
```

---

## Layer 5: Malware & Phishing Detection

### Google Safe Browsing API

```python
def check_url_safety(long_url):
    """Query Google Safe Browsing API"""
    
    response = requests.post(
        "https://safebrowsing.googleapis.com/v4/threatMatches:find",
        json={
            "client": {
                "clientId": "my-shortener",
                "clientVersion": "1.5.2"
            },
            "threatInfo": {
                "threatTypes": [
                    "MALWARE",
                    "SOCIAL_ENGINEERING",
                    "UNWANTED_SOFTWARE"
                ],
                "platformTypes": ["WINDOWS", "LINUX", "ANDROID"],
                "threatEntryTypes": ["URL"],
                "threatEntries": [{"url": long_url}]
            }
        },
        params={"key": GOOGLE_API_KEY}
    )
    
    threats = response.json().get("matches", [])
    
    if threats:
        threat_types = set(t['threatType'] for t in threats)
        return False, threat_types  # Blocked
    
    return True, []  # Safe
```

### Handling Unsafe URLs

```python
def create_link(long_url):
    """Create link with safety check"""
    
    is_safe, threat_types = check_url_safety(long_url)
    
    if not is_safe:
        # Log for investigation
        logger.warn(f"Blocked unsafe URL: {long_url}, threats: {threat_types}")
        
        # Return error to user
        return 403, {
            "error": "URL blocked",
            "reason": "URL contains malware/phishing",
            "support_email": "support@short.app"
        }
    
    # Continue with normal link creation
    return create_link_impl(long_url)
```

---

## Layer 6: Rate Limiting & DDoS Prevention

### Per-User Rate Limiting

```python
def rate_limit_check(user_id, tier):
    """Enforce rate limits per subscription tier"""
    
    quotas = {
        "free": 100,      # 100 per day
        "premium": 10000, # 10K per day
        "enterprise": None  # Unlimited
    }
    
    capacity = quotas[tier]
    if capacity is None:
        return True  # Unlimited
    
    # Use token bucket (Redis)
    bucket = TokenBucket(f"quota:{user_id}", capacity, capacity/(24*3600))
    
    if not bucket.allow_request():
        return False  # Rate limit exceeded
    
    return True
```

### Per-IP Rate Limiting (DDoS Protection)

```python
def rate_limit_by_ip(client_ip):
    """Prevent DDoS from single IP"""
    
    bucket = TokenBucket(f"ip:{client_ip}", capacity=1000, refill_rate=1000/60)
    
    if not bucket.allow_request():
        # IP is abusing
        return 429  # Too Many Requests
    
    return None  # OK
```

### WAF Rules (AWS WAF)

```
Rules:
  1. Block IPs sending > 100 requests/second
  2. Block requests with suspicious User-Agent
  3. Block requests with SQL injection patterns
  4. Block requests with path traversal (../)
  5. Rate limit by IP: 5000 per 5 minutes
  6. Block known bad IPs (reputation lists)
```

---

## Layer 7: Audit Logging

### What to Log

```python
def log_security_event(event_type, details):
    """Log security-relevant events"""
    
    event = {
        "type": event_type,
        "user_id": details.get('user_id'),
        "ip": details.get('ip'),
        "user_agent": details.get('user_agent'),
        "action": details.get('action'),
        "resource": details.get('resource'),
        "result": details.get('result'),  # success/failure
        "timestamp": datetime.utcnow(),
        "details": details
    }
    
    # Store in immutable audit log
    audit_log.insert(event)

# Examples:
log_security_event('login_attempt', {
    'user_id': 'user123',
    'ip': '203.0.113.45',
    'result': 'success'
})

log_security_event('unauthorized_access', {
    'user_id': 'user123',
    'ip': '203.0.113.45',
    'resource': 'other_user_link',
    'result': 'blocked'
})

log_security_event('rate_limit_exceeded', {
    'ip': '203.0.113.45',
    'rate_limit': 100,
    'result': 'rejected'
})
```

### Retention

```
Audit logs retention:
  ├─ Keep all logs for 2 years (compliance)
  ├─ Immutable (can't be modified/deleted)
  ├─ Encrypted at rest
  ├─ Access controlled (admins only)
  └─ Backed up separately
```

---

## Layer 8: Data Protection

### Encryption at Rest

```
Database:
  ├─ DynamoDB: Enabled by default
  ├─ RDS: Use AWS KMS (Key Management Service)
  └─ S3: Bucket encryption enabled

PII (Personally Identifiable Information):
  ├─ Email: Encrypt with customer-managed key
  ├─ Password: Hash with bcrypt, salt
  ├─ API key: Hash with SHA256
  └─ Note: Don't store passwords! Use OAuth/SSO
```

### Password Security

```python
import bcrypt

def hash_password(password):
    """Hash password securely"""
    
    # Never store plaintext
    # Use bcrypt with cost factor 12+
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(password.encode(), salt)
    return hashed

def verify_password(password, hashed):
    """Verify during login"""
    return bcrypt.checkpw(password.encode(), hashed)

# Requirements:
#  ├─ Min 12 characters
#  ├─ Mix of upper/lower/digits/symbols
#  ├─ Not in breach database (check haveibeenpwned.com)
#  └─ No reuse of last 5 passwords
```

---

## Security Checklist

```
Before production:
  ☑ HTTPS enabled, TLS 1.2+
  ☑ Authentication implemented (OAuth 2.0)
  ☑ Authorization checks in place
  ☑ Input validation on all endpoints
  ☑ SQL injection prevention (parameterized queries)
  ☑ Malware detection (Safe Browsing API)
  ☑ Rate limiting enforced
  ☑ Audit logging enabled
  ☑ Password hashing (bcrypt)
  ☑ Secrets not in code (use env vars)
  ☑ CORS properly configured
  ☑ CSRF tokens for POST requests
  ☑ Security headers (CSP, X-Frame-Options, etc.)
  ☑ Dependency vulnerabilities scanned
  ☑ Secrets scanning in Git
```

---

## Summary: Security

**8 layers of defense**:
1. **HTTPS/TLS**: Encryption in transit
2. **Authentication**: Who are you?
3. **Authorization**: What can you access?
4. **Input Validation**: Is this safe?
5. **Malware Detection**: Check URLs
6. **Rate Limiting**: Prevent abuse
7. **Audit Logging**: Track activities
8. **Data Protection**: Encrypt at rest

Each layer catches different attacks. Combine them for defense-in-depth.

**Next**: Production Readiness (monitoring, reliability, operations).
