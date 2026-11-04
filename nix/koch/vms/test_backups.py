"""Local tests: python3 -m unittest discover -s nix/koch/vms -p 'test_*.py'."""
from contextlib import closing
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check = load("check-backup").check
produce = load("grocy-backup").produce


class BackupTests(unittest.TestCase):
    def test_sources_and_freshness(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "source"
            spec = {"paths": [str(source)], "freshnessFile": None, "maxAgeSeconds": 60}
            with self.assertRaises(ValueError):
                check(spec)
            source.mkdir()
            with self.assertRaises(ValueError):
                check(spec)
            (source / ".backup-complete").touch()
            (source / ".backup-tmp-partial").write_text("incomplete")
            with self.assertRaises(ValueError):
                check(spec)
            (source / ".backup-complete").unlink()
            (source / "note.md").write_text("important")
            check(spec)
            marker = source / ".backup-complete"
            spec["freshnessFile"] = str(marker)
            with self.assertRaises(FileNotFoundError):
                check(spec)
            marker.touch()
            os.utime(marker, (1000, 1000))
            check(spec, now=1020)
            with self.assertRaises(ValueError):
                check(spec, now=1061)
            with self.assertRaises(ValueError):
                check(spec, now=0)

    def test_required_mount_and_path(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root) / "synchspace"
            source.mkdir()
            (source / ".stfolder").mkdir()
            notes = source / "notes"
            spec = {"paths": [str(source)], "requiredMounts": [root],
                    "requiredPaths": [str(notes)], "freshnessFile": None,
                    "maxAgeSeconds": 60}
            with patch("os.path.ismount", return_value=False):
                with self.assertRaisesRegex(ValueError, "not mounted"):
                    check(spec)
            with patch("os.path.ismount", return_value=True):
                with self.assertRaisesRegex(ValueError, "path missing"):
                    check(spec)
                notes.mkdir()
                check(spec)

    def test_grocy_archive_can_be_restored(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            source, destination = root / "source", root / "staging"
            source.mkdir()
            destination.mkdir()
            # Keep a WAL database open: the producer must use SQLite's backup
            # API, not depend on all committed data being in the main file.
            with closing(sqlite3.connect(source / "grocy.db")) as live:
                live.execute("PRAGMA journal_mode=WAL")
                live.execute("CREATE TABLE products (name TEXT)")
                live.execute("INSERT INTO products VALUES ('rice')")
                live.commit()
                (source / "storage").mkdir()
                (source / "storage" / "picture.jpg").write_bytes(b"picture")
                (source / "config.php").write_text("configuration")
                (source / "viewcache").mkdir()
                (source / "viewcache" / "cache").write_text("generated")
                config = root / "effective-config.php"
                config.write_text("effective configuration")
                produce(source, destination, config)
            self.assertTrue((destination / ".backup-complete").exists())
            self.assertFalse(list(destination.glob(".backup-tmp-*")))
            restored = root / "restored"
            with tarfile.open(destination / "grocy.tar.gz") as archive:
                archive.extractall(restored, filter="data")
            with closing(sqlite3.connect(restored / "data" / "grocy.db")) as db:
                self.assertEqual(db.execute("SELECT name FROM products").fetchall(), [("rice",)])
                self.assertEqual(db.execute("PRAGMA integrity_check").fetchone(), ("ok",))
            self.assertEqual((restored / "data/storage/picture.jpg").read_bytes(), b"picture")
            self.assertEqual((restored / "data/config.php").read_text(), "configuration")
            self.assertEqual((restored / "config.php").read_text(), "effective configuration")
            self.assertFalse((restored / "data/viewcache").exists())
            self.assertFalse(list((restored / "data").glob("grocy.db-*")))
            # Failure must leave the last good archive and completion marker.
            previous = (destination / "grocy.tar.gz").read_bytes()
            timestamp = (destination / ".backup-complete").stat().st_mtime_ns
            (source / "grocy.db").unlink()
            with self.assertRaises(sqlite3.OperationalError):
                produce(source, destination)
            self.assertEqual((destination / "grocy.tar.gz").read_bytes(), previous)
            self.assertEqual((destination / ".backup-complete").stat().st_mtime_ns, timestamp)
            self.assertFalse(list(destination.glob(".backup-tmp-*")))


class ResticTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("RESTIC_TEST_BINARY") or shutil.which("restic"),
                         "set RESTIC_TEST_BINARY or put restic on PATH for local transport test")
    def test_versioned_local_restore_and_temp_exclusion(self):
        restic = os.environ.get("RESTIC_TEST_BINARY") or shutil.which("restic")
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            source = root / "source"
            source.mkdir()
            (source / "note.md").write_text("first generation")
            (source / ".backup-tmp-incomplete").write_text("do not upload")
            password = root / "password"
            password.write_text(os.urandom(32).hex())
            password.chmod(0o600)
            env = os.environ.copy()
            env.update(RESTIC_REPOSITORY=str(root / "repository"),
                       RESTIC_PASSWORD_FILE=str(password), RESTIC_CACHE_DIR=str(root / "cache"))

            def run(*args):
                return subprocess.run([restic, *args], env=env, cwd=source,
                                      capture_output=True, check=True).stdout

            run("init")
            run("backup", ".", "--exclude", ".backup-tmp-*", "--tag", "koch-vm:test")
            first = json.loads(run("snapshots", "--json"))[0]["id"]
            (source / "note.md").write_text("second generation")
            run("backup", ".", "--exclude", ".backup-tmp-*", "--tag", "koch-vm:test")
            run("check", "--read-data")
            for snapshot, expected in [(first, "first generation"), ("latest", "second generation")]:
                target = root / snapshot
                run("restore", snapshot, "--target", str(target))
                notes = list(target.rglob("note.md"))
                self.assertEqual(len(notes), 1)
                self.assertEqual(notes[0].read_text(), expected)
                self.assertFalse(list(target.rglob(".backup-tmp-*")))


if __name__ == "__main__":
    unittest.main()
