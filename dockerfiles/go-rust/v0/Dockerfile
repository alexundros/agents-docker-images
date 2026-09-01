ARG BASE_IMAGE=scratch
FROM ${BASE_IMAGE}

USER root

# Extra OS packages for cross toolchains
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
  # Linux musl (x86_64-unknown-linux-musl) linker
  musl-tools \
  # Required to unpack the zig tarball (.tar.xz)
  xz-utils; \
  apt-get clean; rm -rf /var/lib/apt/lists/*

USER coder
ENV PATH="/home/coder/.cargo/bin:${PATH}" \
  RUSTUP_HOME=/home/coder/.rustup \
  CARGO_HOME=/home/coder/.cargo

# Rust toolchain (rustup) + targets
ARG RUST_VER=stable
RUN set -eux; \
  curl -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh; \
  sh /tmp/rustup-init.sh -v -y --no-modify-path --default-toolchain "${RUST_VER}" --profile minimal \
  -t "add x86_64-unknown-linux-gnu,x86_64-unknown-linux-musl";
