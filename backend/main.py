"""
Anywhere Music Player - FastAPI Backend

A REST API for music streaming with JWT authentication.
Replaces PostgREST with a simpler, more flexible architecture.
"""
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Import routers
from routers import auth_router, tracks_router

# Create FastAPI app
app = FastAPI(
    title="Anywhere Music Player API",
    description="REST API for self-hosted music streaming",
    version="1.0.0",
    docs_url="/docs",  # Swagger UI at /docs
    redoc_url="/redoc"  # ReDoc at /redoc
)

# CORS Configuration
# Allow requests from your Flutter app (web and mobile)
origins = os.getenv("CORS_ORIGINS", "*").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,  # In production, specify your domains
    allow_credentials=True,
    allow_methods=["*"],  # Allow all HTTP methods
    allow_headers=["*"],  # Allow all headers
)

# Include routers
app.include_router(auth_router.router)
app.include_router(tracks_router.router)


# Health check endpoint for Coolify
@app.get("/health", tags=["Health"])
def health_check():
    """
    Simple health check endpoint for Coolify/monitoring.
    """
    return {"status": "ok"}


# Root endpoint
@app.get("/", tags=["Health"])
def root():
    """
    API health check endpoint.

    Returns basic API information and status.
    """
    return {
        "name": "Anywhere Music Player API",
        "version": "1.0.0",
        "status": "running",
        "docs": "/docs",
        "endpoints": {
            "auth": {
                "signup": "POST /auth/signup",
                "login": "POST /auth/login"
            },
            "tracks": {
                "list": "GET /tracks",
                "search": "GET /tracks/search?query=...",
                "folders": "GET /tracks/folders",
                "get_by_id": "GET /tracks/{track_id}"
            }
        }
    }


# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """
    Catch-all exception handler for better error messages.
    """
    return JSONResponse(
        status_code=500,
        content={
            "detail": str(exc),
            "type": type(exc).__name__
        }
    )


# Startup event
@app.on_event("startup")
async def startup_event():
    """
    Run on application startup.
    """
    print("=" * 50)
    print("🎵 Anywhere Music Player API")
    print("=" * 50)
    print(f"✅ API running on port {os.getenv('PORT', '8000')}")
    print(f"✅ Database: {os.getenv('DB_HOST', 'localhost')}:{os.getenv('DB_PORT', '5432')}")
    print(f"✅ Schema: {os.getenv('DB_SCHEMA', 'musicplayer')}")
    print(f"📚 Docs: http://localhost:{os.getenv('PORT', '8000')}/docs")
    print("=" * 50)


# Shutdown event
@app.on_event("shutdown")
async def shutdown_event():
    """
    Run on application shutdown.
    """
    print("\n👋 Shutting down Anywhere Music Player API...")


if __name__ == "__main__":
    import uvicorn

    # Run the app
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        reload=True  # Auto-reload on code changes (development only)
    )
