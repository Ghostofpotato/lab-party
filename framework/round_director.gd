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
	_rpc_load_minigame.rpc(path)

@rpc("authority", "call_local", "reliable")
func _rpc_brief(path: String, round_no: int) -> void:
	if current and is_instance_valid(current):
		current.queue_free()
		current = null
	_round = round_no
	var slug := path.get_file().get_basename()
	var info := Globals.mode_info(slug)
	_show_card()
	var v := _card_box()
	v.add_child(UiKit.text("TEST %02d · SUBJECTS: %d" % [round_no, NetworkManager.players.size()], 18, UiKit.GREEN_DIM))
	v.add_child(UiKit.heading("NEXT TEST:", 46))
	var name_l := UiKit.heading(info.name, 110, UiKit.AMBER)
	v.add_child(name_l)
	v.add_child(UiKit.text(info.rule, 26))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	v.add_child(gap)
	v.add_child(UiKit.text("CONTROLS", 15, UiKit.GREEN_DIM))
	var c := UiKit.text(info.get("controls", ""), 24, UiKit.AMBER)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.custom_minimum_size = Vector2(900, 0)
	v.add_child(c)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 14)
	v.add_child(gap2)
	var cd := UiKit.heading("", 40, UiKit.GREEN)
	v.add_child(cd)
	Fx.sfx("buzzer", null, -6.0)
	var secs := int(BRIEF_TIME)
	for i in range(secs, 0, -1):
		if not is_instance_valid(cd):
			return
		cd.text = "COMMENCING IN %d" % i
		if i <= 3:
			Fx.sfx("beep", null, -8.0)
		await get_tree().create_timer(1.0).timeout

func _show_card() -> void:
	_hide_card()
	_card = CanvasLayer.new()
	_card.layer = 120
	add_child(_card)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.025, 0.015, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.add_child(bg)
	var grid := ColorRect.new()
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ vec2 g = abs(fract(FRAGCOORD.xy / 48.0) - 0.5); float l = step(0.485, max(g.x, g.y)); float cx = step(abs(UV.x - 0.5), 0.0012) + step(abs(UV.y - 0.5), 0.002); COLOR = vec4(0.3, 0.9, 0.45, l * 0.07 + cx * 0.25); }"
	m.shader = sh
	grid.material = m
	_card.add_child(grid)
	_card.add_child(UiKit.scanlines())

func _card_box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	v.offset_left = 90
	_card.add_child(v)
	return v

func _hide_card() -> void:
	if _card and is_instance_valid(_card):
		_card.queue_free()
	_card = null

@rpc("authority", "call_local", "reliable")
func _rpc_load_minigame(path: String) -> void:
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
	_show_card()
	Fx.music("menu")
	var v := _card_box()
	v.add_child(UiKit.text("TEST %02d CONCLUDED" % _round_display(), 18, UiKit.GREEN_DIM))
	v.add_child(UiKit.heading("RESULTS", 64))
	var place := 1
	for g in gains:
		var id: int = g[0]
		if not NetworkManager.players.has(id):
			continue
		var p: Dictionary = NetworkManager.players[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var sw := ColorRect.new()
		sw.color = p.color
		sw.custom_minimum_size = Vector2(12, 30)
		row.add_child(sw)
		row.add_child(UiKit.heading("%d." % place, 34, UiKit.GREEN_DIM))
		row.add_child(UiKit.heading("%-14s" % p.name, 34, UiKit.AMBER if place == 1 else UiKit.GREEN))
		row.add_child(UiKit.heading("+%d" % g[1], 34, UiKit.GREEN))
		row.add_child(UiKit.heading("= %d / %d" % [p.score, Globals.target_score], 34, UiKit.GREEN_DIM))
		v.add_child(row)
		place += 1
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
		_toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_toasts.offset_left = -400
		_toasts.offset_right = -24
		_toasts.offset_top = 24
		_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toasts.add_theme_constant_override("separation", 8)
		layer.add_child(_toasts)
	var i := 0
	for id in ids:
		var it := Profile.item(id)
		if it.is_empty():
			continue
		var col := Profile.rarity_color(it.r)
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := UiKit.box(Color(0.02, 0.04, 0.03, 0.94), col, 14)
		sb.set_border_width_all(2)
		sb.border_width_left = 8
		p.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(v)
		v.add_child(UiKit.text("UNLOCKED · %s · %s" % [Profile.rarity_name(it.r), Profile.CATEGORY_NAMES.get(it.cat, "")], 13, col))
		v.add_child(UiKit.heading(it.name, 34, col))
		var c := Profile.challenge_for(id)
		if not c.is_empty():
			v.add_child(UiKit.text(c.text, 13, UiKit.GREEN_DIM))
		p.modulate.a = 0.0
		_toasts.add_child(p)
		var tw := p.create_tween()
		tw.tween_interval(0.35 * i)
		tw.tween_property(p, "modulate:a", 1.0, 0.25)
		tw.tween_interval(5.5)
		tw.tween_property(p, "modulate:a", 0.0, 0.6)
		tw.tween_callback(p.queue_free)
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
	show_unlocks(Profile.match_end(winner_id))
	session_over.emit(winner_id)
