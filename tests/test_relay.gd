extends Node
## Optional test-only RPC bus. Not used by workshop teaching / menu flow.

signal report_received(from_peer: int, key: String, value: Variant)

var reports: Dictionary = {} ## peer_id -> { key: value }


func _ready() -> void:
	name = "TestRelay"
	add_to_group("test_relay")


@rpc("any_peer", "reliable")
func rpc_report(key: String, value: Variant) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not reports.has(sender):
		reports[sender] = {}
	reports[sender][key] = value
	report_received.emit(sender, key, value)


@rpc("any_peer", "call_local", "reliable")
func rpc_cmd(cmd: String, args: Dictionary = {}) -> void:
	_handle_cmd(cmd, args)


func _handle_cmd(cmd: String, args: Dictionary) -> void:
	match cmd:
		"snapshot":
			_cmd_snapshot()
		"move_self":
			_cmd_move_self(args.get("pos", Vector2.ZERO))
		"request_tag":
			_cmd_request_tag(int(args.get("target", 0)))
		"request_pickup":
			_cmd_request_pickup(int(args.get("pickup_id", 1)))
		"use_slot":
			_cmd_use_slot(int(args.get("slot", 0)))
		"walk_dirs":
			_cmd_walk_dirs()
		"restart_match":
			_cmd_restart_match()
		"disconnect_self":
			Network.disconnect_game()
			get_tree().quit(0)
		_:
			push_warning("[TestRelay] unknown cmd %s" % cmd)


func _local_player() -> CharacterBody2D:
	var my_id: int = multiplayer.get_unique_id()
	for n in get_tree().get_nodes_in_group("players"):
		if n is CharacterBody2D and int(n.get("peer_id")) == my_id:
			return n as CharacterBody2D
	return null


func _find_player(pid: int) -> CharacterBody2D:
	for n in get_tree().get_nodes_in_group("players"):
		if n is CharacterBody2D and int(n.get("peer_id")) == pid:
			return n as CharacterBody2D
	return null


func _cmd_snapshot() -> void:
	var my_id: int = multiplayer.get_unique_id()
	var players_info: Array = []
	for n in get_tree().get_nodes_in_group("players"):
		if not (n is CharacterBody2D):
			continue
		var h: Node = n.get_node_or_null("Health")
		var t: Node = n.get_node_or_null("Tag")
		var inv: Node = n.get_node_or_null("Inventory")
		players_info.append({
			"peer_id": int(n.get("peer_id")),
			"pos": (n as Node2D).global_position,
			"rot": float((n as Node2D).rotation),
			"health": int(h.get("health")) if h else -1,
			"alive": bool(h.get("is_alive")) if h else false,
			"shield": bool(h.get("has_shield")) if h else false,
			"is_it": bool(t.get("is_it")) if t else false,
			"slots": (inv.get("slots") as Array).duplicate() if inv else [],
			"speed_left": float(inv.get("speed_boost_time_left")) if inv else 0.0,
		})
	var pickups: Array = []
	for p in get_tree().get_nodes_in_group("pickups"):
		pickups.append({
			"id": int(p.get("pickup_net_id")),
			"item_id": int(p.get("item_id")),
			"pos": (p as Node2D).global_position,
		})
	var my_player := _local_player()
	var local_hud := {}
	if my_player:
		var lh: Node = my_player.get_node_or_null("Health")
		var lt: Node = my_player.get_node_or_null("Tag")
		var li: Node = my_player.get_node_or_null("Inventory")
		local_hud = {
			"health": int(lh.get("health")) if lh else -1,
			"alive": bool(lh.get("is_alive")) if lh else false,
			"is_it": bool(lt.get("is_it")) if lt else false,
			"slots": (li.get("slots") as Array).duplicate() if li else [],
			"rot": float(my_player.rotation),
			"can_use": bool(my_player.call("_can_use_items")) if my_player.has_method("_can_use_items") else bool(lh.get("is_alive")),
		}
	var payload := {
		"peer_id": my_id,
		"player_count": players_info.size(),
		"players": players_info,
		"pickups": pickups,
		"scores": Match.player_scores.duplicate(),
		"time": Match.match_time_remaining,
		"it": Match.current_it_player,
		"started": Match.match_started,
		"match_over": Match.match_over_shown,
		"local": local_hud,
	}
	if multiplayer.is_server():
		if not reports.has(my_id):
			reports[my_id] = {}
		reports[my_id]["snapshot"] = payload
	else:
		rpc_report.rpc_id(1, "snapshot", payload)


