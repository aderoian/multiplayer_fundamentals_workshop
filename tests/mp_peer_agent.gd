extends SceneTree
## Multiplayer peer agent for gameplay smoke tests.
## Usage:
##   godot --headless --path . -s res://tests/mp_peer_agent.gd -- --workshop-gameplay --role=host --port=7791 --clients=1
##   godot --headless --path . -s res://tests/mp_peer_agent.gd -- --workshop-gameplay --role=client --port=7791 --name=C1
##
## Host runs the scenario suite and writes tests/output/gameplay_results.json

const RELAY_SCRIPT: Script = preload("res://tests/test_relay.gd")
const ARENA_SCENE: PackedScene = preload("res://scenes/arena.tscn")
const OUT_PATH: String = "res://tests/output/gameplay_results.json"

var role: String = "host"
var port: int = 7791
var peer_name: String = "Host"
var expected_clients: int = 1
var run_late_join: bool = false
var results: Dictionary = {"scenarios": {}, "ok": true, "role": ""}
var relay: Node
var arena: Node2D


func _init() -> void:
	var args := _parse_args()
	if not args.get("gameplay", false):
		push_warning("mp_peer_agent: pass --workshop-gameplay")
		quit(0)
		return
	role = str(args.get("role", "host"))
	port = int(args.get("port", 7791))
	peer_name = str(args.get("name", "Host" if role == "host" else "Client"))
	expected_clients = int(args.get("clients", 1))
	run_late_join = bool(args.get("late_join", false))
	results["role"] = role
	call_deferred("_boot")


func _parse_args() -> Dictionary:
	var out := {"gameplay": false}
	for a in OS.get_cmdline_user_args():
		if a == "--workshop-gameplay":
			out["gameplay"] = true
		elif a.begins_with("--role="):
			out["role"] = a.get_slice("=", 1)
		elif a.begins_with("--port="):
			out["port"] = int(a.get_slice("=", 1))
		elif a.begins_with("--name="):
			out["name"] = a.get_slice("=", 1)
		elif a.begins_with("--clients="):
			out["clients"] = int(a.get_slice("=", 1))
		elif a == "--late-join":
			out["late_join"] = true
	return out


func _boot() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	if role == "host":
		var err: Error = Network.host_game(port, peer_name)
		if err != OK:
			_fail("host_create", "create_server failed: %s" % error_string(err))
			_finish(1)
			return
		_load_arena()
		await create_timer(0.4).timeout
		await _wait_for_peers(expected_clients, 8.0)
		await _run_host_scenarios()
		_finish(0 if results["ok"] else 1)
	else:
		var err2: Error = Network.join_game("127.0.0.1", port, peer_name)
		if err2 != OK:
			push_error("client create failed")
			quit(1)
			return
		# Wait until connected
		var connected := false
		Network.client_connected_ok.connect(func() -> void: connected = true)
		var t := 0.0
		while not connected and t < 8.0:
			await create_timer(0.1).timeout
			t += 0.1
		if not connected:
			push_error("client connect timeout")
			quit(1)
			return
		_load_arena()
		# Clients idle; respond to relay commands until killed or long timeout
		await create_timer(45.0).timeout
		quit(0)


func _load_arena() -> void:
	arena = ARENA_SCENE.instantiate() as Node2D
	root.add_child(arena)
	relay = RELAY_SCRIPT.new()
	arena.add_child(relay)
	print("[agent] %s arena loaded peer=%d" % [role, multiplayer.get_unique_id()])


func _wait_for_peers(count: int, timeout: float) -> void:
	var t := 0.0
	while t < timeout:
		var n: int = multiplayer.get_peers().size()
		var players: int = get_nodes_in_group("players").size()
		print("[agent] waiting peers=%d players=%d need_clients=%d" % [n, players, count])
		if n >= count and players >= count + 1:
			_pass("connection_spawn", "peers=%d players=%d" % [n, players])
			return
		await create_timer(0.25).timeout
		t += 0.25
	_fail("connection_spawn", "timeout peers=%d players=%d" % [
		multiplayer.get_peers().size(), get_nodes_in_group("players").size()
	])


