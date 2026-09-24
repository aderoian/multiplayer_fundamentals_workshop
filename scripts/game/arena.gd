extends Node2D
## Arena root — wires spawn manager, offline player, HUD, match lifecycle.

@onready var spawn_manager: SpawnManager = $SpawnManager
@onready var players_root: Node2D = $Players
@onready var pickups_root: Node2D = $Pickups
@onready var hud: CanvasLayer = $HUD
@onready var network_spawner: Node = $NetworkPlayerSpawner

const PICKUP_SCENE: PackedScene = preload("res://scenes/pickup.tscn")


func _ready() -> void:
	spawn_manager.gather()
	network_spawner.setup(players_root, spawn_manager.player_spawn_markers)
	_spawn_default_pickups()
	# Offline: spawn one local player and start match. Online spawn comes later.
	if multiplayer.multiplayer_peer == null:
		var player: CharacterBody2D = network_spawner.spawn_local_offline_player()
		Match.start_match(1)
		if player:
			(player as Node).get_node("Tag").set_it(true)
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
	# Clear players and pickups, re-seed offline session.
	network_spawner.clear_players()
	for c in pickups_root.get_children():
		c.queue_free()
	await get_tree().process_frame
	_spawn_default_pickups()
	if multiplayer.multiplayer_peer == null:
		var player: CharacterBody2D = network_spawner.spawn_local_offline_player()
		Match.restart_match(1)
		if player:
			(player as Node).get_node("Tag").set_it(true)
	else:
		Match.restart_match(1)
