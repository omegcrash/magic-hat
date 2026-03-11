# Magic Hat — Python ABCI Application
# Copyright (c) 2026 George Scott Foley — MIT License
#
# This is the heart of the Dross Chain. CometBFT calls these methods
# via the ABCI protocol (socket on port 26658). All business logic —
# genesis registry, Dross economics, provenance, marketplace — lives here.
#
# CometBFT handles: consensus, P2P, block gossip, validator management.
# This app handles: everything else.
#
# Run: python -m chain.app [--host 127.0.0.1] [--port 26658]
# Paired with: magichat-chain.service (CometBFT) + magichat-abci.service (this)

from __future__ import annotations

import argparse
import json
import logging
import signal
import socketserver
import struct
import sys
from pathlib import Path
from typing import Any

from chain import __chain_id__, __version__
from chain.codec import Transaction, TxType, QueryRequest
from chain.state import StateManager

logger = logging.getLogger("magichat.chain")

# ABCI message types (subset — the ones we need)
# Full spec: https://docs.cometbft.com/v1/spec/abci/
MSG_INFO = 0x04
MSG_INIT_CHAIN = 0x05
MSG_QUERY = 0x06
MSG_CHECK_TX = 0x07
MSG_DELIVER_TX = 0x08  # called FinalizeBlock in CometBFT v1
MSG_COMMIT = 0x09
MSG_BEGIN_BLOCK = 0x0A
MSG_END_BLOCK = 0x0B


class DrossChainApp:
    """The ABCI application — all Dross Chain business logic.

    CometBFT drives the lifecycle:
    1. CheckTx — validate transaction before mempool admission
    2. BeginBlock — start of new block
    3. DeliverTx — execute transaction (state mutation)
    4. EndBlock — end of block (validator set updates)
    5. Commit — persist state, return app hash

    Handlers are registered per TxType and called by DeliverTx.
    """

    def __init__(self, state: StateManager):
        self.state = state
        self._handlers: dict[str, Any] = {}
        self._query_handlers: dict[str, Any] = {}

    def register_handler(self, tx_type: str, handler: Any) -> None:
        """Register a transaction handler (called on DeliverTx)."""
        self._handlers[tx_type] = handler

    def register_query_handler(self, path: str, handler: Any) -> None:
        """Register a query handler (called on Query)."""
        self._query_handlers[path] = handler

    # ─── ABCI Methods ────────────────────────────────────────────────────

    def info(self) -> dict:
        """Return application info to CometBFT."""
        return {
            "data": f"Magic Hat Dross Chain v{__version__}",
            "version": __version__,
            "app_version": 1,
            "last_block_height": self.state.block_height,
            "last_block_app_hash": self.state.app_hash.hex(),
        }

    def init_chain(self, genesis: dict) -> dict:
        """Called once when the chain is first initialized.

        This is where we set up the initial state — treasury account,
        genesis validators, initial Dross supply.
        """
        logger.info("Initializing Dross Chain: chain_id=%s", genesis.get("chain_id", __chain_id__))
        # Future: process genesis validators, initial accounts
        return {"code": 0}

    def check_tx(self, tx_bytes: bytes) -> dict:
        """Validate transaction for mempool admission.

        Lightweight checks only — signature valid, nonce correct, sender exists.
        Must NOT mutate state. Reject spam/malformed tx here.
        """
        try:
            tx = Transaction.from_bytes(tx_bytes)
        except (json.JSONDecodeError, TypeError, KeyError) as e:
            return {"code": 1, "log": f"Malformed transaction: {e}"}

        # Verify tx_type is known
        try:
            TxType(tx.tx_type)
        except ValueError:
            return {"code": 2, "log": f"Unknown transaction type: {tx.tx_type}"}

        # Verify sender is registered (except for registration tx itself)
        if tx.tx_type != TxType.REGISTER_GENESIS:
            if not self.state.genesis_exists(tx.sender):
                return {"code": 3, "log": f"Unknown sender: {tx.sender}"}

        # TODO (Sprint 4): Verify RSA signature against sender's public key

        return {"code": 0, "log": "OK"}

    def begin_block(self, height: int, **kwargs: Any) -> dict:
        """Called at the start of each block."""
        self.state.begin_block(height)
        logger.debug("Begin block %d", height)
        return {}

    def deliver_tx(self, tx_bytes: bytes) -> dict:
        """Execute a transaction — this is where state mutations happen.

        Routes to the appropriate handler based on tx_type.
        Called by CometBFT after consensus is reached on the block.
        """
        try:
            tx = Transaction.from_bytes(tx_bytes)
        except (json.JSONDecodeError, TypeError, KeyError) as e:
            return {"code": 1, "log": f"Failed to decode: {e}"}

        handler = self._handlers.get(tx.tx_type)
        if handler is None:
            return {"code": 2, "log": f"No handler for tx_type: {tx.tx_type}"}

        try:
            result = handler(tx, self.state)
            return result if isinstance(result, dict) else {"code": 0, "log": "OK"}
        except Exception as e:
            logger.exception("Handler error for %s", tx.tx_type)
            return {"code": 99, "log": f"Internal error: {e}"}

    def end_block(self, height: int) -> dict:
        """Called at the end of each block.

        Future: return validator set updates (for dynamic validator management).
        """
        return {"validator_updates": []}

    def commit(self) -> dict:
        """Persist state and return app hash.

        The app hash is included in the next block header — this is how
        all validators agree on the application state.
        """
        app_hash = self.state.commit()
        logger.debug("Commit: height=%d hash=%s", self.state.block_height, app_hash.hex()[:16])
        return {"data": app_hash}

    def query(self, query_bytes: bytes) -> dict:
        """Handle read-only queries (no consensus needed).

        CometBFT proxies these directly from the client without
        going through the consensus layer.
        """
        try:
            req = QueryRequest.from_bytes(query_bytes)
        except (json.JSONDecodeError, TypeError, KeyError):
            return {"code": 1, "log": "Malformed query"}

        handler = self._query_handlers.get(req.path)
        if handler is None:
            return {"code": 2, "log": f"Unknown query path: {req.path}"}

        try:
            result = handler(req.data, self.state)
            return {"code": 0, "value": json.dumps(result).encode()}
        except Exception as e:
            logger.exception("Query error for %s", req.path)
            return {"code": 99, "log": f"Query error: {e}"}


