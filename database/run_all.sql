-- ============================================================================
-- Run All Database Migrations
-- ============================================================================
-- This file executes all migration scripts in the correct order
--
-- Usage:
--   psql -h localhost -U postgres -d postgres -f run_all.sql
--
-- Or via SSH tunnel:
--   ssh -L 5432:localhost:5432 root@YOUR_IP
--   psql -h localhost -U postgres -d postgres -f run_all.sql
-- ============================================================================

\echo '========================================='
\echo 'Anywhere Music Player - Database Setup'
\echo '========================================='
\echo ''

\echo '[1/6] Creating dedicated schema (anistream)...'
\i 00_create_schema.sql
\echo '✓ Schema created'
\echo ''

\echo '[2/6] Enabling PostgreSQL extensions...'
\i 01_extensions.sql
\echo '✓ Extensions enabled'
\echo ''

\echo '[3/6] Creating users table...'
\i 02_users_table.sql
\echo '✓ Users table created'
\echo ''

\echo '[4/6] Creating tracks table...'
\i 03_tracks_table.sql
\echo '✓ Tracks table created'
\echo ''

\echo '[5/6] Creating authentication functions...'
\i 04_auth_functions.sql
\echo '✓ Auth functions created'
\echo ''

\echo '[6/6] Setting up PostgREST roles...'
\i 05_postgrest_roles.sql
\echo '✓ Roles configured'
\echo ''

\echo '========================================='
\echo 'Database setup complete! ✓'
\echo '========================================='
\echo ''
\echo 'Next steps:'
\echo '  1. Update JWT secret in 04_auth_functions.sql'
\echo '  2. Update authenticator password in 05_postgrest_roles.sql'
\echo '  3. Configure PostgREST in Coolify (use schema: anistream)'
\echo '  4. Test with: SELECT anistream.signup(...)'
\echo ''
