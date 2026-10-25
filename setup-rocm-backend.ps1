<#
.SYNOPSIS
    Automated Setup and Installer for PrismML AMD ROCm/HIP and Vulkan Runtimes in LM Studio.
.DESCRIPTION
    Installs precompiled PrismML llama.cpp backends into LM Studio's extensions directory.
    Specially tuned for AMD Radeon RX 9070 XT / RX 9000 Series (RDNA 4, gfx1201/gfx1200)
    as well as RX 7000 Series (RDNA 3, gfx1100-gfx1151).
    
    Can be run STANDALONE with a single command without cloning the repository:
    powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/zfzfg/llama.cpp-PrismML-Fork-LmStudio/feat/rocm-vulkan-rx9070xt/setup-rocm-backend.ps1 | iex"
#>

[CmdletBinding()]
param (
    [ValidateSet("all", "rocm", "vulkan")]
    [string]$Backend = "all",
    
    [switch]$SkipHardwareCheck,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  PrismML LM Studio Extension Setup (AMD ROCm / Vulkan)   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# Constants
$PrismTag = "prism-b10809-b3ebc47"
$HipZipUrl = "https://github.com/PrismML-Eng/llama.cpp/releases/download/$PrismTag/llama-prism-b10809-b3ebc47-bin-win-hip-radeon-x64.zip"
$VulkanZipUrl = "https://github.com/PrismML-Eng/llama.cpp/releases/download/$PrismTag/llama-prism-b10809-b3ebc47-bin-win-vulkan-x64.zip"

$HipDirName = "llama.cpp-prism-b10809-b3ebc47-bin-win-hip-radeon-x64-lm-studio"
$VulkanDirName = "llama.cpp-prism-b10809-b3ebc47-bin-win-vulkan-x64-lm-studio"

# 1. Detect LM Studio extensions directory
$lmStudioBackendsPath = Join-Path $env:USERPROFILE ".lmstudio\extensions\backends"
Write-Host "[1/4] Checking LM Studio installation..." -ForegroundColor Yellow
if (-not (Test-Path $lmStudioBackendsPath)) {
    Write-Host "Creating LM Studio extensions directory at: $lmStudioBackendsPath" -ForegroundColor Gray
    New-Item -ItemType Directory -Path $lmStudioBackendsPath -Force | Out-Null
} else {
    Write-Host "Found LM Studio extensions directory: $lmStudioBackendsPath" -ForegroundColor Green
}

# 2. Check AMD Hardware
if (-not $SkipHardwareCheck) {
    Write-Host "`n[2/4] Detecting GPU Hardware..." -ForegroundColor Yellow
    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -Property Caption, DriverVersion, VideoProcessor
        $amds = $gpus | Where-Object { $_.Caption -match "AMD|Radeon" }
        
        if ($amds) {
            foreach ($amd in $amds) {
                Write-Host "  [+] Found AMD GPU: $($amd.Caption) (Driver: $($amd.DriverVersion))" -ForegroundColor Green
                if ($amd.Caption -match "9070|9000") {
                    Write-Host "      Detected AMD RDNA 4 architecture (Navi 48 / gfx1201)." -ForegroundColor Cyan
                    Write-Host "      Targeted explicitly in PrismML backend manifest!" -ForegroundColor Cyan
                } elseif ($amd.Caption -match "7900|7800|7700|7600") {
                    Write-Host "      Detected AMD RDNA 3 architecture (gfx1100-gfx1103)." -ForegroundColor Cyan
                }
            }
        } else {
            Write-Host "  [i] No AMD Radeon GPU detected on this system." -ForegroundColor Gray
            Write-Host "      (If installing for a friend or testing, installation will proceed normally)." -ForegroundColor Gray
        }
    } catch {
        Write-Host "  [!] Could not query GPU info: $($_.Exception.Message)" -ForegroundColor Gray
    }
} else {
    Write-Host "`n[2/4] Skipping hardware check as requested." -ForegroundColor Gray
}

# Helper: Download file using curl if available or Invoke-WebRequest
function Download-FileWithProgress {
    param([string]$Url, [string]$OutputFile, [string]$Desc)
    Write-Host "     Downloading $Desc..." -ForegroundColor Cyan
    $curlPath = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if ($curlPath) {
        & curl.exe -L --fail --progress-bar "$Url" -o "$OutputFile"
        if ($LASTEXITCODE -ne 0) { throw "Download failed for $Url (exit code $LASTEXITCODE)" }
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        Invoke-WebRequest -Uri $Url -OutFile $OutputFile -UseBasicParsing
    }
}

