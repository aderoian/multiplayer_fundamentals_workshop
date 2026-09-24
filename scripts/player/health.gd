extends Node
class_name HealthComponent
## Player health — max_health, take_damage, death, respawn hooks.

signal health_changed(current: int, maximum: int)
signal died
signal respawned

const DEFAULT_MAX_HEALTH: int = 100

@export var max_health: int = DEFAULT_MAX_HEALTH
var health: int = DEFAULT_MAX_HEALTH
var is_alive: bool = true
var has_shield: bool = false

# WORKSHOP TODO:
# Health is PLAYER STATE, but damage must be server-authoritative in multiplayer.
# 1) Who owns this? Server owns the true health value.
# 2) Who may change it? Only the server should call take_damage / apply heals from items.
# 3) Who needs it? Every peer needs health for bars / death visuals.
# 4) Late join? Snapshot must include current health, alive flag, shield.
# Concept: never trust "Player B now has 20 health" from a client (checkpoint 06).
# Change: clients request or report contact; server validates and syncs health.


func _ready() -> void:
	health = max_health
	is_alive = true


func reset_full() -> void:
	health = max_health
	is_alive = true
	has_shield = false
	health_changed.emit(health, max_health)


func take_damage(amount: int) -> void:
	if not is_alive or amount <= 0:
		return
	if has_shield:
		has_shield = false
		health_changed.emit(health, max_health)
		return
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0:
		_die()


func heal(amount: int) -> void:
	if not is_alive:
		return
	health = mini(max_health, health + amount)
	health_changed.emit(health, max_health)


func grant_shield() -> void:
	has_shield = true
	health_changed.emit(health, max_health)


func _die() -> void:
	is_alive = false
	died.emit()


func mark_respawned() -> void:
	reset_full()
	respawned.emit()
