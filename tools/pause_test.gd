extends Node
## Dev harness: pause menu leave flow over a real connection.
## host:   godot --headless --path . res://tools/pause_test.tscn -- host
## client: godot --headless --path . res://tools/pause_test.tscn -- client

func _wait_screen(s: int, limit: float) -> bool:
	var t := 0.0
	while GameManager.screen != s and t < limit:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	return GameManager.screen == s

func _ready() -> void:
	var role: String = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://Main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var pause: PauseMenu = main.get_node("PauseMenu")
	if role == "host":
		NetworkManager.local_name = "Host"
		NetworkManager.host()
		NetworkManager.add_bots(2)
		GameManager.go(GameManager.Screen.LOBBY)
		var t := 0.0
		while NetworkManager.players.size() < 4 and t < 20.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		print("PTEST host sees players ", NetworkManager.players.size())
		NetworkManager.start_game()
		await get_tree().create_timer(14.0).timeout
		print("PTEST host screen before leave ", GameManager.screen, " players ", NetworkManager.players.size())
		pause.open()
		pause._on_leave()
		print("PTEST host armed ", pause._armed, " still open ", pause.is_open, " screen ", GameManager.screen)
		pause._on_leave()
		await get_tree().create_timer(1.0).timeout
		print("PTEST host LEAVE ", "OK" if GameManager.screen == GameManager.Screen.MENU and not NetworkManager.is_server() else "FAIL", " screen ", GameManager.screen, " mouse ", Input.mouse_mode)
	else:
		await get_tree().create_timer(1.5).timeout
		NetworkManager.local_name = "Client"
		NetworkManager.join("127.0.0.1")
		var in_session := await _wait_screen(GameManager.Screen.SESSION, 30.0)
		print("PTEST client in session ", in_session)
		await get_tree().create_timer(6.0).timeout
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.3).timeout
		print("PTEST client esc opened ", pause.is_open)
		pause.open()
		pause._on_leave()
		await get_tree().create_timer(1.0).timeout
		print("PTEST client LEAVE ", "OK" if GameManager.screen == GameManager.Screen.MENU else "FAIL", " screen ", GameManager.screen, " peer ", multiplayer.has_multiplayer_peer())
	await get_tree().create_timer(1.5).timeout
	print("PTEST DONE ", role)
	get_tree().quit()
