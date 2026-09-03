# Build system & Makefile

> How the data-driven build system works, the full Makefile reference, and how to add a new image. For what each image contains, see [image-contents.md](image-contents.md).

---

## Quick start

```bash
# Build every image locally
make build

# Run the Java-capable full stack image
docker run --rm -it <image-prefix>/go-rust-zig-java:0.1

# Start a session in a Go image
docker run --rm -it <image-prefix>/go:v0 bash
```

Every image runs `info-banner.sh` by default, which prints the environment, installed tools, and system info.

---

## How the build system works

The Makefile is the engine. Images live under `dockerfiles/` as `<namespace>/<key>/<version>/`, and each directory contains:

```
dockerfiles/<namespace>/<key>/<version>/
├── .meta          # ← the main file (required, drives everything)
└── Dockerfile     # optional — can be shared/reused via DOCKERFILE=
```

### Discovery

Images are **discovered from `.meta` files**. At parse time the Makefile walks `$(DF_DIR)` (`dockerfiles` by default) for every `.meta` at depth ≥ 3, producing image **IDs** of the form `<key>/<version>` (e.g. `extra/go-rust-zig-java/0.1`). IDs are ordered with `$(sort)`, so builds are deterministic.

Everything downstream is derived from those IDs — build targets, aggregates, push/save/load, and CI.

### `.meta` reference

| Key           | Purpose                                                                                                 |
| ------------- | ------------------------------------------------------------------------------------------------------- |
| `PARENT=`     | Image this image is built on (`<key>/<version>`). Builds parents first and passes them as `BASE_IMAGE`. |
| `DOCKERFILE=` | Path to a Dockerfile relative to `dockerfiles/`. If unset, the conventional `<id>/Dockerfile` is used.  |
| `ARG_<NAME>=` | Converted to `--build-arg <NAME>=<value>` for `docker build`.                                           |
| `IMAGE=`      | Optional image-name override (used to disambiguate duplicate basenames).                                |

Notes:

- `PARENT` values are parsed as `<key>/<version>` — the version is the last path component.
- Only scalar (single-line) values are read; inline `#` comments are stripped.
- The layout is validated at parse time with `make validate`: layout sanity, duplicate image names, `PARENT` references, and Dockerfile existence (resolved through `DOCKERFILE=`).

### Refs & tags

- With `REGISTRY` + `NAMESPACE` set, images are tagged as `<registry>/<namespace>/<name>:<version>` (remote refs used for builds, pushes and parents).
- Otherwise images are tagged locally as `<dirname>/<name>:<version>` (local build-only mode — no registry probes).
- `:latest` is only added when `PUSH_LATEST=true`.
- `IMAGE_PREFIX` prepends a prefix to every image name.

---

## Makefile reference

Run `make help` for the full list.

| Target                           | Description                                                        |
| -------------------------------- | ------------------------------------------------------------------ |
| `make validate`                  | Validate layout, duplicate names, PARENT refs and Dockerfile paths |
| `make images`                    | List all discovered images with their refs and parents             |
| `make build`                     | Build all images locally                                           |
| `make build-<id>`                | Build one image (e.g. `build-extra/go-rust-zig-java/0.1`)          |
| `make build-<key>`               | Build all versions of a key (e.g. `build-extra/go-rust-zig-java`)  |
| `make release`                   | Build **and push** every image (skips published tags)              |
| `make release-<id>`              | Build and push one image                                           |
| `make push`                      | Push already-built images (skips published tags)                   |
| `make login`                     | Log in to the registry                                             |
| `make save` / `make load`        | Export/import images to/from `dist/*.tar.gz`                       |
| `make clean` / `make clean-dist` | Remove built images / the `dist/` directory                        |

### Build behaviour

- **Dependency ordering** — `build-<id>` depends on `build-<parent>` (transitively), so parents are always built first.
- **Parent image** — the parent's tag is passed to the Dockerfile as `--build-arg BASE_IMAGE=...`. Dockerfiles declare it as `ARG BASE_IMAGE=scratch` / `ARG BASE_IMAGE=debian:12-slim`.
- **Skips** — when remote refs are in use, `build`, `push` and `release` first probe the registry (`docker manifest inspect`). Already-published tags are skipped unless `ALLOW_OVERWRITE=true`; probe errors are fail-closed (with hinting messages for auth/TLS failures).
- **Aggregates** — `build-<key>` builds every version of a key (emitted only for keys that don't clash with a single ID).

### Key variables

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
| `REGISTRY_USER` / `REGISTRY_TOKEN` | —             | Credentials for `make login`                                                        |

### Examples

```bash
# Local build of a single image
make build-extra/go-rust-zig-java/0.1

# Build everything
make build

# Publish new versions to a registry (existing tags are skipped)
make release REGISTRY=ghcr.io NAMESPACE=acme

# Force-rebuild + update :latest tags
make release REGISTRY=ghcr.io NAMESPACE=acme PUSH_LATEST=true ALLOW_OVERWRITE=true

# Export / import images for air-gapped transfer
make save
make load
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
   make validate
   make build-<namespace>/<key>/<version>
   ```

The image is automatically picked up by discovery, the aggregate targets, `save`/`load`, and CI.

### Rules of thumb

- Point `PARENT` at an already-published or already-built image (`<key>/<version>`).
- Keep version directories immutable — bump by adding a new version, never by overwriting.
- If two images would share a basename (e.g. two `java` keys in different namespaces), set a distinct `IMAGE=` in one of their `.meta` files.

---

Back to [README](../README.md).
