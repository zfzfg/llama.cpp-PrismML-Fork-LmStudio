$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\PrismBackendLib.ps1")

$failures = New-Object System.Collections.Generic.List[string]
function Assert-True($Condition, [string]$Name) {
    if (-not $Condition) { $script:failures.Add($Name); Write-Host "FAIL $Name" -ForegroundColor Red }
    else { Write-Host "PASS $Name" -ForegroundColor Green }
}

Write-Host "PowerShell $($PSVersionTable.PSVersion) on $($PSVersionTable.PSEdition)"

$missing = Merge-PrismGgufPreference -ExistingJson $null -EngineName $script:PrismEngineRocm
$missingParsed = $missing.Json | ConvertFrom-Json
Assert-True (@($missingParsed).Count -eq 1 -and $missingParsed[0].model_format -eq "gguf") "missing preferences become one GGUF object inside an array"
Assert-True ($missing.Json.TrimStart().StartsWith("[")) "missing preferences serialize as an array"
Assert-True (-not $missing.Json.TrimStart().StartsWith("[[")) "single preference is not a nested array"

$one = Merge-PrismGgufPreference -ExistingJson '[{"model_format":"gguf","name":"old","version":"1.0.0","extra":true}]' -EngineName $script:PrismEngineVulkan
$oneParsed = @($one.Json | ConvertFrom-Json)
Assert-True ($oneParsed.Count -eq 1 -and $oneParsed[0].name -eq $script:PrismEngineVulkan) "one existing GGUF row is replaced"
Assert-True ($null -eq $oneParsed[0].extra) "replaced GGUF row does not keep the old engine identity"

$manyJson = '[{"model_format":"mlx","name":"keep-mlx","version":"9.0.0"},{"model_format":"gguf","name":"old-prism","version":"1.0.0"},{"model_format":"onnx","name":"keep-onnx","version":"3.0.0"}]'
$many = Merge-PrismGgufPreference -ExistingJson $manyJson -EngineName $script:PrismEngineRocm
$manyParsed = @($many.Json | ConvertFrom-Json)
Assert-True ($manyParsed.Count -eq 3) "non-GGUF rows are kept and GGUF stays a single row"
Assert-True (($manyParsed | Where-Object { $_.model_format -eq "mlx" }).name -eq "keep-mlx") "mlx row is unchanged"
Assert-True (($manyParsed | Where-Object { $_.model_format -eq "onnx" }).version -eq "3.0.0") "onnx row is unchanged"
Assert-True (($manyParsed | Where-Object { $_.model_format -eq "gguf" }).name -eq $script:PrismEngineRocm) "existing prism GGUF row is replaced"

$invalidThrew = $false
try { Merge-PrismGgufPreference -ExistingJson "{not json" -EngineName $script:PrismEngineRocm | Out-Null }
catch { $invalidThrew = $true }
Assert-True $invalidThrew "invalid preference JSON is rejected"

