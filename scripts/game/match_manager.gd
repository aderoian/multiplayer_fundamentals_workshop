extends Node
## MatchManager — central match / score / timer state.
##
## Architecture reminder (ask for every networked variable):
## 1. Who owns this state?
## 2. Who is allowed to change it?
## 3. Who needs to receive it?
## 4. What happens when a player joins late?
##
## Match state (timer, scores, started, current It) is distinct from:
## - Player state: position, health, inventory, is_it
## - World state: pickups / spawned objects

signal match_updated
signal match_started_signal
signal match_over(winner_peer_id: int, scores: Dictionary)
signal it_changed(new_it_peer_id: int)

const MATCH_DURATION_SEC: float = 120.0
const TAG_DAMAGE: int = 25

var match_started: bool = false
var match_time_remaining: float = MATCH_DURATION_SEC
var player_scores: Dictionary = {} ## peer_id -> int
var current_it_player: int = 1 ## peer_id; host/local is It at start
var match_over_shown: bool = false

# WORKSHOP TODO:
# Match timer and scores are MATCH STATE.
# 1) Who owns this? (Today: whoever runs the scene — every client would tick independently.)
# 2) Who may change it? (Only the authority / server should decrement the timer and award scores.)
# 3) Who needs it? (Every peer needs the same timer and scoreboard for a fair match.)
# 4) Late join? (A joiner mid-match needs the current remaining time and full score dict.)
# Concept: authoritative match state (checkpoint 08). Until then offline works locally.
# Change: tick timer only on the server, then replicate match_time_remaining / player_scores / match_started.


func _ready() -> void:
	reset_match_data()


func _process(delta: float) -> void:
	if not match_started or match_over_shown:
		return
	# Offline / local tick. Networking will move this behind server authority.
	if not _should_tick_timer_locally():
		return
	match_time_remaining = maxf(0.0, match_time_remaining - delta)
	match_updated.emit()
	if match_time_remaining <= 0.0:
		_end_match()


func _should_tick_timer_locally() -> bool:
	# With no multiplayer peer, Godot treats us as server (unique id 1). Offline must work.
	if multiplayer.multiplayer_peer == null:
		return true
	# WORKSHOP TODO:
	# With a peer connected, every machine must NOT run its own authoritative timer.
	# Implement server-only ticking in checkpoint 08 (world / match state).
	# For now (starter), only the offline path is intentional; host may still tick for local testing.
	return multiplayer.is_server()


func reset_match_data() -> void:
	match_started = false
	match_time_remaining = MATCH_DURATION_SEC
	player_scores.clear()
	current_it_player = 1
	match_over_shown = false
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


func ensure_player_score(peer_id: int) -> void:
	if not player_scores.has(peer_id):
		player_scores[peer_id] = 0
		match_updated.emit()


func remove_player_score(peer_id: int) -> void:
	player_scores.erase(peer_id)
	match_updated.emit()


func add_score(peer_id: int, amount: int = 1) -> void:
	ensure_player_score(peer_id)
	player_scores[peer_id] = int(player_scores[peer_id]) + amount
	match_updated.emit()
	# WORKSHOP TODO:
	# Scores are match state shared by everyone.
	# Offline: local add_score is fine.
	# Multiplayer: server should award the point and replicate player_scores (checkpoint 05/08).
	# Until scores replicate, only the host may see the "true" scoreboard.


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


func restart_match(initial_it_peer_id: int = 1) -> void:
	var kept_ids: Array = player_scores.keys()
	player_scores.clear()
	for id in kept_ids:
		player_scores[id] = 0
	start_match(initial_it_peer_id)


@rpc("authority", "call_local", "reliable")
func rpc_apply_tag_result(tagger_id: int, target_id: int) -> void:
	## Server broadcasts a validated tag transfer. Everyone updates It visuals.
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
	# Notify players so server can apply damage (06 hooks here too).
	var target: Node = null
	for n in get_tree().get_nodes_in_group("players"):
		if int(n.get("peer_id")) == target_id:
			target = n
			break
	if target and target.has_method("on_tagged_by_network"):
		target.call("on_tagged_by_network", tagger_id)
	print("[Match] tag result %d -> %d" % [tagger_id, target_id])
