extends Node
## Dev harness: boots Practice with bots straight into one minigame, saves
## screenshots every few seconds, prints the round result, then quits.
## godot --path . res://tools/autotest.tscn -- <minigame.tscn> <shot_prefix> [seconds] [bots]

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Globals.forced_minigame = a[0]
	var prefix: String = a[1] if a.size() > 1 else "user://shot"
	var secs: float = float(a[2]) if a.size() > 2 else 12.0
	var bots: int = int(a[3]) if a.size() > 3 else 5
	var main: Node = load("res://Main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	NetworkManager.local_name = "Tester"
	NetworkManager.host()
	NetworkManager.add_bots(bots)
	NetworkManager.start_game()
	await get_tree().process_frame
	var rd: RoundDirector = main.get_node_or_null("RoundDirector")
	if rd:
		rd.minigame_pool = [a[0]]
		await get_tree().create_timer(0.2).timeout
		if rd.current:
			rd.current.finished.connect(func(p): print("AUTOTEST RESULT ", p))
	var n := 0
	var t := 0.0
	while t < secs:
		await get_tree().create_timer(3.0).timeout
		t += 3.0
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [prefix, n])
		n += 1
	print("AUTOTEST DONE")
	get_tree().quit()
