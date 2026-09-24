extends Node
class_name HealthComponent
## Player health — server owns the true value online; clients display replicas.

signal health_changed(current: int, maximum: int)
signal died
signal respawned

const DEFAULT_MAX_HEALTH: int = 100

@export var max_health: int = DEFAULT_MAX_HEALTH
var health: int = DEFAULT_MAX_HEALTH
var is_alive: bool = true
var has_shield: bool = false

# Ownership (health):
# 1) Who owns this? Server owns true health / shield / alive.
# 2) Who may change? Only the server applies take_damage / heals from validated actions.
# 3) Who needs it? Everyone (bars, death visuals).
# 4) Late join? Snapshot health, alive, shield.
# Why clients must not say "Player B has 20 HP": a cheater could wipe anyone.


func _ready() -> void:
	health = max_health
	is_alive = true


func reset_full() -> void:
	health = max_health
	is_alive = true
	has_shield = false
	health_changed.emit(health, max_health)


func take_damage(amount: int) -> void:
	## Call only from server (or offline). Applies shield, then HP, may emit died.
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


func apply_replica(p_health: int, p_alive: bool, p_shield: bool) -> void:
	## Client-side mirror of server state (no authority to invent values).
	var was_alive: bool = is_alive
	health = p_health
	is_alive = p_alive
	has_shield = p_shield
	health_changed.emit(health, max_health)
	if was_alive and not is_alive:
		died.emit()
	elif not was_alive and is_alive:
		respawned.emit()


func _die() -> void:
	is_alive = false
	died.emit()


func mark_respawned() -> void:
	reset_full()
	respawned.emit()


func to_snapshot() -> Dictionary:
	return {
		"health": health,
		"alive": is_alive,
		"shield": has_shield,
	}
