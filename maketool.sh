#!/usr/bin/env bash
# ============================================================
# maketool.sh — pure-bash build/publish tool for docker images
#
# Usage: ./maketool.sh <command> [selector ...] [VAR=value ...]
# ============================================================
set -euo pipefail
shopt -s nullglob globstar

# ---- config (env or VAR=value on the command line) ----
: "${DF_DIR:=dockerfiles}"
: "${BUILD_CONTEXT:=.}"
: "${DIST_DIR:=dist}"
: "${IMAGE_PREFIX:=}"
: "${OCI_SOURCE:=}"
: "${OCI_REVISION:=local}"
: "${REGISTRY:=}"
: "${NAMESPACE:=}"
: "${PUSH_LATEST:=false}"
: "${ALLOW_OVERWRITE:=false}"
: "${REGISTRY_USER:=}"
: "${REGISTRY_TOKEN:=}"
: "${SUMMARY:=}"

# accepted VAR=value names (word-boundary checked in parse_args)
CONFIG_VARS=" DF_DIR BUILD_CONTEXT DIST_DIR IMAGE_PREFIX OCI_SOURCE OCI_REVISION \
REGISTRY NAMESPACE PUSH_LATEST ALLOW_OVERWRITE REGISTRY_USER REGISTRY_TOKEN SUMMARY "

declare -a args=() IDS=() KEYS=() ORDER=() VISITED=() STACK=() SELECTED=()
die() { echo "ERROR: $*" >&2; exit 1; }

# ---- argument parsing: <command> [selector ...] VAR=value ... ----
parse_args() {
  local a k v
  for a in "$@"; do
    case "$a" in
      *=*)
        k="${a%%=*}"; v="${a#*=}"
        case "$CONFIG_VARS" in
          *" $k "*) export "$k=$v" ;;
          *) die "unknown variable '$k'" ;;
        esac ;;
      *) args+=("$a") ;;
    esac
  done
  cmd="${args[0]:-help}"
}

