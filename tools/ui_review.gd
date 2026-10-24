extends Node
## Dev harness: screenshots of every modernised screen at a given window size.
## godot --path . --windowed res://tools/ui_review.tscn -- <shot_prefix> <width> <height>

var prefix: String = "user://ui"
var main: Node

func shot(tag: String, settle: float = 0.6) -> void:
	await get_tree().create_timer(settle).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s_%s.png" % [prefix, tag]
	img.save_png(p)
	print("SHOT ", p, " ", img.get_size())

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	prefix = a[0]
	var w := int(a[1]) if a.size() > 1 else 1152
	var h := int(a[2]) if a.size() > 2 else 648
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(w, h)
	var path := "user://ui_review.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.use_save_path(path)
	for i in 10:
		Profile.apply_round("duck_hunt", {"place": 1 if i < 4 else 3, "count": 6, "died": false, "role": "sniper" if i < 4 else "runner"})
	for id in ["pattern_gold", "pattern_chrome", "pattern_blood", "hat_tophat_gold", "death_confetti", "hair_pink", "title_eotm", "pattern_hazard", "pattern_camo", "hat_goggles_neon"]:
		Profile.unlocked_ids.append(id)
	main = load("res://Main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	NetworkManager.local_name = "Ghost"
	await shot("01_menu", 2.5)
	for b in main.find_children("*", "Button", true, false):
		if (b as Button).text == "WARDROBE":
			(b as Button).grab_focus()
	await shot("01b_menu_focus", 0.5)

	if Updater._panel == null:
		Updater._build_ui()
	Updater._manifest = {"version": "0.4.0", "build": 4}
	Updater._entry = {"size": 96 * 1048576}
	Updater._state = "offer"
	Updater._info.text = "v0.4.0 is out (you have build 3).\nNew tests, fewer survivors.\n96 MB download."
	Updater._refresh_visible()
	await shot("02_updater_offer", 0.8)
	Updater._target = ""
	Updater._fail("the file was damaged on the way")
	await shot("03_updater_failed", 0.3)
	Updater._state = "idle"
	Updater._refresh_visible()

	NetworkManager.host()
	NetworkManager.add_bots(5)
	GameManager.go(GameManager.Screen.LOBBY)
	await shot("04_lobby", 2.5)
	var pause: PauseMenu = main.get_node("PauseMenu")
	pause.open()
	await shot("05_lobby_pause", 0.5)
	pause._on_leave()
	await shot("06_lobby_pause_confirm", 0.3)
	pause.close()

	Globals.enabled_modes.assign(["minefield3d"])
	NetworkManager.start_game()
	await shot("07_brief", 1.6)
	await get_tree().create_timer(10.0).timeout
	await shot("08_game_hud", 2.0)
	pause.open()
	await shot("09_game_pause", 0.5)
	pause.close()

	var rd: RoundDirector = main.get_node("RoundDirector")
	var ids: Array = NetworkManager.players.keys()
	rd._rpc_results([[ids[0], 6], [ids[1], 5], [ids[2], 4], [ids[3], 3], [ids[4], 2], [ids[5], 1]])
	await shot("10_results", 1.6)
	rd.show_unlocks(["hat_tophat_gold", "pattern_blood", "title_eotm"])
	await shot("11_toasts", 1.4)

	rd._hide_card()
	if rd._toasts and is_instance_valid(rd._toasts):
		rd._toasts.get_parent().queue_free()
	if rd.current and is_instance_valid(rd.current):
		rd.current.queue_free()
	for i in ids.size():
		NetworkManager.players[ids[i]].score = 12 - i * 2
	Profile.session_unlocks.assign(["hat_tophat_gold", "pattern_blood", "title_eotm", "hair_pink", "death_confetti", "pattern_camo", "pattern_hazard"])
	main._on_session_over(ids[0])
	await shot("12_survivor", 2.5)

	pause.open()
	pause._on_leave()
	pause._on_leave()
	await get_tree().create_timer(1.0).timeout
	print("UIREVIEW leave -> screen ", GameManager.screen, " server ", NetworkManager.is_server())
	await shot("13_menu_after_leave", 1.5)

	main._open_wardrobe()
	await shot("14_wardrobe_body", 2.5)
	var wr: Wardrobe = null
	for c in main.get_children():
		if c is Wardrobe:
			wr = c
	for t in ["suit", "pattern", "hair", "hat", "title", "death_fx", "challenges"]:
		wr.select_tab(t)
		await shot("15_wardrobe_" + t, 0.6)
	wr._on_card("hat_cone_blood")
	await shot("16_wardrobe_locked_status", 0.3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("UIREVIEW DONE")
	get_tree().quit()