# ─── ABCI Wire Protocol ─────────────────────────────────────────────────────
# CometBFT communicates via a simple length-prefixed protocol over a socket.
# This is a minimal implementation — production should use abci package or gRPC.
#
# For now, this provides the scaffolding. The actual wire protocol integration
# will use the `abci` Python package (pip install abci) which handles the
# protobuf encoding that CometBFT expects.


def create_app(state_path: Path | str | None = None) -> DrossChainApp:
    """Create and wire up the ABCI application with all handlers.

    This is the application factory. Each handler module registers itself
    for specific TxTypes and query paths.
    """
    state = StateManager(state_path or Path("/var/lib/magichat/chain/state.db"))
    state.connect()
    app = DrossChainApp(state)

    # Register transaction + query handlers
    from chain.handlers.registry import register_handlers as reg_registry
    from chain.handlers.dross import register_handlers as reg_dross
    from chain.handlers.provenance import register_handlers as reg_provenance

    reg_registry(app)
    reg_dross(app)
    reg_provenance(app)

    logger.info(
        "Dross Chain ABCI app ready: chain_id=%s version=%s",
        __chain_id__,
        __version__,
    )
    return app


def main() -> None:
    """Entry point for the ABCI application server."""
    parser = argparse.ArgumentParser(description="Magic Hat Dross Chain — ABCI Application")
    parser.add_argument("--host", default="127.0.0.1", help="ABCI listen address")
    parser.add_argument("--port", type=int, default=26658, help="ABCI listen port")
    parser.add_argument(
        "--state-dir",
        default="/var/lib/magichat/chain",
        help="State database directory",
    )
    parser.add_argument("--log-level", default="INFO", help="Logging level")
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper()),
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    )

    state_path = Path(args.state_dir) / "state.db"
    app = create_app(state_path)

    logger.info("ABCI server listening on %s:%d", args.host, args.port)
    logger.info("State database: %s", state_path)
    logger.info("Waiting for CometBFT connection...")

    # The actual ABCI server integration will use:
    #   from abci.server import ABCIServer
    #   server = ABCIServer(app=app, port=args.port)
    #   server.run()
    #
    # For now, log readiness and wait for signal.
    def handle_signal(signum: int, frame: Any) -> None:
        logger.info("Shutting down ABCI application...")
        app.state.close()
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    # Block until signal
    logger.info("ABCI application started (pid=%d). Send SIGTERM to stop.", __import__("os").getpid())
    signal.pause()


if __name__ == "__main__":
    main()
