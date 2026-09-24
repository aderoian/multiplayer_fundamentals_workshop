extends SceneTree
## Client boot helper for smoke_multiplayer.gd


func _init() -> void:
	call_deferred("_connect")


func _connect() -> void:
	var port: int = 7788
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.get_slice("=", 1))
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client("127.0.0.1", port)
	if err != OK:
		push_error("[smoke-client] connect failed")
		quit(1)
		return
	get_multiplayer().multiplayer_peer = peer
	get_multiplayer().connected_to_server.connect(func() -> void:
		print("[smoke-client] connected id=%d" % get_multiplayer().get_unique_id())
	)
	await create_timer(5.0).timeout
	quit(0)
