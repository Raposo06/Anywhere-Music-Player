-- ============================================================================
-- STEP 1: Enable Required PostgreSQL Extensions
-- ============================================================================
-- This file enables the extensions needed for authentication and UUID generation
--
-- Extensions:
--   - pgcrypto: Password hashing (bcrypt)
--   - pgjwt: JWT token generation
--   - uuid-ossp: UUID generation (alternative to gen_random_uuid)
-- ============================================================================

-- Enable pgcrypto for password hashing with bcrypt
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Enable pgjwt for JWT token generation
CREATE EXTENSION IF NOT EXISTS pgjwt;

-- Enable uuid-ossp for UUID generation (backup for gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Verify extensions are enabled
SELECT
    extname AS extension_name,
    extversion AS version
FROM pg_extension
WHERE extname IN ('pgcrypto', 'pgjwt', 'uuid-ossp');
