# agent-runtime

A persistent, containerized development runtime for AI coding agents such as Claude Code, Codex, OpenCode, and similar tools.

## Design

The runtime separates immutable operating-system dependencies from long-lived agent state:

```text
Docker image: disposable system layer
├── Ubuntu 24.04
├── /usr, /bin, /lib
├── high-frequency build/debug/network bootstrap tools
├── Python + uv
├── official Node 24 LTS/npm baseline + fnm + Corepack
├── Chromium/Playwright system libraries + CJK fonts
└── Nix CLI

Persistent host directory: agent HOME
└── ${AGENT_ROOT_PATH} -> /root
    ├── workspace
    ├── .local
    ├── .config
    ├── .cache
    ├── .sv / .sv.run
    ├── .claude / .codex / ...
    ├── fnm Node versions
    ├── pnpm/Corepack caches
    ├── optional .cargo / .rustup
    ├── optional go
    ├── tools
    └── Playwright browsers

Persistent host directory: Nix store/state
└── ${AGENT_ROOT_PATH}/.nix -> /nix
```

The agent runs as root inside the container, but no Docker socket or broad host filesystem mount is granted.

## Base image philosophy

The image is intentionally **not** a kitchen-sink SDK image. It should contain enough stable infrastructure to let an agent build or acquire the environment it needs, while large/project-specific toolchains live in persistent `/root` or `/nix`.

This keeps the base image smaller and avoids carrying every version of Go, Rust, Java, database clients, cloud CLIs, Kubernetes tooling, Terraform, FFmpeg, Clang, GDB, and similar packages forever.

## Included tools

### Shell / source / search

`bash`, `git`, `git-lfs`, `gh`, `ripgrep`, `fd`, `jq`, `tmux`, `runit`, and a minimal `vi` (`vim-tiny`).

### Build / debugging

`gcc/g++`, `make` (via `build-essential`), `cmake`, `ninja`, `pkg-config`, `strace`, and `lsof`.

### Network

`curl`, `wget`, SSH, `rsync`, `ip`, `ping`, `dig`, `nc`, `socat`, `traceroute`, `tcpdump`.

### Language/runtime bootstrap

- Python 3 + `venv` + `pip` + pinned `uv`
- Node 24 LTS/npm baseline copied from the official Node image
- pinned `fnm` for persistent per-project Node versions
- pinned explicit Corepack + pnpm support
- Nix

Go and Rust are deliberately available **on demand**, not preinstalled.

### Database

`sqlite3` only. PostgreSQL/MySQL/Redis clients are on-demand tools.

### Browser support

Common Chromium runtime libraries, Latin/CJK/Emoji fonts, and a persistent Playwright browser directory at `/root/.cache/ms-playwright`.

## Bootstrap version defaults

The Dockerfile uses explicit build arguments instead of downloading an unconstrained `latest` during every build. Node tracks the 24 LTS line by default; the other bootstrap tools are pinned to exact versions:

```text
NODE_VERSION=24
UV_VERSION=0.12.9
FNM_VERSION=1.39.0
COREPACK_VERSION=0.36.0
```

They can be overridden during local builds through `.env` / `docker-compose.dev.yml`.

## Why fnm instead of nvm?

`fnm` is a small native binary, starts quickly, understands `.nvmrc` and `.node-version`, and stores managed Node versions cleanly under persistent HOME. It is a project-version manager, not a prerequisite for running Node: the image always has a Node 24 LTS/npm baseline copied from the official Node image, so non-interactive commands such as `docker compose exec agent node --version` work before any fnm-managed version is installed.

Typical first use:

```bash
fnm install --lts
fnm default lts-latest
fnm use --lts
```

In a project with `.nvmrc` or `.node-version`, entering the directory automatically activates the matching version when available because the shell initializes `fnm --use-on-cd`.

## Node bootstrap chain

The image deliberately avoids Ubuntu's `nodejs` and `npm` packages. The Dockerfile uses the official `node:24-bookworm-slim` image as a build stage and copies its Node binary and npm installation into the Ubuntu runtime image. This avoids the older distro Node release and its large set of `node-*` package dependencies.

The resulting chain is:

```text
official Node 24 LTS image -> baseline Node/npm -> pinned Corepack -> optional fnm project override
```

`NODE_VERSION` selects the official Node image version used by local builds and defaults to the Node 24 LTS line.

## Corepack and pnpm

Corepack is installed explicitly rather than relying on Node to bundle it.

For a pnpm project:

```bash
corepack enable pnpm
pnpm install
```

Corepack's cache is persisted under:

```text
/root/.cache/node/corepack
```

pnpm state lives under:

```text
/root/.local/share/pnpm
```

## Service supervision with runit

The image includes runit and initializes two persistent directories on every container start:

```text
/root/.sv      service definitions
/root/.sv.run  enabled services watched by runsvdir
```

`runsvdir /root/.sv.run` is the container's default main process. Keep each service definition under `/root/.sv/<name>` with an executable `run` script, then enable it by linking that directory into `/root/.sv.run`:

```bash
ln -s /root/.sv/example /root/.sv.run/example
sv status /root/.sv.run/example
```

Because both directories live under the persistent agent HOME, service definitions and enablement survive container recreation. Removing an enabled-service link stops that service without deleting its definition.

## Nix

