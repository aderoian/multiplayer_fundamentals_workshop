extends CharacterBody2D
## Top-down player: movement, camera, tag contact, inventory use, death/respawn.

const MOVE_SPEED: float = 220.0
const SPRINT_SPEED: float = 340.0
const RESPAWN_DELAY: float = 3.0

@onready var body_poly: Polygon2D = $Body
@onready var it_label: Label = $ItLabel
@onready var camera: Camera2D = $Camera2D
@onready var health: HealthComponent = $Health
@onready var inventory: InventoryComponent = $Inventory
@onready var tag_comp: TagComponent = $Tag
@onready var health_bar: ProgressBar = $HealthBar
@onready var name_label: Label = $NameLabel
@onready var overlap_area: Area2D = $OverlapArea

var peer_id: int = 1
var display_name: String = "Player"
var is_local_controlled: bool = true
var _respawn_timer: float = -1.0
var _base_color: Color = Color(0.2, 0.55, 0.95)
var _setup_applied: bool = false


func _ready() -> void:
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	health.respawned.connect(_on_respawned)
	tag_comp.tag_changed.connect(_on_tag_changed)
	inventory.inventory_changed.connect(_on_inventory_changed)
	inventory.speed_boost_changed.connect(_on_speed_boost_changed)
	overlap_area.body_entered.connect(_on_body_entered)
	_on_health_changed(health.health, health.max_health)
	_apply_setup()


func setup_player(p_peer_id: int, p_name: String, p_local: bool) -> void:
	## Safe to call before the node enters the tree (MultiplayerSpawner spawn_function).
	peer_id = p_peer_id
	display_name = p_name
	is_local_controlled = p_local
	_base_color = _color_for_peer(peer_id)
	if is_node_ready():
		_apply_setup()


func _apply_setup() -> void:
	if tag_comp == null:
		return
	tag_comp.peer_id = peer_id
	name_label.text = display_name
	# The Player node exists on every machine; only the authority reads WASD / owns the camera.
	if multiplayer.multiplayer_peer != null:
		set_multiplayer_authority(peer_id)
	camera.enabled = _should_process_input()
	Match.ensure_player_score(peer_id)
	if peer_id == Match.current_it_player:
		tag_comp.set_it(true)
	else:
		tag_comp.set_it(false)
	_update_visuals()
	_setup_applied = true

	# Ownership (input/camera):
	# 1) Who owns this? The peer with peer_id (set_multiplayer_authority).
	# 2) Who may change? Only is_multiplayer_authority() reads keyboard.
	# 3) Who needs it? Position must reach everyone (movement sync ΓÇö checkpoint 04).
	# 4) Late join? Spawner sets authority when the instance is created.


func _physics_process(delta: float) -> void:
	# Top-down: never rotate the body to face movement.
	rotation = 0.0

	if _respawn_timer >= 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn_timer = -1.0
			_do_respawn()
		return

	if not health.is_alive:
		velocity = Vector2.ZERO
		return

	if not _should_process_input():
		return

	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	dir = dir.normalized()

	var speed: float = MOVE_SPEED
	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	speed *= inventory.get_speed_multiplier()
	velocity = dir * speed
	move_and_slide()

	_broadcast_transform()

	# Position sync: authority sends transform (unreliable). MultiplayerSynchronizer also
	# replicates for spawner-created peers. Remotes look slightly late — prediction is out of scope.
	# Top-down: do not rotate the body to face movement (rotation stays 0).


func _broadcast_transform() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not is_multiplayer_authority():
		return
	rotation = 0.0
	rpc_set_transform.rpc(global_position, 0.0)


@rpc("any_peer", "unreliable_ordered", "call_remote")
func rpc_set_transform(pos: Vector2, _rot: float) -> void:
	## Apply authority position on remotes. Rotation stays fixed (top-down).
	if is_multiplayer_authority():
		return
	global_position = pos
	rotation = 0.0


