extends Node
## Dev harness: host plays only Table Manners so a joined client can confirm the
## host's office face reaches it. godot ... res://tools/face_net_test.tscn -- host|client <seconds>

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var role: String = a[0]
	var secs: float = float(a[1])
	get_tree().create_timer(secs).timeout.connect(get_tree().quit)
	var main: Node = load("res://Main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	if role == "host":
		NetworkManager.local_name = "Host"
		NetworkManager.host()
		GameManager.go(GameManager.Screen.LOBBY)
		Globals.enabled_modes.assign(["table_manners"])
		await get_tree().create_timer(6.0).timeout
		NetworkManager.start_game()
	else:
		NetworkManager.local_name = "Client"
		NetworkManager.join("127.0.0.1")
