extends Node
## Dev harness: a full Practice session through the normal random rotation.
## godot --path . res://tools/session_test.tscn -- <shot_prefix> <seconds> <target_score>

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var prefix: String = a[0]
	var secs: float = float(a[1])
	Globals.target_score = int(a[2])
	var main: Node = load("res://Main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	NetworkManager.local_name = "Tester"
	NetworkManager.host()
	NetworkManager.add_bots(3)
	GameManager.go(GameManager.Screen.LOBBY)
	await get_tree().create_timer(6.0).timeout
	NetworkManager.start_game()
	var t := 0.0
	var n := 0
	var last := ""
	while t < secs:
		await get_tree().create_timer(5.0).timeout
		t += 5.0
		var rd: Node = main.get_node_or_null("RoundDirector")
		var cur := ""
		if rd and rd.current and is_instance_valid(rd.current):
			cur = rd.current.scene_file_path.get_file()
		if cur != last and cur != "":
			print("SESSION LOAD ", cur, " at ", t)
			last = cur
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s_%03d.png" % [prefix, n])
		n += 1
	print("SESSION DONE scores ", NetworkManager.players.values().map(func(p): return [p.name, p.score]))
	get_tree().quit()