func force_set_transform(pos: Vector2) -> void:
	## Test / teleport helper for the authority (or server placing bodies).
	global_position = pos
	position = pos
	rotation = 0.0
	if multiplayer.multiplayer_peer != null and is_multiplayer_authority():
		rpc_set_transform.rpc(pos, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not _should_process_input():
		return
	if not _can_use_items():
		return
	if event.is_action_pressed("use_slot_1"):
		_try_use_item(0)
	elif event.is_action_pressed("use_slot_2"):
		_try_use_item(1)
	elif event.is_action_pressed("use_slot_3"):
		_try_use_item(2)


func _can_use_items() -> bool:
	## Dead or waiting to respawn cannot use inventory. Cleared on respawn.
	if _respawn_timer >= 0.0:
		return false
	if health == null or not health.is_alive:
		return false
	return true


func _should_process_input() -> bool:
	# Offline (no peer): Godot treats us as server id 1 ΓÇö use local control flag.
	if multiplayer.multiplayer_peer == null:
		return is_local_controlled
	# Online: only the authority machine reads keyboard for this Player instance.
	return is_multiplayer_authority()


func _try_use_item(slot_index: int) -> void:
	if not _can_use_items():
		return
	if multiplayer.multiplayer_peer == null:
		inventory.use_slot(slot_index, health)
		return
	if not is_multiplayer_authority():
		return
	_send_use_item(slot_index)


func _send_use_item(slot_index: int) -> void:
	# Host cannot rpc_id(1) to itself with any_peer mode — call the handler directly.
	if multiplayer.is_server():
		_server_use_item(multiplayer.get_unique_id(), slot_index)
	else:
		request_use_item.rpc_id(1, slot_index)


func request_pickup_from_world(pickup: Node) -> void:
	if multiplayer.multiplayer_peer == null:
		collect_pickup_offline(pickup)
		return
	if not is_multiplayer_authority():
		return
	if pickup == null or not is_instance_valid(pickup):
		return
	var net_id: int = int(pickup.get("pickup_net_id"))
	_send_pickup_request(net_id)


func _send_pickup_request(pickup_net_id: int) -> void:
	if multiplayer.is_server():
		_server_pickup(multiplayer.get_unique_id(), pickup_net_id)
	else:
		request_pickup.rpc_id(1, pickup_net_id)


@rpc("any_peer", "reliable")
func request_pickup(pickup_net_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_server_pickup(sender, pickup_net_id)


func _server_pickup(sender: int, pickup_net_id: int) -> void:
	if sender != peer_id:
		return
	if not health.is_alive or not inventory.has_space():
		return
	var pickup: Node = _find_pickup(pickup_net_id)
	if pickup == null:
		return
	if global_position.distance_to((pickup as Node2D).global_position) > WorldPickup.PICKUP_RANGE:
		return
	var item_id: int = int(pickup.call("get_item_id"))
	if not inventory.add_item(item_id):
		return
	# Consume first — second requester finds pickup gone.
	pickup.queue_free()
	rpc_sync_inventory.rpc(inventory.slots.duplicate())
	# Broadcast via Match autoload so every peer removes it (stable node path).
	Match.rpc_remove_world_pickup.rpc(pickup_net_id)


@rpc("any_peer", "reliable")
func request_use_item(slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_server_use_item(sender, slot_index)


func _server_use_item(sender: int, slot_index: int) -> void:
	if sender != peer_id:
		return
	if not health.is_alive:
		return
	if not inventory.use_slot(slot_index, health):
		return
	rpc_sync_inventory.rpc(inventory.slots.duplicate())
	_sync_health_to_peers()
	rpc_sync_powerups.rpc(inventory.speed_boost_time_left, health.has_shield)


@rpc("any_peer", "call_local", "reliable")
func rpc_sync_inventory(slots: Array) -> void:
	for i in range(mini(slots.size(), InventoryComponent.MAX_SLOTS)):
		inventory.slots[i] = int(slots[i])
	inventory.inventory_changed.emit(inventory.slots.duplicate())


@rpc("any_peer", "call_remote", "reliable")
func rpc_sync_powerups(speed_left: float, shield: bool) -> void:
	inventory.speed_boost_time_left = speed_left
	inventory.speed_boost_changed.emit(speed_left > 0.0, speed_left)
	health.has_shield = shield
	health.health_changed.emit(health.health, health.max_health)


## Deprecated path kept for clarity — prefer Match.rpc_remove_world_pickup.
@rpc("any_peer", "call_local", "reliable")
func rpc_remove_pickup(pickup_net_id: int) -> void:
	Match.rpc_remove_world_pickup(pickup_net_id)


func _find_pickup(pickup_net_id: int) -> Node:
	for n in get_tree().get_nodes_in_group("pickups"):
		if int(n.get("pickup_net_id")) == pickup_net_id:
			return n
	return null


func _on_body_entered(body: Node) -> void:
	if body == self:
		return
	if not (body is CharacterBody2D):
		return
	if not tag_comp.is_it:
		return
	if not health.is_alive:
		return
	if multiplayer.multiplayer_peer == null:
		_attempt_tag_offline(body)
		return
	# Online: only the authority that is It sends a REQUEST; server validates.
	if not is_multiplayer_authority():
		return
	var target_id: int = int(body.get("peer_id"))
	_send_tag_request(target_id)


func _send_tag_request(target_id: int) -> void:
	# Host cannot use rpc_id(1) on itself with any_peer RPCs ΓÇö call handler directly.
	if multiplayer.is_server():
		_server_handle_tag(multiplayer.get_unique_id(), target_id)
	else:
		request_tag.rpc_id(1, target_id)


func _attempt_tag_offline(target: Node) -> void:
	if tag_comp.try_tag_local(target):
		Match.add_score(peer_id, 1)


func receive_tag_offline(from_peer_id: int) -> void:
	tag_comp.set_it(true)
	tag_comp.begin_cooldown()
	Match.set_current_it(peer_id)
	# Damage stays local offline; checkpoint 06 makes health server-authoritative online.
	health.take_damage(Match.TAG_DAMAGE)
	print("[Tag] %s tagged by peer %d" % [display_name, from_peer_id])


@rpc("any_peer", "reliable")
func request_tag(target_peer_id: int) -> void:
	## Client ΓåÆ server: ask to transfer It to target_peer_id.
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_server_handle_tag(sender, target_peer_id)


func _server_handle_tag(tagger_id: int, target_id: int) -> void:
	if not _server_validate_tag(tagger_id, target_id):
		return
	_server_apply_tag(tagger_id, target_id)


func _server_validate_tag(tagger_id: int, target_id: int) -> bool:
	if Match.current_it_player != tagger_id:
		return false
	var tagger: CharacterBody2D = _find_player(tagger_id)
	var target: CharacterBody2D = _find_player(target_id)
	if tagger == null or target == null:
		return false
	var t_health: HealthComponent = tagger.get_node("Health") as HealthComponent
	var o_health: HealthComponent = target.get_node("Health") as HealthComponent
	if not t_health.is_alive or not o_health.is_alive:
		return false
	var t_tag: TagComponent = tagger.get_node("Tag") as TagComponent
	if not t_tag.can_tag_now():
		return false
	if tagger.global_position.distance_to(target.global_position) > TagComponent.TAG_RANGE:
		return false
	return true


func _server_apply_tag(tagger_id: int, target_id: int) -> void:
	Match.add_score(tagger_id, 1) # replicates scores to all peers (08)
	Match.rpc_apply_tag_result.rpc(tagger_id, target_id)


func on_tagged_by_network(from_peer_id: int) -> void:
	## Runs on all peers after tag result. Only the server mutates health, then syncs.
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		health.take_damage(Match.TAG_DAMAGE)
		_sync_health_to_peers()
	print("[Tag] %s tagged by peer %d" % [display_name, from_peer_id])


func _sync_health_to_peers() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.is_server():
		return
	# any_peer: server must be allowed to push state on client-owned player nodes.
	rpc_sync_health.rpc(health.health, health.is_alive, health.has_shield, global_position)


@rpc("any_peer", "call_remote", "reliable")
func rpc_sync_health(p_health: int, p_alive: bool, p_shield: bool, p_pos: Vector2) -> void:
	## Server → clients: display server health; clients never invent HP.
	if p_alive:
		_respawn_timer = -1.0
	health.apply_replica(p_health, p_alive, p_shield)
	global_position = p_pos
	rotation = 0.0
	if not p_alive:
		modulate = Color(1, 1, 1, 0.35)
	else:
		modulate = Color(1, 1, 1, 1)
	_update_visuals()


func collect_pickup_offline(pickup: Node) -> bool:
	if not health.is_alive:
		return false
	if not inventory.has_space():
		return false
	if pickup == null or not pickup.has_method("get_item_id"):
		return false
	var item_id: int = int(pickup.call("get_item_id"))
	if inventory.add_item(item_id):
		pickup.queue_free()
		return true
	return false


func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


func _find_player(p_id: int) -> CharacterBody2D:
	for n in get_tree().get_nodes_in_group("players"):
		if n is CharacterBody2D and int(n.get("peer_id")) == p_id:
			return n as CharacterBody2D
	return null


func _on_died() -> void:
	visible = true
	modulate = Color(1, 1, 1, 0.35)
	velocity = Vector2.ZERO
	# Only the server (or offline) starts the respawn timer.
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		_respawn_timer = RESPAWN_DELAY


func _on_respawned() -> void:
	_respawn_timer = -1.0
	modulate = Color(1, 1, 1, 1)
	rotation = 0.0
	_update_visuals()


func _do_respawn() -> void:
	## Server / offline respawn; then replicate.
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	_apply_respawn_state(_pick_respawn_position())
	_sync_health_to_peers()
	rpc_notify_respawn.rpc(global_position)


func _pick_respawn_position() -> Vector2:
	var points := get_tree().get_nodes_in_group("respawn_points")
	if points.size() > 0:
		var idx: int = abs(peer_id) % points.size()
		return (points[idx] as Node2D).global_position
	return global_position


func _apply_respawn_state(p_pos: Vector2) -> void:
	## Clears death gates so movement, pickup, and item use work again.
	_respawn_timer = -1.0
	global_position = p_pos
	rotation = 0.0
	modulate = Color(1, 1, 1, 1)
	health.mark_respawned()
	_update_visuals()


@rpc("any_peer", "call_remote", "reliable")
func rpc_notify_respawn(p_pos: Vector2) -> void:
	_respawn_timer = -1.0
	global_position = p_pos
	rotation = 0.0
	modulate = Color(1, 1, 1, 1)
	health.apply_replica(health.max_health, true, false)
	_update_visuals()


func reset_for_new_match(as_it: bool, spawn_pos: Vector2) -> void:
	## In-place match restart — keep the node, reset gameplay state.
	_respawn_timer = -1.0
	velocity = Vector2.ZERO
	tag_comp.begin_cooldown_sec(2.0)
	global_position = spawn_pos
	rotation = 0.0
	modulate = Color(1, 1, 1, 1)
	health.reset_full()
	inventory.clear_all()
	tag_comp.set_it(as_it)
	_update_visuals()
	health.health_changed.emit(health.health, health.max_health)
	inventory.inventory_changed.emit(inventory.slots.duplicate())
	inventory.speed_boost_changed.emit(false, 0.0)


func _on_tag_changed(_is_it: bool) -> void:
	_update_visuals()


func _on_inventory_changed(_slots: Array) -> void:
	pass


func _on_speed_boost_changed(_active: bool, _time_left: float) -> void:
	pass


func _update_visuals() -> void:
	if tag_comp == null:
		return
	if tag_comp.is_it:
		body_poly.color = Color(0.95, 0.35, 0.1)
		it_label.visible = true
	else:
		body_poly.color = _base_color
		it_label.visible = false


func _color_for_peer(id: int) -> Color:
	var palette: Array[Color] = [
		Color(0.2, 0.55, 0.95),
		Color(0.2, 0.8, 0.45),
		Color(0.85, 0.3, 0.75),
		Color(0.95, 0.8, 0.2),
		Color(0.4, 0.9, 0.9),
		Color(0.7, 0.5, 0.2),
	]
	return palette[abs(id) % palette.size()]


func build_state_snapshot() -> Dictionary:
	return {
		"peer_id": peer_id,
		"name": display_name,
		"pos": global_position,
		"rot": rotation,
		"is_it": tag_comp.is_it,
		"health": health.health,
		"alive": health.is_alive,
		"shield": health.has_shield,
		"slots": inventory.slots.duplicate(),
		"speed_left": inventory.speed_boost_time_left,
	}


func apply_state_snapshot(data: Dictionary) -> void:
	## Late join: apply a full copy of this player's current state.
	global_position = data.get("pos", global_position)
	rotation = 0.0
	display_name = str(data.get("name", display_name))
	if name_label:
		name_label.text = display_name
	tag_comp.set_it(bool(data.get("is_it", false)))
	_respawn_timer = -1.0
	health.apply_replica(int(data.get("health", 100)), bool(data.get("alive", true)), bool(data.get("shield", false)))
	var slots: Array = data.get("slots", [])
	for i in range(mini(slots.size(), InventoryComponent.MAX_SLOTS)):
		inventory.slots[i] = int(slots[i])
	inventory.inventory_changed.emit(inventory.slots.duplicate())
	inventory.speed_boost_time_left = float(data.get("speed_left", 0.0))
	inventory.speed_boost_changed.emit(inventory.speed_boost_time_left > 0.0, inventory.speed_boost_time_left)
	if not health.is_alive:
		modulate = Color(1, 1, 1, 0.35)
	else:
		modulate = Color(1, 1, 1, 1)
	_update_visuals()
