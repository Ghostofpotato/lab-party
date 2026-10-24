extends Control
## Screen shell: Menu -> Lobby -> Session, styled as the lab intake terminal over
## a live 3D chamber. Builds identically on every peer so RPC node paths
## (Main/GameArea, Main/RoundDirector, .../Minigame) line up.

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _lobby_list: VBoxContainer
var _toast_label: Label
var _backdrop: MenuBackdrop
var _mode_grid: GridContainer
var _score_label: Label

func _ready() -> void:
	theme = UiKit.theme()
	GameManager.screen_changed.connect(_on_screen)
	NetworkManager.roster_changed.connect(_on_roster)
	NetworkManager.connected_to_server.connect(func(): GameManager.go(GameManager.Screen.LOBBY))
	NetworkManager.connection_failed.connect(func(): _toast("CONNECTION FAILED"))
	NetworkManager.disconnected.connect(func(): GameManager.go(GameManager.Screen.MENU))
	NetworkManager.game_should_start.connect(func(): GameManager.go(GameManager.Screen.SESSION))
	if OS.get_cmdline_user_args().is_empty():
		_play_intro()
	else:
		_on_screen(GameManager.Screen.MENU)

func _play_intro() -> void:
	var intro: Node = load("res://intro/studio_intro.tscn").instantiate()
	add_child(intro)
	intro.finished.connect(func():
		intro.queue_free()
		if GameManager.screen == GameManager.Screen.MENU:
			_on_screen(GameManager.Screen.MENU))

func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_backdrop = null
	_lobby_list = null

func _on_screen(s: int) -> void:
	_clear()
	match s:
		GameManager.Screen.MENU: _build_menu()
		GameManager.Screen.LOBBY: _build_lobby()
		GameManager.Screen.SESSION: _build_session()

func _add_backdrop() -> void:
	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.85))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(0.62, 0.5)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	add_child(UiKit.scanlines())

func _left_column(width: float = 420.0) -> VBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	m.custom_minimum_size = Vector2(width, 0)
	m.add_theme_constant_override("margin_left", 48)
	m.add_theme_constant_override("margin_top", 40)
	m.add_theme_constant_override("margin_bottom", 32)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	return v

# --- menu -----------------------------------------------------------------

