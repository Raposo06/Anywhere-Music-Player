# 🗄️ Database Setup Guide

This directory contains SQL migration files to set up your PostgreSQL database for the Anywhere Music Player.

## 📋 Quick Start

### Option 1: Run All Scripts at Once (Recommended)

```bash
# Connect to your PostgreSQL database
psql -h YOUR_HETZNER_IP -U postgres -d postgres -f run_all.sql

# Or if using SSH tunnel:
ssh -L 5432:localhost:5432 root@YOUR_HETZNER_IP
psql -h localhost -U postgres -d postgres -f run_all.sql
```

### Option 2: Run Scripts Individually

Execute each file in order:

```bash
psql -h localhost -U postgres -d postgres -f 01_extensions.sql
psql -h localhost -U postgres -d postgres -f 02_users_table.sql
psql -h localhost -U postgres -d postgres -f 03_tracks_table.sql
psql -h localhost -U postgres -d postgres -f 04_auth_functions.sql
psql -h localhost -U postgres -d postgres -f 05_postgrest_roles.sql
```

### Option 3: Using DBeaver or pgAdmin

1. Connect to your PostgreSQL instance
2. Open each `.sql` file
3. Execute them in numerical order (01 → 05)

---

## 📁 File Descriptions

| File | Purpose | What it Creates |
|------|---------|----------------|
| `00_create_schema.sql` | Create dedicated schema | `anistream` schema (isolates from other projects) |
| `01_extensions.sql` | Enable PostgreSQL extensions | pgcrypto, pgjwt, uuid-ossp |
| `02_users_table.sql` | User authentication table | `anistream.users` table + indexes |
| `03_tracks_table.sql` | Music library metadata | `anistream.tracks` table + indexes |
| `04_auth_functions.sql` | Signup/Login functions | `anistream.signup()`, `anistream.login()` functions |
| `05_postgrest_roles.sql` | PostgREST permissions | `anon`, `authenticated`, `authenticator` roles |

---

## 🔐 Security Configuration

### **CRITICAL: Change These Values Before Deploying!**

#### 1. JWT Secret (`04_auth_functions.sql`)

**Line 56:**
```sql
jwt_secret TEXT := 'REPLACE_WITH_YOUR_JWT_SECRET_MIN_32_CHARS';
```

**Generate a secure secret:**
```bash
# Option 1: OpenSSL
openssl rand -base64 32

# Option 2: Python
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Option 3: Node.js
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
```

**Update the SQL file with your generated secret.**

#### 2. Authenticator Password (`05_postgrest_roles.sql`)

**Line 38:**
```sql
CREATE ROLE authenticator LOGIN PASSWORD 'CHANGE_THIS_PASSWORD';
```

**Generate a strong password:**
```bash
openssl rand -base64 24
```

**Update the SQL file with your generated password.**

---

## 🚀 PostgREST Configuration

After running the SQL scripts, configure PostgREST in Coolify:

### Environment Variables

Add these to your PostgREST service:

```bash
PGRST_DB_URI=postgres://authenticator:YOUR_PASSWORD@postgres:5432/postgres
PGRST_DB_SCHEMA=anistream
PGRST_DB_ANON_ROLE=anon
PGRST_JWT_SECRET=YOUR_JWT_SECRET_FROM_STEP_1
PGRST_JWT_SECRET_IS_BASE64=false
```

**Important:**
- The `PGRST_DB_SCHEMA` is set to `anistream` (our dedicated schema, not `public`)
- The `PGRST_JWT_SECRET` must match the `jwt_secret` in `04_auth_functions.sql`

---

## 🧪 Testing the Setup

### 1. Test Extensions

```sql
SELECT extname, extversion FROM pg_extension
WHERE extname IN ('pgcrypto', 'pgjwt', 'uuid-ossp');
```

Expected output:
```
  extname   | extversion
------------+------------
 pgcrypto   | 1.3
 pgjwt      | 0.2.0
 uuid-ossp  | 1.1
```

### 2. Test Signup Function

```sql
SELECT anistream.signup(
    'test@example.com',
    'testuser',
    'securepassword123'
);
```

