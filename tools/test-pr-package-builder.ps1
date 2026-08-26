[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$output = Join-Path ([IO.Path]::GetTempPath()) ("csm-pr-packages-" + [guid]::NewGuid().ToString('N'))
try {
    $packages = @(& (Join-Path $PSScriptRoot 'build-pr-packages.ps1') -Root $Root -DesignId 'naerian.narianux' -OutputDirectory $output)
    $package = @(Get-ChildItem -LiteralPath $output -Filter '*.csmtheme' -File)
    if ($package.Count -ne 1 -or $package[0].Name -notmatch '^naerian\.narianux-1\.0\.0-pr\.csmtheme$') { throw 'The PR package was not generated with the expected name.' }
    $zip = [IO.Path]::ChangeExtension($package[0].FullName, '.zip')
    Copy-Item -LiteralPath $package[0].FullName -Destination $zip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try { if (-not @($archive.Entries | Where-Object { $_.FullName -eq 'manifest.json' }).Count) { throw 'The PR package does not contain manifest.json at its root.' } }
    finally { $archive.Dispose() }
    Write-Host 'PR package builder test passed.'
}
finally { if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force } }
