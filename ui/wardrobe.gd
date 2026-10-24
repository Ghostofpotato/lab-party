extends Control
class_name Wardrobe
## Wardrobe terminal: live turntable preview of your subject, category tabs with
## rarity-coloured item cards (locked ones show their challenge and progress),
## and a CHALLENGES tab with every challenge and its progress bar. Equipping
## saves to the Profile immediately.

signal closed()

const TABS: Array[String] = ["body", "suit", "pattern", "hair", "hat", "title", "death_fx", "challenges"]
const CARD_W: float = 196.0

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
	var tr := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.9))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.75, 0.5)
	tr.texture = gt
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	add_child(UiKit.scanlines())
	_build_left()
	_build_plate()
	_refresh_preview()
	select_tab("body")

func _build_left() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	m.offset_right = 690
	m.add_theme_constant_override("margin_left", 32)
	m.add_theme_constant_override("margin_top", 22)
	m.add_theme_constant_override("margin_bottom", 18)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(UiKit.heading("WARDROBE", 52))
	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_theme_constant_override("separation", 0)
	head.add_child(hv)
	hv.add_child(UiKit.text("FACILITY 7 · ISSUED EQUIPMENT", 13, UiKit.GREEN_DIM))
	_count = UiKit.text("", 15, UiKit.AMBER)
	hv.add_child(_count)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	for t in TABS:
		var b := UiKit.button(Profile.CATEGORY_NAMES.get(t, "CHALLENGES"), select_tab.bind(t), 19)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(0, 32)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_tab_buttons[t] = b
	var p := UiKit.panel()
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, UiKit.GREEN_DIM, 10))
	v.add_child(p)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(_scroll)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	v.add_child(bottom)
	bottom.add_child(UiKit.button("> BACK", _close, 26))
	_status = UiKit.text("", 14, UiKit.GREEN_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_status)

func _build_plate() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	m.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	m.grow_vertical = Control.GROW_DIRECTION_BEGIN
	m.add_theme_constant_override("margin_right", 30)
	m.add_theme_constant_override("margin_bottom", 22)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	v.add_theme_constant_override("separation", 0)
	v.custom_minimum_size = Vector2(400, 0)
	m.add_child(v)
	_plate_name = UiKit.heading("", 40, UiKit.GREEN)
	_plate_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_plate_name)
	_plate_title = UiKit.text("", 20, UiKit.GREEN)
	_plate_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_plate_title.add_theme_constant_override("outline_size", 6)
	_plate_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_plate_title)
	_plate_items = UiKit.text("", 14, UiKit.GREEN)
	_plate_items.add_theme_color_override("font_outline_color", Color.BLACK)
	_plate_items.add_theme_constant_override("outline_size", 6)
	_plate_items.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_plate_items.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_plate_items)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	closed.emit()

func select_tab(t: String) -> void:
	tab = t
	for k in _tab_buttons:
		var b: Button = _tab_buttons[k]
		var on: bool = k == t
		b.add_theme_stylebox_override("normal", UiKit.box(UiKit.AMBER if on else Color(0, 0, 0, 0.55), UiKit.AMBER if on else UiKit.GREEN_DIM))
		b.add_theme_color_override("font_color", UiKit.INK if on else UiKit.GREEN)
		b.add_theme_color_override("font_focus_color", UiKit.INK if on else UiKit.GREEN)
	_rebuild()

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
	_count.text = "%d / %d ITEMS · %d / %d CHALLENGES" % [have, total, done, Profile.CHALLENGES.size()]
	if tab == "challenges":
		_build_challenges()
	else:
		_build_items()
	_refresh_plate()

func _build_items() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_scroll.add_child(grid)
	_list = grid
	var items := Profile.items_in(tab)
	var unlocked := items.filter(func(it): return Profile.is_unlocked(it.id))
	var locked := items.filter(func(it): return not Profile.is_unlocked(it.id))
	unlocked.sort_custom(func(a, b): return a.r < b.r)
	locked.sort_custom(func(a, b): return a.r < b.r)
	for it in unlocked + locked:
		grid.add_child(_card(it))

