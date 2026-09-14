[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath
)

$ErrorActionPreference = "Stop"
$msi = (Resolve-Path $MsiPath).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$evidenceRoot = Join-Path $repoRoot ".artifacts\test-results\stage-07"
$installLog = Join-Path $evidenceRoot "install.log"
$repairLog = Join-Path $evidenceRoot "repair.log"
$uninstallLog = Join-Path $evidenceRoot "uninstall.log"
$installRoot = Join-Path $env:ProgramFiles "Parental Control System\Windows Child Endpoint"
$dataRoot = Join-Path $env:ProgramData "Parental Control\Windows Endpoint"
$serviceName = "ParentalControlWindowsEndpoint"
New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null

function Invoke-Msi([string]$arguments) {
    $process = Start-Process -FilePath msiexec.exe -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) { throw "msiexec failed with $($process.ExitCode)." }
}

function Read-Exactly([IO.Stream]$stream, [byte[]]$buffer) {
    $offset = 0
    while ($offset -lt $buffer.Length) {
        $count = $stream.Read($buffer, $offset, $buffer.Length - $offset)
        if ($count -eq 0) { throw "Named pipe closed unexpectedly." }
        $offset += $count
    }
}

function Get-EndpointStatus {
    $pipe = [IO.Pipes.NamedPipeClientStream]::new(".", "ParentalControl.Windows.Endpoint.v1", [IO.Pipes.PipeDirection]::InOut)
    try {
        $pipe.Connect(5000)
        $body = [Text.Encoding]::UTF8.GetBytes('{"operation":"status","invitation":null}')
        $prefix = [BitConverter]::GetBytes([Net.IPAddress]::HostToNetworkOrder([int]$body.Length))
        $pipe.Write($prefix, 0, $prefix.Length)
        $pipe.Write($body, 0, $body.Length)
        $pipe.Flush()
        Read-Exactly $pipe $prefix
        $length = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($prefix, 0))
        if ($length -le 0 -or $length -gt 16384) { throw "Invalid pipe response length." }
        $response = [byte[]]::new($length)
        Read-Exactly $pipe $response
        return ([Text.Encoding]::UTF8.GetString($response) | ConvertFrom-Json)
    } finally { $pipe.Dispose() }
}

try {
    Invoke-Msi "/i `"$msi`" /qn /norestart /l*v `"$installLog`""
    $service = Get-Service -Name $serviceName
    if ($service.StartType -ne "Automatic") { throw "Endpoint service is not automatic." }
    $serviceConfiguration = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
    if ($serviceConfiguration.StartName -ne "LocalSystem") { throw "Unexpected service account." }
    if ($service.Status -ne "Running") { Start-Service $serviceName }
    $service.WaitForStatus("Running", [TimeSpan]::FromSeconds(20))
    if (-not (Test-Path (Join-Path $installRoot "ParentalControl.Windows.Service.exe"))) { throw "Service payload missing." }
    if (-not (Test-Path (Join-Path $installRoot "ParentalControl.Windows.App.exe"))) { throw "Visible app payload missing." }

    $status = Get-EndpointStatus
    if (-not $status.success -or -not $status.status.serviceHealthy) { throw "Authenticated local status failed." }
    if ($status.status.sessionState -eq "unknown") { throw "Initial Windows session state is unknown." }
    if ($status.status.capabilities -contains "app-activity" -or $status.status.capabilities -contains "browser-tabs") {
        throw "Stage 07 claimed a later-stage capability."
    }
    $identityHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dataRoot "endpoint.dat")).Hash
    $dataAcl = Get-Acl -LiteralPath $dataRoot
    if (-not $dataAcl.AreAccessRulesProtected) { throw "Protected data inherits an unbounded ACL." }
    $untrustedRules = $dataAcl.Access | Where-Object {
        $_.IdentityReference.Value -match "Everyone|Authenticated Users|BUILTIN\\Users" -and
        $_.AccessControlType -eq "Allow"
    }
    if ($untrustedRules) { throw "Protected data is accessible to an untrusted local group." }
    $process = Get-Process -Name "ParentalControl.Windows.Service" -ErrorAction Stop
    $resourceEvidence = [ordered]@{
        serviceWorkingSetBytes = $process.WorkingSet64
        servicePrivateMemoryBytes = $process.PrivateMemorySize64
        installedBytes = (Get-ChildItem -LiteralPath $installRoot -File -Recurse | Measure-Object Length -Sum).Sum
        collectedAt = [DateTimeOffset]::UtcNow.ToString("O")
    }
    $resourceEvidence | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidenceRoot "resources.json") -Encoding utf8

    Invoke-Msi "/fa `"$msi`" /qn /norestart /l*v `"$repairLog`""
    (Get-Service -Name $serviceName).WaitForStatus("Running", [TimeSpan]::FromSeconds(20))
    $repairedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dataRoot "endpoint.dat")).Hash
    if ($identityHash -ne $repairedHash) { throw "Repair replaced protected endpoint identity." }
    $repairedStatus = Get-EndpointStatus
    if (-not $repairedStatus.success) { throw "Status failed after repair." }

    Invoke-Msi "/x `"$msi`" /qn /norestart /l*v `"$uninstallLog`""
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) { throw "Service remains after uninstall." }
    if (Test-Path $installRoot) { throw "Program files remain after uninstall." }
    if (Test-Path $dataRoot) { throw "Protected endpoint data remains after uninstall." }
    Write-Host "Windows MSI install, status, repair, identity retention, and uninstall passed."
} finally {
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Start-Process -FilePath msiexec.exe -ArgumentList "/x `"$msi`" /qn /norestart" -Wait | Out-Null
    }
}
