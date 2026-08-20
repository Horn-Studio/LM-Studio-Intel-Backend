#Requires -Version 5.1
<#
.SYNOPSIS
  One-click installer for custom llama.cpp backends (SYCL + OpenVINO) for LM Studio.

.DESCRIPTION
  Copies the packaged backends from this patch\backends into the LM Studio
  extensions\backends folder. Kills running llama-server processes first so files are
  not locked. Optionally selects the engine via the lms CLI and optionally installs the
  OpenVINO toolkit (only needed for rebuilding from source, NOT for running).

.EXAMPLE
  .\install.ps1 -Force
  .\install.ps1 -SelectEngine sycl
  .\install.ps1 -InstallOvtk -SelectEngine none
#>
param(
    [string]$PatchRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path),
    [string]$LmStudioBackends = (Join-Path $env:USERPROFILE '.lmstudio\extensions\backends'),
    [ValidateSet('openvino', 'sycl', 'none')]
    [string]$SelectEngine = 'openvino',
    [switch]$InstallOvtk,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

$Backends = @(
    'llama.cpp-win-x86_64-sycl-avx2-2.29.1',
    'llama.cpp-win-x86_64-openvino-avx2-2.29.1'
)

function Write-Step { param([string]$Msg) Write-Host ("[" + (Get-Date -Format HH:mm:ss) + "] " + $Msg) -ForegroundColor Cyan }

Write-Step ('Patch root : ' + $PatchRoot)
Write-Step ('Target dir : ' + $LmStudioBackends)

# --- checks ---------------------------------------------------------------
foreach ($b in $Backends) {
    $src = Join-Path (Join-Path $PatchRoot 'backends') $b
    if (-not (Test-Path $src)) { throw 'Missing packaged backend: ' + $src }
}
if (-not (Test-Path $LmStudioBackends)) {
    throw "LM Studio backends folder not found: $LmStudioBackends`nStart LM Studio once so it creates the folder, then run this script again."
}

# --- stop running llama-server processes (avoid file locks) ---------------
$procs = Get-CimInstance Win32_Process -Filter "Name='llama-server.exe' or Name='llama-server-real.exe'" -ErrorAction SilentlyContinue
if ($procs) {
    $names = ($procs | ForEach-Object { $_.ProcessId }) -join ', '
    if (-not $Force) {
        $ans = Read-Host "Running llama-server processes (PIDs: $names) will be stopped. Continue? [y/N]"
        if ($ans -notmatch '^[yY]') { Write-Host 'Aborted.'; exit 1 }
    }
    $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Write-Step ('Stopped llama-server processes: ' + $names)
    Start-Sleep -Seconds 2
}

# --- copy backends ---------------------------------------------------------
foreach ($b in $Backends) {
    $src = Join-Path (Join-Path $PatchRoot 'backends') $b
    $dst = Join-Path $LmStudioBackends $b
    Write-Step ('Installing ' + $b + ' ...')
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item $src $dst -Recurse -Force
    $count = (Get-ChildItem $dst -File).Count
    Write-Step ('  OK (' + $count + ' files)')
}

# --- OpenVINO backend sanity check -----------------------------------------
$ov = Join-Path $LmStudioBackends 'llama.cpp-win-x86_64-openvino-avx2-2.29.1'
foreach ($need in @('llama-server.exe', 'llama-server-real.exe', 'openvino.dll', 'ggml-openvino.dll')) {
    if (-not (Test-Path (Join-Path $ov $need))) { throw 'OpenVINO backend incomplete: missing ' + $need }
}
Write-Step 'OpenVINO backend files verified (shim + runtime complete).'

# --- optional: OpenVINO toolkit (rebuilds only) -----------------------------
if ($InstallOvtk) {
    Write-Step 'Installing OpenVINO toolkit (pip) - only needed for rebuilding from source...'
    python -m pip install --disable-pip-version-check openvino
    if ($LASTEXITCODE -ne 0) { Write-Host "  pip install openvino failed. The backend does NOT need it to run." -ForegroundColor Yellow }
    else { Write-Step '  OpenVINO toolkit installed.' }
}

# --- optional: select engine via lms CLI ------------------------------------
$lms = $null
$appLoc = Join-Path $env:USERPROFILE '.lmstudio\.internal\app-install-location.json'
if (Test-Path $appLoc) {
    try {
        $j = Get-Content $appLoc -Raw | ConvertFrom-Json
        $cand = Join-Path (Split-Path $j.path) 'resources\app\.webpack\lms.exe'
        if (Test-Path $cand) { $lms = $cand }
    } catch {}
}
if (-not $lms) {
    foreach ($cand in @((Join-Path $env:LOCALAPPDATA "Programs\LM Studio\resources\app\.webpack\lms.exe"),
                        'D:\LMStudio\LM Studio\resources\app\.webpack\lms.exe')) {
        if (Test-Path $cand) { $lms = $cand; break }
    }
}
if ($lms) {
    Write-Step ('Found lms CLI: ' + $lms)
    if ($SelectEngine -ne 'none') {
        $eng = 'llama.cpp-win-x86_64-' + $SelectEngine + '-avx2@2.29.1'
        Write-Step ('Selecting engine: ' + $eng)
        & $lms runtime select $eng
        if ($LASTEXITCODE -ne 0) { Write-Host "  Engine selection failed - select it manually in LM Studio UI." -ForegroundColor Yellow }
    }
    Write-Step 'Engine list after install:'
    & $lms runtime ls
} else {
    Write-Host 'lms CLI not found - restart LM Studio and verify in the UI.' -ForegroundColor Yellow
}

Write-Step 'Done. Backends installed successfully.'
