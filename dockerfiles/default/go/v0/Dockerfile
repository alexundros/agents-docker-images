ARG BASE_IMAGE=scratch
FROM ${BASE_IMAGE}

USER root

# Go (official tarball, multi-arch)
ARG GO_VER=1.26.7
RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "${arch}" in \
  amd64) g_arch=amd64 ;; \
  arm64) g_arch=arm64 ;; \
  *) echo "unsupported architecture: ${arch}" >&2; exit 1 ;; \
  esac; \
  url="https://go.dev/dl/go${GO_VER}.linux-${g_arch}.tar.gz"; \
  curl -fsSL "${url}" -o /tmp/go.tar.gz; rm -rf /usr/local/go; \
  tar -C /usr/local -xzf /tmp/go.tar.gz; rm -f /tmp/go.tar.gz; \
  /usr/local/go/bin/go version; \
  rm -rf /usr/local/go/test /usr/local/go/doc /usr/local/go/misc

USER coder
ENV GOPATH=/home/coder/go \
  PATH="/usr/local/go/bin:/home/coder/go/bin:${PATH}"
