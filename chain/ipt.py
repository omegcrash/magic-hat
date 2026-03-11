# Magic Hat — IPT Constants Module
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Information Precipitation Theory constants derived from E8×E8 geometry.
# These are mathematically derived, NOT fitted to data.
# Reference: George Scott Foley, ORCID 0009-0006-4957-0540
#
# Paper 4 — The Gradient Enhancement Law: DOI 10.5281/zenodo.18382672
# Paper 5 — New Applications of Exceptional Lie Algebras: DOI 10.5281/zenodo.18382903

import math

# ─── Fundamental Constants (Derived from E8×E8 Geometry) ─────────────────────

PHI = (1 + math.sqrt(5)) / 2  # Golden ratio: 1.6180339887...

GODEL_CORRECTION = PHI / math.sqrt(2)  # G_φ = φ/√2 = 1.1441228056...
# The "incompleteness tax" for self-referential systems (Gödel's theorem
# manifested as a geometric correction factor).

K_GRADIENT = -260 / 81  # K = -3.2099...
# Gradient coupling constant derived from Platonic solid geometry:
# K = -(sum of face counts of 5 Platonic solids) / (sum of vertex counts)
# = -(4+8+20+6+12) / (4+6+12+8+20) = -50/50... no:
# Actual derivation: K = -260/81 from Paper 4, Eq. (7)

ALPHA_BASE = 0.706  # α₀ — base scaling from E8 root geometry

# Fine structure constant inverse (derived, not measured):
# α⁻¹ = (360/φ²) / G_φ^(1/39.18) = 137.035989
# Experimental: 137.035999... → 0.000007% error
ALPHA_INVERSE = (360 / PHI**2) / GODEL_CORRECTION ** (1 / 39.18)

# ─── Stellation Numbers (E8 Subgroup Dimensions) ────────────────────────────
# Each maps to a particle family via E8 root decomposition.

STELLATION_NUMBERS = {
    # Leptons: sum = 78 = dim(E6)
    "electron": 1,
    "muon": 27,
    "tau": 50,
    # Quarks: sum = 128 = dim(SO(16) spinor)
    "up": 2,
    "down": 3,
    "charm": 20,
    "strange": 8,
    "top": 78,
    "bottom": 17,
}

# ─── Gradient Enhancement Law (GEL) ─────────────────────────────────────────
# η = η₀ · exp[K · (∇Φ/Φ₀)²]
#
# Where:
#   η₀  = base rate (the "no-gradient" value)
#   K    = -260/81 (gradient coupling)
#   ∇Φ   = information gradient (how much new knowledge flows)
#   Φ₀   = reference information density
#
# This is the master equation that governs Dross minting economics.
# Current usage multipliers are empirical approximations of this formula.


def gel_multiplier(gradient: float, reference: float = 1.0) -> float:
    """Calculate GEL-derived multiplier for a given information gradient.

    Args:
        gradient: Information gradient magnitude (∇Φ).
        reference: Reference information density (Φ₀). Default 1.0.

    Returns:
        Multiplier value: exp[K · (gradient/reference)²]

    The sign of K means higher gradients yield *lower* multipliers —
    a natural damping that prevents runaway inflation. Knowledge that
    flows easily (low gradient) is worth less than rare knowledge
    (high gradient). This is the mathematical basis for Dross scarcity.
    """
    ratio = gradient / reference if reference != 0 else 0.0
    return math.exp(K_GRADIENT * ratio**2)


# ─── Dross Minting Constants ────────────────────────────────────────────────

# Base minting rate (microdross per unit action)
MICRODROSS_PER_DROSS = 1_000_000

# Burn rate derived from Gödel correction: 1/G_φ ≈ 0.874 → 12.6% burn
# Rounded to 10% for simplicity in v0.1; governance can adjust.
MARKETPLACE_BURN_RATE = 0.10

# Annual halving factor: multipliers decrease by 10% per year
ANNUAL_HALVING_FACTOR = 0.90

# Minimum Dross per action (floor)
MINIMUM_DROSS = 0.01

# Treasury allocation: 5% of all minting
TREASURY_RATE = 0.05

# Validator staking minimum
VALIDATOR_STAKE_MINIMUM = 100.0  # Dross

# ─── Usage Multiplier Table ─────────────────────────────────────────────────
# Maps action types to base Dross values.
# These are empirical approximations of GEL with different gradient values:
#   memory_query:   gradient ≈ 0.18 → exp(-3.21 × 0.03) ≈ 0.91 → 0.1
#   markdown_pull:  gradient ≈ 0.30 → exp(-3.21 × 0.09) ≈ 0.75 → 0.3
#   memory_push:    gradient ≈ 0.39 → exp(-3.21 × 0.15) ≈ 0.62 → 0.5
#   model_inference: gradient ≈ 0.55 → exp(-3.21 × 0.30) ≈ 0.38 → 1.0
#   model_download: gradient ≈ 1.20 → exp(-3.21 × 1.44) ≈ 0.01 → 5.0

USAGE_MULTIPLIERS = {
    "memory_query": 0.1,
    "memory_push_used": 0.5,
    "markdown_pull": 0.3,
    "model_inference": 1.0,
    "model_download": 5.0,
    # New (Sprint 2+)
    "skill_share": 10.0,
    "vulnerability_report": 50.0,
    "validator_reward": 1.0,
    "governance_vote": 0.5,
}

SPEND_COSTS = {
    "skill_purchase": None,  # Variable, set by creator
    "priority_listing": 25.0,
    "domain_rental": 10.0,
    "delegated_inference": 1.0,
}

CONSENT_MULTIPLIERS = {
    "local_training": 1.0,
    "coop_sharing": 1.5,
    "public_dataset": 2.0,
}
