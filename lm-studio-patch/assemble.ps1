#Requires -Version 5.1
<#
.SYNOPSIS
  Assemble full LM Studio backends from the adaptation layer + vanilla llama.cpp release zips.

.DESCRIPTION
  The lm-studio-patch\backends folders contain ONLY the LM Studio adaptation files
  (manifests, LM Studio bindings, shim, renamed server). This script combines them
  with the vanilla llama.cpp prebuilt release zips (build\release) to produce complete
  backend folders that install.ps1 can install.

.EXAMPLE
  .\assemble.ps1
  .\assemble.ps1 -OutDir C:\tmp\out
#>
param(
    [string]$AdaptRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path),
    [string]$ReleaseDir = (Join-Path (Split-Path -Parent $AdaptRoot) 'build\release'),
    [string]$OutDir = (Join-Path (Split-Path -Parent $AdaptRoot) 'backends')
)
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Msg) Write-Host ("[" + (Get-Date -Format HH:mm:ss) + "] " + $Msg) -ForegroundColor Cyan }

# Files in the vanilla zips that are NOT part of the runtime backends (tools/docs/debug)
$Exclude = @(
    'llama-batched-bench*', 'llama-bench*', 'llama-cli*', 'llama-completion*',
    'llama-fit-params*', 'llama-gemma3-cli*', 'llama-gguf-split*', 'llama-imatrix*',
    'llama-llava-cli*', 'llama-minicpmv-cli*', 'llama-mtmd-cli*', 'llama-mtmd-debug*',
    'llama-perplexity*', 'llama-quantize*', 'llama-qwen2vl-cli*', 'llama-results*',
    'llama-template-analysis*', 'llama-tokenize*', 'llama-tts*',
    'llama-cvector-generator*', 'llama-export-lora*',
    'llama.exe', 'sycl-ls.exe', 'libomp140*', 'openvino_c.dll',
    '*_debug.dll', 'cache.json', 'LICENSE', 'EULA*', '*.txt', '*.htm', '*.rtf'
)

$Plan = @(
    @{ Name = 'llama.cpp-win-x86_64-sycl-avx2-2.29.1'; Zip = 'llama-b10516-bin-win-sycl-x64.zip' },
    @{ Name = 'llama.cpp-win-x86_64-openvino-avx2-2.29.1'; Zip = 'llama-b10516-bin-win-openvino-2026.3-x64.zip' }
)

Write-Step ('Adaptation : ' + $AdaptRoot)
Write-Step ('Releases   : ' + $ReleaseDir)
Write-Step ('Output     : ' + $OutDir)

foreach ($p in $Plan) {
    $zip = Join-Path $ReleaseDir $p.Zip
    if (-not (Test-Path $zip)) { throw 'Missing release zip: ' + $zip }
    $adapt = Join-Path (Join-Path $AdaptRoot 'backends') $p.Name
    if (-not (Test-Path $adapt)) { throw 'Missing adaptation folder: ' + $adapt }
    $dst = Join-Path $OutDir $p.Name
    Write-Step ('Assembling ' + $p.Name + ' ...')
    # 1) extract the vanilla release to a temp dir
    $tmp = Join-Path $env:TEMP ("lms-asm-" + [guid]::NewGuid().ToString("N"))
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    # 2) copy vanilla runtime files, skipping tools/docs/debug
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    $files = Get-ChildItem $tmp -File
    foreach ($f in $files) {
        $skip = $false
        foreach ($pat in $Exclude) { if ($f.Name -like $pat) { $skip = $true; break } }
        if (-not $skip) { Copy-Item $f.FullName $dst }
    }
    # 3) overlay the adaptation layer (manifests, bindings, shim, renamed server)
    Get-ChildItem $adapt -File | ForEach-Object { Copy-Item $_.FullName $dst -Force }
    Remove-Item $tmp -Recurse -Force
    $count = (Get-ChildItem $dst -File).Count
    Write-Step ('  OK (' + $count + ' files)')
}

Write-Step 'Done. Run install.ps1 (package root) to install into LM Studio.'
