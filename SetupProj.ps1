#Requires -Version 5.1
#
# Proteus Setup script (Windows / PowerShell)
# SPDX-License-Identifier: MPL-2.0
#
# Run from the repository root:
#   powershell -ExecutionPolicy Bypass -File .\Setup.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

function Info { param([string]$Message) Write-Host "[?] :: $Message" }
function Ok   { param([string]$Message) Write-Host "[*] :: $Message" -ForegroundColor Green }
function Err  { param([string]$Message) Write-Host "[X] :: $Message" -ForegroundColor Red }

# Run a native command, swallow all its output, report success as a bool.
function Invoke-Quiet {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$Arguments = @()
    )
    & $File @Arguments *> $null
    return ($LASTEXITCODE -eq 0)
}

# Remove-Item chokes on git's read-only pack files under .git\objects, and
# on long paths. Clearing attributes first fixes most of it; rmdir via cmd
# is the reliable last resort.
function Remove-Tree {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    try {
        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Attributes = 'Normal' }
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return $true
    }
    catch {
        cmd /c "rmdir /s /q `"$Path`"" *> $null
        return (-not (Test-Path -LiteralPath $Path))
    }
}

Start-Sleep -Seconds 1
Ok   "========== Proteus Engine Setup =========="
Info "Preparing to set up the project..."

$Root = (Get-Location).Path

if ((Test-Path -LiteralPath '.psetupdone') -or (Test-Path -LiteralPath '.pbuilddone')) {
    Ok "Setup has already been done before, to redo setup, do the following:"
    Ok "  Remove-Item -Recurse -Force Build"
    Ok "  Remove-Item -Recurse -Force Dependencies"
    Ok "  Remove-Item -Force .psetupdone"
    Ok "And rerun the setup script."
    exit 0
}

## Step 0: Prepare directories
foreach ($dirName in @('Dependencies', 'Build')) {
    $dirPath = Join-Path $Root $dirName
    if (-not (Test-Path -LiteralPath $dirPath)) {
        try {
            New-Item -ItemType Directory -Path $dirPath -ErrorAction Stop | Out-Null
            Ok "Created $dirName dir successfully."
        }
        catch {
            Err "Could not create the directory, maybe there is a permissions issue?"
            Err "(Try running this shell as Administrator)"
            exit 1
        }
    }
    else {
        Info "$dirName dir already exists, skipping."
    }
}

## Step 1: Check for all required tooling
Start-Sleep -Seconds 1
Info "Checking now for required tools..."

# Pulls a version number out of most tools' --version output
function Get-VersionString {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$Arguments = @('--version')
    )
    try {
        $first = (& $File @Arguments 2>&1 | Select-Object -First 1) -as [string]
        if ([string]::IsNullOrWhiteSpace($first)) { return 'unknown' }
        $m = [regex]::Match($first, '[0-9]+\.[0-9]+(\.[0-9]+)?([.-][0-9A-Za-z]+)*')
        if ($m.Success) { return $m.Value }
        return 'unknown'
    }
    catch {
        return 'unknown'
    }
}

function Get-NormalizedArch {
    param([string]$Arch)
    switch -Regex ($Arch.ToLower()) {
        '^(x86_64|amd64|x64)$'   { return 'x86_64' }
        '^(arm64|aarch64)$'      { return 'arm64'  }
        '^(i386|i686|x86)$'      { return 'i386'   }
        default                  { return $Arch.ToLower() }
    }
}

# Confirms clang++'s default target triple matches the actual host arch
function Test-TargetArch {
    # PROCESSOR_ARCHITECTURE reports the *process* arch, so a 32-bit shell on
    # a 64-bit box lies; PROCESSOR_ARCHITEW6432 is the tell-tale when it does.
    $hostArch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $hostArch = $env:PROCESSOR_ARCHITEW6432 }

    $triple = (& clang++ -dumpmachine 2>$null | Select-Object -First 1) -as [string]
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($triple)) {
        Err "Could not determine clang++'s default target triple."
        return $false
    }
    $triple = $triple.Trim()
    $compilerArch = ($triple -split '-')[0]

    $hostNorm     = Get-NormalizedArch $hostArch
    $compilerNorm = Get-NormalizedArch $compilerArch

    if ($hostNorm -ne $compilerNorm) {
        Err "Arch mismatch: host is $hostArch, but clang++ defaults to $triple"
        Err "Building without explicit -arch/-target flags will produce wrong-arch object files."
        return $false
    }

    Ok "clang++ default target ($triple) matches host ($hostArch)."
    return $true
}

# label => how to invoke it. Order matches Setup.sh.
$tools = [ordered]@{
    'git'      = 'Git  version:   '
    'curl'     = 'Curl version:   '
    'make'     = 'Make version:   '
    'cmake'    = 'CMake version:  '
    'premake5' = 'Premake version:'
    'lldb'     = 'LLDB version:   '
    'gdb'      = 'GDB  version:   '
    'clang++'  = 'Clang version:  '
}

foreach ($tool in $tools.Keys) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Err "Missing dependency $tool !"
        continue
    }

    if ($tool -eq 'premake5') {
        Info ("{0} {1}" -f $tools[$tool], (Get-VersionString $tool @('--version')))
    }
    else {
        Info ("{0} {1}" -f $tools[$tool], (Get-VersionString $tool))
    }

    if ($tool -eq 'clang++') {
        if (-not (Test-TargetArch)) { exit 1 }
    }
}

# Warn if no debugger is present. On Windows the usual answer is the Visual
# Studio debugger rather than lldb/gdb, so this is a nudge, not a failure.
if (-not (Get-Command 'lldb' -ErrorAction SilentlyContinue) -and
    -not (Get-Command 'gdb'  -ErrorAction SilentlyContinue)) {
    Err "No debugger found (lldb or gdb). The Visual Studio debugger works too."
}

## Step 2: Fetch and pin dependencies from the manifest
Start-Sleep -Seconds 1
Info "Tooling check complete, moving on to dependency fetching..."

$Manifest = Join-Path $Root 'manifest.txt'
$DepsDir  = Join-Path $Root 'Dependencies'

if (-not (Test-Path -LiteralPath $Manifest)) {
    Err "No manifest.txt found in $Root !"
    exit 1
}

# Shallow-fetch one exact commit. 'git clone --depth 1' can only target a
# branch or tag, never an arbitrary SHA, hence init + fetch + checkout.
function Get-PinnedRepo {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Sha,
        [Parameter(Mandatory = $true)][string]$Dest
    )
    if (-not (Invoke-Quiet 'git' @('init', '-q', $Dest)))                       { return $false }
    Invoke-Quiet 'git' @('-C', $Dest, 'remote', 'add', 'origin', $Url) | Out-Null
    if (-not (Invoke-Quiet 'git' @('-C', $Dest, 'fetch', '-q', '--depth', '1', 'origin', $Sha))) { return $false }
    if (-not (Invoke-Quiet 'git' @('-C', $Dest, 'checkout', '-q', 'FETCH_HEAD'))) { return $false }
    return $true
}

# trickery is needed here so git can't eat the manifest out from under us.
foreach ($line in (Get-Content -LiteralPath $Manifest)) {
    $line = $line.Trim()

    # Skip blank lines and comments
    if ($line -eq '' -or $line.StartsWith('#')) { continue }

    $fields = $line -split '\s+'
    $url = $fields[0]
    $sha = if ($fields.Count -ge 2) { $fields[1] } else { '' }

    if ([string]::IsNullOrWhiteSpace($sha)) {
        Err "Malformed manifest entry (no commit hash): $url"
        exit 1
    }

    # Reject anything that isn't the full hash: short hashes and tags are
    # ambiguous or mutable, making this pointless
    if ($sha -notmatch '^[0-9a-f]{40}$') {
        Err "Invalid commit hash for $url"
        Err "(Expected a full hash, got: $sha)"
        exit 1
    }

    # Derive dir name from the repo URL: .../glfw.git -> glfw
    $name = [System.IO.Path]::GetFileName($url.TrimEnd('/')) -replace '\.git$', ''
    $dest = Join-Path $DepsDir $name

    if (Test-Path -LiteralPath (Join-Path $dest '.git')) {
        $current = (& git -C $dest rev-parse HEAD 2>$null | Select-Object -First 1) -as [string]
        if ($current) { $current = $current.Trim() }

        if ($current -eq $sha) {
            Info "$name already at pinned commit, skipping."
            continue
        }
        Info "$name is at the wrong commit, refetching..."
        if (-not (Remove-Tree $dest)) {
            Err "Could not remove $dest - is a file in it open in another program?"
            exit 1
        }
    }
    elseif (Test-Path -LiteralPath $dest) {
        Err "$dest exists but is not a git repo, refusing to touch it."
        exit 1
    }

    Info "Fetching $name ..."
    if (-not (Get-PinnedRepo -Url $url -Sha $sha -Dest $dest)) {
        Err "Failed to fetch $name at $sha"
        Err "(Check the URL and that the commit still exists upstream)"
        Remove-Tree $dest | Out-Null
        exit 1
    }

    # Paranoia: confirm we actually landed where we meant to
    $landed = (& git -C $dest rev-parse HEAD 2>$null | Select-Object -First 1) -as [string]
    if ($landed) { $landed = $landed.Trim() }
    if ($landed -ne $sha) {
        Err "$name checked out $landed but manifest pins $sha"
        exit 1
    }

    Ok "$name pinned to $sha"
}

Ok "All dependencies fetched and verified."

New-Item -ItemType File -Path (Join-Path $Root '.psetupdone') -Force | Out-Null
Info "Setup is now complete, you can run premake:"
Ok   "    premake5 vs2022"
Ok   "    premake5 gmake2"
Start-Sleep -Seconds 2
exit 0