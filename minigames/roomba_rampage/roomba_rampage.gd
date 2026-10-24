extends ArenaMinigame3D
## Roomba Rampage: robot vacuums with spinning saw blades bounce around the floor
## in straight lines, reflecting off the walls. A floor hatch glows red 1.5 s
## before each new roomba rolls out (one every 6 s). Touching a blade shreds you.
## Some roombas leave oil that makes you slide. SPACE = dive roll (0.3 s
## invulnerable, 2 s cooldown). Last subject standing wins, else the round ends
## after 45 s; placement is survival order.

const TIME_LIMIT: float = 45.0
const SPAWN_EVERY: float = 6.0
const HATCH_WARN: float = 1.5
const MAX_ROOMBAS: int = 9
const BODY_R: float = 0.5
const BLADE_R: float = 0.62
const KILL_R: float = 0.82
const ARM_AGE: float = 0.4
const DIVE_CD: float = 2.0
const DIVE_T: float = 0.3
const DIVE_SPEED: float = 10.5
const INVULN: float = 0.34
const WALK_SPEED: float = 4.4
const OIL_SPEED: float = 1.9
const OIL_R: float = 0.26
const OIL_HIT_R: float = 0.4
const OIL_LIFE: float = 2.8
const OIL_EVERY: float = 0.3
const OIL_MAX: int = 48
const BODY_TINTS: Array = [Color(0.88, 0.9, 0.92), Color(0.95, 0.62, 0.52), Color(0.72, 0.9, 0.72), Color(0.92, 0.86, 0.56)]
const OIL_TINT: Color = Color(0.98, 0.72, 0.28)

enum St { COUNTDOWN, RUN, DONE }

class Roomba:
	var id: int = 0
	var node: Node3D
	var blade: Node3D
	var led_mat: StandardMaterial3D
	var pos: Vector3 = Vector3.ZERO
	var vel: Vector3 = Vector3.ZERO
	var oily: bool = false
	var age: float = 0.0
	var armed: bool = false
	var oil_acc: float = 0.0
	var phase: float = 0.0
	var bounce_cd: float = 0.0

class Hatch:
	var root: Node3D
	var door_l: MeshInstance3D
	var door_r: MeshInstance3D
	var light: OmniLight3D
	var glow: StandardMaterial3D
	var t: float = 0.0
	var open: float = 0.0
	var closing: bool = false

var st: St = St.COUNTDOWN
var clock: float = 0.0
var elim_order: Array = []
var roombas: Array[Roomba] = []
var hatches: Array[Hatch] = []
var puddles: Array[Dictionary] = []
var dashes: Dictionary = {}
var dive_ready: Dictionary = {}
var invuln_until: Dictionary = {}
var last_dive: Dictionary = {}
var oil_state: Dictionary = {}
var warn_times: Array[float] = [0.0, 0.7]
var next_regular: float = 4.5
var next_hid: int = 0
var pending_spawns: int = 0

var rx0: float = 0.62
var rx1: float = W - 0.62
var rz0: float = 0.62
var rz1: float = D - 0.62

var _bot: Dictionary = {}
var _body_mats: Dictionary = {}
var _steel: StandardMaterial3D
var _hz: StandardMaterial3D
var _oil_mat: StandardMaterial3D
var _dark: StandardMaterial3D
var _rubber: StandardMaterial3D
var _blade_mesh_cache: Dictionary = {}
var _hum: AudioStreamPlayer
var _space_down: bool = false
var _ended: bool = false
var _sync_t: float = 0.0
var _time_t: float = 0.0

var _big: Label
var _hint: Label
var _timer_label: Label
var _alive_label: Label
var _roll_label: Label

func begin() -> void:
	setup_arena()
	_steel = _blade_material()
	_hz = _hazard_mat()
	_dark = _plain(Color(0.09, 0.09, 0.1), 0.45, 0.5)
	_rubber = _plain(Color(0.06, 0.06, 0.06), 0.9)
	_oil_mat = _make_oil_mat()
	_build_dressing()
	spawn_players(_spawns())
	for id in players:
		var p: LabPlayer3D = players[id]
		p.speed = WALK_SPEED
		p.input_enabled = false
		p.bot_brain = _bot_brain.bind(id)
		dive_ready[id] = 0.0
		invuln_until[id] = -1.0
		last_dive[id] = -100.0
		oil_state[id] = {"t": 0.0, "slide": Vector3.ZERO, "free": Vector3.ZERO}
		if p.is_bot:
			_bot[id] = {"react": randf_range(0.22, 0.48), "aware": randf() < 0.6, "noise": randf_range(0.12, 0.35),
				"dive_p": randf_range(0.55, 0.95), "think": 0.0, "dir": Vector3.ZERO, "snaps": [], "wander": randf() * TAU}
	camera.fov = 43.0
	camera.position = Vector3(W * 0.5, 10.2, D + 4.6)
	camera.look_at(Vector3(W * 0.5, 0.0, D * 0.5 + 0.4), Vector3.UP)
	_build_hud()
	_start_hum()
	if NetworkManager.is_server():
		_run.call_deferred()

