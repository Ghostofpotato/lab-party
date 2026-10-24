extends Control
## Screen shell: Menu -> Lobby -> Session over a live 3D chamber. Builds
## identically on every peer so RPC node paths (Main/GameArea,
## Main/RoundDirector, .../Minigame) line up.

const MARGIN_X: int = 56
const MARGIN_TOP: int = 44
const MARGIN_BOTTOM: int = 32

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _lobby_list: VBoxContainer
var _lobby_count: Label
var _toast_label: Label
var _backdrop: MenuBackdrop
var _mode_grid: VBoxContainer
var _mode_count: Label
var _score_label: Label
var _pause: PauseMenu
var _lab_list: VBoxContainer
var _lab_status: Label
var _news_row: HBoxContainer
var _news_dots: HBoxContainer
var _news_root: Control
var _news_cards: Array = []
var _news_page: int = 0
var _news_tick: float = 0.0
var _news_fetched_at: int = -1

const NEWS_URL := "https://raw.githubusercontent.com/Ghostofpotato/lab-party/main/news.json"
const NEWS_CACHE := "user://news.json"
const NEWS_IMG_CACHE := "user://news/"
const NEWS_BUNDLED := "res://ui/news.json"
const NEWS_PER_PAGE: int = 1
const NEWS_SECONDS: float = 8.0
const NEWS_REFETCH_MS: int = 600000

func _ready() -> void:
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause = PauseMenu.new()
	_pause.name = "PauseMenu"
	add_child(_pause)
	GameManager.screen_changed.connect(_on_screen)
	NetworkManager.roster_changed.connect(_on_roster)
	NetworkManager.connected_to_server.connect(func(): GameManager.go(GameManager.Screen.LOBBY))
	NetworkManager.connection_failed.connect(func(): _toast("Connection failed. Check the address and that the host is open."))
	NetworkManager.disconnected.connect(func(): GameManager.go(GameManager.Screen.MENU))
	NetworkManager.game_should_start.connect(func(): GameManager.go(GameManager.Screen.SESSION))
	NetworkManager.lan.labs_changed.connect(_refresh_labs)
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
		if c != _pause:
			c.queue_free()
	_backdrop = null
	_lobby_list = null
	_mode_grid = null
	_lab_list = null
	_lab_status = null
	_news_row = null
	_news_dots = null
	_news_root = null

func _on_screen(s: int) -> void:
	_clear()
	if s != GameManager.Screen.MENU:
		NetworkManager.lan.stop_listening()
	if _pause:
		_pause.close()
	match s:
		GameManager.Screen.MENU: _build_menu()
		GameManager.Screen.LOBBY: _build_lobby()
		GameManager.Screen.SESSION: _build_session()
	if _pause:
		move_child(_pause, get_child_count() - 1)

func _add_backdrop(reach: float = 0.62) -> void:
	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)
	add_child(UiKit.scrim(true, reach))
	add_child(UiKit.scanlines())

func _column(width: float, anchor_left: bool = true) -> VBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_LEFT_WIDE if anchor_left else Control.PRESET_RIGHT_WIDE)
	if anchor_left:
		m.offset_right = width + MARGIN_X
		m.add_theme_constant_override("margin_left", MARGIN_X)
	else:
		m.offset_left = -width - MARGIN_X * 0.7
		m.add_theme_constant_override("margin_right", int(MARGIN_X * 0.7))
	m.add_theme_constant_override("margin_top", MARGIN_TOP)
	m.add_theme_constant_override("margin_bottom", MARGIN_BOTTOM)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	UiKit.slide_in.call_deferred(m, Vector2(-24 if anchor_left else 24, 0))
	return v

# --- menu -----------------------------------------------------------------

