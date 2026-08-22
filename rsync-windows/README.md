# Rsync for Windows build project

This project packages upstream **rsync 3.5.0** for Windows while preserving rsync's normal CLI, wire protocol, daemon mode, filters, checksums, compression and exit codes.

## What this build is

- `rsync.exe`: small native Windows launcher that accepts normal Windows paths such as `C:\Data\` and translates them for the rsync core.
- `rsync-core.exe`: upstream rsync 3.5.0 built on Cygwin's POSIX compatibility runtime.
- Bundled Cygwin runtime DLLs required by the core; no separate Cygwin installation is required after packaging.
- `rsync-service.exe`: native Windows Service host for `rsync --daemon`.
- MSI installer adds the install directory to the machine `PATH` and installs the daemon service in **Manual** start mode.

This is deliberately a compatibility build, not a claim that upstream rsync has been fully rewritten against raw Win32 APIs. A runtime-free native port requires replacing rsync's Unix `fork()` process model and mapping filesystem semantics that Windows does not implement 1:1.

## Examples

```powershell
rsync --version
rsync -av C:\Data\ D:\Backup\
rsync -av --delete C:\Data\ user@linux-server:/backup/
rsync -aHAX user@linux-server:/data/ C:\Restore\
rsync server::module
```

Windows drive paths are accepted by the native launcher and converted to Cygwin paths before they reach upstream rsync.

## Daemon / Windows Service

The MSI installs a service named `RsyncDaemon` with manual start. No network share/module is enabled automatically.

Copy `C:\ProgramData\Rsync\rsyncd.conf.example` to `C:\ProgramData\Rsync\rsyncd.conf`, edit access rules, then start with `sc.exe start RsyncDaemon`.

If remote clients must connect to TCP 873, add a firewall rule yourself after you have secured `rsyncd.conf`.

## Build

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\build-windows.ps1
.\scripts\build-msi.ps1
```

Outputs:

```text
dist\rsync-windows-3.5.0-x64.msi
dist\rsync-windows-3.5.0-x64-portable.zip
```

## Licensing

The rsync core is upstream rsync and remains licensed under GNU GPL as provided by the upstream project. The package copies upstream `COPYING` into the installed payload. The small launcher/service sources are GPL-3.0-or-later.