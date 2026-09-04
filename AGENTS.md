# Agent Runtime Instructions

You are running inside a dedicated Linux container with root privileges.

The complete `/root` directory is persistent across container recreation. The Nix store at `/nix` is also persistent. Other filesystem locations should be treated as ephemeral unless explicitly documented otherwise.

## Persistent storage

Use these locations for anything that should survive recreation:

- Workspace: `/root/workspace`
- User binaries: `/root/.local/bin`
- User data: `/root/.local/share`
- Configuration: `/root/.config`
- Cache: `/root/.cache`
- General tools: `/root/tools`
- runit service definitions: `/root/.sv`
- runit enabled services: `/root/.sv.run`
- Python virtual environments: `/root/.venvs`
- fnm/Node versions: `/root/.local/share/fnm`
- pnpm: `/root/.local/share/pnpm`
- Corepack cache: `/root/.cache/node/corepack`
- Rust (when installed): `/root/.cargo` and `/root/.rustup`
- Go (when installed): `/root/go`
- Playwright browsers: `/root/.cache/ms-playwright`
- Nix store/state: `/nix`

Do not rely on software installed into `/usr`, `/lib`, `/bin`, `/sbin`, `/opt`, `/etc`, or `/var` surviving container recreation.

## Software installation policy

Prefer installations in this order:

1. Use an existing command.
2. Install a standalone binary into `/root/.local/bin`.
3. Use a language-native user installation.
4. Use Nix when it provides a clean persistent package and no project-specific constraint conflicts with it.
5. Build from source with prefix `/root/.local` or `/root/tools`.
6. Use `apt` only when a dependency fundamentally needs to modify the system layer.

If a broadly useful dependency genuinely requires `apt`, prefer adding it to the Dockerfile instead of relying on runtime installation.

The base image intentionally does not preinstall every SDK or specialized client. Go, Rust, Java, database clients, cloud CLIs, Kubernetes tools, Terraform, FFmpeg, ShellCheck, GDB, Clang and similar tools should normally be installed only when a task needs them.

## Node.js / fnm / Corepack / pnpm

The image includes a Node 24 LTS/npm baseline copied from the official Node image, so Node works without fnm initialization. Prefer `fnm` when a project has a different or more specific Node version requirement in `.nvmrc`, `.node-version`, or `engines.node`.

Typical commands:

```bash
fnm install --lts
fnm use --install-if-missing
fnm use
```

`fnm` understands `.nvmrc` and `.node-version` files. Node versions live under persistent `/root/.local/share/fnm`.

Corepack is explicitly installed by the image. For pnpm projects prefer Corepack:

```bash
corepack enable pnpm
pnpm install
```

Global npm packages are configured to install under `/root/.local`.

Respect the package manager and version declared by a project. Do not replace or upgrade it without a task-specific reason.

## Python

Prefer `uv`.

For CLI applications:

```bash
uv tool install <package>
```

For projects, prefer a project-local virtual environment. Avoid modifying the system Python environment.

## Rust

Rust is intentionally not preinstalled. When required, prefer a persistent user-space installation (for example rustup under `/root/.cargo` and `/root/.rustup`) or use Nix for an isolated toolchain.

## Go

Go is intentionally not preinstalled. When required, install it persistently under `/root`, or use Nix. `GOPATH=/root/go` and `GOBIN=/root/.local/bin` are already configured for persistent use.

## Nix

Nix is available as a daemonless root installation from the Ubuntu package, and `/nix` is persisted separately from `/root`.

Prefer modern CLI commands such as:

```bash
nix profile install nixpkgs#ripgrep
nix shell nixpkgs#ffmpeg
nix shell nixpkgs#go
nix shell nixpkgs#rustc nixpkgs#cargo
nix develop
```

Flakes and `nix-command` are enabled. Nix sandboxing is disabled inside this container because nested namespace restrictions commonly conflict with Docker defaults; the outer container is the intended isolation boundary.

Do not mount `/nix` from an unrelated host Nix installation.

## Source builds

Prefer:

```bash
./configure --prefix=/root/.local
make -j"$(nproc)"
make install
```

or install multi-file tools under `/root/tools/<tool>` and expose executables via `/root/.local/bin`.

## Browser automation

Prefer Playwright. Browser downloads must remain under `/root/.cache/ms-playwright`; `PLAYWRIGHT_BROWSERS_PATH` is already configured.

Use headless mode unless headed execution is specifically required. The base image includes common Chromium runtime libraries and CJK fonts, but if a Playwright release requires additional OS libraries, add those dependencies to the Dockerfile rather than treating runtime `apt install` as persistent.

## Background services

The container's default main process is `runsvdir /root/.sv.run`. Put runit service definitions under `/root/.sv/<name>` and enable them with links under `/root/.sv.run`; both directories persist with the agent HOME.

Use `sv status`, `sv start`, `sv stop`, and `sv restart` against enabled services under `/root/.sv.run`.

## Workspace workflow

Primary workspace: `/root/workspace`.

Before modifying an existing repository:

- read project instructions;
- inspect `git status`;
- understand relevant code first;
- preserve existing user changes;
- make focused changes;
- run relevant tests/checks;
- review the resulting diff;
- report failures accurately.

## Preferred tools

Use these where appropriate:

- `rg`, `fd`, `git grep` for search
- `jq` for JSON
- `git`, `gh` for source control/GitHub
- `curl`, `wget` for HTTP/downloads
- `dig`, `ping`, `nc`, `socat`, `tcpdump` for network diagnostics
- `strace`, `lsof` for debugging
- `uv` for Python
- `fnm`, `npm`, `corepack`, `pnpm` for Node.js
- `nix` for persistent/isolated tooling
- `sqlite3` for lightweight database inspection

Install task-specific tools persistently when needed rather than assuming they are part of the base image.

## Safety boundaries

Root privileges apply only inside this container.

Treat persistent HOME data as sensitive. Do not expose or modify credentials, SSH keys, authentication tokens, cookies, browser profiles, or unrelated user configuration unless the task explicitly requires it.

Do not attempt to escape the container or weaken isolation. Do not assume Docker socket or host filesystem access.

Be especially careful with destructive commands such as `rm -rf`, `git reset --hard`, `git clean -fdx`, database deletion, filesystem formatting, and recursive permission changes.

## Persistence rule

If it would be annoying to reinstall or recreate, keep it under `/root` or install it through the persistent `/nix` store.

If it is a fundamental operating-system dependency, it belongs in the Dockerfile.
