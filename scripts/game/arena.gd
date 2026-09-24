extends Node2D
## Arena root — wires spawn manager, offline/online players, HUD, match lifecycle.

@onready var spawn_manager: SpawnManager = $SpawnManager
@onready var players_root: Node2D = $Players
@onready var pickups_root: Node2D = $Pickups
@onready var hud: CanvasLayer = $HUD
@onready var network_spawner: Node = $NetworkPlayerSpawner
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner

const PICKUP_SCENE: PackedScene = preload("res://scenes/pickup.tscn")


func _ready() -> void:
	spawn_manager.gather()
	network_spawner.setup(players_root, spawn_manager.player_spawn_markers, multiplayer_spawner)
	_spawn_default_pickups()
	if multiplayer.multiplayer_peer == null:
		var player: CharacterBody2D = network_spawner.spawn_local_offline_player()
		Match.start_match(1)
		if player:
			(player as Node).get_node("Tag").call("set_it", true)
	else:
		# Online: spawn via MultiplayerSpawner (server). Host is It at match start.
		network_spawner.begin_online_session()
		if multiplayer.is_server():
			Match.start_match(1)
	hud.setup(self)


func _spawn_default_pickups() -> void:
	var types: Array[int] = [1, 2, 3, 1, 2, 3]
	var markers: Array[Marker2D] = spawn_manager.pickup_spawn_markers
	for i in range(mini(types.size(), markers.size())):
		var p: Area2D = PICKUP_SCENE.instantiate() as Area2D
		p.item_id = types[i]
		pickups_root.add_child(p)
		p.global_position = markers[i].global_position


func restart_from_ui() -> void:
	## Only the host/server may restart. Keep MultiplayerSpawner player nodes.
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	_server_restart_match()


func _server_restart_match() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		_reset_pickups_local()
		for n in get_tree().get_nodes_in_group("players"):
			if n.has_method("reset_for_new_match"):
				var spawn: Vector2 = _spawn_pos_for(int(n.get("peer_id")))
				n.call("reset_for_new_match", true, spawn)
		Match.restart_match(1)
		return
	_rpc_restart_match.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_restart_match() -> void:
	## All peers: reset pickups + each existing player. Do not free MultiplayerSpawner nodes.
	_reset_pickups_local()
	for n in get_tree().get_nodes_in_group("players"):
		if not (n is CharacterBody2D):
			continue
		var pid: int = int(n.get("peer_id"))
		var spawn: Vector2 = _spawn_pos_for(pid)
		var as_it: bool = (pid == 1)
		if n.has_method("reset_for_new_match"):
			n.call("reset_for_new_match", as_it, spawn)
	if multiplayer.is_server():
		Match.restart_match(1)


func _reset_pickups_local() -> void:
	var old: Array = pickups_root.get_children()
	for c in old:
		pickups_root.remove_child(c)
		c.free()
	_spawn_default_pickups()


func _spawn_pos_for(peer_id: int) -> Vector2:
	var markers: Array[Marker2D] = spawn_manager.player_spawn_markers
	if markers.is_empty():
		return Vector2(200, 200)
	var idx: int = abs(peer_id - 1) % markers.size()
	return markers[idx].global_position
