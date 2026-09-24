# Participant Guide — Network Tag

Start on branch **`workshop/00-starter`**. Do not peek at `workshop/10-complete` until you finish or the instructor says so.

```text
git checkout workshop/00-starter
```

Open `project.godot` in **Godot 4.3+**, press **F5**.

---

## Checkpoint 00 — Starter

**Goal:** Play and understand the offline game; find every `WORKSHOP TODO`.

**How to play offline**

1. Menu → **Play Offline**
2. WASD move, Shift sprint, 1/2/3 use items
3. Collect pickups (red=HP, cyan=Speed, yellow=Shield)
4. You start as **IT** (orange). With only one player, tag has no target yet — that’s OK
5. Timer counts down from 120s; match over shows winner by score

**Files to read:** `network/network_manager.gd`, `scripts/player/player.gd`, `scripts/game/match_manager.gd`, `scripts/world/pickup.gd`

**Concept:** Offline gameplay is done; networking is missing on purpose.

**TODOs to complete:** None yet — inventory the `WORKSHOP TODO` comments (search the project).

**Expected:** Offline arena works. Host/Join show a workshop status message.

---

## Checkpoint 01 — Connect

**Goal:** Implement real host/join with ENet.

**Files:** `network/network_manager.gd`, `scripts/ui/menu.gd`

**Concept:** peer, server, client, peer id, connection signals.

**TODOs:** `host_game`, `join_game` — create peer, assign `multiplayer.multiplayer_peer`, connect signals, show status + peer id, enter arena on success. Do **not** spawn remote players yet.

**Expected:** Host and client show connected status and peer ids. Play Offline still works.

---

## Checkpoint 02 — Player spawning

**Goal:** Spawn one player per peer; despawn on disconnect.

**Files:** `network/network_player_spawner.gd`, `scripts/game/arena.gd`

**Concept:** peer_id → instance lifecycle (`MultiplayerSpawner` preferred).

**TODOs:** spawn on `peer_connected` (and host self); despawn on `peer_disconnected`; pass name + id.

**Expected:** Each peer sees N player bodies. Input may still be wrong for remotes (next checkpoint).

---

## Checkpoint 03 — Player authority

**Goal:** Only the owning peer reads input; only their camera is on.

**Files:** `scripts/player/player.gd`

**Concept:** `set_multiplayer_authority` / `is_multiplayer_authority`.

**TODOs:** replace local-control checks; enable camera only for authority.

**Expected:** You move only your avatar. Remotes stand still until checkpoint 04.

---

## Checkpoint 04 — Movement

**Goal:** Sync authority position to everyone.

**Files:** `scenes/player.tscn` / `scripts/player/player.gd`

**Concept:** replication without prediction. Remotes look a bit late — OK.

**TODOs:** `MultiplayerSynchronizer` or unreliable position RPC; keep offline path working when `multiplayer_peer == null`.

**Expected:** Remote players move on your screen.

---

## Checkpoint 05 — Tag system

**Goal:** Tag via server-validated request RPC.

**Files:** `scripts/player/tag_component.gd`, `scripts/player/player.gd`, `scripts/game/match_manager.gd`

**Concept:** request → validate → broadcast result. Do not set another player’s `is_it` locally.

**Expected:** Only the current It can tag; visuals update for all; cooldown prevents ping-pong.

---

## Checkpoint 06 — Health

**Goal:** Server applies damage / death / respawn / shield; sync health.

**Files:** `scripts/player/health.gd`, `scripts/player/player.gd`

**Concept:** clients never authoritatively set another player’s HP.

**Expected:** Tag damage and death/respawn agree across peers.

---

## Checkpoint 07 — Inventory

**Goal:** Pickup and use-item requests; server grants once.

**Files:** `scripts/player/inventory.gd`, `scripts/world/pickup.gd`

**Concept:** first valid pickup request wins when two players contest.

**Expected:** Item appears in one inventory; world pickup disappears for all.

---

## Checkpoint 08 — World state

**Goal:** Server owns timer, scores, remaining pickups.

**Files:** `scripts/game/match_manager.gd`, arena / spawn pickup code

**Concept:** player vs world vs match state.

**Expected:** Same timer and scores on every peer; match over agrees.

---

## Checkpoint 09 — Late join

**Goal:** Joiner receives a full snapshot of current state.

**Files:** network spawner + match/player snapshot helpers

**Concept:** deltas ≠ enough for late joiners.

**Expected:** Joining mid-match shows existing players, It, HP, inventory, timer, scores, pickups.

---

## Checkpoint 10 — Complete

**Goal:** Use the reference; compare your work. It reassigns if It disconnects.

**Files:** whole project — `WORKSHOP TODO` markers removed; ownership comments remain.

**Expected:** Full host + 2 clients play session works end-to-end.
