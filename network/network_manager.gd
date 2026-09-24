extends Node
## NetworkManager autoload — connection entry points for the workshop.
## Starter branch: Host/Join are intentionally incomplete (teaching TODOs).

signal connection_changed(status_text: String)
signal peer_list_changed

const DEFAULT_PORT: int = 7777
const DEFAULT_MAX_CLIENTS: int = 8

var player_name: String = "Player"
var address: String = "127.0.0.1"
var port: int = DEFAULT_PORT
var status_text: String = "Offline"
var local_peer_id: int = 1


func _ready() -> void:
	# Signals will be wired once ENet is created (checkpoint 01).
	pass


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null


func host_game(p_port: int = DEFAULT_PORT, p_name: String = "Host") -> void:
	player_name = p_name
	port = p_port
	# WORKSHOP TODO:
	# What is wrong: Host Game does not create an ENet server or assign multiplayer.multiplayer_peer.
	# Concept: ENetMultiplayerPeer.create_server + multiplayer.multiplayer_peer = peer (checkpoint 01).
	# Why it matters: Without a peer, Godot has no notion of other machines; Host/Join stay dead.
	# Change: create ENetMultiplayerPeer, call create_server(port), assign it, connect peer signals,
	# update status_text / local_peer_id, then change scene to the arena. Do NOT spawn players yet
	# in checkpoint 01 — connection only.
	status_text = "Networking is a workshop exercise"
	connection_changed.emit(status_text)
	print("[Network] host_game stub — implement ENet server in checkpoint 01")


func join_game(p_address: String = "127.0.0.1", p_port: int = DEFAULT_PORT, p_name: String = "Player") -> void:
	player_name = p_name
	address = p_address
	port = p_port
	# WORKSHOP TODO:
	# What is wrong: Join Game does not create an ENet client or connect to a host.
	# Concept: ENetMultiplayerPeer.create_client(address, port) + multiplayer.multiplayer_peer = peer.
	# Why it matters: Clients need a peer id assigned by the server and connection callbacks.
	# Change: create_client, assign peer, connect connected_to_server / connection_failed /
	# server_disconnected, update UI status. Do not spawn players until checkpoint 02.
	status_text = "Networking is a workshop exercise"
	connection_changed.emit(status_text)
	print("[Network] join_game stub — implement ENet client in checkpoint 01")


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	status_text = "Offline"
	local_peer_id = 1
	connection_changed.emit(status_text)
	peer_list_changed.emit()


func play_offline(p_name: String = "Player") -> void:
	disconnect_game()
	player_name = p_name
	status_text = "Offline"
	local_peer_id = 1
	connection_changed.emit(status_text)
