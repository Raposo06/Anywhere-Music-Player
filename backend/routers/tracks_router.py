"""
Tracks endpoints: list, search, and folder management.
"""
from fastapi import APIRouter, Depends, Query, HTTPException
from fastapi.responses import StreamingResponse
from typing import List, Optional
import os
import requests
from models import TrackResponse, FolderResponse
from auth import get_current_user
from database import execute_query

router = APIRouter(prefix="/tracks", tags=["Tracks"])


def _build_stream_url(track_id: str) -> str:
    """Build streaming URL for a track using our proxy endpoint."""
    api_base = os.getenv("API_BASE_URL", "http://localhost:8000")
    return f"{api_base}/tracks/{track_id}/stream"


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

    # Replace stream_url with proxy endpoint
    for track in tracks:
        track["stream_url"] = _build_stream_url(track["id"])

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

    # Replace stream_url with proxy endpoint
    for track in tracks:
        track["stream_url"] = _build_stream_url(track["id"])

    return [TrackResponse(**track) for track in tracks]


@router.get("/folders", response_model=List[FolderResponse])
def get_folders(
    current_user: dict = Depends(get_current_user),
    parent_path: Optional[str] = Query(None, description="Parent folder path to get children from")
):
    """
    Get folders with hierarchical support.

    - Without parent_path: Returns only root-level folders (no "/" in path)
    - With parent_path="Animes": Returns direct children like "Animes/Pokemon", "Animes/Naruto"

    Requires authentication (JWT token in Authorization header).

    Args:
        current_user: Authenticated user (from JWT token)
        parent_path: Optional parent folder to get children from

    Returns:
        List of folders with track counts
    """
    if parent_path is None:
        # Get root-level folders (no "/" in folder_path)
        query = """
            SELECT
                folder_path,
                COUNT(*) as track_count
            FROM musicplayer.tracks
            WHERE folder_path NOT LIKE '%/%'
            GROUP BY folder_path
            ORDER BY folder_path
        """
        folders = execute_query(query)
    else:
        # Get direct children of parent_path
        # For parent_path="Animes", match "Animes/Pokemon" but not "Animes/Pokemon/Season1"
        query = """
            SELECT
                folder_path,
                COUNT(*) as track_count
            FROM musicplayer.tracks
            WHERE folder_path LIKE %s
              AND folder_path != %s
              AND LENGTH(folder_path) - LENGTH(REPLACE(folder_path, '/', '')) =
                  LENGTH(%s) - LENGTH(REPLACE(%s, '/', '')) + 1
            GROUP BY folder_path
            ORDER BY folder_path
        """
        parent_pattern = f"{parent_path}/%"
        folders = execute_query(query, (parent_pattern, parent_path, parent_path, parent_path))

    return [FolderResponse(**folder) for folder in folders]


@router.get("/folders/search", response_model=List[FolderResponse])
def search_folders(
    query: str = Query(..., min_length=1, description="Search query for folder names"),
    current_user: dict = Depends(get_current_user)
):
    """
    Search folders by name.

    Searches the folder_path field and returns matching folders with track counts.

    Args:
        query: Search query string
        current_user: Authenticated user (from JWT token)

    Returns:
        List of matching folders with track counts
    """
    search_query = """
        SELECT folder_path, COUNT(*) as track_count
        FROM musicplayer.tracks
        WHERE folder_path ILIKE %s
        GROUP BY folder_path
        ORDER BY folder_path
        LIMIT 50
    """
    search_pattern = f"%{query}%"
    folders = execute_query(search_query, (search_pattern,))
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
    query = """
        SELECT id, title, filename, stream_url, cover_art_url,
               folder_path, duration_seconds, file_size_bytes, created_at
        FROM musicplayer.tracks
        WHERE id = %s
    """
    track = execute_query(query, (track_id,), fetch_one=True)

    if not track:
        raise HTTPException(status_code=404, detail="Track not found")

    # Replace stream_url with proxy endpoint
    track["stream_url"] = _build_stream_url(track["id"])

    return TrackResponse(**track)


@router.get("/{track_id}/stream")
def stream_track(
    track_id: str,
    current_user: dict = Depends(get_current_user)
):
    """
    Stream audio file for a track.

    This endpoint proxies the audio file from MinIO storage, solving CORS issues
    and allowing authenticated access to audio files.

    Requires authentication (JWT token in Authorization header).

    Args:
        track_id: Track UUID
        current_user: Authenticated user (from JWT token)

    Returns:
        Streaming audio file

    Raises:
        HTTPException 404: If track not found
        HTTPException 500: If streaming fails
    """
    # Get track from database
    query = """
        SELECT stream_url, filename
        FROM musicplayer.tracks
        WHERE id = %s
    """
    track = execute_query(query, (track_id,), fetch_one=True)

    if not track:
        raise HTTPException(status_code=404, detail="Track not found")

    stream_url = track["stream_url"]

    try:
        # Stream the file from MinIO
        response = requests.get(stream_url, stream=True, timeout=30)
        response.raise_for_status()

        # Return streaming response
        return StreamingResponse(
            response.iter_content(chunk_size=8192),
            media_type="audio/mpeg",
            headers={
                "Content-Disposition": f'inline; filename="{track["filename"]}"',
                "Accept-Ranges": "bytes",
                "Cache-Control": "public, max-age=3600"
            }
        )

    except requests.RequestException as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to stream audio: {str(e)}"
        )
