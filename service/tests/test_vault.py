import base64
import os
import stat

import pytest
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from sqlalchemy import text

from david_lab import vault as vault_module
from david_lab.db import session_factory
from david_lab.vault import KeyMissing, KeyUnreadable, Vault, VaultUnavailable, seal, unseal

SECRET = "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789"


def master() -> bytes:
    return AESGCM.generate_key(bit_length=256)


def test_seal_roundtrips_and_never_contains_the_plaintext():
    key = master()
    record = seal(key, "anthropic", SECRET)
    assert SECRET not in "".join(record.values())
    assert unseal(key, "anthropic", record) == SECRET


def test_every_seal_uses_a_fresh_data_key_and_nonces():
    key = master()
    first = seal(key, "anthropic", SECRET)
    second = seal(key, "anthropic", SECRET)
    assert first["ciphertext"] != second["ciphertext"]
    assert first["wrapped_dek"] != second["wrapped_dek"]
    assert first["nonce"] != second["nonce"]


def test_a_sealed_key_cannot_be_moved_to_another_provider():
    key = master()
    record = seal(key, "anthropic", SECRET)
    with pytest.raises(KeyUnreadable):
        unseal(key, "other-provider", record)


def test_tampering_or_the_wrong_master_key_is_detected():
    key = master()
    record = seal(key, "anthropic", SECRET)
    flipped = dict(record, ciphertext=base64.b64encode(b"x" * 40).decode())
    with pytest.raises(KeyUnreadable):
        unseal(key, "anthropic", flipped)
    with pytest.raises(KeyUnreadable):
        unseal(master(), "anthropic", record)


def test_the_database_holds_ciphertext_only():
    vault = Vault(master_key=master())
    view = vault.put("anthropic", SECRET)
    assert view["last4"] == SECRET[-4:]
    assert SECRET not in str(view)
    session = session_factory()
    try:
        rows = session.execute(text("SELECT * FROM api_keys")).all()
    finally:
        session.close()
    assert len(rows) == 1
    assert SECRET not in str(rows[0])
    assert SECRET[:-4] not in str(rows[0])
    assert vault.get("anthropic") == SECRET


def test_status_get_and_delete():
    vault = Vault(master_key=master())
    assert vault.status("anthropic")["configured"] is False
    with pytest.raises(KeyMissing):
        vault.get("anthropic")
    vault.put("anthropic", SECRET)
    vault.mark_verified("anthropic")
    status = vault.status("anthropic")
    assert status["configured"] and status["readable"] and status["verified_at"]
    assert vault.delete("anthropic") is True
    assert vault.delete("anthropic") is False
    assert vault.status("anthropic")["configured"] is False


def test_replacing_a_key_clears_its_verification():
    vault = Vault(master_key=master())
    vault.put("anthropic", SECRET)
    vault.mark_verified("anthropic")
    vault.put("anthropic", SECRET[:-4] + "ZZZZ")
    status = vault.status("anthropic")
    assert status["verified_at"] is None
    assert status["last4"] == "ZZZZ"


def test_a_changed_master_key_makes_the_saved_key_unreadable_not_a_crash():
    Vault(master_key=master()).put("anthropic", SECRET)
    other = Vault(master_key=master())
    assert other.status("anthropic")["readable"] is False
    with pytest.raises(KeyUnreadable):
        other.get("anthropic")


def test_master_key_file_is_created_private(tmp_path, monkeypatch):
    monkeypatch.setenv("DAVID_DATA_DIR", str(tmp_path / "data"))
    key = vault_module.load_master_key(create=True)
    path = tmp_path / "data" / "master.key"
    assert len(key) == 32
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert vault_module.load_master_key(create=False) == key


def test_a_group_readable_master_key_file_is_refused(tmp_path, monkeypatch):
    monkeypatch.setenv("DAVID_DATA_DIR", str(tmp_path))
    vault_module.load_master_key(create=True)
    os.chmod(tmp_path / "master.key", 0o640)
    with pytest.raises(VaultUnavailable):
        vault_module.load_master_key(create=False)


def test_the_environment_master_key_wins_and_is_validated(tmp_path, monkeypatch):
    monkeypatch.setenv("DAVID_DATA_DIR", str(tmp_path))
    good = master()
    monkeypatch.setenv("DAVID_MASTER_KEY", base64.b64encode(good).decode())
    assert vault_module.load_master_key(create=False) == good
    monkeypatch.setenv("DAVID_MASTER_KEY", "not base64 !!")
    with pytest.raises(VaultUnavailable) as caught:
        vault_module.load_master_key(create=False)
    assert "not base64" not in str(caught.value)
    monkeypatch.setenv("DAVID_MASTER_KEY", base64.b64encode(b"short").decode())
    with pytest.raises(VaultUnavailable):
        vault_module.load_master_key(create=False)


def test_readiness_without_a_master_key_or_a_writable_directory(tmp_path, monkeypatch):
    locked = tmp_path / "locked"
    locked.mkdir()
    os.chmod(locked, 0o500)
    try:
        monkeypatch.setenv("DAVID_DATA_DIR", str(locked / "data"))
        result = Vault().readiness()
        if os.geteuid() != 0:
            assert result["ready"] is False
    finally:
        os.chmod(locked, 0o700)
    monkeypatch.setenv("DAVID_DATA_DIR", str(tmp_path / "fresh"))
    assert Vault().readiness()["ready"] is True
