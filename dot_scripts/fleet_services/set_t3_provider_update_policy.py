#!/usr/bin/env python3

import argparse
import json
import os
import tempfile
import time
from pathlib import Path

parser = argparse.ArgumentParser(description="Set T3 provider-update ownership policy")
parser.add_argument("--apply", action="store_true", help="write the reviewed policy")
args = parser.parse_args()

path = Path.home() / ".t3/userdata/settings.json"
if path.exists():
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise SystemExit(f"T3 settings are not a JSON object: {path}")
else:
    data = {}

current = data.get("enableProviderUpdateChecks", True)
print(f"path={path}")
print(f"enableProviderUpdateChecks.current={str(bool(current)).lower()}")
print("enableProviderUpdateChecks.desired=false")
if not args.apply:
    raise SystemExit(0)

path.parent.mkdir(parents=True, exist_ok=True)
if path.exists() and current is not False:
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    backup = path.with_name(f"settings.json.pre-agent-updates-{stamp}")
    backup.write_bytes(path.read_bytes())

data["enableProviderUpdateChecks"] = False
fd, temp_name = tempfile.mkstemp(prefix=".settings.", dir=path.parent)
try:
    with os.fdopen(fd, "w") as handle:
        json.dump(data, handle, separators=(",", ":"), sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp_name, path)
finally:
    if os.path.exists(temp_name):
        os.unlink(temp_name)

verified = json.loads(path.read_text()).get("enableProviderUpdateChecks")
if verified is not False:
    raise SystemExit("T3 provider update checks were not disabled")
print("enableProviderUpdateChecks.applied=false")
print("restart_required=true")
