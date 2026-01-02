-- ============================================================================
-- STEP 2: Users Table for Authentication
-- ============================================================================
-- This table stores user accounts for the music player
--
-- Security Notes:
--   - Passwords are NEVER stored in plain text
--   - We use bcrypt hashing via pgcrypto extension
--   - Email and username must be unique
-- ============================================================================

CREATE TABLE IF NOT EXISTS anistream.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'),
    username TEXT UNIQUE NOT NULL CHECK (length(username) >= 3),
    password_hash TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Index for faster login lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON anistream.users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON anistream.users(username);

-- Trigger to automatically update 'updated_at' timestamp
CREATE OR REPLACE FUNCTION anistream.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON anistream.users
    FOR EACH ROW
    EXECUTE FUNCTION anistream.update_updated_at_column();

-- Add comment for documentation
COMMENT ON TABLE anistream.users IS 'User accounts for authentication';
COMMENT ON COLUMN anistream.users.password_hash IS 'Bcrypt hashed password - NEVER store plain text passwords';
