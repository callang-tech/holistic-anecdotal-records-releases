
# HOLISTIC EDUCATIONAL ANECDOTAL RECORD & TRACKING SYSTEM

Fresh Flutter/Dart baseline for a Windows-first application that can later be ported to Android.

## Current foundation

- Flutter/Dart
- SQLite local database
- Windows SQLite initialization through `sqflite_common_ffi`
- Android-compatible database initialization through `sqflite`
- Six screens:
  - Home
  - Search
  - Add Learner
  - Teachers/Sections
  - View Learner
  - Print
- Password gate
- Change-password support
- Sync-pending counter
- Database tables for teachers, sections, learners, school history, incidents
- Automatic CreatedAt / UpdatedAt / DeviceID / Version / Deleted fields

## Important

Google Sheets synchronization, QR scanning, actual printing, and the full Philippine locations database are intentionally kept as the next implementation phase. The app must be tested locally first before adding cloud synchronization.

## Run

For a new Windows installation, place the installation's OAuth client
configuration at `Documents\HolisticAnecdotalRecords\config\google_oauth_client.json`
for the Windows account that runs the application. Windows Documents may be
redirected to OneDrive. The file must contain nonempty `installed.client_id`
and `installed.client_secret` string fields. The example at
`assets/google/google_oauth_client.example.json` shows the structure without
credentials. Do not commit or publish a real configuration.

Existing installations that still bundle a valid
`assets/google/google_oauth_client.json` copy it to the Documents configuration
path on first authentication initialization. Once present, the Documents copy
is authoritative and is never overwritten by the bundled asset. An invalid
Documents copy requires deliberate correction; it is not silently replaced.
The legacy asset is optional so future public release builds can omit the real
configuration. **A build made while the real file is present in `assets/google/`
will still bundle it.** Remove it from the public release build input and inspect
the release ZIP before publication. Moving this desktop configuration outside
the release directory protects it from updates, but does not make its client
secret cryptographically secret from a local user.

```text
flutter pub get
flutter run -d windows
```

For Android later:

```text
flutter run -d android
```

## Windows release contract (Updater Phase 2)

`pubspec.yaml` is the single authoritative application version source. Its
`version` field uses `major.minor.patch+build`: the semantic version is shown to
users, and the build number identifies the release. Increment the build number
for each distributed release. Do not override the version with `--build-name`
or `--build-number` when producing releases; that would disagree with the
bundled manifest used by the existing About screen.

The package/product identity remains `holistic_anecdotal_records`, and the
Windows executable remains `holistic_anecdotal_records.exe`. Flutter passes the
manifest version to the Windows runner's file/product version resources. The
About screen already reads the bundled `pubspec.yaml` and displays its semantic
version without the build suffix. No additional version dependency is needed.

A future updater may replace only the installed program bundle: the executable,
Flutter runtime, application/plugin DLLs, and packaged `data`/assets. It must
preserve user files outside that bundle, including:

- `Documents\HolisticAnecdotalRecords\holistic_anecdotal_records.db` and its
  SQLite sidecar files, when present.
- `Documents\HolisticAnecdotalRecords\school_name.txt` and `customization\`.
- `Documents\HolisticAnecdotalRecords\config\google_oauth_client.json`.
- Per-user application support/preferences and authentication storage.
- User-created backups and exported PDFs, wherever the user saves them.

Documents means the Windows account's resolved Documents folder, which may be
redirected. The current Windows PDF export opens a PDF in the user's temporary
directory; users must save a permanent copy outside the installed program
directory, along with any manual backups. No managed backup
feature or fixed backup directory currently exists. Do not install the program
bundle into the persistent Documents data directory. Keep the Windows product
and company identity stable because per-user support paths may depend on it.

This contract adds no updater, update check, installer, or data migration.

## Phase 3A: standalone local Windows updater

`windows/updater` contains a C++17 console executable, `holistic_local_updater`.
It is independent of Flutter and uses only Windows APIs and the existing MSVC/
CMake toolchain. There is no main-app integration, network access, version
comparison, installer, rollback, or updater self-update.

Build only this tool from a Visual Studio developer shell with CMake available:

```powershell
cmake -S windows/updater -B build/local_updater -A x64
cmake --build build/local_updater --config Release --target holistic_local_updater
```

No Flutter build or dependency fetch is required. In PowerShell, if CMake is not
on PATH, replace `cmake` with `& '<Visual Studio installation>\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'`.

Invocation (example paths only; not a request to update an existing installation):

```powershell
& .\build\local_updater\Release\holistic_local_updater.exe `
  --app-dir 'C:\LocalUpdateTest\installed' `
  --source 'C:\LocalUpdateTest\staged' `
  --exe holistic_anecdotal_records.exe
```

