#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_LIST_DIR="${CHART_LIST_DIR:-$SCRIPT_DIR/chart-lists}"
HELM_PACKAGE_DIR="${HELM_PACKAGE_DIR:-$SCRIPT_DIR/helm-packages}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
CHART_LIST=""
DRY_RUN="false"
FORCE_PULL="false"
BUNDLE_OUTPUT=""

usage() {
  cat <<'EOF'
Usage:
  ./helm-airgap.sh pull [--list chart-lists/<charts>.list] [--destination helm-packages] [--force] [--dry-run]
  ./helm-airgap.sh bundle [--output bundles/helm-charts-YYYYmmdd-HHMMSS.tar.gz] [--dry-run]

Wrappers:
  ./download-helm-charts.sh [pull options]
  ./create-chart-package.sh [bundle options]

Chart list format:
  repo_alias|repo_url|chart|version

Example:
  cnpg|https://cloudnative-pg.github.io/charts|cloudnative-pg|0.29.0

Environment:
  CHART_LIST_DIR=./chart-lists
  HELM_PACKAGE_DIR=./helm-packages
  LOG_DIR=./logs
EOF
}

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
err() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Required command not found in PATH: $1"; exit 1; }
}

append_unique() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -Fxq "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

sort_unique_file() {
  local file="$1"
  [[ -f "$file" ]] && LC_ALL=C sort -u "$file" -o "$file"
}

default_chart_list() {
  local default="$CHART_LIST_DIR/all-charts.list"
  if [[ -f "$default" ]]; then
    printf '%s\n' "$default"
    return 0
  fi

  local generated="$CHART_LIST_DIR/.all-charts.generated.list"
  mkdir -p "$CHART_LIST_DIR"
  : > "$generated"
  find "$CHART_LIST_DIR" -type f -name '*.list' ! -name '.all-charts.generated.list' -print0 \
    | sort -z \
    | while IFS= read -r -d '' file; do
        cat "$file" >> "$generated"
        printf '\n' >> "$generated"
      done
  printf '%s\n' "$generated"
}

parse_pull_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list)
        CHART_LIST="${2:-}"; shift 2 ;;
      --destination|--dest)
        HELM_PACKAGE_DIR="${2:-}"; shift 2 ;;
      --force)
        FORCE_PULL="true"; shift ;;
      --dry-run)
        DRY_RUN="true"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        err "Unknown pull option: $1"; usage; exit 2 ;;
    esac
  done
}

parse_bundle_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output|-o)
        BUNDLE_OUTPUT="${2:-}"; shift 2 ;;
      --dry-run)
        DRY_RUN="true"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        err "Unknown bundle option: $1"; usage; exit 2 ;;
    esac
  done
}

helm_pull_one() {
  local alias="$1" repo_url="$2" chart="$3" version="$4" success_log="$5" failed_log="$6"
  local package="$HELM_PACKAGE_DIR/${chart}-${version}.tgz"

  if [[ "$FORCE_PULL" != "true" && -f "$package" ]]; then
    log "SKIP existing chart package: $package"
    append_unique "$success_log" "$package"
    return 0
  fi

  log "Chart source: $alias -> $repo_url"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN: would run 'helm repo add $alias $repo_url --force-update'"
    log "DRY RUN: would run 'helm pull $alias/$chart --version $version --destination $HELM_PACKAGE_DIR'"
    return 0
  fi

  helm repo add "$alias" "$repo_url" --force-update >/dev/null
  helm pull "$alias/$chart" --version "$version" --destination "$HELM_PACKAGE_DIR"

  if [[ -f "$package" ]]; then
    append_unique "$success_log" "$package"
  else
    err "Expected chart package was not created: $package"
    append_unique "$failed_log" "$alias|$repo_url|$chart|$version"
    return 1
  fi
}

pull_charts() {
  require_cmd helm
  mkdir -p "$HELM_PACKAGE_DIR" "$LOG_DIR"

  local list="${CHART_LIST:-$(default_chart_list)}"
  [[ -f "$list" ]] || { err "Chart list not found: $list"; exit 1; }

  local stamp success_log failed_log total current raw alias repo_url chart version rc
  stamp="$(date '+%Y%m%d-%H%M%S')"
  success_log="$LOG_DIR/helm-pull-success.list"
  failed_log="$LOG_DIR/helm-pull-failed-$stamp.list"
  : > "$failed_log"
  total="$(grep -cvE '^\s*(#|$)' "$list" || true)"
  current=0

  while IFS= read -r raw || [[ -n "$raw" ]]; do
    raw="$(trim "$raw")"
    [[ -z "$raw" || "$raw" == \#* ]] && continue

    IFS='|' read -r alias repo_url chart version <<<"$raw"
    alias="$(trim "$alias")"
    repo_url="$(trim "$repo_url")"
    chart="$(trim "$chart")"
    version="$(trim "$version")"

    if [[ -z "$alias" || -z "$repo_url" || -z "$chart" || -z "$version" ]]; then
      err "Invalid chart list row: $raw"
      append_unique "$failed_log" "$raw"
      continue
    fi

    current=$((current + 1))
    log "Helm chart pull progress $current/$total: $chart $version"
    if helm_pull_one "$alias" "$repo_url" "$chart" "$version" "$success_log" "$failed_log"; then
      rc=0
    else
      rc=$?
      warn "Chart pull failed for $chart $version"
    fi
  done < "$list"

  sort_unique_file "$success_log"
  sort_unique_file "$failed_log"
  log "Helm chart pull workflow complete. Success log: $success_log"
  if [[ -s "$failed_log" ]]; then
    warn "Some chart pulls failed. Review: $failed_log"
  else
    rm -f "$failed_log"
  fi
}

bundle_charts() {
  require_cmd tar
  mkdir -p "$SCRIPT_DIR/bundles"
  local stamp output
  stamp="$(date '+%Y%m%d-%H%M%S')"
  output="${BUNDLE_OUTPUT:-$SCRIPT_DIR/bundles/helm-charts-$stamp.tar.gz}"
  mkdir -p "$(dirname "$output")"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN: would create chart bundle: $output"
    return 0
  fi

  tar -C "$SCRIPT_DIR" -czf "$output" chart-lists helm-packages
  log "Created Helm chart transfer bundle: $output"
}

main() {
  local command="${1:-}"
  [[ -n "$command" ]] || { usage; exit 2; }
  shift || true

  case "$command" in
    pull)
      parse_pull_args "$@"
      pull_charts
      ;;
    bundle)
      parse_bundle_args "$@"
      bundle_charts
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      err "Unknown command: $command"
      usage
      exit 2
      ;;
  esac
}

main "$@"
