"""
Authentication endpoints: signup and login.
"""
from fastapi import APIRouter, HTTPException
from models import SignupRequest, LoginRequest, AuthResponse, UserResponse
from auth import hash_password, verify_password, create_access_token
from database import execute_query, execute_insert

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/signup", response_model=AuthResponse)
def signup(request: SignupRequest):
    """
    Create a new user account.

    Args:
        request: Signup request with email, username, password

    Returns:
        JWT token and user information

    Raises:
        HTTPException 400: If email or username already exists
        HTTPException 500: If database error occurs
    """
    # Check if email already exists
    existing_user = execute_query(
        "SELECT id FROM musicplayer.users WHERE email = %s",
        (request.email,),
        fetch_one=True
    )

    if existing_user:
        raise HTTPException(status_code=400, detail="Email already registered")

    # Check if username already exists
    existing_username = execute_query(
        "SELECT id FROM musicplayer.users WHERE username = %s",
        (request.username,),
        fetch_one=True
    )

    if existing_username:
        raise HTTPException(status_code=400, detail="Username already taken")

    # Hash password
    password_hash = hash_password(request.password)

    # Insert user
    try:
        user = execute_insert(
            """
            INSERT INTO musicplayer.users (email, username, password_hash)
            VALUES (%s, %s, %s)
            RETURNING id, email, username, created_at
            """,
            (request.email, request.username, password_hash)
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create user: {str(e)}")

    # Generate JWT token
    token = create_access_token(user["id"], user["email"])

    # Return response
    return AuthResponse(
        token=token,
        user=UserResponse(**user)
    )


@router.post("/login", response_model=AuthResponse)
def login(request: LoginRequest):
    """
    Login with email and password.

    Args:
        request: Login request with email and password

    Returns:
        JWT token and user information

    Raises:
        HTTPException 401: If email not found or password incorrect
    """
    # Get user by email
    user = execute_query(
        """
        SELECT id, email, username, password_hash, created_at
        FROM musicplayer.users
        WHERE email = %s
        """,
        (request.email,),
        fetch_one=True
    )

    if not user:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    # Verify password
    if not verify_password(request.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    # Generate JWT token
    token = create_access_token(user["id"], user["email"])

    # Remove password_hash from response
    user_data = {k: v for k, v in user.items() if k != "password_hash"}

    # Return response
    return AuthResponse(
        token=token,
        user=UserResponse(**user_data)
    )
