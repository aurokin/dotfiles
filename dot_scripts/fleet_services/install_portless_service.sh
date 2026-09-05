#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# --apply alone is deliberately refused, including legacy migration callers.
# No service enablement, linger, or system ownership changes are performed.
exec python3 -B "$script_dir/installer_transaction.py" portless "$@"
