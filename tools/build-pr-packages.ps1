[CmdletBinding()]
param(
    [string]$Root,
    [string]$BaseSha,
    [string]$HeadSha = 'HEAD',
    [string[]]$DesignId,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [IO.Path]::GetFullPath($Root)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $Root 'pr-artifacts' }

if (-not $DesignId -or $DesignId.Count -eq 0) {
    if ([string]::IsNullOrWhiteSpace($BaseSha)) { throw 'BaseSha or DesignId is required.' }
    $changed = @(& git -C $Root diff --name-only "$BaseSha...$HeadSha" -- themes)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to determine the designs changed by the pull request.' }
    $DesignId = @($changed | ForEach-Object {
        $normalized = $_ -replace '\\','/'
        if ($normalized -match '^themes/([^/]+)/') { $Matches[1] }
    } | Where-Object { $_ } | Sort-Object -Unique)
}

if (Test-Path -LiteralPath $OutputDirectory) { Remove-Item -LiteralPath $OutputDirectory -Recurse -Force }
New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null

$built = [Collections.Generic.List[string]]::new()
foreach ($id in @($DesignId)) {
    if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') { throw "Invalid design ID '$id'." }
    $folder = Join-Path (Join-Path $Root 'themes') $id
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        Write-Host "Skipping removed design: $id"
        continue
    }
    $manifestPath = Join-Path $folder 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.Id -cne $id) { throw "${id}: manifest Id does not match its folder." }
    $safeVersion = ([string]$manifest.Version) -replace '[^0-9A-Za-z._-]', '-'
    $package = Join-Path $OutputDirectory "$id-$safeVersion-pr.csmtheme"
    $zip = [IO.Path]::ChangeExtension($package, '.zip')
    Compress-Archive -Path (Join-Path $folder '*') -DestinationPath $zip -CompressionLevel Optimal
    Move-Item -LiteralPath $zip -Destination $package
    $built.Add($package)
    Write-Host "Built PR package: $package"
}

Write-Host "Built $($built.Count) pull-request package(s)."
@($built)
