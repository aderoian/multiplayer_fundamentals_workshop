extends CanvasLayer
## In-game HUD: health, inventory, IT, score, timer, match-over.

@onready var health_bar: ProgressBar = $Root/TopLeft/HealthBar
@onready var health_label: Label = $Root/TopLeft/HealthLabel
@onready var inventory_label: Label = $Root/TopLeft/InventoryLabel
@onready var power_label: Label = $Root/TopLeft/PowerLabel
@onready var it_label: Label = $Root/TopRight/ItLabel
@onready var score_label: Label = $Root/TopRight/ScoreLabel
@onready var timer_label: Label = $Root/TopRight/TimerLabel
@onready var status_label: Label = $Root/TopRight/NetStatus
@onready var match_over_panel: PanelContainer = $Root/MatchOver
@onready var match_over_label: Label = $Root/MatchOver/VBox/ResultLabel
@onready var restart_button: Button = $Root/MatchOver/VBox/RestartButton
@onready var menu_button: Button = $Root/MatchOver/VBox/MenuButton

var _arena: Node2D
var _tracked_player: CharacterBody2D
var _bound_peer_id: int = -1


func setup(arena: Node2D) -> void:
	_arena = arena
	if not Match.match_updated.is_connected(_refresh_match):
		Match.match_updated.connect(_refresh_match)
	if not Match.match_over.is_connected(_on_match_over):
		Match.match_over.connect(_on_match_over)
	if not Match.match_started_signal.is_connected(_on_match_started):
		Match.match_started_signal.connect(_on_match_started)
	if not Network.connection_changed.is_connected(_on_net_status):
		Network.connection_changed.connect(_on_net_status)
	if not restart_button.pressed.is_connected(_on_restart):
		restart_button.pressed.connect(_on_restart)
	if not menu_button.pressed.is_connected(_on_menu):
		menu_button.pressed.connect(_on_menu)
	match_over_panel.visible = false
	_update_restart_button_visibility()
	_refresh_match()
	_on_net_status(Network.status_text)
	call_deferred("_bind_local_player")


func _update_restart_button_visibility() -> void:
	# Offline always may restart. Online: only the host/server.
	var can_restart: bool = multiplayer.multiplayer_peer == null or multiplayer.is_server()
	restart_button.visible = can_restart
	restart_button.disabled = not can_restart


func _local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()


func _bind_local_player() -> void:
	var want_id: int = _local_peer_id()
	var players := get_tree().get_nodes_in_group("players")
	for p in players:
		if not (p is CharacterBody2D):
			continue
		# Prefer local-controlled / matching peer when present.
		if bool(p.get("is_local_controlled")) or int(p.get("peer_id")) == want_id:
			_track_player(p as CharacterBody2D)
			return
	# Offline starter: single local player — safe fallback.
	if multiplayer.multiplayer_peer == null and players.size() > 0:
		_track_player(players[0] as CharacterBody2D)


func _track_player(player: CharacterBody2D) -> void:
	if _tracked_player == player and _bound_peer_id == int(player.get("peer_id")):
		_pull_player_state()
		return
	_disconnect_tracked_signals()
	_tracked_player = player
	_bound_peer_id = int(player.get("peer_id"))
	var h: HealthComponent = player.get_node("Health")
	var inv: InventoryComponent = player.get_node("Inventory")
	var tag: TagComponent = player.get_node("Tag")
	h.health_changed.connect(_on_health)
	h.died.connect(_on_local_died)
	h.respawned.connect(_on_local_respawned)
	inv.inventory_changed.connect(_on_inventory)
	inv.speed_boost_changed.connect(_on_speed)
	if inv.has_signal("shield_changed"):
		inv.shield_changed.connect(_on_shield_signal)
	tag.tag_changed.connect(_on_local_tag)
	_pull_player_state()


func _disconnect_tracked_signals() -> void:
	if _tracked_player == null or not is_instance_valid(_tracked_player):
		return
	var h: HealthComponent = _tracked_player.get_node_or_null("Health") as HealthComponent
	var inv: InventoryComponent = _tracked_player.get_node_or_null("Inventory") as InventoryComponent
	var tag: TagComponent = _tracked_player.get_node_or_null("Tag") as TagComponent
	if h:
		if h.health_changed.is_connected(_on_health):
			h.health_changed.disconnect(_on_health)
		if h.died.is_connected(_on_local_died):
			h.died.disconnect(_on_local_died)
		if h.respawned.is_connected(_on_local_respawned):
			h.respawned.disconnect(_on_local_respawned)
	if inv:
		if inv.inventory_changed.is_connected(_on_inventory):
			inv.inventory_changed.disconnect(_on_inventory)
		if inv.speed_boost_changed.is_connected(_on_speed):
			inv.speed_boost_changed.disconnect(_on_speed)
		if inv.has_signal("shield_changed") and inv.shield_changed.is_connected(_on_shield_signal):
			inv.shield_changed.disconnect(_on_shield_signal)
	if tag and tag.tag_changed.is_connected(_on_local_tag):
		tag.tag_changed.disconnect(_on_local_tag)


