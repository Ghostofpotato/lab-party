extends Node
## Joins a lab as an AI subject the host plays with its bot brains, and stays until
## the host closes. godot --headless --path . res://tools/claude_join.tscn -- <host ip> [name]

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var ip: String = a[0] if a.size() > 0 else "127.0.0.1"
	var main: Node = load("res://Main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	NetworkManager.local_name = a[1] if a.size() > 1 else "Claude"
	NetworkManager.autopilot = true
	NetworkManager.disconnected.connect(get_tree().quit)
	NetworkManager.connection_failed.connect(get_tree().quit)
	print("[LP] CLAUDE joining ", ip, " ", NetworkManager.join(ip))
