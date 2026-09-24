# Instructor Notes — Network Tag Workshop

Keep live coding small. Prefer filling one `WORKSHOP TODO` at a time. If a demo breaks:

```text
git checkout workshop/NN-<name>
# or
git checkout checkpoint-NN
```

Attendees start on **`workshop/00-starter`**. Solution is **`workshop/10-complete`**.

---

## Checkpoint 00 — Starter (offline)

**Goal:** Prove the game is fun offline and surface every networking gap as a readable TODO.

**Explain:** Player vs world vs match state; the four questions (own / change / receive / late join).

**Live-code:** None required — walk the arena, tag concept with two editors offline is optional.

**Common mistakes:** Students try to “add multiplayer” everywhere at once.

**Audience questions:** What breaks if two machines each run their own match timer?

**Progression:** Establish mental model before ENet.

---

## Checkpoint 01 — Connect

**Goal:** Host and join create a real `ENetMultiplayerPeer` and show peer id / status.

**Explain:** client vs server vs peer id; `multiplayer.multiplayer_peer = peer`.

**Live-code:** Fill `host_game` / `join_game`; wire `peer_connected`, `connected_to_server`, etc. Load arena after success. **Do not spawn players yet.**

**Common mistakes:** Forgetting to assign `multiplayer_peer`; joining before host listens.

**Audience questions:** What is my peer id on the host? On the first client?

**Progression:** Connection without gameplay replication.

---

## Checkpoint 02 — Player spawning

**Goal:** One `Player` instance per connected peer (including host).

**Explain:** Instances exist on every machine; spawn/despawn lifecycle.

**Live-code:** `MultiplayerSpawner` or explicit spawn RPC; pass peer id + name.

**Common mistakes:** Spawning only on the server’s scene tree without replication path.

**Audience questions:** If three peers connect, how many Player nodes should each machine have?

**Progression:** Bodies exist; input authority is next.

**Note:** Leave a TODO that everyone may still read keyboard input.

---

## Checkpoint 03 — Player authority

**Goal:** Only the owning peer processes input; only their camera is enabled.

**Explain:** The Player node is duplicated everywhere, but **one computer** reads WASD.

**Live-code:** `set_multiplayer_authority(peer_id)`; `is_multiplayer_authority()` for input/camera.

**Common mistakes:** Enabling every camera; checking `multiplayer.is_server()` for movement input.

**Sample audience question:** *Which computer should read the keyboard for Player 2 — the host, or the machine where that human sits?*

**Progression:** Local player moves; remotes idle until sync.

---

## Checkpoint 04 — Movement

**Goal:** Replicate authority position (synchronizer or unreliable RPC). No prediction.

**Explain:** Remotes look slightly late; prediction is a future topic, out of scope.

**Live-code:** Add `MultiplayerSynchronizer` on player or a tiny position RPC.

**Common mistakes:** Building interpolation/rollback “while we’re here.”

**Audience questions:** Who is allowed to invent a new position?

---

## Checkpoint 05 — Tag system

**Goal:** Tag is a **request**; server validates; everyone gets the result.

**Explain:** Clients must not set another player’s `is_it`.

**Live-code:** `request_tag` RPC → validate sender is It, range, alive → update Match + visuals.

**Scores:** Prefer tag state replication now; numeric scoreboard becomes clearly shared match state by 08. Host may see score updates earlier — call that out.

**Common mistakes:** Client-side `target.is_it = true`.

---

## Checkpoint 06 — Health

**Goal:** `take_damage`, death, respawn, shield absorption on the server; sync health.

**Explain:** Why a client must not say “Player B has 20 HP.”

**Live-code:** Server applies damage from valid tag; replicate health / alive / position on respawn.

---

## Checkpoint 07 — Inventory

**Goal:** `request_pickup` / use-item requests; server consumes pickup once.

**Explain:** Two overlapping players → only first valid request wins.

**Live-code:** Validate exists, range, space, alive; sync inventory + delete pickup.

---

## Checkpoint 08 — World / match state

**Goal:** Server owns timer, scores, remaining pickups; clients display copies.

**Explain:** Player vs world vs match state table again.

**Live-code:** Server tick timer; replicate scores and match over; pickup spawn list ownership.

---

## Checkpoint 09 — Late join

**Goal:** Mid-match joiner gets a **snapshot**, not only future deltas.

**Explain:** Syncing changes ≠ enough for late joiners.

**Live-code:** Explicit snapshot if spawner does not replicate already-spawned state; include health, inventory, It, scores, timer, pickups, boosts.

**Verify:** Actually connect a third peer after play has started.

---

## Checkpoint 10 — Complete

**Goal:** Reference solution; It reassignment on disconnect; remove obsolete `WORKSHOP TODO` markers; short ownership comments remain.

**Explain:** Celebrate the four questions as a lasting checklist.

**Recover:** Always safe to `git checkout workshop/10-complete`.

---

## Switching / recovery commands

```text
git branch -a
git tag
git checkout workshop/00-starter
git checkout checkpoint-03
git checkout workshop/10-complete
```

Do not force-push. Do not rewrite shared history during the workshop.
