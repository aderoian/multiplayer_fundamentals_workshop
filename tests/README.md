# Optional smoke tests

These scripts are **optional**. Workshop teaching does not depend on them.

## Headless project load

```powershell
.\tools\Godot_v4.3-stable_win64_console.exe --headless --path . --quit-after 2
```

## Gameplay multiplayer smoke (required for release confidence)

Launches real Godot processes (host + N clients) against `workshop/10-complete`:

```powershell
.\tests\run_gameplay_smoke.ps1 -Clients 1 -Port 7791
.\tests\run_gameplay_smoke.ps1 -Clients 2 -Port 7792 -LateJoin
```

Uses `tests/mp_boot.tscn` (autoload-safe) and `tests/test_relay.gd` (RPC test bus). Results: `tests/output/gameplay_results.json`.

Scenarios covered:
- connection + spawn
- movement replication
- tag transfer + damage
- death / respawn
- contested pickup (one winner)
- scores / timer agreement
- late join snapshot agreement
- It reassignment on disconnect + despawn

## Legacy connection-only smoke

```powershell
$env:GODOT = (Resolve-Path .\tools\Godot_v4.3-stable_win64_console.exe).Path
.\tools\Godot_v4.3-stable_win64_console.exe --headless --path . -s res://tests/smoke_multiplayer.gd -- --workshop-smoke
```
