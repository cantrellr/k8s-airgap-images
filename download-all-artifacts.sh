#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_IMAGES="false"
SKIP_CHARTS="false"
IMAGE_ARGS=()
CHART_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  ./download-all-artifacts.sh [--skip-images] [--skip-charts]

Environment overrides:
  IMAGE_LIST=image-lists/all-active-images.list
  CHART_LIST=chart-lists/<specific-chart-list>.list
  HELM_PACKAGE_DIR=helm-packages

This wrapper downloads both container images and Helm chart packages while connected.
If CHART_LIST is not set, all chart-lists/*.list files are combined by helm-airgap.sh.

Use the lower-level wrappers for custom options:
  ./download-images.sh --help
  ./download-helm-charts.sh --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-images)
      SKIP_IMAGES="true"; shift ;;
    --skip-charts)
      SKIP_CHARTS="true"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      printf '[ERROR] Unknown option: %s\n' "$1" >&2
      usage
      exit 2 ;;
  esac
done

if [[ "$SKIP_IMAGES" != "true" ]]; then
  "$SCRIPT_DIR/download-images.sh" --list "${IMAGE_LIST:-$SCRIPT_DIR/image-lists/all-active-images.list}" "${IMAGE_ARGS[@]}"
fi

if [[ "$SKIP_CHARTS" != "true" ]]; then
  if [[ -n "${CHART_LIST:-}" ]]; then
    "$SCRIPT_DIR/download-helm-charts.sh" --list "$CHART_LIST" "${CHART_ARGS[@]}"
  else
    "$SCRIPT_DIR/download-helm-charts.sh" "${CHART_ARGS[@]}"
  fi
fi
