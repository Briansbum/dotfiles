#!/run/current-system/sw/bin/env bash

set -euo pipefail

rsync -v -a --ignore-existing --partial /home/alex/Pictures/Darktable/ /mnt/photos/sync
