[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$stageRoot = Join-Path $repoRoot ".artifacts\build\stage-08"
$payload = Join-Path $stageRoot "payload"
$installerOutput = Join-Path $stageRoot "installer"
$candidateRoot = Join-Path $repoRoot ".artifacts\release-candidate"
$candidate = Join-Path $candidateRoot "ParentalControlWindows-0.8.0-rc.2-x64.msi"
$solution = Join-Path $repoRoot "agents\endpoint-windows\ParentalControl.Windows.sln"
$installerProject = Join-Path $repoRoot "agents\endpoint-windows\installer\ParentalControl.Windows.Installer.wixproj"

if ($stageRoot -ne (Join-Path $repoRoot ".artifacts\build\stage-08")) {
    throw "Refusing to clean an unexpected build path."
}
if (Test-Path $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $payload, $installerOutput, $candidateRoot | Out-Null

dotnet restore $solution --locked-mode
if ($LASTEXITCODE -ne 0) { throw "Solution restore failed." }
dotnet test (Join-Path $repoRoot "agents\endpoint-windows\tests\ParentalControl.Windows.Tests\ParentalControl.Windows.Tests.csproj") `
    --no-restore --configuration Release --maxcpucount:2
if ($LASTEXITCODE -ne 0) { throw "Unit tests failed." }

dotnet publish (Join-Path $repoRoot "agents\endpoint-windows\src\ParentalControl.Windows.Service\ParentalControl.Windows.Service.csproj") `
    --no-restore --configuration Release --runtime win-x64 --self-contained true `
    --output $payload --maxcpucount:2 -p:PublishReadyToRun=false
if ($LASTEXITCODE -ne 0) { throw "Service publish failed." }
dotnet publish (Join-Path $repoRoot "agents\endpoint-windows\src\ParentalControl.Windows.App\ParentalControl.Windows.App.csproj") `
    --no-restore --configuration Release --runtime win-x64 --self-contained true `
    --output $payload --maxcpucount:2 -p:PublishReadyToRun=false
if ($LASTEXITCODE -ne 0) { throw "App publish failed." }
dotnet publish (Join-Path $repoRoot "agents\endpoint-windows\src\ParentalControl.Windows.BrowserHost\ParentalControl.Windows.BrowserHost.csproj") `
    --no-restore --configuration Release --runtime win-x64 --self-contained true `
    --output $payload --maxcpucount:2 -p:PublishReadyToRun=false
if ($LASTEXITCODE -ne 0) { throw "Browser host publish failed." }
Copy-Item -LiteralPath (Join-Path $repoRoot "agents\endpoint-windows\installer\windows-native-host-manifest.json") `
    -Destination (Join-Path $payload "windows-native-host-manifest.json") -Force

dotnet restore $installerProject --locked-mode
if ($LASTEXITCODE -ne 0) { throw "Installer restore failed." }
dotnet build $installerProject --no-restore --configuration Release --maxcpucount:2 `
    -p:PayloadDir=$payload -p:OutputPath=$installerOutput
if ($LASTEXITCODE -ne 0) { throw "MSI build failed." }

$builtMsi = Get-ChildItem -LiteralPath $installerOutput -Filter "*.msi" -File -Recurse
if ($builtMsi.Count -ne 1) { throw "Expected exactly one MSI; found $($builtMsi.Count)." }
Copy-Item -LiteralPath $builtMsi[0].FullName -Destination $candidate -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidate).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$candidate.sha256" -Encoding ascii -NoNewline `
    -Value "$hash  $([IO.Path]::GetFileName($candidate))`n"

$signature = Get-AuthenticodeSignature -LiteralPath $candidate
Write-Host "Candidate: $candidate"
Write-Host "SHA-256: $hash"
Write-Host "Authenticode: $($signature.Status)"