func _build_menu() -> void:
	Fx.music("menu")
	_add_backdrop(0.58)
	var v := _column(372.0)
	v.add_theme_constant_override("separation", 0)
	v.add_child(UiKit.label("Facility 7 · Subject intake", 14, UiKit.ACCENT))
	var title := UiKit.heading("Lab Party", 108)
	title.add_theme_constant_override("line_spacing", -26)
	v.add_child(title)
	v.add_child(UiKit.text("Survival is not expected.", 18, UiKit.MUTED))
	v.add_child(UiKit.spacer(26))

	v.add_child(UiKit.label("Subject name", 13))
	v.add_child(UiKit.spacer(6))
	_name_edit = LineEdit.new()
	_name_edit.text = NetworkManager.local_name
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "Your name"
	_name_edit.custom_minimum_size = Vector2(0, 44)
	_name_edit.add_theme_font_size_override("font_size", 20)
	v.add_child(_name_edit)
	v.add_child(UiKit.spacer(16))

	var practice := UiKit.primary("Practice  ·  you + 5 bots", _on_practice, 22)
	v.add_child(practice)
	v.add_child(UiKit.spacer(10))

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	v.add_child(list)
	list.add_child(UiKit.menu_item("Host a lab", _on_host))
	list.add_child(UiKit.menu_item("Wardrobe", _open_wardrobe))
	var gfx_b := UiKit.menu_item("Graphics: " + Gfx.level_name(), func(): pass)
	gfx_b.pressed.connect(func(): Gfx.cycle(); gfx_b.text = ("Graphics: " + Gfx.level_name()).to_upper())
	list.add_child(gfx_b)
	list.add_child(UiKit.menu_item("Leave facility", func(): get_tree().quit()))
	UiKit.stagger(list, 0.18)

	v.add_child(UiKit.spacer(8))
	_toast_label = UiKit.strong("", 15, UiKit.DANGER)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_toast_label)
	v.add_child(UiKit.flex())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	foot.add_child(UiKit.label("WASD move   Space act   Esc menu   F11 fullscreen", 12, UiKit.FAINT))
	v.add_child(foot)
	v.add_child(UiKit.label(Globals.GAME_VERSION, 11, UiKit.FAINT))
	practice.grab_focus.call_deferred()
	_build_lan_panel()
	_build_news()

## --- LAN labs ----------------------------------------------------------------

func _build_lan_panel() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	m.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	m.grow_vertical = Control.GROW_DIRECTION_BEGIN
	m.add_theme_constant_override("margin_right", 40)
	m.add_theme_constant_override("margin_bottom", MARGIN_BOTTOM)
	add_child(m)
	UiKit.slide_in.call_deferred(m, Vector2(28, 0), 0.12)
	var p := UiKit.panel(16)
	p.custom_minimum_size = Vector2(452, 0)
	m.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.label("Labs on your network", 14, UiKit.ACCENT))
	head.add_child(UiKit.flex())
	var listening := NetworkManager.lan.start_listening()
	var dot := UiKit.pulse_dot(UiKit.ACCENT if listening else UiKit.FAINT, 7)
	head.add_child(dot)
	_lab_status = UiKit.label("Scanning" if listening else "Scanner offline", 12, UiKit.MUTED)
	head.add_child(_lab_status)
	v.add_child(head)
	_lab_list = VBoxContainer.new()
	_lab_list.add_theme_constant_override("separation", 4)
	v.add_child(_lab_list)
	if not listening:
		var note := UiKit.text("Another copy of the game on this PC is already listening for labs. Join by IP below.", 14, UiKit.MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(note)
	v.add_child(UiKit.hairline())
	var jbox := HBoxContainer.new()
	jbox.add_theme_constant_override("separation", 8)
	var jl := UiKit.label("Join by IP", 13)
	jl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	jbox.add_child(jl)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "Host address"
	_ip_edit.custom_minimum_size = Vector2(0, 36)
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.add_theme_font_size_override("font_size", 16)
	_ip_edit.text_submitted.connect(func(_t): _on_join())
	jbox.add_child(_ip_edit)
	jbox.add_child(UiKit.button("Join", _on_join, 15))
	v.add_child(jbox)
	_refresh_labs()

func _refresh_labs() -> void:
	if not _lab_list or not is_instance_valid(_lab_list):
		return
	for c in _lab_list.get_children():
		c.queue_free()
	if not NetworkManager.lan.is_listening():
		return
	var labs: Array = NetworkManager.lan.labs()
	if _lab_status:
		_lab_status.text = ("%d found" % labs.size() if labs.size() > 0 else "Scanning").to_upper()
	if labs.is_empty():
		var e := UiKit.text("No labs detected. Either nobody is hosting, or they are hiding from us. Both are noted in your file.", 14, UiKit.MUTED)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lab_list.add_child(e)
		return
	for lab in labs.slice(0, 4):
		_lab_list.add_child(_lab_row(lab))

func _lab_row(lab: Dictionary) -> Control:
	var reason := ""
	var tag := ""
	if int(lab.build) != Updater.BUILD:
		tag = "Needs update"
		reason = "Build %d here, you have %d" % [lab.build, Updater.BUILD]
	elif lab.started:
		tag = "In session"
		reason = "Testing already under way. Wait for the next batch."
	elif int(lab.players) >= int(lab.max):
		tag = "Full"
		reason = "Every chair is taken."
	var row := PanelContainer.new()
	var rs := UiKit.box(UiKit.SURFACE_HI, UiKit.LINE, 12)
	rs.content_margin_top = 7
	rs.content_margin_bottom = 7
	row.add_theme_stylebox_override("panel", rs)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	h.add_child(UiKit.chip(UiKit.ACCENT if tag == "" else UiKit.FAINT, 6, 30))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -3)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(names)
	var nm := UiKit.strong("%s's lab" % lab.host, 17, UiKit.TEXT if tag == "" else UiKit.MUTED)
	nm.clip_text = true
	names.add_child(nm)
	var sub := UiKit.text(reason if reason != "" else "%d of %d subjects   %s" % [lab.players, lab.max, lab.ip], 13, UiKit.MUTED)
	sub.clip_text = true
	names.add_child(sub)
	if tag != "":
		h.add_child(UiKit.pill(tag, UiKit.DANGER if tag == "Needs update" else UiKit.MUTED))
	var b := UiKit.primary("Join", _join_lab.bind(lab), 16) if tag == "" else UiKit.button("Join", func(): pass, 15)
	b.custom_minimum_size = Vector2(76, 38)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.set_meta("lan_sid", lab.sid)
	b.disabled = tag != ""
	var tip := reason
	if tag == "Needs update":
		tip += ". " + ("Restart the game to get the update." if int(lab.build) > Updater.BUILD else "The host needs to update.")
	b.tooltip_text = tip
	row.tooltip_text = tip
	h.add_child(b)
	return row

