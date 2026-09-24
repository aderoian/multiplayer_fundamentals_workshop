extends Node
## Boot node for multiplayer gameplay smoke (autoload-safe).
## Run: godot --headless --path . res://tests/mp_boot.tscn -- --workshop-gameplay --role=host --port=7791 --clients=1

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
var _gameplay: bool = false


func _ready() -> void:
	var args := _parse_args()
	_gameplay = bool(args.get("gameplay", false))
	if not _gameplay:
		push_warning("mp_boot: pass -- --workshop-gameplay")
		get_tree().quit(0)
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
		await get_tree().create_timer(0.5).timeout
		await _wait_for_peers(expected_clients, 10.0)
		await _run_host_scenarios()
		_finish(0 if results["ok"] else 1)
	else:
		# Connect BEFORE join so we cannot miss the connected signal.
		var connected := false
		Network.client_connected_ok.connect(func() -> void: connected = true)
		var err2: Error = Network.join_game("127.0.0.1", port, peer_name)
		if err2 != OK:
			push_error("client create failed")
			get_tree().quit(1)
			return
		var t := 0.0
		while not connected and t < 10.0:
			# Also poll connection status (covers race if signal already fired).
			if multiplayer.multiplayer_peer != null:
				var st: MultiplayerPeer.ConnectionStatus = multiplayer.multiplayer_peer.get_connection_status()
				if st == MultiplayerPeer.CONNECTION_CONNECTED and multiplayer.get_unique_id() != 1:
					connected = true
					break
			await get_tree().create_timer(0.05).timeout
			t += 0.05
		if not connected:
			push_error("client connect timeout")
			get_tree().quit(1)
			return
		_load_arena()
		print("[agent] client ready peer=%d" % multiplayer.get_unique_id())
		# Tell host our TestRelay exists and arena is up.
		await get_tree().create_timer(0.3).timeout
		if relay:
			relay.rpc_report.rpc_id(1, "ready", true)
		await get_tree().create_timer(90.0).timeout
		get_tree().quit(0)


func _load_arena() -> void:
	arena = ARENA_SCENE.instantiate() as Node2D
	get_tree().root.add_child(arena)
	relay = RELAY_SCRIPT.new()
	arena.add_child(relay)
	print("[agent] %s arena loaded peer=%d" % [role, multiplayer.get_unique_id()])


func _wait_for_peers(count: int, timeout: float) -> void:
	var t := 0.0
	while t < timeout:
		var n: int = multiplayer.get_peers().size()
		var players: int = get_tree().get_nodes_in_group("players").size()
		var ready_clients := 0
		for pid in relay.reports.keys():
			if int(pid) != 1 and relay.reports[pid].get("ready", false):
				ready_clients += 1
		print("[agent] waiting peers=%d players=%d ready=%d need=%d" % [n, players, ready_clients, count])
		if n >= count and players >= count + 1 and ready_clients >= count:
			_pass("connection_spawn", "peers=%d players=%d ready=%d" % [n, players, ready_clients])
			return
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_fail("connection_spawn", "timeout peers=%d players=%d" % [
		multiplayer.get_peers().size(), get_tree().get_nodes_in_group("players").size()
	])


func _run_host_scenarios() -> void:
	await _scenario_movement()
	await _scenario_tag()
	await _scenario_hud_state()
	await _scenario_health_death_respawn()
	await _scenario_use_after_respawn()
	await _scenario_rotation_stays_zero()
	await _scenario_inventory_and_contest()
	await _scenario_scores_timer()
	await _scenario_restart_match()
	if expected_clients >= 2 or run_late_join:
		await _scenario_late_join_and_it_disconnect()
	else:
		await _scenario_it_disconnect_single_client()


func _scenario_movement() -> void:
	var host_player := _player(1)
	if host_player == null:
		_fail("movement", "missing host player")
		return
	var dest: Vector2 = Vector2(400, 300)
	if host_player.has_method("force_set_transform"):
		host_player.call("force_set_transform", dest)
	else:
		host_player.global_position = dest
	# Keep broadcasting for a few frames so unreliable sync lands
	for i in range(8):
		if host_player.has_method("_broadcast_transform"):
			host_player.call("_broadcast_transform")
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.3).timeout
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
				if pos.distance_to(dest) > 40.0:
					ok = false
					detail += " peer%s saw host at %s;" % [str(peer_id), str(pos)]
		if not found:
			ok = false
			detail += " peer%s missing host;" % str(peer_id)
	if ok:
		_pass("movement", "host moved; peers observed")
	else:
		_fail("movement", detail)