func _card(it: Dictionary) -> Button:
	var unlocked: bool = Profile.is_unlocked(it.id)
	var worn: bool = Profile.equipped(it.cat) == it.id
	var col: Color = Profile.rarity_color(it.r)
	var b := Button.new()
	b.custom_minimum_size = Vector2(CARD_W, 104)
	b.focus_mode = Control.FOCUS_NONE
	var bg := Color(0.03, 0.07, 0.045, 0.92) if unlocked else Color(0.01, 0.015, 0.012, 0.92)
	var edge := UiKit.AMBER if worn else (col if unlocked else col.darkened(0.6))
	var normal := UiKit.box(bg, edge, 8)
	normal.border_width_left = 5
	if worn:
		normal.set_border_width_all(2)
		normal.border_width_left = 5
	var hover := UiKit.box(bg.lightened(0.06), col.lightened(0.2), 8)
	hover.set_border_width_all(2)
	hover.border_width_left = 5
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 12)
	mc.add_theme_constant_override("margin_right", 8)
	mc.add_theme_constant_override("margin_top", 6)
	mc.add_theme_constant_override("margin_bottom", 6)
	b.add_child(mc)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	mc.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var sw := _swatch(it)
	if sw:
		sw.modulate.a = 1.0 if unlocked else 0.35
		top.add_child(sw)
	var rl := UiKit.text(Profile.rarity_name(it.r), 12, col if unlocked else col.darkened(0.45))
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(rl)
	if worn:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(spacer)
		top.add_child(UiKit.text("WORN", 12, UiKit.AMBER))
	var nm := UiKit.heading(it.name, 25, col.lightened(0.1) if unlocked else Color(0.36, 0.4, 0.37))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.clip_text = true
	nm.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	nm.custom_minimum_size = Vector2(CARD_W - 24, 0)
	v.add_child(nm)
	var sub := UiKit.text("", 12, UiKit.GREEN_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(CARD_W - 24, 0)
	if not unlocked:
		var c := Profile.challenge_for(it.id)
		sub.text = "LOCKED · %s · %d/%d" % [c.get("text", "?"), Profile.progress(c) if not c.is_empty() else 0, c.get("goal", 0)]
		sub.add_theme_color_override("font_color", Color(0.55, 0.5, 0.42))
	elif worn:
		sub.text = "equipped" if it.cat != "death_fx" else "equipped · click to replay"
	else:
		sub.text = "click to equip"
	v.add_child(sub)
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
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = Vector2(14, 14)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _on_card(id: String) -> void:
	var it := Profile.item(id)
	if not Profile.is_unlocked(id):
		Fx.sfx("buzzer", null, -14.0, 1.5)
		_status.text = "LOCKED: " + Profile.requirement_text(id)
		_status.add_theme_color_override("font_color", UiKit.RED)
		return
	equip(id)

func equip(id: String) -> void:
	var it := Profile.item(id)
	if not Profile.equip(id):
		return
	_status.text = "EQUIPPED · %s · %s" % [Profile.rarity_name(it.r), it.name]
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
	_plate_title.text = "«%s»" % look.title if look.title != "" else ""
	_plate_title.add_theme_color_override("font_color", Profile.rarity_color(ti.get("r", 0)))
	var parts: Array[String] = []
	for cat in ["suit", "pattern", "hair", "hat", "death_fx"]:
		parts.append(Profile.item(Profile.equipped(cat)).get("name", ""))
	_plate_items.text = " · ".join(parts)

func _build_challenges() -> void:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 5)
	_scroll.add_child(v)
	_list = v
	var rows: Array = Profile.CHALLENGES.duplicate()
	rows.sort_custom(func(a, b):
		var da := Profile.is_done(a)
		var db := Profile.is_done(b)
		if da != db:
			return db
		return float(Profile.progress(a)) / float(a.goal) > float(Profile.progress(b)) / float(b.goal))
	for c in rows:
		v.add_child(_challenge_row(c))

func _challenge_row(c: Dictionary) -> Control:
	var done := Profile.is_done(c)
	var it := Profile.item(c.reward)
	var col := Profile.rarity_color(it.get("r", 0))
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UiKit.box(Color(0.03, 0.07, 0.045, 0.9) if done else Color(0.015, 0.03, 0.02, 0.9), col if done else UiKit.GREEN_DIM.darkened(0.3), 8)
	sb.border_width_left = 4
	sb.border_color = col
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	h.add_child(left)
	var t := UiKit.text(c.text, 15, UiKit.AMBER if done else UiKit.GREEN)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(t)
	left.add_child(UiKit.text("REWARD · %s · %s · %s" % [Profile.rarity_name(it.get("r", 0)), Profile.CATEGORY_NAMES.get(it.get("cat", ""), ""), it.get("name", "?")], 12, col))
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(150, 0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 2)
	h.add_child(right)
	var pt := UiKit.text("DONE" if done else "%d / %d" % [Profile.progress(c), c.goal], 14, UiKit.AMBER if done else UiKit.GREEN_DIM)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(pt)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 8)
	bar.max_value = float(c.goal)
	bar.value = float(Profile.progress(c))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	bg.border_color = UiKit.GREEN_DIM.darkened(0.3)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col if done else UiKit.GREEN
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	right.add_child(bar)
	return p