func _cmd_move_self(pos: Vector2) -> void:
	var p := _local_player()
	if p == null or not p.is_multiplayer_authority():
		return
	p.global_position = pos
	p.position = pos


func _cmd_request_tag(target_id: int) -> void:
	var p := _local_player()
	if p == null or not p.is_multiplayer_authority():
		return
	var target := _find_player(target_id)
	if target:
		p.global_position = target.global_position + Vector2(20, 0)
	if p.has_method("_send_tag_request"):
		p.call("_send_tag_request", target_id)
	elif multiplayer.is_server():
		p.call("_server_handle_tag", multiplayer.get_unique_id(), target_id)
	else:
		p.request_tag.rpc_id(1, target_id)


func _cmd_request_pickup(pickup_id: int) -> void:
	var p := _local_player()
	if p == null or not p.is_multiplayer_authority():
		return
	for n in get_tree().get_nodes_in_group("pickups"):
		if int(n.get("pickup_net_id")) == pickup_id:
			p.global_position = (n as Node2D).global_position
			break
	if p.has_method("_send_pickup_request"):
		p.call("_send_pickup_request", pickup_id)
	elif multiplayer.is_server():
		p.call("_server_pickup", multiplayer.get_unique_id(), pickup_id)
	else:
		p.request_pickup.rpc_id(1, pickup_id)


func _cmd_use_slot(slot: int) -> void:
	var p := _local_player()
	if p == null or not p.is_multiplayer_authority():
		return
	if p.has_method("_try_use_item"):
		p.call("_try_use_item", slot)
	elif p.has_method("_send_use_item"):
		p.call("_send_use_item", slot)
	elif multiplayer.is_server():
		p.call("_server_use_item", multiplayer.get_unique_id(), slot)
	else:
		p.request_use_item.rpc_id(1, slot)


func _cmd_walk_dirs() -> void:
	## Move in several directions on the authority. Rotation must remain 0 (top-down).
	var p := _local_player()
	if p == null or not p.is_multiplayer_authority():
		return
	var dirs: Array[Vector2] = [
		Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 1).normalized()
	]
	for d in dirs:
		p.velocity = d * 200.0
		p.move_and_slide()
		# Intentionally do NOT assign rotation from velocity — production code must keep 0.
		if p.has_method("_broadcast_transform"):
			p.call("_broadcast_transform")


func _cmd_restart_match() -> void:
	var arenas := get_tree().get_nodes_in_group("arena")
	if arenas.is_empty():
		return
	var arena: Node = arenas[0]
	if arena.has_method("restart_from_ui"):
		arena.call("restart_from_ui")


func _cmd_grant_item(item_id: int, slot: int) -> void:
	## Server-only helper: put an item in a player's inventory for smoke tests.
	if not multiplayer.is_server():
		return
	var target_id: int = multiplayer.get_remote_sender_id()
	if target_id == 0:
		target_id = multiplayer.get_unique_id()
	# Prefer explicit peer from args chain — grant to local player of whoever handles cmd.
	# When called via rpc_cmd from host targeting a client, that client runs this locally —
	# so only run grant on server for the named peer via host-side path.
	pass


@rpc("any_peer", "reliable")
func rpc_server_damage(peer_id: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var p := _find_player(peer_id)
	if p == null:
		return
	var h: HealthComponent = p.get_node("Health") as HealthComponent
	h.take_damage(amount)
	if p.has_method("_sync_health_to_peers"):
		p.call("_sync_health_to_peers")


@rpc("any_peer", "reliable")
func rpc_server_grant_item(peer_id: int, item_id: int) -> void:
	if not multiplayer.is_server():
		return
	var p := _find_player(peer_id)
	if p == null:
		return
	var inv: InventoryComponent = p.get_node("Inventory") as InventoryComponent
	inv.add_item(item_id)
	if p.has_method("rpc_sync_inventory"):
		p.rpc_sync_inventory.rpc(inv.slots.duplicate())