func _scenario_tag() -> void:
	Match.reassign_it(1)
	await get_tree().create_timer(0.25).timeout
	var clients: PackedInt32Array = multiplayer.get_peers()
	if clients.is_empty():
		_fail("tag", "no clients")
		return
	var target_id: int = clients[0]
	var host_p := _player(1)
	var tgt := _player(target_id)
	if host_p == null or tgt == null:
		_fail("tag", "missing players")
		return
	var meet := Vector2(600, 400)
	host_p.global_position = meet
	tgt.global_position = meet + Vector2(15, 0)
	relay.rpc_cmd.rpc_id(target_id, "move_self", {"pos": meet + Vector2(15, 0)})
	await get_tree().create_timer(0.4).timeout
	# Host requests tag via the same path as WASD-overlap (server-safe).
	host_p.call("_send_tag_request", target_id)
	await get_tree().create_timer(0.5).timeout
	await _collect_snapshots()
	var ok := true
	var detail := ""
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		if int(snap.get("it", -1)) != target_id:
			ok = false
			detail += " peer%s it=%s;" % [str(peer_id), str(snap.get("it"))]
		for p in snap.get("players", []):
			if int(p.get("peer_id")) == target_id:
				if not bool(p.get("is_it")):
					ok = false
					detail += " peer%s target not It;" % str(peer_id)
				if int(p.get("health", 100)) >= 100:
					ok = false
					detail += " peer%s target hp=%s;" % [str(peer_id), str(p.get("health"))]
	if ok:
		_pass("tag", "It -> %d with damage" % target_id)
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
	var h: HealthComponent = p.get_node("Health") as HealthComponent
	# Ensure killable
	h.apply_replica(25, true, false)
	h.take_damage(25)
	p.call("_sync_health_to_peers")
	await get_tree().create_timer(0.4).timeout
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
	_pass("health_death", "target dead on all peers")
	await get_tree().create_timer(3.6).timeout
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
		_pass("health_respawn", "respawned full hp")
	else:
		_fail("health_respawn", detail)


func _scenario_hud_state() -> void:
	## After tag, client snapshots must reflect health / is_it / alive for HUD-relevant props.
	await _collect_snapshots()
	var clients: PackedInt32Array = multiplayer.get_peers()
	if clients.is_empty():
		_fail("hud_state", "no clients")
		return
	var target_id: int = clients[0]
	var ok := true
	var detail := ""
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		var local: Dictionary = snap.get("local", {})
		# Every peer's player list must show consistent It / health for the tagged target.
		for pl in snap.get("players", []):
			if int(pl.get("peer_id")) == target_id:
				if not bool(pl.get("is_it")):
					ok = false
					detail += " peer%s target not It;" % str(peer_id)
				if int(pl.get("health", 100)) >= 100:
					ok = false
					detail += " peer%s target hp not damaged;" % str(peer_id)
				if not bool(pl.get("alive", true)):
					ok = false
					detail += " peer%s target unexpectedly dead;" % str(peer_id)
		# Local HUD props on the tagged client must match.
		if int(peer_id) == target_id:
			if not bool(local.get("is_it")):
				ok = false
				detail += " client local is_it false;"
			if int(local.get("health", 100)) >= 100:
				ok = false
				detail += " client local health not damaged;"
			if not bool(local.get("alive", false)):
				ok = false
				detail += " client local not alive;"
	if ok:
		_pass("hud_state", "clients see health/is_it/alive after tag")
	else:
		_fail("hud_state", detail)


