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
