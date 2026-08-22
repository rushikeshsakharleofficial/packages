$ErrorActionPreference = "Stop"
$Project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Build = Join-Path $Project "build"
$Payload = Join-Path $Build "stage\payload"
$Native = Join-Path $Build "native"
$Dist = Join-Path $Project "dist"
if (-not (Test-Path (Join-Path $Payload "rsync.exe"))) { throw "Run scripts/build-windows.ps1 first" }
New-Item -ItemType Directory -Force $Dist | Out-Null

if (-not (Get-Command candle.exe -ErrorAction SilentlyContinue)) {
  if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
    choco install wixtoolset -y --no-progress
  }
}
$wix = Get-ChildItem "${env:ProgramFiles(x86)}\WiX Toolset*\bin\candle.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $wix) { throw "WiX Toolset v3 not found" }
$wixbin = Split-Path $wix.FullName
$heat = Join-Path $wixbin "heat.exe"
$candle = Join-Path $wixbin "candle.exe"
$light = Join-Path $wixbin "light.exe"

# Harvest a clean MSI payload. rsync-service.exe is installed explicitly by
# Product.wxs because ServiceInstall must live in the executable's component.
# Keep the service EXE in the original payload so the portable ZIP still gets it.
$MsiPayload = Join-Path $Build "msi-payload"
Remove-Item -Recurse -Force $MsiPayload -ErrorAction SilentlyContinue
Copy-Item -Recurse $Payload $MsiPayload
Remove-Item (Join-Path $MsiPayload "rsync-service.exe") -Force -ErrorAction SilentlyContinue

$harvest = Join-Path $Build "PayloadFiles.wxs"
& $heat dir $MsiPayload -cg PayloadComponents -dr INSTALLFOLDER -gg -scom -sreg -sfrag -srd -var var.PayloadDir -out $harvest
if ($LASTEXITCODE -ne 0) { throw "heat.exe failed" }

$objdir = Join-Path $Build "wixobj"
New-Item -ItemType Directory -Force $objdir | Out-Null
$product = Join-Path $Project "installer\Product.wxs"
$service = Join-Path $Native "rsync-service.exe"
$config = Join-Path $Project "installer\rsyncd.conf.example"
& $candle -nologo -arch x64 "-dPayloadDir=$MsiPayload" "-dServiceExe=$service" "-dConfigExample=$config" -out "$objdir\" $product $harvest
if ($LASTEXITCODE -ne 0) { throw "candle.exe failed" }

$out = Join-Path $Dist "rsync-windows-3.5.0-x64.msi"
& $light -nologo -out $out (Join-Path $objdir "Product.wixobj") (Join-Path $objdir "PayloadFiles.wixobj")
if ($LASTEXITCODE -ne 0) { throw "light.exe failed" }

$zip = Join-Path $Dist "rsync-windows-3.5.0-x64-portable.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $Payload "*") -DestinationPath $zip -CompressionLevel Optimal
Get-FileHash -Algorithm SHA256 $out, $zip | Format-Table
Write-Host "MSI: $out"
Write-Host "ZIP: $zip"
