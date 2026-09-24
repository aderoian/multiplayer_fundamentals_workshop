param(
  [int]$Clients = 1,
  [int]$Port = 7791,
  [switch]$LateJoin
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root

$godot = $env:GODOT
if (-not $godot -or -not (Test-Path $godot)) {
  $godot = Join-Path $root "tools\Godot_v4.3-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) {
  throw "Godot binary not found: $godot"
}

New-Item -ItemType Directory -Force -Path "tests\output" | Out-Null
Remove-Item "tests\output\gameplay_results.json" -ErrorAction SilentlyContinue

Write-Host "Godot: $godot | Clients=$Clients Port=$Port LateJoin=$LateJoin"

$hostArgList = @(
  "--headless", "--path", "$root",
  "res://tests/mp_boot.tscn",
  "--", "--workshop-gameplay", "--role=host", "--port=$Port", "--clients=$Clients"
)
if ($LateJoin) {
  $hostArgList += "--late-join"
}

$hostProc = Start-Process -FilePath $godot -ArgumentList $hostArgList -PassThru -NoNewWindow `
  -RedirectStandardOutput "tests\output\host_stdout.txt" `
  -RedirectStandardError "tests\output\host_stderr.txt"

Start-Sleep -Milliseconds 1000

$clientProcs = @()
for ($i = 1; $i -le $Clients; $i++) {
  $cArgs = @(
    "--headless", "--path", "$root",
    "res://tests/mp_boot.tscn",
    "--", "--workshop-gameplay", "--role=client", "--port=$Port", "--name=C$i"
  )
  $clientProcs += Start-Process -FilePath $godot -ArgumentList $cArgs -PassThru -NoNewWindow `
    -RedirectStandardOutput "tests\output\client${i}_stdout.txt" `
    -RedirectStandardError "tests\output\client${i}_stderr.txt"
  Start-Sleep -Milliseconds 500
}

$lateProc = $null
if ($LateJoin) {
  Start-Sleep -Seconds 4
  $lateArgs = @(
    "--headless", "--path", "$root",
    "res://tests/mp_boot.tscn",
    "--", "--workshop-gameplay", "--role=client", "--port=$Port", "--name=Late"
  )
  $lateProc = Start-Process -FilePath $godot -ArgumentList $lateArgs -PassThru -NoNewWindow `
    -RedirectStandardOutput "tests\output\late_stdout.txt" `
    -RedirectStandardError "tests\output\late_stderr.txt"
}

$timeoutSec = 70
$sw = [Diagnostics.Stopwatch]::StartNew()
while (-not $hostProc.HasExited -and $sw.Elapsed.TotalSeconds -lt $timeoutSec) {
  Start-Sleep -Milliseconds 400
}

if (-not $hostProc.HasExited) {
  Write-Host "Host timed out - killing processes"
  try { Stop-Process -Id $hostProc.Id -Force } catch {}
  foreach ($p in $clientProcs) {
    try { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } } catch {}
  }
  if ($lateProc -and -not $lateProc.HasExited) {
    try { Stop-Process -Id $lateProc.Id -Force } catch {}
  }
  if (Test-Path "tests\output\host_stdout.txt") {
    Get-Content "tests\output\host_stdout.txt" | Select-Object -Last 50
  }
  if (Test-Path "tests\output\host_stderr.txt") {
    Get-Content "tests\output\host_stderr.txt" | Select-Object -Last 50
  }
  exit 1
}

foreach ($p in $clientProcs) {
  try { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } } catch {}
}
if ($lateProc -and -not $lateProc.HasExited) {
  try { Stop-Process -Id $lateProc.Id -Force } catch {}
}

Write-Host "Host exit: $($hostProc.ExitCode)"
Write-Host "HOST STDOUT"
if (Test-Path "tests\output\host_stdout.txt") { Get-Content "tests\output\host_stdout.txt" }
Write-Host "HOST STDERR"
if (Test-Path "tests\output\host_stderr.txt") { Get-Content "tests\output\host_stderr.txt" }
Write-Host "RESULTS"
if (Test-Path "tests\output\gameplay_results.json") {
  Get-Content "tests\output\gameplay_results.json" -Raw
} else {
  Write-Host "(no results json)"
}

exit $hostProc.ExitCode
