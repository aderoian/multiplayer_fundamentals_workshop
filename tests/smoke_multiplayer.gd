extends SceneTree
## Optional multiplayer smoke harness. Not part of the workshop teaching path.
## Run: godot --headless --path . -s res://tests/smoke_multiplayer.gd -- --workshop-smoke
##
## Spawns a second Godot process as an ENet client and checks peer connection.

const PORT: int = 7788


func _init() -> void:
	var run: bool = false
	for a in OS.get_cmdline_user_args():
		if a == "--workshop-smoke":
			run = true
	if not run:
		push_warning("smoke_multiplayer: pass -- --workshop-smoke to run")
		quit(0)
		return
	call_deferred("_run")


func _run() -> void:
	print("[smoke] starting ENet host")
	var host_peer := ENetMultiplayerPeer.new()
	var err: Error = host_peer.create_server(PORT, 4)
	if err != OK:
		push_error("[smoke] create_server failed: %s" % error_string(err))
		quit(1)
		return
	get_multiplayer().multiplayer_peer = host_peer
	print("[smoke] host peer id=%d" % get_multiplayer().get_unique_id())

	var godot: String = OS.get_environment("GODOT")
	if godot == "" or not FileAccess.file_exists(godot):
		print("[smoke] GODOT env / binary missing — host-only PASS (server created)")
		get_multiplayer().multiplayer_peer = null
		quit(0)
		return

	var project_path: String = ProjectSettings.globalize_path("res://")
	var pid: int = OS.create_process(godot, [
		"--headless",
		"--path", project_path,
		"-s", "res://tests/smoke_client_boot.gd",
		"--",
		"--port=%d" % PORT,
	])
	print("[smoke] spawned client pid=%d" % pid)
	await create_timer(2.5).timeout
	var peers: PackedInt32Array = get_multiplayer().get_peers()
	print("[smoke] peers connected: ", peers)
	var ok: bool = not peers.is_empty()
	if ok:
		print("[smoke] PASS connection host+1 client")
	else:
		push_error("[smoke] FAIL no client connected")
	if pid > 0:
		OS.kill(pid)
	await create_timer(0.3).timeout
	get_multiplayer().multiplayer_peer = null
	quit(0 if ok else 1)
