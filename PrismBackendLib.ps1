# Pure helpers for the PrismML LM Studio installer.
# Dot-source this file. It does not change the machine by itself.

$script:PrismEngineRocm = "llama.cpp-win-x86_64-prism-rocm-rx9070"
$script:PrismEngineVulkan = "llama.cpp-win-x86_64-prism-vulkan"
$script:PrismPackageVersion = "2.64.0"
# Adapter contract used by the tested RX 9070 XT LM Studio bridge.
# These are registration versions, not a measurement of the .node binaries.
$script:PrismAdapterEngineVersion = "0.1.2"
$script:PrismAdapterBindingVersion = "0.2.26"

$script:PrismRequiredRuntimeFiles = @{
    rocm   = @(
        "llama-server.exe", "llama-server-impl.dll", "llama.dll", "llama-common.dll",
        "ggml.dll", "ggml-base.dll", "ggml-hip.dll", "libhipblas.dll", "libhipblaslt.dll", "rocblas.dll", "mtmd.dll"
    )
    vulkan = @(
        "llama-server.exe", "llama-server-impl.dll", "llama.dll", "llama-common.dll",
        "ggml.dll", "ggml-base.dll", "ggml-vulkan.dll", "mtmd.dll"
    )
}

$script:PrismRequiredAdapterFiles = @(
    "llm_engine_vulkan.node",
    "liblmstudio_bindings_vulkan.node"
)

function Get-PrismManagedEngineNames {
    @($script:PrismEngineRocm, $script:PrismEngineVulkan)
}

function ConvertTo-PrismJson {
    param($Value, [int]$Depth = 30)
    if ($Depth -lt 0) { return "null" }
    if ($null -eq $Value) { return "null" }
    if ($Value -is [string]) { return (ConvertTo-Json -InputObject $Value -Compress) }
    if ($Value -is [bool]) { if ($Value) { return "true" } else { return "false" } }
    if ($Value -is [ValueType]) { return (ConvertTo-Json -InputObject $Value -Compress) }
    if ($Value -is [pscustomobject]) {
        $parts = foreach ($prop in @($Value.PSObject.Properties | Where-Object { $_.MemberType -eq "NoteProperty" })) {
            $name = ConvertTo-Json -InputObject ([string]$prop.Name) -Compress
            $inner = ConvertTo-PrismJson -Value $prop.Value -Depth ($Depth - 1)
            "${name}:${inner}"
        }
        return "{" + (@($parts) -join ",") + "}"
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = foreach ($key in @($Value.Keys)) {
            $name = ConvertTo-Json -InputObject ([string]$key) -Compress
            $inner = ConvertTo-PrismJson -Value $Value[$key] -Depth ($Depth - 1)
            "${name}:${inner}"
        }
        return "{" + ($parts -join ",") + "}"
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = foreach ($item in @($Value)) {
            ConvertTo-PrismJson -Value $item -Depth ($Depth - 1)
        }
        return "[" + (@($parts) -join ",") + "]"
    }
    return "null"
}

function ConvertTo-PrismJsonArray {
    param([AllowEmptyCollection()][object[]]$Items)
    ConvertTo-PrismJson -Value @($Items)
}

function Merge-PrismGgufPreference {
    param(
        [AllowNull()][string]$ExistingJson,
        [Parameter(Mandatory)][string]$EngineName,
        [string]$Version = $script:PrismPackageVersion
    )
    $rows = @()
    if (-not [string]::IsNullOrWhiteSpace($ExistingJson)) {
        try {
            $parsed = $ExistingJson | ConvertFrom-Json
        } catch {
            throw "Preference JSON is invalid and was not modified: $($_.Exception.Message)"
        }
        if ($null -ne $parsed) { $rows = @($parsed) }
    }
    $kept = @($rows | Where-Object { $_.model_format -ne "gguf" })
    $row = [pscustomobject]@{
        model_format = "gguf"
        name         = $EngineName
        version      = $Version
    }
    $merged = @($kept + $row)
    [pscustomobject]@{
        Rows = $merged
        Json = (ConvertTo-PrismJsonArray -Items $merged)
    }
}

function Get-PrismMissingFiles {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Kind
    )
    $required = @($script:PrismRequiredRuntimeFiles[$Kind] + $script:PrismRequiredAdapterFiles)
    $missing = foreach ($rel in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $Directory $rel))) { $rel }
    }
    @($missing)
}

