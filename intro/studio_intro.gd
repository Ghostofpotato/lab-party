extends Node3D
## GRIM INTERN studio sting (~11 s). A lamp flickers on, an intern pulls the
## lever that lowers the steel logo on chains, the last letter snaps loose and
## crushes him, then the logo flickers to neon over the corpse with the tagline.
## Any key, mouse click or gamepad button skips. Emits finished() exactly once.

signal finished()

const PH_TEX := "res://assets/ph/tex/"
const PH_MOD := "res://assets/ph/models/"
const FONT := preload("res://assets/ui/VT323-Regular.ttf")
const NEON := Color(0.25, 1.0, 0.4)
const TOP_Y := 3.55
const LOW_Y := 2.15
const CRUSH_X := 2.7
const CRUSH_Z := 1.25
const PX := 0.15
const GLYPHS := {
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#"],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
}

var _t: float = 0.0
var _events: Array = []
var _done: bool = false
var _world: Node3D
var _cam: Camera3D
var _env: Environment
var _lamp_light: SpotLight3D
var _lamp_pivot: Node3D
var _lamp_bulb: StandardMaterial3D
var _neon_light: OmniLight3D
var _fill: SpotLight3D
var _intern: LabCharacter
var _lever: Node3D
var _letters: Array[Node3D] = []
var _letter_mats: Array[StandardMaterial3D] = []
var _targets: Array[Vector3] = []
var _ui: CanvasLayer
var _black: ColorRect
var _tagline: Label
var _hum: AudioStreamPlayer
var _sounds: Dictionary = {}
var _mat_cache: Dictionary = {}
var _swing: float = 0.4
var _cam_tw: Tween

func _ready() -> void:
	for n in ["hum", "hit", "explosion", "splat", "buzzer", "click", "whoosh", "beep", "arm", "step"]:
		_sounds[n] = load("res://assets/sfx/%s.wav" % n)
	_world = Node3D.new()
	add_child(_world)
	_build_env()
	_build_room()
	_build_lamp()
	_build_sign()
	_build_intern()
	_build_ui()
	_schedule()

func _mat(tex_name: String, tile: float = 0.5, tint: Color = Color.WHITE, world_space: bool = true) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [tex_name, tile, tint.to_html(), world_space]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	var dir := PH_TEX + tex_name + "/"
	if ResourceLoader.exists(dir + "diff.jpg"):
		m.albedo_texture = load(dir + "diff.jpg")
	m.albedo_color = tint
	if ResourceLoader.exists(dir + "nor.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(dir + "nor.jpg")
	if ResourceLoader.exists(dir + "arm.jpg"):
		var arm: Texture2D = load(dir + "arm.jpg")
		m.ao_enabled = true
		m.ao_texture = arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = arm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.metallic = 1.0
	elif ResourceLoader.exists(dir + "rough.jpg"):
		m.roughness_texture = load(dir + "rough.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world_space
	m.uv1_scale = Vector3.ONE * tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[key] = m
	return m

func _box(size: Vector3, pos: Vector3, material: Material, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	(parent if parent else _world).add_child(mi)
	return mi

func _prop(id: String, pos: Vector3, yaw_deg: float = 0.0, scale_f: float = 1.0, parent: Node = null) -> Node3D:
	var p := PH_MOD + id + "/" + id + ".gltf"
	if not ResourceLoader.exists(p):
		return null
	var n: Node3D = load(p).instantiate()
	(parent if parent else _world).add_child(n)
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	n.scale = Vector3.ONE * scale_f
	return n

func _build_env() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0, 0, 0)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.5, 0.48, 0.42)
	_env.ambient_light_energy = 0.0
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.1
	_env.ssao_enabled = true
	_env.ssao_radius = 1.2
	_env.ssao_intensity = 2.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_bloom = 0.05
	_env.glow_hdr_threshold = 1.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.22, 0.21, 0.18)
	_env.fog_density = 0.012
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 0.8
	_env.adjustment_contrast = 1.12
	we.environment = _env
	_world.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_world.add_child(_cam)
	_cam.position = Vector3(0.0, 2.5, 9.6)
	_cam.look_at(Vector3(0.3, 2.0, 0.0), Vector3.UP)
	_cam.make_current()