func _join_lab(lab: Dictionary) -> void:
	_apply_name()
	if NetworkManager.join(str(lab.ip), int(lab.port)) != OK:
		_toast("Could not reach %s's lab." % lab.host)

## --- news cards --------------------------------------------------------------

func _build_news() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	m.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	m.add_theme_constant_override("margin_right", 40)
	m.add_theme_constant_override("margin_top", MARGIN_TOP)
	add_child(m)
	_news_root = m
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UiKit.label("Facility bulletin", 13, UiKit.ACCENT))
	head.add_child(UiKit.flex())
	_news_dots = HBoxContainer.new()
	_news_dots.add_theme_constant_override("separation", 2)
	head.add_child(_news_dots)
	v.add_child(head)
	_news_row = HBoxContainer.new()
	_news_row.custom_minimum_size = Vector2(452, 0)
	_news_row.add_theme_constant_override("separation", 12)
	v.add_child(_news_row)
	_news_cards = _parse_news(_read_text(NEWS_CACHE))
	if _news_cards.is_empty():
		_news_cards = _parse_news(_read_text(NEWS_BUNDLED))
	_news_page = 0
	_news_tick = 0.0
	_show_news_page(true)
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	m.add_child(t)
	t.timeout.connect(_news_timer)
	if _news_fetched_at < 0 or Time.get_ticks_msec() - _news_fetched_at > NEWS_REFETCH_MS:
		var http := HTTPRequest.new()
		http.timeout = 6.0
		m.add_child(http)
		http.request_completed.connect(_on_news_fetched.bind(http))
		if http.request(NEWS_URL) != OK:
			http.queue_free()

func _news_timer() -> void:
	if not _news_root or not is_instance_valid(_news_root):
		return
	_news_root.visible = not (Updater._panel != null and Updater._panel.visible)
	_news_tick += 0.5
	if _news_tick >= NEWS_SECONDS and _news_pages() > 1:
		_news_tick = 0.0
		_news_page = (_news_page + 1) % _news_pages()
		_show_news_page(false)