func _build_menu() -> void:
	Fx.music("menu")
	_add_backdrop()
	var v := _left_column()
	v.add_child(UiKit.text("FACILITY 7 · SUBJECT INTAKE", 15, UiKit.GREEN_DIM))
	v.add_child(UiKit.heading("LAB PARTY", 96))
	v.add_child(UiKit.text("Survival is not expected.", 18, UiKit.AMBER))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	v.add_child(gap)

	v.add_child(UiKit.text("SUBJECT NAME", 14, UiKit.GREEN_DIM))
	_name_edit = LineEdit.new()
	_name_edit.text = NetworkManager.local_name
	_name_edit.custom_minimum_size = Vector2(300, 38)
	_name_edit.add_theme_font_override("font", UiKit.heading_font)
	_name_edit.add_theme_font_size_override("font_size", 26)
	v.add_child(_name_edit)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 10)
	v.add_child(gap2)

	v.add_child(UiKit.button("> PRACTICE  (you + 5 bots)", _on_practice, 30))
	v.add_child(UiKit.button("> HOST A LAB", _on_host, 30))
	var jbox := HBoxContainer.new()
	jbox.add_theme_constant_override("separation", 8)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(190, 40)
	jbox.add_child(_ip_edit)
	var join := UiKit.button("> JOIN", _on_join, 30)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jbox.add_child(join)
	v.add_child(jbox)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	var wb := UiKit.button("> WARDROBE", _open_wardrobe, 30)
	wb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrow.add_child(wb)
	var gfx_b := UiKit.button("> GFX: " + Gfx.level_name(), func(): pass, 30)
	gfx_b.pressed.connect(func(): Gfx.cycle(); gfx_b.text = "> GFX: " + Gfx.level_name())
	wrow.add_child(gfx_b)
	v.add_child(wrow)
	v.add_child(UiKit.button("> LEAVE FACILITY", func(): get_tree().quit(), 30))

	_toast_label = UiKit.text("", 18, UiKit.RED)
	v.add_child(_toast_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	v.add_child(UiKit.text("WASD move · SPACE act · F11 fullscreen · F3 FPS · " + Globals.GAME_VERSION, 13, UiKit.GREEN_DIM))

func _open_wardrobe() -> void:
	_apply_name()
	_clear()
	var w := Wardrobe.new()
	add_child(w)
	w.closed.connect(func(): _on_screen(GameManager.Screen.MENU))

func _apply_name() -> void:
	if _name_edit and _name_edit.text.strip_edges() != "":
		NetworkManager.local_name = _name_edit.text.strip_edges().left(16)

func _on_practice() -> void:
	_apply_name()
	if NetworkManager.host() == OK:
		NetworkManager.add_bots(5)
		GameManager.go(GameManager.Screen.LOBBY)
	else:
		_toast("COULD NOT OPEN A LOCAL SERVER")

func _on_host() -> void:
	_apply_name()
	if NetworkManager.host() == OK:
		GameManager.go(GameManager.Screen.LOBBY)
	else:
		_toast("HOST FAILED (PORT IN USE?)")

func _on_join() -> void:
	_apply_name()
	var ip := _ip_edit.text.strip_edges()
	if NetworkManager.join(ip) != OK:
		_toast("JOIN FAILED")

func _toast(msg: String) -> void:
	if _toast_label:
		_toast_label.text = msg
	push_warning(msg)

# --- lobby ----------------------------------------------------------------

func _build_lobby() -> void:
	Fx.music("menu")
	_add_backdrop()
	var v := _left_column(460.0)
	v.add_child(UiKit.text("HOLDING AREA", 15, UiKit.GREEN_DIM))
	v.add_child(UiKit.heading("SUBJECTS", 64))
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 4)
	v.add_child(_lobby_list)
	_refresh_lobby_list()

	if NetworkManager.is_server():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UiKit.button("+ BOT", func(): NetworkManager.add_bots(1), 22))
		row.add_child(UiKit.button("- BOT", _remove_bot, 22))
		v.add_child(row)
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 8)
		srow.add_child(UiKit.text("POINTS TO WIN", 16, UiKit.GREEN_DIM))
		srow.add_child(UiKit.button("-", func(): _set_target(Globals.target_score - 2), 22))
		_score_label = UiKit.heading(str(Globals.target_score), 34, UiKit.AMBER)
		srow.add_child(_score_label)
		srow.add_child(UiKit.button("+", func(): _set_target(Globals.target_score + 2), 22))
		v.add_child(srow)
		v.add_child(UiKit.button("> BEGIN TESTING", _start, 36))
	else:
		v.add_child(UiKit.text("waiting for the host to begin testing...", 16, UiKit.GREEN_DIM))
	v.add_child(UiKit.button("> LEAVE", func(): NetworkManager.close(); GameManager.go(GameManager.Screen.MENU), 24))

	if NetworkManager.is_server():
		_build_mode_panel()