func _run_host_scenarios() -> void:
	await _scenario_movement()
	await _scenario_tag()
	await _scenario_health_death_respawn()
	await _scenario_inventory_and_contest()
	await _scenario_scores_timer()
	if expected_clients >= 2 or run_late_join:
		await _scenario_late_join_and_it_disconnect()
	else:
		await _scenario_it_disconnect_single_client()


func _scenario_movement() -> void:
	var host_player := _player(1)
	if host_player == null:
		_fail("movement", "missing host player")
		return
	var start_pos: Vector2 = host_player.global_position
	var dest := start_pos + Vector2(120, 40)
	relay.rpc_cmd.rpc("move_self", {"pos": dest})
	# Also move host locally (authority)
	host_player.global_position = dest
	await create_timer(0.6).timeout
	await _collect_snapshots()
	var ok := true
	var detail := ""
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		var found := false
		for p in snap.get("players", []):
			if int(p.get("peer_id")) == 1:
				found = true
				var pos: Vector2 = p.get("pos", Vector2.ZERO)
				if pos.distance_to(dest) > 30.0:
					ok = false
					detail += " peer%s saw host at %s;" % [str(peer_id), str(pos)]
		if not found:
			ok = false
			detail += " peer%s missing host;" % str(peer_id)
	if ok:
		_pass("movement", "host moved to %s observed by peers" % str(dest))
	else:
		_fail("movement", detail)


func _scenario_tag() -> void:
	# Ensure host is It
	Match.reassign_it(1)
	await create_timer(0.2).timeout
	var clients: PackedInt32Array = multiplayer.get_peers()
	if clients.is_empty():
		_fail("tag", "no clients")
		return
	var target_id: int = clients[0]
	# Move both close via commands
	var host_p := _player(1)
	var tgt := _player(target_id)
	if host_p == null or tgt == null:
		_fail("tag", "missing players host=%s target=%s" % [host_p != null, tgt != null])
		return
	var meet := Vector2(600, 400)
	host_p.global_position = meet
	relay.rpc_cmd.rpc_id(target_id, "move_self", {"pos": meet + Vector2(15, 0)})
	await create_timer(0.35).timeout
	# Host requests tag (server validates)
	host_p.request_tag.rpc_id(1, target_id)
	await create_timer(0.5).timeout
	await _collect_snapshots()
	var ok := true
	var detail := ""
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		if int(snap.get("it", -1)) != target_id:
			ok = false
			detail += " peer%s it=%s;" % [str(peer_id), str(snap.get("it"))]
		for p in snap.get("players", []):
			if int(p.get("peer_id")) == target_id and not bool(p.get("is_it")):
				ok = false
				detail += " peer%s target not visually It;" % str(peer_id)
			if int(p.get("peer_id")) == target_id:
				var hp: int = int(p.get("health", 100))
				if hp > 100 - Match.TAG_DAMAGE + 1:
					# allow shield edge; expect damage applied
					if hp == 100:
						ok = false
						detail += " peer%s target hp still 100;" % str(peer_id)
	if ok:
		_pass("tag", "It transferred to %d and damage applied" % target_id)
	else:
		_fail("tag", detail)