Nix is installed from Ubuntu's `nix-bin` package and runs daemonless as root. It is a good fit for tools that are awkward to install as a standalone binary, have many dependencies, or are only needed temporarily in an isolated environment.

Unlike most user-space tools, Nix cannot be fully persisted by saving `/root`; its package store and state live under `/nix`. Compose therefore uses a second bind mount alongside the agent HOME mount:

```text
${AGENT_ROOT_PATH}       -> /root
${AGENT_ROOT_PATH}/.nix  -> /nix
```

Use `nix profile install` for tools that should remain available in later sessions:

```bash
nix profile install nixpkgs#ffmpeg
```

Use `nix shell` for a temporary environment without adding the packages to the user profile:

```bash
nix shell nixpkgs#go
nix shell nixpkgs#rustc nixpkgs#cargo
nix shell nixpkgs#postgresql
nix shell nixpkgs#terraform
```

Projects with a `flake.nix` can enter their declared development environment with:

```bash
nix develop
```

`nix-command` and flakes are enabled. Nix sandboxing is disabled inside the container for compatibility with Docker's default namespace/capability restrictions; the container itself is the primary isolation boundary.

Do not point `${AGENT_ROOT_PATH}/.nix` at an unrelated host Nix installation. The container expects to own the mounted store and state.

## Persistent installation policy

Recommended priority:

1. already installed tool;
2. standalone binary -> `/root/.local/bin`;
3. language-native installation under `/root`;
4. Nix -> persistent `/nix` store;
5. source build -> `/root/.local` or `/root/tools`;
6. runtime `apt` only when unavoidable.

Examples:

```bash
uv tool install ruff
npm install -g some-cli
nix profile install nixpkgs#some-tool
```

`apt` writes into the disposable system layer. If a package is generally useful and truly system-level, add it to the Dockerfile.

## Browser automation

Playwright browser downloads are persisted:

```bash
npx playwright install chromium
```

because:

```text
PLAYWRIGHT_BROWSERS_PATH=/root/.cache/ms-playwright
```

The image includes common Chromium runtime libraries and CJK fonts. If a future Playwright release reports missing OS libraries, add those libraries to the Dockerfile.

`shm_size` is set to 2 GiB to reduce browser crashes caused by Docker's small default `/dev/shm`.

## Start from Docker Hub

```bash
cp .env.example .env
# edit AGENT_IMAGE

docker compose pull
docker compose up -d
docker compose exec agent bash
```

## Build locally

The deployment Compose file intentionally contains only `image:`. Local builds use an override so `docker compose up` does not ambiguously build when the intent is to pull a published runtime:

```bash
cp .env.example .env

docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  up -d --build
```

Stop without deleting persistent state:

```bash
docker compose down
```

Both `/root` and `/nix` are bind-mounted host directories, so `docker compose down -v` does not delete their contents. To reset persistent state, stop the container and deliberately remove the relevant directory under the configured `${AGENT_ROOT_PATH}` on the host; `.nix` contains the Nix store and state.

## Instruction files

`AGENTS.md` is the single source of truth for runtime-wide agent instructions. `CLAUDE.md` imports it with Claude Code's `@AGENTS.md` syntax instead of duplicating the same rules.

Both files are baked into the image under `/opt/agent-defaults` and seeded into persistent `/root` only when the corresponding file does not already exist. The entrypoint also creates `/root/.codex/AGENTS.md` as a symlink to `/root/AGENTS.md`, because Codex discovers global instructions under its own home directory rather than directly under `/root`. Claude Code discovers `/root/CLAUDE.md` while walking up from the workspace and expands its import of the sibling `AGENTS.md`.

Image upgrades never replace or merge persistent instruction files. To adopt a newer image default, remove the corresponding `/root/AGENTS.md` or `/root/CLAUDE.md` deliberately and restart the container. If `/root/.codex/AGENTS.md` already exists, the entrypoint leaves it unchanged.

## Docker Hub publishing

The included GitHub Actions workflow builds one multi-platform tag:

```text
<DOCKERHUB_USERNAME>/agent-runtime:latest
```

Platforms:

```text
linux/amd64
linux/arm64
```

Configure repository secrets:

```text
DOCKERHUB_USERNAME
DOCKERHUB_PASSWORD
```

A Docker Hub access token is preferred for `DOCKERHUB_PASSWORD`.

The publish workflow always pulls the current `ubuntu:24.04` base before building, uses a dedicated GitHub Actions BuildKit cache scope, and publishes SBOM/provenance attestations alongside the multi-platform image.

## Intentional omissions

Some tools are useful but intentionally not enabled by default because they substantially change the security or size profile or are project-specific:

- Go/Rust/Java and other full SDKs
- Clang/LLVM, GDB, autotools, ShellCheck
- PostgreSQL/MySQL/Redis clients
- Docker daemon / `/var/run/docker.sock`
- `--privileged`
- host filesystem mounts
- Kubernetes/cloud-provider credentials
- heavyweight pre-downloaded Chromium/Firefox/WebKit binaries
- every possible SDK/toolchain version

Agents can install project-specific CLI tools persistently via `/root` or Nix as needed.

## Security boundary

Do not casually add:

```text
/var/run/docker.sock
--privileged
/:/host
host /dev
host /proc
```

Container root plus Docker socket access can effectively become host root.

The intended model is:

> powerful inside the agent container; strongly isolated from the host.