func _spawns() -> Array:
	var a: Array = []
	var n: int = NetworkManager.players.size()
	for i in n:
		var ang: float = TAU * float(i) / float(maxi(n, 1)) + 0.4
		a.append(Vector3(W * 0.5 + cos(ang) * 4.2, 0.0, D * 0.5 + sin(ang) * 2.4))
	return a

func _plain(col: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m

func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.4)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

func _cyl(r: float, h: float, m: Material, pos: Vector3, rot: Vector3, parent: Node, seg: int = 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = seg
	mi.mesh = cm
	mi.material_override = m
	mi.rotation_degrees = rot
	mi.position = pos
	parent.add_child(mi)
	return mi

func _torus(inner: float, outer: float, m: Material, pos: Vector3, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 24
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

func _hazard_mat() -> StandardMaterial3D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.045
	noise.seed = 5
	for y in n:
		for x in n:
			var stripe := int(floor(float(x + y) / 16.0)) % 2
			var g := 0.7 + noise.get_noise_2d(x, y) * 0.4
			var c := Color(0.8, 0.58, 0.08) if stripe == 0 else Color(0.06, 0.06, 0.05)
			img.set_pixel(x, y, Color(c.r * g, c.g * g, c.b * g))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 1.4
	return m

func _blade_material() -> StandardMaterial3D:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	noise.seed = 21
	for y in n:
		for x in n:
			var dx := (float(x) - n * 0.5) / (n * 0.5)
			var dy := (float(y) - n * 0.5) / (n * 0.5)
			var r := sqrt(dx * dx + dy * dy)
			var v := 0.66 + 0.07 * sin(r * 160.0 + noise.get_noise_2d(x, y) * 3.0) + noise.get_noise_2d(x * 2.0, y * 2.0) * 0.08
			if r > 0.84:
				v += 0.16
			if r < 0.22:
				v *= 0.55
			if r < 0.07:
				v = 0.05
			var rust := noise.get_noise_2d(x * 0.7 + 300.0, y * 0.7) > 0.42 and r > 0.3
			var c := Color(v, v * 1.01, v * 1.04)
			if rust:
				c = Color(v * 0.62, v * 0.36, v * 0.22)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.metallic = 0.3
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission_texture = m.albedo_texture
	m.emission = Color(0.55, 0.6, 0.62)
	m.emission_energy_multiplier = 0.2
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _blade_mesh(r: float, teeth: int, thick: float) -> ArrayMesh:
	var key := "%s|%d|%s" % [r, teeth, thick]
	if _blade_mesh_cache.has(key):
		return _blade_mesh_cache[key]
	var pts: Array[Vector2] = []
	for i in teeth:
		var a0: float = TAU * float(i) / float(teeth)
		var a1: float = TAU * (float(i) + 0.7) / float(teeth)
		pts.append(Vector2(cos(a0), sin(a0)) * r)
		pts.append(Vector2(cos(a1), sin(a1)) * r * 0.85)
	var n := pts.size()
	var stool := SurfaceTool.new()
	stool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		var z: float = thick * 0.5 * side
		for i in n:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[(i + 1) % n]
			for q in [Vector2.ZERO, p0, p1]:
				var v2: Vector2 = q
				stool.set_normal(Vector3(0, 0, side))
				stool.set_uv(Vector2(v2.x / r * 0.5 + 0.5, v2.y / r * 0.5 + 0.5))
				stool.add_vertex(Vector3(v2.x, v2.y, z))
	for i in n:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % n]
		var nm := Vector3((p0 + p1).x, (p0 + p1).y, 0.0).normalized()
		var quad := [Vector3(p0.x, p0.y, thick * 0.5), Vector3(p1.x, p1.y, thick * 0.5), Vector3(p1.x, p1.y, -thick * 0.5),
			Vector3(p0.x, p0.y, thick * 0.5), Vector3(p1.x, p1.y, -thick * 0.5), Vector3(p0.x, p0.y, -thick * 0.5)]
		for v3 in quad:
			stool.set_normal(nm)
			stool.set_uv(Vector2(0.98, 0.5))
			stool.add_vertex(v3)
	var mesh := stool.commit()
	_blade_mesh_cache[key] = mesh
	return mesh

func _make_oil_mat() -> StandardMaterial3D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.07
	noise.seed = 9
	for y in n:
		for x in n:
			var dx: float = (float(x) - n * 0.5) / (n * 0.5)
			var dy: float = (float(y) - n * 0.5) / (n * 0.5)
			var d: float = sqrt(dx * dx + dy * dy)
			var edge: float = 0.58 + noise.get_noise_2d(x * 1.6, y * 1.6) * 0.5
			var a: float = smoothstep(edge + 0.08, edge - 0.08, d)
			var shade: float = 0.8 + noise.get_noise_2d(x + 50.0, y) * 0.5
			img.set_pixel(x, y, Color(0.075 * shade, 0.048 * shade, 0.026 * shade, a * 0.78))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.15
	m.metallic_specular = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _body_mat(tint: Color) -> StandardMaterial3D:
	var key := tint.to_html()
	if _body_mats.has(key):
		return _body_mats[key]
	var m: StandardMaterial3D = mat("blue_metal_plate", 1.6, tint).duplicate()
	m.uv1_world_triplanar = false
	m.metallic = 0.45
	_body_mats[key] = m
	return m

func _sparker(parent: Node3D, pos: Vector3, dir: Vector3, amount: int = 26) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = amount
	gp.lifetime = 0.42
	gp.randomness = 0.5
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 40.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -11.0, 0)
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	gp.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.014, 0.12, 0.014)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.72, 0.3)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.6, 0.2)
	sm.emission_energy_multiplier = 4.0
	bm.material = sm
	gp.draw_pass_1 = bm
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(gp)
	gp.position = pos
	gp.emitting = true
	return gp

