#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/image-airgap.sh" organize
exec "$SCRIPT_DIR/image-airgap.sh" push "$@"