func _news_pages() -> int:
	return ceili(_news_cards.size() / float(NEWS_PER_PAGE))

func _show_news_page(first: bool) -> void:
	if not _news_row or not is_instance_valid(_news_row):
		return
	for c in _news_row.get_children():
		c.queue_free()
	for c in _news_dots.get_children():
		c.queue_free()
	var pages := _news_pages()
	for i in pages:
		var d := Button.new()
		d.custom_minimum_size = Vector2(18, 14)
		d.focus_mode = Control.FOCUS_NONE
		d.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			d.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var c := UiKit.chip(UiKit.ACCENT if i == _news_page else Color(1, 1, 1, 0.22), 14 if i == _news_page else 6, 6)
		c.set_anchors_preset(Control.PRESET_CENTER)
		c.position = Vector2(9 - c.custom_minimum_size.x * 0.5, 4)
		d.add_child(c)
		d.pressed.connect(func(): _news_page = i; _news_tick = 0.0; _show_news_page(false))
		_news_dots.add_child(d)
	var start := _news_page * NEWS_PER_PAGE
	for card in _news_cards.slice(start, start + NEWS_PER_PAGE):
		var tex := _news_texture(card)
		var w := UiKit.news_card(card.tag, card.title, card.lines, UiKit.accent_named(card.accent), tex)
		w.custom_minimum_size = Vector2(452, 0)
		w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		w.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_news_row.add_child(w)
		if tex == null and str(card.image).begins_with("https://"):
			_fetch_news_image(str(card.image), w)
	UiKit.stagger(_news_row, 0.25 if first else 0.0, 0.09)
	if first:
		UiKit.slide_in.call_deferred(_news_root, Vector2(28, 0), 0.08)

func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func _parse_news(raw: String) -> Array:
	var out: Array = []
	var d: Variant = JSON.parse_string(raw) if raw != "" else null
	if not d is Dictionary or not d.get("cards") is Array:
		return out
	for c: Variant in d.cards:
		if not c is Dictionary or str(c.get("title", "")) == "":
			continue
		var lines: Array = []
		if c.get("lines") is Array:
			for l: Variant in c.lines.slice(0, 2):
				lines.append(str(l).left(90))
		out.append({
			"tag": str(c.get("tag", "Notice")).left(24),
			"title": str(c.get("title", "")).left(40),
			"lines": lines,
			"accent": str(c.get("accent", "amber")),
			"image": str(c.get("image", "")),
		})
		if out.size() >= 10:
			break
	return out

func _news_texture(card: Dictionary) -> Texture2D:
	var src := str(card.image)
	if src.begins_with("res://") and ResourceLoader.exists(src):
		return load(src) as Texture2D
	if src.begins_with("https://"):
		var cached := NEWS_IMG_CACHE + src.md5_text() + "." + ("png" if src.ends_with(".png") else "jpg")
		if FileAccess.file_exists(cached):
			var img := Image.load_from_file(ProjectSettings.globalize_path(cached))
			if img:
				return ImageTexture.create_from_image(img)
		var local := "res://ui/news/" + src.get_file()
		if ResourceLoader.exists(local):
			return load(local) as Texture2D
	return null

func _fetch_news_image(url: String, card: PanelContainer) -> void:
	var http := HTTPRequest.new()
	http.timeout = 6.0
	http.body_size_limit = 1048576
	card.add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var img := Image.new()
		var err := img.load_png_from_buffer(body) if url.ends_with(".png") else img.load_jpg_from_buffer(body)
		if err != OK:
			return
		DirAccess.make_dir_recursive_absolute(NEWS_IMG_CACHE)
		var f := FileAccess.open(NEWS_IMG_CACHE + url.md5_text() + "." + ("png" if url.ends_with(".png") else "jpg"), FileAccess.WRITE)
		if f:
			f.store_buffer(body)
		UiKit.set_news_card_image(card, ImageTexture.create_from_image(img)))
	if http.request(url) != OK:
		http.queue_free()