func _build_dressing() -> void:
	var d := Node3D.new()
	d.name = "Dressing"
	world.add_child(d)
	for s in [[Vector3(W + 0.6, 0.012, 0.3), Vector3(W * 0.5, 0.006, -0.15)], [Vector3(W + 0.6, 0.012, 0.3), Vector3(W * 0.5, 0.006, D + 0.15)],
			[Vector3(0.3, 0.012, D), Vector3(-0.15, 0.006, D * 0.5)], [Vector3(0.3, 0.012, D), Vector3(W + 0.15, 0.006, D * 0.5)]]:
		box(s[0], s[1], _hz, d)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var stain := StandardMaterial3D.new()
	stain.albedo_color = Color(0.1, 0.07, 0.04, 0.4)
	stain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stain.roughness = 0.5
	for i in 9:
		var r: float = rng.randf_range(0.5, 1.3)
		_cyl(r, 0.004, stain, Vector3(rng.randf_range(1.0, W - 1.0), 0.006, rng.randf_range(1.0, D - 1.0)), Vector3.ZERO, d, 20)
	var led_green := _glow(Color(0.3, 1.0, 0.4), 2.5)
	for x in [2.4, 6.2, 11.0, 14.0]:
		box(Vector3(1.3, 0.34, 0.8), Vector3(x, 0.17, -0.7), mat("blue_metal_plate", 1.2, Color(0.75, 0.75, 0.78)), d)
		box(Vector3(0.9, 0.05, 0.1), Vector3(x, 0.36, -0.45), led_green, d)
		box(Vector3(0.7, 0.1, 0.4), Vector3(x, 0.39, -0.8), _dark, d)
	prop("WetFloorSign_01", Vector3(1.0, 0.0, D - 0.5), 25.0, 1.25, d)
	prop("WetFloorSign_01", Vector3(W - 1.3, 0.0, 0.55), -30.0, 1.25, d)
	prop("hanging_industrial_lamp", Vector3(W * 0.5, 6.2, D * 0.5), 0.0, 1.4, d)
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.8, 0.55)
	fill.light_energy = 1.6
	fill.omni_range = 11.0
	d.add_child(fill)
	fill.position = Vector3(W * 0.5, 4.5, D * 0.5)

func _loop_stream() -> AudioStream:
	var s: AudioStream = load("res://assets/sfx/hum.wav")
	if s is AudioStreamWAV:
		var w: AudioStreamWAV = s.duplicate()
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		return w
	return s

func _start_hum() -> void:
	_hum = AudioStreamPlayer.new()
	_hum.stream = _loop_stream()
	_hum.volume_db = -14.0
	_hum.pitch_scale = 1.35
	add_child(_hum)
	_hum.play()

func _style(l: Label, size: int, c: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)

func _center_label(size: int, y: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.anchor_top = y - 0.1
	l.anchor_bottom = y + 0.1
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 12)
	hud.add_child(l)
	return l

