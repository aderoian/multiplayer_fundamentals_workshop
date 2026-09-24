extends Node
class_name TagComponent
## Tag / "It" state for a single player. Exactly one It per match.

signal tag_changed(is_it: bool)

const TAG_COOLDOWN_SEC: float = 0.6
const TAG_RANGE: float = 48.0

var is_it: bool = false
var _cooldown_left: float = 0.0
var peer_id: int = 1


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)


func set_it(value: bool) -> void:
	if is_it == value:
		return
	is_it = value
	tag_changed.emit(is_it)


func can_tag_now() -> bool:
	return is_it and _cooldown_left <= 0.0


func begin_cooldown() -> void:
	_cooldown_left = TAG_COOLDOWN_SEC


# Ownership (tag / current It):
# 1) Who owns this? Server owns current_it_player and each is_it.
# 2) Who may change? Clients send a REQUEST; server validates and applies.
# 3) Who needs it? Everyone (IT label + who may tag).
# 4) Late join? Snapshot must include current_it_player / each is_it.


func try_tag_local(target_player: Node) -> bool:
	## Offline path: validate locally and apply immediately.
	if not can_tag_now():
		return false
	if target_player == null or not target_player.has_method("receive_tag_offline"):
		return false
	var health: HealthComponent = target_player.get_node_or_null("Health") as HealthComponent
	if health != null and not health.is_alive:
		return false
	var dist: float = (owner as Node2D).global_position.distance_to((target_player as Node2D).global_position)
	if dist > TAG_RANGE:
		return false
	begin_cooldown()
	set_it(false)
	target_player.receive_tag_offline(peer_id)
	return true