func _on_news_fetched(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	_news_fetched_at = Time.get_ticks_msec()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[LP] NEWS fetch failed ", result, " ", code)
		return
	var raw := body.get_string_from_utf8()
	var cards := _parse_news(raw)
	if cards.is_empty():
		return
	var f := FileAccess.open(NEWS_CACHE, FileAccess.WRITE)
	if f:
		f.store_string(raw)
	if JSON.stringify(cards) != JSON.stringify(_news_cards):
		_news_cards = cards
		_news_page = 0
		_news_tick = 0.0
		_show_news_page(false)

func _open_wardrobe() -> void:
	_apply_name()
	NetworkManager.lan.stop_listening()
	_clear()
	var w := Wardrobe.new()
	add_child(w)
	move_child(_pause, get_child_count() - 1)
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
		_toast("Could not open a local server.")

func _on_host() -> void:
	_apply_name()
	if NetworkManager.host() == OK:
		NetworkManager.advertise_lan()
		GameManager.go(GameManager.Screen.LOBBY)
	else:
		_toast("Host failed. Is the port already in use?")

func _on_join() -> void:
	_apply_name()
	var ip := _ip_edit.text.strip_edges()
	if NetworkManager.join(ip) != OK:
		_toast("Join failed. Check the address.")

func _toast(msg: String) -> void:
	if _toast_label and is_instance_valid(_toast_label):
		_toast_label.text = msg
		UiKit.fade_in(_toast_label, 0.0, 0.2)
	push_warning(msg)

# --- lobby ----------------------------------------------------------------

func _build_lobby() -> void:
	Fx.music("menu")
	_add_backdrop(0.5)
	var v := _column(404.0)
	v.add_theme_constant_override("separation", 0)
	v.add_child(UiKit.label("Holding area", 14, UiKit.ACCENT))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UiKit.heading("Subjects", 64))
	_lobby_count = UiKit.heading("", 64, UiKit.FAINT)
	head.add_child(_lobby_count)
	v.add_child(head)
	v.add_child(UiKit.spacer(10))

	var lp := UiKit.panel(10)
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(lp)
	var ls := ScrollContainer.new()
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(ls)
	_lobby_list = VBoxContainer.new()
	_lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_list.add_theme_constant_override("separation", 2)
	ls.add_child(_lobby_list)
	_refresh_lobby_list()
	v.add_child(UiKit.spacer(14))

	if NetworkManager.is_server():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var bl := UiKit.label("Bots", 13)
		bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bl)
		row.add_child(UiKit.icon_button("minus", _remove_bot, 36))
		row.add_child(UiKit.icon_button("plus", func(): NetworkManager.add_bots(1), 36))
		row.add_child(UiKit.flex())
		var pl := UiKit.label("Points to win", 13)
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pl)
		row.add_child(UiKit.icon_button("minus", func(): _set_target(Globals.target_score - 2), 36))
		_score_label = UiKit.heading(str(Globals.target_score), 30, UiKit.ACCENT)
		_score_label.custom_minimum_size = Vector2(36, 0)
		_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(_score_label)
		row.add_child(UiKit.icon_button("plus", func(): _set_target(Globals.target_score + 2), 36))
		v.add_child(row)
		v.add_child(UiKit.spacer(14))
		var begin := UiKit.primary("Begin testing", _start, 24)
		v.add_child(begin)
		begin.grab_focus.call_deferred()
	else:
		var wait := UiKit.text("Waiting for the host to begin testing. Try to look calm.", 16, UiKit.MUTED)
		wait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(wait)
	v.add_child(UiKit.spacer(4))
	v.add_child(UiKit.menu_item("Leave", func(): NetworkManager.close(); GameManager.go(GameManager.Screen.MENU), 18, true))

	if NetworkManager.is_server():
		_build_mode_panel()