func _build_hud() -> void:
	hud_title("ROOMBA RAMPAGE  ·  dodge the saw vacuums")
	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-120, 10)
	_timer_label.size = Vector2(100, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(_timer_label, 26, Color("ffd34a"))
	_timer_label.text = "%d s" % int(TIME_LIMIT)
	hud.add_child(_timer_label)
	_alive_label = Label.new()
	_alive_label.position = Vector2(16, 40)
	_style(_alive_label, 18, Color("e8e2c8"))
	hud.add_child(_alive_label)
	_roll_label = Label.new()
	_roll_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_roll_label.position = Vector2(16, -56)
	_roll_label.size = Vector2(300, 30)
	_style(_roll_label, 22, Color("8fe36a"))
	hud.add_child(_roll_label)
	_big = _center_label(84, 0.3)
	_hint = _center_label(24, 0.88)
	_hint.text = "WASD  MOVE   ·   SPACE  DIVE ROLL\na new roomba rolls out every 6 s · oil makes you slide"
	_hint.add_theme_color_override("font_color", Color("e8e2c8"))
	_refresh_alive()

func _refresh_alive() -> void:
	if _alive_label:
		_alive_label.text = "subjects alive: %d" % alive_ids().size()

func _fold(v: float, lo: float, hi: float) -> float:
	var span: float = hi - lo
	var u: float = fposmod(v - lo, span * 2.0)
	return lo + (u if u <= span else span * 2.0 - u)

func _reflect(pos: Vector3, vel: Vector3, t: float) -> Vector3:
	return Vector3(_fold(pos.x + vel.x * t, rx0, rx1), 0.0, _fold(pos.z + vel.z * t, rz0, rz1))

func _build_roomba(tint: Color, oily: bool) -> Roomba:
	var r := Roomba.new()
	var root := Node3D.new()
	world.add_child(root)
	r.node = root
	r.oily = oily
	var bm: StandardMaterial3D = _body_mat(tint)
	_cyl(BODY_R, 0.2, bm, Vector3(0, 0.12, 0), Vector3.ZERO, root, 30)
	_cyl(0.43, 0.04, _dark, Vector3(0, 0.235, 0), Vector3.ZERO, root, 30)
	_torus(0.43, 0.58, _rubber, Vector3(0, 0.1, 0), root)
	var led_col: Color = Color(1.0, 0.65, 0.1) if oily else Color(1.0, 0.18, 0.12)
	r.led_mat = _glow(led_col, 3.0)
	_torus(0.29, 0.34, r.led_mat, Vector3(0, 0.262, 0), root)
	_cyl(0.07, 0.03, r.led_mat, Vector3(0, 0.262, 0.0), Vector3.ZERO, root, 12)
	box(Vector3(0.34, 0.07, 0.06), Vector3(0, 0.15, 0.55), _dark, root)
	box(Vector3(0.1, 0.05, 0.06), Vector3(-0.17, 0.15, 0.56), _glow(Color(0.5, 0.9, 1.0), 1.5), root)
	box(Vector3(0.1, 0.05, 0.06), Vector3(0.17, 0.15, 0.56), _glow(Color(0.5, 0.9, 1.0), 1.5), root)
	if oily:
		box(Vector3(0.22, 0.05, 0.1), Vector3(0, 0.07, -0.56), _plain(Color(0.9, 0.55, 0.1), 0.4, 0.2), root)
	_cyl(0.07, 0.17, mat("rusty_metal_02", 3.0, Color(0.55, 0.52, 0.5)), Vector3(0, 0.33, 0), Vector3.ZERO, root, 12)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.42, 0)
	root.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = _blade_mesh(BLADE_R, 12, 0.04)
	mi.material_override = _steel
	mi.rotation_degrees.x = 90.0
	pivot.add_child(mi)
	_cyl(BLADE_R * 0.24, 0.07, mat("rusty_metal_02", 3.0, Color(0.55, 0.52, 0.5)), Vector3.ZERO, Vector3.ZERO, pivot, 12)
	r.blade = pivot
	_sparker(root, Vector3(0, 0.08, 0.5), Vector3(0, 1, 1), 9)
	r.phase = randf() * 0.8
	return r

func _find_roomba(rid: int) -> Roomba:
	for r in roombas:
		if r.id == rid:
			return r
	return null

func _armed_snapshot() -> Array:
	var a: Array = []
	for r in roombas:
		if r.armed or r.age > ARM_AGE - 0.25:
			a.append([r.pos, r.vel])
	return a

@rpc("authority", "call_local", "reliable")
func _rpc_hatch(hid: int, pos: Vector3, vel: Vector3, oily: bool, tint: int) -> void:
	var h := Hatch.new()
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	world.add_child(root)
	h.root = root
	box(Vector3(1.7, 0.04, 1.7), Vector3(0, 0.02, 0), mat("rusty_metal_02", 1.6, Color(0.7, 0.68, 0.66)), root)
	h.glow = _glow(Color(1.0, 0.1, 0.05), 0.6)
	box(Vector3(1.4, 0.05, 1.4), Vector3(0, 0.026, 0), h.glow, root)
	h.door_l = box(Vector3(0.7, 0.05, 1.4), Vector3(-0.35, 0.06, 0), _hz, root)
	h.door_r = box(Vector3(0.7, 0.05, 1.4), Vector3(0.35, 0.06, 0), _hz, root)
	h.light = OmniLight3D.new()
	h.light.light_color = Color(1.0, 0.12, 0.06)
	h.light.light_energy = 0.0
	h.light.omni_range = 4.2
	root.add_child(h.light)
	h.light.position = Vector3(0, 0.6, 0)
	hatches.append(h)
	Fx.sfx("arm", Vector3(pos.x, 0.0, pos.z), -4.0, 0.8)
	get_tree().create_timer(HATCH_WARN).timeout.connect(_spawn_roomba.bind(hid, pos, vel, oily, tint, h))

func _spawn_roomba(hid: int, pos: Vector3, vel: Vector3, oily: bool, tint: int, h: Hatch) -> void:
	h.closing = true
	h.t = 0.0
	var r: Roomba = _build_roomba(OIL_TINT if oily else BODY_TINTS[tint % BODY_TINTS.size()], oily)
	r.id = hid
	r.pos = Vector3(pos.x, 0.0, pos.z)
	r.vel = vel
	r.node.position = Vector3(pos.x, -0.4, pos.z)
	r.node.rotation.y = atan2(vel.x, vel.z)
	roombas.append(r)
	Fx.sfx("whoosh", r.pos, -2.0, 0.7)
	Fx.sfx("hit", r.pos, -6.0, 0.6)

