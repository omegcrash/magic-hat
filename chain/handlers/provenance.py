# Magic Hat — Provenance Aggregator Handler (Sprint 6)
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Handles Merkle root anchoring from Familiar local chains (L1 → L2).
# Each Familiar batches its local chain blocks, computes a Merkle root,
# and submits it here for network-wide consensus.
#
# This creates an immutable audit trail:
#   - Training data provenance (who contributed what)
#   - Model lineage (which data trained which model)
#   - Artwork provenance (creation, modification, watermarking)
#   - Consent records (GDPR/CCPA compliance)
#
# C2PA 2.2 compliance: provenance records can generate C2PA credentials
# for EU AI Act Article 50 (enforcement August 2026).

from __future__ import annotations

import logging
import time
from typing import TYPE_CHECKING, Any

from chain.codec import Transaction, TxType
from chain.state import ProvenanceAnchor, StateManager

if TYPE_CHECKING:
    from chain.app import DrossChainApp

logger = logging.getLogger("magichat.chain.provenance")


def handle_anchor_merkle_root(tx: Transaction, state: StateManager) -> dict:
    """Anchor a Merkle root from a Familiar's local chain.

    Required payload:
        merkle_root: str — SHA-256 Merkle root of the batch
        block_range_start: int — first local block index in this batch
        block_range_end: int — last local block index in this batch
        block_count: int — number of blocks in this batch

    The sender's genesis_hash identifies which Familiar submitted this anchor.
    """
    payload = tx.payload
    merkle_root = payload.get("merkle_root")

    if not merkle_root:
        return {"code": 60, "log": "Missing merkle_root"}

    block_range_start = payload.get("block_range_start", 0)
    block_range_end = payload.get("block_range_end", 0)
    block_count = payload.get("block_count", 0)

    if block_range_end < block_range_start:
        return {"code": 61, "log": "Invalid block range"}

    anchor = ProvenanceAnchor(
        merkle_root=merkle_root,
        genesis_hash=tx.sender,
        block_range_start=block_range_start,
        block_range_end=block_range_end,
        block_count=block_count,
        anchored_at=time.time(),
    )

    if not state.anchor_provenance(anchor):
        return {"code": 62, "log": "Merkle root already anchored"}

    logger.info(
        "Anchored merkle root %s from %s (blocks %d-%d)",
        merkle_root[:16],
        tx.sender[:16],
        block_range_start,
        block_range_end,
    )
    return {
        "code": 0,
        "log": f"Anchored: {merkle_root[:16]} ({block_count} blocks)",
    }


def handle_query_provenance(data: dict, state: StateManager) -> dict:
    """Look up provenance anchors.

    Query data: {"merkle_root": "..."} or {"genesis_hash": "..."}
    """
    merkle_root = data.get("merkle_root")
    if merkle_root:
        anchor = state.get_provenance(merkle_root)
        if not anchor:
            return {"error": "Not found", "merkle_root": merkle_root}
        return {
            "merkle_root": anchor.merkle_root,
            "genesis_hash": anchor.genesis_hash,
            "block_range_start": anchor.block_range_start,
            "block_range_end": anchor.block_range_end,
            "block_count": anchor.block_count,
            "anchored_at": anchor.anchored_at,
        }

    genesis_hash = data.get("genesis_hash")
    if genesis_hash:
        rows = state.conn.execute(
            "SELECT * FROM provenance_anchors WHERE genesis_hash = ? ORDER BY anchored_at DESC LIMIT 100",
            (genesis_hash,),
        ).fetchall()
        return {
            "genesis_hash": genesis_hash,
            "anchors": [
                {
                    "merkle_root": r["merkle_root"],
                    "block_range_start": r["block_range_start"],
                    "block_range_end": r["block_range_end"],
                    "block_count": r["block_count"],
                    "anchored_at": r["anchored_at"],
                }
                for r in rows
            ],
        }

    return {"error": "Provide merkle_root or genesis_hash"}


def handle_query_verify_inclusion(data: dict, state: StateManager) -> dict:
    """Verify that a block hash is included in an anchored Merkle root.

    Query data:
        merkle_root: str — the anchored root
        leaf_hash: str — the block hash to verify
        proof: list[dict] — Merkle inclusion proof [{hash, position}, ...]

    Uses the same verification logic as Familiar's MerkleTree.verify_proof().
    """
    merkle_root = data.get("merkle_root")
    leaf_hash = data.get("leaf_hash")
    proof = data.get("proof")

    if not all([merkle_root, leaf_hash, proof]):
        return {"error": "merkle_root, leaf_hash, and proof required"}

    # Verify the anchor exists on-chain
    anchor = state.get_provenance(merkle_root)
    if not anchor:
        return {"verified": False, "reason": "Merkle root not anchored"}

    # Verify the inclusion proof
    import hashlib

    current = leaf_hash
    for step in proof:
        sibling = step.get("hash", "")
        position = step.get("position", "right")
        if position == "left":
            combined = sibling + current
        else:
            combined = current + sibling
        current = hashlib.sha256(combined.encode()).hexdigest()

    verified = current == merkle_root
    return {
        "verified": verified,
        "merkle_root": merkle_root,
        "leaf_hash": leaf_hash,
        "genesis_hash": anchor.genesis_hash,
        "anchored_at": anchor.anchored_at,
    }


def register_handlers(app: DrossChainApp) -> None:
    """Register all provenance handlers with the ABCI app."""
    app.register_handler(TxType.ANCHOR_MERKLE_ROOT, handle_anchor_merkle_root)
    app.register_query_handler("provenance/lookup", handle_query_provenance)
    app.register_query_handler("provenance/verify", handle_query_verify_inclusion)
    logger.info("Provenance handlers registered")