func _build_room() -> void:
	var w := 14.0
	var h := 9.0
	_box(Vector3(w, 0.2, 12.0), Vector3(0, -0.1, 2.0), _mat("damaged_concrete_floor", 0.35))
	_box(Vector3(w, h, 0.4), Vector3(0, h * 0.5, -2.2), _mat("concrete_wall_006", 0.35, Color(0.62, 0.6, 0.56)))
	_box(Vector3(0.4, h, 12.0), Vector3(-w * 0.5, h * 0.5, 2.0), _mat("factory_brick", 0.4))
	_box(Vector3(0.4, h, 12.0), Vector3(w * 0.5, h * 0.5, 2.0), _mat("factory_brick", 0.4))
	_box(Vector3(w, 1.2, 0.5), Vector3(0, 0.6, -1.95), _mat("green_metal_rust", 0.6))
	_box(Vector3(w, 0.15, 0.55), Vector3(0, 1.25, -1.93), _mat("rusty_metal", 0.8))
	var pipe_mat := _mat("rusty_metal_02", 1.5)
	for y in [5.4, 5.85]:
		var pipe := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.15
		cm.bottom_radius = 0.15
		cm.height = w
		pipe.mesh = cm
		pipe.material_override = pipe_mat
		pipe.rotation_degrees.z = 90.0
		pipe.position = Vector3(0, y, -1.75)
		_world.add_child(pipe)
	_prop("power_box_01", Vector3(-4.8, 2.0, -1.98), 0.0, 1.6)
	_prop("fire_alarm", Vector3(4.6, 2.3, -1.98), 0.0, 1.6)
	_prop("metal_tool_chest", Vector3(-3.4, 0.0, -1.55), 0.0, 1.15)
	_prop("wooden_crate_02", Vector3(-2.7, 0.0, -1.5), 12.0, 1.15)
	var clutter := [["barrel_03", -5.6, -0.9, 0], ["barrel_03", -4.9, -1.2, 40], ["worn_metal_rack", 5.7, -1.0, -90],
		["wooden_crate_01", -5.4, 0.6, 15], ["cement_bag", -4.6, 0.2, 30], ["trashbag", 5.3, 1.1, 0],
		["metal_trash_can", 4.9, 0.0, 0], ["old_tyre", -3.9, -1.3, 0], ["cardboard_box_01", 4.2, -1.3, 12],
		["WetFloorSign_01", -2.2, 1.8, 25], ["propane_tank", 5.8, 2.6, 0], ["hand_truck", -5.6, 2.6, 60]]
	for c in clutter:
		_prop(c[0], Vector3(c[1], 0.0, c[2]), c[3], 1.15)
	_lever = Node3D.new()
	_world.add_child(_lever)
	_lever.position = Vector3(CRUSH_X + 1.15, 0.0, 0.6)
	_box(Vector3(0.45, 0.95, 0.35), Vector3(0, 0.475, 0), _mat("green_metal_rust", 1.4, Color(0.8, 0.8, 0.75)), _lever)
	_box(Vector3(0.5, 0.06, 0.4), Vector3(0, 0.97, 0), _mat("rusty_metal", 1.2), _lever)
	var arm := Node3D.new()
	arm.name = "Arm"
	_lever.add_child(arm)
	arm.position = Vector3(0, 1.0, 0)
	arm.rotation_degrees.z = 35.0
	_box(Vector3(0.06, 0.6, 0.06), Vector3(0, 0.3, 0), _mat("rusty_metal_02", 2.0, Color.WHITE, false), arm)
	var knob := _box(Vector3(0.14, 0.14, 0.14), Vector3(0, 0.62, 0), null, arm)
	var km := StandardMaterial3D.new()
	km.albedo_color = Color(0.55, 0.06, 0.04)
	km.roughness = 0.4
	knob.material_override = km