func _update_hatches(delta: float) -> void:
	for i in range(hatches.size() - 1, -1, -1):
		var h: Hatch = hatches[i]
		h.t += delta
		if not h.closing:
			var blink: float = 0.5 + 0.5 * sin(h.t * 16.0)
			h.light.light_energy = 1.5 + blink * 6.0
			h.glow.emission_energy_multiplier = 0.6 + blink * 2.4
			h.open = clampf((h.t - (HATCH_WARN - 0.6)) / 0.5, 0.0, 1.0)
			var shake: float = 0.012 * sin(h.t * 60.0) * (1.0 - h.open)
			h.door_l.position.x = -0.35 - h.open * 0.7 + shake
			h.door_r.position.x = 0.35 + h.open * 0.7 - shake
		else:
			var k: float = clampf(h.t / 1.2, 0.0, 1.0)
			h.light.light_energy = lerpf(5.0, 0.0, k)
			h.glow.emission_energy_multiplier = lerpf(2.0, 0.2, k)
			var close: float = clampf((h.t - 0.5) / 0.4, 0.0, 1.0)
			h.door_l.position.x = lerpf(-1.05, -0.35, close)
			h.door_r.position.x = lerpf(1.05, 0.35, close)
			if h.t > 1.6:
				h.root.queue_free()
				hatches.remove_at(i)

func _update_roombas(delta: float) -> void:
	for r in roombas:
		r.age += delta
		r.pos += r.vel * delta
		r.bounce_cd -= delta
		var bounced: bool = false
		if r.pos.x < rx0:
			r.pos.x = rx0 + (rx0 - r.pos.x)
			r.vel.x = absf(r.vel.x)
			bounced = true
		elif r.pos.x > rx1:
			r.pos.x = rx1 - (r.pos.x - rx1)
			r.vel.x = -absf(r.vel.x)
			bounced = true
		if r.pos.z < rz0:
			r.pos.z = rz0 + (rz0 - r.pos.z)
			r.vel.z = absf(r.vel.z)
			bounced = true
		elif r.pos.z > rz1:
			r.pos.z = rz1 - (r.pos.z - rz1)
			r.vel.z = -absf(r.vel.z)
			bounced = true
		if bounced and r.bounce_cd <= 0.0 and r.age > 0.5:
			r.bounce_cd = 0.4
			Fx.sparks(world, r.pos + Vector3(0, 0.3, 0))
			Fx.sfx("click", r.pos, -12.0, 0.6)
		r.armed = r.age > ARM_AGE
		var rise: float = clampf(r.age / ARM_AGE, 0.0, 1.0)
		r.node.position = Vector3(r.pos.x, lerpf(-0.4, 0.0, rise * rise), r.pos.z)
		r.node.rotation.y = lerp_angle(r.node.rotation.y, atan2(r.vel.x, r.vel.z), 1.0 - exp(-9.0 * delta))
		r.blade.rotation.y += 24.0 * delta
		var on: bool = fmod(r.age + r.phase, 0.8) < 0.4
		r.led_mat.emission_energy_multiplier = 3.5 if on else 0.3
		if r.oily and r.armed:
			r.oil_acc += delta
			if r.oil_acc >= OIL_EVERY:
				r.oil_acc = 0.0
				_drop_oil(r.pos)

func _drop_oil(at: Vector3) -> void:
	for k in 2:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var sz: float = OIL_R * 2.0 * (1.0 if k == 0 else randf_range(0.35, 0.55))
		pm.size = Vector2(sz, sz)
		mi.mesh = pm
		var m: StandardMaterial3D = _oil_mat.duplicate()
		mi.material_override = m
		var off := Vector3.ZERO if k == 0 else Vector3(randf_range(-0.28, 0.28), 0.0, randf_range(-0.28, 0.28))
		mi.position = Vector3(at.x + off.x + randf_range(-0.08, 0.08), 0.012 + randf() * 0.004, at.z + off.z + randf_range(-0.08, 0.08))
		mi.rotation.y = randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		puddles.append({"node": mi, "t": 0.0, "mat": m, "main": k == 0})
	while puddles.size() > OIL_MAX:
		var old: Dictionary = puddles.pop_front()
		var on: Node3D = old.node
		on.queue_free()

func _update_puddles(delta: float) -> void:
	for i in range(puddles.size() - 1, -1, -1):
		var pd: Dictionary = puddles[i]
		var t: float = float(pd.t) + delta
		pd.t = t
		var m: StandardMaterial3D = pd.mat
		var k: float = clampf(t / 0.15, 0.0, 1.0) * clampf((OIL_LIFE - t) / 1.4, 0.0, 1.0)
		m.albedo_color = Color(1, 1, 1, k)
		if t >= OIL_LIFE:
			var n: Node3D = pd.node
			n.queue_free()
			puddles.remove_at(i)

