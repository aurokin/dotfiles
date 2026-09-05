#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# Explicit idle confirmation covers work that process inspection cannot detect.
exec python3 -B "$script_dir/installer_transaction.py" t3 "$@"
