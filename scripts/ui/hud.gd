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


func setup(arena: Node2D) -> void:
	_arena = arena
	Match.match_updated.connect(_refresh_match)
	Match.match_over.connect(_on_match_over)
	Network.connection_changed.connect(_on_net_status)
	restart_button.pressed.connect(_on_restart)
	menu_button.pressed.connect(_on_menu)
	match_over_panel.visible = false
	_refresh_match()
	_on_net_status(Network.status_text)
	call_deferred("_bind_local_player")


func _bind_local_player() -> void:
	var players := get_tree().get_nodes_in_group("players")
	for p in players:
		if p is CharacterBody2D and p.get("is_local_controlled"):
			_track_player(p)
			return
	# Fallback: first player
	if players.size() > 0:
		_track_player(players[0])


func _track_player(player: CharacterBody2D) -> void:
	_tracked_player = player
	var h: HealthComponent = player.get_node("Health")
	var inv: InventoryComponent = player.get_node("Inventory")
	var tag: TagComponent = player.get_node("Tag")
	h.health_changed.connect(_on_health)
	h.died.connect(func() -> void: power_label.text = "Power: DEAD")
	inv.inventory_changed.connect(_on_inventory)
	inv.speed_boost_changed.connect(_on_speed)
	tag.tag_changed.connect(func(is_it: bool) -> void:
		it_label.text = "YOU ARE IT" if is_it else "Not It"
		it_label.modulate = Color(1.0, 0.45, 0.2) if is_it else Color(0.8, 0.8, 0.8)
	)
	_on_health(h.health, h.max_health)
	_on_inventory(inv.slots)
	it_label.text = "YOU ARE IT" if tag.is_it else "Not It"


func _process(_delta: float) -> void:
	if _tracked_player == null:
		_bind_local_player()
		return
	var h: HealthComponent = _tracked_player.get_node_or_null("Health")
	if h and h.has_shield:
		if not power_label.text.begins_with("Power: Shield"):
			power_label.text = "Power: Shield"


func _on_health(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "HP %d / %d" % [current, maximum]


func _on_inventory(slots: Array) -> void:
	var parts: PackedStringArray = []
	for i in range(slots.size()):
		var name := InventoryComponent.item_name(int(slots[i]))
		parts.append("%d:%s" % [i + 1, name])
	inventory_label.text = "Inv  " + " | ".join(parts)


func _on_speed(active: bool, time_left: float) -> void:
	if active:
		power_label.text = "Power: Speed %.1fs" % time_left
	elif _tracked_player:
		var h: HealthComponent = _tracked_player.get_node("Health")
		power_label.text = "Power: Shield" if h.has_shield else "Power: —"


func _refresh_match() -> void:
	timer_label.text = "Time %d" % int(ceil(Match.match_time_remaining))
	var lines: PackedStringArray = []
	for peer_id in Match.player_scores.keys():
		lines.append("P%d: %d" % [int(peer_id), int(Match.player_scores[peer_id])])
	score_label.text = "Scores\n" + ("\n".join(lines) if lines.size() > 0 else "—")
	if not Match.match_started and Match.match_over_shown:
		pass


func _on_match_over(winner_peer_id: int, scores: Dictionary) -> void:
	match_over_panel.visible = true
	var score_bits: PackedStringArray = []
	for k in scores.keys():
		score_bits.append("P%s=%s" % [str(k), str(scores[k])])
	match_over_label.text = "Match Over!\nWinner: P%d\n%s" % [winner_peer_id, ", ".join(score_bits)]


func _on_net_status(text: String) -> void:
	status_label.text = "Net: %s | id %d" % [text, Network.local_peer_id]


func _on_restart() -> void:
	match_over_panel.visible = false
	if _arena and _arena.has_method("restart_from_ui"):
		_arena.restart_from_ui()


func _on_menu() -> void:
	Network.disconnect_game()
	Match.reset_match_data()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