func _build_lamp() -> void:
	_lamp_pivot = Node3D.new()
	_world.add_child(_lamp_pivot)
	_lamp_pivot.position = Vector3(0.7, 8.6, 1.0)
	var cord := _box(Vector3(0.025, 2.3, 0.025), Vector3(0, -1.15, 0), _mat("rusty_metal", 2.0), _lamp_pivot)
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop("hanging_industrial_lamp", Vector3(0, -2.3, 0), 0.0, 1.4, _lamp_pivot)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	bulb.mesh = sm
	_lamp_bulb = StandardMaterial3D.new()
	_lamp_bulb.albedo_color = Color(0.1, 0.09, 0.08)
	_lamp_bulb.emission_enabled = true
	_lamp_bulb.emission = Color(1.0, 0.8, 0.5)
	_lamp_bulb.emission_energy_multiplier = 0.0
	bulb.material_override = _lamp_bulb
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp_pivot.add_child(bulb)
	bulb.position = Vector3(0, -2.62, 0)
	_lamp_light = SpotLight3D.new()
	_lamp_light.light_color = Color(1.0, 0.8, 0.55)
	_lamp_light.light_energy = 0.0
	_lamp_light.spot_range = 14.0
	_lamp_light.spot_angle = 46.0
	_lamp_light.spot_attenuation = 0.55
	_lamp_light.shadow_enabled = true
	_lamp_pivot.add_child(_lamp_light)
	_lamp_light.position = Vector3(0, -2.75, 0)
	_lamp_light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_fill = SpotLight3D.new()
	_fill.light_color = Color(1.0, 0.85, 0.65)
	_fill.light_energy = 0.0
	_fill.spot_range = 14.0
	_fill.spot_angle = 24.0
	_fill.shadow_enabled = true
	_world.add_child(_fill)
	_fill.position = Vector3(0.6, 6.5, 7.0)
	_fill.look_at(Vector3(0.4, 2.6, -1.8), Vector3.UP)
	_neon_light = OmniLight3D.new()
	_neon_light.light_color = NEON
	_neon_light.light_energy = 0.0
	_neon_light.omni_range = 7.0
	_world.add_child(_neon_light)
	_neon_light.position = Vector3(0.0, 2.6, 1.6)

func _build_sign() -> void:
	var rows := [["GRIM", TOP_Y, 0.98], ["INTERN", LOW_Y, 0.98]]
	for r in rows:
		var word: String = r[0]
		var step: float = r[2]
		var x0 := -step * float(word.length() - 1) * 0.5
		for i in word.length():
			var x := x0 + step * float(i)
			if word == "INTERN":
				x += 0.25
			_targets.append(Vector3(x, r[1], 0.0))
			_letters.append(_make_letter(word[i]))
	for i in _letters.size():
		_letters[i].position = _targets[i] + Vector3(0, 8.0, 0)

func _make_letter(ch: String) -> Node3D:
	var root := Node3D.new()
	_world.add_child(root)
	var m: StandardMaterial3D = _mat("rusty_metal", 2.6, Color(0.62, 0.58, 0.55), false).duplicate()
	m.emission_enabled = true
	m.emission = NEON
	m.emission_energy_multiplier = 0.0
	_letter_mats.append(m)
	var rows: Array = GLYPHS[ch]
	for y in rows.size():
		var line: String = rows[y]
		var x := 0
		while x < line.length():
			if line[x] != "#":
				x += 1
				continue
			var run := 0
			while x + run < line.length() and line[x + run] == "#":
				run += 1
			var cx := (float(x) + float(run) * 0.5 - 2.5) * PX
			var cy := (3.0 - float(y)) * PX
			_box(Vector3(float(run) * PX, PX, 0.24), Vector3(cx, cy, 0.0), m, root)
			x += run
	var link_mat := _mat("rusty_metal", 2.0, Color(0.7, 0.66, 0.6), false)
	for side in [-0.22, 0.22]:
		for k in 26:
			var link := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.022
			tor.outer_radius = 0.05
			tor.rings = 8
			tor.ring_segments = 6
			link.mesh = tor
			link.material_override = link_mat
			root.add_child(link)
			link.position = Vector3(side, 0.62 + float(k) * 0.085, 0.0)
			link.rotation_degrees = Vector3(90.0, 90.0 * float(k % 2), 0.0)
	return root

