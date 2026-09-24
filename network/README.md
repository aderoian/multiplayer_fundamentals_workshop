# Network folder
#
# This folder holds *connection / spawn infrastructure*, not gameplay rules.
# Gameplay (tag, health, inventory, match timer) lives under scripts/.
#
# | File | Role | Filled in |
# |------|------|-----------|
# | network_manager.gd | ENet host/join, peer signals, status | Done on 01-connect |
# | network_player_spawner.gd | Spawn/despawn Player per peer | 02-player-spawning |
# | README.md | This map | always |
#
# Gameplay networking (RPCs / synchronizers) stays next to the system it belongs to:
# player.gd, tag_component.gd, health.gd, inventory.gd, match_manager.gd, pickup.gd.
#
# Keep this folder small on purpose — participants should see @rpc and
# multiplayer.multiplayer_peer = peer in the scripts they type live.