$index = [pscustomobject]@{
    json = @(
        [pscustomobject]@{
            dirPath = "C:\other"
            libLmStudioPath = "C:\other\bind.node"
            unknownField = "keep-me"
            launchInfo = [pscustomobject]@{ engineLibPath = "C:\other\engine.node"; extra = 7 }
            manifest = [pscustomobject]@{ name = "llama.cpp-win-x86_64-cuda"; version = "1.2.3"; gpu = [pscustomobject]@{ framework = "CUDA" } }
            backendCompatibility = [pscustomobject]@{ status = "compatible"; message = "stock" }
        },
        [pscustomobject]@{
            dirPath = "C:\vk"
            libLmStudioPath = "C:\vk\liblmstudio_bindings_vulkan.node"
            launchInfo = [pscustomobject]@{ engineLibPath = "C:\vk\llm_engine_vulkan.node" }
            manifest = [pscustomobject]@{ name = $script:PrismEngineVulkan; version = "2.64.0"; gpu = [pscustomobject]@{ framework = "Vulkan" }; custom = "vulkan-field" }
            backendCompatibility = [pscustomobject]@{ status = "compatible"; message = "old vulkan" }
        },
        [pscustomobject]@{
            dirPath = "C:\other-prism"
            libLmStudioPath = "C:\other-prism\bind.node"
            launchInfo = [pscustomobject]@{ engineLibPath = "C:\other-prism\engine.node" }
            manifest = [pscustomobject]@{ name = "some-other-prism-build"; version = "0.1.0" }
            backendCompatibility = [pscustomobject]@{ status = "unknown" }
        }
    )
}
$updated = Update-PrismEngineIndex -Index $index -Kinds @("rocm") -RocmDir "D:\rocm" -VulkanDir "D:\vulkan"
$names = @($updated.json | ForEach-Object { $_.manifest.name })
Assert-True ($names -contains $script:PrismEngineVulkan) "rocm-only update keeps the managed Vulkan entry"
Assert-True ($names -contains "some-other-prism-build") "rocm-only update keeps an unrelated prism name"
Assert-True ($names -contains "llama.cpp-win-x86_64-cuda") "rocm-only update keeps a non-prism backend"
Assert-True (@($names | Where-Object { $_ -eq $script:PrismEngineRocm }).Count -eq 1) "rocm identity is registered once"
$vk = @($updated.json | Where-Object { $_.manifest.name -eq $script:PrismEngineVulkan })[0]
Assert-True ($vk.dirPath -eq "C:\vk" -and $vk.manifest.custom -eq "vulkan-field") "existing Vulkan entry is not rebuilt from another backend"
$cuda = @($updated.json | Where-Object { $_.manifest.name -eq "llama.cpp-win-x86_64-cuda" })[0]
Assert-True ($cuda.unknownField -eq "keep-me" -and $cuda.manifest.gpu.framework -eq "CUDA") "unrelated backend fields stay unchanged"
$rocm = @($updated.json | Where-Object { $_.manifest.name -eq $script:PrismEngineRocm })[0]
Assert-True ($rocm.dirPath -eq "D:\rocm") "new rocm entry points at the rocm directory"
Assert-True ($rocm.manifest.gpu.framework -eq "Vulkan") "registered rocm manifest uses the Vulkan bridge framework"
Assert-True ($rocm.launchInfo.engineLibPath -like "*llm_engine_vulkan.node") "registered rocm entry does not keep the template engine path"
Assert-True ($rocm.backendCompatibility.message -like "*not a runtime*") "compatible status is documented as registration"

$temp = Join-Path $env:TEMP ("prism-backup-test-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $temp | Out-Null
$file = Join-Path $temp "prefs.json"
[System.IO.File]::WriteAllText($file, "original")
$first = Save-PrismOriginalOnce -Path $file
Write-PrismAtomicText -Path $file -Text "second"
Write-PrismAtomicText -Path $file -Text "third"
Assert-True ((Get-Content -LiteralPath $first -Raw) -eq "original") "the original backup is not overwritten"
Assert-True ((Get-Content -LiteralPath $file -Raw) -eq "third") "atomic write leaves the latest text"
Remove-Item -LiteralPath $temp -Recurse -Force

$missingServer = Test-PrismServerVersion -ServerPath (Join-Path $temp "missing-llama-server.exe")
Assert-True ((-not $missingServer.FilesPresent) -and (-not $missingServer.ServerStarted) -and (-not $missingServer.InferenceTested)) "a missing server is not reported as started or inference-tested"

$pwsh = (Get-Command pwsh).Source
$started = Test-PrismServerVersion -ServerPath $pwsh
Assert-True ($started.ServerStarted -and $started.ExitCode -eq 0 -and -not $started.InferenceTested) "a process that exits 0 is started, and inference is still not claimed"

if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) test(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host "All PrismBackendLib tests passed."