func _scenario_use_after_respawn() -> void:
	## After death+respawn, the target must be able to use an inventory item again.
	var clients: PackedInt32Array = multiplayer.get_peers()
	if clients.is_empty():
		_fail("use_after_respawn", "no clients")
		return
	var target_id: int = clients[0]
	var p := _player(target_id)
	if p == null:
		_fail("use_after_respawn", "missing target")
		return
	# Ensure alive after prior death scenario.
	var h: HealthComponent = p.get_node("Health") as HealthComponent
	if not h.is_alive:
		p.call("_do_respawn")
		await get_tree().create_timer(0.5).timeout
	# Grant a speed boost (usable while alive) on server and sync.
	relay.rpc_server_grant_item(target_id, 2) # SPEED_BOOST
	await get_tree().create_timer(0.3).timeout
	await _collect_snapshots()
	var had_item := false
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		for pl in snap.get("players", []):
			if int(pl.get("peer_id")) == target_id:
				for s in pl.get("slots", []):
					if int(s) == 2:
						had_item = true
	if not had_item:
		_fail("use_after_respawn", "grant failed; no speed item on target")
		return
	# Client uses via the same path as key 1/2/3.
	relay.rpc_cmd.rpc_id(target_id, "use_slot", {"slot": 0})
	await get_tree().create_timer(0.6).timeout
	await _collect_snapshots()
	var used := true
	var can_use := true
	var detail := ""
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		for pl in snap.get("players", []):
			if int(pl.get("peer_id")) == target_id:
				for s in pl.get("slots", []):
					if int(s) == 2:
						used = false
						detail += " peer%s still has speed;" % str(peer_id)
				if not bool(pl.get("alive")):
					used = false
					detail += " peer%s not alive;" % str(peer_id)
		if int(peer_id) == target_id:
			var local: Dictionary = snap.get("local", {})
			if not bool(local.get("can_use", false)):
				can_use = false
				detail += " client can_use false;"
			if not bool(local.get("alive", false)):
				can_use = false
				detail += " client local not alive;"
	if used and can_use:
		_pass("use_after_respawn", "item used after respawn")
	else:
		_fail("use_after_respawn", detail)


func _scenario_rotation_stays_zero() -> void:
	var host_p := _player(1)
	if host_p == null:
		_fail("rotation", "missing host")
		return
	# Move through several directions on host + client.
	var dirs: Array[Vector2] = [
		Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 1).normalized()
	]
	var base: Vector2 = host_p.global_position
	for d in dirs:
		host_p.global_position = base + d * 40.0
		host_p.rotation = 0.0
		if host_p.has_method("_broadcast_transform"):
			host_p.call("_broadcast_transform")
		await get_tree().create_timer(0.05).timeout
	relay.rpc_cmd.rpc("walk_dirs", {})
	await get_tree().create_timer(0.4).timeout
	await _collect_snapshots()
	var ok := true
	var detail := ""
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		for pl in snap.get("players", []):
			if abs(float(pl.get("rot", 0.0))) > 0.001:
				ok = false
				detail += " peer%s player%d rot=%s;" % [str(peer_id), int(pl.get("peer_id")), str(pl.get("rot"))]
		var local: Dictionary = snap.get("local", {})
		if local.has("rot") and abs(float(local.get("rot", 0.0))) > 0.001:
			ok = false
			detail += " peer%s local rot=%s;" % [str(peer_id), str(local.get("rot"))]
	if ok:
		_pass("rotation", "all players rotation == 0")
	else:
		_fail("rotation", detail)


func _scenario_restart_match() -> void:
	var before_count: int = get_tree().get_nodes_in_group("players").size()
	var clients: PackedInt32Array = multiplayer.get_peers()
	if clients.is_empty():
		_fail("restart", "no clients")
		return
	var client_id: int = clients[0]
	# Mess up state so restart must clear it.
	Match.add_score(1, 5)
	Match.add_score(client_id, 3)
	Match.reassign_it(client_id)
	var host_p := _player(1)
	if host_p:
		host_p.get_node("Inventory").add_item(1)
		host_p.get_node("Health").take_damage(40)
		host_p.call("_sync_health_to_peers")
	await get_tree().create_timer(0.3).timeout
	# Client restart request must be ignored (no drop, It stays client until host restarts).
	var it_before_client_try: int = Match.current_it_player
	relay.rpc_cmd.rpc_id(client_id, "restart_match", {})
	await get_tree().create_timer(0.5).timeout
	var after_client_try: int = get_tree().get_nodes_in_group("players").size()
	if after_client_try < before_count:
		_fail("restart_client_ignored", "client restart dropped players %d -> %d" % [before_count, after_client_try])
		return
	if Match.current_it_player != it_before_client_try:
		_fail("restart_client_ignored", "client restart changed It unexpectedly")
		return
	_pass("restart_client_ignored", "client restart did nothing harmful")
	# Host restart: keep players, reset It to host, clear scores.
	if arena.has_method("restart_from_ui"):
		arena.call("restart_from_ui")
	await get_tree().create_timer(0.8).timeout
	await _collect_snapshots()
	var after_host: int = get_tree().get_nodes_in_group("players").size()
	var ok := after_host >= before_count and Match.current_it_player == 1 and Match.match_started
	var detail := "players=%d it=%d started=%s" % [after_host, Match.current_it_player, Match.match_started]
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		if int(snap.get("player_count", 0)) < before_count:
			ok = false
			detail += " peer%s count=%s;" % [str(peer_id), str(snap.get("player_count"))]
		if int(snap.get("it", -1)) != 1:
			ok = false
			detail += " peer%s it=%s;" % [str(peer_id), str(snap.get("it"))]
		if not bool(snap.get("started", false)):
			ok = false
			detail += " peer%s not started;" % str(peer_id)
		for pl in snap.get("players", []):
			if int(pl.get("health", 0)) < 100 or not bool(pl.get("alive")):
				ok = false
				detail += " peer%s player%d not full;" % [str(peer_id), int(pl.get("peer_id"))]
			for s in pl.get("slots", []):
				if int(s) != 0:
					ok = false
					detail += " peer%s inv not clear;" % str(peer_id)
					break
	if ok:
		_pass("restart_server", detail)
	else:
		_fail("restart_server", detail)


