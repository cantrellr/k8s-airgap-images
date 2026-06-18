#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./diagrams/render-mermaid-assets.sh [repo-path] [--repo PATH] [--install-deps] [--sync-index] [--clean]

Renders diagrams/mermaid-source/*.mmd to diagrams/svg/*.svg and diagrams/png/*.png.
The script uses .diagram-tools/node_modules/.bin/mmdc when present, then mmdc from PATH.
Do not run with sudo.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_DEPS=0
SYNC_INDEX=0
CLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    --install-deps) INSTALL_DEPS=1; shift ;;
    --install-browser-deps)
      echo "Install Puppeteer/Chrome OS libraries using your workstation package manager, then rerun without sudo."
      shift ;;
    --sync-index) SYNC_INDEX=1; shift ;;
    --clean) CLEAN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) REPO_DIR="$(cd "$1" && pwd)"; shift ;;
  esac
done

if [[ "${EUID}" -eq 0 ]]; then
  echo "ERROR: Do not run the Mermaid renderer with sudo/root." >&2
  exit 1
fi

SOURCE_DIR="${REPO_DIR}/diagrams/mermaid-source"
SVG_DIR="${REPO_DIR}/diagrams/svg"
PNG_DIR="${REPO_DIR}/diagrams/png"
TOOLS_DIR="${REPO_DIR}/.diagram-tools"

mkdir -p "${SVG_DIR}" "${PNG_DIR}"
[[ -d "${SOURCE_DIR}" ]] || { echo "ERROR: Missing ${SOURCE_DIR}" >&2; exit 1; }

if [[ "${INSTALL_DEPS}" -eq 1 ]]; then
  command -v node >/dev/null 2>&1 || { echo "ERROR: node is required." >&2; exit 1; }
  command -v npm >/dev/null 2>&1 || { echo "ERROR: npm is required." >&2; exit 1; }
  mkdir -p "${TOOLS_DIR}"
  cat > "${TOOLS_DIR}/package.json" <<'JSON'
{
  "private": true,
  "devDependencies": {
    "@mermaid-js/mermaid-cli": "latest"
  }
}
JSON
  npm install --prefix "${TOOLS_DIR}" --no-audit --no-fund
fi

if [[ -x "${TOOLS_DIR}/node_modules/.bin/mmdc" ]]; then
  MMDC="${TOOLS_DIR}/node_modules/.bin/mmdc"
elif command -v mmdc >/dev/null 2>&1; then
  MMDC="$(command -v mmdc)"
else
  echo "ERROR: Mermaid CLI not found. Run with --install-deps or install mmdc globally." >&2
  exit 1
fi

[[ "${CLEAN}" -eq 1 ]] && rm -f "${SVG_DIR}"/*.svg "${PNG_DIR}"/*.png

mapfile -t sources < <(find "${SOURCE_DIR}" -maxdepth 1 -name '*.mmd' -type f | sort)
[[ "${#sources[@]}" -gt 0 ]] || { echo "ERROR: No Mermaid source files found." >&2; exit 1; }

for src in "${sources[@]}"; do
  base="$(basename "${src}" .mmd)"
  echo "Rendering ${base}"
  "${MMDC}" -i "${src}" -o "${SVG_DIR}/${base}.svg" -t default -b transparent
  "${MMDC}" -i "${src}" -o "${PNG_DIR}/${base}.png" -t default -b transparent -s 2
done

if [[ "${SYNC_INDEX}" -eq 1 ]]; then
  python3 "${REPO_DIR}/diagrams/sync-mermaid-markdown.py" "${REPO_DIR}"
fi