func _on_oil(pos: Vector3) -> bool:
	for pd in puddles:
		if not pd.main:
			continue
		var n: MeshInstance3D = pd.node
		if float(pd.t) < OIL_LIFE - 0.4 and Vector2(n.position.x - pos.x, n.position.z - pos.z).length() < OIL_HIT_R:
			return true
	return false

func _clamp_to_bounds(p: LabPlayer3D) -> void:
	p.position.x = clampf(p.position.x, 0.3, W - 0.3)
	p.position.z = clampf(p.position.z, 0.3, D - 0.3)

func _update_movers(delta: float) -> void:
	for id in dashes.keys():
		var d: Dictionary = dashes[id]
		var p: LabPlayer3D = players[id]
		if not p.alive:
			dashes.erase(id)
			continue
		var dir: Vector3 = d.dir
		p.position += dir * DIVE_SPEED * delta
		_clamp_to_bounds(p)
		d.t = float(d.t) - delta
		if float(d.t) <= 0.0:
			dashes.erase(id)
			if p.is_local_human() and st == St.RUN:
				p.input_enabled = true
	for id in players:
		var p: LabPlayer3D = players[id]
		if not p.alive or not p.is_multiplayer_authority() or dashes.has(id):
			continue
		var os: Dictionary = oil_state[id]
		var slick: bool = _on_oil(p.position)
		var timer: float = float(os.t)
		if slick:
			if timer <= 0.0:
				os.slide = Vector3(os.free) * 0.95
			timer = 0.55
		else:
			timer = maxf(timer - delta, 0.0)
		os.t = timer
		if timer > 0.0:
			p.speed = OIL_SPEED
			var sl: Vector3 = os.slide
			sl *= exp(-0.8 * delta)
			p.position += sl * delta
			_clamp_to_bounds(p)
			os.slide = sl
		else:
			p.speed = WALK_SPEED
			os.slide = Vector3.ZERO
			os.free = p.velocity
		oil_state[id] = os

func _process(delta: float) -> void:
	if not world:
		return
	_update_hatches(delta)
	_update_puddles(delta)
	if st == St.RUN:
		clock += delta
		_handle_input()
		_update_movers(delta)
		_update_hud_roll()
	if st != St.COUNTDOWN:
		_update_roombas(delta)
	if st == St.RUN and NetworkManager.is_server():
		_server_tick(delta)

func _update_hud_roll() -> void:
	var me := local_player()
	if not me or not _roll_label:
		return
	if not me.alive:
		_roll_label.text = ""
		return
	var left: float = DIVE_CD - (clock - float(last_dive.get(me.peer_id, -100.0)))
	if left > 0.0:
		_roll_label.text = "ROLL  %.1f" % left
		_roll_label.add_theme_color_override("font_color", Color("a09a80"))
	else:
		_roll_label.text = "ROLL  READY  [SPACE]"
		_roll_label.add_theme_color_override("font_color", Color("8fe36a"))

func _handle_input() -> void:
	var me := local_player()
	if not me or not me.alive:
		return
	var down := Input.is_physical_key_pressed(KEY_SPACE)
	if down and not _space_down:
		var dir := Vector3(me.velocity.x, 0.0, me.velocity.z)
		if dir.length() < 0.5:
			dir = _fwd(me)
		dir = dir.normalized()
		if NetworkManager.is_server():
			_try_dive(multiplayer.get_unique_id(), dir)
		else:
			_rpc_press.rpc_id(1, dir)
	_space_down = down

@rpc("any_peer", "reliable")
func _rpc_press(dir: Vector3) -> void:
	if NetworkManager.is_server():
		_try_dive(multiplayer.get_remote_sender_id(), dir)

func _fwd(p: LabPlayer3D) -> Vector3:
	return Vector3(sin(p._target_yaw), 0.0, cos(p._target_yaw))

func _try_dive(id: int, dir: Vector3) -> void:
	if st != St.RUN or not players.has(id) or not players[id].alive:
		return
	if clock < float(dive_ready[id]) or dashes.has(id):
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.1:
		d = _fwd(players[id])
	d = d.normalized()
	dive_ready[id] = clock + DIVE_CD
	invuln_until[id] = clock + INVULN
	_rpc_dive.rpc(id, d)

@rpc("authority", "call_local", "reliable")
func _rpc_dive(id: int, dir: Vector3) -> void:
	var p: LabPlayer3D = players[id]
	if not p.alive:
		return
	last_dive[id] = clock
	p.face(dir)
	p.body.play_action("Roll", 0.05, 1.7)
	Fx.sfx("whoosh", p.position, -4.0, 1.2)
	if p.is_multiplayer_authority():
		dashes[id] = {"dir": dir, "t": DIVE_T}
		if p.is_local_human():
			p.input_enabled = false

