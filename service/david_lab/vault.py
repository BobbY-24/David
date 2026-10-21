"""Encrypted store for the user's model API key.

Envelope encryption, entirely inside this service:

- Each secret gets its own random 256-bit data key (DEK).
- The DEK encrypts the secret with AES-256-GCM. The master key wraps the DEK
  with AES-256-GCM. Both use a fresh 96-bit nonce and bind the provider name
  as associated data, so a ciphertext cannot be moved to another provider.
- Postgres stores only ciphertext, the wrapped DEK, the nonces, the last four
  characters of the key, and a short id of the master key. Plaintext and the
  master key are never written to the database or the logs.
- The master key comes from `DAVID_MASTER_KEY` (base64, 32 bytes) or from
  `master.key` in `DAVID_DATA_DIR`, which is created with mode 0600 on first
  use. Losing it makes saved keys unreadable; the user enters the key again.

This protects the key in a database dump, a backup, or a copied volume. It does
not protect against someone who already controls this machine and its files.
"""

import base64
import hashlib
import os
import stat
from datetime import datetime, timezone
from pathlib import Path

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from sqlalchemy.orm import Session

from .db import session_factory
from .schema import ApiKey
from .settings import data_dir

_AAD_PREFIX = b"david-vault-v1|"
_NONCE_BYTES = 12


class VaultError(Exception):
    """Base class. Messages never contain a key."""


class VaultUnavailable(VaultError):
    """No usable master key can be loaded or created."""


class KeyMissing(VaultError):
    """No key is saved for this provider."""


class KeyUnreadable(VaultError):
    """A key is saved but cannot be decrypted (master key changed or data tampered)."""


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def _unb64(text: str) -> bytes:
    return base64.b64decode(text.encode("ascii"))


def _decode_master(raw: str, origin: str) -> bytes:
    try:
        key = base64.b64decode(raw.strip(), validate=True)
    except Exception as exc:  # noqa: BLE001 - never echo the value
        raise VaultUnavailable(f"The master key from {origin} is not valid base64.") from exc
    if len(key) != 32:
        raise VaultUnavailable(f"The master key from {origin} must decode to 32 bytes.")
    return key


def master_key_id(master: bytes) -> str:
    """A short public id so a wrong master key is detected without decrypting."""
    return hashlib.sha256(b"david-master-id|" + master).hexdigest()[:16]


def load_master_key(create: bool) -> bytes | None:
    """Return the master key, creating the key file when `create` is true."""
    raw = os.environ.get("DAVID_MASTER_KEY")
    if raw:
        return _decode_master(raw, "DAVID_MASTER_KEY")
    path = Path(data_dir()) / "master.key"
    if path.exists():
        mode = path.stat().st_mode
        if mode & (stat.S_IRWXG | stat.S_IRWXO):
            raise VaultUnavailable("master.key is readable by other users. Run chmod 600 on it.")
        return _decode_master(path.read_text(), "master.key")
    if not create:
        return None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        os.chmod(path.parent, 0o700)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except OSError as exc:
        raise VaultUnavailable("The data directory is not writable, so a master key cannot be created.") from exc
    key = AESGCM.generate_key(bit_length=256)
    with os.fdopen(fd, "w") as handle:
        handle.write(_b64(key))
    return key


def _aad(provider: str) -> bytes:
    return _AAD_PREFIX + provider.encode("utf-8")


def seal(master: bytes, provider: str, secret: str) -> dict:
    """Encrypt `secret` under a fresh data key that is wrapped by `master`."""
    dek = AESGCM.generate_key(bit_length=256)
    dek_nonce = os.urandom(_NONCE_BYTES)
    nonce = os.urandom(_NONCE_BYTES)
    aad = _aad(provider)
    return {
        "wrapped_dek": _b64(AESGCM(master).encrypt(dek_nonce, dek, aad)),
        "dek_nonce": _b64(dek_nonce),
        "ciphertext": _b64(AESGCM(dek).encrypt(nonce, secret.encode("utf-8"), aad)),
        "nonce": _b64(nonce),
    }


