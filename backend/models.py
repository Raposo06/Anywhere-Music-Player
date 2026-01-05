"""
Pydantic models for request/response validation.
"""
from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from datetime import datetime


# ============================================================================
# Authentication Models
# ============================================================================

class SignupRequest(BaseModel):
    email: EmailStr
    username: str = Field(..., min_length=3)
    password: str = Field(..., min_length=8)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class UserResponse(BaseModel):
    id: str
    email: str
    username: str
    created_at: datetime


class AuthResponse(BaseModel):
    token: str
    user: UserResponse


# ============================================================================
# Track Models
# ============================================================================

class TrackResponse(BaseModel):
    id: str
    title: str
    filename: str
    stream_url: str
    cover_art_url: Optional[str] = None
    folder_path: str
    duration_seconds: Optional[int] = None
    file_size_bytes: Optional[int] = None
    created_at: datetime


class FolderResponse(BaseModel):
    folder_path: str
    track_count: int
