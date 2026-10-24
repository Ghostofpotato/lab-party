extends Control
class_name Wardrobe
## Wardrobe: live turntable preview of your subject, underline tabs per
## category, rarity-tinted item cards (locked ones show their challenge and
## progress) and a CHALLENGES tab with progress bars. Equipping saves at once.

signal closed()

const TABS: Array[String] = ["body", "suit", "pattern", "hair", "hat", "title", "death_fx", "challenges"]
const CARD_W: float = 186.0

var tab: String = "body"
var _backdrop: MenuBackdrop
var _preview: LabCharacter
var _tab_buttons: Dictionary = {}
var _scroll: ScrollContainer
var _list: Container
var _count: Label
var _status: Label
var _plate_name: Label
var _plate_title: Label
var _plate_items: Label
var _death_serial: int = 0

func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)
	add_child(UiKit.scrim(true, 0.72, 0.92))
	add_child(UiKit.scanlines())
	_build_left()
	_build_plate()
	_refresh_preview()
	select_tab("body")

func _build_left() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	m.offset_right = 690
	m.add_theme_constant_override("margin_left", 40)
	m.add_theme_constant_override("margin_top", 32)
	m.add_theme_constant_override("margin_bottom", 26)
	add_child(m)
	UiKit.slide_in.call_deferred(m, Vector2(-24, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	m.add_child(v)
	v.add_child(UiKit.label("Facility 7 · Issued equipment", 13, UiKit.ACCENT))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	v.add_child(head)
	head.add_child(UiKit.heading("Wardrobe", 56))
	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_END
	head.add_child(hv)
	_count = UiKit.label("", 14, UiKit.MUTED)
	hv.add_child(_count)
	hv.add_child(UiKit.spacer(10))
	v.add_child(UiKit.spacer(8))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	v.add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.text = str(Profile.CATEGORY_NAMES.get(t, "CHALLENGES"))
		b.add_theme_font_size_override("font_size", 15)
		b.custom_minimum_size = Vector2(0, 38)
		if t == "challenges":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(14, 0)
			tabs.add_child(gap)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(func(): Fx.sfx("click", null, -8.0); select_tab(t))
		tabs.add_child(b)
		_tab_buttons[t] = b
	v.add_child(UiKit.hairline())
	v.add_child(UiKit.spacer(12))
	var p := UiKit.panel(12)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(p)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(_scroll)
	v.add_child(UiKit.spacer(12))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	v.add_child(bottom)
	var back := UiKit.button("Back", _close, 17)
	back.custom_minimum_size.x = 110
	bottom.add_child(back)
	_status = UiKit.strong("", 15, UiKit.MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_status)

func _build_plate() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	m.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	m.grow_vertical = Control.GROW_DIRECTION_BEGIN
	m.add_theme_constant_override("margin_right", 32)
	m.add_theme_constant_override("margin_bottom", 26)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var p := UiKit.panel(16)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(320, 0)
	m.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(UiKit.label("Subject on file", 12, UiKit.FAINT))
	_plate_name = UiKit.heading("", 38)
	_plate_name.clip_text = true
	v.add_child(_plate_name)
	_plate_title = UiKit.strong("", 16)
	v.add_child(_plate_title)
	v.add_child(UiKit.spacer(6))
	_plate_items = UiKit.text("", 14, UiKit.MUTED)
	_plate_items.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plate_items.custom_minimum_size = Vector2(288, 0)
	v.add_child(_plate_items)
	UiKit.fade_in(m, 0.3)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	closed.emit()

func select_tab(t: String) -> void:
	tab = t
	for k in _tab_buttons:
		_style_tab(_tab_buttons[k], k == t)
	_rebuild()

func _style_tab(b: Button, on: bool) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = UiKit.ACCENT if on else Color(0, 0, 0, 0)
	s.border_width_bottom = 3
	s.content_margin_left = 10
	s.content_margin_right = 10
	var h := s.duplicate() as StyleBoxFlat
	if not on:
		h.border_color = UiKit.LINE_STRONG
	for st in ["normal", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, s)
	b.add_theme_stylebox_override("hover", h)
	var fg := Color.WHITE if on else UiKit.MUTED
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)

func _rebuild() -> void:
	if _list:
		_list.queue_free()
	_scroll.scroll_vertical = 0
	var total := 0
	var have := 0
	for it in Profile.ITEMS:
		total += 1
		if Profile.is_unlocked(it.id):
			have += 1
	var done := Profile.CHALLENGES.filter(func(c): return Profile.is_done(c)).size()
	_count.text = ("%d / %d items   %d / %d challenges" % [have, total, done, Profile.CHALLENGES.size()]).to_upper()
	if tab == "challenges":
		_build_challenges()
	else:
		_build_items()
	_refresh_plate()

func _build_items() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(grid)
	_list = grid
	var items := Profile.items_in(tab)
	var unlocked := items.filter(func(it): return Profile.is_unlocked(it.id))
	var locked := items.filter(func(it): return not Profile.is_unlocked(it.id))
	unlocked.sort_custom(func(a, b): return a.r < b.r)
	locked.sort_custom(func(a, b): return a.r < b.r)
	var i := 0
	for it in unlocked + locked:
		var c := _card(it)
		grid.add_child(c)
		if i < 12:
			UiKit.fade_in(c, 0.025 * i, 0.22)
		i += 1

func _card(it: Dictionary) -> Button:
	var unlocked: bool = Profile.is_unlocked(it.id)
	var worn: bool = Profile.equipped(it.cat) == it.id
	var col: Color = Profile.rarity_color(it.r)
	var b := Button.new()
	b.custom_minimum_size = Vector2(CARD_W, 112)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var bg := Color(0.11, 0.1, 0.09, 0.9).lerp(col, 0.07) if unlocked else Color(0.06, 0.055, 0.05, 0.82)
	var edge := UiKit.ACCENT if worn else (Color(col, 0.38) if unlocked else Color(1, 1, 1, 0.05))
	var normal := UiKit.box(bg, edge, 8)
	if worn:
		normal.set_border_width_all(2)
	var hover := UiKit.box(bg.lightened(0.05), UiKit.ACCENT if worn else Color(col, 0.75) if unlocked else Color(1, 1, 1, 0.14), 8)
	hover.set_border_width_all(2 if worn else 1)
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, normal)
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hover)
	UiKit.hover_lift(b, 1.03)
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 14)
	mc.add_theme_constant_override("margin_right", 12)
	mc.add_theme_constant_override("margin_top", 10)
	mc.add_theme_constant_override("margin_bottom", 10)
	b.add_child(mc)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	mc.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 7)
	v.add_child(top)
	var sw := _swatch(it)
	if sw:
		sw.modulate.a = 1.0 if unlocked else 0.35
		top.add_child(sw)
	var rl := UiKit.label(Profile.rarity_name(it.r), 12, col if unlocked else col.darkened(0.45))
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(rl)
	top.add_child(UiKit.flex())
	if worn:
		top.add_child(UiKit.pill("Worn", UiKit.ACCENT, true, 11))
	elif not unlocked:
		top.add_child(UiKit.label("Locked", 11, UiKit.FAINT))
	var nm := UiKit.strong(it.name, 18, UiKit.TEXT if unlocked else UiKit.FAINT.lightened(0.1))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(CARD_W - 30, 0)
	v.add_child(nm)
	v.add_child(UiKit.flex())
	if not unlocked:
		var c := Profile.challenge_for(it.id)
		var sub := UiKit.text(str(c.get("text", "Not available yet")), 13, UiKit.MUTED)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub.clip_text = true
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub.custom_minimum_size = Vector2(CARD_W - 30, 0)
		sub.tooltip_text = str(c.get("text", ""))
		v.add_child(sub)
		if not c.is_empty():
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override("separation", 8)
			var br := UiKit.bar(float(Profile.progress(c)), float(c.get("goal", 1)), col.darkened(0.1), 60, 4)
			br.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(br)
			row.add_child(UiKit.label("%d/%d" % [Profile.progress(c), c.get("goal", 0)], 11, UiKit.FAINT))
			v.add_child(row)
		b.tooltip_text = Profile.requirement_text(it.id)
	else:
		var hint := "Equipped" if worn else "Click to equip"
		if worn and it.cat == "death_fx":
			hint = "Equipped. Click to replay"
		v.add_child(UiKit.text(hint, 13, UiKit.ACCENT if worn else UiKit.FAINT.lightened(0.15)))
	if unlocked:
		b.tooltip_text = it.name
	b.pressed.connect(_on_card.bind(it.id))
	return b

