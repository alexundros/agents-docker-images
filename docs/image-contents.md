# Image contents

> Detailed breakdown of every image and its versions, straight from the Dockerfiles and `.meta` files. For how images are built and published, see [build-system.md](build-system.md).

Each image is defined by a `dockerfiles/<namespace>/<key>/<version>/` directory. The `.meta` file supplies `PARENT` and `ARG_*` build args; the Dockerfile (its own or reused via `DOCKERFILE=`) does the actual install. Image tags reflect the toolchain version — see [version naming](build-system.md#version-naming).

## `default/*`

| Image              | Version(s)                    | Description                                                              | Details                           |
| ------------------ | ----------------------------- | ------------------------------------------------------------------------ | --------------------------------- |
| `default/base`     | `12`                          | Debian 12 slim, CLI/editors/debug tools, Python 3, Node.js 22            | [base.md](images/base.md)         |
| `default/go`       | `1.27.1`                      | Go toolchain from the official tarball, trimmed                          | [go.md](images/go.md)             |
| `default/rust`     | `stable`                      | rustup (minimal profile), gnu + musl targets                             | [rust.md](images/rust.md)         |
| `default/rust-zig` | `stable-0.14.0`               | Zig + cargo-zigbuild on top of Rust                                      | [rust-zig.md](images/rust-zig.md) |
| `default/java`     | `8` `11` `17` `21` `26` `all` | single-JDK images + multi-JDK `all`; one shared parameterized Dockerfile | [java.md](images/java.md)         |

## `extra/*` — combinations

Prebuilt stacks that reuse the `default/*` Dockerfiles via `DOCKERFILE=` and layer them onto richer parents. Composite versions list components in fixed order `go`-`rust`-`zig`-`jdk`.

| Image                    | Version(s)                               | Contents                                  | Details                     |
| ------------------------ | ---------------------------------------- | ----------------------------------------- | --------------------------- |
| `extra/go-rust`          | `1.27.1-stable`                          | Go + Rust                                 | [extra.md](images/extra.md) |
| `extra/go-rust-zig`      | `1.27.1-stable-0.14.0`                   | Go + Rust + Zig                           | [extra.md](images/extra.md) |
| `extra/go-rust-zig-java` | `1.27.1-stable-0.14.0-jdk{11,17,21,all}` | the full Go + Rust + Zig + Java workspace | [extra.md](images/extra.md) |

---

Back to [README](../README.md).