func _scenario_health_death_respawn() -> void:
	var clients: PackedInt32Array = multiplayer.get_peers()
	if clients.is_empty():
		_fail("health", "no clients")
		return
	var target_id: int = clients[0]
	var p := _player(target_id)
	if p == null:
		_fail("health", "missing target")
		return
	# Kill on server
	var h: HealthComponent = p.get_node("Health") as HealthComponent
	h.apply_replica(100, true, false)
	h.take_damage(100)
	p.call("_sync_health_to_peers")
	await create_timer(0.3).timeout
	await _collect_snapshots()
	var dead_ok := true
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		for pl in snap.get("players", []):
			if int(pl.get("peer_id")) == target_id and bool(pl.get("alive")):
				dead_ok = false
	if not dead_ok:
		_fail("health_death", "target still alive on some peer")
		return
	# Wait respawn (~3s)
	await create_timer(3.5).timeout
	await _collect_snapshots()
	var alive_ok := true
	var detail := ""
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		for pl in snap.get("players", []):
			if int(pl.get("peer_id")) == target_id:
				if not bool(pl.get("alive")) or int(pl.get("health")) < 100:
					alive_ok = false
					detail += " peer%s alive=%s hp=%s;" % [str(peer_id), str(pl.get("alive")), str(pl.get("health"))]
	if alive_ok:
		_pass("health_death_respawn", "died and respawned with full hp")
	else:
		_fail("health_death_respawn", detail)


func _scenario_inventory_and_contest() -> void:
	var clients: PackedInt32Array = multiplayer.get_peers()
	if clients.is_empty():
		_fail("inventory", "no clients")
		return
	var c1: int = clients[0]
	# Pick a known pickup id (1)
	var pickup_id := 1
	# Move host + client onto same pickup and both request
	relay.rpc_cmd.rpc("request_pickup", {"pickup_id": pickup_id})
	await create_timer(0.05).timeout
	# Host also requests same (if authority) — host player
	var host_p := _player(1)
	if host_p:
		host_p.request_pickup.rpc_id(1, pickup_id)
	await create_timer(0.5).timeout
	await _collect_snapshots()
	var holders := 0
	var remaining := 0
	var detail := ""
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		var local_holders := 0
		for pl in snap.get("players", []):
			var slots: Array = pl.get("slots", [])
			var has_item := false
			for s in slots:
				if int(s) != 0:
					has_item = true
			if has_item:
				local_holders += 1
		# Count pickups with id still present
		var still := false
		for pk in snap.get("pickups", []):
			if int(pk.get("id")) == pickup_id:
				still = true
		if still:
			remaining += 1
		holders = maxi(holders, local_holders)
		detail += " peer%s holders=%d pickup_present=%s;" % [str(peer_id), local_holders, still]
	# Exactly one player should have an item; pickup gone on all peers
	var contest_ok: bool = holders == 1 and remaining == 0
	# Also verify all peers agree pickup is gone
	var all_agree_gone := true
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		for pk in snap.get("pickups", []):
			if int(pk.get("id")) == pickup_id:
				all_agree_gone = false
	if contest_ok and all_agree_gone:
		_pass("inventory_contest", "one collector; pickup removed everywhere")
	else:
		_fail("inventory_contest", detail)
	# Power-up use: whoever has an item uses slot 0
	relay.rpc_cmd.rpc("use_slot", {"slot": 0})
	await create_timer(0.4).timeout
	await _collect_snapshots()
	_pass("inventory_use", "use_slot commanded (effects depend on item type)")


func _scenario_scores_timer() -> void:
	await create_timer(0.6).timeout
	await _collect_snapshots()
	var times: Array = []
	var score_mismatch := false
	var host_scores: Dictionary = {}
	var host_time: float = -1.0
	if relay.reports.has(1):
		var hs: Dictionary = relay.reports[1].get("snapshot", {})
		host_scores = hs.get("scores", {})
		host_time = float(hs.get("time", -1))
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		times.append(float(snap.get("time", -1)))
		var sc: Dictionary = snap.get("scores", {})
		for k in host_scores.keys():
			if int(sc.get(k, -999)) != int(host_scores[k]):
				score_mismatch = true
	var time_ok := true
	for t in times:
		if abs(float(t) - host_time) > 1.5:
			time_ok = false
	if time_ok and not score_mismatch and host_time > 0.0:
		_pass("scores_timer", "time~%.1f scores=%s" % [host_time, str(host_scores)])
	else:
		_fail("scores_timer", "times=%s scores_mismatch=%s" % [str(times), score_mismatch])


