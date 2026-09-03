# CI/CD (GitHub Actions)

> The automated build-and-publish lifecycle. For how the build system and Makefile work underneath, see [build-system.md](build-system.md); for what the images contain, see [image-contents.md](image-contents.md).

Two workflows live under `.github/workflows/`:

| Workflow        | File                | Purpose                                                |
| --------------- | ------------------- | ------------------------------------------------------ |
| `build-images`  | `build-images.yml`  | Build and publish images (change-aware, idempotent)    |
| `dump-contexts` | `dump-contexts.yml` | Debug helper: dumps the full GitHub/runner environment |

---

## `build-images`

Handles the full build-and-publish lifecycle.

### Triggers

- **`push`** to `main` when `dockerfiles/**` changes — builds **and publishes** only the new/changed versions (existing tags are never overwritten).
- **`workflow_dispatch`** (manual) with inputs:
  - `push` — publish to the registry (default `true`); otherwise build-only;
  - `push_latest` — also update `:latest` tags (default `false`);
  - `force_rebuild` — rebuild everything even if already published (default `false`).

### Job setup

- `runs-on: ubuntu-latest`, `timeout-minutes: 15`.
- Permissions: `contents: read`, `packages: write` (needed to push to GHCR).
- `actions/checkout@v4` with `fetch-depth: 0` (full history is required to diff against the previous commit).

### Step 1 — Determine Options

Sets three outputs (`do_push`, `push_latest`, `force_rebuild`):

- On `push`: `do_push=true` (publish is the point of the trigger); the two optional flags stay `false`.
- On `workflow_dispatch`: values are taken directly from the manual inputs.

### Step 2 — Detect changed images

Only meaningful on `push`; on manual runs the mode is `all` (everything is rebuilt).

For pushes the workflow:

1. Lists every image ID (`make -s _ids`).
2. Diffs `dockerfiles/` between the previous commit (`github.event.before`) and the pushed SHA (`git diff --name-only`), mapping each changed file to its image ID.
   - A fresh branch (all-zero `before` SHA) is treated as "everything changed".
3. **Transitively closes over dependents** using `make -s _parents` (`<id> <parent>` lines): any image whose parent is in the wanted set is added too, iterated until stable. A change to `default/rust`, for example, pulls in `rust-zig`, `go-rust-zig`, `go-rust-zig-java` (0.1 and e1).
4. Emits the sorted comma-separated ID list as the `ids` output.

### Step 3 — Validate

`make validate` — layout sanity, duplicate names, `PARENT` references, Dockerfile existence.

### Step 4 — Build (build-only)

When `do_push != true`: builds the affected images with `make build-<id> ...` (or `make build` for mode `all`), passing OCI labels:

```bash
OCI_SOURCE="${{ github.server_url }}/${{ github.repository }}"
OCI_REVISION="${{ github.sha }}"
```

### Step 5 — Log in

When `do_push == true`, logs in with `docker/login-action@v4`:

- registry: `${{ vars.REGISTRY }}`
- username: `${{ vars.REGISTRY_USER }}`
- password: `${{ secrets.REGISTRY_TOKEN }}`

### Step 6 — Build & push

When `do_push == true`: runs `make release-<id> ...` (changed mode) or `make release ...` (all mode) with:

```bash
REGISTRY="${{ vars.REGISTRY }}"
NAMESPACE="${{ github.repository }}"
PUSH_LATEST="${{ steps.vars.outputs.push_latest }}"
ALLOW_OVERWRITE="${{ steps.vars.outputs.force_rebuild }}"
OCI_SOURCE=... OCI_REVISION="${{ github.sha }}"
```

`release` probes the registry first (`docker manifest inspect`) and skips already-published tags, so existing versions are never overwritten unless `force_rebuild` is set.

---

## `dump-contexts`

Manual-only (`workflow_dispatch`) debugging workflow. Prints:

- **All environment variables** (`env | sort`), docker registry config and docker socket availability, git config with origins.
- **OS & shell info** — `SHELL`, bash path, UID/GID, `uname -a`, `/etc/os-release`, default shell from passwd, available shells.
- **GitHub / job / steps / runner / strategy / matrix contexts** as JSON (`toJson(...)`).

Use it to inspect runner state when debugging builds: registry auth, docker setup, shell configuration, or injected secrets/vars.

---

Back to [README](../README.md).
