# Magic Hat — ABCI State Manager
# Copyright (c) 2026 George Scott Foley — MIT License
#
# SQLite-backed state storage for the Python ABCI application.
# CometBFT handles consensus; this module handles application state persistence.

from __future__ import annotations

import hashlib
import json
import sqlite3
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

DEFAULT_STATE_PATH = Path("/var/lib/magichat/chain/state.db")


@dataclass
class GenesisRegistration:
    """A registered Familiar genesis block on the L2 chain."""

    genesis_hash: str
    public_key: str  # PEM-encoded RSA public key
    owner_name: str
    metadata: dict[str, Any] = field(default_factory=dict)
    reputation: float = 0.0
    registered_at: float = 0.0
    status: str = "active"  # active, suspended, revoked


@dataclass
class DrossAccount:
    """Dross token balance for a genesis identity."""

    genesis_hash: str
    balance: int = 0  # microdross (1 dross = 10^6 microdross)
    total_minted: int = 0
    total_burned: int = 0
    total_spent: int = 0
    staked: int = 0
    last_activity: float = 0.0


@dataclass
class ProvenanceAnchor:
    """Merkle root anchored from a Familiar's local chain."""

    merkle_root: str
    genesis_hash: str  # which Familiar submitted this
    block_range_start: int = 0
    block_range_end: int = 0
    block_count: int = 0
    anchored_at: float = 0.0