func _swatch(it: Dictionary) -> Control:
	var c: Variant = null
	match it.cat:
		"suit":
			c = it.v
		"hair":
			c = it.v if (it.v as Color).a > 0.5 else Color("4a3424")
		"pattern":
			c = {0: Color("6a6f7c"), 1: Color("e0b818"), 2: Color("4a5a2a"), 3: Color("7a3a14"), 4: Color("6a0008"), 5: Color("2a2418"), 6: Color("4fd13a"), 7: Color("c8ccd4"), 8: Color("ffbf2e"), 9: Color("d8d4c4")}.get(it.v, Color.GRAY)
	if c == null:
		return null
	return UiKit.chip(c, 12, 12)

func _on_card(id: String) -> void:
	if not Profile.is_unlocked(id):
		Fx.sfx("buzzer", null, -14.0, 1.5)
		_status.text = "Locked. " + Profile.requirement_text(id)
		_status.add_theme_color_override("font_color", UiKit.DANGER.lightened(0.2))
		return
	equip(id)

func equip(id: String) -> void:
	var it := Profile.item(id)
	if not Profile.equip(id):
		return
	_status.text = "Equipped %s (%s)" % [it.name, Profile.rarity_name(it.r).capitalize()]
	_status.add_theme_color_override("font_color", Profile.rarity_color(it.r))
	var sy := _scroll.scroll_vertical
	_rebuild()
	await get_tree().process_frame
	_scroll.scroll_vertical = sy
	_refresh_preview()
	if it.cat == "death_fx":
		_preview_death()

