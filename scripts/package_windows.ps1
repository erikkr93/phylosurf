param(
    [switch]$Rebuild,
    [string]$FlutterBin = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if (-not $FlutterBin) {
    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCmd) {
        $FlutterBin = $flutterCmd.Source
    } elseif (Test-Path "C:\Users\erikkr\flutter\bin\flutter.bat") {
        $FlutterBin = "C:\Users\erikkr\flutter\bin\flutter.bat"
    } else {
        $FlutterBin = "flutter"
    }
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$PubspecPath = Join-Path $RepoRoot "pubspec.yaml"
$ReleaseDir = Join-Path $RepoRoot "build\windows\x64\runner\Release"
$DistDir = Join-Path $RepoRoot "dist"
$IssPath = Join-Path $RepoRoot "installer\phylosurf.iss"

# Read version from pubspec.yaml (strip +build suffix for filenames)
$versionMatch = Select-String -Path $PubspecPath -Pattern '^\s*version:\s*([^\s+]+)' | Select-Object -First 1
$AppVersion = if ($versionMatch) { $versionMatch.Matches[0].Groups[1].Value } else { "1.0.0" }

if ($Rebuild -or -not (Test-Path (Join-Path $ReleaseDir "phylosurf.exe"))) {
    Write-Host "Building Flutter Windows release..." -ForegroundColor Cyan
    & $FlutterBin build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter build failed with exit code $LASTEXITCODE"
    }
}

# Stage release bundle + MSVC runtime DLLs for self-contained distribution
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$StageName = "PhyloSurf-$AppVersion-Windows-x64"
$StageDir = Join-Path $DistDir $StageName
if (Test-Path $StageDir) {
    Remove-Item -Recurse -Force $StageDir
}
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

Copy-Item -Path (Join-Path $ReleaseDir "*") -Destination $StageDir -Recurse -Force

$vcRuntimeDlls = @("vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll")
foreach ($dll in $vcRuntimeDlls) {
    $sysPath = Join-Path "$env:SystemRoot\System32" $dll
    if (Test-Path $sysPath) {
        Copy-Item -Path $sysPath -Destination $StageDir -Force
    }
}

# 1. Create Portable ZIP archive
$ZipPath = Join-Path $DistDir "$StageName-Portable.zip"
if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath
}
Write-Host "Creating portable ZIP: $ZipPath" -ForegroundColor Cyan
Compress-Archive -Path $StageDir -DestinationPath $ZipPath -CompressionLevel Optimal

# 2. Build Inno Setup installer
$isccCandidates = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$IsccPath = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $IsccPath) {
    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) { $IsccPath = $cmd.Source }
}
if (-not $IsccPath) {
    throw "Inno Setup (ISCC.exe) not found. Install it via: winget install JRSoftware.InnoSetup"
}

Write-Host "Building Inno Setup installer with $IsccPath..." -ForegroundColor Cyan
& $IsccPath "/DMyAppVersion=$AppVersion" "/DSourceDir=$StageDir" "/DOutputDir=$DistDir" $IssPath
if ($LASTEXITCODE -ne 0) {
    throw "ISCC failed with exit code $LASTEXITCODE"
}

# Clean up staging folder so dist/ only contains final distributables
Remove-Item -Recurse -Force $StageDir

Write-Host ""
Write-Host "Distribution packages ready in ${DistDir}:" -ForegroundColor Green
Get-ChildItem -Path $DistDir -File | Format-Table Name, @{Label="Size (MB)"; Expression={[math]::Round($_.Length / 1MB, 2)}}, LastWriteTime -AutoSize