# Helper: Find LM Studio adapter files
function Get-LmStudioAdapterFiles {
    param([string]$DestinationDir)
    
    $commonFiles = @(
        "llm_engine.dll", "lmstudiocore.dll", "llm_engine.node", "liblmstudio_bindings.node",
        "ggml_llamacpp.dll", "MSVCP140.dll", "VCOMP140.dll", "VCRUNTIME140.dll", "VCRUNTIME140_1.dll"
    )
    
    # 1. Check if files are already in current script directory (e.g. if cloned)
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $localSources = @(
        (Join-Path $scriptDir "llama.cpp-prism-b10709-9a9394a-bin-win-cpu-x64-lm-studio"),
        (Join-Path $scriptDir "llama.cpp-prism-b10709-9a9394a-bin-win-cuda-13.3-x64-lm-studio&"),
        (Join-Path $scriptDir "llama.cpp-prism-b10809-b3ebc47-bin-win-hip-radeon-x64-lm-studio"),
        (Join-Path $scriptDir "llama.cpp-prism-b10809-b3ebc47-bin-win-vulkan-x64-lm-studio")
    )
    
    foreach ($loc in $localSources) {
        if (Test-Path (Join-Path $loc "llm_engine.dll")) {
            foreach ($f in $commonFiles) {
                $srcFile = Join-Path $loc $f
                if (Test-Path $srcFile) {
                    Copy-Item $srcFile $DestinationDir -Force
                }
            }
            return
        }
    }
    
    # 2. Check if already installed in another backend in LM Studio
    $installedDirs = Get-ChildItem -Path $lmStudioBackendsPath -Directory -ErrorAction SilentlyContinue
    foreach ($inst in $installedDirs) {
        if ($inst.FullName -ne $DestinationDir -and (Test-Path (Join-Path $inst.FullName "llm_engine.dll"))) {
            Write-Host "     Reusing LM Studio adapter binaries from existing backend: $($inst.Name)" -ForegroundColor Gray
            foreach ($f in $commonFiles) {
                $srcFile = Join-Path $inst.FullName $f
                if (Test-Path $srcFile) {
                    Copy-Item $srcFile $DestinationDir -Force
                }
            }
            return
        }
    }
}