# ---- discovery (pure bash: globstar + insertion sort; no external tools) ----
discover() {
  local f rel i j tmp id k
  IDS=()
  while IFS= read -r rel; do IDS+=("$rel"); done < <(
    for f in "$DF_DIR"/**/.meta; do
      [ -f "$f" ] || continue
      rel="${f#"$DF_DIR"/}"; rel="${rel%/.meta}"
      case "$rel" in */*) printf '%s\n' "$rel" ;; esac
    done)
  for ((i = 1; i < ${#IDS[@]}; i++)); do
    tmp="${IDS[$i]}"; j=$((i - 1))
    while [ "$j" -ge 0 ] && [ "${IDS[$j]}" \> "$tmp" ]; do
      IDS[$((j + 1))]="${IDS[$j]}"; j=$((j - 1))
    done
    IDS[$((j + 1))]="$tmp"
  done
  [ "${#IDS[@]}" -gt 0 ] || echo "WARN: no images under '$DF_DIR'" >&2
  KEYS=()
  for id in "${IDS[@]}"; do
    k="$(id_key "$id")"
    contains "$k" "${KEYS[@]}" || KEYS+=("$k")
  done
}

# ---- per-ID accessors ----
meta_path()  { printf '%s' "$DF_DIR/$1/.meta"; }
id_version() { printf '%s' "${1##*/}"; }
id_key()     { printf '%s' "${1%/*}"; }
id_name()    { local k="${1%/*}"; printf '%s' "${k##*/}"; }
parent_of()  { meta_get "$1" PARENT; }

meta_get() { # id KEY -> scalar (first match, inline '#' and trailing ws removed)
  local mp; mp="$(meta_path "$1")"; [ -f "$mp" ] || return 0
  sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*(.*)/\1/p" "$mp" \
    | sed -E 's/[[:space:]]*(#.*)?$//' | head -n1
}

dockerfile_path() { local d; d="$(meta_get "$1" DOCKERFILE)"; printf '%s' "$DF_DIR/${d:-$1/Dockerfile}"; }
img_suffix()      { local s; s="$(meta_get "$1" IMAGE)"; printf '%s' "${s:-$(id_name "$1")}"; }
img_name()        { printf '%s%s' "$IMAGE_PREFIX" "$(img_suffix "$1")"; }
local_ref()       { printf '%s/%s:%s' "$REPO" "$(img_name "$1")" "$(id_version "$1")"; }
remote_ref()      { printf '%s%s:%s' "$REMOTE_PREFIX" "$(img_name "$1")" "$(id_version "$1")"; }
latest_ref()      { printf '%s%s:latest' "$REMOTE_PREFIX" "$(img_name "$1")"; }
artifact_ref()    { [ -n "$REMOTE_PREFIX" ] && remote_ref "$1" || local_ref "$1"; }

img_args() { # ARG_* lines -> "--build-arg\nNAME=value" (one token per line)
  local mp; mp="$(meta_path "$1")"; [ -f "$mp" ] || return 0
  sed -nE 's/^[[:space:]]*ARG_([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*(.*)/--build-arg\n\1=\2/p' "$mp"
}
oci_labels() {
  printf '%s\n' --label "org.opencontainers.image.version=$(id_version "$1")" \
    --label "org.opencontainers.image.source=$OCI_SOURCE" \
    --label "org.opencontainers.image.revision=$OCI_REVISION"
}
contains() { local e; for e in "${@:2}"; do [ "$e" = "$1" ] && return 0; done; return 1; }

# ---- dependency ordering (parents before children; DFS) ----
topo() { # args = start IDs; fills ORDER
  local id
  ORDER=(); VISITED=(); STACK=()
  for id in "$@"; do visit "$id"; done
}
visit() {
  local id="$1" p
  contains "$id" "${STACK[@]}"   && die "circular PARENT dependency involving '$id'"
  contains "$id" "${VISITED[@]}" && return 0
  STACK+=("$id")
  p="$(parent_of "$id")"
  if [ -n "$p" ] && contains "$p" "${IDS[@]}"; then visit "$p"; fi
  STACK=("${STACK[@]:0:$(( ${#STACK[@]} - 1 ))}")
  VISITED+=("$id"); ORDER+=("$id")
}
ensure_selected() { # selectors... -> SELECTED (each is an id or a key)
  local sel id
  SELECTED=()
  for sel in "$@"; do
    if   contains "$sel" "${IDS[@]}"; then SELECTED+=("$sel")
    elif contains "$sel" "${KEYS[@]}"; then
      for id in "${IDS[@]}"; do if [ "$(id_key "$id")" = "$sel" ]; then SELECTED+=("$id"); fi; done
    else die "unknown image/key '$sel'"; fi
  done
}

# ---- registry ----
require_remote() {
  [ -n "$REMOTE_PREFIX" ] && return 0
  printf 'ERROR: set REGISTRY and NAMESPACE, e.g.:\n  %s push REGISTRY=ghcr.io NAMESPACE=acme\n' "$0"
  exit 1
}

probe_exists() { # echoes yes|no|error; info on stderr
  local id="$1" ref out rc=""
  [ -z "$REMOTE_PREFIX" ] && { echo no; return 0; }
  ref="$(remote_ref "$id")"
  out="$(docker manifest inspect "$ref" 2>&1)" || rc=$?
  if [ "${rc:-0}" = "0" ]; then echo "FOUND: $ref already exists" >&2; echo yes; return 0; fi
  case "$out" in
    *"no such manifest"*|*"manifest unknown"*|*"not found"*|*"404"*) echo "OK: $ref is free" >&2; echo no ;;
    *"unauthorized"*|*"authentication required"*|*"denied"*|*"permission denied"*)
      echo "ERROR: $ref - registry needs auth (run '$0 login' first)" >&2; echo error ;;
    *"certificate"*|*"x509"*|*"tls"*|*"unknown authority"*)
      echo "ERROR: $ref - TLS check failed for docker CLI" >&2; echo error ;;
    *) echo "ERROR: $ref - manifest inspect failed: $out" >&2; echo error ;;
  esac
}

