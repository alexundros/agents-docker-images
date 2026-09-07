# `default/rust-zig` — Zig + cargo-zigbuild

`PARENT`: `default/rust/stable`. Version is **composite** `rust`+`zig`: `stable-0.14.0`.

## Zig

- **Zig 0.14.0** (`ARG_ZIG_VER`), filename `zig-linux-${z_arch}-${ZIG_VER}.tar.xz`.
- **Arch mapping**: `amd64` → `x86_64`, `arm64` → `aarch64`.
- **Download strategy** (mirror-fallback):
  1. If `ZIG_MIRROR` is set, try `ZIG_MIRROR/<fn>` first.
  2. Otherwise shuffle `assets/zig-mirrors.txt` (`shuf`) and try each base URL until one succeeds.
  3. Fail closed if none succeed.
- Installed to `/usr/local/zig` (stripped `--strip-components=1`), added to `PATH`.

## cargo-zigbuild

- **cargo-zigbuild 0.23.3** (`ARG_ZIGBUILD_VER`) — prebuilt release binary from GitHub:
  `https://github.com/rust-cross/cargo-zigbuild/releases/download/v${ZIGBUILD_VER}/cargo-zigbuild-${zb_arch}-unknown-linux-gnu.tar.xz`.
- Unpacked straight into `/home/coder/.cargo/bin` — no source compilation, no cargo registry cache.

## `.meta`

```text
# dockerfiles/default/rust-zig/stable-0.14.0/.meta
PARENT=default/rust/stable
ARG_ZIG_VER=0.14.0
ARG_ZIGBUILD_VER=0.23.3
```

The version tag is `<rust-channel>-<zig-version>` so the image key matches the composite ordering used by `extra/*` (`go`-`rust`-`zig`-`jdk`). cargo-zigbuild's version is not part of the tag (it is a fixed companion pinned via `ARG_ZIGBUILD_VER`).

---

Pull: `docker pull ghcr.io/alexundros/agents-docker-images/rust-zig:stable-0.14.0`

Back to [image contents](../image-contents.md) · [README](../../README.md)
