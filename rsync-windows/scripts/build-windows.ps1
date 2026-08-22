param(
  [string]$RsyncVersion = "3.5.0",
  [string]$CygwinRoot = "C:\cygwin64"
)
$ErrorActionPreference = "Stop"
$Project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Build = Join-Path $Project "build"
$Stage = Join-Path $Build "stage"
$Payload = Join-Path $Stage "payload"
$PayloadBin = Join-Path $Payload "bin"
$PayloadEtc = Join-Path $Payload "etc"
$Native = Join-Path $Build "native"
$Dist = Join-Path $Project "dist"
New-Item -ItemType Directory -Force $Build,$Stage,$Payload,$Native,$Dist | Out-Null

Write-Host "[1/7] Installing Cygwin build dependencies"
$Setup = Join-Path $Build "setup-x86_64.exe"
Invoke-WebRequest "https://cygwin.com/setup-x86_64.exe" -OutFile $Setup
# libxxhash-devel currently does not depend on its runtime package, so request
# libxxhash0 explicitly. The other development libraries pull their runtimes.
$Pkgs = "make,gawk,gcc-core,gcc-g++,attr,libattr-devel,libzstd-devel,liblz4-devel,libssl-devel,libidn2-devel,libxxhash-devel,libxxhash0"
$setupArgs = @(
  "-q", "-n", "-N", "-d",
  "-R", $CygwinRoot,
  "-s", "https://mirrors.kernel.org/sourceware/cygwin/",
  "-P", $Pkgs
)
$setupProcess = Start-Process -FilePath $Setup -ArgumentList $setupArgs -Wait -PassThru -NoNewWindow
if ($setupProcess.ExitCode -ne 0) { throw "Cygwin setup failed: $($setupProcess.ExitCode)" }
$CygwinBin = Join-Path $CygwinRoot "bin"
if (-not (Test-Path (Join-Path $CygwinBin "bash.exe"))) { throw "Cygwin setup completed but bash.exe is missing" }
$env:PATH = "$CygwinBin;$env:PATH"

Write-Host "[2/7] Downloading upstream rsync $RsyncVersion"
$Tar = Join-Path $Build "rsync-$RsyncVersion.tar.gz"
Invoke-WebRequest "https://github.com/RsyncProject/rsync/releases/download/v$RsyncVersion/rsync-$RsyncVersion.tar.gz" -OutFile $Tar
if ($RsyncVersion -eq "3.5.0") {
  $md5 = (Get-FileHash -Algorithm MD5 $Tar).Hash.ToLowerInvariant()
  if ($md5 -ne "418db7651d1acf55364b0834234dbbfb") { throw "Upstream tarball MD5 mismatch: $md5" }
}

Write-Host "[3/7] Building upstream rsync with Cygwin"
$cygbash = Join-Path $CygwinBin "bash.exe"
$buildCyg = (& (Join-Path $CygwinBin "cygpath.exe") -u $Build).Trim()
& $cygbash -lc "set -e; cd '$buildCyg'; rm -rf rsync-$RsyncVersion; tar -xzf rsync-$RsyncVersion.tar.gz; cd rsync-$RsyncVersion; ./configure --with-included-popt --with-included-zlib; make -j2; ./rsync.exe --version"
if ($LASTEXITCODE -ne 0) { throw "rsync build or version check failed: $LASTEXITCODE" }
$core = Join-Path $Build "rsync-$RsyncVersion\rsync.exe"

Write-Host "[4/7] Building native Windows launcher/service"
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$vs = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
if (-not $vs) { throw "Visual Studio C++ build tools not found" }
$devcmd = Join-Path $vs "Common7\Tools\VsDevCmd.bat"
$launchC = Join-Path $Project "src\rsync-launcher.c"
$svcC = Join-Path $Project "src\rsync-service.c"
$launchExe = Join-Path $Native "rsync.exe"
$svcExe = Join-Path $Native "rsync-service.exe"
$compile = "call `"$devcmd`" -arch=x64 && cl /nologo /O2 /MT /DUNICODE /D_UNICODE /Fe:`"$launchExe`" `"$launchC`" && cl /nologo /O2 /MT /DUNICODE /D_UNICODE /Fe:`"$svcExe`" `"$svcC`" advapi32.lib"
cmd.exe /d /s /c $compile
if ($LASTEXITCODE -ne 0) { throw "MSVC build failed: $LASTEXITCODE" }

Write-Host "[5/7] Staging portable rsync runtime"
Remove-Item -Recurse -Force $Payload -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Payload,$PayloadBin,$PayloadEtc | Out-Null
Copy-Item $launchExe (Join-Path $Payload "rsync.exe")
Copy-Item $svcExe (Join-Path $Payload "rsync-service.exe")
$coreDest = Join-Path $PayloadBin "rsync-core.exe"
Copy-Item $core $coreDest
Copy-Item (Join-Path $Build "rsync-$RsyncVersion\COPYING") (Join-Path $Payload "COPYING.txt")
Copy-Item (Join-Path $Project "README.md") (Join-Path $Payload "README.txt")
Set-Content -Encoding ASCII -Path (Join-Path $PayloadEtc "fstab") -Value "none /cygdrive cygdrive binary,posix=0,user 0 0"

# Do not rely on Windows cygcheck dependency resolution here. A Cygwin-linked
# executable resolves its runtime DLLs from the executable directory. Stage
# the complete Cygwin DLL set installed for this build into payload\bin. This
# is deliberately conservative and makes the MSI/ZIP independent of any
# machine-wide Cygwin installation or registry state.
$runtimeDlls = Get-ChildItem -Path $CygwinBin -Filter "cyg*.dll" -File
if (-not $runtimeDlls) { throw "No Cygwin runtime DLLs found in $CygwinBin" }
foreach ($dll in $runtimeDlls) {
  Copy-Item $dll.FullName (Join-Path $PayloadBin $dll.Name) -Force
}
if (-not (Test-Path (Join-Path $PayloadBin "cygwin1.dll"))) { throw "cygwin1.dll was not staged" }
foreach ($required in @("cygcrypto-3.dll","cygiconv-2.dll","cygintl-8.dll","cyglz4-1.dll","cygzstd-1.dll","cygxxhash-0.dll")) {
  if (-not (Test-Path (Join-Path $PayloadBin $required))) { throw "Required runtime DLL missing: $required" }
}

Write-Host "[6/7] Smoke-testing packaged command and Windows paths"
Push-Location $Payload
try {
  & .\rsync.exe --version
  if ($LASTEXITCODE -ne 0) { throw "Packaged rsync --version failed" }
  New-Item -ItemType Directory -Force test-src,test-dst | Out-Null
  Set-Content -Path test-src\hello.txt -Value "rsync windows smoke test"
  & .\rsync.exe -av "$(Resolve-Path test-src)\" "$(Resolve-Path test-dst)\"
  if ($LASTEXITCODE -ne 0) { throw "Local rsync smoke test failed" }
  if (-not (Test-Path test-dst\hello.txt)) { throw "Smoke-test destination file missing" }
  Remove-Item -Recurse -Force test-src,test-dst
} finally { Pop-Location }

Write-Host "[7/7] Payload ready: $Payload"
