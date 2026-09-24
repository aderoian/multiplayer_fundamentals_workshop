extends Node
## NetworkPlayerSpawner — spawns one player instance per connected peer.
## Starter: offline spawn only. Networked spawn is a later checkpoint.

# WORKSHOP TODO:
# What is wrong: Connected peers do not get a Player instance yet.
# Concept: spawn on peer_connected / despawn on peer_disconnected (MultiplayerSpawner or RPC).
# Why it matters: Each peer needs a CharacterBody2D representation on every machine.
# Change (checkpoint 02): when a peer connects, spawn a player with that peer_id and name;
# when they disconnect, free their instance. Authority comes in checkpoint 03 — for now
# all instances may still read local input (document that remaining gap).

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var players_root: Node2D
var spawn_points: Array[Marker2D] = []


func setup(p_players_root: Node2D, p_spawn_points: Array[Marker2D]) -> void:
	players_root = p_players_root
	spawn_points = p_spawn_points


func spawn_local_offline_player() -> CharacterBody2D:
	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	player.name = "Player_1"
	players_root.add_child(player)
	if player.has_method("setup_player"):
		player.call("setup_player", 1, Network.player_name, true)
	var pos: Vector2 = _spawn_position_for(1)
	player.global_position = pos
	return player


func _spawn_position_for(peer_id: int) -> Vector2:
	if spawn_points.is_empty():
		return Vector2(200, 200)
	var idx: int = abs(peer_id - 1) % spawn_points.size()
	return spawn_points[idx].global_position


func clear_players() -> void:
	if players_root == null:
		return
	for child in players_root.get_children():
		child.queue_free()
