#!/usr/bin/env bash
set -Eeuo pipefail

umask "${UMASK:-022}"

mkdir -p \
  /root/workspace \
  /root/tools/bin /root/tools/lib /root/tools/share \
  /root/.sv /root/.sv.run \
  /root/.local/bin /root/.local/lib /root/.local/share /root/.local/state \
  /root/.local/share/fnm /root/.local/share/pnpm \
  /root/.config /root/.codex \
  /root/.cache/npm /root/.cache/pip /root/.cache/uv \
  /root/.cache/node/corepack /root/.cache/ms-playwright \
  /root/.cargo /root/.rustup /root/go /root/.venvs \
  /nix

# Seed runtime-wide instructions into persistent HOME once. Image upgrades do
# not replace or merge the user's persistent instruction files.
for file in AGENTS.md CLAUDE.md; do
  src="/opt/agent-defaults/${file}"
  dst="/root/${file}"
  if [[ -f "${src}" && ! -e "${dst}" && ! -L "${dst}" ]]; then
    cp "${src}" "${dst}"
  fi
done

# Codex reads global guidance from $CODEX_HOME (normally /root/.codex), not
# directly from /root. Keep a single user-editable source of truth for both
# Codex and Claude Code.
if [[ ! -e /root/.codex/AGENTS.md && ! -L /root/.codex/AGENTS.md ]]; then
  ln -s ../AGENTS.md /root/.codex/AGENTS.md
fi

if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  ln -sf "$(command -v fdfind)" /root/.local/bin/fd
fi

if ! command -v python >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  ln -sf "$(command -v python3)" /root/.local/bin/python
fi

# /nix is separately bind-mounted and may be empty on first boot. Initialize
# daemonless/root Nix store metadata if needed; nix-bin lives in the image.
if command -v nix-store >/dev/null 2>&1 && [[ ! -d /nix/var/nix/db ]]; then
  mkdir -p /nix/store /nix/var/nix/{db,gcroots,profiles,temproots,userpool}
  nix-store --init >/dev/null 2>&1 || true
fi

cat >/root/.agent-runtime.sh <<'EOF_ENV'
export HOME=/root
export PATH="/root/.local/bin:/root/.cargo/bin:/root/go/bin:/root/tools/bin:/root/.local/share/pnpm:$PATH"

export XDG_CONFIG_HOME=/root/.config
export XDG_CACHE_HOME=/root/.cache
export XDG_DATA_HOME=/root/.local/share
export XDG_STATE_HOME=/root/.local/state

export UV_CACHE_DIR=/root/.cache/uv
export UV_TOOL_DIR=/root/.local/share/uv/tools
export UV_TOOL_BIN_DIR=/root/.local/bin
export PIP_CACHE_DIR=/root/.cache/pip

export FNM_DIR=/root/.local/share/fnm
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --shell bash --use-on-cd)"
fi

export NPM_CONFIG_PREFIX=/root/.local
export NPM_CONFIG_CACHE=/root/.cache/npm
export PNPM_HOME=/root/.local/share/pnpm
export COREPACK_HOME=/root/.cache/node/corepack
export PATH="$PNPM_HOME:$PATH"

export CARGO_HOME=/root/.cargo
export RUSTUP_HOME=/root/.rustup

export GOPATH=/root/go
export GOBIN=/root/.local/bin

export PLAYWRIGHT_BROWSERS_PATH=/root/.cache/ms-playwright
export HF_HOME=/root/.cache/huggingface

export LD_LIBRARY_PATH="/root/.local/lib:/root/tools/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="/root/.local/lib/pkgconfig:/root/tools/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
EOF_ENV

touch /root/.bashrc
if ! grep -qF 'source /root/.agent-runtime.sh' /root/.bashrc; then
  cat >>/root/.bashrc <<'EOF_BASHRC'

# Agent runtime persistent environment
if [ -f /root/.agent-runtime.sh ]; then
  source /root/.agent-runtime.sh
fi
EOF_BASHRC
fi

# Also make login shells inherit the same environment.
touch /root/.profile
if ! grep -qF 'source /root/.agent-runtime.sh' /root/.profile; then
  cat >>/root/.profile <<'EOF_PROFILE'

# Agent runtime persistent environment
if [ -f /root/.agent-runtime.sh ]; then
  source /root/.agent-runtime.sh
fi
EOF_PROFILE
fi

if [[ $# -eq 0 ]]; then
  set -- runsvdir /root/.sv.run
fi

exec "$@"
