extends Control
## Main menu — Play Offline works; Host/Join are workshop exercises on starter.

@onready var name_edit: LineEdit = $Center/Panel/VBox/NameRow/NameEdit
@onready var ip_edit: LineEdit = $Center/Panel/VBox/IpRow/IpEdit
@onready var port_edit: LineEdit = $Center/Panel/VBox/PortRow/PortEdit
@onready var status_label: Label = $Center/Panel/VBox/StatusLabel
@onready var offline_btn: Button = $Center/Panel/VBox/OfflineButton
@onready var host_btn: Button = $Center/Panel/VBox/HostButton
@onready var join_btn: Button = $Center/Panel/VBox/JoinButton
@onready var title_label: Label = $Center/Panel/VBox/Title
@onready var subtitle: Label = $Center/Panel/VBox/Subtitle


func _ready() -> void:
	name_edit.text = Network.player_name
	ip_edit.text = Network.address
	port_edit.text = str(Network.port)
	offline_btn.pressed.connect(_on_offline)
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	Network.connection_changed.connect(_on_status)
	_on_status(Network.status_text)
	title_label.text = "NETWORK TAG"
	subtitle.text = "Multiplayer Fundamentals Workshop"


func _on_offline() -> void:
	Network.play_offline(name_edit.text.strip_edges())
	get_tree().change_scene_to_file("res://scenes/arena.tscn")


func _on_host() -> void:
	var p: int = int(port_edit.text)
	Network.host_game(p, name_edit.text.strip_edges())
	# Starter: host_game is a stub — do not enter the arena until networking works (01+).
	# Later checkpoints will change_scene after a successful create_server.


func _on_join() -> void:
	var p: int = int(port_edit.text)
	Network.join_game(ip_edit.text.strip_edges(), p, name_edit.text.strip_edges())


func _on_status(text: String) -> void:
	status_label.text = text
