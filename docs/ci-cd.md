# CI/CD (GitHub Actions)

> The automated build-and-publish lifecycle. For how the build system and `maketool.sh` work underneath, see [build-system.md](build-system.md); for what the images contain, see [image-contents.md](image-contents.md).

Three workflows live under `.github/workflows/`:

| Workflow         | File                 | Purpose                                                         |
| ---------------- | -------------------- | --------------------------------------------------------------- |
| `build-images`   | `build-images.yml`   | Build and publish images (change-aware, idempotent)             |
| `cleanup-images` | `cleanup-images.yml` | Manual GHCR cleanup: deletes versions absent from the keep list |
| `dump-contexts`  | `dump-contexts.yml`  | Debug helper: dumps the full GitHub/runner environment          |

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

- `runs-on: ubuntu-latest`, `timeout-minutes: 30`.
- Permissions: `contents: read`, `packages: write` (needed to push to GHCR).
- `actions/checkout@v4` with `fetch-depth: 0` (full history is required to diff against the previous commit).

### Step 1 — Determine Options

Sets three outputs (`do_push`, `push_latest`, `force_rebuild`):

- On `push`: `do_push=true` (publish is the point of the trigger); the two optional flags stay `false`.
- On `workflow_dispatch`: values are taken directly from the manual inputs.

### Step 2 — Detect changed images

Only meaningful on `push`; on manual runs the mode is `all` (everything is rebuilt).

For pushes the workflow:

1. Lists every image ID (`./maketool.sh ids`).
2. Diffs `dockerfiles/` between the previous commit (`github.event.before`) and the pushed SHA (`git diff --name-only`), mapping each changed file to its image ID.
   - A fresh branch (all-zero `before` SHA) is treated as "everything changed".
   - If `before` names a commit that is not in the repo (history rewritten by force-push/rebase), the step fails fast with an explicit error — re-run the workflow via `workflow_dispatch` (mode `all`) after such pushes.
3. **Transitively closes over dependents** using `./maketool.sh parents` (`<id> <parent>` lines): any image whose parent is in the wanted set is added too, iterated until stable. A change to `default/rust`, for example, pulls in `rust-zig`, `go-rust`, `go-rust-zig` and all four `go-rust-zig-java` combinations.
4. Emits the sorted comma-separated ID list as the `ids` output (empty when no image was touched — the build/push steps then no-op).

### Step 3 — Validate

`./maketool.sh validate` — layout sanity, duplicate names, `PARENT` references, Dockerfile existence.

### Step 4 — Build (build-only)

When `do_push != true`: builds the affected images in one call with `./maketool.sh build <id> ...` (or `./maketool.sh build` for mode `all`), passing OCI labels:

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

When `do_push == true`: runs `./maketool.sh release <id> ...` (changed mode) or `./maketool.sh release` (all mode) with:

```bash
REGISTRY="${{ vars.REGISTRY }}"
NAMESPACE="${{ github.repository }}"
PUSH_LATEST="${{ steps.vars.outputs.push_latest }}"
ALLOW_OVERWRITE="${{ steps.vars.outputs.force_rebuild }}"
OCI_SOURCE=... OCI_REVISION="${{ github.sha }}"
```

`release` probes the registry first (`docker manifest inspect`) and skips already-published tags, so existing versions are never overwritten unless `force_rebuild` is set.

Both build steps pass `SUMMARY=/tmp/mt-summary.tsv` to `maketool.sh`.

### Step 7 — Job summary

Runs `if: always()`, so it renders even when a build/push failed. Converts `/tmp/mt-summary.tsv` into the GitHub **job summary**: a Markdown table (`Image | Result | Ref`) with one row per processed image plus a `N built / N pushed / N skipped / N failed` count line. If the steps never got to processing images (e.g. detection failure or nothing changed), it shows "No images processed".

---

## `cleanup-images`

Manual-only (`workflow_dispatch`) GHCR housekeeping: removes package versions that are no longer
part of the kept set — stale tags (renamed/old versions) and, optionally, untagged versions
(dangling digests left by force rebuilds).

### Keep list

`dockerfiles/keep-images.txt` — one `<package>:<tag>` per line (registry/namespace prefix omitted),
`#` comments allowed, `<package>:*` keeps an entire package. Only packages mentioned in the file are
scanned; everything else in the namespace is left alone.

### Inputs

| Input             | Default | Meaning                                             |
| ----------------- | ------- | --------------------------------------------------- |
| `dry_run`         | `true`  | Print the plan into the job summary, delete nothing |
| `delete_untagged` | `true`  | Also delete versions that carry no tags             |

### Behaviour

1. Parses the keep file; refuses to run on an empty or malformed list.
2. **Safety gate**: every ref produced by `./maketool.sh remote-refs` (the current tree) must appear
   in the keep file — otherwise the workflow aborts, so forgotten keep updates can't delete live tags.
3. Resolves the GHCR API scope (`/users/<owner>` vs `/orgs/<owner>`) by probing the first package.
   Note: images pushed as `ghcr.io/<owner>/<repo>/<image>` are named `<repo>/<image>` in the API
   (the slash is `%2F`-encoded); the keep file uses the short `<image>` part, the workflow adds the prefix.
4. Lists all versions of each kept package (`gh api .../packages/container/<pkg>/versions --paginate`)
   and marks versions whose tags are all absent from the keep set (untagged ones per input).
   A version with *any* kept tag survives (tags share one version id).
5. Renders the plan as a table in the job summary (`Package | Version | Action`) with
   scanned/deleted/kept counters, then executes `DELETE` for each planned version unless `dry_run`.
6. Refuses to proceed if the keep list matches nothing in the registry (mass-deletion guard).

Uses the workflow's `GITHUB_TOKEN` (`packages: write`). If GitHub rejects the deletes (e.g. versions
owned by another principal), store a PAT with `delete:packages` in a secret and pass it as `GH_TOKEN`.

Typical flow after renaming a version: ship the new tags with `build-images`, add them to the keep
file (remove the old lines), run `cleanup-images` with `dry_run=true`, eyeball the table, re-run with
`dry_run=false`.

---

## `dump-contexts`

Manual-only (`workflow_dispatch`) debugging workflow. Prints:

- **All environment variables** (`env | sort`), docker registry config and docker socket availability, git config with origins.
- **OS & shell info** — `SHELL`, bash path, UID/GID, `uname -a`, `/etc/os-release`, default shell from passwd, available shells.
- **GitHub / job / steps / runner / strategy / matrix contexts** as JSON (`toJson(...)`).

Use it to inspect runner state when debugging builds: registry auth, docker setup, shell configuration, or injected secrets/vars.

---

Back to [README](../README.md).
