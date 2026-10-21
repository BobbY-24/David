import os


def database_url() -> str:
    return os.environ.get(
        "DATABASE_URL",
        "postgresql+psycopg://david:david@127.0.0.1:5432/david",
    )


def redis_url() -> str:
    return os.environ.get("REDIS_URL", "redis://127.0.0.1:6379/0")


def queue_cap() -> int:
    return int(os.environ.get("QUEUE_CAP", "32"))


def max_attempts() -> int:
    return int(os.environ.get("MAX_ATTEMPTS", "3"))


def lease_seconds() -> int:
    return int(os.environ.get("LEASE_SECONDS", "30"))


def retry_backoff_seconds() -> float:
    return float(os.environ.get("RETRY_BACKOFF_SECONDS", "0.25"))


def sweep_enabled() -> bool:
    return os.environ.get("SWEEP", "1") != "0"


def cors_origins() -> list[str]:
    """Browser origins allowed to call the API. The desk dev server by default."""
    raw = os.environ.get(
        "CORS_ORIGINS",
        "http://127.0.0.1:43123,http://localhost:43123",
    )
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


def data_dir() -> str:
    """Where the master key file lives when DAVID_MASTER_KEY is not set."""
    return os.environ.get("DAVID_DATA_DIR") or os.path.join(os.path.expanduser("~"), ".david")


def api_token() -> str | None:
    """Optional shared secret for the vault and model routes (X-David-Token)."""
    return os.environ.get("DAVID_API_TOKEN") or None


def model_calls_per_day() -> int:
    """Hard cap on model calls per UTC day through the user's key."""
    return int(os.environ.get("DAVID_MAX_MODEL_CALLS_PER_DAY", "100"))
