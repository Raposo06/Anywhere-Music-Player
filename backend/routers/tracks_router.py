"""
Tracks endpoints: list, search, and folder management.
"""
from fastapi import APIRouter, Depends, Query
from typing import List, Optional
from models import TrackResponse, FolderResponse
from auth import get_current_user
from database import execute_query

router = APIRouter(prefix="/tracks", tags=["Tracks"])


@router.get("", response_model=List[TrackResponse])
def get_tracks(
    current_user: dict = Depends(get_current_user),
    folder_path: Optional[str] = Query(None, description="Filter by folder path"),
    limit: int = Query(1000, description="Maximum number of tracks to return"),
    offset: int = Query(0, description="Number of tracks to skip")
):
    """
    Get all tracks with optional filtering.

    Requires authentication (JWT token in Authorization header).

    Args:
        current_user: Authenticated user (from JWT token)
        folder_path: Optional folder path filter
        limit: Maximum tracks to return (default 1000)
        offset: Pagination offset (default 0)

    Returns:
        List of tracks
    """
    # Build query based on filters
    if folder_path:
        query = """
            SELECT id, title, filename, stream_url, cover_art_url,
                   folder_path, duration_seconds, file_size_bytes, created_at
            FROM musicplayer.tracks
            WHERE folder_path = %s
            ORDER BY created_at DESC
            LIMIT %s OFFSET %s
        """
        params = (folder_path, limit, offset)
    else:
        query = """
            SELECT id, title, filename, stream_url, cover_art_url,
                   folder_path, duration_seconds, file_size_bytes, created_at
            FROM musicplayer.tracks
            ORDER BY created_at DESC
            LIMIT %s OFFSET %s
        """
        params = (limit, offset)

    tracks = execute_query(query, params)
    return [TrackResponse(**track) for track in tracks]


@router.get("/search", response_model=List[TrackResponse])
def search_tracks(
    query: str = Query(..., min_length=1, description="Search query"),
    current_user: dict = Depends(get_current_user)
):
    """
    Search tracks by title or folder path.

    Requires authentication (JWT token in Authorization header).

    Args:
        query: Search query string
        current_user: Authenticated user (from JWT token)

    Returns:
        List of matching tracks
    """
    search_query = """
        SELECT id, title, filename, stream_url, cover_art_url,
               folder_path, duration_seconds, file_size_bytes, created_at
        FROM musicplayer.tracks
        WHERE title ILIKE %s OR folder_path ILIKE %s
        ORDER BY created_at DESC
        LIMIT 100
    """
    search_pattern = f"%{query}%"
    tracks = execute_query(search_query, (search_pattern, search_pattern))
    return [TrackResponse(**track) for track in tracks]


@router.get("/folders", response_model=List[FolderResponse])
def get_folders(current_user: dict = Depends(get_current_user)):
    """
    Get all unique folder paths with track counts.

    Requires authentication (JWT token in Authorization header).

    Args:
        current_user: Authenticated user (from JWT token)

    Returns:
        List of folders with track counts
    """
    query = """
        SELECT folder_path, COUNT(*) as track_count
        FROM musicplayer.tracks
        GROUP BY folder_path
        ORDER BY folder_path
    """
    folders = execute_query(query)
    return [FolderResponse(**folder) for folder in folders]


@router.get("/{track_id}", response_model=TrackResponse)
def get_track(
    track_id: str,
    current_user: dict = Depends(get_current_user)
):
    """
    Get a single track by ID.

    Requires authentication (JWT token in Authorization header).

    Args:
        track_id: Track UUID
        current_user: Authenticated user (from JWT token)

    Returns:
        Track details

    Raises:
        HTTPException 404: If track not found
    """
    from fastapi import HTTPException

    query = """
        SELECT id, title, filename, stream_url, cover_art_url,
               folder_path, duration_seconds, file_size_bytes, created_at
        FROM musicplayer.tracks
        WHERE id = %s
    """
    track = execute_query(query, (track_id,), fetch_one=True)

    if not track:
        raise HTTPException(status_code=404, detail="Track not found")

    return TrackResponse(**track)
