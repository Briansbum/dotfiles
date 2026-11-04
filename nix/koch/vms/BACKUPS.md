# VM backup contract

A VM owns **producing recoverable application material**. The host owns encrypted,
versioned offsite transport. Neither a running VM disk nor arbitrary writable
shares are automatically considered recoverable backups.

## VM interface

Backups are enabled by default in `mk-service-vm.nix`:

```nix
koch-vm.backup = {
  enable = true;
  directory = "/var/backups/application"; # guest staging mount
  # hostDirectory defaults to /data/backups/vms/<VM name>
  # paths defaults to [ hostDirectory ]
};
```

The host creates the staging directory as `alex:users`, mode 0700, matching its
rootless QEMU/virtiofsd. The service's guest UID must have access (Grocy uses UID
1000). No guest tmpfiles chown is needed. Application services must order their
producer after the mount, using `RequiresMountsFor`.

The guest producer must:

1. Include everything needed to recover the application: consistent database
   snapshots/dumps, uploads, configuration, etc.
2. Write temporary work under `.backup-tmp-*`, excluded from transport.
3. Validate and atomically publish completed material, preferably as **one archive**
   so a concurrent reader cannot mix database and file generations.
4. Update `.backup-complete` only after successful publication. The host refuses
   staged backups if this marker is missing, future-dated, or older than
   `maxAgeSeconds` (36 hours by default).
5. Leave the previous completed material untouched on failure. Keep only the
   current staging generation; historical retention belongs to the repository.

The marker is a producer freshness check, not proof of contents or restorability.
The source must also exist and not be empty. Service failures are visible in the
guest journal forwarded to the host. Actual alert delivery and restore-test
scheduling still need monitoring integration.

### Direct sources

For files that need no application-produced dump:

```nix
koch-vm.backup.paths = [ "/data/synchspace" ]; # HOST paths
```

`paths` **replaces**, rather than adds to, the default source list. The staging
mount/directory is omitted unless `hostDirectory` is included. There is no
producer-age check for direct paths by default; a custom host-side
`freshnessFile` may be supplied. `requiredMounts` and `requiredPaths` can
require host mountpoints and additional paths before transport. The Grocy and
Syncthing jobs require `/data` to be mounted; Syncthing also requires its notes
directory. Syncthing includes current notes, `.stversions`,
and conflict files. This is a live file-tree backup, not a transactional snapshot;
its `.zk` databases are notebook indexes, not validated database dumps.

For stateless VMs or data intentionally protected elsewhere:

```nix
koch-vm.backup.enable = false;
```

Git is explicitly out of scope. Chorcy/Knot have no application state. Immich
continues using its existing photo job and PostgreSQL dump; it is not copied
again by this transport. Takeout and home-directory backups are not included.

`runner.nix` discovers the flake's `koch-*` configurations, so adding a VM there
also registers its runner and backup contract without another host list.

## Host transport: explicit provisioning required

Staging is **not offsite protection**. The host transport is deliberately disabled
until repository credentials are provisioned; evaluation emits a warning while
VM sources are registered without transport. Configure:

```nix
koch-vm-backups = {
  enable = true;
  repository = "b2:YOUR-DEDICATED-BUCKET:koch-vms";
  passwordFile = "/run/secrets/vm_backup_password";
  environmentFile = "/run/secrets/vm_backup_environment";
};
```

Those are examples of runtime file paths, not existing secrets. Provision them
with sops-nix or equivalent. The environment file contains `B2_ACCOUNT_ID` and
`B2_ACCOUNT_KEY`; use a dedicated appropriately scoped credential. Never put
secret values in Nix source or command-line arguments. Store the restic password
and recovery instructions independently of this host/SOPS identity.

Initialize the chosen repository explicitly using secure runtime credentials.
The module will **not** initialize repositories, forget snapshots, prune data, or
change B2 lifecycle/Object Lock policies. Agree retention and deletion protection
before adding cleanup. It creates one daily restic job per enabled VM at 03:00
with up to 30 minutes jitter, tagged `koch-vm:<name>`. Each job checks required
sources/freshness first and fails visibly on errors. Independent VM jobs mean one
failed producer does not block protection of another VM.

Inspect `/etc/koch-vm-backups.json` for the registered source manifest. Run a job
manually with `systemctl start restic-backups-koch-vm-grocy.service`. Check its
journal/status; a successful job is not a substitute for a restore test. Ordinary
systemd failure visibility is implemented; dedicated freshness alerts, remote
checks, and periodic restore tests are not yet implemented.

## Grocy producer and recovery

The guest's `grocy-backup.timer` runs at 02:30. It briefly stops the PHP-FPM pool
to coordinate the SQLite snapshot with uploads/configuration, then uses SQLite's
backup API, validates `integrity_check`, and atomically publishes `grocy.tar.gz`.
PHP-FPM drains requests gracefully; if that takes more than five minutes the
producer refuses to publish. The backup has a 30-minute timeout, and
`ExecStopPost` requests a PHP-FPM restart on success, failure, or timeout. Nginx
can return errors throughout the backup, including compression. Other independent
writers must also be quiesced if introduced later.

The archive contains:

- `data/grocy.db`: standalone SQLite backup, including committed WAL contents;
- `data/storage`, plugins, setting overrides, and other dataDir files;
- `config.php`: dereferenced effective `/etc/grocy/config.php`, in addition to any
  historical config inside dataDir;
- no view cache or copied live database sidecars.

To rehearse recovery, restore a restic snapshot into an **isolated directory**,
extract the archive there, run SQLite `integrity_check`, and inspect records and
pictures. For an actual restore, stop Grocy, restore the archive's `data/` into
its configured dataDir with the correct ownership, reconcile effective config
with the Nix declaration, then start and verify authenticated reads. Never
extract over a running production instance as a test.

## Tests

From the repository root, with Python 3.12+ and Nix available:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s nix/koch/vms -p 'test_*.py' -v
nix eval --impure --json --expr '
  let f = builtins.getFlake (toString ./.);
  in import ./nix/koch/vms/test-backups.nix { flake = f; }'
```

Python tests restore a synthetic WAL-mode Grocy database plus uploads/config and
check failed publication preserves the previous generation. With restic on PATH
(or `RESTIC_TEST_BINARY` set to its executable), they also create a temporary
local encrypted repository, back up two generations, read-check all repository
data, and restore both versions while verifying temporary files were excluded.
No remote repository is accessed by these tests. Nix tests exercise
default staging, opt-out, direct paths, transport generation, validation, and
absence of automatic pruning. These do not constitute a production restore test.
