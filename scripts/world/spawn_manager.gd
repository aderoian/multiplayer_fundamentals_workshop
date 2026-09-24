extends Node
class_name SpawnManager
## Collects spawn / respawn / pickup markers from the arena.

@export var player_spawns_path: NodePath
@export var respawn_points_path: NodePath
@export var pickup_spawns_path: NodePath

var player_spawn_markers: Array[Marker2D] = []
var respawn_markers: Array[Marker2D] = []
var pickup_spawn_markers: Array[Marker2D] = []


func gather() -> void:
	player_spawn_markers.clear()
	respawn_markers.clear()
	pickup_spawn_markers.clear()
	_collect(player_spawns_path, player_spawn_markers)
	_collect(respawn_points_path, respawn_markers)
	_collect(pickup_spawns_path, pickup_spawn_markers)
	for m in respawn_markers:
		m.add_to_group("respawn_points")


func _collect(path: NodePath, into: Array[Marker2D]) -> void:
	if path.is_empty():
		return
	var node := get_node_or_null(path)
	if node == null:
		return
	for child in node.get_children():
		if child is Marker2D:
			into.append(child)
