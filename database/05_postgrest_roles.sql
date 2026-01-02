-- ============================================================================
-- STEP 5: PostgREST Roles and Permissions
-- ============================================================================
-- PostgREST uses PostgreSQL roles to handle authentication
--
-- Roles:
--   - anon: Unauthenticated users (can only signup/login)
--   - authenticated: Logged-in users (can access tracks)
--   - authenticator: PostgREST connection role (switches to anon/authenticated)
--
-- Learning Notes:
--   - PostgREST connects as 'authenticator'
--   - It switches to 'anon' for requests without JWT
--   - It switches to 'authenticated' for valid JWT requests
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Create Roles
-- ----------------------------------------------------------------------------

-- Role: anon (for public/unauthenticated requests)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
END
$$;

-- Role: authenticated (for logged-in users with valid JWT)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
END
$$;

-- Role: authenticator (PostgREST connection role)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
        CREATE ROLE authenticator LOGIN PASSWORD 'CHANGE_THIS_PASSWORD';
    END IF;
END
$$;

-- Allow authenticator to switch to anon or authenticated
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;


-- ----------------------------------------------------------------------------
-- Grant Permissions
-- ----------------------------------------------------------------------------

-- Anonymous users can:
--   - Call signup and login functions (already granted in 04_auth_functions.sql)
--   - Nothing else (security!)

-- Authenticated users can:
--   - Read all tracks (SELECT)
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON public.tracks TO authenticated;

-- Prevent authenticated users from modifying tracks
-- (only the Python upload script can write to tracks)
REVOKE INSERT, UPDATE, DELETE ON public.tracks FROM authenticated;


-- ----------------------------------------------------------------------------
-- Row-Level Security (Optional - Future Enhancement)
-- ----------------------------------------------------------------------------
-- Uncomment this section when you add 'favorites' or 'playlists' tables
-- where users should only see their own data

-- ALTER TABLE public.tracks ENABLE ROW LEVEL SECURITY;
--
-- CREATE POLICY "Users can view all tracks"
--     ON public.tracks
--     FOR SELECT
--     TO authenticated
--     USING (true);


-- Add comments for documentation
COMMENT ON ROLE anon IS 'Unauthenticated users - can only signup/login';
COMMENT ON ROLE authenticated IS 'Logged-in users with valid JWT token';
COMMENT ON ROLE authenticator IS 'PostgREST connection role - switches to anon or authenticated';
