# Image contents

> Detailed breakdown of every image and its versions, straight from the Dockerfiles and `.meta` files. For how images are built and published, see [build-system.md](build-system.md).

Each image is defined by a `dockerfiles/<namespace>/<key>/<version>/` directory. The `.meta` file supplies `PARENT` and `ARG_*` build args; the Dockerfile (its own or reused via `DOCKERFILE=`) does the actual install.

---

## `default/base` — the common layer

`PARENT`: — (base of the tree). Version `v0`.

### OS & environment

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

### Packages (installed with `--no-install-recommends`)

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

### Node.js

- Installed from **NodeSource** (setup script for the current LTS), `ARG_NODE_VER=22`.
- Provides `node` and `npm`; versions are printed during the build.

### Entrypoint

- `assets/info-banner.sh` is copied to `/usr/local/bin/info-banner.sh` (mode 755).
- `CMD ["info-banner.sh"]` — every image derived from `base` prints environment, installed tools and system info on start.

### User & workdir

- Non-root `coder` user, UID/GID `1001` (`groupadd`/`useradd`), login shell `/bin/bash`.
- `WORKDIR /home/coder`, home owned by `coder:coder`.

### `.meta` build args

```text
ARG_APT_MIRROR=http://mirror.yandex.ru/debian
ARG_APT_SEC_MIRROR=http://mirror.yandex.ru/debian-security
ARG_NODE_VER=22
```

---

## `default/go` — Go toolchain

`PARENT`: `default/base/v0`. Version `v0`.

- **Go 1.26.7** (`ARG_GO_VER`) from the official tarball: `https://go.dev/dl/go${GO_VER}.linux-${g_arch}.tar.gz`.
- **Multi-arch**: `amd64` → `amd64`, `arm64` → `arm64`.
- Installed to `/usr/local/go`, then trimmed to a smaller layer:
  - removed: `/usr/local/go/test`, `/usr/local/go/doc`, `/usr/local/go/misc`.
- **ENV**:
  - `GOPATH=/home/coder/go`
  - `PATH=/usr/local/go/bin:/home/coder/go/bin:${PATH}`
- Runs as `coder`.

```text
# dockerfiles/default/go/v0/.meta
PARENT=default/base/v0
ARG_GO_VER=1.26.7
```

---

## `default/rust` — Rust toolchain

`PARENT`: `default/base/v0`. Version `v0`.

- **rustup** installed from `https://sh.rustup.rs` with:
  - `--default-toolchain stable` (`ARG_RUST_VER`)
  - `--profile minimal`
  - `--no-modify-path`
- **Targets**: `x86_64-unknown-linux-gnu`, `x86_64-unknown-linux-musl`.
- **Extra OS packages** for cross toolchains:
  - `build-essential` — C toolchain for rust builds
  - `musl-tools` — musl linker for `x86_64-unknown-linux-musl`
  - `xz-utils` — required to unpack the Zig tarball downstream (`.tar.xz`)
- **ENV**:
  - `RUSTUP_HOME=/home/coder/.rustup`
  - `CARGO_HOME=/home/coder/.cargo`
  - `PATH=/home/coder/.cargo/bin:${PATH}`
- **Cleanup**: `/home/coder/.rustup/tmp` is removed.

```text
# dockerfiles/default/rust/v0/.meta
PARENT=default/base/v0
ARG_RUST_VER=stable
```

---

## `default/rust-zig` — Zig + cargo-zigbuild

`PARENT`: `default/rust/v0`. Version `0.1`.

### Zig

- **Zig 0.14.0** (`ARG_ZIG_VER`), filename `zig-linux-${z_arch}-${ZIG_VER}.tar.xz`.
- **Arch mapping**: `amd64` → `x86_64`, `arm64` → `aarch64`.
- **Download strategy** (mirror-fallback):
  1. If `ZIG_MIRROR` is set, try `ZIG_MIRROR/<fn>` first.
  2. Otherwise shuffle `assets/zig-mirrors.txt` (`shuf`) and try each base URL until one succeeds.
  3. Fail closed if none succeed.
- Installed to `/usr/local/zig` (stripped `--strip-components=1`), added to `PATH`.

### cargo-zigbuild

- **cargo-zigbuild 0.23.3** (`ARG_ZIGBUILD_VER`) — prebuilt release binary from GitHub:
  `https://github.com/rust-cross/cargo-zigbuild/releases/download/v${ZIGBUILD_VER}/cargo-zigbuild-${zb_arch}-unknown-linux-gnu.tar.xz`.
- Unpacked straight into `/home/coder/.cargo/bin` — no source compilation, no cargo registry cache.

```text
# dockerfiles/default/rust-zig/0.1/.meta
PARENT=default/rust/v0
ARG_ZIG_VER=0.14.0
ARG_ZIGBUILD_VER=0.23.3
```

---

## `default/java` — Java/Maven/Gradle

`PARENT`: `default/base/v0`. Two versions: `v0` and `e1`.

### SDKMAN

- Installed from `https://get.sdkman.io` into `SDKMAN_DIR=/home/coder/.sdkman`.
- `PATH` includes `/home/coder/.sdkman/bin`.

### JDKs (Temurin identifiers)