def unseal(master: bytes, provider: str, record: dict) -> str:
    aad = _aad(provider)
    try:
        dek = AESGCM(master).decrypt(_unb64(record["dek_nonce"]), _unb64(record["wrapped_dek"]), aad)
        plain = AESGCM(dek).decrypt(_unb64(record["nonce"]), _unb64(record["ciphertext"]), aad)
    except (InvalidTag, ValueError) as exc:
        raise KeyUnreadable("The saved key cannot be decrypted. Enter it again.") from exc
    return plain.decode("utf-8")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Vault:
    """Reads and writes sealed keys. `master_key` is injectable for tests."""

    def __init__(self, factory=None, master_key: bytes | None = None) -> None:
        self._factory = factory or session_factory
        self._master = master_key

    def _master_key(self, create: bool) -> bytes | None:
        if self._master is None:
            self._master = load_master_key(create)
        return self._master

    def _session(self) -> Session:
        return self._factory()

    def readiness(self) -> dict:
        """Whether a key could be saved right now, without creating anything."""
        try:
            master = self._master_key(create=False)
        except VaultUnavailable as exc:
            return {"ready": False, "reason": str(exc)}
        if master is not None:
            return {"ready": True, "reason": None}
        directory = Path(data_dir())
        probe = directory if directory.exists() else directory.parent
        if os.access(probe, os.W_OK):
            return {"ready": True, "reason": None}
        return {"ready": False, "reason": "No master key is set and the data directory is not writable."}

    def put(self, provider: str, secret: str) -> dict:
        master = self._master_key(create=True)
        if master is None:
            raise VaultUnavailable("No master key is available.")
        sealed = seal(master, provider, secret)
        now = utcnow()
        session = self._session()
        try:
            row = session.get(ApiKey, provider)
            if row is None:
                row = ApiKey(provider=provider)
                session.add(row)
            row.key_id = master_key_id(master)
            row.wrapped_dek = sealed["wrapped_dek"]
            row.dek_nonce = sealed["dek_nonce"]
            row.ciphertext = sealed["ciphertext"]
            row.nonce = sealed["nonce"]
            row.last4 = secret[-4:]
            row.saved_at = now
            row.verified_at = None
            session.commit()
            return self._view(row, master)
        finally:
            session.close()

    def get(self, provider: str) -> str:
        session = self._session()
        try:
            row = session.get(ApiKey, provider)
            if row is None:
                raise KeyMissing("No key is saved for this provider.")
            master = self._master_key(create=False)
            if master is None or row.key_id != master_key_id(master):
                raise KeyUnreadable("The master key changed since this key was saved. Enter it again.")
            record = {
                "wrapped_dek": row.wrapped_dek,
                "dek_nonce": row.dek_nonce,
                "ciphertext": row.ciphertext,
                "nonce": row.nonce,
            }
        finally:
            session.close()
        return unseal(master, provider, record)

    def mark_verified(self, provider: str) -> None:
        session = self._session()
        try:
            row = session.get(ApiKey, provider)
            if row is not None:
                row.verified_at = utcnow()
                session.commit()
        finally:
            session.close()

    def delete(self, provider: str) -> bool:
        session = self._session()
        try:
            row = session.get(ApiKey, provider)
            if row is None:
                return False
            session.delete(row)
            session.commit()
            return True
        finally:
            session.close()

    def status(self, provider: str) -> dict:
        session = self._session()
        try:
            row = session.get(ApiKey, provider)
            if row is None:
                return {"provider": provider, "configured": False, "last4": None, "readable": True,
                        "saved_at": None, "verified_at": None}
            try:
                master = self._master_key(create=False)
            except VaultUnavailable:
                master = None
            return self._view(row, master)
        finally:
            session.close()

    @staticmethod
    def _view(row: ApiKey, master: bytes | None) -> dict:
        readable = master is not None and row.key_id == master_key_id(master)
        return {
            "provider": row.provider,
            "configured": True,
            "last4": row.last4,
            "readable": readable,
            "saved_at": row.saved_at.isoformat() if row.saved_at else None,
            "verified_at": row.verified_at.isoformat() if row.verified_at else None,
        }
