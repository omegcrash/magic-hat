# Magic Hat — Genesis Registry Handler (Sprint 4)
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Handles Familiar genesis block registration on the L2 chain.
# A Familiar's genesis block is its identity — 5 patent-protected components
# (hardware fingerprint, cryptographic identity, behavioral baseline,
# network position, temporal markers). Registration makes it discoverable
# and enables reputation aggregation.

from __future__ import annotations

import json
import logging
import time
from typing import TYPE_CHECKING, Any

from chain.codec import Transaction, TxType
from chain.state import GenesisRegistration, StateManager

if TYPE_CHECKING:
    from chain.app import DrossChainApp

logger = logging.getLogger("magichat.chain.registry")


def handle_register_genesis(tx: Transaction, state: StateManager) -> dict:
    """Register a Familiar's genesis block on the L2 chain.

    Required payload fields:
        genesis_hash: str — SHA-256 hash of the genesis block
        public_key: str — PEM-encoded RSA-2048 public key
        owner_name: str — human-readable owner identifier
        metadata: dict — optional metadata (version, job_class, capabilities)

    The genesis_hash in the payload must match tx.sender (you register yourself).
    """
    payload = tx.payload

    # Validate required fields
    for field in ("genesis_hash", "public_key", "owner_name"):
        if field not in payload:
            return {"code": 10, "log": f"Missing required field: {field}"}

    # Sender must be registering their own genesis block
    if payload["genesis_hash"] != tx.sender:
        return {"code": 11, "log": "Cannot register genesis block for another identity"}

    # Check for duplicate
    if state.genesis_exists(payload["genesis_hash"]):
        return {"code": 12, "log": "Genesis block already registered"}

    # TODO: Verify RSA signature proves ownership of the public key
    # TODO: Anti-spam — require minimum Dross stake

    reg = GenesisRegistration(
        genesis_hash=payload["genesis_hash"],
        public_key=payload["public_key"],
        owner_name=payload["owner_name"],
        metadata=payload.get("metadata", {}),
        registered_at=time.time(),
    )

    if not state.register_genesis(reg):
        return {"code": 13, "log": "Registration failed (integrity error)"}

    logger.info("Genesis registered: %s (%s)", reg.genesis_hash[:16], reg.owner_name)
    return {"code": 0, "log": f"Registered: {reg.genesis_hash[:16]}"}


def handle_query_genesis(data: dict, state: StateManager) -> dict:
    """Look up a genesis registration.

    Query data: {"genesis_hash": "..."} or {"owner_name": "..."}
    """
    genesis_hash = data.get("genesis_hash")
    if not genesis_hash:
        return {"error": "genesis_hash required"}

    reg = state.get_genesis(genesis_hash)
    if not reg:
        return {"error": "Not found", "genesis_hash": genesis_hash}

    return {
        "genesis_hash": reg.genesis_hash,
        "owner_name": reg.owner_name,
        "reputation": reg.reputation,
        "registered_at": reg.registered_at,
        "status": reg.status,
        "metadata": reg.metadata,
    }


def handle_query_reputation(data: dict, state: StateManager) -> dict:
    """Query reputation for a genesis identity.

    Reputation is aggregated from: marketplace activity, validator
    participation, skill ratings, governance participation.
    """
    genesis_hash = data.get("genesis_hash")
    if not genesis_hash:
        return {"error": "genesis_hash required"}

    reg = state.get_genesis(genesis_hash)
    if not reg:
        return {"error": "Not found"}

    return {
        "genesis_hash": genesis_hash,
        "reputation": reg.reputation,
        "status": reg.status,
    }


def register_handlers(app: DrossChainApp) -> None:
    """Register all genesis registry handlers with the ABCI app."""
    app.register_handler(TxType.REGISTER_GENESIS, handle_register_genesis)
    app.register_query_handler("genesis/lookup", handle_query_genesis)
    app.register_query_handler("genesis/reputation", handle_query_reputation)
    logger.info("Genesis registry handlers registered")
