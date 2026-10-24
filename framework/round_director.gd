extends Node
class_name RoundDirector
## Drives a session: pick a test, show its briefing card, load it on every peer,
## award points by placement, show the results card, repeat until someone hits
## the target score. Server-authoritative; clients follow via RPC.

signal session_over(winner_id)

const BRIEF_TIME: float = 10.0
const RESULT_TIME: float = 4.0

var container: Control
var minigame_pool: Array[String] = [
	"res://minigames/minefield3d/minefield3d.tscn",
]
var current: Minigame
var _round: int = 0
var _last_path: String = ""
var _bag: Array[String] = []
var _card: CanvasLayer
var _slug: String = ""
var _toasts: VBoxContainer

func _ready() -> void:
	Profile.session_begin()

func start() -> void:
	if NetworkManager.is_server():
		_next_round.call_deferred()

func _winner_id() -> int:
	var best := 0
	for id in NetworkManager.players:
		if NetworkManager.players[id].score >= Globals.target_score:
			if best == 0 or NetworkManager.players[id].score > NetworkManager.players[best].score:
				best = id
	return best

func _pick() -> String:
	if Globals.forced_minigame != "":
		return Globals.forced_minigame
	if _bag.is_empty():
		_bag = minigame_pool.duplicate()
		_bag.shuffle()
		if _bag.size() > 1 and _bag[0] == _last_path:
			_bag.reverse()
	return _bag.pop_front()

func _next_round() -> void:
	var w := _winner_id()
	if w != 0:
		_rpc_session_over.rpc(w)
		return
	var path := _pick()
	_last_path = path
	_round += 1
	if Globals.forced_minigame == "":
		_rpc_brief.rpc(path, _round)
		await get_tree().create_timer(BRIEF_TIME).timeout
	_rpc_load_minigame.rpc(path, randi())

@rpc("authority", "call_local", "reliable")
func _rpc_brief(path: String, round_no: int) -> void:
	if current and is_instance_valid(current):
		current.queue_free()
		current = null
	_round = round_no
	var slug := path.get_file().get_basename()
	var info := Globals.mode_info(slug)
	var v := _show_card("%02d" % round_no)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 10)
	meta.add_child(UiKit.pill("Test %02d" % round_no, UiKit.ACCENT, true, 14))
	meta.add_child(UiKit.label("%d subjects   First to %d points" % [NetworkManager.players.size(), Globals.target_score], 14, UiKit.MUTED))
	v.add_child(meta)
	v.add_child(UiKit.spacer(18))
	v.add_child(UiKit.label("Next test", 16, UiKit.MUTED))
	var name_l := UiKit.heading(info.name, 112, UiKit.TEXT)
	name_l.add_theme_constant_override("line_spacing", -28)
	v.add_child(name_l)
	var rule := UiKit.strong(info.rule, 24, UiKit.ACCENT)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(rule)
	v.add_child(UiKit.spacer(22))
	var cp := UiKit.panel(18)
	cp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cp.custom_minimum_size = Vector2(760, 0)
	v.add_child(cp)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	cp.add_child(cv)
	cv.add_child(UiKit.label("Controls", 13, UiKit.MUTED))
	var c := UiKit.text(info.get("controls", ""), 19, UiKit.TEXT)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.custom_minimum_size = Vector2(720, 0)
	cv.add_child(c)
	v.add_child(UiKit.spacer(26))
	var cd_row := HBoxContainer.new()
	cd_row.add_theme_constant_override("separation", 16)
	v.add_child(cd_row)
	var cd := UiKit.label("", 15, UiKit.MUTED)
	cd.custom_minimum_size = Vector2(170, 0)
	cd_row.add_child(cd)
	var bar := UiKit.bar(BRIEF_TIME, BRIEF_TIME, UiKit.ACCENT, 560, 4)
	cd_row.add_child(bar)
	bar.create_tween().tween_property(bar, "value", 0.0, BRIEF_TIME)
	UiKit.stagger(v, 0.05, 0.06)
	Fx.sfx("buzzer", null, -6.0)
	var secs := int(BRIEF_TIME)
	for i in range(secs, 0, -1):
		if not is_instance_valid(cd):
			return
		cd.text = "COMMENCING IN %d" % i
		if i <= 3:
			Fx.sfx("beep", null, -8.0)
			cd.add_theme_color_override("font_color", UiKit.ACCENT)
		await get_tree().create_timer(1.0).timeout

