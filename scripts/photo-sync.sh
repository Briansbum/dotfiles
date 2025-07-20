#!/etc/profiles/per-user/alex/bin/bash

set -euo pipefail

/run/current-system/sw/bin/rsync -v -a --ignore-existing --partial /home/alex/Pictures/Darktable/ /mnt/photos/sync
