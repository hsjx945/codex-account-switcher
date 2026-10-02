param(
    [string]$Installer = 'windows/artifacts/Codex-Account-Switcher-Setup-win-x64.exe'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not (Test-Path $Installer)) { throw "Installer not found: $Installer" }
$base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$destination = Join-Path $base "codex-switcher-smoke-$PID"

function Invoke-Installer([string]$Executable, [string[]]$Arguments) {
    $start = [System.Diagnostics.ProcessStartInfo]::new((Resolve-Path $Executable).Path)
    $start.UseShellExecute = $false
    foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::Start($start)
    if (-not $process.WaitForExit(120000)) {
        $process.Kill($true)
        throw "Timed out waiting for $Executable"
    }
    if ($process.ExitCode -ne 0) { throw "$Executable exited with status $($process.ExitCode)" }
}

Invoke-Installer $Installer @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=$destination")
$app = Join-Path $destination 'CodexAccountSwitcher.Windows.exe'
$uninstall = Join-Path $destination 'unins000.exe'
if (-not (Test-Path $app) -or -not (Test-Path $uninstall)) {
    throw 'The installer did not install the app and uninstaller.'
}
Write-Output "Installed app: $app"
Invoke-Installer $uninstall @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
if (Test-Path $app) { throw 'Uninstall left the app executable behind.' }
Write-Output 'Install and uninstall smoke test passed.'
