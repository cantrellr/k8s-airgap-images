#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$SCRIPT_DIR/source-lists}"
LIST_DIR="${LIST_DIR:-$SCRIPT_DIR/image-lists}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
CONTAINER_CLI="${CONTAINER_CLI:-}"
FORCE_PULL="false"
DRY_RUN="false"
CONTINUE_ON_ERROR="true"
PUSH_MODE="strip-registry"
TARGET_PREFIX="kubeharbor.dev.kube"
IMAGE_LIST=""
RETRIES="${RETRIES:-3}"

usage() {
  cat <<'EOF'
Usage:
  ./image-airgap.sh organize
  ./image-airgap.sh pull [--list image-lists/all-active-images.list] [--force] [--dry-run]
  ./image-airgap.sh push [--list image-lists/all-active-images.list] [--target REGISTRY/PREFIX] [--mode strip-registry|preserve-registry] [--dry-run]

Wrappers:
  ./organize-image-lists.sh
  ./download-images.sh [pull options]
  ./push-images.sh [push options]

Environment:
  CONTAINER_CLI=docker|podman   Override container client. Defaults to docker, then podman.
  SOURCE_DIR=./source-lists      Source uploaded list directory.
  LIST_DIR=./image-lists         Generated organized list directory.
  LOG_DIR=./logs                 Pull/push result logs.
  RETRIES=3                      Pull/push retry count.

Push modes:
  strip-registry     kubeharbor.dev.kube/rancher/rancher:v2.14.2
  preserve-registry  kubeharbor.dev.kube/docker.io/rancher/rancher:v2.14.2
EOF
}

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
err() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

need_container_cli() {
  if [[ -n "$CONTAINER_CLI" ]]; then
    command -v "$CONTAINER_CLI" >/dev/null 2>&1 || { err "CONTAINER_CLI=$CONTAINER_CLI was not found in PATH"; exit 1; }
    return
  fi
  if command -v docker >/dev/null 2>&1; then
    CONTAINER_CLI="docker"
  elif command -v podman >/dev/null 2>&1; then
    CONTAINER_CLI="podman"
  else
    err "Neither docker nor podman was found in PATH. Install one, or set CONTAINER_CLI."
    exit 1
  fi
}

trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

has_registry() {
  local image="$1" first
  first="${image%%/*}"
  [[ "$first" == "localhost" || "$first" == *.* || "$first" == *:* ]]
}

normalize_image() {
  local image
  image="$(trim "$1")"
  image="${image%%#*}"
  image="$(trim "$image")"
  [[ -z "$image" ]] && return 1
  if has_registry "$image"; then
    printf '%s\n' "$image"
  else
    printf 'docker.io/%s\n' "$image"
  fi
}

registry_of() {
  local image="$1"
  if has_registry "$image"; then
    printf '%s\n' "${image%%/*}"
  else
    printf 'docker.io\n'
  fi
}

without_registry() {
  local image="$1"
  if has_registry "$image"; then
    printf '%s\n' "${image#*/}"
  else
    printf '%s\n' "$image"
  fi
}

is_bitnami() {
  local image="$1"
  [[ "$image" == docker.io/bitnami/* || "$image" == bitnami/* ]]
}

is_dhi() {
  local image="$1"
  [[ "$image" == dhi.io/* || "$image" == docker.io/cantrellcloud/dhi-* || "$image" == docker.io/*/dhi-* ]]
}