func _server_tick(delta: float) -> void:
	_time_t -= delta
	if _time_t <= 0.0:
		_time_t = 1.0
		_rpc_sync_time.rpc(maxf(TIME_LIMIT - clock, 0.0))
	if not warn_times.is_empty():
		if clock >= warn_times[0]:
			warn_times.pop_front()
			_warn_spawn()
	elif clock >= next_regular:
		next_regular += SPAWN_EVERY
		_warn_spawn()
	for id in alive_ids():
		if clock < float(invuln_until[id]):
			continue
		var pos: Vector3 = players[id].position
		for r in roombas:
			if not r.armed:
				continue
			if Vector2(r.pos.x - pos.x, r.pos.z - pos.z).length() < KILL_R:
				elim_order.append(id)
				_rpc_die.rpc(id, pos, r.vel.normalized())
				break
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.5
		var data: Array = []
		for r in roombas:
			data.append([r.id, r.pos, r.vel])
		_rpc_sync_roombas.rpc(data)

func _warn_spawn() -> void:
	if roombas.size() + pending_spawns >= MAX_ROOMBAS:
		return
	var alive := alive_ids()
	var best: Vector3 = Vector3(W * 0.5, 0.0, D * 0.5)
	var best_d: float = -1.0
	for i in 10:
		var c := Vector3(randf_range(1.6, W - 1.6), 0.0, randf_range(1.6, D - 1.6))
		var md: float = 99.0
		for id in alive:
			md = minf(md, c.distance_to(players[id].position))
		for r in roombas:
			md = minf(md, c.distance_to(r.pos) * 0.7)
		for h in hatches:
			md = minf(md, c.distance_to(h.root.position))
		if md > best_d:
			best_d = md
			best = c
	var ang: float = float(randi() % 4) * PI * 0.5 + PI * 0.25 + randf_range(-0.38, 0.38)
	var spd: float = 2.9 + minf(clock / TIME_LIMIT, 1.0) * 1.1 + randf_range(-0.2, 0.3)
	var oily: bool = randf() < 0.4
	pending_spawns += 1
	get_tree().create_timer(HATCH_WARN + 0.05).timeout.connect(func() -> void: pending_spawns -= 1)
	next_hid += 1
	_rpc_hatch.rpc(next_hid, best, Vector3(cos(ang), 0.0, sin(ang)) * spd, oily, randi() % BODY_TINTS.size())

@rpc("authority", "unreliable_ordered")
func _rpc_sync_roombas(data: Array) -> void:
	for e in data:
		var r: Roomba = _find_roomba(int(e[0]))
		if r:
			r.pos = e[1]
			r.vel = e[2]

@rpc("authority", "call_local", "reliable")
func _rpc_sync_time(time_left: float) -> void:
	_timer_label.text = "%d s" % int(ceil(time_left))

