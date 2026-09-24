extends Node
class_name InventoryComponent
## Tiny inventory: 3 slots. Items = Health Potion, Speed Boost, Shield.

signal inventory_changed(slots: Array)
signal item_used(slot_index: int, item_id: int)
signal speed_boost_changed(active: bool, time_left: float)
signal shield_changed(active: bool)

enum ItemId {
	NONE = 0,
	HEALTH_POTION = 1,
	SPEED_BOOST = 2,
	SHIELD = 3,
}

const MAX_SLOTS: int = 3
const POTION_HEAL: int = 40
const SPEED_BOOST_DURATION: float = 4.0
const SPEED_BOOST_MULTIPLIER: float = 1.6

var slots: Array[int] = [ItemId.NONE, ItemId.NONE, ItemId.NONE]
var speed_boost_time_left: float = 0.0

# WORKSHOP TODO:
# Inventory and world pickups are split across PLAYER STATE and WORLD STATE.
# 1) Who owns slots? Server owns true inventory; clients display a copy.
# 2) Who may change? Client sends pickup/use REQUEST; server validates (exists, range, space, alive).
# 3) Who needs it? Owner UI + everyone if you show remote inventory; at minimum sync after change.
# 4) Late join? Send current slots + active speed/shield timers.
# Concept: two players grabbing the same pickup — only first valid server request wins (07).
# Change: request_pickup / request_use_item RPCs; server mutates and replicates.


func _process(delta: float) -> void:
	if speed_boost_time_left > 0.0:
		speed_boost_time_left = maxf(0.0, speed_boost_time_left - delta)
		speed_boost_changed.emit(speed_boost_time_left > 0.0, speed_boost_time_left)


func get_speed_multiplier() -> float:
	if speed_boost_time_left > 0.0:
		return SPEED_BOOST_MULTIPLIER
	return 1.0


func has_space() -> bool:
	return slots.has(ItemId.NONE)


func add_item(item_id: int) -> bool:
	if item_id == ItemId.NONE:
		return false
	for i in range(MAX_SLOTS):
		if slots[i] == ItemId.NONE:
			slots[i] = item_id
			inventory_changed.emit(slots.duplicate())
			return true
	return false


func use_slot(slot_index: int, health: HealthComponent) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	var item_id: int = slots[slot_index]
	if item_id == ItemId.NONE:
		return false
	if not _apply_item(item_id, health):
		return false
	slots[slot_index] = ItemId.NONE
	inventory_changed.emit(slots.duplicate())
	item_used.emit(slot_index, item_id)
	return true


func _apply_item(item_id: int, health: HealthComponent) -> bool:
	match item_id:
		ItemId.HEALTH_POTION:
			if health == null or not health.is_alive:
				return false
			health.heal(POTION_HEAL)
			return true
		ItemId.SPEED_BOOST:
			speed_boost_time_left = SPEED_BOOST_DURATION
			speed_boost_changed.emit(true, speed_boost_time_left)
			return true
		ItemId.SHIELD:
			if health == null or not health.is_alive:
				return false
			health.grant_shield()
			shield_changed.emit(true)
			return true
		_:
			return false


func clear_all() -> void:
	slots = [ItemId.NONE, ItemId.NONE, ItemId.NONE]
	speed_boost_time_left = 0.0
	inventory_changed.emit(slots.duplicate())
	speed_boost_changed.emit(false, 0.0)


static func item_name(item_id: int) -> String:
	match item_id:
		ItemId.HEALTH_POTION:
			return "Potion"
		ItemId.SPEED_BOOST:
			return "Speed"
		ItemId.SHIELD:
			return "Shield"
		_:
			return "Empty"
