extends Area2D
class_name WorldPickup
## World pickup for Health Potion / Speed Boost / Shield.

signal collected(pickup: Node, by_player: Node)

@export var item_id: int = 1
@export var pickup_net_id: int = 0 ## Stable id assigned by server for networking

@onready var visual: Polygon2D = $Visual
@onready var label: Label = $Label

const PICKUP_RANGE: float = 40.0

# Ownership (world pickups):
# 1) Who owns remaining pickups? Server.
# 2) Who may collect? Client REQUEST; server validates exists/range/space/alive.
# 3) Who needs updates? Everyone must see the pickup disappear.
# 4) Late join? Snapshot remaining pickups (09).
# Two players contesting: first valid server request wins.


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_visual()
	add_to_group("pickups")
	# pickup_net_id should be set by the spawner (stable 1..N). Do not use instance_id.

func get_item_id() -> int:
	return item_id


func _apply_visual() -> void:
	match item_id:
		1:
			visual.color = Color(0.9, 0.25, 0.35)
			label.text = "HP"
		2:
			visual.color = Color(0.3, 0.85, 0.95)
			label.text = "SPD"
		3:
			visual.color = Color(0.95, 0.85, 0.2)
			label.text = "SH"
		_:
			visual.color = Color.WHITE
			label.text = "?"


func _on_body_entered(body: Node) -> void:
	if not (body is CharacterBody2D):
		return
	if multiplayer.multiplayer_peer == null:
		if body.has_method("collect_pickup_offline"):
			body.collect_pickup_offline(self)
		return
	# Online: only the local authority asks the server.
	if body.has_method("request_pickup_from_world"):
		body.call("request_pickup_from_world", self)