@rpc("authority", "call_local", "reliable")
func _rpc_die(id: int, at: Vector3, dir: Vector3) -> void:
	if not elim_order.has(id):
		elim_order.append(id)
	dashes.erase(id)
	var p: LabPlayer3D = players[id]
	if p.is_local_human():
		p.input_enabled = false
	eliminate(id, "Death01")
	Fx.blood(world, at + Vector3(0, 0.5, 0), 150)
	Fx.sparks(world, at + Vector3(0, 0.4, 0))
	Fx.sparks(world, at + Vector3(0, 0.9, 0))
	Fx.sfx("splat", at, 5.0, 0.75)
	Fx.sfx("hit", at, 4.0, 0.55)
	Fx.shake(0.9)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.2, 0.1)
	fl.light_energy = 9.0
	fl.omni_range = 4.0
	world.add_child(fl)
	fl.global_position = at + Vector3(0, 0.6, 0)
	var ft := fl.create_tween()
	ft.tween_property(fl, "light_energy", 0.0, 0.35)
	ft.tween_callback(fl.queue_free)
	var b: LabCharacter = p.body
	var land: Vector3 = dir * randf_range(0.8, 1.3)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(b, "position:x", land.x, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "position:z", land.z, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var up := create_tween()
	up.tween_property(b, "position:y", randf_range(0.5, 0.9), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	up.tween_property(b, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	up.tween_callback(func() -> void:
		Fx.blood(world, p.position + land + Vector3(0, 0.3, 0), 60))
	_refresh_alive()
	var me := local_player()
	if me and me.peer_id == id:
		_big_local("SHREDDED", "ff4040", 1.4, 72)

func _big_local(text: String, hex: String, hold: float, size: int = 84) -> void:
	_big.text = text
	_big.add_theme_font_size_override("font_size", size)
	_big.add_theme_color_override("font_color", Color(hex))
	_big.modulate.a = 1.0
	if hold > 0.0:
		var tw := create_tween()
		tw.tween_interval(hold)
		tw.tween_property(_big, "modulate:a", 0.0, 0.4)

@rpc("authority", "call_local", "reliable")
func _rpc_big(text: String, hex: String, hold: float) -> void:
	_big_local(text, hex, hold)

@rpc("authority", "call_local", "reliable")
func _rpc_start() -> void:
	st = St.RUN
	clock = 0.0
	for id in players:
		var p: LabPlayer3D = players[id]
		if p.is_local_human():
			p.input_enabled = true
	_big_local("RUN!", "8fe36a", 0.7)
	Fx.sfx("beep", null, -4.0, 1.4)
	var th := create_tween()
	th.tween_interval(6.0)
	th.tween_property(_hint, "modulate:a", 0.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_end(timeout: bool) -> void:
	st = St.DONE
	for id in players:
		players[id].input_enabled = false
	var alive := alive_ids()
	var txt := "TIME!" if timeout else "LAST ONE STANDING"
	if not timeout and alive.size() == 1:
		txt = "%s SURVIVES" % players[alive[0]].display_name
	_big_local(txt, "e2c84b", 0.0, 60)
	Fx.sfx("buzzer", null, -6.0, 1.3)

func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	for n in ["3", "2", "1"]:
		_rpc_big.rpc(n, "e8e2c8", 0.0)
		Fx.sfx("click")
		await get_tree().create_timer(0.8).timeout
	_rpc_start.rpc()
	var floor_alive: int = 1 if players.size() > 1 else 0
	while clock < TIME_LIMIT and alive_ids().size() > floor_alive:
		await get_tree().process_frame
	_rpc_end.rpc(clock >= TIME_LIMIT)
	await get_tree().create_timer(2.4).timeout
	if not _ended:
		_ended = true
		finished.emit(survival_placement(elim_order))

func _bot_brain(delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	if st != St.RUN or dashes.has(id):
		return Vector3.ZERO
	var b: Dictionary = _bot[id]
	b.think = float(b.think) - delta
	if float(b.think) > 0.0:
		return b.dir
	b.think = randf_range(0.08, 0.15)
	var snaps: Array = b.snaps
	snaps.append({"t": clock, "r": _armed_snapshot()})
	var react: float = b.react
	while snaps.size() > 1 and float(snaps[1].t) <= clock - react:
		snaps.pop_front()
	var snap: Dictionary = snaps[0]
	var age: float = clock - float(snap.t)
	var aware: bool = b.aware
	var noise: float = b.noise
	var preds: Array = []
	var taus: Array[float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.85, 1.0, 1.2]
	for e in snap.r:
		var series: Array = []
		var off := Vector3(randf_range(-noise, noise), 0.0, randf_range(-noise, noise))
		for tau in taus:
			var rp: Vector3
			if aware:
				rp = _reflect(e[0], e[1], age + tau)
			else:
				rp = Vector3(e[0]) + Vector3(e[1]) * (age + tau)
			series.append(rp + off)
		preds.append(series)
	var spd: float = p.speed
	var dirs: Array[Vector3] = [Vector3.ZERO]
	for k in 8:
		var a: float = TAU * float(k) / 8.0
		dirs.append(Vector3(cos(a), 0.0, sin(a)))
	var cur: Vector3 = b.dir
	var best_i: int = 0
	var best_c: float = INF
	var center := Vector3(W * 0.5, 0.0, D * 0.5)
	for i in dirs.size():
		var d: Vector3 = dirs[i]
		var cost: float = randf() * 0.12
		var q_end: Vector3 = p.position
		for ti in taus.size():
			var tau: float = taus[ti]
			var q: Vector3 = p.position + d * spd * tau
			q.x = clampf(q.x, 0.35, W - 0.35)
			q.z = clampf(q.z, 0.35, D - 0.35)
			q_end = q
			for series in preds:
				var rp: Vector3 = series[ti]
				var dist: float = Vector2(q.x - rp.x, q.z - rp.z).length()
				if dist < 1.75:
					cost += pow(1.75 - dist, 2.0) * (2.3 - tau)
			if ti < 5 and _on_oil(q):
				cost += 0.9
		var edge: float = 0.0
		edge += maxf(1.1 - q_end.x, 0.0) + maxf(q_end.x - (W - 1.1), 0.0)
		edge += maxf(1.0 - q_end.z, 0.0) + maxf(q_end.z - (D - 1.0), 0.0)
		cost += edge * 0.6 + Vector2(q_end.x - center.x, q_end.z - center.z).length() * 0.03
		if d.is_equal_approx(cur):
			cost -= 0.2
		if d == Vector3.ZERO:
			cost += 0.1
		if cost < best_c:
			best_c = cost
			best_i = i
	var chosen: Vector3 = dirs[best_i]
	if clock >= float(dive_ready[id]) and not preds.is_empty() and randf() < float(b.dive_p):
		var imminent: float = 99.0
		var worst: Vector3 = Vector3.ZERO
		var stay_end: Vector3 = p.position + chosen * spd * 0.3
		for series in preds:
			for ti in 3:
				var rp: Vector3 = series[ti]
				var dist: float = Vector2(stay_end.x - rp.x, stay_end.z - rp.z).length()
				if dist < imminent:
					imminent = dist
					worst = rp
		if imminent < 0.95:
			var away: Vector3 = Vector3(p.position.x - worst.x, 0.0, p.position.z - worst.z)
			var dive_dir: Vector3 = chosen if chosen != Vector3.ZERO else away
			if dive_dir.length() < 0.1:
				dive_dir = center - p.position
			_try_dive(id, dive_dir.normalized())
			b.dir = Vector3.ZERO
			return Vector3.ZERO
	b.dir = chosen
	return chosen
