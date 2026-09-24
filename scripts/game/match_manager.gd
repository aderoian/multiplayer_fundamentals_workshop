extends Node
## MatchManager — MATCH STATE (timer, scores, started, current It).
##
## Distinct from:
## - Player state: position, health, inventory, is_it
## - World state: remaining pickups / spawned objects
##
## Ownership:
## 1) Who owns this? Server (or offline local).
## 2) Who may change? Server awards scores / ticks timer / ends match.
## 3) Who needs it? Every peer (same clock and scoreboard).
## 4) Late join? Snapshot time, scores, started, current It (checkpoint 09).

signal match_updated
signal match_started_signal
signal match_over(winner_peer_id: int, scores: Dictionary)
signal it_changed(new_it_peer_id: int)

const MATCH_DURATION_SEC: float = 120.0
const TAG_DAMAGE: int = 25
const SYNC_INTERVAL: float = 0.5

var match_started: bool = false
var match_time_remaining: float = MATCH_DURATION_SEC
var player_scores: Dictionary = {} ## peer_id -> int
var current_it_player: int = 1 ## host is It at match start
var match_over_shown: bool = false
var _sync_accum: float = 0.0


func _ready() -> void:
	reset_match_data()


func _process(delta: float) -> void:
	if not match_started or match_over_shown:
		return
	if not _should_tick_timer_locally():
		return
	match_time_remaining = maxf(0.0, match_time_remaining - delta)
	match_updated.emit()
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_sync_accum += delta
		if _sync_accum >= SYNC_INTERVAL:
			_sync_accum = 0.0
			_replicate_match_state()
	if match_time_remaining <= 0.0:
		_end_match()


func _should_tick_timer_locally() -> bool:
	# Offline: no peer → tick locally. Online: ONLY the server ticks.
	if multiplayer.multiplayer_peer == null:
		return true
	return multiplayer.is_server()


func reset_match_data() -> void:
	match_started = false
	match_time_remaining = MATCH_DURATION_SEC
	player_scores.clear()
	current_it_player = 1
	match_over_shown = false
	_sync_accum = 0.0
	match_updated.emit()


func start_match(initial_it_peer_id: int = 1) -> void:
	match_started = true
	match_time_remaining = MATCH_DURATION_SEC
	match_over_shown = false
	current_it_player = initial_it_peer_id
	if not player_scores.has(initial_it_peer_id):
		player_scores[initial_it_peer_id] = 0
	match_started_signal.emit()
	it_changed.emit(current_it_player)
	match_updated.emit()
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_match_started.rpc(initial_it_peer_id, match_time_remaining, player_scores.duplicate())


func ensure_player_score(peer_id: int) -> void:
	if not player_scores.has(peer_id):
		player_scores[peer_id] = 0
		match_updated.emit()
		_replicate_scores()


func remove_player_score(peer_id: int) -> void:
	player_scores.erase(peer_id)
	match_updated.emit()
	_replicate_scores()


func add_score(peer_id: int, amount: int = 1) -> void:
	ensure_player_score(peer_id)
	player_scores[peer_id] = int(player_scores[peer_id]) + amount
	match_updated.emit()
	_replicate_scores()


func set_current_it(peer_id: int) -> void:
	current_it_player = peer_id
	ensure_player_score(peer_id)
	it_changed.emit(peer_id)
	match_updated.emit()


func get_winner_peer_id() -> int:
	var best_id: int = -1
	var best_score: int = -1
	for peer_id in player_scores.keys():
		var s: int = int(player_scores[peer_id])
		if s > best_score:
			best_score = s
			best_id = int(peer_id)
	return best_id


func _end_match() -> void:
	if match_over_shown:
		return
	match_over_shown = true
	match_started = false
	var winner: int = get_winner_peer_id()
	match_over.emit(winner, player_scores.duplicate())
	match_updated.emit()
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_match_over.rpc(winner, player_scores.duplicate())


func restart_match(initial_it_peer_id: int = 1) -> void:
	var kept_ids: Array = player_scores.keys()
	player_scores.clear()
	for id in kept_ids:
		player_scores[id] = 0
	start_match(initial_it_peer_id)


func _replicate_scores() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.is_server():
		return
	rpc_sync_scores.rpc(player_scores.duplicate(), current_it_player)


func _replicate_match_state() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	rpc_sync_timer.rpc(match_time_remaining, match_started, match_over_shown)


@rpc("authority", "call_remote", "reliable")
func rpc_match_started(initial_it: int, time_left: float, scores: Dictionary) -> void:
	match_started = true
	match_over_shown = false
	match_time_remaining = time_left
	current_it_player = initial_it
	player_scores = scores.duplicate()
	match_started_signal.emit()
	it_changed.emit(current_it_player)
	match_updated.emit()


@rpc("authority", "call_remote", "reliable")
func rpc_sync_timer(time_left: float, started: bool, over: bool) -> void:
	match_time_remaining = time_left
	match_started = started
	match_over_shown = over
	match_updated.emit()