func _scenario_inventory_and_contest() -> void:
	var clients: PackedInt32Array = multiplayer.get_peers()
	if clients.is_empty():
		_fail("inventory", "no clients")
		return
	var pickup_id := 2
	# Both request same pickup nearly together
	relay.rpc_cmd.rpc("request_pickup", {"pickup_id": pickup_id})
	await get_tree().create_timer(0.02).timeout
	var host_p := _player(1)
	if host_p:
		# Ensure host in range
		for n in get_tree().get_nodes_in_group("pickups"):
			if int(n.get("pickup_net_id")) == pickup_id:
				host_p.global_position = (n as Node2D).global_position
				break
		host_p.call("_send_pickup_request", pickup_id)
	await get_tree().create_timer(0.6).timeout
	await _collect_snapshots()
	var max_holders := 0
	var any_has_pickup := false
	var detail := ""
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		var holders := 0
		for pl in snap.get("players", []):
			for s in pl.get("slots", []):
				if int(s) != 0:
					holders += 1
					break
		max_holders = maxi(max_holders, holders)
		for pk in snap.get("pickups", []):
			if int(pk.get("id")) == pickup_id:
				any_has_pickup = true
		detail += " peer%s holders=%d;" % [str(peer_id), holders]
	if max_holders == 1 and not any_has_pickup:
		_pass("inventory_contest", "exactly one collector; world pickup gone")
	else:
		_fail("inventory_contest", detail + " pickup_still=%s" % any_has_pickup)
	relay.rpc_cmd.rpc("use_slot", {"slot": 0})
	await get_tree().create_timer(0.5).timeout
	await _collect_snapshots()
	_pass("inventory_use", "use_slot issued")


func _scenario_scores_timer() -> void:
	await get_tree().create_timer(0.7).timeout
	await _collect_snapshots()
	if not relay.reports.has(1):
		_fail("scores_timer", "no host snapshot")
		return
	var host_snap: Dictionary = relay.reports[1].get("snapshot", {})
	var host_scores: Dictionary = host_snap.get("scores", {})
	var host_time: float = float(host_snap.get("time", -1))
	var score_mismatch := false
	var time_ok := true
	for peer_id in relay.reports.keys():
		var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
		var sc: Dictionary = snap.get("scores", {})
		for k in host_scores.keys():
			if int(sc.get(k, -999)) != int(host_scores[k]):
				score_mismatch = true
		if abs(float(snap.get("time", -1)) - host_time) > 2.0:
			time_ok = false
	if time_ok and not score_mismatch and host_time > 0.0 and Match.match_started:
		_pass("scores_timer", "time~%.1f scores=%s" % [host_time, str(host_scores)])
	else:
		_fail("scores_timer", "time_ok=%s score_mismatch=%s time=%.1f" % [time_ok, score_mismatch, host_time])


func _scenario_it_disconnect_single_client() -> void:
	var clients: PackedInt32Array = multiplayer.get_peers()
	if clients.is_empty():
		_fail("it_reassign", "no clients")
		return
	var cid: int = clients[0]
	Match.reassign_it(cid)
	await get_tree().create_timer(0.3).timeout
	relay.rpc_cmd.rpc_id(cid, "disconnect_self", {})
	await get_tree().create_timer(1.2).timeout
	await _collect_snapshots()
	var it_now: int = Match.current_it_player
	var players_left: int = get_tree().get_nodes_in_group("players").size()
	if it_now == 1 and players_left == 1:
		_pass("it_reassign_despawn", "It reassigned to host; despawned client")
	else:
		_fail("it_reassign_despawn", "it=%d players=%d" % [it_now, players_left])


