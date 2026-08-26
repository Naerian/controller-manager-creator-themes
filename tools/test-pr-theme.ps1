[CmdletBinding(DefaultParameterSetName='Install')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='Install')]
    [ValidateRange(1, 2147483647)]
    [int]$PullRequest,

    [string[]]$DesignId,

    [Parameter(Mandatory=$true, ParameterSetName='Restore')]
    [switch]$Restore,

    [string]$PluginDataDirectory
)

$ErrorActionPreference = 'Stop'
$repository = 'https://github.com/Naerian/controller-manager-creator-themes.git'
$pluginId = '6f3e7a21-98f4-4f2b-92ad-3fc0e6e941dc'

function Resolve-PluginDataDirectory([string]$ExplicitPath) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) { return [IO.Path]::GetFullPath($ExplicitPath) }
    $candidates = @(
        "C:\Playnite\ExtensionsData\$pluginId",
        (Join-Path $env:APPDATA "Playnite\ExtensionsData\$pluginId"),
        (Join-Path $env:LOCALAPPDATA "Playnite\ExtensionsData\$pluginId")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    if ($candidates.Count -eq 1) { return [IO.Path]::GetFullPath($candidates[0]) }
    if ($candidates.Count -gt 1) { throw "Several Controller Manager data folders were found. Use -PluginDataDirectory with the one Playnite uses.`n$($candidates -join "`n")" }
    throw 'Controller Manager data folder was not found. Use -PluginDataDirectory, for example C:\Playnite\ExtensionsData\<plugin-id>.'
}

function Assert-PlayniteClosed {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Playnite*' })
    if ($running.Count) { throw 'Close Playnite before installing or restoring a PR design.' }
}

function Restore-State($stateFile) {
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    $installed = [IO.Path]::GetFullPath([string]$state.InstalledPath)
    $backup = [IO.Path]::GetFullPath([string]$state.BackupPath)
    $safeThemesRoot = [IO.Path]::GetFullPath($themesRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $safeBackupRoot = [IO.Path]::GetFullPath($backupRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not ($installed + [IO.Path]::DirectorySeparatorChar).StartsWith($safeThemesRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not ($backup + [IO.Path]::DirectorySeparatorChar).StartsWith($safeBackupRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe restore paths in state file: $stateFile"
    }
    if (Test-Path -LiteralPath $installed) { Remove-Item -LiteralPath $installed -Recurse -Force }
    if ($state.HadPreviousDesign -eq $true) {
        if (-not (Test-Path -LiteralPath $backup -PathType Container)) { throw "Backup is missing for $($state.DesignId): $backup" }
        Move-Item -LiteralPath $backup -Destination $installed
    }
    Remove-Item -LiteralPath $stateFile -Force
    Write-Host "Restored $($state.DesignId)."
}

Assert-PlayniteClosed
$dataRoot = Resolve-PluginDataDirectory $PluginDataDirectory
$themesRoot = Join-Path $dataRoot 'CreatorThemes'
$backupRoot = Join-Path $dataRoot 'CreatorThemeTestBackups'
$stateRoot = Join-Path $backupRoot 'State'
New-Item -Path $themesRoot -ItemType Directory -Force | Out-Null
New-Item -Path $stateRoot -ItemType Directory -Force | Out-Null

if ($Restore) {
    $states = if ($DesignId) { @($DesignId | ForEach-Object { Join-Path $stateRoot "$_.json" } | Where-Object { Test-Path -LiteralPath $_ }) } else { @(Get-ChildItem -LiteralPath $stateRoot -Filter '*.json' -File | Select-Object -ExpandProperty FullName) }
    if (-not $states.Count) { Write-Host 'There are no temporary PR designs to restore.'; exit 0 }
    foreach ($state in $states) { Restore-State $state }
    exit 0
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ("controller-manager-pr-$PullRequest-" + [guid]::NewGuid().ToString('N'))
try {
    $checkout = Join-Path $temp 'repository'
    New-Item -Path $temp -ItemType Directory -Force | Out-Null
    & git clone --quiet $repository $checkout
    if ($LASTEXITCODE -ne 0) { throw 'Unable to clone the creator-theme repository.' }
    & git -C $checkout fetch --quiet origin "pull/$PullRequest/head"
    if ($LASTEXITCODE -ne 0) { throw "Pull request #$PullRequest was not found." }
    & git -C $checkout checkout --quiet --detach FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "Unable to check out pull request #$PullRequest." }

    # Always use the trusted validator beside this installer, never scripts supplied by the PR.
    $shell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if ([string]::IsNullOrWhiteSpace($shell)) { $shell = (Get-Command powershell).Source }
    & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'validate-themes.ps1') -Root $checkout
    if ($LASTEXITCODE -ne 0) { throw "Pull request #$PullRequest failed creator-theme validation." }

    if (-not $DesignId -or -not $DesignId.Count) {
        $changed = @(& git -C $checkout diff --name-only origin/main...HEAD -- themes)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to determine which designs the PR changes.' }
        $DesignId = @($changed | ForEach-Object { $path=$_ -replace '\\','/'; if($path -match '^themes/([^/]+)/'){ $Matches[1] } } | Where-Object { $_ } | Sort-Object -Unique)
    }
    if (-not $DesignId.Count) { throw "Pull request #$PullRequest does not add or modify a design under themes/." }

    foreach ($id in $DesignId) {
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') { throw "Invalid design ID '$id'." }
        $source = Join-Path (Join-Path $checkout 'themes') $id
        if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Design '$id' was removed or is not present in the PR." }
        $installed = Join-Path $themesRoot $id
        $stateFile = Join-Path $stateRoot "$id.json"
        if (Test-Path -LiteralPath $stateFile) { Restore-State $stateFile }

        $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
        $backup = Join-Path $backupRoot "$id-$stamp"
        $hadPrevious = Test-Path -LiteralPath $installed -PathType Container
        if ($hadPrevious) { Move-Item -LiteralPath $installed -Destination $backup }
        try {
            Copy-Item -LiteralPath $source -Destination $installed -Recurse
            $state = [ordered]@{ DesignId=$id; PullRequest=$PullRequest; InstalledPath=$installed; BackupPath=$backup; HadPreviousDesign=$hadPrevious; InstalledUtc=[DateTime]::UtcNow.ToString('o') }
            [IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        } catch {
            if (Test-Path -LiteralPath $installed) { Remove-Item -LiteralPath $installed -Recurse -Force }
            if ($hadPrevious -and (Test-Path -LiteralPath $backup)) { Move-Item -LiteralPath $backup -Destination $installed }
            throw
        }
        Write-Host "Installed temporary design '$id' from PR #$PullRequest."
    }
    Write-Host 'Open Playnite and test the design. Close Playnite and run the following command to restore previous designs:'
    Write-Host '.\tools\test-pr-theme.ps1 -Restore'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
