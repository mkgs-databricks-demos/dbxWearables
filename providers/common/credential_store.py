"""Python credential store for dbxWearables pull-based connectors.

Mirrors the TypeScript ``CredentialStore`` exported by the AppKit
``wearable-core`` plugin. Both implementations read the same Lakebase
``wearable_credentials`` table — the AppKit app writes tokens there
during OAuth, and this module reads them during the Lakeflow fanout job.

Usage in a Lakeflow notebook::

    from providers.common.credential_store import LakebaseCredentialStore

    store = LakebaseCredentialStore.from_env()
    for user_id, provider, provider_user_id in store.list_enrolled(provider="garmin"):
        creds = store.get(user_id, provider)
        # creds.access_token, creds.refresh_token, creds.token_expires_at

The default implementation talks to Lakebase over psycopg using the
caller's Databricks OAuth identity (same auth path the AppKit Lakebase
plugin uses). Customers who route secrets through Vault or a cloud KMS
can subclass ``CredentialStore`` and plug their own implementation into
``providers/<name>/pull/__init__.py``.
"""
from __future__ import annotations

import os
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from typing import Iterable


@dataclass
class WearableCredentials:
    user_id: str
    provider: str
    provider_user_id: str
    access_token: str
    refresh_token: str | None
    token_expires_at: datetime | None
    scopes: list[str]


@dataclass
class EnrolledUser:
    user_id: str
    provider: str
    provider_user_id: str


class CredentialStore(ABC):
    """Abstract interface. Provider plugins depend on this, not the concrete impl."""

    @abstractmethod
    def get(self, user_id: str, provider: str) -> WearableCredentials:
        ...

    @abstractmethod
    def put(self, creds: WearableCredentials) -> None:
        ...

    @abstractmethod
    def revoke(self, user_id: str, provider: str) -> None:
        ...

    @abstractmethod
    def list_enrolled(self, provider: str | None = None) -> Iterable[EnrolledUser]:
        ...