@rpc("authority", "call_remote", "reliable")
func rpc_sync_scores(scores: Dictionary, it_id: int) -> void:
	player_scores = scores.duplicate()
	current_it_player = it_id
	match_updated.emit()
	it_changed.emit(it_id)


@rpc("authority", "call_remote", "reliable")
func rpc_match_over(winner: int, scores: Dictionary) -> void:
	match_over_shown = true
	match_started = false
	player_scores = scores.duplicate()
	match_over.emit(winner, scores)
	match_updated.emit()


@rpc("authority", "call_local", "reliable")
func rpc_apply_tag_result(tagger_id: int, target_id: int) -> void:
	## Server broadcasts a validated tag transfer.
	current_it_player = target_id
	it_changed.emit(target_id)
	match_updated.emit()
	for n in get_tree().get_nodes_in_group("players"):
		if not (n is CharacterBody2D):
			continue
		var pid: int = int(n.get("peer_id"))
		var tag: TagComponent = n.get_node("Tag") as TagComponent
		if pid == target_id:
			tag.set_it(true)
			tag.begin_cooldown()
		elif pid == tagger_id:
			tag.set_it(false)
			tag.begin_cooldown()
		else:
			tag.set_it(false)
	var target: Node = null
	for n in get_tree().get_nodes_in_group("players"):
		if int(n.get("peer_id")) == target_id:
			target = n
			break
	if target and target.has_method("on_tagged_by_network"):
		target.call("on_tagged_by_network", tagger_id)
	print("[Match] tag result %d -> %d" % [tagger_id, target_id])


func to_snapshot() -> Dictionary:
	## Used by late-join (09).
	return {
		"time": match_time_remaining,
		"started": match_started,
		"over": match_over_shown,
		"scores": player_scores.duplicate(),
		"it": current_it_player,
	}


func apply_snapshot(data: Dictionary) -> void:
	match_time_remaining = float(data.get("time", MATCH_DURATION_SEC))
	match_started = bool(data.get("started", false))
	match_over_shown = bool(data.get("over", false))
	player_scores = Dictionary(data.get("scores", {})).duplicate()
	current_it_player = int(data.get("it", 1))
	match_updated.emit()
	it_changed.emit(current_it_player)
	if match_over_shown:
		match_over.emit(get_winner_peer_id(), player_scores.duplicate())


@rpc("authority", "call_remote", "reliable")
func rpc_late_join_snapshot(match_data: Dictionary, players_data: Array, pickups_data: Array) -> void:
	## Synchronizing *changes* is not enough — late joiners need a full snapshot.
	apply_snapshot(match_data)
	# Rebuild world pickups from server list.
	var arena := get_tree().get_first_node_in_group("arena")
	if arena and arena.has_method("apply_pickup_snapshot"):
		arena.call("apply_pickup_snapshot", pickups_data)
	for entry in players_data:
		var pid: int = int(entry.get("peer_id", 0))
		for n in get_tree().get_nodes_in_group("players"):
			if int(n.get("peer_id")) == pid and n.has_method("apply_state_snapshot"):
				n.call("apply_state_snapshot", entry)
				break
	print("[Match] applied late-join snapshot it=%d time=%.1f pickups=%d" % [
		current_it_player, match_time_remaining, pickups_data.size()
	])


func build_and_send_late_join(to_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var players_data: Array = []
	for n in get_tree().get_nodes_in_group("players"):
		if n.has_method("build_state_snapshot"):
			players_data.append(n.call("build_state_snapshot"))
	var pickups_data: Array = []
	for p in get_tree().get_nodes_in_group("pickups"):
		pickups_data.append({
			"id": int(p.get("pickup_net_id")),
			"item_id": int(p.get("item_id")),
			"pos": (p as Node2D).global_position,
		})
	rpc_late_join_snapshot.rpc_id(to_peer, to_snapshot(), players_data, pickups_data)


func reassign_it(next_it: int) -> void:
	## Disconnect path: transfer It without dealing tag damage.
	if not multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		return
	set_current_it(next_it)
	_replicate_scores()
	rpc_force_it.rpc(next_it)


@rpc("authority", "call_local", "reliable")
func rpc_force_it(next_it: int) -> void:
	current_it_player = next_it
	it_changed.emit(next_it)
	for n in get_tree().get_nodes_in_group("players"):
		if not (n is CharacterBody2D):
			continue
		var tag: TagComponent = n.get_node("Tag") as TagComponent
		tag.set_it(int(n.get("peer_id")) == next_it)
	match_updated.emit()


@rpc("authority", "call_local", "reliable")
func rpc_remove_world_pickup(pickup_net_id: int) -> void:
	## World-state change: remove a pickup on every peer (autoload path is stable).
	for n in get_tree().get_nodes_in_group("pickups"):
		if int(n.get("pickup_net_id")) == pickup_net_id:
			n.queue_free()
			return
