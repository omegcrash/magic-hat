#!/usr/bin/env bash
# Magic Hat — GPU Detection & Driver Setup
# Copyright (c) 2026 George Scott Foley — MIT License
#
# Auto-detects NVIDIA/AMD GPUs and installs appropriate drivers.
# Called by install.sh and first-boot wizard.
# Usage: sudo ./detect-gpu.sh [--install] [--json]

set -euo pipefail

# ── GPU Detection ─────────────────────────────────────────────────────────────

GPU_VENDOR="none"
GPU_MODEL=""
GPU_PCI_ID=""
GPU_VRAM_MB=0
DRIVER_STATUS="not_installed"
CUDA_VERSION=""
ROCM_VERSION=""

detect_gpu() {
    # NVIDIA: PCI vendor 10de
    if lspci -nn 2>/dev/null | grep -i '\[10de:' | grep -qi 'vga\|3d\|display'; then
        GPU_VENDOR="nvidia"
        GPU_MODEL=$(lspci 2>/dev/null | grep -i nvidia | grep -i 'vga\|3d\|display' | head -1 | sed 's/.*: //')
        GPU_PCI_ID=$(lspci -nn 2>/dev/null | grep -i '\[10de:' | grep -qi 'vga\|3d\|display' && \
            lspci -nn | grep -i '\[10de:' | grep -i 'vga\|3d\|display' | head -1 | grep -oP '\[10de:\K[0-9a-f]+' || echo "")

        # Check VRAM via nvidia-smi if driver is loaded
        if command -v nvidia-smi &>/dev/null; then
            DRIVER_STATUS="installed"
            GPU_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ' || echo "0")
            CUDA_VERSION=$(nvidia-smi 2>/dev/null | grep -oP 'CUDA Version: \K[0-9.]+' || echo "")
        fi

    # AMD: PCI vendor 1002
    elif lspci -nn 2>/dev/null | grep -i '\[1002:' | grep -qi 'vga\|3d\|display'; then
        GPU_VENDOR="amd"
        GPU_MODEL=$(lspci 2>/dev/null | grep -i 'amd\|radeon\|ati' | grep -i 'vga\|3d\|display' | head -1 | sed 's/.*: //')
        GPU_PCI_ID=$(lspci -nn 2>/dev/null | grep -i '\[1002:' | grep -i 'vga\|3d\|display' | head -1 | grep -oP '\[1002:\K[0-9a-f]+' || echo "")

        # Check ROCm
        if command -v rocminfo &>/dev/null; then
            DRIVER_STATUS="installed"
            ROCM_VERSION=$(rocminfo 2>/dev/null | grep -oP 'ROCm Runtime Version: \K.*' || echo "")
        elif command -v clinfo &>/dev/null; then
            DRIVER_STATUS="partial"
        fi
    fi
}

# ── NVIDIA Driver Installation ────────────────────────────────────────────────

install_nvidia() {
    echo "[GPU] Installing NVIDIA drivers and container toolkit..."

    # Disable nouveau (open-source driver conflicts with proprietary)
    if ! grep -q "blacklist nouveau" /etc/modprobe.d/blacklist-nouveau.conf 2>/dev/null; then
        cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
        dracut --force 2>/dev/null || true
    fi

    # Add NVIDIA CUDA repo (Fedora)
    if [[ ! -f /etc/yum.repos.d/cuda-fedora.repo ]]; then
        local fedora_version
        fedora_version=$(rpm -E %fedora)
        dnf config-manager addrepo \
            --from-repofile="https://developer.download.nvidia.com/compute/cuda/repos/fedora${fedora_version}/x86_64/cuda-fedora${fedora_version}.repo" \
            2>/dev/null || true
    fi

    # Install driver + CUDA toolkit
    dnf install -y \
        akmod-nvidia \
        xorg-x11-drv-nvidia-cuda \
        nvidia-container-toolkit \
        2>/dev/null || {
            echo "[GPU] WARN: Could not install from NVIDIA repo, trying RPM Fusion..."
            dnf install -y \
                https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
                2>/dev/null || true
            dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda 2>/dev/null || true
        }

    # Configure nvidia-container-toolkit for Podman (rootless)
    if command -v nvidia-ctk &>/dev/null; then
        nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml 2>/dev/null || true
        echo "[GPU] NVIDIA CDI config generated for Podman"
    fi

    # Wait for akmod to build kernel module
    echo "[GPU] Building kernel module (this may take a few minutes)..."
    akmods --force 2>/dev/null || true

    echo "[GPU] NVIDIA driver installation complete"
    echo "[GPU] A reboot is recommended to load the new kernel module"
}

