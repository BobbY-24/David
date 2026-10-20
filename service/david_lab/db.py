from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .settings import database_url


class Base(DeclarativeBase):
    pass


_engine = None
Session = None


def get_engine():
    global _engine, Session
    if _engine is None:
        _engine = create_engine(database_url(), pool_pre_ping=True)
        Session = sessionmaker(bind=_engine, expire_on_commit=False)
    return _engine


def session_factory():
    get_engine()
    return Session()


def reset_engine() -> None:
    global _engine, Session
    if _engine is not None:
        _engine.dispose()
    _engine = None
    Session = None
