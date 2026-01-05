-- ============================================================================
-- STEP 2: Users Table for Authentication
-- ============================================================================
-- This table stores user accounts for the music player
--
-- Security Notes:
--   - Passwords are NEVER stored in plain text
--   - We use bcrypt hashing via pgcrypto extension
--   - Email and username must be unique
--
-- Design Notes (for small user base):
--   - Only email is indexed (used for login)
--   - No updated_at tracking (overkill for 2-3 users)
-- ============================================================================

CREATE TABLE IF NOT EXISTS musicplayer.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'),
    username TEXT UNIQUE NOT NULL CHECK (length(username) >= 3),
    password_hash TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Index for faster login lookups (email is used for authentication)
CREATE INDEX IF NOT EXISTS idx_users_email ON musicplayer.users(email);

-- Add comment for documentation
COMMENT ON TABLE musicplayer.users IS 'User accounts for authentication';
COMMENT ON COLUMN musicplayer.users.password_hash IS 'Bcrypt hashed password - NEVER store plain text passwords';
