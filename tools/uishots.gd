extends Node
## Dev tool: screenshots of menu, lobby, a briefing card and a results card.
## godot --path . res://tools/uishots.tscn -- <prefix>

func _shot(prefix: String, n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, n])

func _ready() -> void:
	var prefix: String = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://Main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(2.0).timeout
	await _shot(prefix, "menu")
	NetworkManager.local_name = "Ghost"
	NetworkManager.host()
	NetworkManager.add_bots(5)
	GameManager.go(GameManager.Screen.LOBBY)
	await get_tree().create_timer(2.0).timeout
	await _shot(prefix, "lobby")
	NetworkManager.start_game()
	await get_tree().create_timer(1.2).timeout
	await _shot(prefix, "brief")
	await get_tree().create_timer(4.0).timeout
	await _shot(prefix, "game")
	var rd: RoundDirector = main.get_node("RoundDirector")
	rd._rpc_results([[1, 6], [1002, 5], [1003, 4]])
	await get_tree().create_timer(0.5).timeout
	await _shot(prefix, "results")
	get_tree().quit()
