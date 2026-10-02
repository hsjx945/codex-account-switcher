param(
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$versionMatch = @(Select-String -Path (Join-Path $repo 'CITATION.cff') -Pattern '^version:\s*(\d+\.\d+\.\d+)\s*$')
if ($versionMatch.Count -ne 1) { throw 'CITATION.cff must contain exactly one semantic version.' }
$version = $versionMatch.Matches[0].Groups[1].Value
$project = Join-Path $repo 'windows/CodexAccountSwitcher.Windows.csproj'
$tests = Join-Path $repo 'windows/tests/CodexAccountSwitcher.Tests.csproj'
$publish = Join-Path $repo 'windows/artifacts/app'
$installerScript = Join-Path $repo 'windows/installer.iss'
$iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
if (-not (Test-Path $iscc)) { throw "Inno Setup compiler not found: $iscc" }

if (-not $SkipTests) {
    & dotnet run --project $tests --configuration Release
    if ($LASTEXITCODE -ne 0) { throw 'Windows core tests failed.' }
}

& dotnet publish $project --configuration Release --runtime win-x64 --self-contained true `
    '-p:PublishSingleFile=true' "-p:Version=$version" --output $publish
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
if (-not (Test-Path (Join-Path $publish 'CodexAccountSwitcher.Windows.exe'))) {
    throw 'Published application executable is missing.'
}

& $iscc "/DAppVersion=$version" $installerScript
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
$installer = Join-Path $repo 'windows/artifacts/Codex-Account-Switcher-Setup-win-x64.exe'
if (-not (Test-Path $installer)) { throw 'Installer executable is missing.' }
$hash = (Get-FileHash -Path $installer -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  Codex-Account-Switcher-Setup-win-x64.exe" |
    Set-Content -Path "$installer.sha256" -Encoding ascii
Write-Output $installer