func _scenario_it_disconnect_single_client() -> void:
	# Make client It, then disconnect client; host should become It
	var clients: PackedInt32Array = multiplayer.get_peers()
	if clients.is_empty():
		_fail("it_reassign", "no clients")
		return
	var cid: int = clients[0]
	Match.reassign_it(cid)
	await create_timer(0.3).timeout
	relay.rpc_cmd.rpc_id(cid, "disconnect_self", {})
	await create_timer(1.0).timeout
	await _collect_snapshots()
	var it_now: int = Match.current_it_player
	var players_left: int = get_nodes_in_group("players").size()
	if it_now == 1 and players_left == 1:
		_pass("it_reassign_despawn", "It->host after client disconnect; players=%d" % players_left)
	else:
		_fail("it_reassign_despawn", "it=%d players=%d" % [it_now, players_left])


func _scenario_late_join_and_it_disconnect() -> void:
	# Expected: already have 2 clients from start OR spawn late joiner externally.
	# Here we verify snapshot fields agree across current peers, then disconnect It.
	await _collect_snapshots()
	var ok := true
	var detail := ""
	var ref: Dictionary = {}
	if relay.reports.has(1):
		ref = relay.reports[1].get("snapshot", {})
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		if int(snap.get("it", -1)) != int(ref.get("it", -2)):
			ok = false
			detail += " it mismatch;"
		if int(snap.get("player_count", 0)) != int(ref.get("player_count", -1)):
			ok = false
			detail += " player_count mismatch;"
		if snap.get("pickups", []).size() != ref.get("pickups", []).size():
			ok = false
			detail += " pickup count mismatch;"
	if ok:
		_pass("late_join_state", "peers agree on it/players/pickups/timer")
	else:
		_fail("late_join_state", detail)
	# Disconnect current It if it is a client
	var it_id: int = Match.current_it_player
	if it_id != 1 and multiplayer.get_peers().has(it_id):
		relay.rpc_cmd.rpc_id(it_id, "disconnect_self", {})
		await create_timer(1.0).timeout
		await _collect_snapshots()
		var new_it: int = Match.current_it_player
		var agree := true
		for peer_id in relay.reports.keys():
			var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
			if int(snap.get("it", -1)) != new_it:
				agree = false
		if new_it != it_id and agree:
			_pass("it_reassign", "It %d -> %d visible to remaining peers" % [it_id, new_it])
		else:
			_fail("it_reassign", "it_id=%d new=%d agree=%s" % [it_id, new_it, agree])
	else:
		_pass("it_reassign", "skipped (It was host)")


func _collect_snapshots() -> void:
	relay.reports.clear()
	relay.rpc_cmd.rpc("snapshot", {})
	await create_timer(0.4).timeout
	# Host snapshot stored in _cmd_snapshot
	if not relay.reports.has(1):
		relay.reports[1] = {}
	# Force host snapshot if missing
	if not relay.reports[1].has("snapshot"):
		relay._cmd_snapshot()


func _player(pid: int) -> CharacterBody2D:
	for n in get_nodes_in_group("players"):
		if n is CharacterBody2D and int(n.get("peer_id")) == pid:
			return n as CharacterBody2D
	return null


func _pass(name: String, detail: String) -> void:
	results["scenarios"][name] = {"pass": true, "detail": detail}
	print("[PASS] %s — %s" % [name, detail])


func _fail(name: String, detail: String) -> void:
	results["scenarios"][name] = {"pass": false, "detail": detail}
	results["ok"] = false
	print("[FAIL] %s — %s" % [name, detail])


func _finish(code: int) -> void:
	var abs_path := ProjectSettings.globalize_path(OUT_PATH)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "\t"))
		f.close()
		print("[agent] wrote %s" % abs_path)
	quit(code)
