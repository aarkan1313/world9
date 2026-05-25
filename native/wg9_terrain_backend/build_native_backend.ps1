$ErrorActionPreference = "Stop"

$backendRoot = $PSScriptRoot
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $backendRoot)
$projectRoot = Join-Path $workspaceRoot "wg-9-directory"
$godotBin = Join-Path $projectRoot "bin"
$godotCache = Join-Path $projectRoot ".godot"
$extensionResource = "res://wg9_terrain_backend.gdextension"

New-Item -ItemType Directory -Force -Path $godotBin | Out-Null
New-Item -ItemType Directory -Force -Path $godotCache | Out-Null

Push-Location $backendRoot
try {
    $env:CARGO_TARGET_DIR = Join-Path $backendRoot "target"
    cargo build --release
    if ($LASTEXITCODE -ne 0) {
        throw "cargo build failed with exit code $LASTEXITCODE"
    }
    $libraryName = if ($IsWindows -or $env:OS -eq "Windows_NT") {
        "wg9_terrain_backend.dll"
    } elseif ($IsMacOS) {
        "libwg9_terrain_backend.dylib"
    } else {
        "libwg9_terrain_backend.so"
    }
    $library = Join-Path $backendRoot "target\release\$libraryName"
    if (!(Test-Path $library)) {
        throw "Expected Rust GDExtension library not found: $library"
    }
    $projectLibrary = Join-Path $godotBin $libraryName
    Copy-Item -Force $library $projectLibrary
    $sourceHash = (Get-FileHash -Algorithm SHA256 $library).Hash
    $projectHash = (Get-FileHash -Algorithm SHA256 $projectLibrary).Hash
    if ($sourceHash -ne $projectHash) {
        throw "Copied DLL hash mismatch: source=$sourceHash project=$projectHash"
    }
    $pdb = Join-Path $backendRoot "target\release\wg9_terrain_backend.pdb"
    if (Test-Path $pdb) {
        $projectPdb = Join-Path $godotBin "wg9_terrain_backend.pdb"
        Copy-Item -Force $pdb $projectPdb
    }
}
finally {
    Pop-Location
}

$extensionList = Join-Path $godotCache "extension_list.cfg"
$entries = @()
if (Test-Path $extensionList) {
    $entries = @(Get-Content -Path $extensionList | Where-Object { $_.Trim().Length -gt 0 })
}
if ($entries -notcontains $extensionResource) {
    $entries += $extensionResource
    Set-Content -Path $extensionList -Value $entries -Encoding UTF8
}

Write-Output "Built Wg9TerrainNativeBackend -> $godotBin sha256=$sourceHash"