function Test-PrismServerVersion {
    <#
    .OUTPUTS
    FilesPresent, ServerStarted, ExitCode, Output, InferenceTested
    InferenceTested is always $false. --version does not load a model.
    #>
    param([Parameter(Mandatory)][string]$ServerPath)
    $result = [ordered]@{
        FilesPresent    = (Test-Path -LiteralPath $ServerPath)
        ServerStarted   = $false
        ExitCode        = $null
        Output          = ""
        InferenceTested = $false
    }
    if (-not $result.FilesPresent) {
        return [pscustomobject]$result
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ServerPath
    $psi.Arguments = "--version"
    $psi.WorkingDirectory = Split-Path -Parent $ServerPath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        $result.Output = $_.Exception.Message
        return [pscustomobject]$result
    }
    $result.ServerStarted = $true
    if (-not $proc.WaitForExit(20000)) {
        try { $proc.Kill() } catch {}
        $result.ExitCode = -1
        $result.Output = "llama-server.exe --version did not exit within 20 seconds."
        return [pscustomobject]$result
    }
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $result.ExitCode = $proc.ExitCode
    $result.Output = (($stdout + "`n" + $stderr).Trim())
    return [pscustomobject]$result
}

function Update-PrismEngineIndex {
    <#
    Replaces only the managed identities requested in Kinds.
    Other entries, including the other managed identity and any other name
    that happens to contain "prism", stay as they are.
    backendCompatibility.status "compatible" is a registration flag so LM Studio
    lists the engine. It is not a hardware or inference test.
    #>
    param(
        [Parameter(Mandatory)]$Index,
        [Parameter(Mandatory)][string[]]$Kinds,
        [Parameter(Mandatory)][string]$RocmDir,
        [Parameter(Mandatory)][string]$VulkanDir
    )
    $entries = @()
    if ($Index.json) { $entries = @($Index.json) }
    $replace = @{}
    if ($Kinds -contains "rocm") { $replace[$script:PrismEngineRocm] = "rocm" }
    if ($Kinds -contains "vulkan") { $replace[$script:PrismEngineVulkan] = "vulkan" }

    $kept = foreach ($entry in $entries) {
        $name = $entry.manifest.name
        if ($replace.ContainsKey([string]$name)) { continue }
        $entry
    }
    $kept = @($kept)

    foreach ($name in $replace.Keys) {
        $kind = $replace[$name]
        $dir = if ($kind -eq "rocm") { $RocmDir } else { $VulkanDir }
        $existing = @($entries | Where-Object { $_.manifest.name -eq $name } | Select-Object -First 1)
        $template = $null
        if ($existing.Count -gt 0 -and $existing[0]) {
            $template = $existing[0]
        } else {
            $template = @($entries | Where-Object {
                $_.manifest -and $_.launchInfo -and $_.dirPath -and
                ($_.manifest.gpu.framework -eq "Vulkan" -or $_.manifest.name -eq $script:PrismEngineVulkan)
            } | Select-Object -First 1)
            if (-not $template) {
                $template = @($entries | Where-Object { $_.manifest -and $_.launchInfo -and $_.dirPath } | Select-Object -First 1)
            }
        }
        if (-not $template) {
            throw "Engine index has no entry with manifest, launchInfo, and dirPath. It was not modified."
        }
        $clone = $template | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $clone.dirPath = $dir
        $clone.libLmStudioPath = [System.IO.Path]::Combine($dir, "liblmstudio_bindings_vulkan.node")
        if (-not $clone.launchInfo) { $clone | Add-Member -NotePropertyName launchInfo -NotePropertyValue ([pscustomobject]@{}) }
        $clone.launchInfo.engineLibPath = [System.IO.Path]::Combine($dir, "llm_engine_vulkan.node")
        if (-not $clone.manifest) { $clone | Add-Member -NotePropertyName manifest -NotePropertyValue ([pscustomobject]@{}) }
        $clone.manifest.name = $name
        $clone.manifest.version = $script:PrismPackageVersion
        if ($clone.manifest.gpu) { $clone.manifest.gpu.framework = "Vulkan" }
        if (-not $clone.backendCompatibility) {
            $clone | Add-Member -NotePropertyName backendCompatibility -NotePropertyValue ([pscustomobject]@{})
        }
        $clone.backendCompatibility.status = "compatible"
        $clone.backendCompatibility.message = "Registered by the PrismML LM Studio installer. This flag is not a runtime or model-inference test."
        $kept += $clone
    }
    $Index.json = @($kept)
    return $Index
}

function Get-PrismOriginalBackupPath {
    param([Parameter(Mandatory)][string]$Path)
    return "$Path.bak-prism-original"
}

function Save-PrismOriginalOnce {
    param([Parameter(Mandatory)][string]$Path)
    $backup = Get-PrismOriginalBackupPath -Path $Path
    if ((Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $Path -Destination $backup -Force
    }
    return $backup
}

function Write-PrismAtomicText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (Test-Path -LiteralPath $Path) {
        Save-PrismOriginalOnce -Path $Path | Out-Null
    }
    $tmp = Join-Path $dir (".{0}.{1}.tmp" -f (Split-Path -Leaf $Path), [guid]::NewGuid().ToString("n"))
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tmp, $Text, $utf8)
    if (Test-Path -LiteralPath $Path) {
        [System.IO.File]::Delete($Path)
    }
    [System.IO.File]::Move($tmp, $Path)
}
