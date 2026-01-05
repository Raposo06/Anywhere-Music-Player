"""
Database connection and utilities for PostgreSQL.
"""
import os
import psycopg2
from psycopg2.extras import RealDictCursor
from contextlib import contextmanager
from typing import Generator

# Database configuration from environment
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "postgres")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_SCHEMA = os.getenv("DB_SCHEMA", "musicplayer")


def get_connection():
    """Get a database connection."""
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        cursor_factory=RealDictCursor
    )


@contextmanager
def get_db() -> Generator:
    """
    Context manager for database connections.

    Usage:
        with get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM tracks")
    """
    conn = get_connection()
    try:
        yield conn
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        conn.close()


def execute_query(query: str, params: tuple = None, fetch_one: bool = False):
    """
    Execute a query and return results.

    Args:
        query: SQL query string
        params: Query parameters
        fetch_one: If True, return single row. If False, return all rows.

    Returns:
        Query results as dict or list of dicts
    """
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(query, params)

        if fetch_one:
            return cursor.fetchone()
        return cursor.fetchall()


def execute_insert(query: str, params: tuple = None):
    """
    Execute an INSERT query and return the inserted row.

    Args:
        query: SQL INSERT query with RETURNING clause
        params: Query parameters

    Returns:
        Inserted row as dict
    """
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(query, params)
        return cursor.fetchone()
