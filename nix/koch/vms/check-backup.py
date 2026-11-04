"""Fail closed on missing sources or stale application-produced backup material."""
import json
import os
from pathlib import Path
import sys
import time


def check(source, now=None):
    now = time.time() if now is None else now
    for name in source.get("requiredMounts", []):
        if not os.path.ismount(name):
            raise ValueError(f"Required backup filesystem is not mounted: {name}")
    for name in source.get("requiredPaths", []):
        if not Path(name).exists():
            raise ValueError(f"Required backup path missing: {name}")
    for name in source["paths"]:
        path = Path(name)
        if not path.exists():
            raise ValueError(f"Required backup source missing: {path}")
        if path.is_dir():
            # Detect an empty/unreadable source rather than silently succeeding.
            if not any(child.name != ".backup-complete" and
                       not child.name.startswith(".backup-tmp-") for child in path.iterdir()):
                raise ValueError(f"Required backup source has no completed material: {path}")
    if source["freshnessFile"] is not None:
        marker = Path(source["freshnessFile"])
        age = now - marker.stat().st_mtime
        if age < -300 or age > source["maxAgeSeconds"]:
            raise ValueError(f"Backup producer marker is stale or future-dated: {marker}")


if __name__ == "__main__":
    try:
        manifest = json.loads(Path(sys.argv[1]).read_text())
        check(manifest[sys.argv[2]])
    except (OSError, ValueError) as error:
        sys.exit(str(error))
