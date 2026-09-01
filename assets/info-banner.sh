#!/usr/bin/env bash
set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n===== %s =====\n' "$1"; }
tool() {  # tool <label> <cmd> [args...]
    local label=$1 cmd=$2; shift 2
    if have "$cmd"; then
        printf '%-14s %s\n' "$label:" "$("$cmd" "$@" 2>&1 | head -n1)"
    fi
}

section "Environment"
printf '%-14s %s\n' 'Directory:' "$(pwd)"
printf '%-14s %s\n' 'User:'      "$(whoami 2>/dev/null || id -un 2>/dev/null || echo unknown)"
if have hostname; then printf '%-14s %s\n' 'Hostname:' "$(hostname)"; fi
printf '%-14s %s\n' 'Shell:'      "${SHELL:-<unset>}"
printf '%-14s %s\n' 'Bash:'       "$BASH_VERSION"
printf '%-14s %s\n' 'HOME:'       "${HOME:-<unset>}"
printf '%-14s %s\n' 'GOPATH:'     "${GOPATH:-<unset>}"
printf '%-14s %s\n' 'PATH:'       "${PATH:-<unset>}"

section "Tools"
tool 'Node.js' node --version
tool 'npm'     npm --version
tool 'Go'      go version
tool 'Python'  python3 --version
tool 'Git'     git --version
tool 'Rust'    rustc --version
tool 'Cargo'   cargo --version
tool 'Zig'     zig version
tool 'Make'    make --version
tool 'GCC'     gcc --version
tool 'Clang'   clang --version
tool 'curl'    curl --version
tool 'wget'    wget --version
tool 'jq'      jq --version
tool 'OpenSSL' openssl version
tool 'Java'    java -version
if have rustup; then
    printf '%-14s\n' 'Rust targets:'
    rustup target list --installed | sed 's/^/  - /'
fi

section "System"
printf '%-14s %s\n' 'Date:'  "$(date)"
if [ -r /etc/os-release ]; then
    . /etc/os-release
    printf '%-14s %s\n' 'OS:' "${PRETTY_NAME:-${NAME:-unknown}}"
fi
if have uname; then
    printf '%-14s %s\n' 'Kernel:' "$(uname -r)"
    printf '%-14s %s\n' 'Arch:'   "$(uname -m)"
fi
if have nproc; then printf '%-14s %s\n' 'CPU:' "$(nproc) cores"; fi
if have free; then
    printf '%-14s %s\n' 'Memory:' "$(free -h | awk '/^Mem:/ {print $2"/"$3" total/used"}')"
fi
if have df; then
    printf '%-14s %s\n' 'Disk (/):' "$(df -h / | awk 'NR==2 {print $3"/"$2" used ("$5")"}')"
fi
if have uptime; then printf '%-14s %s\n' 'Uptime:' "$(uptime | sed 's/^ *//')"; fi

section "Contents of $(pwd)"
ls -la
