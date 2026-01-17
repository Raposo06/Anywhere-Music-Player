"""
Tracks endpoints: list, search, and folder management.
"""
from fastapi import APIRouter, Depends, Query, HTTPException, Request
from fastapi.responses import StreamingResponse
from typing import List, Optional
import os
import requests
from models import TrackResponse, FolderResponse
from auth import get_current_user
from database import execute_query

router = APIRouter(prefix="/tracks", tags=["Tracks"])


def _use_direct_minio() -> bool:
    """Check if direct MinIO URLs should be used (bypasses proxy for better seeking)."""
    return os.getenv("USE_DIRECT_MINIO_URLS", "false").lower() == "true"


def _build_stream_url(track_id: str, original_url: str = None) -> str:
    """Build streaming URL for a track.

    If USE_DIRECT_MINIO_URLS is true and original_url is provided,
    returns the direct MinIO URL for better seeking performance.
    Otherwise returns the proxy endpoint URL.
    """
    if _use_direct_minio() and original_url:
        return original_url
    api_base = os.getenv("API_BASE_URL", "http://localhost:8000")
    return f"{api_base}/tracks/{track_id}/stream"


@router.get("", response_model=List[TrackResponse])
def get_tracks(
    current_user: dict = Depends(get_current_user),
    folder_path: Optional[str] = Query(None, description="Filter by folder path"),
    parent_folder: Optional[str] = Query(None, description="Filter by parent folder (includes subfolders)"),
    limit: int = Query(10000, description="Maximum number of tracks to return"),
    offset: int = Query(0, description="Number of tracks to skip")
):
    """
    Get all tracks with optional filtering.

    Requires authentication (JWT token in Authorization header).

    Args:
        current_user: Authenticated user (from JWT token)
        folder_path: Exact folder path filter
        parent_folder: Parent folder filter (includes all subfolders)
        limit: Maximum tracks to return (default 10000)
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
            ORDER BY title ASC
            LIMIT %s OFFSET %s
        """
        params = (folder_path, limit, offset)
    elif parent_folder:
        # Get all tracks in parent folder and its subfolders
        query = """
            SELECT id, title, filename, stream_url, cover_art_url,
                   folder_path, duration_seconds, file_size_bytes, created_at
            FROM musicplayer.tracks
            WHERE folder_path = %s OR folder_path LIKE %s
            ORDER BY folder_path ASC, title ASC
            LIMIT %s OFFSET %s
        """
        parent_pattern = f"{parent_folder}/%"
        params = (parent_folder, parent_pattern, limit, offset)
        print(f"🔍 parent_folder query: folder_path='{parent_folder}' OR folder_path LIKE '{parent_pattern}'")
    else:
        query = """
            SELECT id, title, filename, stream_url, cover_art_url,
                   folder_path, duration_seconds, file_size_bytes, created_at
            FROM musicplayer.tracks
            ORDER BY title ASC
            LIMIT %s OFFSET %s
        """
        params = (limit, offset)

    tracks = execute_query(query, params)
    print(f"✅ Query returned {len(tracks)} tracks")

    # Replace stream_url with proxy endpoint (or keep direct MinIO URL if configured)
    for track in tracks:
        track["stream_url"] = _build_stream_url(track["id"], track.get("stream_url"))

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

    # Replace stream_url with proxy endpoint (or keep direct MinIO URL if configured)
    for track in tracks:
        track["stream_url"] = _build_stream_url(track["id"], track.get("stream_url"))

    return [TrackResponse(**track) for track in tracks]


