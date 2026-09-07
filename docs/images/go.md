# `default/go` — Go toolchain

`PARENT`: `default/base/12`. Version = Go release (`1.27.1`).

- **Go** (`ARG_GO_VER`) from the official tarball: `https://go.dev/dl/go${GO_VER}.linux-${g_arch}.tar.gz`.
- **Multi-arch**: `amd64` → `amd64`, `arm64` → `arm64`.
- Installed to `/usr/local/go`, then trimmed to a smaller layer:
  - removed: `/usr/local/go/test`, `/usr/local/go/doc`, `/usr/local/go/misc`.
- **ENV**:
  - `GOPATH=/home/coder/go`
  - `PATH=/usr/local/go/bin:/home/coder/go/bin:${PATH}`
- Runs as `coder`.

```text
# dockerfiles/default/go/1.27.1/.meta
PARENT=default/base/12
ARG_GO_VER=1.27.1
```

Bumping Go = new version directory (`go/1.28.0`) + repointing dependents' `PARENT`; older images stay immutable.

---

Pull: `docker pull ghcr.io/alexundros/agents-docker-images/go:1.27.1`

Back to [image contents](../image-contents.md) · [README](../../README.md)
