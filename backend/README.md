# Anywhere Music Player - FastAPI Backend

A simple, powerful REST API for music streaming built with FastAPI. Replaces PostgREST for easier deployment and debugging.

## ✨ Features

- 🔐 **JWT Authentication** - Secure user signup and login
- 🎵 **Track Management** - List, search, and filter tracks
- 📁 **Folder Organization** - Group tracks by folder structure
- 🚀 **Fast & Async** - Built on FastAPI for high performance
- 📚 **Auto-generated Docs** - Swagger UI at `/docs`
- 🐳 **Docker Ready** - One-command deployment
- 🔧 **Simple CORS** - Easy cross-origin configuration

---

## 📋 Prerequisites

- Python 3.11+ (for local development)
- Docker (for deployment)
- PostgreSQL database (already set up with database/ scripts)

---

## 🚀 Quick Start

### Option 1: Run Locally (Development)

1. **Install dependencies:**

```bash
cd backend
pip install -r requirements.txt
```

2. **Configure environment:**

```bash
cp .env.example .env
# Edit .env with your database credentials
```

3. **Run the server:**

```bash
python main.py
```

The API will be available at `http://localhost:8000`

**Docs:**
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

### Option 2: Run with Docker

1. **Build the image:**

```bash
docker build -t music-player-api .
```

2. **Run the container:**

```bash
docker run -d \
  -p 8000:8000 \
  -e DB_HOST=your_db_host \
  -e DB_PASSWORD=your_db_password \
  -e JWT_SECRET=your_jwt_secret \
  --name music-api \
  music-player-api
```

---

## 🌐 Deploy to Coolify

### Step 1: Prepare PostgreSQL

Make sure you've run all SQL scripts in the `database/` folder:

```sql
-- In psql or Coolify PostgreSQL terminal:
\i /path/to/00_create_schema.sql
\i /path/to/01_extensions.sql
\i /path/to/02_users_table.sql
\i /path/to/03_tracks_table.sql
\i /path/to/04_auth_functions.sql
\i /path/to/05_postgrest_roles.sql
```

**Note:** You don't need the `authenticator` role or PostgREST roles anymore, but they won't hurt if they exist.

### Step 2: Deploy in Coolify

1. **Create a new service** in Coolify
   - Type: **Docker Compose**
   - Copy the contents of `docker-compose.yml`

2. **Set environment variables** in Coolify:

```bash
DB_PASSWORD=your_postgres_password
JWT_SECRET=your_jwt_secret_min_32_chars
```

**Generate JWT Secret:**
```bash
openssl rand -base64 32
```

3. **Configure domain:**
   - Set your public domain: `api.n8nauto.win`
   - Enable HTTPS/SSL

4. **Deploy!**
   - Click "Deploy"
   - Wait for health check to pass

### Step 3: Test the API

```bash
# Health check
curl https://api.n8nauto.win/

# Should return JSON with API info
```

---

## 🔧 Configuration

### Environment Variables

All configuration is done via environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `PORT` | Server port | `8000` |
| `DB_HOST` | PostgreSQL host | `postgresql_database` (Coolify service name) |
| `DB_PORT` | PostgreSQL port | `5432` |
| `DB_NAME` | Database name | `postgres` |
| `DB_USER` | Database user | `postgres` |
| `DB_PASSWORD` | Database password | `your_password` |
| `DB_SCHEMA` | Schema name | `musicplayer` |
| `JWT_SECRET` | JWT signing secret (32+ chars) | Generated with `openssl rand -base64 32` |
| `CORS_ORIGINS` | Allowed origins (comma-separated) | `*` (dev) or `https://music.yourdomain.com` (prod) |

### CORS Configuration

**Development (allow all):**
```bash
CORS_ORIGINS=*
```

**Production (restrict):**
```bash
CORS_ORIGINS=https://music.yourdomain.com,https://app.yourdomain.com
```

---

## 📡 API Endpoints

### Authentication

#### `POST /auth/signup`
Create a new user account.

**Request:**
```json
{
  "email": "user@example.com",
  "username": "johndoe",
  "password": "secure_password"
}
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "username": "johndoe",
    "created_at": "2026-01-04T12:00:00Z"
  }
}
```

#### `POST /auth/login`
Login with email and password.

**Request:**
```json
{
  "email": "user@example.com",
  "password": "secure_password"
}
```

**Response:** Same as signup

### Tracks

#### `GET /tracks`
Get all tracks (requires authentication).

**Headers:**
```
Authorization: Bearer <your_jwt_token>
```

**Query Parameters:**
- `folder_path` (optional): Filter by folder
- `limit` (optional): Max tracks to return (default: 1000)
- `offset` (optional): Pagination offset (default: 0)

**Response:**
```json
[
  {
    "id": "uuid",
    "title": "Track Name",
    "filename": "track.mp3",
    "stream_url": "https://minio.example.com/music/track.mp3",
    "cover_art_url": "https://minio.example.com/music/covers/track.jpg",
    "folder_path": "Animes/Naruto",
    "duration_seconds": 180,
    "file_size_bytes": 5242880,
    "created_at": "2026-01-04T12:00:00Z"
  }
]
```

