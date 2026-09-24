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
	camera.enabled = is_local_controlled
	Match.ensure_player_score(peer_id)
	if peer_id == Match.current_it_player:
		tag_comp.set_it(true)
	else:
		tag_comp.set_it(false)
	_update_visuals()
	_setup_applied = true

	# WORKSHOP TODO:
	# Input & camera are about AUTHORITY, not "who exists".
	# 1) Who owns input? The peer that owns this player (peer_id).
	# 2) Who may change position via keyboard? Only is_multiplayer_authority().
	# 3) Who needs position? Everyone (movement sync in checkpoint 04).
	# 4) Late join? Spawner/snapshot must create this node with correct authority.
	# Concept: set_multiplayer_authority(peer_id); only authority reads WASD (03).
	# Change: replace is_local_controlled checks with is_multiplayer_authority() once networked.
	# Until checkpoint 03, every machine may still read local input — intentional leftover.


func _physics_process(delta: float) -> void:
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

	if dir.length_squared() > 0.0:
		rotation = dir.angle()

	# WORKSHOP TODO:
	# Position is PLAYER STATE owned by the input authority.
	# After checkpoint 03 only the authority moves; without sync, remotes stand still.
	# Concept: MultiplayerSynchronizer or unreliable position RPC (checkpoint 04).
	# Note: remotes will look slightly late — prediction is out of scope for this workshop.


func _unhandled_input(event: InputEvent) -> void:
	if not _should_process_input():
		return
	if not health.is_alive:
		return
	if event.is_action_pressed("use_slot_1"):
		_try_use_item(0)
	elif event.is_action_pressed("use_slot_2"):
		_try_use_item(1)
	elif event.is_action_pressed("use_slot_3"):
		_try_use_item(2)


func _should_process_input() -> bool:
	if multiplayer.multiplayer_peer == null:
		return is_local_controlled
	# WORKSHOP TODO (checkpoint 03): return is_multiplayer_authority()
	return is_local_controlled


func _try_use_item(slot_index: int) -> void:
	inventory.use_slot(slot_index, health)


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
	# WORKSHOP TODO:
	# Online: do not set the other player's is_it from this client.
	# Send a tag REQUEST to the server; server validates and broadcasts the result (05).
	_attempt_tag_offline(body)


func _attempt_tag_offline(target: Node) -> void:
	if tag_comp.try_tag_local(target):
		Match.add_score(peer_id, 1)


func receive_tag_offline(from_peer_id: int) -> void:
	tag_comp.set_it(true)
	tag_comp.begin_cooldown()
	Match.set_current_it(peer_id)
	health.take_damage(Match.TAG_DAMAGE)
	print("[Tag] %s tagged by peer %d" % [display_name, from_peer_id])


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


func _on_died() -> void:
	visible = true
	modulate = Color(1, 1, 1, 0.35)
	velocity = Vector2.ZERO
	_respawn_timer = RESPAWN_DELAY
	# WORKSHOP TODO (06): death/respawn must be server-authoritative and replicated.


func _on_respawned() -> void:
	modulate = Color(1, 1, 1, 1)
	_update_visuals()


func _do_respawn() -> void:
	var points := get_tree().get_nodes_in_group("respawn_points")
	if points.size() > 0:
		var idx: int = abs(peer_id) % points.size()
		global_position = (points[idx] as Node2D).global_position
	health.mark_respawned()


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