func _build_mode_panel() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	m.offset_left = -470
	m.add_theme_constant_override("margin_right", 36)
	m.add_theme_constant_override("margin_top", 40)
	m.add_theme_constant_override("margin_bottom", 32)
	add_child(m)
	var p := UiKit.panel()
	m.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UiKit.heading("TEST ROTATION", 40))
	v.add_child(UiKit.text("click to toggle · ▶ run only that test", 13, UiKit.GREEN_DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	_mode_grid = GridContainer.new()
	_mode_grid.columns = 1
	_mode_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_grid.add_theme_constant_override("v_separation", 3)
	scroll.add_child(_mode_grid)
	_refresh_modes()

func _refresh_modes() -> void:
	if not _mode_grid:
		return
	for c in _mode_grid.get_children():
		c.queue_free()
	var i := 1
	for mode in Globals.MODES:
		var slug: String = mode.slug
		var on: bool = mode.ready and (Globals.enabled_modes.is_empty() or Globals.enabled_modes.has(slug))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var b := Button.new()
		b.text = "%s %02d  %s%s" % ["■" if on else "□", i, mode.name, "" if mode.ready else "   · OFFLINE"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.disabled = not mode.ready
		b.tooltip_text = mode.rule
		b.pressed.connect(_toggle_mode.bind(slug))
		row.add_child(b)
		var solo := Button.new()
		solo.text = "▶"
		solo.disabled = not mode.ready
		solo.tooltip_text = "Run only " + mode.name
		solo.pressed.connect(_solo_mode.bind(slug))
		row.add_child(solo)
		_mode_grid.add_child(row)
		i += 1

func _toggle_mode(slug: String) -> void:
	Fx.sfx("click", null, -6.0)
	if Globals.enabled_modes.is_empty():
		for m in Globals.MODES:
			if m.ready:
				Globals.enabled_modes.append(m.slug)
	if Globals.enabled_modes.has(slug):
		if Globals.enabled_modes.size() > 1:
			Globals.enabled_modes.erase(slug)
	else:
		Globals.enabled_modes.append(slug)
	_refresh_modes()

func _solo_mode(slug: String) -> void:
	Globals.enabled_modes.assign([slug])
	_start()

func _set_target(v: int) -> void:
	Globals.target_score = clampi(v, 4, 40)
	if _score_label:
		_score_label.text = str(Globals.target_score)

func _start() -> void:
	if Globals.active_mode_paths().is_empty():
		return
	NetworkManager.start_game()

func _remove_bot() -> void:
	for id in NetworkManager.players.keys():
		if NetworkManager.players[id].is_bot:
			NetworkManager.players.erase(id)
			NetworkManager._broadcast_roster()
			return

func _refresh_lobby_list() -> void:
	if not _lobby_list:
		return
	for c in _lobby_list.get_children():
		c.queue_free()
	var lineup: Array = []
	var n := 1
	for id in NetworkManager.players:
		var p: Dictionary = NetworkManager.players[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var sw := ColorRect.new()
		sw.color = p.color
		sw.custom_minimum_size = Vector2(14, 22)
		row.add_child(sw)
		row.add_child(UiKit.text("#%03d  %s" % [n, p.name], 20))
		if str(p.get("title", "")) != "":
			row.add_child(UiKit.text("«%s»" % p.title, 14, Profile.rarity_color(int(p.get("title_rarity", 0)))))
		row.add_child(UiKit.text(("BOT" if p.is_bot else "HUMAN") + " · " + str(p.get("hat", "")).to_upper(), 13, UiKit.GREEN_DIM))
		_lobby_list.add_child(row)
		lineup.append(p)
		n += 1
	if _backdrop:
		_backdrop.refresh(lineup)

func _on_roster() -> void:
	if GameManager.screen == GameManager.Screen.LOBBY:
		_refresh_lobby_list()

# --- session --------------------------------------------------------------

func _build_session() -> void:
	var area := Control.new()
	area.name = "GameArea"
	area.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(area)

	var rd := RoundDirector.new()
	rd.name = "RoundDirector"
	add_child(rd)
	rd.container = area
	rd.minigame_pool.assign(Globals.active_mode_paths())
	rd.session_over.connect(_on_session_over)
	rd.start()

func _on_session_over(winner_id: int) -> void:
	_add_backdrop()
	if NetworkManager.players.has(winner_id):
		var p: Dictionary = NetworkManager.players[winner_id]
		_backdrop.refresh([p])
		_backdrop.subjects[0].play_loop("Dance")
	var v := _left_column(560.0)
	var nm: String = NetworkManager.players[winner_id].name if NetworkManager.players.has(winner_id) else "?"
	v.add_child(UiKit.text("ALL TESTS CONCLUDED", 16, UiKit.GREEN_DIM))
	v.add_child(UiKit.heading("SURVIVOR:", 48))
	v.add_child(UiKit.heading(nm.to_upper(), 88, UiKit.AMBER))
	v.add_child(UiKit.text("Every other subject has been scheduled for recalibration.", 16))
	var ranks: Array = NetworkManager.players.keys()
	ranks.sort_custom(func(a, b): return NetworkManager.players[a].score > NetworkManager.players[b].score)
	for id in ranks:
		v.add_child(UiKit.text("%-16s %3d pts" % [NetworkManager.players[id].name, NetworkManager.players[id].score], 18))
	if not Profile.session_unlocks.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		v.add_child(gap)
		v.add_child(UiKit.text("UNLOCKED THIS SESSION · see WARDROBE", 14, UiKit.GREEN_DIM))
		var shown := 0
		for id in Profile.session_unlocks:
			var it := Profile.item(id)
			if it.is_empty():
				continue
			if shown >= 6:
				v.add_child(UiKit.text("+ %d more" % (Profile.session_unlocks.size() - shown), 14, UiKit.GREEN_DIM))
				break
			v.add_child(UiKit.text("%-9s %s  ·  %s" % [Profile.rarity_name(it.r), it.name, Profile.CATEGORY_NAMES.get(it.cat, "")], 16, Profile.rarity_color(it.r)))
			shown += 1
	v.add_child(UiKit.button("> RETURN TO INTAKE", func(): NetworkManager.close(); GameManager.go(GameManager.Screen.MENU), 30))
	Fx.sfx("win")
