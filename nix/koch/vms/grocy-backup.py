"""Produce one atomic Grocy recovery archive; never copy the live SQLite file.

Run as the Grocy service user. The caller must pause application writes while
this runs to coordinate the SQLite snapshot with uploads/configuration.
"""
from contextlib import closing
import os
from pathlib import Path
import shutil
import sqlite3
import sys
import tarfile
import tempfile
from urllib.parse import quote


def produce(source, destination, config_file=None):
    source, destination = Path(source), Path(destination)
    os.umask(0o077)
    # No mkdir fallback: a missing share must not write into the guest disk.
    if not destination.is_dir():
        raise ValueError("Backup staging mount does not exist")
    with tempfile.TemporaryDirectory(prefix=".backup-tmp-", dir=destination) as temp:
        temp = Path(temp)
        data = temp / "data"
        shutil.copytree(source, data, ignore=shutil.ignore_patterns(
            "grocy.db", "grocy.db-*", "viewcache"))
        with closing(sqlite3.connect(f"file:{quote(str(source / 'grocy.db'))}?mode=ro", uri=True)) as live:
            with closing(sqlite3.connect(data / "grocy.db")) as snapshot:
                live.backup(snapshot)
                # Publish a standalone DB even when the source uses WAL.
                snapshot.execute("PRAGMA journal_mode=DELETE")
                if snapshot.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                    raise ValueError("Grocy SQLite backup failed integrity_check")
        # The NixOS service uses /etc/grocy/config.php, not necessarily the
        # historical config.php in dataDir. Dereference its store symlink.
        if config_file is not None:
            shutil.copyfile(config_file, temp / "config.php")
        archive = temp / "grocy.tar.gz"
        with tarfile.open(archive, "w:gz") as stream:
            stream.add(data, arcname="data")
            if config_file is not None:
                stream.add(temp / "config.php", arcname="config.php")
        with archive.open("rb") as stream:
            os.fsync(stream.fileno())
        os.replace(archive, destination / "grocy.tar.gz")
        marker = temp / "complete"
        marker.touch()
        os.replace(marker, destination / ".backup-complete")
        fd = os.open(destination, os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


if __name__ == "__main__":
    produce(*sys.argv[1:])
