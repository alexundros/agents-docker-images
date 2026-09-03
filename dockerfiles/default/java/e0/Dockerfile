ARG BASE_IMAGE=scratch
FROM ${BASE_IMAGE}

USER coder

# SDKMAN
ENV SDKMAN_DIR=/home/coder/.sdkman \
  PATH="/home/coder/.sdkman/bin:${PATH}"

# JDK versions (Temurin identifiers)
ARG JAVA8_VER=8.0.504+1-tem
ARG JAVA11_VER=11.0.32+1.1-tem
ARG JAVA17_VER=17.0.20-tem
ARG JAVA21_VER=21.0.12+1.1-tem
ARG JAVA_DEFAULT=21.0.12+1.1-tem

# GraalVM (Oracle, based on JDK 21)
ARG GRAALVM_VER=21.0.12-graal

# Build tools
ARG MAVEN_VER=3.9.16
ARG GRADLE_VER=9.7.1

RUN set -eux; \
  curl -fsSL "https://get.sdkman.io" | bash; \
  bash -lc ' \
  source "${SDKMAN_DIR}/bin/sdkman-init.sh"; \
  sdk install java "${JAVA8_VER}" < /dev/null; \
  sdk install java "${JAVA11_VER}" < /dev/null; \
  sdk install java "${JAVA17_VER}" < /dev/null; \
  sdk install java "${JAVA21_VER}" < /dev/null; \
  sdk install java "${GRAALVM_VER}" < /dev/null; \
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
