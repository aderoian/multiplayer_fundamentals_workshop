extends Node
## NetworkManager autoload — ENet host/join (checkpoint 01).

signal connection_changed(status_text: String)
signal peer_list_changed
signal server_ready
signal client_connected_ok

const DEFAULT_PORT: int = 7777
const DEFAULT_MAX_CLIENTS: int = 8

var player_name: String = "Player"
var address: String = "127.0.0.1"
var port: int = DEFAULT_PORT
var status_text: String = "Offline"
var local_peer_id: int = 1
## peer_id -> display name (filled as peers connect; names synced later)
var peer_names: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null


func host_game(p_port: int = DEFAULT_PORT, p_name: String = "Host") -> Error:
	player_name = p_name
	port = p_port
	disconnect_game()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, DEFAULT_MAX_CLIENTS)
	if err != OK:
		status_text = "Host failed: %s" % error_string(err)
		connection_changed.emit(status_text)
		return err
	multiplayer.multiplayer_peer = peer
	local_peer_id = multiplayer.get_unique_id()
	peer_names[local_peer_id] = player_name
	status_text = "Hosting on port %d (peer %d)" % [port, local_peer_id]
	connection_changed.emit(status_text)
	peer_list_changed.emit()
	server_ready.emit()
	print("[Network] Host ready peer_id=%d port=%d" % [local_peer_id, port])
	return OK


func join_game(p_address: String = "127.0.0.1", p_port: int = DEFAULT_PORT, p_name: String = "Player") -> Error:
	player_name = p_name
	address = p_address
	port = p_port
	disconnect_game()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		status_text = "Join failed: %s" % error_string(err)
		connection_changed.emit(status_text)
		return err
	multiplayer.multiplayer_peer = peer
	status_text = "Connecting to %s:%d ..." % [address, port]
	connection_changed.emit(status_text)
	print("[Network] Client connecting to %s:%d" % [address, port])
	return OK


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	status_text = "Offline"
	local_peer_id = 1
	peer_names.clear()
	connection_changed.emit(status_text)
	peer_list_changed.emit()


func play_offline(p_name: String = "Player") -> void:
	disconnect_game()
	player_name = p_name
	status_text = "Offline"
	local_peer_id = 1
	connection_changed.emit(status_text)


func _on_peer_connected(id: int) -> void:
	print("[Network] peer_connected id=%d" % id)
	peer_list_changed.emit()
	# WORKSHOP TODO:
	# What is wrong: A connected peer does not yet get a Player CharacterBody2D.
	# Concept: spawn/despawn one player instance per peer_id (checkpoint 02).
	# Why it matters: Without instances there is nothing to move, tag, or sync.
	# Change: on peer_connected (and for the host itself when entering the arena),
	# spawn a player with that peer_id and name; despawn on peer_disconnected.
	# Authority is checkpoint 03 — instances may still all read local input until then.


func _on_peer_disconnected(id: int) -> void:
	print("[Network] peer_disconnected id=%d" % id)
	peer_names.erase(id)
	peer_list_changed.emit()


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	peer_names[local_peer_id] = player_name
	status_text = "Connected as peer %d" % local_peer_id
	connection_changed.emit(status_text)
	peer_list_changed.emit()
	client_connected_ok.emit()
	print("[Network] connected_to_server peer_id=%d" % local_peer_id)


func _on_connection_failed() -> void:
	status_text = "Connection failed"
	connection_changed.emit(status_text)
	disconnect_game()


func _on_server_disconnected() -> void:
	status_text = "Server disconnected"
	connection_changed.emit(status_text)
	disconnect_game()
