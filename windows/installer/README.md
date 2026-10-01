# Phase 3C Windows installer

Preparation only. Do not run the installer until an installation test is approved.

From the project root:

```powershell
& C:\Development\flutter\bin\flutter.bat build windows --release --no-pub
& .\windows\installer\build-installer.ps1
# For a nonstandard compiler location:
& .\windows\installer\build-installer.ps1 -CompilerPath 'D:\Tools\Inno Setup 6\ISCC.exe'
```

If local PowerShell policy blocks the helper, use a process-only policy override
for this reviewed script (does not change the machine's execution policy):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\installer\build-installer.ps1
```

Requires Inno Setup 6.3 or newer, installed separately. The helper never installs
software or runs the resulting installer. It derives the display/file version
from `pubspec.yaml` (currently `1.0.1+2` becomes `1.0.1`), checks the executable
and bundled pubspec versions, checks the reference database hash, and checks
required files. It does not change the project version or build the app itself.

- Script: `windows/installer/HolisticAnecdotalRecords.iss`
- Source: `build/windows/x64/runner/Release`
- Output: `build/installer/HolisticAnecdotalRecords-Setup-1.0.1.exe`
- Default destination: `C:\Program Files\Holistic Anecdotal Records`
- Per-machine installation, administrator elevation, stable AppId, Windows
  uninstall entry, all-users Start Menu shortcut, unchecked optional Desktop shortcut.
- No post-install launch, automatic app shutdown, or restart.

## Payload and data protection

The `[Files]` section explicitly lists the complete required runtime: application
EXE, Flutter/plugin/native DLLs, AOT code, ICU data, manifests, fonts, shaders,
images, bundled pubspec, license notices and the plugin HTML asset. Review this
list whenever Flutter, plugins or application assets change. Additional DLLs
cause the helper to stop for review.

Only `data/flutter_assets/assets/database/locations.db` is included as SQLite
content: it is the required project geographic reference asset, hash-checked
against `assets/database/locations.db`. No user database is included.

The source release directory may contain development leftovers. Explicit entries
exclude its `.dart_tool` database, all Google OAuth JSON assets (including test
credentials), root `native_assets.json` build metadata containing a developer
path, preferences, school settings, backups, test records, Phase 3B bundles and
preparation files. The source assets and release files are not deleted to perform
these exclusions. AssetManifest may retain names of excluded OAuth files; it
contains asset paths, not the credential JSON contents. Google sync needs the
user's separately configured external OAuth configuration.

There are no reads/copies from persistent user directories, user-area installer
entries, recursive delete rules, custom uninstall commands, or permission grants.
Normal Inno uninstall removes tracked program files, installer metadata and
shortcuts only. It does not remove Documents data, AppData preferences, backups,
school settings or counselor records. Unknown files added later are not subject
to a recursive cleanup rule; updater-added program files may therefore remain.

## Program Files limitations to resolve before deployment

The standalone local updater preserves this bundle layout, but requests no
elevation and writes directly to target program files. A normal user cannot
update a Program Files installation. An explicitly elevated updater process is
needed with the present architecture; the updater must remain outside both the
installed and staged bundles. This installer does not ship or redesign it, grant
write access to Program Files, or arrange elevation/relaunch.

The location-reference working-directory write has been fixed in source.
`LocationsDatabase` now copies the bundled `assets/database/locations.db` into
`getApplicationSupportDirectory()/reference_data/locations.db` and opens it
read-only. On Windows this is the per-user Roaming AppData application directory
(`%APPDATA%\com.example\holistic_anecdotal_records\reference_data\locations.db`
with the current executable metadata). Copying is needed to give SQLite a real
filesystem file; runtime queries do not modify reference records. Neither the
copy nor its temporary file uses the install directory or working directory.
Existing working-directory copies are left alone, with no migration/deletion.
Counselor storage is unchanged. The bundled reference remains in the installer.

Rebuild the Windows release after this source fix before any future approved
installer compilation; the earlier release build predates it. An approved
isolated installation test is still required before deployment.

Inno references: [administrative installation](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm),
[file installation and uninstall tracking](https://jrsoftware.org/ishelp/topic_filessection.htm),
[x64 architecture settings](https://jrsoftware.org/ishelp/topic_setup_architecturesallowed.htm).

## Preparation verification (2026-09-25)

- Windows release build at unchanged `1.0.0+1`: succeeded.
- `flutter analyze --no-pub`: no issues found.
- Helper preflight: 22 explicit payload files validated, version and reference
  database hash checks passed.
- Compiler not found in PATH, standard Program Files/local Programs locations,
  or registered Inno Setup applications. Compilation could not proceed during
  that verification; no setup EXE was generated at that time.
- No installer, updater or application was launched. No production persistent
  data directory was accessed or modified. No authorization/access codes added.

## Subsequent local artifact evidence (2026-10-02)

Before the Phase 1A-2 rebuild, the existing local
`build/installer/HolisticAnecdotalRecords-Setup-1.0.0.exe` was observed
(18,098,839 bytes, last modified 2026-10-01, product version `1.0.0`). This
supersedes the earlier absence of installer output. The artifact alone does not
prove which source revision produced it or that installation/runtime tests passed.

During Phase 1A-2, the helper validated 25 explicit payload files against the
rebuilt Windows release at `1.0.0+1`, and Inno Setup 7.1.0 successfully compiled
a fresh installer at the same output path. The installer was not run; installation
and runtime persistence verification remain outstanding.
