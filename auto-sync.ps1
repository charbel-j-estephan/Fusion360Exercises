#Requires -Version 5.1
<#
Watches the repo directory for changes and auto commits + pushes them to GitHub.
Uses FileSystemWatcher.WaitForChanged in a loop with a debounce so bursty saves
(e.g. Fusion 360) batch into a single commit.
#>

$ErrorActionPreference = 'Stop'
$RepoPath   = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogPath    = Join-Path $RepoPath 'auto-sync.log'
$DebounceMs = 5000   # wait this long after the last event before committing
$GitExe     = 'git'

function Write-Log($msg) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $LogPath -Value $line -Encoding utf8
}

function Invoke-Git {
    param([string[]]$GitArgs)
    # Locally allow stderr-as-output without aborting on native command warnings.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $GitExe -C $RepoPath @GitArgs 2>&1
        return @{ ExitCode = $LASTEXITCODE; Output = (($out | ForEach-Object { $_.ToString() }) -join "`n") }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Should-Ignore([string]$path) {
    if (-not $path) { return $true }
    return ($path -match '\\\.git(\\|$)') -or
           ($path -match 'auto-sync\.log$') -or
           ($path -match '\\\.claude(\\|$)')
}

function Sync-Repo {
    $status = Invoke-Git @('status', '--porcelain')
    if ([string]::IsNullOrWhiteSpace($status.Output)) {
        Write-Log "No changes to commit."
        return
    }
    Write-Log "Changes detected:`n$($status.Output)"

    $add = Invoke-Git @('add', '-A')
    if ($add.ExitCode -ne 0) { Write-Log "git add failed: $($add.Output)"; return }

    $stamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $msg    = "Auto-sync: $stamp"
    $commit = Invoke-Git @('commit', '-m', $msg)
    if ($commit.ExitCode -ne 0) { Write-Log "git commit failed: $($commit.Output)"; return }
    Write-Log "Committed."

    $push = Invoke-Git @('push', 'origin', 'HEAD')
    if ($push.ExitCode -ne 0) { Write-Log "git push failed: $($push.Output)"; return }
    Write-Log "Pushed."
}

Write-Log "Watcher starting on: $RepoPath"

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path                  = $RepoPath
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor `
                       [System.IO.NotifyFilters]::DirectoryName -bor `
                       [System.IO.NotifyFilters]::LastWrite -bor `
                       [System.IO.NotifyFilters]::Size

$changeTypes = [System.IO.WatcherChangeTypes]::Created -bor `
               [System.IO.WatcherChangeTypes]::Changed -bor `
               [System.IO.WatcherChangeTypes]::Deleted -bor `
               [System.IO.WatcherChangeTypes]::Renamed

try {
    while ($true) {
        # Block until a relevant change happens.
        $result = $watcher.WaitForChanged($changeTypes, [System.Threading.Timeout]::Infinite)
        if ($result.TimedOut) { continue }

        $changedPath = Join-Path $RepoPath $result.Name
        if (Should-Ignore $changedPath) { continue }

        # Drain any further events within the debounce window.
        $deadline = (Get-Date).AddMilliseconds($DebounceMs)
        while ((Get-Date) -lt $deadline) {
            $remainingMs = [int](($deadline - (Get-Date)).TotalMilliseconds)
            if ($remainingMs -le 0) { break }
            $next = $watcher.WaitForChanged($changeTypes, $remainingMs)
            if ($next.TimedOut) { break }
            $nextPath = Join-Path $RepoPath $next.Name
            if (Should-Ignore $nextPath) { continue }
            # Reset debounce window on a fresh, relevant event.
            $deadline = (Get-Date).AddMilliseconds($DebounceMs)
        }

        try { Sync-Repo } catch { Write-Log "Sync error: $_" }
    }
}
finally {
    $watcher.Dispose()
    Write-Log "Watcher stopped."
}