# Manifest Generator
function Write-BackendManifests {
    param(
        [string]$TargetDir,
        [string]$Kind # 'rocm' or 'vulkan'
    )
    
    if ($Kind -eq "rocm") {
        $manifestJson = @'
{
  "version": "2.41.0",
  "domains": [
    "llm",
    "embedding"
  ],
  "engine": "llama.cpp",
  "extension_type": "engine",
  "target_libraries": [
    {
      "name": "llm_engine.node",
      "type": "llm_engine",
      "version": "0.1.2"
    },
    {
      "name": "liblmstudio_bindings.node",
      "type": "liblmstudio",
      "version": "0.2.26"
    }
  ],
  "platform": "win",
  "cpu": {
    "architecture": "x86_64",
    "instruction_set_extensions": [
      "AVX2"
    ]
  },
  "gpu": {
    "make": "AMD",
    "framework": "ROCm",
    "targets": [
      "gfx1010",
      "gfx1011",
      "gfx1012",
      "gfx1030",
      "gfx1031",
      "gfx1032",
      "gfx1033",
      "gfx1034",
      "gfx1035",
      "gfx1036",
      "gfx1100",
      "gfx1101",
      "gfx1102",
      "gfx1103",
      "gfx1150",
      "gfx1151",
      "gfx1152",
      "gfx1153",
      "gfx1200",
      "gfx1201"
    ]
  },
  "supported_model_formats": [
    "gguf"
  ],
  "manifest_version": "4",
  "minimum_lmstudio_version": "0.4.0+15",
  "minimum_llmster_version": "0.0.1+9",
  "engine_protocol_server": {
    "runtime_kind": "llama-server",
    "executable_relative_path": "llama-server.exe"
  },
  "name": "llama.cpp-win-x86_64-prism-rocm-rx9070"
}
'@
        $displayJson = @'
[["en",{"langKey":"en","displayName":"Prism ML AMD ROCm/HIP llama.cpp (Windows - RX 9070 XT / RDNA 4)","description":"AMD ROCm/HIP accelerated llama.cpp engine with native Prism ML PQ2_0 ternary model support for Radeon RX 7000 / 9000 series","releaseNotes":[{"version":"2.41.0","releaseNotes":"- Native AMD ROCm/HIP support for Windows\n- Full support for Radeon RX 9070 / 9070 XT (RDNA 4, gfx1201 / gfx1200) and RX 7000 series (RDNA 3, gfx1100-gfx1151)\n- Accelerated PrismML Bonsai ternary model inference (*-PQ2_0.gguf, *-Q2_0_g64.gguf)\n"}]}]]
'@
        $artifactsJson = @'
{
  "schema_version": 1,
  "runtime_kind": "llama-server",
  "executable_relative_path": "llama-server.exe",
  "files": [
    { "relative_path": "ggml-base.dll", "executable": false },
    { "relative_path": "ggml-cpu.dll", "executable": false },
    { "relative_path": "ggml-hip.dll", "executable": false },
    { "relative_path": "libhipblas.dll", "executable": false },
    { "relative_path": "libhipblaslt.dll", "executable": false },
    { "relative_path": "rocblas.dll", "executable": false },
    { "relative_path": "llama-common.dll", "executable": false },
    { "relative_path": "llama-server-impl.dll", "executable": false },
    { "relative_path": "llama-server.exe", "executable": true },
    { "relative_path": "llama.dll", "executable": false },
    { "relative_path": "mtmd.dll", "executable": false }
  ]
}
'@
    } else {
        $manifestJson = @'
{
  "version": "2.41.0",
  "domains": [
    "llm",
    "embedding"
  ],
  "engine": "llama.cpp",
  "extension_type": "engine",
  "target_libraries": [
    {
      "name": "llm_engine_vulkan.node",
      "type": "llm_engine",
      "version": "0.1.2"
    },
    {
      "name": "liblmstudio_bindings_vulkan.node",
      "type": "liblmstudio",
      "version": "0.2.26"
    }
  ],
  "platform": "win",
  "cpu": {
    "architecture": "x86_64",
    "instruction_set_extensions": [
      "AVX2"
    ]
  },
  "gpu": {
    "framework": "Vulkan"
  },
  "supported_model_formats": [
    "gguf"
  ],
  "manifest_version": "4",
  "vendor_lib_package_names": [
    "win-llama-vulkan-vendor-v3"
  ],
  "minimum_lmstudio_version": "0.4.0+15",
  "minimum_llmster_version": "0.0.1+9",
  "engine_protocol_server": {
    "runtime_kind": "llama-server",
    "executable_relative_path": "llama-server.exe"
  },
  "name": "llama.cpp-win-x86_64-prism-vulkan"
}
'@
        $displayJson = @'
[["en",{"langKey":"en","displayName":"Prism ML Vulkan llama.cpp (Windows - Universal / AMD Fallback)","description":"Vulkan accelerated llama.cpp engine with native Prism ML PQ2_0 ternary model support for all GPUs including AMD Radeon","releaseNotes":[{"version":"2.41.0","releaseNotes":"- Universal GPU acceleration via Vulkan (AMD, Intel, Nvidia)\n- Zero driver configuration required\n- Accelerated PrismML Bonsai ternary model inference (*-PQ2_0.gguf, *-Q2_0_g64.gguf)\n"}]}]]
'@
        $artifactsJson = @'
{
  "schema_version": 1,
  "runtime_kind": "llama-server",
  "executable_relative_path": "llama-server.exe",
  "files": [
    { "relative_path": "ggml-base.dll", "executable": false },
    { "relative_path": "ggml-cpu.dll", "executable": false },
    { "relative_path": "ggml-vulkan.dll", "executable": false },
    { "relative_path": "llama-common.dll", "executable": false },
    { "relative_path": "llama-server-impl.dll", "executable": false },
    { "relative_path": "llama-server.exe", "executable": true },
    { "relative_path": "llama.dll", "executable": false },
    { "relative_path": "mtmd.dll", "executable": false }
  ]
}
'@
    }
    
    [System.IO.File]::WriteAllText((Join-Path $TargetDir "backend-manifest.json"), $manifestJson)
    [System.IO.File]::WriteAllText((Join-Path $TargetDir "display-data.json"), $displayJson)
    [System.IO.File]::WriteAllText((Join-Path $TargetDir "engine-protocol-server-artifacts.json"), $artifactsJson)
}