func _build_intern() -> void:
	_intern = LabCharacter.new()
	_intern.sex = "male"
	_intern.hat = "hardhat"
	_intern.suit_color = Color("8a7a4e")
	_world.add_child(_intern)
	_intern.position = Vector3(-7.4, 0.0, 0.9)
	_intern.rotation.y = PI * 0.5

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	_tagline = Label.new()
	_tagline.text = "G R I M   I N T E R N\nWe're hiring. Again."
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tagline.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tagline.anchor_top = 0.855
	_tagline.anchor_bottom = 0.99
	_tagline.add_theme_constant_override("line_spacing", -4)
	_tagline.add_theme_font_override("font", FONT)
	_tagline.add_theme_font_size_override("font_size", 40)
	_tagline.add_theme_color_override("font_color", Color(0.88, 0.86, 0.78))
	_tagline.add_theme_color_override("font_outline_color", Color.BLACK)
	_tagline.add_theme_constant_override("outline_size", 10)
	_tagline.modulate.a = 0.0
	root.add_child(_tagline)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_black)

func _sfx(n: String, db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _sounds[n]
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p

func _at(time: float, f: Callable) -> void:
	_events.append([time, f])

func _schedule() -> void:
	_at(0.0, _start_hum)
	_at(0.15, func(): create_tween().tween_property(_black, "color:a", 0.0, 0.5))
	_at(0.7, _lamp_on)
	_at(1.3, _walk_in)
	_at(3.35, _pull_lever)
	for i in 9:
		_at(3.85 + 0.26 * float(i), _drop.bind(i))
	_at(4.3, _proud)
	_at(6.55, _creak)
	_at(7.05, _crush)
	_at(7.5, func(): _hum.stop())
	_at(8.25, _neon_on)
	_at(9.15, _show_tagline)
	_at(10.6, func(): create_tween().tween_property(_black, "color:a", 1.0, 0.6))
	_at(11.3, _finish)
	_events.sort_custom(func(a, b): return a[0] < b[0])
	var ct := create_tween()
	ct.tween_interval(0.6)
	ct.tween_callback(_cam_to.bind(Vector3(0.3, 2.2, 8.4), Vector3(0.4, 1.9, 0.0), 3.2))

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	while not _events.is_empty() and _events[0][0] <= _t:
		var e: Array = _events.pop_front()
		(e[1] as Callable).call()
		if _done:
			return
	_lamp_pivot.rotation.z = sin(_t * 2.1) * 0.035 * _swing
	_lamp_pivot.rotation.x = cos(_t * 1.7) * 0.02 * _swing
	_swing = maxf(_swing - delta * 0.12, 0.2)

func _input(event: InputEvent) -> void:
	if _done:
		return
	var skip := false
	if event is InputEventKey and event.pressed and not event.echo:
		skip = true
	elif event is InputEventMouseButton and event.pressed:
		skip = true
	elif event is InputEventJoypadButton and event.pressed:
		skip = true
	if skip:
		get_viewport().set_input_as_handled()
		_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	if _hum:
		_hum.stop()
	finished.emit()

func _cam_to(pos: Vector3, look: Vector3, dur: float, trans: Tween.TransitionType = Tween.TRANS_SINE) -> void:
	if _cam_tw:
		_cam_tw.kill()
	var from := _cam.transform
	var to := Transform3D(Basis(), pos).looking_at(look, Vector3.UP)
	_cam_tw = create_tween()
	_cam_tw.tween_method(func(k: float): _cam.transform = from.interpolate_with(to, k), 0.0, 1.0, dur).set_trans(trans).set_ease(Tween.EASE_IN_OUT if trans == Tween.TRANS_SINE else Tween.EASE_OUT)

func _start_hum() -> void:
	var s: AudioStreamWAV = _sounds["hum"].duplicate()
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(s.get_length() * s.mix_rate)
	_hum = AudioStreamPlayer.new()
	_hum.stream = s
	_hum.volume_db = -30.0
	add_child(_hum)
	_hum.play()
	create_tween().tween_property(_hum, "volume_db", -9.0, 1.2)

func _set_lamp(e: float) -> void:
	_lamp_light.light_energy = e
	_lamp_bulb.emission_energy_multiplier = e * 0.9
	_env.ambient_light_energy = e * 0.03
	_fill.light_energy = e * 1.1

func _lamp_on() -> void:
	_sfx("click", -2.0)
	var tw := create_tween()
	var seq := [[9.0, 0.06], [0.0, 0.1], [7.0, 0.04], [0.0, 0.22], [10.0, 0.05], [1.0, 0.07], [8.0, 0.0]]
	for s in seq:
		tw.tween_callback(_set_lamp.bind(s[0]))
		tw.tween_callback(_sfx.bind("click", -10.0, randf_range(0.8, 1.3)))
		tw.tween_interval(s[1])

func _walk_in() -> void:
	_intern.play_loop("Walk")
	var tw := create_tween()
	tw.tween_property(_intern, "position", Vector3(CRUSH_X + 1.15, 0.0, CRUSH_Z), 2.0)
	tw.tween_callback(_intern.play_loop.bind("Idle"))
	tw.tween_property(_intern, "rotation:y", PI, 0.15)
	var st := create_tween()
	for k in 5:
		st.tween_interval(0.38)
		st.tween_callback(_sfx.bind("step", -14.0, randf_range(0.9, 1.1)))

func _pull_lever() -> void:
	_intern.play_action("Interact", 0.1, 1.3)
	var arm: Node3D = _lever.get_node("Arm")
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(_sfx.bind("click", 0.0, 0.7))
	tw.tween_property(arm, "rotation_degrees:z", -35.0, 0.12).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(_sfx.bind("buzzer", -6.0, 0.8))
	tw.tween_callback(_sfx.bind("whoosh", -4.0, 0.6))
	_cam_to(Vector3(0.9, 2.3, 8.6), Vector3(0.6, 2.4, 0.0), 1.4)

func _drop(i: int) -> void:
	var l := _letters[i]
	var target := _targets[i]
	if i == _letters.size() - 1:
		return
	var tw := create_tween()
	tw.tween_property(l, "position", target - Vector3(0, 0.16, 0), 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_clang.bind(i))
	tw.tween_property(l, "position", target + Vector3(0, 0.05, 0), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position", target, 0.2).set_trans(Tween.TRANS_SINE)
	l.rotation_degrees.z = randf_range(-6.0, 6.0)
	tw.parallel().tween_property(l, "rotation_degrees:z", randf_range(-1.5, 1.5), 0.6).set_trans(Tween.TRANS_ELASTIC)

func _clang(i: int) -> void:
	_sfx("hit", 0.0, 0.55 + float(i) * 0.03)
	_sfx("arm", -10.0, 0.6)
	Fx.shake(0.1)
	_swing = minf(_swing + 0.25, 1.4)
	Fx.sparks(_world, _letters[i].position + Vector3(0, 0.75, 0.1))

func _proud() -> void:
	var tw := create_tween()
	tw.tween_property(_intern, "rotation:y", -PI * 0.5, 0.15)
	tw.tween_callback(_intern.play_loop.bind("Walk"))
	tw.tween_property(_intern, "position", Vector3(CRUSH_X, 0.0, CRUSH_Z), 0.8)
	tw.tween_callback(_intern.play_loop.bind("Idle"))
	tw.tween_property(_intern, "rotation:y", 0.0, 0.2)
	tw.tween_callback(_intern.play_action.bind("Yes"))
	tw.tween_interval(1.2)
	tw.tween_callback(_intern.play_loop.bind("Idle_FoldArms"))

func _creak() -> void:
	var l: Node3D = _letters[_letters.size() - 1]
	l.position = _targets[_letters.size() - 1] + Vector3(0.0, 4.2, 0.0)
	_sfx("arm", -2.0, 0.45)
	_sfx("click", -4.0, 0.5)
	_cam_to(Vector3(2.0, 1.6, 6.6), Vector3(2.6, 2.4, 0.5), 0.45)
	var tw := create_tween()
	tw.tween_property(l, "rotation_degrees:z", 9.0, 0.12)
	tw.tween_property(l, "rotation_degrees:z", -4.0, 0.2)
	tw.tween_property(l, "position:y", l.position.y + 0.35, 0.12)

func _crush() -> void:
	var l: Node3D = _letters[_letters.size() - 1]
	_sfx("whoosh", 0.0, 0.7)
	var hit := Vector3(CRUSH_X, 2.2, CRUSH_Z - 0.1)
	var rest := Vector3(CRUSH_X - 0.85, 0.22, CRUSH_Z + 0.05)
	var tw := create_tween()
	tw.tween_property(l, "position", hit, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(l, "rotation_degrees", Vector3(-8.0, -6.0, 4.0), 0.16)
	tw.tween_callback(_impact)
	tw.tween_property(l, "position", rest, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(l, "rotation_degrees", Vector3(-90.0, 84.0, 0.0), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_slam)
	tw.tween_property(l, "position:y", rest.y + 0.12, 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", rest.y, 0.1).set_ease(Tween.EASE_IN)

func _slam() -> void:
	_sfx("hit", 2.0, 0.35)
	_sfx("splat", 0.0, 0.8)
	Fx.blood(_world, Vector3(CRUSH_X - 0.9, 0.3, CRUSH_Z), 50)
	Fx.shake(0.6)
	_swing = 2.4

func _impact() -> void:
	_intern.die("Death01")
	_sfx("hit", 4.0, 0.4)
	_sfx("explosion", -6.0, 0.7)
	Fx.blood(_world, _intern.global_position + Vector3(0, 1.2, 0.1), 70)
	Fx.shake(0.9)
	_swing = 2.2
	_fly_hat()
	var ct := create_tween()
	ct.tween_interval(0.2)
	ct.tween_callback(_cam_to.bind(Vector3(1.6, 1.7, 5.4), Vector3(2.0, 0.3, 0.9), 0.9, Tween.TRANS_EXPO))
	var tw := create_tween()
	tw.tween_callback(_set_lamp.bind(2.0))
	tw.tween_interval(0.06)
	tw.tween_callback(_set_lamp.bind(8.0))

func _fly_hat() -> void:
	for att in _intern.skeleton.find_children("*", "BoneAttachment3D", false, false):
		(att as Node3D).visible = false
	if not ResourceLoader.exists("res://assets/hats/hat_hardhat.glb"):
		return
	var hat: Node3D = load("res://assets/hats/hat_hardhat.glb").instantiate()
	_world.add_child(hat)
	var start := _intern.global_position + Vector3(0.2, 1.4, 0.2)
	hat.position = start
	var tw := create_tween()
	var dur := 0.9
	tw.tween_method(func(k: float):
		hat.position = start + Vector3(-2.4 * k, 2.6 * k - 4.2 * k * k + 0.0, 1.4 * k)
		hat.position.y = maxf(hat.position.y, 0.08)
		hat.rotation = Vector3(k * 9.0, k * 5.0, k * 7.0), 0.0, 1.0, dur)
	tw.tween_callback(_sfx.bind("click", -2.0, 0.6))
	tw.tween_property(hat, "position:x", hat.position.x - 3.1, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(hat, "rotation", Vector3(PI, 0.4, 0.0), 0.7)

func _set_neon(e: float) -> void:
	for i in _letter_mats.size() - 1:
		_letter_mats[i].emission_energy_multiplier = e
	_neon_light.light_energy = e * 1.4

func _neon_on() -> void:
	_cam_to(Vector3(0.6, 2.1, 8.8), Vector3(0.7, 1.9, 0.0), 1.3)
	var tw := create_tween()
	var seq := [[1.0, 0.05], [0.0, 0.12], [1.3, 0.04], [0.0, 0.06], [0.5, 0.05], [0.0, 0.2], [1.4, 0.0]]
	for s in seq:
		tw.tween_callback(_set_neon.bind(s[0]))
		if s[0] > 0.0:
			tw.tween_callback(_sfx.bind("beep", -12.0, 0.5))
		tw.tween_interval(s[1])
	tw.tween_callback(_sfx.bind("buzzer", -14.0, 1.6))
	tw.tween_callback(_dead_letter)
	tw.tween_property(_lamp_light, "light_energy", 5.0, 0.8)

func _dead_letter() -> void:
	if _done:
		return
	var m: StandardMaterial3D = _letter_mats[_letter_mats.size() - 1]
	var on := m.emission_energy_multiplier < 0.1
	m.emission_energy_multiplier = randf_range(0.3, 0.9) if on else 0.0
	if on:
		Fx.sparks(_world, _letters[_letters.size() - 1].position + Vector3(0.3, 0.2, 0.3))
		_sfx("click", -14.0, randf_range(1.4, 2.0))
	var tw := create_tween()
	tw.tween_interval(randf_range(0.05, 0.12) if on else randf_range(0.15, 0.6))
	tw.tween_callback(_dead_letter)

func _show_tagline() -> void:
	_sfx("click", -4.0, 1.2)
	var tw := create_tween()
	tw.tween_property(_tagline, "modulate:a", 1.0, 0.35)