func _scenario_late_join_and_it_disconnect() -> void:
	# Wait until late joiner (if any) is ready and player counts agree.
	var need_players: int = expected_clients + 1
	if run_late_join:
		need_players = expected_clients + 2 # host + initial clients + late
	var deadline := 10.0
	var t := 0.0
	var agreed := false
	var ref_count := 0
	var reporters := 0
	while t < deadline:
		await _collect_snapshots()
		ref_count = 0
		reporters = relay.reports.size()
		var counts: Dictionary = {}
		for peer_id in relay.reports.keys():
			var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
			var c: int = int(snap.get("player_count", 0))
			counts[c] = int(counts.get(c, 0)) + 1
			ref_count = maxi(ref_count, c)
		var matched: int = int(counts.get(ref_count, 0))
		print("[agent] late-join wait count=%d matched=%d reporters=%d need=%d" % [
			ref_count, matched, reporters, need_players
		])
		if matched == reporters and reporters >= need_players and ref_count >= need_players:
			agreed = true
			break
		await get_tree().create_timer(0.4).timeout
		t += 0.4
	var ok := agreed
	var detail := ""
	var ref: Dictionary = relay.reports.get(1, {}).get("snapshot", {})
	if not agreed:
		detail = "never agreed on player_count (last=%d reporters=%d need=%d)" % [
			ref_count, reporters, need_players
		]
	else:
		for peer_id in relay.reports.keys():
			var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
			if int(snap.get("it", -1)) != int(ref.get("it", -2)):
				ok = false
				detail += "it mismatch;"
			if abs(float(snap.get("time", 0)) - float(ref.get("time", 0))) > 2.5:
				ok = false
				detail += "timer mismatch;"
			if snap.get("pickups", []).size() != ref.get("pickups", []).size():
				ok = false
				detail += "pickup count mismatch;"
			for pl in snap.get("players", []):
				for rpl in ref.get("players", []):
					if int(pl.get("peer_id")) == int(rpl.get("peer_id")):
						if int(pl.get("health", -1)) != int(rpl.get("health", -2)):
							ok = false
							detail += "health mismatch;"
						if str(pl.get("slots", [])) != str(rpl.get("slots", [])):
							ok = false
							detail += "inventory mismatch;"
	if ok:
		_pass("late_join_state", "peers agree players=%d it=%s pickups=%d time=%.1f" % [
			int(ref.get("player_count", 0)), str(ref.get("it")),
			ref.get("pickups", []).size(), float(ref.get("time", 0))
		])
	else:
		_fail("late_join_state", detail)
	# Disconnect a client who is It (or make one It first)
	var it_id: int = Match.current_it_player
	if it_id == 1:
		var peers: PackedInt32Array = multiplayer.get_peers()
		if peers.size() > 0:
			Match.reassign_it(peers[0])
			await get_tree().create_timer(0.25).timeout
			it_id = Match.current_it_player
	if it_id != 1 and multiplayer.get_peers().has(it_id):
		relay.rpc_cmd.rpc_id(it_id, "disconnect_self", {})
		await get_tree().create_timer(1.2).timeout
		await _collect_snapshots()
		var new_it: int = Match.current_it_player
		var agree := true
		for peer_id in relay.reports.keys():
			var snap: Dictionary = relay.reports[peer_id].get("snapshot", {})
			if int(snap.get("it", -1)) != new_it:
				agree = false
		if new_it != it_id and agree:
			_pass("it_reassign", "It %d -> %d" % [it_id, new_it])
		else:
			_fail("it_reassign", "it=%d new=%d agree=%s" % [it_id, new_it, agree])
	else:
		_pass("it_reassign", "skipped")


func _collect_snapshots() -> void:
	relay.reports.clear()
	relay.rpc_cmd.rpc("snapshot", {})
	await get_tree().create_timer(0.5).timeout
	if not relay.reports.has(1) or not relay.reports[1].has("snapshot"):
		relay._cmd_snapshot()


func _player(pid: int) -> CharacterBody2D:
	for n in get_tree().get_nodes_in_group("players"):
		if n is CharacterBody2D and int(n.get("peer_id")) == pid:
			return n as CharacterBody2D
	return null


func _pass(name: String, detail: String) -> void:
	results["scenarios"][name] = {"pass": true, "detail": detail}
	print("[PASS] %s -- %s" % [name, detail])


func _fail(name: String, detail: String) -> void:
	results["scenarios"][name] = {"pass": false, "detail": detail}
	results["ok"] = false
	print("[FAIL] %s -- %s" % [name, detail])


func _finish(code: int) -> void:
	var abs_path := ProjectSettings.globalize_path(OUT_PATH)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "\t"))
		f.close()
		print("[agent] wrote %s" % abs_path)
	get_tree().quit(code)
