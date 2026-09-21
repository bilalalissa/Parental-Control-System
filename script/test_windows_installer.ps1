[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath
)

$ErrorActionPreference = "Stop"
$msi = (Resolve-Path $MsiPath).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$evidenceRoot = Join-Path $repoRoot ".artifacts\test-results\stage-08"
$installLog = Join-Path $evidenceRoot "install.log"
$repairLog = Join-Path $evidenceRoot "repair.log"
$uninstallLog = Join-Path $evidenceRoot "uninstall.log"
$installRoot = Join-Path $env:ProgramFiles "Parental Control System\Windows Child Endpoint"
$dataRoot = Join-Path $env:ProgramData "Parental Control\Windows Endpoint"
$serviceName = "ParentalControlWindowsEndpoint"
$unreadableFixture = [byte[]](0x01, 0x02, 0x03, 0x04)
$fixtureCreated = $false
$installAttempted = $false
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

function Invoke-EndpointRequest([string]$bodyText) {
    $pipe = [IO.Pipes.NamedPipeClientStream]::new(".", "ParentalControl.Windows.Endpoint.v1", [IO.Pipes.PipeDirection]::InOut)
    try {
        $pipe.Connect(5000)
        $body = [Text.Encoding]::UTF8.GetBytes($bodyText)
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
    if (Test-Path $dataRoot) {
        throw "Recovery fixture requires an otherwise clean Windows endpoint data directory."
    }
    New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $dataRoot "endpoint.dat"), $unreadableFixture)
    $fixtureCreated = $true
    $unreadableFixtureHash = (Get-FileHash -Algorithm SHA256 -LiteralPath `
        (Join-Path $dataRoot "endpoint.dat")).Hash

    $installAttempted = $true
    Invoke-Msi "/i `"$msi`" /qn /norestart /l*v `"$installLog`""
    $service = Get-Service -Name $serviceName
    if ($service.StartType -ne "Automatic") { throw "Endpoint service is not automatic." }
    $serviceConfiguration = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
    if ($serviceConfiguration.StartName -ne "LocalSystem") { throw "Unexpected service account." }
    if ($service.Status -ne "Running") { Start-Service $serviceName }
    $service.WaitForStatus("Running", [TimeSpan]::FromSeconds(20))
    if (-not (Test-Path (Join-Path $installRoot "ParentalControl.Windows.Service.exe"))) { throw "Service payload missing." }
    if (-not (Test-Path (Join-Path $installRoot "ParentalControl.Windows.App.exe"))) { throw "Visible app payload missing." }
    if (-not (Test-Path (Join-Path $installRoot "ParentalControl.Windows.BrowserHost.exe"))) { throw "Browser host payload missing." }
    $nativeManifestPath = Join-Path $installRoot "windows-native-host-manifest.json"
    if (-not (Test-Path $nativeManifestPath)) { throw "Browser native-host manifest missing." }
    $nativeManifest = Get-Content -LiteralPath $nativeManifestPath -Raw | ConvertFrom-Json
    if ($nativeManifest.name -ne "com.bilalalissa.parental_control") { throw "Unexpected browser native-host name." }
    if ($nativeManifest.allowed_origins.Count -ne 1 -or
        $nativeManifest.allowed_origins[0] -ne "chrome-extension://pdcjgejgdjomjjemejhjhmdkcabkidmi/") {
        throw "Browser native-host origin is not narrowly bound."
    }
    foreach ($browserKey in @(
        "HKLM:\Software\Google\Chrome\NativeMessagingHosts\com.bilalalissa.parental_control",
        "HKLM:\Software\Microsoft\Edge\NativeMessagingHosts\com.bilalalissa.parental_control")) {
        if ((Get-Item -LiteralPath $browserKey).GetValue("") -ne $nativeManifestPath) {
            throw "Browser native-host registration is missing or incorrect: $browserKey"
        }
    }
    $uninstallEntry = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" |
        Get-ItemProperty | Where-Object { $_.DisplayName -eq "Parental Control Child" } |
        Select-Object -First 1
    if (-not $uninstallEntry) { throw "Windows Installer registration is missing." }
    if ($uninstallEntry.PSObject.Properties.Name -contains "NoRepair") {
        throw "Windows Installer repair is incorrectly hidden from Programs and Features."
    }

    $health = Invoke-EndpointRequest '{"operation":"health"}'
    if (-not $health.success) { throw "Local service health request failed." }
    $identityPath = Join-Path $dataRoot "endpoint.dat"
    $unreadablePath = "$identityPath.unreadable"
    if (-not (Test-Path $unreadablePath)) { throw "Unreadable state was not preserved." }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $unreadablePath).Hash -ne $unreadableFixtureHash) {
        throw "Preserved unreadable state does not match the recovery fixture."
    }
    $identityHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $identityPath).Hash
    if ($identityHash -eq $unreadableFixtureHash) { throw "Unreadable state was not replaced." }
    $serviceLog = Get-Content -LiteralPath (Join-Path $dataRoot "endpoint.log") -Raw
    if ($serviceLog -notmatch "configuration\.recovered") {
        throw "Service did not record bounded unreadable-state recovery."
    }
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
    $resourceJson = $resourceEvidence | ConvertTo-Json
    $resourceJson | Set-Content -LiteralPath (Join-Path $evidenceRoot "resources.json") -Encoding utf8
    Write-Host "Stage 08 resource evidence: $($resourceJson -replace '\r?\n', ' ')"

    Invoke-Msi "/fa `"$msi`" /qn /norestart /l*v `"$repairLog`""
    (Get-Service -Name $serviceName).WaitForStatus("Running", [TimeSpan]::FromSeconds(20))
    $repairedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dataRoot "endpoint.dat")).Hash
    if ($identityHash -ne $repairedHash) { throw "Repair replaced protected endpoint identity." }
    $repairedHealth = Invoke-EndpointRequest '{"operation":"health"}'
    if (-not $repairedHealth.success) { throw "Health request failed after repair." }

    Invoke-Msi "/x `"$msi`" /qn /norestart /l*v `"$uninstallLog`""
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) { throw "Service remains after uninstall." }
    if (Test-Path $installRoot) { throw "Program files remain after uninstall." }
    if (Test-Path $dataRoot) { throw "Protected endpoint data remains after uninstall." }
    Write-Host "Windows MSI install, visible repair registration, health, browser-host registration, repair, identity retention, and uninstall passed."
} finally {
    if ($installAttempted -and (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath msiexec.exe -ArgumentList "/x `"$msi`" /qn /norestart" -Wait | Out-Null
    }
    if ($fixtureCreated -and (Test-Path $dataRoot)) {
        foreach ($name in @("endpoint.dat", "endpoint.dat.new", "endpoint.dat.unreadable", "endpoint.log", "endpoint.log.1")) {
            $candidate = Join-Path $dataRoot $name
            if (Test-Path $candidate) { Remove-Item -LiteralPath $candidate -Force }
        }
        if (-not (Get-ChildItem -LiteralPath $dataRoot -Force)) {
            Remove-Item -LiteralPath $dataRoot -Force
        }
    }
}
