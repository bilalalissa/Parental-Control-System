[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$Root
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
} else {
    $RepositoryRoot = [System.IO.Path]::GetFullPath($Root)
}

$VolumeRoot = [System.IO.Path]::GetPathRoot($RepositoryRoot)
if ($RepositoryRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) -eq $VolumeRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar)) {
    throw "Refusing cleanup at a volume root."
}

$IsRepository = (Test-Path -LiteralPath (Join-Path $RepositoryRoot "AGENTS.md") -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $RepositoryRoot "CODEX_MASTER_PROMPT.md") -PathType Leaf)
$IsMarkedTestRoot = Test-Path -LiteralPath (Join-Path $RepositoryRoot ".parental-control-cleanup-test-root") -PathType Leaf

if (-not $IsRepository -and -not $IsMarkedTestRoot) {
    throw "Refusing cleanup outside the Parental Control System repository or a marked test root."
}

$DirectTargets = @(
    ".build",
    "build",
    "dist",
    "coverage",
    "TestResults",
    ".artifacts/derived-data",
    ".artifacts/test-results",
    ".artifacts/tmp",
    ".artifacts/package-staging",
    ".artifacts/diagnostics",
    "apps/controller-macos/.artifacts"
)

$Targets = [System.Collections.Generic.List[string]]::new()
foreach ($RelativePath in $DirectTargets) {
    $Candidate = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $RelativePath))
    if (Test-Path -LiteralPath $Candidate) {
        $Item = Get-Item -LiteralPath $Candidate -Force
        if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-Warning "Skipping reparse point: $Candidate"
        } else {
            $Targets.Add($Candidate)
        }
    }
}

$NestedNames = @(".build", "node_modules", "bin", "obj", "publish")
$Pending = [System.Collections.Generic.Queue[string]]::new()
$Pending.Enqueue($RepositoryRoot)
$GitPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ".git"))
$CandidatePath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ".artifacts\release-candidate"))
while ($Pending.Count -gt 0) {
    $Current = $Pending.Dequeue()
    foreach ($Directory in Get-ChildItem -LiteralPath $Current -Directory -Force -ErrorAction SilentlyContinue) {
        if (($Directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            continue
        }
        if ($Directory.FullName.Equals($GitPath, [System.StringComparison]::OrdinalIgnoreCase) -or
            $Directory.FullName.Equals($CandidatePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if ($NestedNames -contains $Directory.Name) {
            $Targets.Add($Directory.FullName)
        } else {
            $Pending.Enqueue($Directory.FullName)
        }
    }
}

$Targets = @($Targets | Sort-Object -Unique)
if ($Targets.Count -eq 0) {
    Write-Output "No repository-owned generated output found."
    exit 0
}

Write-Output "Repository-owned generated output:"
foreach ($Target in $Targets) {
    $Relative = $Target.Substring($RepositoryRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar).Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
    Write-Output "  $Relative"
}

if (-not $Apply) {
    Write-Output "Dry run only. Re-run with -Apply to remove the listed paths."
    exit 0
}

$RootPrefix = $RepositoryRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
foreach ($Target in $Targets) {
    $ResolvedTarget = [System.IO.Path]::GetFullPath($Target)
    if (-not $ResolvedTarget.StartsWith($RootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside repository: $ResolvedTarget"
    }
    Remove-Item -LiteralPath $ResolvedTarget -Recurse -Force
}

Write-Output "Removed $($Targets.Count) repository-owned generated path(s)."