# ── AMD Driver Installation ───────────────────────────────────────────────────

install_amd() {
    echo "[GPU] Installing AMD ROCm drivers..."

    # Add ROCm repo
    if [[ ! -f /etc/yum.repos.d/rocm.repo ]]; then
        cat > /etc/yum.repos.d/rocm.repo << 'EOF'
[rocm]
name=ROCm
baseurl=https://repo.radeon.com/rocm/rhel9/latest/main
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
EOF
    fi

    # Install ROCm runtime (not full dev stack — just what Ollama needs)
    dnf install -y \
        rocm-hip-runtime \
        rocm-opencl-runtime \
        2>/dev/null || {
            echo "[GPU] WARN: ROCm repo not available for this Fedora version"
            echo "[GPU] AMD GPU detected but driver install skipped"
            return 1
        }

    # Add magichat user to render + video groups
    usermod -aG render,video magichat 2>/dev/null || true

    echo "[GPU] AMD ROCm installation complete"
}

# ── Recommended Model Selection ───────────────────────────────────────────────
# Based on VRAM, suggest the best default model for Ollama.

recommend_model() {
    local vram=${GPU_VRAM_MB:-0}

    if [[ ${vram} -ge 24000 ]]; then
        echo "qwen3:32b"       # 24GB+ (RTX 4090, A100)
    elif [[ ${vram} -ge 12000 ]]; then
        echo "qwen3:14b"       # 12-24GB (RTX 4070 Ti, 3080)
    elif [[ ${vram} -ge 8000 ]]; then
        echo "qwen3:8b"        # 8-12GB (RTX 4060, 3070)
    elif [[ ${vram} -ge 4000 ]]; then
        echo "llama3.2:3b"     # 4-8GB (GTX 1650, RX 580)
    elif [[ ${vram} -ge 2000 ]]; then
        echo "qwen2.5:1.5b"   # 2-4GB (minimal GPU)
    elif [[ "${GPU_VENDOR}" == "none" ]]; then
        echo "qwen2.5:1.5b"   # CPU-only: smallest capable model
    else
        echo "llama3.2:3b"     # Unknown VRAM: safe default
    fi
}

# ── JSON Output ───────────────────────────────────────────────────────────────

output_json() {
    local recommended
    recommended=$(recommend_model)
    cat << EOF
{
    "gpu_vendor": "${GPU_VENDOR}",
    "gpu_model": "${GPU_MODEL}",
    "gpu_pci_id": "${GPU_PCI_ID}",
    "gpu_vram_mb": ${GPU_VRAM_MB},
    "driver_status": "${DRIVER_STATUS}",
    "cuda_version": "${CUDA_VERSION}",
    "rocm_version": "${ROCM_VERSION}",
    "recommended_model": "${recommended}"
}
EOF
}

# ── Human-Readable Output ─────────────────────────────────────────────────────

output_human() {
    echo "──────────────────────────────────────"
    echo "  Magic Hat — GPU Detection Report"
    echo "──────────────────────────────────────"

    if [[ "${GPU_VENDOR}" == "none" ]]; then
        echo "  GPU:       None detected (CPU-only mode)"
        echo "  Driver:    N/A"
    else
        echo "  GPU:       ${GPU_MODEL}"
        echo "  Vendor:    ${GPU_VENDOR^^}"
        echo "  PCI ID:    ${GPU_PCI_ID}"
        echo "  VRAM:      ${GPU_VRAM_MB} MB"
        echo "  Driver:    ${DRIVER_STATUS}"
        [[ -n "${CUDA_VERSION}" ]] && echo "  CUDA:      ${CUDA_VERSION}"
        [[ -n "${ROCM_VERSION}" ]] && echo "  ROCm:      ${ROCM_VERSION}"
    fi

    echo ""
    echo "  Recommended model: $(recommend_model)"
    echo "──────────────────────────────────────"
}

# ── Main ──────────────────────────────────────────────────────────────────────

detect_gpu

case "${1:-}" in
    --install)
        output_human
        echo ""
        if [[ "${GPU_VENDOR}" == "nvidia" && "${DRIVER_STATUS}" != "installed" ]]; then
            install_nvidia
        elif [[ "${GPU_VENDOR}" == "amd" && "${DRIVER_STATUS}" != "installed" ]]; then
            install_amd
        elif [[ "${DRIVER_STATUS}" == "installed" ]]; then
            echo "[GPU] Drivers already installed — nothing to do"
        else
            echo "[GPU] No GPU detected — Ollama will use CPU mode"
        fi
        ;;
    --json)
        output_json
        ;;
    *)
        output_human
        ;;
esac