#### `GET /tracks/search?query=naruto`
Search tracks by title or folder path.

**Headers:**
```
Authorization: Bearer <your_jwt_token>
```

**Query Parameters:**
- `query` (required): Search query

**Response:** Same as GET /tracks

#### `GET /tracks/folders`
Get unique folders with track counts.

**Headers:**
```
Authorization: Bearer <your_jwt_token>
```

**Response:**
```json
[
  {
    "folder_path": "Animes/Naruto",
    "track_count": 25
  },
  {
    "folder_path": "Animes/Tekken",
    "track_count": 15
  }
]
```

#### `GET /tracks/{track_id}`
Get a single track by ID.

**Headers:**
```
Authorization: Bearer <your_jwt_token>
```

**Response:** Single track object

---

## 🧪 Testing

### Interactive API Docs

Visit `http://localhost:8000/docs` for Swagger UI where you can:
- View all endpoints
- Test requests interactively
- See request/response schemas

### Manual Testing with curl

**1. Create account:**
```bash
curl -X POST http://localhost:8000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@test.com",
    "username": "testuser",
    "password": "password123"
  }'
```

**2. Login:**
```bash
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@test.com",
    "password": "password123"
  }'
```

Copy the `token` from the response.

**3. Get tracks:**
```bash
curl http://localhost:8000/tracks \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

---

## 🔄 Migration from PostgREST

If you previously had PostgREST running:

### ✅ What Stays the Same:
- PostgreSQL database and schema
- All your uploaded tracks
- MinIO storage
- Upload script

### 🔄 What Changes:
1. **Delete PostgREST service** in Coolify
2. **Deploy this FastAPI backend** instead
3. **Update Flutter app's `.env`:**
   ```
   API_BASE_URL=https://api.n8nauto.win
   ```
4. **Restart Flutter app** - that's it!

The Flutter app has been updated to work with FastAPI endpoints automatically.

---

## 🐛 Troubleshooting

### Issue: "Connection refused" or "Network error"

**Solution:** Check that:
1. Backend is running: `curl http://localhost:8000/`
2. Database connection works (check logs)
3. Firewall allows port 8000

### Issue: "Invalid or expired token"

**Solution:**
1. JWT tokens expire after 7 days - login again
2. Make sure `JWT_SECRET` matches between backend and database (if you set one in SQL scripts)

### Issue: "Failed to fetch tracks"

**Solution:**
1. Make sure you're logged in (have a valid token)
2. Check Authorization header: `Bearer <token>`
3. Verify database has tracks: `SELECT COUNT(*) FROM musicplayer.tracks;`

### Issue: CORS errors in browser

**Solution:**
1. Check `CORS_ORIGINS` environment variable
2. Make sure it includes your Flutter web domain
3. For development, use `CORS_ORIGINS=*`

---

## 📁 Project Structure

```
backend/
├── main.py              # FastAPI application entry point
├── models.py            # Pydantic models (request/response)
├── auth.py              # JWT and password utilities
├── database.py          # PostgreSQL connection
├── routers/
│   ├── __init__.py
│   ├── auth_router.py   # Signup/login endpoints
│   └── tracks_router.py # Track management endpoints
├── requirements.txt     # Python dependencies
├── Dockerfile           # Docker build configuration
├── docker-compose.yml   # Coolify deployment config
├── .env.example         # Environment template
└── README.md            # This file
```

---

## 🚦 Health Checks

The API includes a health check endpoint at `/` that returns:

```json
{
  "name": "Anywhere Music Player API",
  "version": "1.0.0",
  "status": "running",
  "docs": "/docs"
}
```

Docker health checks run every 30 seconds and verify the API is responding.

---

## 📝 Development

### Adding New Endpoints

1. Create or edit a router in `routers/`
2. Define Pydantic models in `models.py` if needed
3. Import and include router in `main.py`
4. Test at `/docs`

### Database Queries

Use the `database.py` utilities:

```python
from database import execute_query, execute_insert

# Fetch multiple rows
tracks = execute_query("SELECT * FROM musicplayer.tracks LIMIT 10")

# Fetch single row
user = execute_query(
    "SELECT * FROM musicplayer.users WHERE email = %s",
    ("user@example.com",),
    fetch_one=True
)

# Insert and return
new_track = execute_insert(
    "INSERT INTO musicplayer.tracks (title) VALUES (%s) RETURNING *",
    ("Track Title",)
)
```

---

## 🎉 That's It!

You now have a simple, powerful REST API for your music player. No more PostgREST headaches!

**Next steps:**
1. Deploy backend to Coolify
2. Upload music with `scripts/upload.py`
3. Run Flutter app and enjoy your music!

---

## 📞 Support

If you encounter issues:
1. Check logs in Coolify
2. Test endpoints with `/docs`
3. Verify database connectivity
4. Check environment variables

**Pro tip:** The `/docs` endpoint is your best friend for testing!
