#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${1:-${SCRIPT_DIR}/..}" && pwd)"
if [[ $# -gt 0 && "$1" != --* ]]; then
  shift
fi
if [[ "${EUID}" -eq 0 ]]; then
  echo "ERROR: Do not run diagram sync with sudo/root." >&2
  exit 1
fi
"${SCRIPT_DIR}/render-mermaid-assets.sh" --repo "${REPO_DIR}" --sync-index "$@"
