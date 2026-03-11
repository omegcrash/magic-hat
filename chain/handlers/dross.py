# Magic Hat — Dross Token Handler (Sprint 5)
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Handles Dross token lifecycle: minting from usage, peer-to-peer transfers,
# marketplace burns, and validator staking.
#
# The minting formula is derived from the Gradient Enhancement Law (GEL):
#   η = η₀ · exp[K · (∇Φ/Φ₀)²]
# where K = -260/81 (from Platonic solid geometry, Paper 4, DOI 10.5281/zenodo.18382672)
#
# Current usage multipliers are empirical approximations of this formula.
# Future: governance can vote to adjust multipliers via GEL parameters.

from __future__ import annotations

import logging
import time
from typing import TYPE_CHECKING, Any

from chain.codec import Transaction, TxType
from chain.ipt import (
    MARKETPLACE_BURN_RATE,
    MICRODROSS_PER_DROSS,
    MINIMUM_DROSS,
    TREASURY_RATE,
    USAGE_MULTIPLIERS,
    VALIDATOR_STAKE_MINIMUM,
    gel_multiplier,
)
from chain.state import StateManager

if TYPE_CHECKING:
    from chain.app import DrossChainApp

logger = logging.getLogger("magichat.chain.dross")

# Treasury account — receives 5% of all minting
TREASURY_HASH = "treasury:magichat-1"


def _dross_to_microdross(dross: float) -> int:
    """Convert human-readable Dross to on-chain microdross."""
    return int(dross * MICRODROSS_PER_DROSS)


def handle_mint_from_usage(tx: Transaction, state: StateManager) -> dict:
    """Mint Dross based on verified usage records.

    Required payload:
        usage_type: str — key from USAGE_MULTIPLIERS
        quantity: int — number of units (default 1)
        evidence_hash: str — hash of the usage record (for auditability)

    Minting formula:
        base = USAGE_MULTIPLIERS[usage_type] × quantity
        treasury_cut = base × TREASURY_RATE
        minter_gets = base - treasury_cut

    All amounts are stored in microdross (1 dross = 10^6 microdross).
    """
    payload = tx.payload
    usage_type = payload.get("usage_type")
    quantity = payload.get("quantity", 1)
    evidence_hash = payload.get("evidence_hash", "")

    if not usage_type:
        return {"code": 20, "log": "Missing usage_type"}

    if usage_type not in USAGE_MULTIPLIERS:
        return {"code": 21, "log": f"Unknown usage_type: {usage_type}"}

    if quantity < 1:
        return {"code": 22, "log": "Quantity must be >= 1"}

    # Calculate Dross amount
    base_dross = USAGE_MULTIPLIERS[usage_type] * quantity
    base_dross = max(base_dross, MINIMUM_DROSS)

    # Treasury cut
    treasury_amount = _dross_to_microdross(base_dross * TREASURY_RATE)
    minter_amount = _dross_to_microdross(base_dross) - treasury_amount

    # Mint to sender
    state.mint(tx.sender, minter_amount, reason=f"usage:{usage_type}×{quantity}")

    # Mint treasury cut
    if treasury_amount > 0:
        # Ensure treasury account exists (bootstrap if needed)
        if not state.genesis_exists(TREASURY_HASH):
            from chain.state import GenesisRegistration

            state.register_genesis(
                GenesisRegistration(
                    genesis_hash=TREASURY_HASH,
                    public_key="",
                    owner_name="Community Treasury",
                    registered_at=time.time(),
                    status="system",
                )
            )
        state.mint(TREASURY_HASH, treasury_amount, reason=f"treasury:{usage_type}")

    logger.info(
        "Minted %d microdross to %s (usage: %s×%d, treasury: %d)",
        minter_amount,
        tx.sender[:16],
        usage_type,
        quantity,
        treasury_amount,
    )
    return {
        "code": 0,
        "log": f"Minted {minter_amount} microdross ({usage_type}×{quantity})",
    }


