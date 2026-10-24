extends Node
## Dev harness: boots Practice with bots straight into one minigame, saves
## screenshots every few seconds, prints the round result, then quits.
## Same as autotest plus FPS logging and a forced gfx level.
## godot --path . res://tools/gfx_fps.tscn -- <minigame.tscn> <shot_prefix> <seconds> <bots> <level 0-2>

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_tree().create_timer(150.0).timeout.connect(get_tree().quit)
	var a := OS.get_cmdline_user_args()
	Globals.forced_minigame = a[0]
	var prefix: String = a[1] if a.size() > 1 else "user://shot"
	var secs: float = float(a[2]) if a.size() > 2 else 12.0
	var bots: int = int(a[3]) if a.size() > 3 else 5
	if a.size() > 4:
		Gfx.auto_adjust = false
		Gfx.set_level(int(a[4]))
		if a.size() > 5 and a[5] == "old":
			var vp := get_viewport()
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.use_debanding = false
			vp.mesh_lod_threshold = 1.0
			if Gfx.level == Gfx.Q.LOW:
				vp.scaling_3d_scale = 0.5
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
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
		print("FPSLOG ", Gfx.level_name(), " ", Engine.get_frames_per_second())
	print("AUTOTEST DONE")
	get_tree().quit()
