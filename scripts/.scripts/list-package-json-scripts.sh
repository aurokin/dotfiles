#!/usr/bin/env bash
set -euo pipefail

pkg="package.json"
json=false

for arg in "$@"; do
  case "$arg" in
    --json|-j)
      json=true
      ;;
    --help|-h)
      cat <<'EOF'
Usage: list-package-json-scripts.sh [--json|-j]

Options:
  --json, -j   Output scripts as a JSON object.
  --help, -h   Show this help message.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$pkg" ]]; then
  echo "No package.json found in $(pwd)" >&2
  exit 1
fi

scripts=""

if command -v jq >/dev/null 2>&1; then
  scripts=$(jq -r '.scripts // {} | to_entries[]? | "\(.key)\t\(.value)"' "$pkg")
  scripts_json=$(jq -c '(.scripts // {}) | to_entries | sort_by(.key) | from_entries' "$pkg")
elif command -v node >/dev/null 2>&1; then
  scripts=$(node -e 'const fs=require("fs"); const pkg=JSON.parse(fs.readFileSync("package.json","utf8")); const scripts=pkg.scripts||{}; Object.keys(scripts).forEach(k=>console.log(`${k}\t${scripts[k]}`));')
  scripts_json=$(node -e 'const fs=require("fs"); const pkg=JSON.parse(fs.readFileSync("package.json","utf8")); const scripts=pkg.scripts||{}; const out={}; Object.keys(scripts).sort().forEach(k=>out[k]=scripts[k]); console.log(JSON.stringify(out));')
else
  echo "Neither jq nor node found to parse package.json." >&2
  exit 2
fi

if [[ -z "$scripts" ]]; then
  if [[ "$json" == true ]]; then
    echo "{}"
    exit 0
  fi
  echo "No scripts found in package.json"
  exit 0
fi

if [[ "$json" == true ]]; then
  echo "$scripts_json"
  exit 0
fi

scripts_sorted=$(printf '%s\n' "$scripts" | LC_ALL=C sort -t $'\t' -k1,1)

printf "%-20s %s\n" "script" "command"
printf "%-20s %s\n" "------" "-------"
while IFS=$'\t' read -r name cmd; do
  printf "%-20s %s\n" "$name" "$cmd"
done <<< "$scripts_sorted"
