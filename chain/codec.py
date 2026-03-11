# Magic Hat — Transaction Codec
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Defines transaction types and serialization for the ABCI application.
# Transactions are JSON-encoded, signed by the sender's genesis block key.

from __future__ import annotations

import hashlib
import json
import time
from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any


class TxType(str, Enum):
    """All transaction types supported by the Dross Chain."""

    # Genesis registry (Sprint 4)
    REGISTER_GENESIS = "register_genesis"

    # Dross token (Sprint 5)
    MINT_FROM_USAGE = "mint_from_usage"
    TRANSFER = "transfer"
    BURN = "burn"
    STAKE = "stake"
    UNSTAKE = "unstake"

    # Provenance (Sprint 6)
    ANCHOR_MERKLE_ROOT = "anchor_merkle_root"

    # Marketplace (Sprint 7)
    PUBLISH_SKILL = "publish_skill"
    PURCHASE_SKILL = "purchase_skill"
    RATE_SKILL = "rate_skill"
    UPDATE_SKILL = "update_skill"

    # Licensing (Sprint 8)
    ISSUE_LICENSE = "issue_license"
    REVOKE_LICENSE = "revoke_license"

    # Governance (Sprint 13)
    CREATE_PROPOSAL = "create_proposal"
    CAST_VOTE = "cast_vote"


@dataclass
class Transaction:
    """A signed transaction submitted to the Dross Chain.

    Transactions are created by Familiars (L1), signed with their genesis
    block RSA key, and submitted to a Magic Hat validator via REST gateway.
    CometBFT broadcasts them to all validators; the ABCI app processes them.
    """

    tx_type: str
    sender: str  # genesis block hash of the sender
    payload: dict[str, Any] = field(default_factory=dict)
    signature: str = ""  # RSA signature of (tx_type + sender + payload + nonce)
    nonce: int = 0  # replay protection
    timestamp: float = field(default_factory=time.time)

    @property
    def tx_hash(self) -> str:
        """Deterministic hash of this transaction (excludes signature)."""
        content = json.dumps(
            {
                "tx_type": self.tx_type,
                "sender": self.sender,
                "payload": self.payload,
                "nonce": self.nonce,
                "timestamp": self.timestamp,
            },
            sort_keys=True,
        )
        return hashlib.sha256(content.encode()).hexdigest()

    def to_bytes(self) -> bytes:
        """Serialize for CometBFT broadcast."""
        return json.dumps(asdict(self), sort_keys=True).encode()

    @classmethod
    def from_bytes(cls, data: bytes) -> Transaction:
        """Deserialize from CometBFT delivery."""
        d = json.loads(data)
        return cls(**d)

    def signing_payload(self) -> bytes:
        """The bytes that must be signed by the sender's RSA key."""
        content = json.dumps(
            {
                "tx_type": self.tx_type,
                "sender": self.sender,
                "payload": self.payload,
                "nonce": self.nonce,
                "timestamp": self.timestamp,
            },
            sort_keys=True,
        )
        return content.encode()


@dataclass
class QueryRequest:
    """A query to the ABCI application (read-only, no consensus needed)."""

    path: str  # e.g. "genesis/lookup", "dross/balance", "provenance/verify"
    data: dict[str, Any] = field(default_factory=dict)

    def to_bytes(self) -> bytes:
        return json.dumps({"path": self.path, "data": self.data}).encode()

    @classmethod
    def from_bytes(cls, data: bytes) -> QueryRequest:
        d = json.loads(data)
        return cls(path=d["path"], data=d.get("data", {}))