is_ironbank() {
  local image="$1"
  [[ "$image" == registry1.dso.mil/* ]]
}

is_nginx_private() {
  local image="$1"
  [[ "$image" == docker-registry.nginx.com/* ]]
}

sort_unique_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    LC_ALL=C sort -u "$file" -o "$file"
  else
    : > "$file"
  fi
}

organize_lists() {
  mkdir -p "$LIST_DIR" "$LOG_DIR"
  if ! command -v python3 >/dev/null 2>&1; then
    err "python3 is required for the organize step. Install python3 or pre-generate image-lists on another host."
    exit 1
  fi
  SOURCE_DIR="$SOURCE_DIR" LIST_DIR="$LIST_DIR" python3 "$SCRIPT_DIR/tools/organize_image_lists.py"
}

read_yes_no() {
  local prompt="$1" default="${2:-n}" reply
  local suffix='[y/N]'
  [[ "$default" == "y" ]] && suffix='[Y/n]'
  read -r -p "$prompt $suffix: " reply || reply=""
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy]$ || "$reply" =~ ^[Yy][Ee][Ss]$ ]]
}

prompt_login() {
  local registry="$1" label="$2" default_answer="${3:-n}"
  log "Credential gate: $label ($registry)"
  if read_yes_no "Login to $registry now? Choose no to skip credentials for this registry." "$default_answer"; then
    local user pass
    read -r -p "  Username for $registry: " user
    read -r -s -p "  Password/token for $registry: " pass
    printf '\n'
    if [[ -z "$user" || -z "$pass" ]]; then
      warn "Username or password/token was empty; skipping login for $registry"
      return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
      log "DRY RUN: would run '$CONTAINER_CLI login $registry -u <user> --password-stdin'"
    else
      printf '%s' "$pass" | "$CONTAINER_CLI" login "$registry" -u "$user" --password-stdin
    fi
  else
    warn "Skipped login for $registry"
  fi
}

ensure_organized() {
  if [[ ! -f "$LIST_DIR/all-active-images.list" ]]; then
    organize_lists
  fi
}

append_unique() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -Fxq "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

pull_one() {
  local image="$1" success_log="$2" failed_log="$3"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN: would pull $image"
    return 0
  fi
  if [[ "$FORCE_PULL" != "true" ]] && "$CONTAINER_CLI" image inspect "$image" >/dev/null 2>&1; then
    log "SKIP existing local image: $image"
    append_unique "$success_log" "$image"
    return 0
  fi

  local attempt
  for attempt in $(seq 1 "$RETRIES"); do
    log "Pulling [$attempt/$RETRIES]: $image"
    if "$CONTAINER_CLI" pull "$image"; then
      append_unique "$success_log" "$image"
      return 0
    fi
    sleep $(( attempt * 2 ))
  done

  err "Pull failed after $RETRIES attempts: $image"
  append_unique "$failed_log" "$image"
  [[ "$CONTINUE_ON_ERROR" == "true" ]] && return 0 || return 1
}

pull_images() {
  need_container_cli
  ensure_organized
  local list="${IMAGE_LIST:-$LIST_DIR/all-active-images.list}"
  [[ -f "$list" ]] || { err "Image list not found: $list"; exit 1; }
  mkdir -p "$LOG_DIR"

  # Required by design: ask Docker Hub and registry1 first, and allow each to be skipped.
  prompt_login "docker.io" "Docker Hub / Docker Hardened Images hosted on Docker Hub"
  prompt_login "registry1.dso.mil" "Iron Bank / registry1.dso.mil"

  # Additional auth-gated registries detected in the provided resources.
  if grep -q '^dhi.io/' "$LIST_DIR/10-docker-hardened-images.list" 2>/dev/null; then
    prompt_login "dhi.io" "Docker Hardened Images registry"
  fi
  if [[ -s "$LIST_DIR/30-nginx-registry-images.list" ]]; then
    prompt_login "docker-registry.nginx.com" "NGINX private registry"
  fi

  local stamp success_log failed_log image total current
  stamp="$(date '+%Y%m%d-%H%M%S')"
  success_log="$LOG_DIR/pull-success.list"
  failed_log="$LOG_DIR/pull-failed-$stamp.list"
  : > "$failed_log"
  total="$(grep -cvE '^\s*(#|$)' "$list" || true)"
  current=0

  while IFS= read -r image || [[ -n "$image" ]]; do
    image="$(trim "$image")"
    [[ -z "$image" || "$image" == \#* ]] && continue
    current=$((current + 1))
    log "Pull progress $current/$total"
    pull_one "$image" "$success_log" "$failed_log"
  done < "$list"

  sort_unique_file "$success_log"
  sort_unique_file "$failed_log"
  log "Pull workflow complete. Success log: $success_log"
  if [[ -s "$failed_log" ]]; then
    warn "Some pulls failed. Review: $failed_log"
  else
    rm -f "$failed_log"
  fi
}

registry_host_from_prefix() {
  local prefix="$1"
  printf '%s\n' "${prefix%%/*}"
}

target_for_image() {
  local image="$1" target="$2" mode="$3" normalized path
  target="${target%/}"
  normalized="$(normalize_image "$image")"
  case "$mode" in
    preserve-registry)
      path="$normalized"
      ;;
    strip-registry)
      path="$(without_registry "$normalized")"
      ;;
    *)
      err "Unsupported push mode: $mode"
      exit 1
      ;;
  esac

  # Harbor and similar registries expect a project/image path shape.
  # If the transformed path has only one segment, place it under library/.
  if [[ "$path" != */* ]]; then
    path="library/$path"
  fi

  printf '%s/%s\n' "$target" "$path"
}

