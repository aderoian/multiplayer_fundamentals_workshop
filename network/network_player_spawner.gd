extends Node
## NetworkPlayerSpawner ΓÇö one Player instance per connected peer (checkpoint 02).
## Prefer MultiplayerSpawner so spawn/despawn replicate automatically.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var players_root: Node2D
var spawn_points: Array[Marker2D] = []
var _spawner: MultiplayerSpawner
## peer_id -> Player node
var players: Dictionary = {}


func setup(p_players_root: Node2D, p_spawn_points: Array[Marker2D], spawner: MultiplayerSpawner = null) -> void:
	players_root = p_players_root
	spawn_points = p_spawn_points
	_spawner = spawner
	if _spawner:
		_spawner.spawn_function = _spawn_player_from_data
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func begin_online_session() -> void:
	## Call from arena when a multiplayer peer exists. Server spawns all current peers.
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.is_server():
		# Client: register name with server; spawner will create our node.
		_rpc_register_name.rpc_id(1, Network.player_name)
		return
	# Host: register own name and spawn everyone already connected (host + existing).
	Network.peer_names[1] = Network.player_name
	_spawn_for_peer(1, Network.player_name)
	for id in multiplayer.get_peers():
		var n: String = str(Network.peer_names.get(id, "Player_%d" % id))
		_spawn_for_peer(id, n)


func spawn_local_offline_player() -> CharacterBody2D:
	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	player.name = "Player_1"
	players_root.add_child(player, true)
	player.call("setup_player", 1, Network.player_name, true)
	player.global_position = _spawn_position_for(1)
	players[1] = player
	return player


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# Do NOT spawn immediately ΓÇö the client may not have loaded the arena yet.
	# Spawn when they register a name from begin_online_session (arena _ready).
	# Late-join snapshot is sent after that spawn (see _rpc_register_name).
	print("[Spawner] peer_connected %d ΓÇö waiting for name/arena ready" % id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		var was_it: bool = (Match.current_it_player == id)
		_despawn_for_peer(id)
		Match.remove_player_score(id)
		if was_it:
			_reassign_it_after_disconnect()
	players.erase(id)


func _reassign_it_after_disconnect() -> void:
	## If the player who is It leaves, server picks another remaining peer and syncs.
	var next_it: int = -1
	for pid in players.keys():
		next_it = int(pid)
		break
	if next_it < 0:
		next_it = 1
	Match.reassign_it(next_it)
	print("[Spawner] It reassigned to peer %d after disconnect" % next_it)


func _spawn_for_peer(peer_id: int, display_name: String) -> void:
	if players.has(peer_id):
		return
	if _spawner == null:
		# Fallback without MultiplayerSpawner (should not happen in arena).
		var data := {"peer_id": peer_id, "player_name": display_name}
		var p: Node = _spawn_player_from_data(data)
		players_root.add_child(p, true)
		players[peer_id] = p
		return
	var data := {"peer_id": peer_id, "player_name": display_name}
	var node: Node = _spawner.spawn(data)
	if node:
		players[peer_id] = node


func _despawn_for_peer(peer_id: int) -> void:
	var node: Node = players.get(peer_id) as Node
	if node and is_instance_valid(node):
		node.queue_free()
	players.erase(peer_id)


func _spawn_player_from_data(data: Variant) -> Node:
	## MultiplayerSpawner.spawn_function ΓÇö runs on every peer when server spawns.
	var dict: Dictionary = data as Dictionary
	var peer_id: int = int(dict.get("peer_id", 1))
	if players.has(peer_id) and is_instance_valid(players[peer_id]):
		return players[peer_id]
	var display_name: String = str(dict.get("player_name", "Player"))
	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	# Authority + MultiplayerSynchronizer handle input and position (03/04).
	var is_local: bool = (multiplayer.multiplayer_peer == null) or (peer_id == multiplayer.get_unique_id())
	player.call("setup_player", peer_id, display_name, is_local)
	player.global_position = _spawn_position_for(peer_id)
	players[peer_id] = player
	Match.ensure_player_score(peer_id)
	return player


@rpc("any_peer", "reliable")
func _rpc_register_name(p_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	Network.peer_names[sender] = p_name
	# Client arena is ready (they called begin_online_session). Safe to spawn now.
	if players.has(sender):
		var p: Node = players[sender]
		if p.has_method("setup_player"):
			var is_local: bool = sender == multiplayer.get_unique_id()
			p.call("setup_player", sender, p_name, is_local)
	else:
		_spawn_for_peer(sender, p_name)
	# Resync everyone ΓÇö MultiplayerSpawner alone can miss peers whose arena
	# was not ready at an earlier spawn, and late joiners need existing bodies.
	_resync_all_player_nodes()
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer != null and multiplayer.is_server():
			Match.build_and_send_late_join(sender)
	)


func _resync_all_player_nodes() -> void:
	if not multiplayer.is_server():
		return
	for pid in multiplayer.get_peers():
		_sync_existing_players_to(int(pid))


func _sync_existing_players_to(peer_id: int) -> void:
	## Make sure a late joiner has every already-spawned Player node.
	for pid in players.keys():
		var node: Node = players[pid]
		if not is_instance_valid(node):
			continue
		var data := {
			"peer_id": int(pid),
			"player_name": str(Network.peer_names.get(pid, "Player_%d" % pid)),
			"pos": (node as Node2D).global_position,
		}
		_rpc_ensure_player.rpc_id(peer_id, data)


@rpc("authority", "reliable")
func _rpc_ensure_player(data: Dictionary) -> void:
	## Client receives existing players the MultiplayerSpawner may have missed.
	var peer_id: int = int(data.get("peer_id", 0))
	if peer_id == 0:
		return
	if players.has(peer_id):
		var existing: Node = players[peer_id]
		if is_instance_valid(existing) and data.has("pos"):
			(existing as Node2D).global_position = data["pos"]
		return
	var player: Node = _spawn_player_from_data(data)
	if players_root and player.get_parent() == null:
		players_root.add_child(player, true)
	if data.has("pos"):
		(player as Node2D).global_position = data["pos"]
	print("[Spawner] ensured Player_%d on peer %d" % [peer_id, multiplayer.get_unique_id()])


func get_player(peer_id: int) -> CharacterBody2D:
	return players.get(peer_id) as CharacterBody2D


func clear_players() -> void:
	for peer_id in players.keys():
		var n: Node = players[peer_id]
		if is_instance_valid(n):
			n.queue_free()
	players.clear()
	if players_root:
		for child in players_root.get_children():
			child.queue_free()


func _spawn_position_for(peer_id: int) -> Vector2:
	if spawn_points.is_empty():
		return Vector2(200, 200)
	var idx: int = abs(peer_id - 1) % spawn_points.size()
	return spawn_points[idx].global_position
