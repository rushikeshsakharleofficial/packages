param(
  [string]$RsyncVersion = "3.5.0",
  [string]$CygwinRoot = "C:\cygwin64"
)
$ErrorActionPreference = "Stop"
$Project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Build = Join-Path $Project "build"
$Stage = Join-Path $Build "stage"
$Payload = Join-Path $Stage "payload"
$Native = Join-Path $Build "native"
$Dist = Join-Path $Project "dist"
New-Item -ItemType Directory -Force $Build,$Stage,$Payload,$Native,$Dist | Out-Null

Write-Host "[1/7] Installing Cygwin build dependencies"
$Setup = Join-Path $Build "setup-x86_64.exe"
Invoke-WebRequest "https://cygwin.com/setup-x86_64.exe" -OutFile $Setup
$Pkgs = "make,gawk,gcc-core,gcc-g++,attr,libattr-devel,libzstd-devel,liblz4-devel,libssl-devel,libidn2-devel,libxxhash-devel"
& $Setup -q -n -N -d -R $CygwinRoot -s "https://mirrors.kernel.org/sourceware/cygwin/" -P $Pkgs
if ($LASTEXITCODE -ne 0) { throw "Cygwin setup failed: $LASTEXITCODE" }

Write-Host "[2/7] Downloading upstream rsync $RsyncVersion"
$Tar = Join-Path $Build "rsync-$RsyncVersion.tar.gz"
Invoke-WebRequest "https://github.com/RsyncProject/rsync/releases/download/v$RsyncVersion/rsync-$RsyncVersion.tar.gz" -OutFile $Tar
if ($RsyncVersion -eq "3.5.0") {
  $md5 = (Get-FileHash -Algorithm MD5 $Tar).Hash.ToLowerInvariant()
  if ($md5 -ne "418db7651d1acf55364b0834234dbbfb") { throw "Upstream tarball MD5 mismatch: $md5" }
}

Write-Host "[3/7] Building upstream rsync with Cygwin"
$cygbash = Join-Path $CygwinRoot "bin\bash.exe"
$buildCyg = (& (Join-Path $CygwinRoot "bin\cygpath.exe") -u $Build).Trim()
& $cygbash -lc "set -e; cd '$buildCyg'; rm -rf rsync-$RsyncVersion; tar -xzf rsync-$RsyncVersion.tar.gz; cd rsync-$RsyncVersion; ./configure --with-included-popt --with-included-zlib; make -j2; ./rsync.exe --version"
if ($LASTEXITCODE -ne 0) { throw "rsync build failed: $LASTEXITCODE" }

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

Write-Host "[5/7] Staging rsync and runtime DLLs"
Remove-Item -Recurse -Force $Payload -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Payload | Out-Null
Copy-Item $launchExe (Join-Path $Payload "rsync.exe")
$core = Join-Path $Build "rsync-$RsyncVersion\rsync.exe"
$coreDest = Join-Path $Payload "rsync-core.exe"
Copy-Item $core $coreDest
Copy-Item (Join-Path $Build "rsync-$RsyncVersion\COPYING") (Join-Path $Payload "COPYING.txt")
Copy-Item (Join-Path $Project "README.md") (Join-Path $Payload "README.txt")

$cygcheck = Join-Path $CygwinRoot "bin\cygcheck.exe"
$deps = & $cygcheck $core | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^([A-Za-z]:\\.*\.dll)$' }
foreach ($dep in $deps) {
  if ($dep.StartsWith($CygwinRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    Copy-Item $dep (Join-Path $Payload ([IO.Path]::GetFileName($dep))) -Force
  }
}
if (-not (Test-Path (Join-Path $Payload "cygwin1.dll"))) { throw "cygwin1.dll was not staged" }

Write-Host "[6/7] Smoke-testing packaged command"
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
