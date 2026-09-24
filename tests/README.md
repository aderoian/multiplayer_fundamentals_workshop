# Optional smoke tests

These scripts are **optional**. Workshop teaching does not depend on them.

## Headless project load

```powershell
.\tools\Godot_v4.3-stable_win64_console.exe --headless --path . --quit-after 2
```

## Multiplayer smoke (host + clients)

`smoke_multiplayer.gd` boots multiple Godot processes (host + clients) when run with:

```powershell
.\tools\Godot_v4.3-stable_win64_console.exe --headless --path . -s res://tests/smoke_multiplayer.gd -- --workshop-smoke
```

Requires the Godot binary path (or `GODOT` env var). Output goes to stdout / `tests/output/`.

What it tries to verify:
- Host listens and clients connect
- Players spawn
- Basic RPC reachability

Full gameplay playtests (tag, inventory contests, late join) still need manual or extended automation.
