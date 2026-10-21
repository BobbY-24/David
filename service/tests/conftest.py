import os

os.environ["DATABASE_URL"] = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+psycopg://david:david@127.0.0.1:5432/david_test",
)
os.environ["REDIS_DISPATCH"] = "0"
os.environ["SWEEP"] = "0"
os.environ["RETRY_BACKOFF_SECONDS"] = "0"
os.environ["QUEUE_CAP"] = "8"
os.environ["MAX_ATTEMPTS"] = "3"
os.environ.pop("DAVID_MASTER_KEY", None)
os.environ.pop("DAVID_API_TOKEN", None)

import pytest
from sqlalchemy import text

from david_lab.db import reset_engine, session_factory
from david_lab.service import init_db


@pytest.fixture(autouse=True)
def clean_jobs():
    reset_engine()
    init_db()
    session = session_factory()
    session.execute(text("DELETE FROM jobs"))
    session.execute(text("DELETE FROM agent_spec_versions"))
    session.execute(text("DELETE FROM company_profiles"))
    session.execute(text("DELETE FROM api_keys"))
    session.execute(text("DELETE FROM model_usage"))
    session.commit()
    session.close()
    yield
    reset_engine()
