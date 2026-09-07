# Native Client Storage Probe

This is a non-shipping test executable. It imports the production
`apps/mobile/lib/src/data/file_library_storage.dart` directly, without copying or
mocking the backend. Flutter's application-directory selection stays in
`library_storage.dart`; app callers keep the same exported storage API.

From this directory:

```sh
dart pub get --enforce-lockfile
dart run tool/verify_dependencies.dart
dart run tool/test_dependency_policy.dart
dart analyze
dart build cli --target bin/library_storage_probe.dart --output ../../../build/client-storage-probe
```

Keep the generated `bundle/bin` and `bundle/lib` together. SQLite uses Dart build
hooks, so use `dart build cli`, not `dart compile exe`. The dependency verifier
requires every probe package to have the same version, hosted origin, and archive
checksum as the client lockfile. Update the probe constraints/lockfile together
with applicable client dependency upgrades; do not remove this check to accept
a different SQLite implementation. [SQLite package documentation](https://pub.dev/packages/sqlite3),
[Dart build guidance](https://dart.dev/tools/dart-compile).

Dependabot includes this package and the client in one grouped update
configuration. Review any remaining transitive-version differences reported by
the verifier; grouping is not permission to accept mismatched native dependencies.

From the repository root, run native process acceptance with a new evidence
directory. Add `.exe` to the executable path on Windows:

```sh
python3 scripts/ci/client_storage_runtime.py \
  --executable build/client-storage-probe/bundle/bin/library_storage_probe \
  --evidence build/client-storage-runtime
```

On a Linux host with mount namespaces and root permission, the additional
filesystem-exhaustion checks run inside a private namespace:

```sh
sudo unshare --mount --propagation private \
  python3 scripts/ci/client_storage_runtime.py \
  --executable build/client-storage-probe/bundle/bin/library_storage_probe \
  --evidence build/client-storage-runtime-enospc --disk-full
```

The driver creates an 8 MiB tmpfs inside its own fresh temporary directory. It
refuses to mount in the host init mount namespace and runs the storage processes
as UID/GID 65534 for these cases. Filling that bounded tmpfs must produce real
zero-free-block/`SQLITE_FULL` or `ENOSPC` evidence. It does not fill the host disk
or operate on an existing library. Processes are closed/awaited, the mount is
removed, and cleanup failures reject the run. Do not point the low-level probe
at real application data; the acceptance driver supplies disposable paths.

The checked-in CI and release desktop jobs run the process checks on all three
desktop platforms and the extra filesystem cases on Linux. Failed assertions,
unexpected exits/error codes, missing evidence, and cleanup errors fail those
jobs. Reports identify executable/backend/lockfile hashes and contain only
synthetic fixture data. A local report does not establish that these jobs have
run on GitHub for a published revision.

Scope: acknowledged and pending commit process death, stale concurrent writers,
lock release after death, explicit corruption recovery, a 25,000-track serialized
snapshot, interrupted initial commit, and real Linux filesystem exhaustion.
The pause hook is at the production flushed-pending/pre-replacement boundary;
it does not simulate every possible interruption point. No claim is made about
physical power-loss durability, filesystem directory metadata, installed app
migration, audio/UI responsiveness, mobile targets, or differing schema versions.
