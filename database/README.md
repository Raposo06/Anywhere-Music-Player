# 🗄️ Database Setup Guide

This directory contains SQL scripts to set up your PostgreSQL database for the Anywhere Music Player with FastAPI backend.

## 📋 Quick Start

### Simple 3-Step Setup

Execute these SQL files in order:

```bash
# Connect to your PostgreSQL database
psql -h YOUR_HOST -U postgres -d postgres

# Then run each file:
\i 00_create_schema.sql
\i 02_users_table.sql
\i 03_tracks_table.sql
```

**That's it!** Your database is ready for FastAPI.

---

## 📁 Files

| File | Purpose |
|------|---------|
| `00_create_schema.sql` | Creates the `musicplayer` schema (isolated from other projects) |
| `02_users_table.sql` | Creates the `users` table for authentication |
| `03_tracks_table.sql` | Creates the `tracks` table for music metadata |

---

## 🔐 Grant Permissions to Postgres User

After running the scripts, grant permissions for the FastAPI backend:

```sql
-- Grant all permissions on musicplayer schema to postgres user
GRANT ALL PRIVILEGES ON SCHEMA musicplayer TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA musicplayer TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA musicplayer TO postgres;

-- Make sure future tables also get permissions
ALTER DEFAULT PRIVILEGES IN SCHEMA musicplayer
  GRANT ALL PRIVILEGES ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA musicplayer
  GRANT ALL PRIVILEGES ON SEQUENCES TO postgres;
```

**Why?** The FastAPI backend connects as the `postgres` user, so it needs full access to the `musicplayer` schema.

---

## 🗺️ Database Schema

```
Schema: musicplayer

┌─────────────────────────────┐
│    musicplayer.users        │
├─────────────────────────────┤
│ id (UUID) PK                │
│ email (TEXT) UNIQUE         │
│ username (TEXT) UNIQUE      │
│ password_hash (TEXT)        │
│ created_at (TIMESTAMPTZ)    │
└─────────────────────────────┘

┌─────────────────────────────┐
│    musicplayer.tracks       │
├─────────────────────────────┤
│ id (UUID) PK                │
│ title (TEXT)                │
│ filename (TEXT) UNIQUE      │
│ stream_url (TEXT)           │
│ cover_art_url (TEXT)        │
│ folder_path (TEXT)          │
│ duration_seconds (INTEGER)  │
│ file_size_bytes (BIGINT)    │
│ created_at (TIMESTAMPTZ)    │
└─────────────────────────────┘
```

**Note:**
- Passwords are hashed using **bcrypt** (handled by FastAPI backend)
- JWT tokens are generated in **Python** (not SQL)
- No complex PostgreSQL extensions needed!

---

## 🧪 Testing the Setup

### 1. Verify Tables Exist

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'musicplayer';
```

Expected output:
```
 table_name
------------
 users
 tracks
```

### 2. Check Permissions

```sql
SELECT
    grantee,
    privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'musicplayer'
  AND grantee = 'postgres';
```

You should see `SELECT`, `INSERT`, `UPDATE`, `DELETE` permissions.

### 3. Test via FastAPI

Once your FastAPI backend is running, test signup:

```bash
curl -X POST http://localhost:8000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "username": "testuser",
    "password": "password123"
  }'
```

Expected response:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "user": {
    "id": "uuid-here",
    "email": "test@example.com",
    "username": "testuser",
    "created_at": "2026-01-04T12:00:00Z"
  }
}
```

---

## 🔧 Troubleshooting

### Error: "permission denied for table users"

**Solution:** Run the grant permissions SQL above.

### Error: "schema musicplayer does not exist"

**Solution:** Run `00_create_schema.sql` first.

### Error: "relation tracks does not exist"

**Solution:** Make sure you ran all 3 SQL files in order.

---

## ✅ Next Steps

After database setup:

1. ✅ Deploy FastAPI backend (see `backend/README.md`)
2. ✅ Upload music files with `scripts/upload.py`
3. ✅ Test authentication via `/auth/signup` and `/auth/login`
4. ✅ Run the Flutter app to start streaming!

---

**Simple, clean, and ready for FastAPI!** No PostgREST complexity needed.