Expected output:
```json
{
  "success": true,
  "user_id": "a1b2c3d4-...",
  "message": "Account created successfully"
}
```

### 3. Test Login Function

```sql
SELECT anistream.login('test@example.com', 'securepassword123');
```

Expected output:
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

### 4. Test PostgREST API

```bash
# Signup via API
curl -X POST https://api.YOUR_DOMAIN/rpc/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "api-test@example.com",
    "username": "apiuser",
    "password": "testpass123"
  }'

# Login via API
curl -X POST https://api.YOUR_DOMAIN/rpc/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "api-test@example.com",
    "password": "testpass123"
  }'

# Get tracks (authenticated)
curl https://api.YOUR_DOMAIN/tracks \
  -H "Authorization: Bearer YOUR_JWT_TOKEN_HERE"
```

---

## 🗺️ Database Schema Diagram

```
Schema: anistream (isolated from other projects)

┌─────────────────────────────┐
│    anistream.users          │
├─────────────────────────────┤
│ id (UUID) PK                │
│ email (TEXT) UNIQUE         │
│ username (TEXT) UNIQUE      │
│ password_hash (TEXT)        │
│ created_at (TIMESTAMPTZ)    │
│ updated_at (TIMESTAMPTZ)    │
└─────────────────────────────┘

┌─────────────────────────────┐
│    anistream.tracks         │
├─────────────────────────────┤
│ id (UUID) PK                │
│ title (TEXT)                │
│ artist (TEXT)               │
│ album (TEXT)                │
│ filename (TEXT) UNIQUE      │
│ stream_url (TEXT)           │
│ cover_art_url (TEXT)        │
│ duration_seconds (INTEGER)  │
│ file_size_bytes (BIGINT)    │
│ created_at (TIMESTAMPTZ)    │
│ updated_at (TIMESTAMPTZ)    │
└─────────────────────────────┘
```

---

## 📚 Learning Resources

### Understanding JWT (JSON Web Tokens)

A JWT has 3 parts separated by dots: `header.payload.signature`

**Example JWT:**
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiYTFiMi4uLiIsImV4cCI6MTczNTk4NzY1NH0.signature
```

**Decoded:**
```json
// Header
{
  "alg": "HS256",
  "typ": "JWT"
}

// Payload (this is what your app reads)
{
  "user_id": "a1b2c3d4-...",
  "email": "user@example.com",
  "role": "authenticated",
  "iat": 1735387654,  // Issued at (Unix timestamp)
  "exp": 1735987654   // Expires (Unix timestamp)
}

// Signature (verifies the token hasn't been tampered with)
```

### How PostgREST Uses JWT

1. Client sends: `Authorization: Bearer <JWT>`
2. PostgREST verifies signature using `PGRST_JWT_SECRET`
3. If valid, PostgREST switches to `authenticated` role
4. If invalid/missing, PostgREST uses `anon` role
5. PostgreSQL enforces permissions based on role

---

## 🔧 Troubleshooting

### Error: "extension does not exist"

**Problem:** `pgjwt` extension not installed

**Solution:**
```bash
# SSH into your Hetzner server
ssh root@YOUR_HETZNER_IP

# Enter PostgreSQL container
docker exec -it <postgres-container-id> bash

# Install pgjwt
apt update && apt install -y postgresql-contrib
```

### Error: "role already exists"

**Problem:** Re-running `05_postgrest_roles.sql`

**Solution:** This is safe to ignore, or use `DROP ROLE` first:
```sql
DROP ROLE IF EXISTS anon;
DROP ROLE IF EXISTS authenticated;
DROP ROLE IF EXISTS authenticator;
```

### Error: "permission denied for schema public"

**Problem:** Roles don't have proper grants

**Solution:** Re-run `05_postgrest_roles.sql`

---

## ✅ Next Steps

After database setup is complete:

1. ✅ Configure PostgREST in Coolify with the environment variables above
2. ✅ Test the API endpoints with curl
3. ✅ Create your first user account via `/rpc/signup`
4. ✅ Run the Python uploader script to populate tracks
5. ✅ Build the Flutter app to connect to your API

---

**Questions?** Check the main README.md or the `/docs/AUTHENTICATION.md` guide.
