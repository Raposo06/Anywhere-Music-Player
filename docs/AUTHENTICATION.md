# 🔐 Authentication System Guide

This guide explains how authentication works in the Anywhere Music Player, using **JWT (JSON Web Tokens)** with PostgreSQL and PostgREST.

---

## 📚 Table of Contents

1. [Why Authentication?](#why-authentication)
2. [How JWT Works](#how-jwt-works)
3. [The Authentication Flow](#the-authentication-flow)
4. [Password Security](#password-security)
5. [Implementation Details](#implementation-details)
6. [Testing Authentication](#testing-authentication)
7. [Common Issues](#common-issues)

---

## Why Authentication?

Without authentication, anyone with your API URL could:
- Stream your entire music library
- See all your tracks and metadata
- Abuse your server resources

With authentication:
- ✅ Only you and your brother can access the music
- ✅ Each user has their own account
- ✅ Future features: favorites, playlists, listening history

---

## How JWT Works

### What is a JWT?

A **JSON Web Token** is like a digital passport that proves who you are without storing sessions on the server.

### JWT Structure

A JWT has 3 parts separated by dots:

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMTIzIn0.signature
└─────────── HEADER ────────────┘ └──── PAYLOAD ────┘ └─ SIGNATURE ─┘
```

**1. Header** (Algorithm & Type)
```json
{
  "alg": "HS256",  // HMAC-SHA256 algorithm
  "typ": "JWT"     // Token type
}
```

**2. Payload** (User Data)
```json
{
  "user_id": "a1b2c3d4-5678-...",
  "email": "you@example.com",
  "role": "authenticated",
  "iat": 1735387654,  // Issued at (Unix timestamp)
  "exp": 1735987654   // Expires in 7 days
}
```

**3. Signature** (Security)
```
HMACSHA256(
  base64UrlEncode(header) + "." + base64UrlEncode(payload),
  your-secret-key
)
```

### Why JWT is Secure

- ✅ **Tamper-proof:** Changing the payload invalidates the signature
- ✅ **Stateless:** Server doesn't need to store sessions (perfect for PostgREST)
- ✅ **Expiration:** Tokens expire after 7 days (forces re-login)
- ✅ **No database lookup:** Server verifies signature instantly

---

## The Authentication Flow

### 🔹 Signup Flow

```
┌─────────────┐                  ┌─────────────┐                  ┌──────────────┐
│ Flutter App │                  │  PostgREST  │                  │  PostgreSQL  │
└──────┬──────┘                  └──────┬──────┘                  └──────┬───────┘
       │                                │                                │
       │ POST /rpc/signup               │                                │
       │ {email, username, password}    │                                │
       ├───────────────────────────────>│                                │
       │                                │                                │
       │                                │ CALL signup(...)               │
       │                                ├───────────────────────────────>│
       │                                │                                │
       │                                │ 1. Validate password length    │
       │                                │ 2. Hash password with bcrypt   │
       │                                │ 3. INSERT INTO users           │
       │                                │                                │
       │                                │<───────────────────────────────┤
       │                                │ {user_id, success: true}       │
       │                                │                                │
       │<───────────────────────────────┤                                │
       │ 201 Created                    │                                │
       │ {user_id, message}             │                                │
       │                                │                                │
```

**Key Points:**
- Password is **never** stored in plain text
- Bcrypt hashing is slow by design (prevents brute-force attacks)
- Email and username must be unique

### 🔹 Login Flow

```
┌─────────────┐                  ┌─────────────┐                  ┌──────────────┐
│ Flutter App │                  │  PostgREST  │                  │  PostgreSQL  │
└──────┬──────┘                  └──────┬──────┘                  └──────┬───────┘
       │                                │                                │
       │ POST /rpc/login                │                                │
       │ {email, password}              │                                │
       ├───────────────────────────────>│                                │
       │                                │                                │
       │                                │ CALL login(...)                │
       │                                ├───────────────────────────────>│
       │                                │                                │
       │                                │ 1. Find user by email          │
       │                                │ 2. Verify password with bcrypt │
       │                                │ 3. Generate JWT token          │
       │                                │ 4. Set expiration (7 days)     │
       │                                │                                │
       │                                │<───────────────────────────────┤
       │                                │ {token: "eyJhbG...", user: {}}  │
       │                                │                                │
       │<───────────────────────────────┤                                │
       │ 200 OK                         │                                │
       │ {token, user}                  │                                │
       │                                │                                │
       │ Store token in secure storage  │                                │
       │                                │                                │
```

**Key Points:**
- Password verification uses constant-time comparison (prevents timing attacks)
- JWT expires in 7 days (configurable)
- Token is stored in Flutter's secure storage (encrypted on device)

### 🔹 Authenticated Request Flow

```
┌─────────────┐                  ┌─────────────┐                  ┌──────────────┐
│ Flutter App │                  │  PostgREST  │                  │  PostgreSQL  │
└──────┬──────┘                  └──────┬──────┘                  └──────┬───────┘
       │                                │                                │
       │ GET /tracks                    │                                │
       │ Authorization: Bearer <JWT>    │                                │
       ├───────────────────────────────>│                                │
       │                                │                                │
       │                                │ 1. Verify JWT signature        │
       │                                │ 2. Check expiration            │
       │                                │ 3. Extract user_id from payload│
       │                                │ 4. Switch to 'authenticated'   │
       │                                │                                │
       │                                │ SELECT * FROM tracks           │
       │                                ├───────────────────────────────>│
       │                                │                                │
       │                                │ (Permission check: OK!)        │
       │                                │                                │
       │                                │<───────────────────────────────┤
       │                                │ [array of tracks]              │
       │                                │                                │
       │<───────────────────────────────┤                                │
       │ 200 OK                         │                                │
       │ [tracks array]                 │                                │
       │                                │                                │
```

**Key Points:**
- JWT is sent in the `Authorization` header
- PostgREST validates the signature using `PGRST_JWT_SECRET`
- If valid, PostgreSQL grants access based on the `authenticated` role
- If invalid/missing, request is rejected with 401 Unauthorized

---

## Password Security

### Why NOT to Store Plain Text Passwords

```sql
-- ❌ NEVER DO THIS!
INSERT INTO users (email, password) VALUES ('user@example.com', 'mypassword123');

-- Problem: If your database is hacked, all passwords are exposed!
```

### Why Use Bcrypt?

**Bcrypt** is a password hashing algorithm designed to be slow.

```sql
-- ✅ CORRECT: Hash the password
INSERT INTO users (email, password_hash)
VALUES ('user@example.com', crypt('mypassword123', gen_salt('bf', 8)));
```

**How it works:**
1. `gen_salt('bf', 8)` generates a random salt with cost factor 8
2. `crypt(password, salt)` hashes the password using bcrypt
3. Result: `$2a$08$randomsalt...hashedpassword`

**Why cost factor 8?**
- Higher = slower = more secure (but slower login)
- 8 = ~40ms to hash (good balance for login UX)
- 12 = ~500ms (use for high-security apps)

### How Password Verification Works

```sql
-- Verification query (used in login function)
SELECT id FROM users
WHERE email = 'user@example.com'
AND password_hash = crypt('entered_password', password_hash);
```

**Magic:**
- `crypt('entered_password', password_hash)` extracts the salt from `password_hash`
- Re-hashes the entered password with the same salt
- If the result matches `password_hash`, password is correct!

---

## Implementation Details

### Database Roles

PostgREST uses PostgreSQL roles for access control:

| Role | Purpose | Permissions |
|------|---------|-------------|
| `anon` | Unauthenticated users | Can call `signup()` and `login()` only |
| `authenticated` | Logged-in users | Can read `tracks` table |
| `authenticator` | PostgREST connection | Switches between `anon` and `authenticated` |

### How PostgREST Switches Roles

```
Request WITHOUT JWT:
  ┌────────────┐
  │ PostgREST  │ Connects as: authenticator
  └─────┬──────┘ Switches to: anon
        │
        │ Limited access (signup/login only)
        ▼
  ┌────────────┐
  │ PostgreSQL │
  └────────────┘

Request WITH valid JWT:
  ┌────────────┐
  │ PostgREST  │ Connects as: authenticator
  └─────┬──────┘ Switches to: authenticated
        │
        │ Full access (read tracks)
        ▼
  ┌────────────┐
  │ PostgreSQL │
  └────────────┘
```

### JWT Secret Configuration

**In PostgreSQL (`04_auth_functions.sql`):**
```sql
jwt_secret TEXT := 'your-secret-key-min-32-chars';
```

**In PostgREST (Coolify environment variables):**
```bash
PGRST_JWT_SECRET=your-secret-key-min-32-chars
```

**⚠️ CRITICAL:** These must match exactly! Otherwise, tokens will fail validation.

---

## Testing Authentication

### 1. Test Signup (SQL)

```sql
SELECT public.signup(
    'test@example.com',
    'testuser',
    'securepass123'
);
```

Expected result:
```json
{
  "success": true,
  "user_id": "a1b2c3d4-...",
  "message": "Account created successfully"
}
```

### 2. Test Login (SQL)

```sql
SELECT public.login('test@example.com', 'securepass123');
```

Expected result:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "a1b2c3d4-...",
    "email": "test@example.com",
    "username": "testuser"
  }
}
```

### 3. Test Signup (API)

```bash
curl -X POST https://api.YOUR_DOMAIN/rpc/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "you@example.com",
    "username": "yourname",
    "password": "yourpassword"
  }'
```

### 4. Test Login (API)

```bash
curl -X POST https://api.YOUR_DOMAIN/rpc/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "you@example.com",
    "password": "yourpassword"
  }'
```

Save the returned token!

### 5. Test Authenticated Request

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl https://api.YOUR_DOMAIN/tracks \
  -H "Authorization: Bearer $TOKEN"
```

Should return your tracks (or `[]` if none uploaded yet).

---

## Common Issues

### ❌ Error: "Invalid email or password"

**Causes:**
- Wrong email or password (obviously!)
- User doesn't exist (must signup first)
- Password too short (minimum 8 characters)

**Debug:**
```sql
-- Check if user exists
SELECT email, username FROM users WHERE email = 'test@example.com';
```

### ❌ Error: "JWT verification failed"

**Causes:**
- JWT secret mismatch between PostgreSQL and PostgREST
- Token expired (7-day expiration)
- Token was tampered with

**Debug:**
```bash
# Decode JWT to check expiration (don't validate signature)
echo "YOUR_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq
```

Check the `exp` field (Unix timestamp). If `exp < current_time`, token is expired.

### ❌ Error: "permission denied for schema public"

**Cause:** Roles don't have proper grants

**Fix:** Re-run `database/05_postgrest_roles.sql`

### ❌ Error: "function pgjwt.sign does not exist"

**Cause:** `pgjwt` extension not installed

**Fix:**
```bash
# SSH into server
ssh root@YOUR_IP

# Enter PostgreSQL container
docker exec -it <postgres-container-id> bash

# Install pgjwt (requires compilation)
apt update && apt install -y git build-essential postgresql-server-dev-all
cd /tmp
git clone https://github.com/michelp/pgjwt.git
cd pgjwt
make install

# Restart PostgreSQL
exit
docker restart <postgres-container-id>
```

---

## Security Best Practices

### ✅ Do's

- ✅ Use HTTPS (already handled by Coolify/Traefik)
- ✅ Store JWT in Flutter's `flutter_secure_storage` (encrypted)
- ✅ Use strong JWT secret (min 32 characters, random)
- ✅ Set token expiration (7 days is reasonable)
- ✅ Validate password strength (min 8 chars)

### ❌ Don'ts

- ❌ Never store passwords in plain text
- ❌ Never commit JWT secret to Git (use environment variables)
- ❌ Never send password in URL query params
- ❌ Never store JWT in localStorage on web (XSS risk)
- ❌ Never use short JWT secrets (min 32 chars)

---

## Future Enhancements

### Refresh Tokens

Currently, users must re-login after 7 days. You could add:

```sql
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    token TEXT NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE
);
```

Then create a `refresh()` function to exchange refresh token for a new JWT.

### Row-Level Security (RLS)

For user-specific data (favorites, playlists):

```sql
CREATE TABLE favorites (
    user_id UUID REFERENCES users(id),
    track_id UUID REFERENCES tracks(id)
);

ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see only their favorites"
ON favorites FOR SELECT
TO authenticated
USING (user_id = current_setting('request.jwt.claims')::json->>'user_id'::uuid);
```

### Password Reset

Add email verification and password reset:

```sql
CREATE TABLE password_reset_tokens (
    user_id UUID REFERENCES users(id),
    token TEXT NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE
);
```

---

## Glossary

- **JWT:** JSON Web Token - a self-contained authentication token
- **Bcrypt:** Password hashing algorithm resistant to brute-force attacks
- **Salt:** Random data added to passwords before hashing (prevents rainbow table attacks)
- **PostgREST:** Turns PostgreSQL database into a RESTful API
- **Role:** PostgreSQL permission level (`anon`, `authenticated`, etc.)
- **Payload:** The data contained in a JWT (user ID, expiration, etc.)
- **Signature:** Cryptographic proof that the JWT hasn't been tampered with

---

## Next Steps

1. ✅ Complete database setup (`database/README.md`)
2. ✅ Configure PostgREST with JWT secret
3. ✅ Test signup/login with curl
4. ✅ Implement authentication in Flutter app
5. ✅ Add secure token storage in Flutter

**Questions?** Re-read this guide or ask for clarification!
