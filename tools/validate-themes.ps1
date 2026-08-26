[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$allowed = @('.json', '.png', '.jpg', '.jpeg', '.ttf', '.otf', '.wav', '.mp3', '.wma', '.txt', '.md')
$ids = @{}
$errors = [System.Collections.Generic.List[string]]::new()
$themeRoot = Join-Path $Root 'themes'

Get-ChildItem $themeRoot -Directory | ForEach-Object {
    $folder = $_
    $manifestPath = Join-Path $folder.FullName 'manifest.json'
    if (-not (Test-Path $manifestPath)) { $errors.Add("$($folder.Name): missing manifest.json"); return }
    try { $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json }
    catch { $errors.Add("$($folder.Name): invalid manifest.json: $($_.Exception.Message)"); return }

    if ($manifest.SchemaVersion -ne 1) { $errors.Add("$($folder.Name): SchemaVersion must be 1") }
    if ([string]::IsNullOrWhiteSpace($manifest.Id) -or $manifest.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') {
        $errors.Add("$($folder.Name): invalid Id")
    } elseif ($ids.ContainsKey($manifest.Id)) { $errors.Add("Duplicate Id: $($manifest.Id)") }
    else { $ids[$manifest.Id] = $true }
    foreach ($required in 'Name','Author','Version','MinimumPluginVersion') {
        if ([string]::IsNullOrWhiteSpace($manifest.$required)) { $errors.Add("$($folder.Name): missing $required") }
    }
    $parsed = $null
    if (-not [version]::TryParse([string]$manifest.Version, [ref]$parsed)) { $errors.Add("$($folder.Name): invalid Version") }
    if (-not [version]::TryParse([string]$manifest.MinimumPluginVersion, [ref]$parsed)) { $errors.Add("$($folder.Name): invalid MinimumPluginVersion") }
    if ($manifest.MaximumPluginVersion -and -not [version]::TryParse([string]$manifest.MaximumPluginVersion, [ref]$parsed)) {
        $errors.Add("$($folder.Name): invalid MaximumPluginVersion")
    }
    if (-not (Test-Path (Join-Path $folder.FullName 'notification.json')) -and
        -not (Test-Path (Join-Path $folder.FullName 'overlay.json'))) {
        $errors.Add("$($folder.Name): notification.json or overlay.json is required")
    }
    Get-ChildItem $folder.FullName -Recurse -File | ForEach-Object {
        if ($_.Length -gt 12MB) { $errors.Add("$($folder.Name): $($_.Name) exceeds 12 MB") }
        if ($allowed -notcontains $_.Extension.ToLowerInvariant() -and $_.Name -ne 'LICENSE') {
            $errors.Add("$($folder.Name): forbidden file type $($_.Extension)")
        }
        if ($_.FullName.Substring($folder.FullName.Length + 1).Split([IO.Path]::DirectorySeparatorChar).Count -gt 8) {
            $errors.Add("$($folder.Name): path nesting is too deep")
        }
    }
}

if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Host "Validated $($ids.Count) creator theme(s)."
