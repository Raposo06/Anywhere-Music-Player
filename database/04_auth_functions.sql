-- ============================================================================
-- STEP 4: Authentication Functions
-- ============================================================================
-- These PostgreSQL functions handle user registration and login
--
-- Functions:
--   1. signup(email, username, password) - Create new user account
--   2. login(email, password) - Authenticate and return JWT token
--
-- Learning Notes:
--   - Passwords are hashed using bcrypt (via crypt function)
--   - JWT tokens contain: user_id, role, and expiration time
--   - SECURITY DEFINER allows function to access users table
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Function: signup
-- Purpose: Register a new user with hashed password
-- Returns: JSON with user_id and success message
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION anistream.signup(
    email TEXT,
    username TEXT,
    password TEXT
)
RETURNS JSON AS $$
DECLARE
    new_user_id UUID;
BEGIN
    -- Validate password strength (minimum 8 characters)
    IF length(password) < 8 THEN
        RAISE EXCEPTION 'Password must be at least 8 characters long';
    END IF;

    -- Insert new user with bcrypt-hashed password
    INSERT INTO anistream.users (email, username, password_hash)
    VALUES (
        signup.email,
        signup.username,
        crypt(signup.password, gen_salt('bf', 8))  -- bcrypt with cost factor 8
    )
    RETURNING id INTO new_user_id;

    -- Return success response
    RETURN json_build_object(
        'success', true,
        'user_id', new_user_id,
        'message', 'Account created successfully'
    );

EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Email or username already exists';
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Signup failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ----------------------------------------------------------------------------
-- Function: login
-- Purpose: Authenticate user and generate JWT token
-- Returns: JSON with JWT token and user info
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION anistream.login(
    email TEXT,
    password TEXT
)
RETURNS JSON AS $$
DECLARE
    user_record RECORD;
    jwt_token TEXT;
    jwt_secret TEXT := 'REPLACE_WITH_YOUR_JWT_SECRET_MIN_32_CHARS';  -- CHANGE THIS!
BEGIN
    -- Find user and verify password
    SELECT id, username, email INTO user_record
    FROM anistream.users
    WHERE users.email = login.email
    AND password_hash = crypt(login.password, password_hash);

    -- If no match found, invalid credentials
    IF user_record.id IS NULL THEN
        RAISE EXCEPTION 'Invalid email or password';
    END IF;

    -- Generate JWT token (expires in 7 days)
    SELECT sign(
        row_to_json(payload),
        jwt_secret
    ) INTO jwt_token
    FROM (
        SELECT
            user_record.id AS user_id,
            user_record.email AS email,
            'authenticated' AS role,
            extract(epoch from now())::integer AS iat,  -- Issued at
            extract(epoch from now() + interval '7 days')::integer AS exp  -- Expiration
    ) AS payload;

    -- Return token and user info
    RETURN json_build_object(
        'token', jwt_token,
        'user', json_build_object(
            'id', user_record.id,
            'email', user_record.email,
            'username', user_record.username
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Login failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ----------------------------------------------------------------------------
-- Grant permissions for PostgREST
-- ----------------------------------------------------------------------------
-- Allow anonymous users to call signup and login functions
GRANT EXECUTE ON FUNCTION anistream.signup(TEXT, TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION anistream.login(TEXT, TEXT) TO anon;

-- Add comments for documentation
COMMENT ON FUNCTION anistream.signup IS 'Register new user with bcrypt password hashing';
COMMENT ON FUNCTION anistream.login IS 'Authenticate user and return JWT token (7-day expiration)';