func _refresh_preview() -> void:
	_death_serial += 1
	_preview = _backdrop.showcase(Profile.local_look(), "Idle")

func _preview_death() -> void:
	_death_serial += 1
	var serial := _death_serial
	await get_tree().create_timer(0.5).timeout
	if serial != _death_serial or not is_instance_valid(_preview):
		return
	_preview.die("Death01")
	Fx.blood(_backdrop.world, _preview.global_position + Vector3(0, 0.9, 0))
	await get_tree().create_timer(2.8).timeout
	if serial == _death_serial:
		_refresh_preview()

func _refresh_plate() -> void:
	var look := Profile.local_look()
	_plate_name.text = NetworkManager.local_name.to_upper()
	var title_id := Profile.equipped("title")
	var ti := Profile.item(title_id)
	_plate_title.text = str(look.title) if str(look.title) != "" else "No title"
	_plate_title.add_theme_color_override("font_color", Profile.rarity_color(ti.get("r", 0)) if str(look.title) != "" else UiKit.FAINT)
	var parts: Array[String] = []
	for cat in ["suit", "pattern", "hair", "hat", "death_fx"]:
		parts.append(str(Profile.item(Profile.equipped(cat)).get("name", "")))
	_plate_items.text = ",  ".join(parts)

func _build_challenges() -> void:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	_scroll.add_child(v)
	_list = v
	var rows: Array = Profile.CHALLENGES.duplicate()
	rows.sort_custom(func(a, b):
		var da := Profile.is_done(a)
		var db := Profile.is_done(b)
		if da != db:
			return db
		return float(Profile.progress(a)) / float(a.goal) > float(Profile.progress(b)) / float(b.goal))
	var i := 0
	for c in rows:
		var r := _challenge_row(c)
		v.add_child(r)
		if i < 10:
			UiKit.fade_in(r, 0.025 * i, 0.22)
		i += 1

func _challenge_row(c: Dictionary) -> Control:
	var done := Profile.is_done(c)
	var it := Profile.item(c.reward)
	var col := Profile.rarity_color(it.get("r", 0))
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UiKit.box(Color(0.11, 0.1, 0.09, 0.85).lerp(col, 0.06) if done else Color(1, 0.95, 0.88, 0.035), Color(col, 0.35) if done else Color(1, 1, 1, 0.04), 14)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	h.add_child(left)
	var t := UiKit.strong(c.text, 16, UiKit.TEXT if not done else UiKit.TEXT.darkened(0.1))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(t)
	var rw := HBoxContainer.new()
	rw.add_theme_constant_override("separation", 8)
	rw.add_child(UiKit.pill(Profile.rarity_name(it.get("r", 0)), col, false, 11))
	var rn := UiKit.text("%s  %s" % [str(Profile.CATEGORY_NAMES.get(it.get("cat", ""), "")).capitalize(), it.get("name", "?")], 13, UiKit.MUTED)
	rn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rw.add_child(rn)
	left.add_child(rw)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(140, 0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 6)
	h.add_child(right)
	if done:
		var dp := UiKit.pill("Done", col, true, 12)
		dp.size_flags_horizontal = Control.SIZE_SHRINK_END
		right.add_child(dp)
	else:
		var pt := UiKit.label("%d / %d" % [Profile.progress(c), c.goal], 14, UiKit.MUTED)
		pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(pt)
		right.add_child(UiKit.bar(float(Profile.progress(c)), float(c.goal), UiKit.ACCENT, 140, 6))
	return p