# shared gate: true = skip this image (already published)
skip_published() { # id [label]
  { [ "$ALLOW_OVERWRITE" = "true" ] || [ -z "$REMOTE_PREFIX" ]; } && return 1
  local st; st="$(probe_exists "$1")"
  case "$st" in
    yes)   echo "SKIP${2:+ $2}: $(remote_ref "$1") already published"; return 0 ;;
    error) exit 1 ;;
    *)     return 1 ;;
  esac
}

# ---- build / push / release ----
do_build() {
  local id="$1" dfp p
  local -a bargs=() kargs=() labels=() tags=()
  dfp="$(dockerfile_path "$id")"
  mapfile -t kargs  < <(img_args "$id")
  mapfile -t labels < <(oci_labels "$id")
  tags=(-t "$(artifact_ref "$id")")
  if [ -n "$REMOTE_PREFIX" ] && [ "$PUSH_LATEST" = "true" ]; then tags+=(-t "$(latest_ref "$id")"); fi
  p="$(parent_of "$id")"
  bargs=(-f "$dfp")
  [ -z "$p" ] || bargs+=(--build-arg "BASE_IMAGE=$(parent_base "$p")")
  docker build "${bargs[@]}" \
    ${kargs[@]+"${kargs[@]}"} ${labels[@]+"${labels[@]}"} "${tags[@]}" "$BUILD_CONTEXT"
}
# PARENT -> BASE_IMAGE: internal id becomes its ref (remote/local by mode);
# anything else is a foreign docker ref, passed through verbatim.
parent_base() { contains "$1" "${IDS[@]}" && artifact_ref "$1" || printf '%s' "$1"; }

# machine-readable run log: "<id>\t<status>\t<ref>" appended to $SUMMARY
record() { [ -n "$SUMMARY" ] || return 0; printf '%s\t%s\t%s\n' "$1" "$2" "${3:--}" >> "$SUMMARY"; }

build_one() {
  skip_published "$1" && { record "$1" skipped "$(remote_ref "$1")"; return 0; }
  do_build "$1" || { record "$1" failed; exit 1; }
  record "$1" built "$(artifact_ref "$1")"
}
# explicit || return: status must propagate even when errexit is off in the caller's || context
push_only() {
  docker push "$(remote_ref "$1")" || return 1
  [ "$PUSH_LATEST" != "true" ] || docker push "$(latest_ref "$1")" || return 1
}
push_one() {
  skip_published "$1" push && { record "$1" skipped "$(remote_ref "$1")"; return 0; }
  push_only "$1" || { record "$1" failed; exit 1; }
  record "$1" pushed "$(remote_ref "$1")"
}
release_one() {
  skip_published "$1" && { record "$1" skipped "$(remote_ref "$1")"; return 0; }
  do_build "$1" || { record "$1" failed; exit 1; }
  push_only "$1" || { record "$1" failed; exit 1; }
  record "$1" pushed "$(remote_ref "$1")"
}