func _show_card(watermark: String = "") -> VBoxContainer:
	_hide_card()
	_card = CanvasLayer.new()
	_card.layer = 120
	add_child(_card)
	var root := Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(UiKit.INK, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var glow := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(UiKit.ACCENT, 0.09))
	g.set_color(1, Color(UiKit.ACCENT, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.85, 0.15)
	gt.fill_to = Vector2(0.25, 0.95)
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(glow)
	if watermark != "":
		var wm := UiKit.heading(watermark, 420, Color(1, 0.95, 0.88, 0.035))
		wm.remove_theme_color_override("font_shadow_color")
		wm.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		wm.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		wm.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		wm.grow_vertical = Control.GROW_DIRECTION_BOTH
		wm.offset_right = -40
		wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(wm)
	root.add_child(UiKit.scanlines())
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.offset_left = 88
	v.offset_right = -88
	root.add_child(v)
	root.modulate.a = 0.0
	root.create_tween().set_ease(UiKit.EASE).set_trans(UiKit.TRANS).tween_property(root, "modulate:a", 1.0, 0.25)
	return v

func _hide_card() -> void:
	if _card and is_instance_valid(_card):
		_card.queue_free()
	_card = null

@rpc("authority", "call_local", "reliable")
func _rpc_load_minigame(path: String, seed: int) -> void:
	Globals.round_seed = seed
	_hide_card()
	if current and is_instance_valid(current):
		current.queue_free()
	print("[LP] LOAD ", path.get_file(), " t=", Time.get_ticks_msec() / 1000)
	_slug = path.get_file().get_basename()
	Profile.round_begin(_slug)
	var scene: PackedScene = load(path)
	current = scene.instantiate()
	current.name = "Minigame"
	container.add_child(current)
	if NetworkManager.is_server():
		current.finished.connect(_on_finished, CONNECT_ONE_SHOT)
	Fx.music("game" if _round % 2 == 1 else "game2", -12.0)
	current.begin()

func _on_finished(placement: Array) -> void:
	if not NetworkManager.is_server():
		return
	print("[LP] RESULT ", placement.map(func(i): return NetworkManager.players.get(i, {}).get("name", str(i))))
	var award := placement.size()
	var gains: Array = []
	for id in placement:
		if NetworkManager.players.has(id):
			NetworkManager.players[id].score += award
			gains.append([id, award])
		award -= 1
	NetworkManager._broadcast_roster()
	await get_tree().create_timer(1.6).timeout
	_rpc_results.rpc(gains)
	await get_tree().create_timer(RESULT_TIME).timeout
	_next_round()

@rpc("authority", "call_local", "reliable")
func _rpc_results(gains: Array) -> void:
	var fresh := Profile.round_end(_slug, current, gains.map(func(g): return g[0]))
	if current and is_instance_valid(current):
		current.queue_free()
		current = null
	var v := _show_card()
	Fx.music("menu")
	v.add_child(UiKit.label("Test %02d concluded" % _round_display(), 15, UiKit.ACCENT))
	v.add_child(UiKit.heading("Results", 76))
	v.add_child(UiKit.spacer(14))
	var panel := UiKit.panel(20)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(700, 0)
	v.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	panel.add_child(rows)
	var place := 1
	for g in gains:
		var id: int = g[0]
		if not NetworkManager.players.has(id):
			continue
		var p: Dictionary = NetworkManager.players[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var rank := UiKit.heading(str(place), 34, UiKit.ACCENT if place == 1 else UiKit.FAINT)
		rank.custom_minimum_size = Vector2(26, 0)
		row.add_child(rank)
		row.add_child(UiKit.chip(p.color, 8, 30))
		var nm := UiKit.strong(str(p.name), 22, UiKit.TEXT if place == 1 else UiKit.MUTED.lightened(0.25))
		nm.custom_minimum_size = Vector2(190, 0)
		nm.clip_text = true
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(nm)
		var gain := UiKit.pill("+%d" % g[1], UiKit.ACCENT, place == 1, 15)
		gain.custom_minimum_size = Vector2(48, 0)
		row.add_child(gain)
		var br := UiKit.bar(float(p.score - g[1]), float(Globals.target_score), UiKit.ACCENT if place == 1 else UiKit.TEXT.darkened(0.35), 220, 6)
		br.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(br)
		br.create_tween().set_ease(UiKit.EASE).set_trans(UiKit.TRANS).tween_property(br, "value", float(p.score), 0.7).set_delay(0.35 + 0.08 * place)
		var sc := UiKit.label("%d / %d" % [p.score, Globals.target_score], 16, UiKit.TEXT if place == 1 else UiKit.MUTED)
		sc.custom_minimum_size = Vector2(64, 0)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sc)
		rows.add_child(row)
		place += 1
	UiKit.stagger(rows, 0.15, 0.07)
	Fx.sfx("win", null, -6.0)
	show_unlocks(fresh)

func show_unlocks(ids: Array[String]) -> void:
	if ids.is_empty():
		return
	if not _toasts or not is_instance_valid(_toasts):
		var layer := CanvasLayer.new()
		layer.layer = 130
		add_child(layer)
		_toasts = VBoxContainer.new()
		_toasts.theme = UiKit.theme()
		_toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_toasts.offset_left = -360
		_toasts.offset_right = -24
		_toasts.offset_top = 24
		_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toasts.add_theme_constant_override("separation", 10)
		layer.add_child(_toasts)
	var i := 0
	for id in ids:
		var it := Profile.item(id)
		if it.is_empty():
			continue
		var col := Profile.rarity_color(it.r)
		var holder := MarginContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var p := UiKit.panel(16)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := UiKit.glass_box(16)
		sb.border_color = Color(col, 0.55)
		sb.border_width_left = 4
		p.add_theme_stylebox_override("panel", sb)
		p.custom_minimum_size = Vector2(336, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		top.add_child(UiKit.label("Unlocked", 12, col.lightened(0.1)))
		top.add_child(UiKit.flex())
		top.add_child(UiKit.label("%s  %s" % [Profile.rarity_name(it.r), Profile.CATEGORY_NAMES.get(it.cat, "")], 12, UiKit.MUTED))
		v.add_child(top)
		v.add_child(UiKit.heading(it.name, 30, col.lightened(0.15)))
		var c := Profile.challenge_for(id)
		if not c.is_empty():
			var ct := UiKit.text(c.text, 14, UiKit.MUTED)
			ct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ct.custom_minimum_size = Vector2(300, 0)
			v.add_child(ct)
		holder.add_child(p)
		_toasts.add_child(holder)
		var slide := func(x: float) -> void:
			holder.add_theme_constant_override("margin_left", int(x))
			holder.add_theme_constant_override("margin_right", -int(x))
		slide.call(360.0)
		p.modulate.a = 0.0
		var tw := holder.create_tween().set_ease(UiKit.EASE).set_trans(Tween.TRANS_QUART)
		tw.tween_interval(0.3 * i)
		tw.tween_method(slide, 360.0, 0.0, 0.45)
		tw.parallel().tween_property(p, "modulate:a", 1.0, 0.3)
		tw.tween_interval(5.5)
		tw.tween_property(p, "modulate:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
		tw.tween_callback(holder.queue_free)
		i += 1
	Fx.sfx("arm", null, -6.0, 1.3)

func _round_display() -> int:
	return maxi(_round, 1)

@rpc("authority", "call_local", "reliable")
func _rpc_session_over(winner_id: int) -> void:
	_hide_card()
	if current and is_instance_valid(current):
		current.queue_free()
		current = null
	print("[LP] SESSION OVER winner=", winner_id)
	Profile.match_end(winner_id)
	if _toasts and is_instance_valid(_toasts):
		_toasts.get_parent().queue_free()
		_toasts = null
	session_over.emit(winner_id)
