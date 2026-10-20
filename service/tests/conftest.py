import os

os.environ["DATABASE_URL"] = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+psycopg://fieldline:fieldline@127.0.0.1:5432/fieldline_test",
)
os.environ["REDIS_DISPATCH"] = "0"
os.environ["SWEEP"] = "0"
os.environ["RETRY_BACKOFF_SECONDS"] = "0"
os.environ["QUEUE_CAP"] = "8"
os.environ["MAX_ATTEMPTS"] = "3"

import pytest
from sqlalchemy import text

from fieldline_lab.db import reset_engine, session_factory
from fieldline_lab.service import init_db


@pytest.fixture(autouse=True)
def clean_jobs():
    reset_engine()
    init_db()
    session = session_factory()
    session.execute(text("DELETE FROM jobs"))
    session.commit()
    session.close()
    yield
    reset_engine()
