extends CanvasLayer
class_name PauseMenu
## Esc / gamepad Start overlay for the lobby and a running session. The match
## keeps running underneath (networked, nothing pauses); the overlay only takes
## the mouse. Leaving closes the connection and returns to the main menu.

var is_open: bool = false
var _root: Control
var _card: PanelContainer
var _resume: Button
var _gfx: Button
var _fs: Button
var _leave: Button
var _quit: Button
var _hint: Label
var _armed: String = ""
var _saved_mouse: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	layer = 140
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	var esc: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	var start: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START
	if not (esc or start):
		return
	if is_open:
		get_viewport().set_input_as_handled()
		close()
	elif GameManager.screen != GameManager.Screen.MENU:
		get_viewport().set_input_as_handled()
		open()

func open() -> void:
	if is_open:
		return
	is_open = true
	_saved_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_armed = ""
	_build()
	Fx.sfx("click", null, -8.0, 0.8)

func close() -> void:
	if not is_open:
		return
	is_open = false
	if _root and is_instance_valid(_root):
		var r := _root
		_root = null
		var tw := r.create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(r, "modulate:a", 0.0, 0.12)
		tw.tween_callback(r.queue_free)
	if GameManager.screen == GameManager.Screen.SESSION:
		Input.mouse_mode = _saved_mouse

func _build() -> void:
	_root = Control.new()
	_root.theme = UiKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(UiKit.INK, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_card = UiKit.panel(26)
	_card.custom_minimum_size = Vector2(380, 0)
	center.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	_card.add_child(v)
	var in_session := GameManager.screen == GameManager.Screen.SESSION
	v.add_child(UiKit.label("Testing continues without you" if in_session else "Holding area", 13, UiKit.ACCENT))
	v.add_child(UiKit.heading("Paused" if not in_session else "Break room", 52))
	var sub := UiKit.text("The lab does not pause. Your subject is still standing there." if in_session else "Nobody is being tested yet. Enjoy it.", 15, UiKit.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	v.add_child(UiKit.spacer(18))

	_resume = UiKit.primary("Resume", close, 20)
	v.add_child(_resume)
	v.add_child(UiKit.spacer(10))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	v.add_child(list)
	_gfx = UiKit.menu_item("", _cycle_gfx, 18)
	list.add_child(_gfx)
	_fs = UiKit.menu_item("", _toggle_fullscreen, 18)
	list.add_child(_fs)
	list.add_child(UiKit.hairline())
	_leave = UiKit.menu_item("", _on_leave, 18, true)
	list.add_child(_leave)
	_quit = UiKit.menu_item("", _on_quit, 18, true)
	list.add_child(_quit)
	v.add_child(UiKit.spacer(10))
	_hint = UiKit.text("", 14, UiKit.DANGER.lightened(0.2))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hint)
	v.add_child(UiKit.spacer(6))
	v.add_child(UiKit.label("Esc to close", 12, UiKit.FAINT))
	_refresh_labels()

	_root.modulate.a = 0.0
	var tw := _root.create_tween().set_ease(UiKit.EASE).set_trans(UiKit.TRANS)
	tw.tween_property(_root, "modulate:a", 1.0, 0.16)
	_card.pivot_offset = Vector2(190, 160)
	_card.scale = Vector2(0.96, 0.96)
	_card.create_tween().set_ease(UiKit.EASE).set_trans(Tween.TRANS_BACK).tween_property(_card, "scale", Vector2.ONE, 0.22)
	_resume.grab_focus.call_deferred()

func _refresh_labels() -> void:
	var in_session := GameManager.screen == GameManager.Screen.SESSION
	_gfx.text = "GRAPHICS: " + Gfx.level_name()
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	_fs.text = "FULLSCREEN: " + ("ON" if fs else "OFF")
	var host := NetworkManager.is_server()
	if _armed == "leave":
		_leave.text = "CONFIRM: END THE LAB" if host else "CONFIRM: LEAVE"
	else:
		_leave.text = ("LEAVE MATCH" if in_session else "LEAVE LAB")
	_quit.text = "CONFIRM: QUIT TO DESKTOP" if _armed == "quit" else "QUIT GAME"
	match _armed:
		"leave":
			_hint.text = "Leave and end the lab for everyone? Click again to confirm." if host else "Leave this lab and go back to the main menu? Click again."
		"quit":
			_hint.text = ("Quit the game? This also ends the lab for everyone. " if host else "Quit the game? ") + "Click again to confirm."
		_:
			_hint.text = ""

func _cycle_gfx() -> void:
	Gfx.cycle()
	_refresh_labels()

func _toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_refresh_labels.call_deferred()

func _on_leave() -> void:
	var host := NetworkManager.is_server()
	var needs_confirm := host and NetworkManager.players.size() > 0
	if needs_confirm and _armed != "leave":
		_armed = "leave"
		_refresh_labels()
		return
	leave()

func leave() -> void:
	close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.close()
	GameManager.go(GameManager.Screen.MENU)

func _on_quit() -> void:
	if _armed != "quit":
		_armed = "quit"
		_refresh_labels()
		return
	get_tree().quit()
