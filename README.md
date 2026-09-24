# Network Tag — Multiplayer Fundamentals Workshop

Convert a working **offline** top-down tag game into a small multiplayer arena using Godot 4.x (`ENetMultiplayerPeer`, `@rpc`, `MultiplayerSpawner` / `MultiplayerSynchronizer`).

**Required Godot version:** 4.3+ (validated with **4.3.stable**)

**You are here:** `workshop/10-complete` — full reference solution. Networking TODOs are complete.

**Attendees start on:** `workshop/00-starter`

**Solution branch:** `workshop/10-complete`

---

## Prerequisites

- Basic Godot editor use (scenes, nodes, running the project)
- Basic GDScript (variables, functions, signals)
- **No prior networking knowledge required**

---

## How to run the starter

1. Open `project.godot` in Godot 4.3+
2. Press **F5** (main scene = menu)
3. Click **Play Offline**
4. Controls: **WASD** move, **Shift** sprint, **1 / 2 / 3** use inventory slots
5. Walk over colored pickups to collect; while **IT**, touch another player to tag (offline with one player: you start as It)

Host / Join create a real ENet peer and show peer id / status. Player spawning is still a later TODO.

---

## Testing multiplayer locally (later checkpoints)

Default: **IP `127.0.0.1`**, **port `7777`**

1. **Host:** run instance A → Host Game
2. **Client:** run instance B → Join Game with `127.0.0.1`
3. Multiple clients: Debug → **Customize Run Instances**, or launch a second Godot editor/process on the same project

---

## Multiplayer mental model

For **every** multiplayer variable, ask:

1. **Who owns this?**
2. **Who can change it?**
3. **Who needs to know about it?**
4. **What happens when someone joins late?**

State categories in this project:

| Kind | Examples |
|------|----------|
| Player state | position, health, inventory, `is_it` |
| World state | remaining pickups |
| Match state | timer, scores, started, current It id |

---

## Workshop progression

| Checkpoint | Branch | Focus |
|------------|--------|-------|
| 00 | `workshop/00-starter` | Offline game + networking TODOs |
| 01 | `workshop/01-connect` | ENet host/join, peer id, connection signals |
| 02 | `workshop/02-player-spawning` | One player instance per peer |
| 03 | `workshop/03-player-authority` | `set_multiplayer_authority`, input + camera |
| 04 | `workshop/04-movement` | Sync position (no prediction) |
| 05 | `workshop/05-tag-system` | Tag request → server validate → result |
| 06 | `workshop/06-health` | Server-auth damage, death, respawn |
| 07 | `workshop/07-inventory` | Pickup/use requests; first valid wins |
| 08 | `workshop/08-world-state` | Timer, scores, pickups as shared state |
| 09 | `workshop/09-late-join` | Snapshot for mid-match joiners |
| 10 | `workshop/10-complete` | It reassignment, polish, reference solution |

Switch checkpoints:

```text
git checkout workshop/00-starter
git checkout workshop/10-complete
git checkout checkpoint-05
```

---

## Workshop TODO locations (this branch: 10-complete)

All networking `WORKSHOP TODO` markers are **complete** on this branch. Ownership decisions remain as short teaching comments (who owns / who changes / who receives / late join).

| Topic | Reference location | Status |
|-------|-------------------|--------|
| ENet host/join | `network/network_manager.gd` | Done |
| Spawn / despawn / It reassignment | `network/network_player_spawner.gd` | Done |
| Authority + movement sync | `scripts/player/player.gd`, `scenes/player.tscn` | Done |
| Tag request → validate → result | `player.gd` `request_tag`, `Match.rpc_apply_tag_result` | Done |
| Health / death / respawn | `scripts/player/health.gd`, `player.gd` | Done |
| Inventory / pickup | `player.gd` requests, `scripts/world/pickup.gd` | Done |
| Match timer / scores | `scripts/game/match_manager.gd` | Done |
| Late-join snapshot | `Match.build_and_send_late_join` | Done |

On earlier branches, search for `WORKSHOP TODO` to see the incomplete markers.

---

## Network flow diagrams (target design)

### PLAYER MOVEMENT

```text
[Authority peer]  WASD → move_and_slide → position
        │
        ▼  MultiplayerSynchronizer / unreliable RPC
[Other peers]  apply remote transform (slightly late — OK)
```

### DAMAGE

```text
[Contact / item] → request or server detects
        │
        ▼
[Server] validate → Health.take_damage → sync health / death
        │
        ▼
[All peers] update bars / visuals
```

### PICKUP

```text
[Client] overlap → request_pickup(item_id)
        │
        ▼
[Server] exists? in range? space? alive? → add item, remove pickup, sync
        │  (second request for same pickup fails)
        ▼
[All peers] inventory UI + world pickup gone
```

---

## Project layout

```text
project.godot          # open this in Godot
scenes/                # menu, arena, player, pickup
scripts/player|world|game|ui/
network/               # connection + spawn infrastructure (see network/README.md)
docs/                  # instructor + participant guides
```

Autoloads: `Network`, `Match`

---

## Host is It

When a networked match starts, **the host (peer id 1) is It**. Documented in match start code on later branches.
