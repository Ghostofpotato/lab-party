extends Node
## Dev harness: joins a host at 127.0.0.1 as a plain client and stays for N seconds.
## godot --path . res://tools/client_test.tscn -- <seconds>

func _ready() -> void:
	var secs: float = float(OS.get_cmdline_user_args()[0])
	var main: Node = load("res://Main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.5).timeout
	NetworkManager.local_name = "ClientBot"
	print("CLIENT join ", NetworkManager.join("127.0.0.1"))
	await get_tree().create_timer(secs).timeout
	print("CLIENT DONE")
	get_tree().quit()
