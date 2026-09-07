# `default/rust` — Rust toolchain

`PARENT`: `default/base/12`. Version `stable` (rustup rolling channel — not pinned).

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
# dockerfiles/default/rust/stable/.meta
PARENT=default/base/12
ARG_RUST_VER=stable
```

---

Pull: `docker pull ghcr.io/alexundros/agents-docker-images/rust:stable`

Back to [image contents](../image-contents.md) · [README](../../README.md)