push_one() {
  local image="$1" target_prefix="$2" mode="$3" map_file="$4" success_log="$5" failed_log="$6" missing_log="$7"
  local target attempt
  target="$(target_for_image "$image" "$target_prefix" "$mode")"
  printf '%s\t%s\n' "$image" "$target" >> "$map_file"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN: would tag $image -> $target"
    log "DRY RUN: would push $target"
    return 0
  fi

  if ! "$CONTAINER_CLI" image inspect "$image" >/dev/null 2>&1; then
    err "Local source image missing, pull it first: $image"
    append_unique "$missing_log" "$image"
    [[ "$CONTINUE_ON_ERROR" == "true" ]] && return 0 || return 1
  fi

  "$CONTAINER_CLI" tag "$image" "$target"
  for attempt in $(seq 1 "$RETRIES"); do
    log "Pushing [$attempt/$RETRIES]: $target"
    if "$CONTAINER_CLI" push "$target"; then
      append_unique "$success_log" "$target"
      return 0
    fi
    sleep $(( attempt * 2 ))
  done

  err "Push failed after $RETRIES attempts: $target"
  append_unique "$failed_log" "$target"
  [[ "$CONTINUE_ON_ERROR" == "true" ]] && return 0 || return 1
}

push_images() {
  need_container_cli
  ensure_organized
  local list="${IMAGE_LIST:-$LIST_DIR/all-active-images.list}"
  [[ -f "$list" ]] || { err "Image list not found: $list"; exit 1; }

  if [[ -z "$TARGET_PREFIX" ]]; then
    read -r -p "Target registry/repository prefix, e.g. kubeharbor.dev.kube: " TARGET_PREFIX
  fi
  TARGET_PREFIX="$(trim "$TARGET_PREFIX")"
  [[ -n "$TARGET_PREFIX" ]] || { err "Target registry/repository prefix is required."; exit 1; }
  TARGET_PREFIX="${TARGET_PREFIX%/}"

  if [[ "$PUSH_MODE" != "preserve-registry" && "$PUSH_MODE" != "strip-registry" ]]; then
    err "Invalid push mode: $PUSH_MODE"
    exit 1
  fi

  local target_host
  target_host="$(registry_host_from_prefix "$TARGET_PREFIX")"
  log "Target prefix: $TARGET_PREFIX"
  log "Target registry host: $target_host"
  log "Retag mode: $PUSH_MODE"
  prompt_login "$target_host" "Target registry" "y"

  mkdir -p "$LOG_DIR" "$LIST_DIR"
  local stamp map_file target_list success_log failed_log missing_log image total current target
  stamp="$(date '+%Y%m%d-%H%M%S')"
  map_file="$LOG_DIR/push-image-map-$stamp.tsv"
  target_list="$LOG_DIR/pushed-target-images-$stamp.list"
  success_log="$LOG_DIR/push-success.list"
  failed_log="$LOG_DIR/push-failed-$stamp.list"
  missing_log="$LOG_DIR/push-missing-local-$stamp.list"
  printf 'source\ttarget\n' > "$map_file"
  : > "$target_list"; : > "$failed_log"; : > "$missing_log"

  total="$(grep -cvE '^\s*(#|$)' "$list" || true)"
  current=0
  while IFS= read -r image || [[ -n "$image" ]]; do
    image="$(trim "$image")"
    [[ -z "$image" || "$image" == \#* ]] && continue
    current=$((current + 1))
    log "Push progress $current/$total"
    push_one "$image" "$TARGET_PREFIX" "$PUSH_MODE" "$map_file" "$success_log" "$failed_log" "$missing_log"
    target="$(target_for_image "$image" "$TARGET_PREFIX" "$PUSH_MODE")"
    append_unique "$target_list" "$target"
  done < "$list"

  sort_unique_file "$success_log"
  sort_unique_file "$failed_log"
  sort_unique_file "$missing_log"
  sort_unique_file "$target_list"

  log "Push workflow complete."
  log "Image map: $map_file"
  log "Target image list: $target_list"
  [[ -s "$failed_log" ]] && warn "Some pushes failed. Review: $failed_log" || rm -f "$failed_log"
  [[ -s "$missing_log" ]] && warn "Some local images were missing. Review: $missing_log" || rm -f "$missing_log"
}

parse_common_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list)
        IMAGE_LIST="$2"; shift 2 ;;
      --target)
        TARGET_PREFIX="$2"; shift 2 ;;
      --mode)
        PUSH_MODE="$2"; shift 2 ;;
      --force|--force-pull)
        FORCE_PULL="true"; shift ;;
      --dry-run)
        DRY_RUN="true"; shift ;;
      --fail-fast)
        CONTINUE_ON_ERROR="false"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        err "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
}

main() {
  local cmd="${1:-}"
  [[ -n "$cmd" ]] || { usage; exit 1; }
  shift || true
  case "$cmd" in
    organize)
      parse_common_args "$@"
      organize_lists
      ;;
    pull|download)
      parse_common_args "$@"
      pull_images
      ;;
    push)
      parse_common_args "$@"
      push_images
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      err "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
