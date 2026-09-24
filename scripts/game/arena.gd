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
	add_to_group("arena")
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
		_add_pickup(i + 1, types[i], markers[i].global_position)


func _add_pickup(net_id: int, item_id: int, pos: Vector2) -> void:
	var p: Area2D = PICKUP_SCENE.instantiate() as Area2D
	p.item_id = item_id
	p.set("pickup_net_id", net_id)
	pickups_root.add_child(p)
	p.global_position = pos


func apply_pickup_snapshot(pickups_data: Array) -> void:
	## World state for late joiners: replace local pickups with the server list.
	## Syncing deltas is not enough when someone joins mid-match.
	for c in pickups_root.get_children():
		c.queue_free()
	for entry in pickups_data:
		_add_pickup(int(entry.get("id", 0)), int(entry.get("item_id", 1)), entry.get("pos", Vector2.ZERO))


func restart_from_ui() -> void:
	network_spawner.clear_players()
	for c in pickups_root.get_children():
		c.queue_free()
	await get_tree().process_frame
	_spawn_default_pickups()
	if multiplayer.multiplayer_peer == null:
		var player: CharacterBody2D = network_spawner.spawn_local_offline_player()
		Match.restart_match(1)
		if player:
			(player as Node).get_node("Tag").call("set_it", true)
	else:
		if multiplayer.is_server():
			network_spawner.begin_online_session()
			Match.restart_match(1)
