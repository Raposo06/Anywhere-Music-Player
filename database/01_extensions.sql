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

-- 1. Enable Standard Extensions (pgcrypto is required for our manual JWT functions)
-- We install these in 'public' so they are accessible globally, or you can specify 'musicplayer'
CREATE EXTENSION IF NOT EXISTS pgcrypto ;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" ;

-- -------------------------------------------------------------------------
-- 2. Manually Create JWT Functions in 'musicplayer' schema
-- (This replaces "CREATE EXTENSION pgjwt")
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION musicplayer.url_encode(data bytea) RETURNS text LANGUAGE sql AS $$
    SELECT translate(encode(data, 'base64'), E'+/=\n', '-_');
$$ IMMUTABLE;

CREATE OR REPLACE FUNCTION musicplayer.url_decode(data text) RETURNS bytea LANGUAGE sql AS $$
WITH t AS (SELECT translate(data, '-_', '+/') AS trans),
     rem AS (SELECT length(t.trans) % 4 AS remainder FROM t)
    SELECT decode(
        t.trans ||
        CASE WHEN rem.remainder > 0
           THEN repeat('=', (4 - rem.remainder))
           ELSE '' END,
    'base64') FROM t, rem;
$$ IMMUTABLE;

CREATE OR REPLACE FUNCTION musicplayer.algorithm_sign(signables text, secret text, algorithm text)
RETURNS text LANGUAGE sql AS $$
WITH
  alg AS (
    SELECT CASE
      WHEN algorithm = 'HS256' THEN 'sha256'
      WHEN algorithm = 'HS384' THEN 'sha384'
      WHEN algorithm = 'HS512' THEN 'sha512'
      ELSE '' END AS id)
SELECT musicplayer.url_encode(public.hmac(signables::bytea, secret::bytea, alg.id)) FROM alg;
$$ IMMUTABLE;

CREATE OR REPLACE FUNCTION musicplayer.sign(payload json, secret text, algorithm text DEFAULT 'HS256')
RETURNS text LANGUAGE sql AS $$
WITH
  header AS (
    SELECT musicplayer.url_encode(convert_to('{"alg":"' || algorithm || '","typ":"JWT"}', 'utf8')) AS data
    ),
  payload AS (
    SELECT musicplayer.url_encode(convert_to(payload::text, 'utf8')) AS data
    ),
  signables AS (
    SELECT header.data || '.' || payload.data AS data FROM header, payload
    )
SELECT
    signables.data || '.' ||
    musicplayer.algorithm_sign(signables.data, secret, algorithm) FROM signables;
$$ IMMUTABLE;

CREATE OR REPLACE FUNCTION musicplayer.try_cast_double(inp text)
RETURNS double precision AS $$
  BEGIN
    BEGIN
      RETURN inp::double precision;
    EXCEPTION
      WHEN OTHERS THEN RETURN NULL;
    END;
  END;
$$ language plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION musicplayer.verify(token text, secret text, algorithm text DEFAULT 'HS256')
RETURNS table(header json, payload json, valid boolean) LANGUAGE sql AS $$
  SELECT
    jwt.header AS header,
    jwt.payload AS payload,
    jwt.signature_ok AND tstzrange(
      to_timestamp(musicplayer.try_cast_double(jwt.payload->>'nbf')),
      to_timestamp(musicplayer.try_cast_double(jwt.payload->>'exp'))
    ) @> CURRENT_TIMESTAMP AS valid
  FROM (
    SELECT
      convert_from(musicplayer.url_decode(r[1]), 'utf8')::json AS header,
      convert_from(musicplayer.url_decode(r[2]), 'utf8')::json AS payload,
      r[3] = musicplayer.algorithm_sign(r[1] || '.' || r[2], secret, algorithm) AS signature_ok
    FROM regexp_split_to_array(token, '\.') r
  ) jwt
$$ IMMUTABLE;

-- Enable uuid-ossp for UUID generation (backup for gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Verify extensions are enabled
SELECT
    extname AS extension_name,
    extversion AS version
FROM pg_extension
WHERE extname IN ('pgcrypto', 'uuid-ossp');