func _pull_player_state() -> void:
	if _tracked_player == null or not is_instance_valid(_tracked_player):
		return
	var h: HealthComponent = _tracked_player.get_node_or_null("Health") as HealthComponent
	var inv: InventoryComponent = _tracked_player.get_node_or_null("Inventory") as InventoryComponent
	var tag: TagComponent = _tracked_player.get_node_or_null("Tag") as TagComponent
	if h:
		_on_health(h.health, h.max_health)
		if not h.is_alive:
			power_label.text = "Power: DEAD"
		else:
			_refresh_power_label(h, inv)
	if inv:
		_on_inventory(inv.slots)
	if tag:
		_on_local_tag(tag.is_it)


func _refresh_power_label(h: HealthComponent, inv: InventoryComponent) -> void:
	if h == null or not h.is_alive:
		power_label.text = "Power: DEAD"
		return
	if inv and inv.speed_boost_time_left > 0.0:
		power_label.text = "Power: Speed %.1fs" % inv.speed_boost_time_left
	elif h.has_shield:
		power_label.text = "Power: Shield"
	else:
		power_label.text = "Power: —"


func _process(_delta: float) -> void:
	_update_restart_button_visibility()
	if _tracked_player == null or not is_instance_valid(_tracked_player):
		_bind_local_player()
		return
	var h: HealthComponent = _tracked_player.get_node_or_null("Health") as HealthComponent
	var inv: InventoryComponent = _tracked_player.get_node_or_null("Inventory") as InventoryComponent
	if h and inv and h.is_alive and inv.speed_boost_time_left > 0.0:
		power_label.text = "Power: Speed %.1fs" % inv.speed_boost_time_left


func _on_health(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "HP %d / %d" % [current, maximum]
	if _tracked_player:
		var h: HealthComponent = _tracked_player.get_node_or_null("Health") as HealthComponent
		var inv: InventoryComponent = _tracked_player.get_node_or_null("Inventory") as InventoryComponent
		if h and not h.is_alive:
			power_label.text = "Power: DEAD"
		elif h:
			_refresh_power_label(h, inv)


func _on_local_died() -> void:
	power_label.text = "Power: DEAD"
	_pull_player_state()


func _on_local_respawned() -> void:
	_pull_player_state()


func _on_local_tag(is_it: bool) -> void:
	it_label.text = "YOU ARE IT" if is_it else "Not It"
	it_label.modulate = Color(1.0, 0.45, 0.2) if is_it else Color(0.8, 0.8, 0.8)


func _on_inventory(slots: Array) -> void:
	var parts: PackedStringArray = []
	for i in range(slots.size()):
		var slot_name := InventoryComponent.item_name(int(slots[i]))
		parts.append("%d:%s" % [i + 1, slot_name])
	inventory_label.text = "Inv  " + " | ".join(parts)


func _on_speed(active: bool, time_left: float) -> void:
	if active:
		power_label.text = "Power: Speed %.1fs" % time_left
	elif _tracked_player:
		var h: HealthComponent = _tracked_player.get_node_or_null("Health") as HealthComponent
		var inv: InventoryComponent = _tracked_player.get_node_or_null("Inventory") as InventoryComponent
		_refresh_power_label(h, inv)


func _on_shield_signal(_active: bool) -> void:
	if _tracked_player:
		var h: HealthComponent = _tracked_player.get_node_or_null("Health") as HealthComponent
		var inv: InventoryComponent = _tracked_player.get_node_or_null("Inventory") as InventoryComponent
		_refresh_power_label(h, inv)


func _refresh_match() -> void:
	timer_label.text = "Time %d" % int(ceil(Match.match_time_remaining))
	var lines: PackedStringArray = []
	var keys: Array = Match.player_scores.keys()
	keys.sort()
	for peer_id in keys:
		lines.append("P%d: %d" % [int(peer_id), int(Match.player_scores[peer_id])])
	score_label.text = "Scores\n" + ("\n".join(lines) if lines.size() > 0 else "—")
	_pull_player_state()
	if Match.match_over_shown:
		match_over_panel.visible = true
	elif Match.match_started:
		match_over_panel.visible = false


func _on_match_started() -> void:
	match_over_panel.visible = false
	_update_restart_button_visibility()
	_pull_player_state()
	_refresh_match()


func _on_match_over(winner_peer_id: int, scores: Dictionary) -> void:
	match_over_panel.visible = true
	_update_restart_button_visibility()
	var score_bits: PackedStringArray = []
	var keys: Array = scores.keys()
	keys.sort()
	for k in keys:
		score_bits.append("P%s=%s" % [str(k), str(scores[k])])
	match_over_label.text = "Match Over!\nWinner: P%d\n%s" % [winner_peer_id, ", ".join(score_bits)]


func _on_net_status(text: String) -> void:
	status_label.text = "Net: %s | id %d" % [text, Network.local_peer_id]
	_update_restart_button_visibility()


func _on_restart() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	match_over_panel.visible = false
	if _arena and _arena.has_method("restart_from_ui"):
		_arena.restart_from_ui()


func _on_menu() -> void:
	Network.disconnect_game()
	Match.reset_match_data()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
