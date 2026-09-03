ARG BASE_IMAGE=scratch
FROM ${BASE_IMAGE}

USER root

# Zig
ARG ZIG_VER=0.14.0
ARG ZIG_MIRROR=
COPY assets/zig-mirrors.txt /tmp/zig-mirrors.txt
RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "${arch}" in \
  amd64) z_arch=x86_64 ;; \
  arm64) z_arch=aarch64 ;; \
  *) echo "unsupported architecture: ${arch}" >&2; exit 1 ;; \
  esac; \
  fn="zig-linux-${z_arch}-${ZIG_VER}.tar.xz"; ok=0; \
  try_url() { \
    echo "downloading: ${1}"; \
    curl -fsSL --connect-timeout 15 --max-time 180 --retry 1 "${1}" -o /tmp/zig.tar.xz; \
  }; \
  if [ -n "${ZIG_MIRROR}" ] && try_url "${ZIG_MIRROR}/${fn}"; then ok=1; fi; \
  if [ "${ok}" != "1" ]; then \
    shuf /tmp/zig-mirrors.txt > /tmp/zig-mirrors.shuf; \
    while IFS= read -r base; do \
      [ -n "${base}" ] || continue; \
      case "${base}" in \#*) continue ;; esac; \
      base="$(printf '%s\n' "${base}" | tr -d '\r')"; \
      if try_url "${base}/${fn}"; then ok=1; break; fi; \
    done < /tmp/zig-mirrors.shuf; \
    rm -f /tmp/zig-mirrors.shuf; \
  fi; \
  [ "${ok}" = "1" ] || { echo "ERROR: all zig download failed" >&2; exit 1; }; \
  rm -rf /usr/local/zig; mkdir -p /usr/local/zig; \
  tar -C /usr/local/zig --strip-components=1 -xJf /tmp/zig.tar.xz; \
  rm -f /tmp/zig.tar.xz; rm -rf /tmp/dist;

USER coder
ENV PATH="/usr/local/zig:${PATH}"

# cargo-zigbuild (prebuilt release binary)
ARG ZIGBUILD_VER=0.23.3
RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "${arch}" in \
  amd64) zb_arch=x86_64 ;; \
  arm64) zb_arch=aarch64 ;; \
  *) echo "unsupported architecture: ${arch}" >&2; exit 1 ;; \
  esac; \
  curl -fsSL "https://github.com/rust-cross/cargo-zigbuild/releases/download/v${ZIGBUILD_VER}/cargo-zigbuild-${zb_arch}-unknown-linux-gnu.tar.xz" \
    -o /tmp/czb.tar.xz; \
  tar -C /home/coder/.cargo/bin -xJf /tmp/czb.tar.xz; \
  rm -f /tmp/czb.tar.xz
