-- ============================================================================
-- STEP 3: Tracks Table for Music Library
-- ============================================================================
-- This table stores metadata for all music files
--
-- Fields:
--   - title, artist, album: Extracted from MP3 ID3 tags
--   - filename: Original filename (unique constraint prevents duplicates)
--   - stream_url: Direct MinIO URL for streaming (e.g., https://minio.domain.com/anime-music/song.mp3)
--   - cover_art_url: MinIO URL for album art image
--   - duration_seconds: Song length for progress bars
--   - file_size_bytes: File size for storage tracking
-- ============================================================================

CREATE TABLE IF NOT EXISTS musicplayer.tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    artist TEXT DEFAULT 'Unknown',
    album TEXT,
    filename TEXT NOT NULL UNIQUE,
    stream_url TEXT NOT NULL,
    cover_art_url TEXT,
    duration_seconds INTEGER,
    file_size_bytes BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Indexes for fast sorting and filtering
CREATE INDEX IF NOT EXISTS idx_tracks_artist ON musicplayer.tracks(artist);
CREATE INDEX IF NOT EXISTS idx_tracks_title ON musicplayer.tracks(title);
CREATE INDEX IF NOT EXISTS idx_tracks_album ON musicplayer.tracks(album);
CREATE INDEX IF NOT EXISTS idx_tracks_created_at ON musicplayer.tracks(created_at DESC);

-- Full-text search index for searching across title and artist
CREATE INDEX IF NOT EXISTS idx_tracks_search ON musicplayer.tracks
    USING gin(to_tsvector('english', title || ' ' || artist || ' ' || COALESCE(album, '')));

-- Add comments for documentation
COMMENT ON TABLE musicplayer.tracks IS 'Music library metadata - populated by Python upload script';
COMMENT ON COLUMN musicplayer.tracks.stream_url IS 'Direct MinIO URL for streaming audio';
COMMENT ON COLUMN musicplayer.tracks.cover_art_url IS 'MinIO URL for album cover image (extracted from MP3)';
COMMENT ON COLUMN musicplayer.tracks.duration_seconds IS 'Song duration in seconds for UI progress bars';