# ---- commands ----
cmd_help() {
  cat <<EOF
Usage: $(basename "$0") <command> [selector ...] [VAR=value ...]

  help                 Show this help
  validate             Validate layout, duplicate image names and PARENT refs
  ids                  List discovered image IDs
  parents              Print "<id> <parent>" for every ID
  images               List discovered images
  describe <id>        Describe one image
  build [id|key ...]   Build all (or the given images/keys); parents first
  push                 Push images (existing skipped unless ALLOW_OVERWRITE=true)
  release [id|key ...] Build + push, one existence probe per image
  login                Log in to the registry (no-op if REGISTRY is empty)
  save                 Save images to \$DIST_DIR/<image>-<version>.tar.gz
  load                 Load images from \$DIST_DIR/*.tar.gz
  clean                Remove built images
  clean-dist           Remove \$DIST_DIR
  img-suffix <id> | parent-of <id> | dockerfile <id> | remote-ref <id>
  meta-get <id> KEY    Read a scalar from <id>/.meta
  exists <id>          Probe remote existence (prints yes|no|error)
  require-remote       Exit 1 unless REGISTRY and NAMESPACE are set

Notes:
  PARENT in .meta is either an internal <key>/<version> id (dependency edge, ref resolved by the tool)
  or any foreign docker ref (alpine:3.19, ghcr.io/x/y:v1) passed to the Dockerfile as BASE_IMAGE verbatim.

Config (env or VAR=value): DF_DIR BUILD_CONTEXT DIST_DIR IMAGE_PREFIX
  OCI_SOURCE OCI_REVISION REGISTRY NAMESPACE PUSH_LATEST ALLOW_OVERWRITE
  REGISTRY_USER REGISTRY_TOKEN SUMMARY
EOF
}

cmd_validate() {
  local id key ver suffix dfp p pdfp err=0
  declare -A seen_key=() seen_id=()
  for id in "${IDS[@]}"; do
    case "$id" in */*) ;; *) echo "ERROR: invalid layout '$id'"; err=1; continue ;; esac
    key="$(id_key "$id")"; ver="$(id_version "$id")"
    if [ -z "$ver" ] || [ "$key" = "$id" ]; then echo "ERROR: missing version in '$id'"; err=1; continue; fi
    suffix="$(img_suffix "$id")"
    if [ -n "${seen_key[$suffix]:-}" ] && [ "${seen_key[$suffix]}" != "$key" ]; then
      echo "ERROR: duplicate image name '$suffix' from '$id' and '${seen_id[$suffix]}'."
      echo "       Set a distinct IMAGE= in one of their .meta files."; err=1
    else seen_key[$suffix]="$key"; seen_id[$suffix]="$id"; fi
  done
  for id in "${IDS[@]}"; do
    dfp="$(dockerfile_path "$id")"
    [ -f "$dfp" ] || { echo "ERROR: '$id' has no Dockerfile '$dfp' (set DOCKERFILE= in .meta)"; err=1; }
    p="$(parent_of "$id")"; [ -z "$p" ] && continue
    if contains "$p" "${IDS[@]}"; then
      pdfp="$(dockerfile_path "$p")"
      [ -f "$pdfp" ] || { echo "ERROR: PARENT '$p' (from '$id') has no Dockerfile '$pdfp'"; err=1; }
    elif case "$p" in *[[:space:]]*) true ;; *) false ;; esac; then
      echo "ERROR: PARENT='$p' in '$id/.meta' contains whitespace"; err=1
    elif case "$p" in */*) contains "${p%/*}" "${KEYS[@]}" ;; *) false ;; esac; then
      echo "ERROR: PARENT='$p' in '$id/.meta' looks like an internal id but is unknown"; err=1
    fi
  done
  if [ "$err" = "0" ]; then echo "validate: OK (${#IDS[@]} image(s))"; else exit 1; fi
}

cmd_ids()     { local id; for id in "${IDS[@]}"; do printf '%s\n' "$id"; done; }
cmd_parents() { local id; for id in "${IDS[@]}"; do printf '%s %s\n' "$id" "$(parent_of "$id")"; done; }
describe_one() {
  local p dep; p="$(parent_of "$1")"; dep=""; [ -n "$p" ] && dep=" (parent: $p)"
  printf '  %-36s -> %s%s\n' "$1" "$(artifact_ref "$1")" "$dep"
}
cmd_images()   { local id; for id in "${IDS[@]}"; do describe_one "$id"; done; }
cmd_describe() { describe_one "${args[1]}"; }

cmd_img_suffix() { printf '%s\n' "$(img_suffix "${args[1]}")"; }
cmd_parent_of()  { printf '%s\n' "$(parent_of "${args[1]}")"; }
cmd_dockerfile() { printf '%s\n' "$(dockerfile_path "${args[1]}")"; }
cmd_remote_ref() { printf '%s\n' "$(remote_ref "${args[1]}")"; }
cmd_exists()     { probe_exists "${args[1]}"; }
cmd_meta_get()   { printf '%s\n' "$(meta_get "${args[1]}" "${args[2]}")"; }

build_seq() { # selectors... -> ORDER (no selectors = all images, validated)
  if [ "$#" -eq 0 ]; then cmd_validate; topo "${IDS[@]}"; else ensure_selected "$@"; topo "${SELECTED[@]}"; fi
}
cmd_build()   { local id; build_seq "$@"; for id in "${ORDER[@]}"; do build_one "$id"; done; }
cmd_release() { local id; require_remote; build_seq "$@"; for id in "${ORDER[@]}"; do release_one "$id"; done; }
cmd_push()    { local id; for id in "${IDS[@]}"; do push_one "$id"; done; }

cmd_login() { [ -n "$REGISTRY" ] || { echo "SKIP login: REGISTRY is not set"; return 0; }
  echo "$REGISTRY_TOKEN" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin; }

cmd_save() {
  local id ref out; mkdir -p "$DIST_DIR"
  for id in "${IDS[@]}"; do
    ref="$(artifact_ref "$id")"; out="$DIST_DIR/$(img_name "$id")-$(id_version "$id").tar.gz"
    echo "Saving $ref -> $out"; docker save "$ref" | gzip > "$out"
  done
}
cmd_load() {
  local f files=("$DIST_DIR"/*.tar.gz)
  [ "${#files[@]}" -gt 0 ] || { echo "No files in $DIST_DIR/*.tar.gz"; return 0; }
  for f in "${files[@]}"; do echo "Loading $f"; gunzip -c "$f" | docker load; done
}
cmd_clean() {
  local id ref refs=()
  for id in "${IDS[@]}"; do
    refs=("$(artifact_ref "$id")")
    [ -z "$REMOTE_PREFIX" ] || refs+=("$(latest_ref "$id")")
    for ref in "${refs[@]}"; do docker rmi -f "$ref" 2>/dev/null || true; done
  done
}

need_arg()  { [ -n "${args[1]:-}" ] || die "usage: $0 $1 <id>"; }
need_arg2() { [ -n "${args[2]:-}" ] || die "usage: $0 $1 <id> KEY"; }

# ---- main ----
parse_args "$@"
REPO="$(basename "$PWD")"
REMOTE_PREFIX=""
if [ -n "$REGISTRY" ] && [ -n "$NAMESPACE" ]; then REMOTE_PREFIX="$REGISTRY/$NAMESPACE/"; fi

case "$cmd" in
  help|-h|--help)  cmd_help ;;
  validate)        discover; cmd_validate ;;
  ids)             discover; cmd_ids ;;
  parents)         discover; cmd_parents ;;
  images)          discover; cmd_images ;;
  describe)        need_arg describe; discover; cmd_describe ;;
  img-suffix)      need_arg img-suffix; discover; cmd_img_suffix ;;
  parent-of)       need_arg parent-of; discover; cmd_parent_of ;;
  dockerfile)      need_arg dockerfile; discover; cmd_dockerfile ;;
  remote-ref)      need_arg remote-ref; discover; cmd_remote_ref ;;
  meta-get)        need_arg meta-get; need_arg2 meta-get; discover; cmd_meta_get ;;
  exists)          need_arg exists; discover; cmd_exists ;;
  all|build)       discover; cmd_build "${args[@]:1}" ;;
  build-*)         discover; cmd_build "${cmd#build-}" ;;
  push)            discover; require_remote; cmd_push ;;
  release)         discover; cmd_release "${args[@]:1}" ;;
  release-*)       discover; cmd_release "${cmd#release-}" ;;
  login)           cmd_login ;;
  save)            discover; cmd_save ;;
  load)            discover; cmd_load ;;
  clean)           discover; cmd_clean ;;
  clean-dist)      rm -rf "$DIST_DIR" ;;
  require-remote)  require_remote ;;
  *)               die "unknown command '$cmd' (try '$0 help')" ;;
esac
