# Build system & maketool.sh

> How the data-driven build system works, the `.meta` reference, the full command reference, and how to add a new image. For what each image contains, see [image-contents.md](image-contents.md).

---

## Quick start

```bash
# Build every image locally
./maketool.sh build

# Run the Java-capable full stack image
docker run --rm -it <image-prefix>/go-rust-zig-java:0.1

# Start a session in a Go image
docker run --rm -it <image-prefix>/go:v0 bash
```

Every image runs `info-banner.sh` by default, which prints the environment, installed tools, and system info on start.

---

## How the build system works

`maketool.sh` is the engine — a single pure-bash script (bash ≥ 4, no make, no external `find`/`sort`). Images live under `dockerfiles/` as `<namespace>/<key>/<version>/`, and each directory contains:

```
dockerfiles/<namespace>/<key>/<version>/
├── .meta          # ← the main file (required, drives everything)
└── Dockerfile     # optional — can be shared/reused via DOCKERFILE=
```

### Discovery

Images are **discovered from `.meta` files**. Every command walks `$DF_DIR` (`dockerfiles` by default) with bash globstar for any `.meta` at least two directories deep, producing image **IDs** of the form `<key>/<version>` (e.g. `extra/go-rust-zig-java/0.1`). IDs are sorted inside the script, so builds are deterministic.

Everything downstream is derived from those IDs — build order, aggregates, push/save/load, and CI.

### `.meta` reference

| Key           | Purpose                                                                                                                                                                                                            |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `PARENT=`     | Image this image is built on. Either an internal `<key>/<version>` id (built first, its ref passed as `BASE_IMAGE`) **or** a foreign docker ref (`alpine:3.19`, `ghcr.io/o/r:v1`) passed to `BASE_IMAGE` verbatim. |
| `DOCKERFILE=` | Path to a Dockerfile relative to `dockerfiles/`. If unset, the conventional `<id>/Dockerfile` is used.                                                                                                             |
| `ARG_<NAME>=` | Converted to `--build-arg <NAME>=<value>` for `docker build`.                                                                                                                                                      |
| `IMAGE=`      | Optional image-name override (used to disambiguate duplicate basenames).                                                                                                                                           |

Notes:

- An internal `PARENT` id must exist in discovery — a value like `default/go/v9` with no such version fails `validate` (typo protection). A value that is not an internal id is treated as an external ref: no dependency edge, no build of the parent, `docker build` resolves it.
- Only scalar (single-line) values are read; inline `#` comments are stripped.
- The layout is validated with `./maketool.sh validate`: layout sanity, duplicate image names, `PARENT` references, and Dockerfile existence (resolved through `DOCKERFILE=`).

### Refs & tags

- With `REGISTRY` + `NAMESPACE` set, images are tagged as `<registry>/<namespace>/<name>:<version>` (remote refs used for builds, pushes and parents).
- Otherwise images are tagged locally as `<dirname>/<name>:<version>`, where `<dirname>` is the name of the current working directory (local build-only mode — no registry probes).
- `:latest` is only added when `PUSH_LATEST=true`.
- `IMAGE_PREFIX` prepends a prefix to every image name.

---

## Using maketool.sh for your own images

The script is not tied to this repository — it discovers whatever lives under `DF_DIR`
(`dockerfiles/` by default). To build your own layered images with it:

1. In **your** repo, create the same layout: `dockerfiles/<namespace>/<key>/<version>/`
   with a `.meta` (see [.meta reference](#meta-reference)) and a `Dockerfile`.

2. Run our script directly from GitHub, from your repo root — nothing is installed:

   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/alexundros/agents-docker-images/main/maketool.sh) build
   ```

   or vendor a pinned copy into your project:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/alexundros/agents-docker-images/main/maketool.sh -o maketool.sh
   chmod +x maketool.sh
   ./maketool.sh validate
   ./maketool.sh release REGISTRY=ghcr.io NAMESPACE=you/your-images
   ```

Notes:

- Requires **bash ≥ 4** (Git-Bash/MSYS2 on Windows) and docker in `PATH`.
- Run from the directory that contains your `dockerfiles/` — or point the tool elsewhere:
  `... maketool.sh build DF_DIR=path/to/images`.
- Prefer pinning the script version (tag or commit SHA in the raw URL) for reproducible builds.
- Your child Dockerfiles should accept the base the same way ours do:
  `ARG BASE_IMAGE=scratch` / `FROM ${BASE_IMAGE}`; external parents pass the ref verbatim.

---

## Command reference

Run `./maketool.sh help` (or just `./maketool.sh`) for the full list.

| Command                                                              | Description                                                        |
| -------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `./maketool.sh validate`                                             | Validate layout, duplicate names, PARENT refs and Dockerfile paths |
| `./maketool.sh ids`                                                  | List discovered image IDs                                          |
| `./maketool.sh parents`                                              | Print `<id> <parent>` for every image                              |
| `./maketool.sh images`                                               | List all discovered images with their refs and parents             |
| `./maketool.sh describe <id>`                                        | Describe one image                                                 |
| `./maketool.sh build`                                                | Build all images locally                                           |
| `./maketool.sh build <sel> ...`                                      | Build one or more images / key aggregates (also `build-<id>` form) |
| `./maketool.sh release`                                              | Build **and push** every image (skips published tags)              |
| `./maketool.sh release <sel> ...`                                    | Build and push the given images (also `release-<id>` form)         |
| `./maketool.sh push`                                                 | Push already-built images (skips published tags)                   |
| `./maketool.sh login`                                                | Log in to the registry                                             |
| `./maketool.sh save` / `load`                                        | Export/import images to/from `dist/*.tar.gz`                       |
| `./maketool.sh clean` / `clean-dist`                                 | Remove built images / the `dist/` directory                        |
| `./maketool.sh img-suffix\|parent-of\|dockerfile\|remote-ref <id>`   | Introspection helpers for CI                                       |
| `./maketool.sh meta-get <id> KEY` / `exists <id>` / `require-remote` | Low-level helpers                                                  |

### Build behaviour

- **Dependency ordering** — `build`/`release` order the selected images by walking `PARENT` transitively (DFS, parents first) and abort on circular references.
- **Parent image** — for an internal parent its ref is resolved per mode (remote or local tag) and passed to the Dockerfile as `--build-arg BASE_IMAGE=...`; for an external `PARENT` the value is passed verbatim. Dockerfiles declare it as `ARG BASE_IMAGE=scratch` / `ARG BASE_IMAGE=debian:12-slim`.
- **Skips** — when remote refs are in use, `build`, `push` and `release` first probe the registry (`docker manifest inspect`). Already-published tags are skipped unless `ALLOW_OVERWRITE=true`; probe errors are fail-closed (with hinting messages for auth/TLS failures).
- **Aggregates** — a `<key>` selector builds every version of that key; `build`/`release` accept multiple selectors in one call (e.g. `./maketool.sh build default/rust extra/go-rust/v0`).

### Key variables

All variables are set via the environment or as trailing `VAR=value` arguments.

| Variable                           | Default       | Description                                                                         |
| ---------------------------------- | ------------- | ----------------------------------------------------------------------------------- |
| `REGISTRY`                         | *(empty)*     | Container registry (e.g. `ghcr.io`). Together with `NAMESPACE` enables remote refs. |
| `NAMESPACE`                        | *(empty)*     | Repository/namespace, e.g. `acme/agents-images`                                     |
| `PUSH_LATEST`                      | `false`       | Also tag/push `:latest`                                                             |
| `ALLOW_OVERWRITE`                  | `false`       | Rebuild/republish existing versions                                                 |
| `OCI_SOURCE` / `OCI_REVISION`      | — / `local`   | OCI labels (`source`, `revision`)                                                   |
| `IMAGE_PREFIX`                     | *(empty)*     | Prefix for image names                                                              |
| `DF_DIR`                           | `dockerfiles` | Directory containing image definitions                                              |
| `BUILD_CONTEXT`                    | `.`           | Docker build context                                                                |
| `REGISTRY_USER` / `REGISTRY_TOKEN` | —             | Credentials for `./maketool.sh login`                                               |

### Examples

```bash
# Local build of a single image
./maketool.sh build extra/go-rust-zig-java/0.1

# Build everything
./maketool.sh build

# Publish new versions to a registry (existing tags are skipped)
./maketool.sh release REGISTRY=ghcr.io NAMESPACE=acme

# Force-rebuild + update :latest tags
./maketool.sh release REGISTRY=ghcr.io NAMESPACE=acme PUSH_LATEST=true ALLOW_OVERWRITE=true

# Export / import images for air-gapped transfer
./maketool.sh save
./maketool.sh load
```

---

## Adding a new image

1. Create `dockerfiles/<namespace>/<key>/<version>/.meta`:

   ```text
   PARENT=default/base/v0

   # Build args passed to the Dockerfile
   ARG_GO_VER=1.26.7
   ```

2. Add a `Dockerfile` next to it — **or** reuse an existing one by setting `DOCKERFILE=`.

3. Verify and build:

   ```bash
   ./maketool.sh validate
   ./maketool.sh build <namespace>/<key>/<version>
   ```

The image is automatically picked up by discovery, the key aggregates, `save`/`load`, and CI.

### Rules of thumb

- Point `PARENT` at an already-published or already-built image (`<key>/<version>`), or at any public docker ref you want as the base.
- Keep version directories immutable — bump by adding a new version, never by overwriting.
- If two images would share a basename (e.g. two `java` keys in different namespaces), set a distinct `IMAGE=` in one of their `.meta` files.

---

Back to [README](../README.md).