class StateManager:
    """SQLite state manager for the ABCI application.

    All ABCI state lives here — genesis registry, Dross balances,
    provenance anchors, marketplace listings. CometBFT calls DeliverTx
    which routes to handlers which mutate state through this manager.
    """

    def __init__(self, db_path: Path | str = DEFAULT_STATE_PATH):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn: sqlite3.Connection | None = None
        self._app_hash: bytes = b""
        self._block_height: int = 0

    def connect(self) -> None:
        """Open database connection and initialize schema."""
        self._conn = sqlite3.connect(str(self.db_path))
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._create_tables()

    def close(self) -> None:
        """Close database connection."""
        if self._conn:
            self._conn.close()
            self._conn = None

    @property
    def conn(self) -> sqlite3.Connection:
        if self._conn is None:
            self.connect()
        assert self._conn is not None
        return self._conn

    @property
    def app_hash(self) -> bytes:
        """Current application state hash (returned to CometBFT on Commit)."""
        return self._app_hash

    @property
    def block_height(self) -> int:
        return self._block_height

    # ─── Schema ──────────────────────────────────────────────────────────

    def _create_tables(self) -> None:
        c = self.conn
        c.executescript("""
            CREATE TABLE IF NOT EXISTS genesis_registry (
                genesis_hash    TEXT PRIMARY KEY,
                public_key      TEXT NOT NULL,
                owner_name      TEXT NOT NULL,
                metadata        TEXT DEFAULT '{}',
                reputation      REAL DEFAULT 0.0,
                registered_at   REAL NOT NULL,
                status          TEXT DEFAULT 'active'
            );

            CREATE TABLE IF NOT EXISTS dross_accounts (
                genesis_hash    TEXT PRIMARY KEY,
                balance         INTEGER DEFAULT 0,
                total_minted    INTEGER DEFAULT 0,
                total_burned    INTEGER DEFAULT 0,
                total_spent     INTEGER DEFAULT 0,
                staked          INTEGER DEFAULT 0,
                last_activity   REAL DEFAULT 0.0,
                FOREIGN KEY (genesis_hash) REFERENCES genesis_registry(genesis_hash)
            );

            CREATE TABLE IF NOT EXISTS provenance_anchors (
                merkle_root     TEXT PRIMARY KEY,
                genesis_hash    TEXT NOT NULL,
                block_range_start INTEGER DEFAULT 0,
                block_range_end   INTEGER DEFAULT 0,
                block_count     INTEGER DEFAULT 0,
                anchored_at     REAL NOT NULL,
                FOREIGN KEY (genesis_hash) REFERENCES genesis_registry(genesis_hash)
            );

            CREATE TABLE IF NOT EXISTS dross_transactions (
                tx_id           TEXT PRIMARY KEY,
                tx_type         TEXT NOT NULL,
                from_hash       TEXT,
                to_hash         TEXT,
                amount          INTEGER NOT NULL,
                reason          TEXT DEFAULT '',
                block_height    INTEGER NOT NULL,
                timestamp       REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS chain_meta (
                key             TEXT PRIMARY KEY,
                value           TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_dross_tx_from
                ON dross_transactions(from_hash);
            CREATE INDEX IF NOT EXISTS idx_dross_tx_to
                ON dross_transactions(to_hash);
            CREATE INDEX IF NOT EXISTS idx_dross_tx_height
                ON dross_transactions(block_height);
            CREATE INDEX IF NOT EXISTS idx_provenance_genesis
                ON provenance_anchors(genesis_hash);
        """)
        c.commit()

    # ─── Genesis Registry ────────────────────────────────────────────────

    def register_genesis(self, reg: GenesisRegistration) -> bool:
        """Register a new genesis block. Returns False if already exists."""
        try:
            self.conn.execute(
                """INSERT INTO genesis_registry
                   (genesis_hash, public_key, owner_name, metadata, reputation, registered_at, status)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (
                    reg.genesis_hash,
                    reg.public_key,
                    reg.owner_name,
                    json.dumps(reg.metadata),
                    reg.reputation,
                    reg.registered_at or time.time(),
                    reg.status,
                ),
            )
            # Create corresponding Dross account
            self.conn.execute(
                "INSERT INTO dross_accounts (genesis_hash) VALUES (?)",
                (reg.genesis_hash,),
            )
            return True
        except sqlite3.IntegrityError:
            return False

    def get_genesis(self, genesis_hash: str) -> GenesisRegistration | None:
        """Look up a genesis registration by hash."""
        row = self.conn.execute(
            "SELECT * FROM genesis_registry WHERE genesis_hash = ?",
            (genesis_hash,),
        ).fetchone()
        if not row:
            return None
        return GenesisRegistration(
            genesis_hash=row["genesis_hash"],
            public_key=row["public_key"],
            owner_name=row["owner_name"],
            metadata=json.loads(row["metadata"]),
            reputation=row["reputation"],
            registered_at=row["registered_at"],
            status=row["status"],
        )

    def genesis_exists(self, genesis_hash: str) -> bool:
        row = self.conn.execute(
            "SELECT 1 FROM genesis_registry WHERE genesis_hash = ?",
            (genesis_hash,),
        ).fetchone()
        return row is not None

    # ─── Dross Accounts ──────────────────────────────────────────────────

    def get_balance(self, genesis_hash: str) -> int:
        """Get Dross balance in microdross."""
        row = self.conn.execute(
            "SELECT balance FROM dross_accounts WHERE genesis_hash = ?",
            (genesis_hash,),
        ).fetchone()
        return row["balance"] if row else 0

    def mint(self, genesis_hash: str, amount: int, reason: str = "") -> bool:
        """Mint Dross to an account. Amount in microdross."""
        if amount <= 0:
            return False
        now = time.time()
        self.conn.execute(
            """UPDATE dross_accounts
               SET balance = balance + ?, total_minted = total_minted + ?, last_activity = ?
               WHERE genesis_hash = ?""",
            (amount, amount, now, genesis_hash),
        )
        self._record_tx("mint", None, genesis_hash, amount, reason)
        return True

    def transfer(self, from_hash: str, to_hash: str, amount: int, reason: str = "") -> bool:
        """Transfer Dross between accounts. Returns False if insufficient balance."""
        balance = self.get_balance(from_hash)
        if balance < amount or amount <= 0:
            return False
        now = time.time()
        self.conn.execute(
            "UPDATE dross_accounts SET balance = balance - ?, total_spent = total_spent + ?, last_activity = ? WHERE genesis_hash = ?",
            (amount, amount, now, from_hash),
        )
        self.conn.execute(
            "UPDATE dross_accounts SET balance = balance + ?, last_activity = ? WHERE genesis_hash = ?",
            (amount, now, to_hash),
        )
        self._record_tx("transfer", from_hash, to_hash, amount, reason)
        return True

    def burn(self, genesis_hash: str, amount: int, reason: str = "") -> bool:
        """Burn Dross (destroy permanently). Returns False if insufficient balance."""
        balance = self.get_balance(genesis_hash)
        if balance < amount or amount <= 0:
            return False
        now = time.time()
        self.conn.execute(
            "UPDATE dross_accounts SET balance = balance - ?, total_burned = total_burned + ?, last_activity = ? WHERE genesis_hash = ?",
            (amount, amount, now, genesis_hash),
        )
        self._record_tx("burn", genesis_hash, None, amount, reason)
        return True

    def _record_tx(
        self, tx_type: str, from_hash: str | None, to_hash: str | None, amount: int, reason: str
    ) -> None:
        tx_id = hashlib.sha256(
            f"{tx_type}:{from_hash}:{to_hash}:{amount}:{time.time()}".encode()
        ).hexdigest()[:32]
        self.conn.execute(
            """INSERT INTO dross_transactions
               (tx_id, tx_type, from_hash, to_hash, amount, reason, block_height, timestamp)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (tx_id, tx_type, from_hash, to_hash, amount, reason, self._block_height, time.time()),
        )

    # ─── Provenance ──────────────────────────────────────────────────────

    def anchor_provenance(self, anchor: ProvenanceAnchor) -> bool:
        """Store a Merkle root anchor. Returns False if duplicate."""
        try:
            self.conn.execute(
                """INSERT INTO provenance_anchors
                   (merkle_root, genesis_hash, block_range_start, block_range_end, block_count, anchored_at)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (
                    anchor.merkle_root,
                    anchor.genesis_hash,
                    anchor.block_range_start,
                    anchor.block_range_end,
                    anchor.block_count,
                    anchor.anchored_at or time.time(),
                ),
            )
            return True
        except sqlite3.IntegrityError:
            return False

    def get_provenance(self, merkle_root: str) -> ProvenanceAnchor | None:
        row = self.conn.execute(
            "SELECT * FROM provenance_anchors WHERE merkle_root = ?",
            (merkle_root,),
        ).fetchone()
        if not row:
            return None
        return ProvenanceAnchor(
            merkle_root=row["merkle_root"],
            genesis_hash=row["genesis_hash"],
            block_range_start=row["block_range_start"],
            block_range_end=row["block_range_end"],
            block_count=row["block_count"],
            anchored_at=row["anchored_at"],
        )

    # ─── Block Lifecycle ─────────────────────────────────────────────────

    def begin_block(self, height: int) -> None:
        """Called at the start of each block."""
        self._block_height = height

    def commit(self) -> bytes:
        """Commit all pending state changes and return app hash.

        The app hash is returned to CometBFT and included in the next block
        header — this is how validators agree on application state.
        """
        self.conn.commit()

        # Compute app hash from state digest
        digest = hashlib.sha256()
        digest.update(f"height:{self._block_height}".encode())

        # Include latest transaction hashes
        rows = self.conn.execute(
            "SELECT tx_id FROM dross_transactions WHERE block_height = ? ORDER BY tx_id",
            (self._block_height,),
        ).fetchall()
        for row in rows:
            digest.update(row["tx_id"].encode())

        self._app_hash = digest.digest()

        # Persist height
        self.conn.execute(
            "INSERT OR REPLACE INTO chain_meta (key, value) VALUES ('block_height', ?)",
            (str(self._block_height),),
        )
        self.conn.commit()
        return self._app_hash

    # ─── Supply Statistics ───────────────────────────────────────────────

    def get_supply_stats(self) -> dict[str, int]:
        """Total supply statistics across all accounts."""
        row = self.conn.execute(
            """SELECT
                COALESCE(SUM(total_minted), 0) as total_minted,
                COALESCE(SUM(total_burned), 0) as total_burned,
                COALESCE(SUM(balance), 0) as circulating,
                COALESCE(SUM(staked), 0) as staked,
                COUNT(*) as accounts
            FROM dross_accounts"""
        ).fetchone()
        return {
            "total_minted": row["total_minted"],
            "total_burned": row["total_burned"],
            "circulating": row["circulating"],
            "staked": row["staked"],
            "accounts": row["accounts"],
        }
