-- ============================================================================
-- STEP 0: Create Dedicated Schema for Anywhere Music Player
-- ============================================================================
-- This creates a separate schema to isolate this project from others
-- in the same PostgreSQL instance.
--
-- Why use a separate schema?
--   - Clean separation from other projects
--   - Prevent table name conflicts
--   - Easier permission management
--   - Easier backup/restore per project
-- ============================================================================

-- Create the schema
CREATE SCHEMA IF NOT EXISTS musicplayer;

-- Set search_path so all subsequent commands use this schema by default
-- This allows the rest of the SQL files to work without modification
SET search_path TO musicplayer, public;

-- Grant usage to roles (will be created in later scripts)
-- This is idempotent, so it won't fail if roles don't exist yet
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        GRANT USAGE ON SCHEMA musicplayer TO anon;
    END IF;

    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        GRANT USAGE ON SCHEMA musicplayer TO authenticated;
    END IF;

    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
        GRANT USAGE ON SCHEMA musicplayer TO authenticator;
    END IF;
END
$$;

-- Add comment for documentation
COMMENT ON SCHEMA musicplayer IS 'Anywhere Music Player - Self-hosted music streaming platform';

-- Show current search_path
SHOW search_path;
