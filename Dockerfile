ARG NODE_VERSION=24
ARG UBUNTU_VERSION=24.04

FROM node:${NODE_VERSION}-bookworm-slim AS node-base

FROM ubuntu:${UBUNTU_VERSION}

ARG DEBIAN_FRONTEND=noninteractive
ARG UV_VERSION=0.12.9
ARG FNM_VERSION=1.39.0
ARG COREPACK_VERSION=0.36.0

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Keep the immutable OS layer focused on high-frequency bootstrap capabilities.
# Project-specific SDKs/toolchains should be installed persistently under /root
# or through the persistent /nix store.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash bash-completion ca-certificates curl wget gnupg openssl \
      git git-lfs gh \
      ripgrep fd-find jq \
      gawk diffutils patch file tree less \
      tar gzip bzip2 xz-utils zstd zip unzip \
      openssh-client rsync \
      iproute2 iputils-ping dnsutils netcat-openbsd socat traceroute tcpdump \
      procps psmisc lsof strace \
      build-essential cmake ninja-build pkg-config \
      python3 python3-venv python3-pip \
      sqlite3 \
      tmux vim-tiny runit tzdata \
      nix-bin \
      fonts-liberation fonts-noto-cjk fonts-noto-color-emoji \
      libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 \
      libcairo2 libcairo-gobject2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 \
      libglib2.0-0t64 libnspr4 libnss3 libpango-1.0-0 libpangocairo-1.0-0 \
      libfontconfig1 libfreetype6 libgdk-pixbuf-2.0-0 libgtk-3-0t64 \
      libx11-6 libx11-xcb1 libxcb1 libxcb-shm0 libxcomposite1 libxcursor1 \
      libxdamage1 libxext6 libxfixes3 libxi6 libxkbcommon0 libxrandr2 libxrender1 \
      xdg-utils \
    && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    ln -sf /usr/bin/python3 /usr/local/bin/python

# Provide a supported baseline Node/npm directly from the official Node image.
# fnm remains available below for projects that need to select another version.
COPY --from=node-base /usr/local/bin/node /usr/local/bin/node
COPY --from=node-base /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    node --version && \
    npm --version

# Nix runs daemonless as root in this container. Docker remains the outer sandbox.
RUN mkdir -p /etc/nix && \
    printf '%s\n' \
      'experimental-features = nix-command flakes' \
      'sandbox = false' \
      > /etc/nix/nix.conf

# Pin bootstrap tools so rebuilding the same Dockerfile does not silently change them.
RUN curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | \
      env UV_UNMANAGED_INSTALL=/usr/local/bin sh && \
    uv --version

RUN curl -fsSL https://fnm.vercel.app/install | \
      bash -s -- --release "v${FNM_VERSION}" --install-dir /usr/local/bin --skip-shell && \
    fnm --version

# Corepack is explicit because modern Node distributions do not universally bundle it.
RUN npm install --global "corepack@${COREPACK_VERSION}" && \
    corepack enable --install-directory /usr/local/bin && \
    corepack --version

RUN mkdir -p \
      /root/workspace \
      /root/tools/bin /root/tools/lib /root/tools/share \
      /root/.sv /root/.sv.run \
      /root/.local/bin /root/.local/share /root/.local/state \
      /root/.config /root/.cache \
      /root/.cargo /root/.rustup /root/go \
      /root/.local/share/fnm \
      /root/.local/share/pnpm \
      /root/.cache/node/corepack \
      /root/.cache/ms-playwright \
      /root/.venvs \
      /nix \
      /opt/agent-defaults

# Bake default agent instructions into the published image. The entrypoint copies
# them into persistent /root only when the user has no persistent copy yet.
COPY AGENTS.md CLAUDE.md /opt/agent-defaults/
COPY agent-entrypoint.sh /usr/local/bin/agent-entrypoint
RUN chmod +x /usr/local/bin/agent-entrypoint

WORKDIR /root/workspace
ENTRYPOINT ["/usr/local/bin/agent-entrypoint"]
CMD ["runsvdir", "/root/.sv.run"]