func _build_mode_panel() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	m.offset_left = -436
	m.add_theme_constant_override("margin_right", 40)
	m.add_theme_constant_override("margin_top", MARGIN_TOP)
	m.add_theme_constant_override("margin_bottom", MARGIN_BOTTOM)
	add_child(m)
	UiKit.slide_in.call_deferred(m, Vector2(28, 0), 0.06)
	var p := UiKit.panel(18)
	m.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UiKit.heading("Test rotation", 34))
	head.add_child(UiKit.flex())
	_mode_count = UiKit.label("", 13, UiKit.MUTED)
	_mode_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_mode_count)
	v.add_child(head)
	var hint := UiKit.text("Click a test to include or skip it. Play runs only that one.", 14, UiKit.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	v.add_child(UiKit.spacer(6))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	_mode_grid = VBoxContainer.new()
	_mode_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_grid.add_theme_constant_override("separation", 2)
	scroll.add_child(_mode_grid)
	_refresh_modes()

func _refresh_modes() -> void:
	if not _mode_grid:
		return
	for c in _mode_grid.get_children():
		c.queue_free()
	var i := 1
	var on_count := 0
	var ready_count := 0
	for mode in Globals.MODES:
		var slug: String = mode.slug
		var on: bool = mode.ready and (Globals.enabled_modes.is_empty() or Globals.enabled_modes.has(slug))
		if mode.ready:
			ready_count += 1
		if on:
			on_count += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 38)
		b.disabled = not mode.ready
		b.tooltip_text = mode.rule
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var s := UiKit.box(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), 10)
		var sh := UiKit.box(UiKit.SURFACE_HI, UiKit.LINE, 10)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("disabled", s)
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("pressed", sh)
		b.add_theme_stylebox_override("hover_pressed", sh)
		b.pressed.connect(_toggle_mode.bind(slug))
		var h := HBoxContainer.new()
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 10
		h.offset_right = -10
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 12)
		b.add_child(h)
		var g := UiKit.Glyph.new()
		g.kind = "box"
		g.custom_minimum_size = Vector2(18, 18)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.color = UiKit.FAINT if not on else UiKit.ACCENT
		g.fill = UiKit.ACCENT if on else Color(0, 0, 0, 0)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(g)
		var num := UiKit.label("%02d" % i, 13, UiKit.FAINT)
		num.custom_minimum_size = Vector2(20, 0)
		h.add_child(num)
		var nm := UiKit.label(mode.name, 17, UiKit.TEXT if on else UiKit.MUTED)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		h.add_child(nm)
		if not mode.ready:
			h.add_child(UiKit.pill("Offline", UiKit.FAINT))
		row.add_child(b)
		var solo := UiKit.icon_button("play", _solo_mode.bind(slug), 38)
		solo.disabled = not mode.ready
		solo.tooltip_text = "Run only " + str(mode.name).capitalize()
		row.add_child(solo)
		_mode_grid.add_child(row)
		i += 1
	if _mode_count:
		_mode_count.text = ("%d of %d on" % [on_count, ready_count]).to_upper()

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
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	for id in NetworkManager.players:
		var p: Dictionary = NetworkManager.players[id]
		var row := PanelContainer.new()
		var rs := UiKit.box(UiKit.SURFACE_HI if id == me else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 12)
		rs.content_margin_top = 7
		rs.content_margin_bottom = 7
		row.add_theme_stylebox_override("panel", rs)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		h.add_child(UiKit.chip(p.color, 10, 30))
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", -3)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(names)
		var nm := UiKit.strong(str(p.name), 18)
		nm.clip_text = true
		names.add_child(nm)
		var sub := str(p.get("hat", "")).capitalize()
		if str(p.get("title", "")) != "":
			var tl := UiKit.text(str(p.title), 13, Profile.rarity_color(int(p.get("title_rarity", 0))))
			tl.clip_text = true
			names.add_child(tl)
		else:
			names.add_child(UiKit.text(sub if sub != "" else "No hat. Brave.", 13, UiKit.MUTED))
		if id == me:
			h.add_child(UiKit.pill("You", UiKit.ACCENT))
		elif p.is_bot:
			h.add_child(UiKit.pill("Bot", UiKit.MUTED))
		else:
			h.add_child(UiKit.pill("Human", UiKit.TEXT))
		_lobby_list.add_child(row)
		lineup.append(p)
	if _lobby_count:
		_lobby_count.text = str(NetworkManager.players.size())
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
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(area)

	var rd := RoundDirector.new()
	rd.name = "RoundDirector"
	add_child(rd)
	rd.container = area
	rd.minigame_pool.assign(Globals.active_mode_paths())
	rd.session_over.connect(_on_session_over)
	rd.start()