def handle_transfer(tx: Transaction, state: StateManager) -> dict:
    """Transfer Dross between accounts.

    Required payload:
        to: str — recipient genesis hash
        amount: int — amount in microdross
        memo: str — optional memo
    """
    payload = tx.payload
    to_hash = payload.get("to")
    amount = payload.get("amount", 0)

    if not to_hash:
        return {"code": 30, "log": "Missing recipient (to)"}
    if amount <= 0:
        return {"code": 31, "log": "Amount must be > 0"}
    if not state.genesis_exists(to_hash):
        return {"code": 32, "log": f"Unknown recipient: {to_hash}"}

    memo = payload.get("memo", "transfer")
    if not state.transfer(tx.sender, to_hash, amount, reason=memo):
        return {"code": 33, "log": "Insufficient balance"}

    logger.info("Transfer %d microdross: %s → %s", amount, tx.sender[:16], to_hash[:16])
    return {"code": 0, "log": f"Transferred {amount} microdross"}


def handle_burn(tx: Transaction, state: StateManager) -> dict:
    """Burn Dross (permanently destroy).

    Required payload:
        amount: int — amount in microdross
        reason: str — burn reason (e.g., "marketplace_fee")
    """
    amount = tx.payload.get("amount", 0)
    reason = tx.payload.get("reason", "burn")

    if amount <= 0:
        return {"code": 40, "log": "Amount must be > 0"}

    if not state.burn(tx.sender, amount, reason=reason):
        return {"code": 41, "log": "Insufficient balance"}

    logger.info("Burned %d microdross from %s (%s)", amount, tx.sender[:16], reason)
    return {"code": 0, "log": f"Burned {amount} microdross"}


def handle_stake(tx: Transaction, state: StateManager) -> dict:
    """Stake Dross for validator eligibility.

    Required payload:
        amount: int — amount in microdross to stake
    """
    amount = tx.payload.get("amount", 0)
    if amount <= 0:
        return {"code": 50, "log": "Amount must be > 0"}

    balance = state.get_balance(tx.sender)
    if balance < amount:
        return {"code": 51, "log": "Insufficient balance"}

    # Move from balance to staked
    state.conn.execute(
        "UPDATE dross_accounts SET balance = balance - ?, staked = staked + ? WHERE genesis_hash = ?",
        (amount, amount, tx.sender),
    )
    logger.info("Staked %d microdross by %s", amount, tx.sender[:16])
    return {"code": 0, "log": f"Staked {amount} microdross"}


def handle_query_balance(data: dict, state: StateManager) -> dict:
    """Query Dross balance for a genesis identity."""
    genesis_hash = data.get("genesis_hash")
    if not genesis_hash:
        return {"error": "genesis_hash required"}

    balance = state.get_balance(genesis_hash)
    return {
        "genesis_hash": genesis_hash,
        "balance": balance,
        "balance_dross": balance / MICRODROSS_PER_DROSS,
    }


def handle_query_supply(data: dict, state: StateManager) -> dict:
    """Query total Dross supply statistics."""
    stats = state.get_supply_stats()
    return {
        **stats,
        "total_minted_dross": stats["total_minted"] / MICRODROSS_PER_DROSS,
        "total_burned_dross": stats["total_burned"] / MICRODROSS_PER_DROSS,
        "circulating_dross": stats["circulating"] / MICRODROSS_PER_DROSS,
    }


def register_handlers(app: DrossChainApp) -> None:
    """Register all Dross token handlers with the ABCI app."""
    app.register_handler(TxType.MINT_FROM_USAGE, handle_mint_from_usage)
    app.register_handler(TxType.TRANSFER, handle_transfer)
    app.register_handler(TxType.BURN, handle_burn)
    app.register_handler(TxType.STAKE, handle_stake)
    app.register_query_handler("dross/balance", handle_query_balance)
    app.register_query_handler("dross/supply", handle_query_supply)
    logger.info("Dross token handlers registered")
