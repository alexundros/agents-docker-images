ARG BASE_IMAGE=scratch
FROM ${BASE_IMAGE}

USER coder

# SDKMAN
ENV SDKMAN_DIR=/home/coder/.sdkman \
  PATH="/home/coder/.sdkman/bin:${PATH}"

# JDK versions: space-separated Temurin identifiers,
# e.g. "8.0.504+1-tem 11.0.32+1.1-tem" (single version for standalone images)
ARG JAVA_VERS
ARG JAVA_DEFAULT

# GraalVM (Oracle, based on JDK 21); only installed when non-empty
ARG GRAALVM_VER=

# Build tools
ARG MAVEN_VER=3.9.16
ARG GRADLE_VER=9.7.1

RUN set -eux; \
  [ -n "${JAVA_VERS}" ] || { echo "ERROR: JAVA_VERS is not set" >&2; exit 1; }; \
  [ -n "${JAVA_DEFAULT}" ] || { echo "ERROR: JAVA_DEFAULT is not set" >&2; exit 1; }; \
  curl -fsSL "https://get.sdkman.io" | bash; \
  bash -lc ' \
  source "${SDKMAN_DIR}/bin/sdkman-init.sh"; \
  for v in ${JAVA_VERS}; do \
    sdk install java "${v}" < /dev/null; \
  done; \
  if [ -n "${GRAALVM_VER}" ]; then sdk install java "${GRAALVM_VER}" < /dev/null; fi; \
  sdk default java "${JAVA_DEFAULT}"; \
  sdk install maven "${MAVEN_VER}" < /dev/null; \
  sdk install gradle "${GRADLE_VER}" < /dev/null; \
  java -version; mvn -version; gradle --version; \
  '; \
  for d in "${HOME}/.sdkman/candidates/java"/*/; do \
    case "$(basename "$d")" in current) continue ;; esac; \
    rm -rf "${d}lib/src.zip"; \
  done; \
  rm -rf "${HOME}/.sdkman/tmp" "${HOME}/.sdkman/archives"

# Default JDK and build tools on PATH
ENV JAVA_HOME=/home/coder/.sdkman/candidates/java/current
ENV PATH="/home/coder/.sdkman/candidates/gradle/current/bin:${PATH}"
ENV PATH="/home/coder/.sdkman/candidates/maven/current/bin:${PATH}"
ENV PATH="/home/coder/.sdkman/candidates/java/current/bin:${PATH}"
