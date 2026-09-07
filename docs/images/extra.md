# `extra/*` — combinations

`extra` images carry **no Dockerfile of their own**: they reuse an existing one via `DOCKERFILE=` and layer it onto a richer parent. Because every reused Dockerfile installs into `/home/coder`, the layers compose cleanly. Versions are **composite**: components are listed in the fixed order `go`-`rust`-`zig`-`jdk`.

| Image                    | Version                       | Reuses Dockerfile                           | Parent                                   | Result                                             |
| ------------------------ | ----------------------------- | ------------------------------------------- | ---------------------------------------- | -------------------------------------------------- |
| `extra/go-rust`          | `1.27.1-stable`               | `default/rust/stable/Dockerfile`            | `default/go/1.27.1`                      | Go + Rust                                          |
| `extra/go-rust-zig`      | `1.27.1-stable-0.14.0`        | `default/rust-zig/stable-0.14.0/Dockerfile` | `extra/go-rust/1.27.1-stable`            | Go + Rust + Zig                                    |
| `extra/go-rust-zig-java` | `1.27.1-stable-0.14.0-jdk11`  | `default/java/Dockerfile`                   | `extra/go-rust-zig/1.27.1-stable-0.14.0` | Go + Rust + Zig + JDK 11/Maven/Gradle              |
| `extra/go-rust-zig-java` | `1.27.1-stable-0.14.0-jdk17`  | `default/java/Dockerfile`                   | `extra/go-rust-zig/1.27.1-stable-0.14.0` | Go + Rust + Zig + JDK 17/Maven/Gradle              |
| `extra/go-rust-zig-java` | `1.27.1-stable-0.14.0-jdk21`  | `default/java/Dockerfile`                   | `extra/go-rust-zig/1.27.1-stable-0.14.0` | Go + Rust + Zig + JDK 21/Maven/Gradle              |
| `extra/go-rust-zig-java` | `1.27.1-stable-0.14.0-jdkall` | `default/java/Dockerfile`                   | `extra/go-rust-zig/1.27.1-stable-0.14.0` | Go + Rust + Zig + all JDKs 8/11/17/21/26 + GraalVM |

Image names come from the key basename (no `IMAGE=` override is set), so the full workspace is pulled as `go-rust-zig-java`.

## `.meta` examples

```text
# extra/go-rust/1.27.1-stable/.meta
DOCKERFILE=default/rust/stable/Dockerfile
PARENT=default/go/1.27.1
ARG_RUST_VER=stable
```

```text
# extra/go-rust-zig/1.27.1-stable-0.14.0/.meta
DOCKERFILE=default/rust-zig/stable-0.14.0/Dockerfile
PARENT=extra/go-rust/1.27.1-stable
ARG_ZIG_VER=0.14.0
ARG_ZIGBUILD_VER=0.23.3
```

```text
# extra/go-rust-zig-java/1.27.1-stable-0.14.0-jdkall/.meta
DOCKERFILE=default/java/Dockerfile
PARENT=extra/go-rust-zig/1.27.1-stable-0.14.0
ARG_JAVA_VERS=8.0.504+1-tem 11.0.32+1.1-tem 17.0.20-tem 21.0.12+1.1-tem 26.0.2+1.1-tem
ARG_JAVA_DEFAULT=21.0.12+1.1-tem
ARG_GRAALVM_VER=21.0.12-graal
ARG_MAVEN_VER=3.9.16
ARG_GRADLE_VER=9.7.1
```

## What each layer adds

- **`extra/go-rust`** = [Go](go.md) image + the [Rust](rust.md) toolchain (rustup, gnu/musl targets, C toolchain) laid on top.
- **`extra/go-rust-zig`** = `go-rust` + the [rust-zig](rust-zig.md) layer (Zig + cargo-zigbuild) — full Rust↔Zig cross-compilation.
- **`extra/go-rust-zig-java`** = `go-rust-zig` + the [java](java.md) layer (SDKMAN JDK + Maven + Gradle). The `jdkNN` suffix selects a single JDK; `jdkall` bundles 8/11/17/21/26 + GraalVM.

The toolchain details (ENV, install layout, size cleanup) are identical to the corresponding `default/*` image — see [Go](go.md), [Rust](rust.md), [Rust+Zig](rust-zig.md), [Java](java.md).

---

Pull (example): `docker pull ghcr.io/alexundros/agents-docker-images/go-rust-zig-java:1.27.1-stable-0.14.0-jdk21`

Back to [image contents](../image-contents.md) · [README](../../README.md)
