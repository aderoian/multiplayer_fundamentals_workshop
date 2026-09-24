extends Area2D
class_name WorldPickup
## World pickup for Health Potion / Speed Boost / Shield.

signal collected(pickup: Node, by_player: Node)

@export var item_id: int = 1 ## InventoryComponent.ItemId

@onready var visual: Polygon2D = $Visual
@onready var label: Label = $Label

# WORKSHOP TODO:
# Pickups are WORLD STATE owned by the server.
# 1) Who owns remaining pickups? Server spawn list / scene tree on server.
# 2) Who may collect? Client sends request; server checks exists, range, inventory space, alive.
# 3) Who needs updates? Everyone must see the pickup disappear.
# 4) Late join? Snapshot remaining pickup ids/positions (checkpoint 09).
# Concept: first valid server request wins when two players overlap (07 / 08).


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_visual()
	add_to_group("pickups")


func get_item_id() -> int:
	return item_id


func _apply_visual() -> void:
	match item_id:
		1: # potion
			visual.color = Color(0.9, 0.25, 0.35)
			label.text = "HP"
		2: # speed
			visual.color = Color(0.3, 0.85, 0.95)
			label.text = "SPD"
		3: # shield
			visual.color = Color(0.95, 0.85, 0.2)
			label.text = "SH"
		_:
			visual.color = Color.WHITE
			label.text = "?"


func _on_body_entered(body: Node) -> void:
	if not (body is CharacterBody2D):
		return
	if not body.has_method("collect_pickup_offline"):
		return
	if multiplayer.multiplayer_peer == null:
		body.collect_pickup_offline(self)
		return
	# WORKSHOP TODO (07): request_pickup RPC instead of trusting the client to free this node.
	body.collect_pickup_offline(self)
