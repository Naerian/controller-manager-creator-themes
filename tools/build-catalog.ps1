[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
& (Join-Path $PSScriptRoot 'validate-themes.ps1') -Root $Root
$dist = Join-Path $Root 'dist'
$packages = Join-Path $dist 'packages'
New-Item $packages -ItemType Directory -Force | Out-Null
$catalogPath = Join-Path $dist 'catalog.json'
$old = if (Test-Path $catalogPath) { Get-Content $catalogPath -Raw | ConvertFrom-Json } else { $null }
$entries = @{}
if ($old -and $old.Themes) {
    foreach ($entry in $old.Themes) { $entries[[string]$entry.Id] = @($entry.Versions) }
}

Get-ChildItem (Join-Path $Root 'themes') -Directory | ForEach-Object {
    $folder = $_
    $manifest = Get-Content (Join-Path $folder.FullName 'manifest.json') -Raw | ConvertFrom-Json
    $safeVersion = ([string]$manifest.Version) -replace '[^0-9A-Za-z._-]', '-'
    $fileName = "$($manifest.Id)-$safeVersion.csmtheme"
    $packagePath = Join-Path $packages $fileName
    $zipPath = [IO.Path]::ChangeExtension($packagePath, '.zip')
    if (Test-Path $packagePath) { Remove-Item -LiteralPath $packagePath -Force }
    if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $folder.FullName '*') -DestinationPath $zipPath -CompressionLevel Optimal
    Move-Item -LiteralPath $zipPath -Destination $packagePath
    $hash = (Get-FileHash $packagePath -Algorithm SHA256).Hash
    $release = [ordered]@{
        Version = [string]$manifest.Version
        SchemaVersion = [int]$manifest.SchemaVersion
        MinimumPluginVersion = [string]$manifest.MinimumPluginVersion
        MaximumPluginVersion = [string]$manifest.MaximumPluginVersion
        Url = "https://raw.githubusercontent.com/Naerian/controller-manager-creator-themes/main/dist/packages/$fileName"
        Sha256 = $hash
        Size = (Get-Item $packagePath).Length
    }
    $versions = @($entries[[string]$manifest.Id] | Where-Object { $_.Version -ne $manifest.Version }) + @($release)
    $entries[[string]$manifest.Id] = @($versions | Sort-Object { [version]$_.Version } -Descending)
}

$themes = foreach ($id in ($entries.Keys | Sort-Object)) {
    [ordered]@{ Id = $id; Versions = @($entries[$id]) }
}
$catalog = [ordered]@{ SchemaVersion = 1; GeneratedUtc = [DateTime]::UtcNow.ToString('o'); Themes = @($themes) }
$json = $catalog | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($catalogPath, $json, [Text.UTF8Encoding]::new($false))
Write-Host "Built catalog with $(@($themes).Count) design(s)."