An optional `--pid <PID>` verifies that the PID belongs to the target executable
and waits up to 60 seconds for its exit. An unresolvable, already-exited, reused,
or unrelated PID fails validation; close the app and retry without `--pid`.
Without a PID, close the app first. In either case the updater checks matching
processes and uses Windows Restart Manager to detect users of target files;
uncertain checks or files still in use stop the update. It never kills processes.
Keep the application closed and both directories undisturbed for the operation.

Safety restrictions:

- Use existing, separate, non-nested directories on local fixed drives and run
  the updater from outside both. Absolute drive paths are required; UNC/device
  paths, path aliases, reparse points/junctions/symlinks and hard links fail closed.
- Both bundles must have `holistic_anecdotal_records.exe`, `flutter_windows.dll`,
  `data\icudtl.dat`, and `data\flutter_assets\`. These are plausibility checks,
  not authentication or a guarantee that a release is valid. Use trusted, complete
  staged bundles only.
- Drive/user/system roots are rejected, as are Windows, ProgramData, per-user
  AppData trees and the protected `Documents\HolisticAnecdotalRecords` tree.
  This intentionally also excludes installations inside AppData in this phase.
  Windows known folders and their resolved paths are checked.
- Before copying, the tool inspects both trees and locks source files and existing
  destinations against concurrent writers, and pins directories against renaming.
  Existing files are overwritten through the validated handles. New files use
  exclusive creation. Writes stay within the validated application directory.
- Files absent from the staged bundle are preserved. There is no recursive
  deletion, stale-file cleanup, rollback, or automatic restart. Exit code `0`
  means the copy completed; nonzero means failure. A copy failure can leave a
  partial bundle: do not launch it until a complete bundle is restored or the
  copy succeeds. Close all apps using the bundle before retrying.
- Diagnostics go only to standard output/error, with no log file and no user
  record/credential contents. Events identify validation, waiting, copying and
  success/failure; no restart is attempted. The updater requests no elevation.

Run the safe rejection tests after building:

```powershell
& .\windows\updater\test_validation.ps1
```

The tests create disposable marker bundles beneath `build\updater-validation-*`,
check rejection and unchanged fixture hashes, and retain the fixtures for
inspection. They do not run a successful update or modify real user data.

For the separately approved Phase 3B test, prepare isolated copies of complete
`1.0.0+1` and `1.0.1+2` Windows release bundles as `installed` and `staged`, keep
the updater outside both, close the test app, and invoke the command above.
Check the exit code and diagnostics before manually launching the test copy;
verify its About/version resources and supporting bundle files. Keep production
installations and user data out of the test. Launching an ordinary app copy still
uses the current Windows user's persistent data, so use a separate Windows test
account for the runtime check. **Phase 3B preparation is authorized; runtime
replacement and persistence verification have not yet been performed.** The
initialized test account is `HARUpdaterTest` (`C:\Users\HARUpdaterTest`). The
Addmin session is for builds/preparation only: never launch the test application
there or copy its production records/configuration into the test account.
The current preparation handoff is under `build\phase3b-preparation`; follow
the transfer package's `START-HERE.md` and stop after the test-account baseline
is recorded, before invoking the updater.
