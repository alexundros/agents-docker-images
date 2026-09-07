# `default/base` — the common layer

`PARENT`: — (base of the tree). Version `12` (Debian major).

## OS & environment

- **OS**: Debian 12 (bookworm) **slim**.
- **apt sources** written at build time:
  - `bookworm` main/contrib/non-free
  - `bookworm-updates` main/contrib/non-free
  - `bookworm-security` main/contrib/non-free
- **apt mirrors** are configurable via build args (`ARG_APT_MIRROR` / `ARG_APT_SEC_MIRROR`). The `.meta` defaults point at the regional Yandex mirrors:
  - `http://mirror.yandex.ru/debian`
  - `http://mirror.yandex.ru/debian-security`
  - Set `ARG_APT_MIRROR=https://deb.debian.org/debian` in the Dockerfile ARGs for the official mirrors.
- **ENV**:
  - `DEBIAN_FRONTEND=noninteractive`
  - `PIP_NO_CACHE_DIR=1`
  - `PIP_DISABLE_PIP_VERSION_CHECK=1`
- **OCI labels**:
  - `org.opencontainers.image.title="AI tools images"`
  - `org.opencontainers.image.description="Base layer with common tooling for AI tools images"`

## Packages (installed with `--no-install-recommends`)

| Category            | Packages                                                        |
| ------------------- | --------------------------------------------------------------- |
| TLS / apt transport | `apt-transport-https`, `ca-certificates`, `gnupg`               |
| Shell               | `bash`                                                          |
| VCS & downloaders   | `curl`, `wget`, `git`                                           |
| Archivers           | `zip`, `unzip`                                                  |
| Search & CLI        | `fzf`, `fd-find` (aliased to `fd` via symlink), `ripgrep`, `jq` |
| Editors & TUI       | `nano`, `vim`, `neovim`, `mc` (Midnight Commander)              |
| Network & debug     | `net-tools`, `iputils-ping`, `strace`, `lsof`, `tcpdump`        |
| System info         | `procps` (`free`, `nproc`, …)                                   |
| Dev libraries       | `libssl-dev`, `zlib1g-dev`, `libffi-dev`                        |
| Languages           | `python3`, `python3-pip`, `python3-venv`                        |

`fd` is provided as a symlink: `ln -s "$(command -v fdfind)" /usr/local/bin/fd`.

## Node.js

- Installed from **NodeSource** (setup script for the current LTS), `ARG_NODE_VER=22`.
- Provides `node` and `npm`; versions are printed during the build.

## Entrypoint

- `assets/info-banner.sh` is copied to `/usr/local/bin/info-banner.sh` (mode 755).
- `CMD ["info-banner.sh"]` — every image derived from `base` prints environment, installed tools and system info on start.

## User & workdir

- Non-root `coder` user, UID/GID `1001` (`groupadd`/`useradd`), login shell `/bin/bash`.
- `WORKDIR /home/coder`, home owned by `coder:coder`.

## `.meta` build args

```text
ARG_APT_MIRROR=http://mirror.yandex.ru/debian
ARG_APT_SEC_MIRROR=http://mirror.yandex.ru/debian-security
ARG_NODE_VER=22
```

---

Pull: `docker pull ghcr.io/alexundros/agents-docker-images/base:12`

Back to [image contents](../image-contents.md) · [README](../../README.md)