# 3. Installation function
function Install-Backend {
    param(
        [string]$TargetName,
        [string]$ZipUrl,
        [string]$DisplayName,
        [string]$Kind
    )
    
    $dest = Join-Path $lmStudioBackendsPath $TargetName
    Write-Host "`n  -> Installing $DisplayName..." -ForegroundColor Cyan
    Write-Host "     Destination: $dest" -ForegroundColor Gray
    
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $localSource = Join-Path $scriptDir $TargetName
    
    if (Test-Path (Join-Path $localSource "llama-server.exe")) {
        Write-Host "     [Fast Path] Using local repository files..." -ForegroundColor Green
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        & robocopy $localSource $dest /E /NFL /NDL /NJH /NJS | Out-Null
        if ($LASTEXITCODE -gt 7) {
            Write-Host "     [ERROR] Robocopy failed with exit code $LASTEXITCODE" -ForegroundColor Red
            return $false
        }
    } else {
        # Standalone / Remote Path: Download from GitHub Release directly
        Write-Host "     [Standalone Path] Downloading precompiled release from GitHub CDN..." -ForegroundColor Yellow
        $tempZip = Join-Path $env:TEMP "$TargetName.zip"
        
        try {
            Download-FileWithProgress -Url $ZipUrl -OutputFile $tempZip -Desc "$DisplayName ($PrismTag)"
            
            Write-Host "     Extracting archive to destination..." -ForegroundColor Cyan
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            
            $tarPath = Get-Command "tar.exe" -ErrorAction SilentlyContinue
            if ($tarPath) {
                & tar.exe -xf "$tempZip" -C "$dest"
            } else {
                Expand-Archive -Path $tempZip -DestinationPath $dest -Force
            }
            
            # Setup CPU compatibility link
            if (Test-Path (Join-Path $dest "ggml-cpu-x64.dll")) {
                Copy-Item (Join-Path $dest "ggml-cpu-x64.dll") (Join-Path $dest "ggml-cpu.dll") -Force
            }
            
            # Write Manifests directly
            Write-BackendManifests -TargetDir $dest -Kind $Kind
            
            # Copy LM Studio adapters
            Get-LmStudioAdapterFiles -DestinationDir $dest
            
        } finally {
            if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
        }
    }
    
    # Verify installation
    $testServer = Join-Path $dest "llama-server.exe"
    if (Test-Path $testServer) {
        try {
            $ver = cmd.exe /c "`"$testServer`" --version 2>&1" | Select-Object -First 1
            if ($ver) {
                Write-Host "     [OK] Server verified: $ver" -ForegroundColor Green
            } else {
                Write-Host "     [OK] Server verified: llama-server.exe ready" -ForegroundColor Green
            }
        } catch {
            Write-Host "     [OK] Server verified: llama-server.exe ready" -ForegroundColor Green
        }
        return $true
    } else {
        Write-Host "     [ERROR] llama-server.exe not found at $testServer" -ForegroundColor Red
        return $false
    }
}

Write-Host "`n[3/4] Installing Backends..." -ForegroundColor Yellow

if ($Backend -eq "all" -or $Backend -eq "rocm") {
    Install-Backend -TargetName $HipDirName `
        -ZipUrl $HipZipUrl `
        -DisplayName "PrismML AMD ROCm/HIP (Radeon RX 9070 XT / RDNA 4)" `
        -Kind "rocm" | Out-Null
}

if ($Backend -eq "all" -or $Backend -eq "vulkan") {
    Install-Backend -TargetName $VulkanDirName `
        -ZipUrl $VulkanZipUrl `
        -DisplayName "PrismML Vulkan (Universal Fallback)" `
        -Kind "vulkan" | Out-Null
}

# 4. Verify with LM Studio CLI
Write-Host "`n[4/4] Verifying with LM Studio..." -ForegroundColor Yellow
$lmsPath = Join-Path $env:LOCALAPPDATA "Programs\LM Studio\resources\app\.webpack\lms.exe"
if (Test-Path $lmsPath) {
    Write-Host "Querying LM Studio installed runtime engines via 'lms runtime ls'..." -ForegroundColor Gray
    Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
    try {
        & $lmsPath runtime ls
    } catch {
        Write-Host "     Note: CLI query skipped: $($_.Exception.Message)" -ForegroundColor Gray
    }
    Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
} else {
    Write-Host "LM Studio CLI not found at default location. Manual check in GUI required." -ForegroundColor Gray
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "                Installation Completed!                   " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps for LM Studio:" -ForegroundColor Yellow
Write-Host "1. Restart LM Studio (close and open again)."
Write-Host "2. Go to Settings (gear icon) -> 'Runtime' -> Under GGUF select:"
Write-Host "   - 'Prism ML AMD ROCm/HIP llama.cpp (Windows - RX 9070 XT / RDNA 4)'" -ForegroundColor Cyan
Write-Host "   - Or 'Prism ML Vulkan llama.cpp (Windows - Universal / AMD Fallback)'" -ForegroundColor Cyan
Write-Host "3. Load your PrismML model (*-PQ2_0.gguf or *-Q2_0_g64.gguf)."
Write-Host "4. Enjoy hardware-accelerated 1-bit / ternary inference!"
Write-Host ""
Write-Host "Troubleshooting note for RX 9070 XT:" -ForegroundColor Gray
Write-Host "If LM Studio shows 'No supported ROCm GPUs found', set this in Windows Environment Variables:" -ForegroundColor Gray
Write-Host "   HSA_OVERRIDE_GFX_VERSION = 12.0.1" -ForegroundColor Yellow
Write-Host ""