func _on_session_over(winner_id: int) -> void:
	_add_backdrop(0.55)
	move_child(_pause, get_child_count() - 1)
	if NetworkManager.players.has(winner_id):
		var p: Dictionary = NetworkManager.players[winner_id]
		_backdrop.refresh([p])
		_backdrop.subjects[0].play_loop("Dance")
	var v := _column(440.0)
	v.add_theme_constant_override("separation", 0)
	var nm: String = NetworkManager.players[winner_id].name if NetworkManager.players.has(winner_id) else "?"
	v.add_child(UiKit.label("All tests concluded", 14, UiKit.ACCENT))
	v.add_child(UiKit.spacer(10))
	v.add_child(UiKit.label("Survivor", 16, UiKit.MUTED))
	var name_l := UiKit.heading(nm, 92, UiKit.ACCENT)
	name_l.clip_text = true
	v.add_child(name_l)
	v.add_child(UiKit.text("Every other subject has been scheduled for recalibration.", 17, UiKit.MUTED))
	v.add_child(UiKit.spacer(18))

	var sp := UiKit.panel(16)
	v.add_child(sp)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	sp.add_child(rows)
	rows.add_child(UiKit.label("Final standings", 13))
	var ranks: Array = NetworkManager.players.keys()
	ranks.sort_custom(func(a, b): return NetworkManager.players[a].score > NetworkManager.players[b].score)
	var place := 1
	for id in ranks:
		var pl: Dictionary = NetworkManager.players[id]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var rank := UiKit.heading(str(place), 22, UiKit.ACCENT if place == 1 else UiKit.FAINT)
		rank.custom_minimum_size = Vector2(18, 0)
		h.add_child(rank)
		h.add_child(UiKit.chip(pl.color, 8, 20))
		var pn := UiKit.strong(str(pl.name), 17, UiKit.TEXT if place == 1 else UiKit.MUTED.lightened(0.2))
		pn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pn.clip_text = true
		h.add_child(pn)
		var pts := UiKit.label("%d pts" % pl.score, 15, UiKit.TEXT if place == 1 else UiKit.MUTED)
		h.add_child(pts)
		rows.add_child(h)
		place += 1
	UiKit.stagger(rows, 0.25, 0.05)
	v.add_child(UiKit.flex())
	var back := UiKit.primary("Return to intake", func(): NetworkManager.close(); GameManager.go(GameManager.Screen.MENU), 22)
	v.add_child(back)
	back.grab_focus.call_deferred()
	if not Profile.session_unlocks.is_empty():
		_build_unlock_panel()
	Fx.sfx("win")

func _build_unlock_panel() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	m.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	m.grow_vertical = Control.GROW_DIRECTION_BEGIN
	m.add_theme_constant_override("margin_right", 40)
	m.add_theme_constant_override("margin_bottom", MARGIN_BOTTOM)
	add_child(m)
	move_child(_pause, get_child_count() - 1)
	var p := UiKit.panel(16)
	p.custom_minimum_size = Vector2(330, 0)
	m.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UiKit.label("Unlocked this session", 13, UiKit.ACCENT))
	head.add_child(UiKit.flex())
	head.add_child(UiKit.label("See wardrobe", 12, UiKit.FAINT))
	v.add_child(head)
	var shown := 0
	for id in Profile.session_unlocks:
		var it := Profile.item(id)
		if it.is_empty():
			continue
		if shown >= 5:
			v.add_child(UiKit.label("+ %d more" % (Profile.session_unlocks.size() - shown), 13, UiKit.MUTED))
			break
		var col := Profile.rarity_color(it.r)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(UiKit.chip(col, 8, 8))
		var nl := UiKit.strong(it.name, 16, col.lightened(0.15))
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		h.add_child(nl)
		h.add_child(UiKit.label(str(Profile.CATEGORY_NAMES.get(it.cat, "")), 12, UiKit.MUTED))
		v.add_child(h)
		shown += 1
	UiKit.fade_in(m, 0.6)
	UiKit.slide_in(m, Vector2(28, 0), 0.6)
	get_tree().create_timer(0.7).timeout.connect(func(): Fx.sfx("arm", null, -6.0, 1.3))
