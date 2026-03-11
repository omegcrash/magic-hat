# Magic Hat — ABCI Transaction Handlers
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Each handler module registers itself for specific TxTypes.
# Pattern: register_handlers(app) → app.register_handler(TxType.X, handler_func)
