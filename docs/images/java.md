# `default/java` — JDK + Maven/Gradle

`PARENT`: `default/base/12`. One shared, parameterized Dockerfile
(`dockerfiles/default/java/Dockerfile`, referenced via `DOCKERFILE=default/java/Dockerfile`)
serves **all** java versions — no duplicated Dockerfiles:

- `8`, `11`, `17`, `21`, `26` — single-JDK images (small, default JDK = the one installed);
- `all` — multi-JDK image (8/11/17/21/26 + GraalVM 21, default JDK 21).

## Dockerfile knobs

| ARG            | Meaning                                                                 |
| -------------- | ----------------------------------------------------------------------- |
| `JAVA_VERS`    | space-separated list of Temurin identifiers to install                  |
| `JAVA_DEFAULT` | the version made default (`JAVA_HOME`, `java` on `PATH`)                |
| `GRAALVM_VER`  | optional Oracle GraalVM id — installed only when non-empty (`all` only) |
| `MAVEN_VER`    | Maven version (default `3.9.16`)                                        |
| `GRADLE_VER`   | Gradle version (default `9.7.1`)                                        |

## SDKMAN

- Installed from `https://get.sdkman.io` into `SDKMAN_DIR=/home/coder/.sdkman`.
- `PATH` includes `/home/coder/.sdkman/bin`.

## Current Temurin identifiers

| Tag   | `JAVA_VERS`                                                   |
| ----- | ------------------------------------------------------------- |
| `8`   | `8.0.504+1-tem`                                               |
| `11`  | `11.0.32+1.1-tem`                                             |
| `17`  | `17.0.20-tem`                                                 |
| `21`  | `21.0.12+1.1-tem`                                             |
| `26`  | `26.0.2+1.1-tem`                                              |
| `all` | all five + GraalVM `21.0.12-graal`, default `21.0.12+1.1-tem` |

## ENV

```text
JAVA_HOME=/home/coder/.sdkman/candidates/java/current
PATH=.../gradle/current/bin:.../maven/current/bin:.../java/current/bin:${PATH}
```

## Size optimization

- Per-JDK `lib/src.zip` is removed for every installed JDK except `current`.
- `.sdkman/tmp` and `.sdkman/archives` (download cache) are removed — saves roughly **1 GB**.

## `.meta` examples

```text
# dockerfiles/default/java/21/.meta
DOCKERFILE=default/java/Dockerfile
PARENT=default/base/12
ARG_JAVA_VERS=21.0.12+1.1-tem
ARG_JAVA_DEFAULT=21.0.12+1.1-tem
ARG_MAVEN_VER=3.9.16
ARG_GRADLE_VER=9.7.1
```

```text
# dockerfiles/default/java/all/.meta
DOCKERFILE=default/java/Dockerfile
PARENT=default/base/12
ARG_JAVA_VERS=8.0.504+1-tem 11.0.32+1.1-tem 17.0.20-tem 21.0.12+1.1-tem 26.0.2+1.1-tem
ARG_JAVA_DEFAULT=21.0.12+1.1-tem
ARG_GRAALVM_VER=21.0.12-graal
ARG_MAVEN_VER=3.9.16
ARG_GRADLE_VER=9.7.1
```

---

Pull: `docker pull ghcr.io/alexundros/agents-docker-images/java:<tag>` — `<tag>` is `8`, `11`, `17`, `21`, `26` or `all`.

Back to [image contents](../image-contents.md) · [README](../../README.md)