class LakebaseCredentialStore(CredentialStore):
    """Reads/writes ``wearable_credentials`` in Lakebase via psycopg.

    Token columns are stored encrypted (``access_token_encrypted``,
    ``refresh_token_encrypted``) and decrypted here using an envelope key
    fetched from a Databricks secret (default scope/key is provided by the
    ``wearable-core`` AppKit plugin at deploy time and shared via the
    secret scope the infra bundle provisions).
    """

    def __init__(
        self,
        *,
        pghost: str,
        pgdatabase: str,
        pguser: str,
        pgpassword: str,
        pgport: int = 5432,
        pgsslmode: str = "require",
        signing_key: bytes | None = None,
    ) -> None:
        self.pghost = pghost
        self.pgdatabase = pgdatabase
        self.pguser = pguser
        self.pgpassword = pgpassword
        self.pgport = pgport
        self.pgsslmode = pgsslmode
        self.signing_key = signing_key
        self._conn = None

    @classmethod
    def from_env(cls) -> "LakebaseCredentialStore":
        """Construct from PG* + LAKEBASE_SIGNING_KEY env vars.

        These env vars are injected automatically by the Databricks Apps
        ``postgres`` resource at runtime and can be forwarded to a Lakeflow
        job via job parameters or cluster env. See
        ``lakeflow/wearable_daily_fanout.ipynb`` for the notebook wiring.
        """
        missing = [
            name for name in ("PGHOST", "PGDATABASE", "PGUSER", "PGPASSWORD")
            if not os.environ.get(name)
        ]
        if missing:
            raise RuntimeError(
                f"LakebaseCredentialStore.from_env() missing env vars: {missing}. "
                "Wire them via the Lakeflow job parameters (see wearable_daily_fanout.ipynb)."
            )
        signing_key_hex = os.environ.get("LAKEBASE_SIGNING_KEY", "")
        return cls(
            pghost=os.environ["PGHOST"],
            pgdatabase=os.environ["PGDATABASE"],
            pguser=os.environ["PGUSER"],
            pgpassword=os.environ["PGPASSWORD"],
            pgport=int(os.environ.get("PGPORT", "5432")),
            pgsslmode=os.environ.get("PGSSLMODE", "require"),
            signing_key=bytes.fromhex(signing_key_hex) if signing_key_hex else None,
        )

    def _connect(self):
        import psycopg  # deferred — only needed in notebook runtime

        if self._conn is None or self._conn.closed:
            self._conn = psycopg.connect(
                host=self.pghost,
                port=self.pgport,
                dbname=self.pgdatabase,
                user=self.pguser,
                password=self.pgpassword,
                sslmode=self.pgsslmode,
            )
        return self._conn

    def _decrypt(self, ciphertext: bytes) -> str:
        """Envelope-decrypt a stored token column.

        The TS ``wearable-core`` plugin encrypts tokens with AES-256-GCM
        using a per-row data key wrapped by ``signing_key``. This Python
        implementation mirrors that wire format so the two sides agree.

        Placeholder — the actual AES-GCM implementation is finalized in the
        TS bronzeWriter first, and this routine follows the same framing.
        """
        if self.signing_key is None:
            # Dev fallback: tokens were written raw. Document loudly.
            return ciphertext.decode("utf-8")
        raise NotImplementedError(
            "Envelope decryption not yet implemented. "
            "Follow the AES-GCM framing finalized in app/plugins/wearable-core/src/credentialStore.ts."
        )

    def _encrypt(self, plaintext: str) -> bytes:
        if self.signing_key is None:
            return plaintext.encode("utf-8")
        raise NotImplementedError(
            "Envelope encryption not yet implemented. "
            "Follow the AES-GCM framing finalized in app/plugins/wearable-core/src/credentialStore.ts."
        )

    def get(self, user_id: str, provider: str) -> WearableCredentials:
        conn = self._connect()
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT provider_user_id, access_token_encrypted, refresh_token_encrypted,
                       token_expires_at, scopes
                  FROM wearable_credentials
                 WHERE user_id = %s AND provider = %s AND revoked_at IS NULL
                """,
                (user_id, provider),
            )
            row = cur.fetchone()
        if row is None:
            raise KeyError(f"No active credentials for user={user_id} provider={provider}")
        provider_user_id, access_ct, refresh_ct, expires_at, scopes = row
        return WearableCredentials(
            user_id=user_id,
            provider=provider,
            provider_user_id=provider_user_id,
            access_token=self._decrypt(access_ct),
            refresh_token=self._decrypt(refresh_ct) if refresh_ct else None,
            token_expires_at=expires_at,
            scopes=list(scopes or []),
        )

    def put(self, creds: WearableCredentials) -> None:
        conn = self._connect()
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO wearable_credentials (
                    user_id, provider, provider_user_id,
                    access_token_encrypted, refresh_token_encrypted,
                    token_expires_at, scopes, revoked_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, NULL)
                ON CONFLICT (user_id, provider) DO UPDATE SET
                    provider_user_id = EXCLUDED.provider_user_id,
                    access_token_encrypted = EXCLUDED.access_token_encrypted,
                    refresh_token_encrypted = EXCLUDED.refresh_token_encrypted,
                    token_expires_at = EXCLUDED.token_expires_at,
                    scopes = EXCLUDED.scopes,
                    revoked_at = NULL
                """,
                (
                    creds.user_id,
                    creds.provider,
                    creds.provider_user_id,
                    self._encrypt(creds.access_token),
                    self._encrypt(creds.refresh_token) if creds.refresh_token else None,
                    creds.token_expires_at,
                    creds.scopes,
                ),
            )
        conn.commit()

    def revoke(self, user_id: str, provider: str) -> None:
        conn = self._connect()
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE wearable_credentials "
                "SET revoked_at = NOW() "
                "WHERE user_id = %s AND provider = %s AND revoked_at IS NULL",
                (user_id, provider),
            )
        conn.commit()

    def list_enrolled(self, provider: str | None = None) -> Iterable[EnrolledUser]:
        conn = self._connect()
        with conn.cursor() as cur:
            if provider is None:
                cur.execute(
                    "SELECT user_id, provider, provider_user_id "
                    "FROM wearable_credentials WHERE revoked_at IS NULL "
                    "ORDER BY provider, user_id"
                )
            else:
                cur.execute(
                    "SELECT user_id, provider, provider_user_id "
                    "FROM wearable_credentials WHERE revoked_at IS NULL AND provider = %s "
                    "ORDER BY user_id",
                    (provider,),
                )
            for user_id, prov, provider_user_id in cur.fetchall():
                yield EnrolledUser(
                    user_id=str(user_id),
                    provider=prov,
                    provider_user_id=provider_user_id,
                )
