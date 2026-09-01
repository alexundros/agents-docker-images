ARG BASE_IMAGE=debian:12-slim
FROM ${BASE_IMAGE}

# Default to official Debian mirrors
ARG APT_MIRROR=https://deb.debian.org/debian
ARG APT_SEC_MIRROR=https://deb.debian.org/debian-security

ENV DEBIAN_FRONTEND=noninteractive \
  PIP_NO_CACHE_DIR=1 \
  PIP_DISABLE_PIP_VERSION_CHECK=1

LABEL org.opencontainers.image.title="AI tools images" \
  org.opencontainers.image.description="Base layer with common tooling for AI tools images"

# APT sources + base packages
ARG DEBIAN_CODENAME=bookworm
RUN set -eux; \
  { \
  echo "deb ${APT_MIRROR} ${DEBIAN_CODENAME} main contrib non-free"; \
  echo "deb ${APT_MIRROR} ${DEBIAN_CODENAME}-updates main contrib non-free"; \
  echo "deb ${APT_SEC_MIRROR} ${DEBIAN_CODENAME}-security main contrib non-free"; \
  } > /etc/apt/sources.list; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
  # TLS / apt transport
  apt-transport-https ca-certificates gnupg \
  # Build toolchain & shell
  build-essential bash \
  # VCS & downloaders
  curl wget git \
  # Archivers
  zip unzip \
  # Search & CLI utilities
  fzf fd-find ripgrep jq \
  # Editors & TUI
  nano vim neovim mc \
  # Network & debug
  net-tools iputils-ping strace lsof tcpdump \
  # Process/system info utilities (free, nproc, ...)
  procps \
  # Development libraries
  libssl-dev zlib1g-dev libffi-dev \
  # Python
  python3 python3-pip python3-venv; \
  ln -s "$(command -v fdfind)" /usr/local/bin/fd; \
  apt-get clean; rm -rf /var/lib/apt/lists/*

# Container info banner
COPY --chmod=755 assets/info-banner.sh /usr/local/bin/info-banner.sh

# Node.js (NodeSource, current LTS)
ARG NODE_MAJOR=22
RUN set -eux; \
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -; \
  apt-get install -y --no-install-recommends nodejs; apt-get clean; \
  rm -rf /var/lib/apt/lists/*; node --version; npm --version

# Non-root user
ARG USER_GID=1001
ARG USER_UID=1001
RUN groupadd -g ${USER_GID} coder && \
  useradd -u ${USER_UID} -g coder -m -s /bin/bash coder && \
  mkdir -p /home/coder && chown -R coder:coder /home/coder

USER coder
WORKDIR /home/coder
CMD ["info-banner.sh"]
