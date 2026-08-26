[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$validator = Join-Path $PSScriptRoot 'validate-themes.ps1'
$shell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if ([string]::IsNullOrWhiteSpace($shell)) { $shell = (Get-Command powershell).Source }

function Invoke-InvalidFixture([string]$Name, [scriptblock]$Mutate, [string]$ExpectedText) {
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ("csm-validator-" + [guid]::NewGuid().ToString('N'))
    try {
        New-Item (Join-Path $fixture 'themes') -ItemType Directory -Force | Out-Null
        New-Item (Join-Path $fixture 'previews') -ItemType Directory -Force | Out-Null
        Copy-Item (Join-Path $Root 'themes\naerian.narianux') (Join-Path $fixture 'themes\naerian.narianux') -Recurse
        Copy-Item (Join-Path $Root 'previews\naerian.narianux') (Join-Path $fixture 'previews\naerian.narianux') -Recurse
        & $Mutate $fixture
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $output = & $shell -NoProfile -ExecutionPolicy Bypass -File $validator -Root $fixture 2>&1 | Out-String }
        finally { $ErrorActionPreference = $previousErrorActionPreference }
        if ($LASTEXITCODE -eq 0) { throw "$Name unexpectedly passed validation" }
        if ($output -notmatch [regex]::Escape($ExpectedText)) { throw "$Name failed for the wrong reason. Output: $output" }
        Write-Host "PASS: $Name"
    }
    finally { if (Test-Path $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
}

Invoke-InvalidFixture 'unknown appearance property' {
    param($fixture)
    $path=Join-Path $fixture 'themes\naerian.narianux\overlay.json';$json=Get-Content $path -Raw|ConvertFrom-Json;$json|Add-Member UnknownVisualOption 1;$json|ConvertTo-Json -Depth 20|Set-Content $path -Encoding UTF8
} "unknown property 'UnknownVisualOption'"
Invoke-InvalidFixture 'out-of-range value' {
    param($fixture)
    $path=Join-Path $fixture 'themes\naerian.narianux\overlay.json';$json=Get-Content $path -Raw|ConvertFrom-Json;$json.OverlayScalePercent=999;$json|ConvertTo-Json -Depth 20|Set-Content $path -Encoding UTF8
} 'OverlayScalePercent must be between 80 and 140'
Invoke-InvalidFixture 'invalid color' {
    param($fixture)
    $path=Join-Path $fixture 'themes\naerian.narianux\notification.json';$json=Get-Content $path -Raw|ConvertFrom-Json;$json.NotificationTextColor='cyan';$json|ConvertTo-Json -Depth 20|Set-Content $path -Encoding UTF8
} 'NotificationTextColor must be #RRGGBB or #AARRGGBB'
Invoke-InvalidFixture 'unsafe asset path' {
    param($fixture)
    $path=Join-Path $fixture 'themes\naerian.narianux\overlay.json';$json=Get-Content $path -Raw|ConvertFrom-Json;$json|Add-Member OverlayBackgroundImagePath '..\outside.png';$json|ConvertTo-Json -Depth 20|Set-Content $path -Encoding UTF8
} 'OverlayBackgroundImagePath escapes the design folder'

Write-Host 'All validator regression tests passed.'
$global:LASTEXITCODE = 0