| Version | `v0`              | `e1`                                      |
| ------- | ----------------- | ----------------------------------------- |
| JDK 8   | `8.0.504+1-tem`   | `8.0.504+1-tem`                           |
| JDK 11  | `11.0.32+1.1-tem` | `11.0.32+1.1-tem`                         |
| JDK 17  | `17.0.20-tem`     | `17.0.20-tem`                             |
| JDK 21  | `21.0.12+1.1-tem` | `21.0.12+1.1-tem`                         |
| JDK 26  | —                 | `26.0.2+1.1-tem`                          |
| GraalVM | —                 | `21.0.12-graal` (Oracle, based on JDK 21) |

- **Default JDK is 21** (`ARG_JAVA_DEFAULT=21.0.12+1.1-tem`) in both versions — it defines `JAVA_HOME` and the `java`/`javac` on `PATH`.

### Build tools

- Maven **3.9.16** (`ARG_MAVEN_VER`).
- Gradle **9.7.1** (`ARG_GRADLE_VER`).

### ENV

```text
JAVA_HOME=/home/coder/.sdkman/candidates/java/current
PATH=.../gradle/current/bin:.../maven/current/bin:.../java/current/bin:${PATH}
```

### Size optimization

- Per-JDK `lib/src.zip` is removed for every installed JDK except `current`.
- `.sdkman/tmp` and `.sdkman/archives` (download cache) are removed — saves roughly **1 GB**.

### `.meta`

```text
# dockerfiles/default/java/v0/.meta
PARENT=default/base/v0
ARG_JAVA8_VER=8.0.504+1-tem
ARG_JAVA11_VER=11.0.32+1.1-tem
ARG_JAVA17_VER=17.0.20-tem
ARG_JAVA21_VER=21.0.12+1.1-tem
ARG_JAVA_DEFAULT=21.0.12+1.1-tem
ARG_MAVEN_VER=3.9.16
ARG_GRADLE_VER=9.7.1
```

```text
# dockerfiles/default/java/e1/.meta
PARENT=default/base/v0
ARG_JAVA8_VER=8.0.504+1-tem
ARG_JAVA11_VER=11.0.32+1.1-tem
ARG_JAVA17_VER=17.0.20-tem
ARG_JAVA21_VER=21.0.12+1.1-tem
ARG_JAVA26_VER=26.0.2+1.1-tem
ARG_JAVA_DEFAULT=21.0.12+1.1-tem
ARG_GRAALVM_VER=21.0.12-graal
ARG_MAVEN_VER=3.9.16
ARG_GRADLE_VER=9.7.1
```

---

## `extra/*` — combinations

`extra` images carry **no Dockerfile of their own**: they reuse an existing one via `DOCKERFILE=` and layer it onto a richer parent. Because every reused Dockerfile installs into `/home/coder`, the layers compose cleanly.

| Image                    | Version | Reuses Dockerfile                 | Parent                  | Result                                                               |
| ------------------------ | ------- | --------------------------------- | ----------------------- | -------------------------------------------------------------------- |
| `extra/go-rust`          | `v0`    | `default/rust/v0/Dockerfile`      | `default/go/v0`         | Go + Rust                                                            |
| `extra/go-rust-zig`      | `0.1`   | `default/rust-zig/0.1/Dockerfile` | `extra/go-rust/v0`      | Go + Rust + Zig                                                      |
| `extra/go-rust-zig-java` | `0.1`   | `default/java/v0/Dockerfile`      | `extra/go-rust-zig/0.1` | Go + Rust + Zig + Java/Maven/Gradle (JDK 8/11/17/21)                 |
| `extra/go-rust-zig-java` | `e1`    | `default/java/e1/Dockerfile`      | `extra/go-rust-zig/0.1` | Go + Rust + Zig + Java/Maven/Gradle (JDK 8/11/17/21/26 + GraalVM 21) |

Image names come from the key basename (no `IMAGE=` override is set), so the full workspace is pulled as `go-rust-zig-java`.

### `.meta` examples

```text
# extra/go-rust/v0/.meta
DOCKERFILE=default/rust/v0/Dockerfile
PARENT=default/go/v0
ARG_RUST_VER=stable
```

```text
# extra/go-rust-zig/0.1/.meta
DOCKERFILE=default/rust-zig/0.1/Dockerfile
PARENT=extra/go-rust/v0
ARG_ZIG_VER=0.14.0
ARG_ZIGBUILD_VER=0.23.3
```

```text
# extra/go-rust-zig-java/0.1/.meta
DOCKERFILE=default/java/v0/Dockerfile
PARENT=extra/go-rust-zig/0.1
ARG_JAVA8_VER=8.0.504+1-tem
ARG_JAVA11_VER=11.0.32+1.1-tem
ARG_JAVA17_VER=17.0.20-tem
ARG_JAVA21_VER=21.0.12+1.1-tem
ARG_JAVA_DEFAULT=21.0.12+1.1-tem
ARG_MAVEN_VER=3.9.16
ARG_GRADLE_VER=9.7.1
```

```text
# extra/go-rust-zig-java/e1/.meta
DOCKERFILE=default/java/e1/Dockerfile
PARENT=extra/go-rust-zig/0.1
ARG_JAVA8_VER=8.0.504+1-tem
ARG_JAVA11_VER=11.0.32+1.1-tem
ARG_JAVA17_VER=17.0.20-tem
ARG_JAVA21_VER=21.0.12+1.1-tem
ARG_JAVA26_VER=26.0.2+1.1-tem
ARG_JAVA_DEFAULT=21.0.12+1.1-tem
ARG_GRAALVM_VER=21.0.12-graal
ARG_MAVEN_VER=3.9.16
ARG_GRADLE_VER=9.7.1
```

---

Back to [README](../README.md).