@router.get("/folders", response_model=List[FolderResponse])
def get_folders(
    current_user: dict = Depends(get_current_user),
    parent_path: Optional[str] = Query(None, description="Parent folder path to get children from")
):
    """
    Get folders with hierarchical support.

    - Without parent_path: Returns only top-level parent folders
      (extracts first segment: "Tekken/Tekken 2" -> "Tekken")
    - With parent_path="Tekken": Returns direct children like "Tekken/Tekken 2"

    Requires authentication (JWT token in Authorization header).

    Args:
        current_user: Authenticated user (from JWT token)
        parent_path: Optional parent folder to get children from

    Returns:
        List of folders with track counts (includes all nested tracks)
    """
    if parent_path is None:
        # Get top-level parent folders by extracting first segment
        # "Tekken/Tekken 2/Stage 1" -> "Tekken"
        # Also count ALL tracks in that parent and its subfolders
        query = """
            SELECT
                CASE
                    WHEN folder_path LIKE '%/%' THEN SPLIT_PART(folder_path, '/', 1)
                    ELSE folder_path
                END as folder_path,
                COUNT(*) as track_count
            FROM musicplayer.tracks
            WHERE folder_path != ''
            GROUP BY
                CASE
                    WHEN folder_path LIKE '%/%' THEN SPLIT_PART(folder_path, '/', 1)
                    ELSE folder_path
                END
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


@router.get("/root-tracks", response_model=List[TrackResponse])
def get_root_tracks(
    current_user: dict = Depends(get_current_user)
):
    """
    Get tracks that are in the root folder (empty folder_path).

    These are songs not organized into any folder.
    """
    query = """
        SELECT id, title, filename, stream_url, cover_art_url,
               folder_path, duration_seconds, file_size_bytes, created_at
        FROM musicplayer.tracks
        WHERE folder_path = '' OR folder_path IS NULL
        ORDER BY title ASC
    """
    tracks = execute_query(query)

    for track in tracks:
        track["stream_url"] = _build_stream_url(track["id"], track.get("stream_url"))

    return [TrackResponse(**track) for track in tracks]


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

    # Replace stream_url with proxy endpoint (or keep direct MinIO URL if configured)
    track["stream_url"] = _build_stream_url(track["id"], track.get("stream_url"))

    return TrackResponse(**track)


def _get_content_type(filename: str) -> str:
    """Get the appropriate content type based on file extension."""
    ext = filename.lower().split('.')[-1] if '.' in filename else ''
    content_types = {
        'mp3': 'audio/mpeg',
        'm4a': 'audio/mp4',
        'aac': 'audio/aac',
        'ogg': 'audio/ogg',
        'opus': 'audio/opus',
        'flac': 'audio/flac',
        'wav': 'audio/wav',
        'wma': 'audio/x-ms-wma',
    }
    return content_types.get(ext, 'audio/mpeg')


@router.head("/{track_id}/stream")
def stream_track_head(track_id: str):
    """
    HEAD request for audio stream - returns metadata without body.

    This is used by audio players to get file size and content type
    before starting to stream. Critical for Windows Media Foundation.

    Args:
        track_id: Track UUID

    Returns:
        Response with headers only (no body)
    """
    from fastapi.responses import Response

    # Get track from database
    query = """
        SELECT filename, file_size_bytes
        FROM musicplayer.tracks
        WHERE id = %s
    """
    track = execute_query(query, (track_id,), fetch_one=True)

    if not track:
        raise HTTPException(status_code=404, detail="Track not found")

    filename = track["filename"]
    file_size = track.get("file_size_bytes")
    content_type = _get_content_type(filename)

    headers = {
        "Content-Type": content_type,
        "Accept-Ranges": "bytes",
        "Cache-Control": "public, max-age=3600",
        "Content-Disposition": f'inline; filename="{filename}"',
    }

    if file_size:
        headers["Content-Length"] = str(file_size)

    return Response(content=b"", headers=headers)


@router.get("/{track_id}/stream")
def stream_track(track_id: str, request: Request):
    """
    Stream audio file for a track.

    This endpoint proxies the audio file from MinIO storage, solving CORS issues.
    Supports HTTP Range requests for seeking.
    Public endpoint - no authentication required since MinIO bucket is public.

    Args:
        track_id: Track UUID
        request: FastAPI Request object for Range header

    Returns:
        Streaming audio file

    Raises:
        HTTPException 404: If track not found
        HTTPException 500: If streaming fails
    """
    # Get track from database (include file_size_bytes for Content-Length)
    query = """
        SELECT stream_url, filename, file_size_bytes
        FROM musicplayer.tracks
        WHERE id = %s
    """
    track = execute_query(query, (track_id,), fetch_one=True)

    if not track:
        raise HTTPException(status_code=404, detail="Track not found")

    stream_url = track["stream_url"]
    filename = track["filename"]
    file_size = track.get("file_size_bytes")

    # Determine content type based on file extension
    content_type = _get_content_type(filename)

    try:
        # Prepare headers for MinIO request (forward Range header if present)
        headers = {}
        range_header = request.headers.get("range")
        if range_header:
            headers["Range"] = range_header

        # Stream the file from MinIO with Range support
        # Use a session for connection pooling and keep-alive
        session = requests.Session()
        response = session.get(
            stream_url,
            headers=headers,
            stream=True,
            timeout=60  # Increased timeout for large files
        )
        response.raise_for_status()

        # Prepare response headers with proper content type
        response_headers = {
            "Content-Type": content_type,
            "Accept-Ranges": "bytes",
            "Cache-Control": "public, max-age=3600",
            "Content-Disposition": f'inline; filename="{filename}"',
            "Connection": "keep-alive",
        }

        # Forward Content-Length from MinIO, or use database value as fallback
        if "Content-Length" in response.headers:
            response_headers["Content-Length"] = response.headers["Content-Length"]
        elif file_size and not range_header:
            # Use stored file size for full requests (not range requests)
            response_headers["Content-Length"] = str(file_size)

        # Forward Content-Range for partial content responses
        if "Content-Range" in response.headers:
            response_headers["Content-Range"] = response.headers["Content-Range"]

        # Return streaming response with proper status code
        status_code = response.status_code  # 200 or 206 (partial content)

        # Use larger chunk size (64KB) for faster seeking and streaming
        return StreamingResponse(
            response.iter_content(chunk_size=65536),
            status_code=status_code,
            headers=response_headers,
        )

    except requests.RequestException as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to stream audio: {str(e)}"
        )
