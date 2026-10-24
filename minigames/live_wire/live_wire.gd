extends ArenaMinigame3D
## Live Wire: a flooded generator room and one crackling high-voltage battery.
## The holder passes it by touching another subject or with SPACE within reach;
## no tag-backs for 0.8 s. A hidden fuse (8 to 16 s) runs down and electrocutes
## whoever holds it, then a fresh battery lands on a random survivor. Last subject
## standing wins; at the time limit the current holder fries too. Survival order.

const TIME_LIMIT: float = 55.0
const START_DELAY: float = 1.6
const FUSE_MIN: float = 8.0
const FUSE_MAX: float = 16.0
const RESPAWN_T: float = 1.9
const TOUCH_R: float = 0.92
const PASS_R: float = 1.6
const NO_BACK_T: float = 0.8
const MIN_HOLD: float = 0.22
const BASE_SPEED: float = 4.6
const HOLD_SPEED: float = 5.05
const ZAP_T: float = 0.95
const ARC_COL: Color = Color(0.55, 0.8, 1.0)
const CHAR: Color = Color(0.07, 0.06, 0.05)

class ArmPose extends SkeletonModifier3D:
	var poses: Dictionary = {}
	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for b in poses:
			sk.set_bone_pose_rotation(b, poses[b])

static var _carry_lib: AnimationLibrary
static var _carry_poses: Dictionary = {}

var holder: int = -1
var elim_order: Array = []
var bots: Dictionary = {}
var _no_back_id: int = -1
var _no_back_until: float = 0.0
var _hold_since: float = 0.0
var _srv_fuse: float = 0.0
var _fuse_left: float = 0.0
var _wait_t: float = 0.0
var _game_t: float = 0.0
var _clock: float = 0.0
var _running: bool = false
var _ending: bool = false
var _done: bool = false
var _space_down: bool = false
var _battery: Node3D
var _bat_light: OmniLight3D
var _bat_hum: AudioStreamPlayer3D
var _bat_glow: StandardMaterial3D
var _buzz_ph: float = 0.0
var _click_t: float = 0.0
var _carry_mods: Dictionary = {}
var _zap_fx: Dictionary = {}
var _arc_mesh: ImmediateMesh
var _arc_mat: StandardMaterial3D
var _arc_t: float = 0.0
var _pass_arc: Array = []
var _cables: Array = []
var _flicker: Array = []
var _hum_stream: AudioStreamWAV
var _char_mat: StandardMaterial3D
var _flash: ColorRect
var _hud_time: Label
var _hud_status: Label
var _hud_board: Label
var _hud_help: Label
var _hud_big: Label

func begin() -> void:
	setup_arena(false)
	build_chamber("hangar_concrete_floor", "dark_brick_wall", "rusty_metal")
	_tune_light()
	camera.fov = 44.0
	camera.position = Vector3(W * 0.5, 9.0, D + 4.6)
	camera.look_at(Vector3(W * 0.5, 0.0, D * 0.5 - 0.5), Vector3.UP)
	_hum_stream = (load("res://assets/sfx/hum.wav") as AudioStreamWAV).duplicate()
	_hum_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_hum_stream.loop_end = int(_hum_stream.get_length() * _hum_stream.mix_rate)
	_build_room()
	spawn_players(_spawns())
	for id in players:
		var p: LabPlayer3D = players[id]
		p.speed = BASE_SPEED
		p.bot_brain = _bot_brain.bind(id)
		bots[id] = {"t": randf_range(0.0, 0.3), "dir": Vector3.ZERO, "react": 0.0, "freeze": 0.0, "aim": Vector3.INF,
			"target": -1, "tid": -1, "tp": Vector3.ZERO, "pass": randf_range(0.12, 0.35), "wander": Vector3.INF}
	_build_fx()
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.4
			n.light_color = Color(0.75, 0.85, 1.0)
	env.ambient_light_color = Color(0.5, 0.56, 0.6)
	env.ambient_light_energy = 0.55
	env.tonemap_exposure = 1.05
	env.fog_density = 0.016
	env.fog_light_color = Color(0.18, 0.21, 0.23)
	env.adjustment_saturation = 0.74
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 1.0
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	var fl: MeshInstance3D = world.get_node("Chamber").get_child(0)
	var wet: StandardMaterial3D = mat("hangar_concrete_floor", 0.35, Color(0.6, 0.62, 0.62)).duplicate()
	wet.roughness = 0.42
	fl.material_override = wet

func _spawns() -> Array:
	var pts: Array = [Vector3(4.0, 0, 3.0), Vector3(12.0, 0, 7.0), Vector3(12.0, 0, 3.0), Vector3(4.0, 0, 7.0),
		Vector3(8.0, 0, 2.2), Vector3(8.0, 0, 7.8), Vector3(1.6, 0, 5.0), Vector3(14.4, 0, 5.0)]
	var a: Array = []
	for i in NetworkManager.players.size():
		a.append(pts[i % pts.size()])
	return a

func _lm(tex: String, tile: float, tint: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = mat(tex, tile, tint).duplicate()
	m.uv1_world_triplanar = false
	return m

func _place(id: String, pos: Vector3, yaw: float, s: float, parent: Node) -> Node3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.position = pos
	pivot.rotation_degrees.y = yaw
	var n := prop(id, Vector3.ZERO, 0.0, s, pivot)
	if n == null:
		return pivot
	var ab := _model_aabb(n)
	n.position = Vector3(-ab.get_center().x, -ab.position.y, -ab.get_center().z) * s
	return pivot

func _model_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D()
		var c: Node = mi
		while c != n and c != null:
			if c is Node3D:
				xf = (c as Node3D).transform * xf
			c = c.get_parent()
		var m: MeshInstance3D = mi
		var b: AABB = xf * m.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

func _tube(pts: Array, radius: float, m: Material, parent: Node) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var len := a.distance_to(b)
		if len < 0.001:
			continue
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = len + radius
		cm.radial_segments = 8
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = m
		parent.add_child(mi)
		var y := (b - a) / len
		var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var x := y.cross(ref).normalized()
		mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)

func _build_room() -> void:
	var r := Node3D.new()
	r.name = "GeneratorRoom"
	world.add_child(r)
	var rust := mat("rusty_metal", 1.0)
	var rubber := mat("rubber_tiles", 3.0, Color(0.1, 0.1, 0.11))
	box(Vector3(W + 6.0, 0.28, 0.2), Vector3(W * 0.5, 6.3, 5.0), rust, r)
	box(Vector3(W + 6.0, 0.06, 0.5), Vector3(W * 0.5, 6.13, 5.0), mat("metal_grate_rusty", 1.4), r)
	_main_generator(Vector3(10.4, 0.0, -1.95), r)
	_place("portable_generator", Vector3(-1.8, 0, 3.7), 90.0, 1.7, r)
	_place("portable_generator", Vector3(W + 1.8, 0, 6.0), -90.0, 1.7, r)
	_place("portable_generator", Vector3(11.4, 0, D + 1.7), 200.0, 1.5, r)
	_place("old_military_compressor", Vector3(-1.75, 0, 9.3), 0.0, 1.3, r)
	_place("old_military_compressor", Vector3(W + 1.75, 0, 9.0), 180.0, 1.3, r)
	_place("utility_box_01", Vector3(5.0, 0, -2.55), 0.0, 1.2, r)
	_place("utility_box_01", Vector3(5.72, 0, -2.55), 0.0, 1.2, r)
	_place("portable_welding_cart", Vector3(-1.7, 0, 6.6), 80.0, 1.0, r)
	_place("tool_cart", Vector3(W + 1.9, 0, 2.7), -100.0, 1.0, r)
	_place("propane_tank", Vector3(12.7, 0, -0.95), 0.0, 1.3, r)
	_place("propane_tank", Vector3(13.15, 0, -1.2), 0.0, 1.3, r)
	_place("metal_jerrycan", Vector3(8.35, 0, -0.85), 30.0, 1.3, r)
	_place("metal_jerrycan", Vector3(7.85, 0, -0.55), -20.0, 1.3, r)
	_place("oil_tin", Vector3(8.7, 0, -0.45), 70.0, 1.4, r)
	_place("metal_toolbox", Vector3(4.1, 0, -1.8), 15.0, 1.3, r)
	_place("WetFloorSign_01", Vector3(-0.6, 0, 8.0), 40.0, 1.3, r)
	_place("WetFloorSign_01", Vector3(W + 0.6, 0, 0.9), -30.0, 1.3, r)
	_place("WetFloorSign_01", Vector3(5.5, 0, D + 0.9), 10.0, 1.3, r)
	_place("korean_fire_extinguisher_01", Vector3(W + 2.55, 0, 7.6), -90.0, 1.3, r)
	_place("can_rusted", Vector3(-0.5, 0, 2.6), 0.0, 1.4, r)
	_place("can_rusted", Vector3(W + 0.5, 0, 7.2), 0.0, 1.4, r)
	_place("barrel_03", Vector3(W + 1.9, 0, D + 1.0), 20.0, 1.15, r)
	prop("modular_electric_cables", Vector3(0.0, 1.7, -2.7), 0.0, 1.5, r)
	prop("modular_electric_cables", Vector3(14.8, 2.5, -2.7), 0.0, 1.3, r)
	prop("modular_electric_cables", Vector3(-2.7, 2.2, 5.0), 90.0, 1.5, r)
	prop("modular_electric_cables", Vector3(W + 2.7, 2.2, 4.4), -90.0, 1.5, r)
	prop("modular_pipes", Vector3(-2.62, 1.35, 1.2), 90.0, 1.0, r)
	prop("power_box_01", Vector3(W + 2.78, 2.0, 2.0), -90.0, 1.6, r)
	prop("security_light", Vector3(6.6, 4.3, -2.72), 0.0, 1.6, r)
	var sec := OmniLight3D.new()
	sec.light_color = Color(0.8, 0.88, 1.0)
	sec.light_energy = 1.6
	sec.omni_range = 5.5
	r.add_child(sec)
	sec.position = Vector3(6.6, 3.9, -2.2)
	_caged_light(Vector3(5.6, 5.4, 5.0), 3.2, 0, r)
	_caged_light(Vector3(10.6, 5.4, 5.0), 3.0, -1, r)
	for s in [[Vector3(-2.75, 3.0, 7.8), 90.0, 1], [Vector3(W + 2.75, 3.0, 1.8), -90.0, -1]]:
		prop("industrial_caged_sconce", s[0], s[1], 1.5, r)
		var wl := OmniLight3D.new()
		wl.light_color = Color(1.0, 0.8, 0.55)
		wl.light_energy = 2.2
		wl.omni_range = 5.0
		r.add_child(wl)
		var sp: Vector3 = s[0]
		wl.position = sp + Vector3(0.45 if sp.x < 0.0 else -0.45, -0.1, 0.0)
		if int(s[2]) >= 0:
			_flicker.append({"l": wl, "base": 2.2, "t": 0.0, "kind": int(s[2])})
	_hang_cable(Vector3(8.0, 6.2, 5.0), Vector3(8.15, 0.32, 5.05), 0.35, true, r)
	_hang_cable(Vector3(2.6, 6.2, 5.0), Vector3(2.9, 1.5, 4.7), -0.25, false, r)
	_hang_cable(Vector3(13.4, 6.2, 5.0), Vector3(13.05, 0.85, 5.5), 0.3, true, r)
	_tube([Vector3(9.9, 0.05, -1.2), Vector3(9.6, 0.05, 0.6), Vector3(9.0, 0.05, 2.1), Vector3(8.7, 0.05, 3.4), Vector3(8.25, 0.05, 4.7)], 0.05, rubber, r)
	_tube([Vector3(8.7, 0.05, -1.25), Vector3(6.0, 0.05, -0.7), Vector3(2.5, 0.05, -0.9), Vector3(0.2, 0.05, -0.5), Vector3(-2.6, 0.05, -0.8)], 0.045, rubber, r)
	_tube([Vector3(W + 1.4, 0.05, 6.2), Vector3(W + 0.2, 0.05, 6.8), Vector3(15.0, 0.05, 7.6), Vector3(14.0, 0.05, 8.1)], 0.04, rubber, r)
	_tube([Vector3(-1.4, 0.05, 3.8), Vector3(0.4, 0.05, 3.2), Vector3(1.6, 0.05, 2.5), Vector3(2.3, 0.05, 1.9)], 0.04, rubber, r)
	box(Vector3(0.9, 0.02, 0.9), Vector3(14.8, 0.011, 0.95), mat("metal_grate_rusty", 2.0, Color(0.5, 0.5, 0.48)), r)
	_puddles(r)
	_grime(r)

func _hazard_mat() -> StandardMaterial3D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.045
	noise.seed = 3
	for y in n:
		for x in n:
			var stripe := int(floor(float(x + y) / 16.0)) % 2
			var g := 0.72 + noise.get_noise_2d(x, y) * 0.4
			var c := Color(0.82, 0.6, 0.08) if stripe == 0 else Color(0.06, 0.06, 0.05)
			img.set_pixel(x, y, Color(c.r * g, c.g * g, c.b * g))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.9
	return m

func _main_generator(c: Vector3, parent: Node) -> void:
	var g := Node3D.new()
	g.name = "MainGenerator"
	parent.add_child(g)
	var shell := mat("green_metal_rust", 0.6, Color(0.55, 0.62, 0.58))
	var steel := mat("rusty_metal_02", 1.2)
	var grate := mat("metal_grate_rusty", 1.6)
	box(Vector3(3.6, 0.25, 1.7), c + Vector3(0, 0.125, 0), steel, g)
	box(Vector3(3.2, 1.9, 1.4), c + Vector3(0, 1.2, 0), shell, g)
	box(Vector3(3.3, 0.1, 1.5), c + Vector3(0, 2.2, 0), steel, g)
	box(Vector3(3.22, 0.18, 1.42), c + Vector3(0, 0.4, 0), _hazard_mat(), g)
	for x in [-0.15, 0.85]:
		box(Vector3(0.8, 1.1, 0.04), c + Vector3(x, 1.2, 0.71), grate, g)
	box(Vector3(0.7, 0.55, 0.08), c + Vector3(-1.1, 1.55, 0.72), steel, g)
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(1.0, 0.7, 0.3)
	amber.emission_enabled = true
	amber.emission = Color(1.0, 0.62, 0.25)
	amber.emission_energy_multiplier = 2.5
	var red: StandardMaterial3D = amber.duplicate()
	red.emission = Color(1.0, 0.12, 0.08)
	red.albedo_color = Color(1.0, 0.2, 0.15)
	for i in 3:
		box(Vector3(0.1, 0.1, 0.03), c + Vector3(-1.32 + 0.22 * i, 1.68, 0.77), amber if i != 2 else red, g)
	var rl := OmniLight3D.new()
	rl.light_color = Color(1.0, 0.2, 0.1)
	rl.light_energy = 0.8
	rl.omni_range = 1.4
	g.add_child(rl)
	rl.position = c + Vector3(-0.88, 1.68, 0.95)
	_flicker.append({"l": rl, "base": 0.8, "t": 0.0, "kind": 3, "m": red, "e": 2.5})
	var ex := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.14
	cm.height = 1.3
	ex.mesh = cm
	ex.material_override = steel
	g.add_child(ex)
	ex.position = c + Vector3(1.2, 2.85, -0.35)
	var sign := Label3D.new()
	sign.text = "DANGER\nHIGH VOLTAGE"
	sign.font_size = 54
	sign.pixel_size = 0.0042
	sign.outline_size = 8
	sign.modulate = Color(0.92, 0.74, 0.16)
	sign.outline_modulate = Color(0.05, 0.04, 0.03)
	sign.shaded = true
	sign.double_sided = false
	g.add_child(sign)
	sign.position = c + Vector3(0.35, 1.93, 0.715)
	var hum := AudioStreamPlayer3D.new()
	hum.stream = _hum_stream
	hum.volume_db = -16.0
	hum.pitch_scale = 0.55
	hum.unit_size = 5.0
	g.add_child(hum)
	hum.position = c + Vector3(0, 1.0, 0)
	hum.autoplay = true

func _caged_light(pos: Vector3, energy: float, flick: int, parent: Node) -> void:
	prop("caged_hanging_light", pos, 0.0, 1.3, parent)
	var wire := box(Vector3(0.015, 6.2 - pos.y, 0.015), Vector3(pos.x, (6.2 + pos.y) * 0.5, pos.z), mat("rusty_metal_02", 1.0), parent)
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.55)
	l.light_energy = energy
	l.omni_range = 7.5
	l.omni_attenuation = 1.2
	parent.add_child(l)
	l.position = pos + Vector3(0, -0.85, 0)
	if flick >= 0:
		_flicker.append({"l": l, "base": energy, "t": 0.0, "kind": flick})

func _hang_cable(anchor: Vector3, tip: Vector3, bulge: float, live: bool, parent: Node) -> void:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.position = anchor
	var pts: Array = []
	for i in 9:
		var t := float(i) / 8.0
		var p := (tip - anchor) * t
		p.x += sin(t * PI) * bulge
		p.z += sin(t * PI) * bulge * 0.4
		pts.append(p)
	_tube(pts, 0.032, mat("rubber_tiles", 3.0, Color(0.1, 0.1, 0.11)), pivot)
	var copper := StandardMaterial3D.new()
	copper.albedo_color = Color(0.78, 0.45, 0.22)
	copper.metallic = 1.0
	copper.roughness = 0.35
	var end := tip - anchor
	for k in 4:
		var w := box(Vector3(0.009, 0.11, 0.009), end + Vector3(randf_range(-0.03, 0.03), -0.04, randf_range(-0.03, 0.03)), copper, pivot)
		w.rotation = Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	_cables.append({"pivot": pivot, "tip": end + Vector3(0, -0.08, 0), "t": randf_range(0.2, 1.0), "live": live, "ph": randf() * TAU, "flash": 0.0})

func _puddles(parent: Node) -> void:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.035
	noise.seed = 4
	for y in n:
		for x in n:
			var dx := (x - n * 0.5) / (n * 0.5)
			var dy := (y - n * 0.5) / (n * 0.5)
			var r := sqrt(dx * dx + dy * dy)
			var v := 1.0 - r + noise.get_noise_2d(x, y) * 0.55 + noise.get_noise_2d(x * 3.1, y * 3.1) * 0.12
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if v > 0.42 and r < 0.97 else 0.0))
	img.generate_mipmaps()
	var ripple := NoiseTexture2D.new()
	ripple.width = 256
	ripple.height = 256
	ripple.seamless = true
	ripple.as_normal_map = true
	ripple.bump_strength = 4.0
	var rn := FastNoiseLite.new()
	rn.frequency = 0.03
	ripple.noise = rn
	var water := StandardMaterial3D.new()
	water.albedo_texture = ImageTexture.create_from_image(img)
	water.albedo_color = Color(0.05, 0.06, 0.065)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	water.alpha_scissor_threshold = 0.5
	water.roughness = 0.04
	water.metallic = 0.15
	water.metallic_specular = 0.9
	water.normal_enabled = true
	water.normal_texture = ripple
	water.normal_scale = 0.15
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0))
	var soft := GradientTexture2D.new()
	soft.gradient = g
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	var spots := [[8.1, 5.0, 4.2, 3.0], [3.0, 7.6, 3.0, 2.2], [12.8, 2.6, 3.4, 2.4], [13.6, 8.2, 2.4, 1.8], [2.4, 1.8, 2.2, 1.8],
		[5.8, 2.8, 1.4, 1.0], [10.4, 7.4, 1.6, 1.2], [W + 1.2, 5.3, 1.6, 2.6], [7.0, -0.7, 2.6, 1.2], [-1.2, 1.6, 1.4, 1.8], [3.6, D + 1.4, 2.2, 1.2]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	for s in spots:
		var yaw := rng.randf() * TAU
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(s[2], s[3])
		mi.mesh = pm
		mi.material_override = water
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.position = Vector3(s[0], 0.012, s[1])
		mi.rotation.y = yaw
		var d := Decal.new()
		d.texture_albedo = soft
		d.size = Vector3(float(s[2]) * 1.7, 0.8, float(s[3]) * 1.7)
		d.modulate = Color(0.3, 0.32, 0.33)
		d.albedo_mix = 0.6
		d.cull_mask = 1
		d.rotation.y = yaw
		parent.add_child(d)
		d.position = Vector3(s[0], 0.1, s[1])

func _grime(parent: Node) -> void:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.seed = 23
	for y in n:
		for x in n:
			var dx := (x - n * 0.5) / (n * 0.5)
			var dy := (y - n * 0.5) / (n * 0.5)
			var v := 1.0 - sqrt(dx * dx + dy * dy) + noise.get_noise_2d(x, y) * 0.6
			img.set_pixel(x, y, Color(1, 1, 1, clampf((v - 0.25) * 2.0, 0.0, 0.85)))
	var tex := ImageTexture.create_from_image(img)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	for i in 18:
		var d := Decal.new()
		d.texture_albedo = tex
		var sz := rng.randf_range(1.2, 3.2)
		d.size = Vector3(sz, 1.0, sz * rng.randf_range(0.6, 1.0))
		d.modulate = Color(0.1, 0.11, 0.08) if i % 3 != 0 else Color(0.26, 0.16, 0.08)
		d.rotation.y = rng.randf() * TAU
		parent.add_child(d)
		d.position = Vector3(rng.randf_range(-1.0, W + 1.0), 0.1, rng.randf_range(-1.0, D + 1.5))
	for i in 6:
		var d := Decal.new()
		d.texture_albedo = tex
		d.size = Vector3(rng.randf_range(0.8, 2.0), 0.6, rng.randf_range(1.5, 3.5))
		d.modulate = Color(0.12, 0.1, 0.07)
		parent.add_child(d)
		d.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		d.position = Vector3(rng.randf_range(-2.0, W + 2.0), rng.randf_range(2.4, 4.4), -2.78)

func _build_fx() -> void:
	_battery = Node3D.new()
	_battery.name = "LiveBattery"
	world.add_child(_battery)
	var shell := _lm("blue_metal_plate", 4.0, Color(0.42, 0.55, 0.68))
	var cap := _lm("rusty_metal_02", 4.0, Color(0.35, 0.33, 0.3))
	var hz: StandardMaterial3D = _hazard_mat().duplicate()
	hz.uv1_world_triplanar = false
	hz.uv1_scale = Vector3.ONE * 3.0
	box(Vector3(0.4, 0.28, 0.26), Vector3.ZERO, shell, _battery)
	box(Vector3(0.42, 0.05, 0.28), Vector3(0, 0.16, 0), cap, _battery)
	box(Vector3(0.405, 0.07, 0.265), Vector3(0, -0.06, 0), hz, _battery)
	_bat_glow = StandardMaterial3D.new()
	_bat_glow.albedo_color = Color(0.4, 0.7, 1.0)
	_bat_glow.emission_enabled = true
	_bat_glow.emission = Color(0.45, 0.75, 1.0)
	_bat_glow.emission_energy_multiplier = 4.0
	box(Vector3(0.41, 0.025, 0.27), Vector3(0, 0.05, 0), _bat_glow, _battery)
	for s in [-1.0, 1.0]:
		var t := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.028
		cm.bottom_radius = 0.034
		cm.height = 0.07
		cm.radial_segments = 10
		t.mesh = cm
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(0.7, 0.12, 0.08) if s > 0.0 else Color(0.12, 0.12, 0.12)
		tm.metallic = 0.6
		tm.roughness = 0.4
		t.material_override = tm
		_battery.add_child(t)
		t.position = Vector3(s * 0.12, 0.215, 0.0)
	_bat_light = OmniLight3D.new()
	_bat_light.light_color = Color(0.45, 0.72, 1.0)
	_bat_light.light_energy = 2.5
	_bat_light.omni_range = 3.4
	_battery.add_child(_bat_light)
	_bat_light.position = Vector3(0, 0.25, 0.1)
	_bat_hum = AudioStreamPlayer3D.new()
	_bat_hum.stream = _hum_stream
	_bat_hum.unit_size = 6.0
	_bat_hum.volume_db = -8.0
	_battery.add_child(_bat_hum)
	_battery.visible = false
	_arc_mesh = ImmediateMesh.new()
	var arcs := MeshInstance3D.new()
	arcs.mesh = _arc_mesh
	arcs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(arcs)
	_arc_mat = StandardMaterial3D.new()
	_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arc_mat.albedo_color = Color(1.6, 2.2, 3.0)
	_char_mat = StandardMaterial3D.new()
	_char_mat.albedo_color = Color(0.02, 0.018, 0.015, 0.62)
	_char_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_char_mat.roughness = 1.0

func _build_hud() -> void:
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0.55, 0.8, 1.0, 0.0)
	hud.add_child(_flash)
	hud_title("LIVE WIRE  ·  don't be holding it")
	_hud_help = Label.new()
	_hud_help.text = "WASD move  ·  touch someone to hand over the battery  ·  SPACE pass within reach"
	_hud_help.position = Vector2(16, 42)
	_style(_hud_help, 16, Color("e8e2c8"))
	hud.add_child(_hud_help)
	_hud_time = Label.new()
	_hud_time.position = Vector2(560, 10)
	_style(_hud_time, 26, Color("8fd8ff"))
	hud.add_child(_hud_time)
	_hud_board = Label.new()
	_hud_board.position = Vector2(930, 12)
	_style(_hud_board, 16, Color("e8e2c8"))
	hud.add_child(_hud_board)
	_hud_status = Label.new()
	_hud_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hud_status.position = Vector2(-320, -64)
	_hud_status.size = Vector2(640, 30)
	_hud_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_hud_status, 20, Color("e8e2c8"))
	hud.add_child(_hud_status)
	_hud_big = Label.new()
	_hud_big.set_anchors_preset(Control.PRESET_CENTER)
	_hud_big.position = Vector2(-400, -150)
	_hud_big.size = Vector2(800, 60)
	_hud_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_hud_big, 34, ARC_COL)
	_hud_big.modulate.a = 0.0
	hud.add_child(_hud_big)
	_refresh_hud()

func _style(l: Label, size: int, c: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)

func _announce(text: String, c: Color) -> void:
	_hud_big.text = text
	_hud_big.add_theme_color_override("font_color", c)
	_hud_big.modulate.a = 1.0
	_hud_big.create_tween().tween_property(_hud_big, "modulate:a", 0.0, 0.6).set_delay(1.8)

func _survivors() -> Array:
	return players.keys().filter(func(i): return not elim_order.has(i) and is_instance_valid(players[i]) and players[i].alive)

func _refresh_hud() -> void:
	var me := multiplayer.get_unique_id()
	var lp := local_player()
	if lp == null:
		_hud_status.text = ""
	elif not lp.alive or elim_order.has(me) or _zap_fx.has(me):
		_hud_status.text = "FRIED"
		_hud_status.add_theme_color_override("font_color", Color("ff6a5a"))
	elif holder == me:
		_hud_status.text = "YOU HAVE THE LIVE ONE  ·  touch someone or SPACE to pass it"
		_hud_status.add_theme_color_override("font_color", Color("8fd8ff"))
	elif holder != -1 and players.has(holder):
		_hud_status.text = "stay away from %s" % players[holder].display_name
		_hud_status.add_theme_color_override("font_color", Color("e8e2c8"))
	else:
		_hud_status.text = "a fresh battery is coming..."
		_hud_status.add_theme_color_override("font_color", Color("e8e2c8"))
	var ids: Array = players.keys()
	ids.sort_custom(func(a, b): return int(not elim_order.has(a)) > int(not elim_order.has(b)))
	var lines: Array = []
	for id in ids:
		var p: LabPlayer3D = players[id]
		var mark := "† " if elim_order.has(id) else (">> " if id == holder else "")
		lines.append(mark + p.display_name)
	_hud_board.text = "STILL BREATHING\n" + "\n".join(lines)

func _process(delta: float) -> void:
	_clock += delta
	if _hud_time:
		var left := clampf(TIME_LIMIT - (_clock - START_DELAY), 0.0, TIME_LIMIT)
		_hud_time.text = "%d" % ceili(left)
		_hud_help.modulate.a = clampf(9.0 - _clock, 0.0, 1.0)
	if holder != -1:
		_fuse_left -= delta
	_update_battery(delta)
	_update_cables(delta)
	_flicker_lights(delta)
	_draw_arcs(delta)
	var lp := local_player()
	if lp and lp.alive:
		var down := Input.is_physical_key_pressed(KEY_SPACE)
		if down != _space_down:
			_space_down = down
			if down and holder == lp.peer_id:
				if multiplayer.is_server():
					_req_pass()
				else:
					_req_pass.rpc_id(1)

func _urgency() -> float:
	return clampf(1.0 - _fuse_left / 7.0, 0.0, 1.0)

func _update_battery(delta: float) -> void:
	if holder == -1 or not players.has(holder) or not is_instance_valid(players[holder]):
		_battery.visible = false
		if _bat_hum.playing:
			_bat_hum.stop()
		return
	var p: LabPlayer3D = players[holder]
	var yaw := p.body.global_rotation.y
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var mid := p.global_position + Vector3(0, 1.12, 0) + fwd * 0.36
	if _carry_mods.has(holder):
		var hands: Array = _carry_mods[holder]
		var ar: Node3D = hands[1]
		var al: Node3D = hands[2]
		if is_instance_valid(ar) and is_instance_valid(al) and ar.is_inside_tree() and al.is_inside_tree():
			var a := ar.global_position
			var b := al.global_position
			if a.distance_to(b) < 0.9 and absf(a.y - b.y) < 0.5 and a.y > 0.6:
				mid = (a + b) * 0.5 + fwd * 0.06 + Vector3(0, -0.03, 0)
	var u := _urgency()
	var jit := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (0.006 + u * 0.018)
	var bas := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, randf_range(-1, 1) * u * 0.08)
	_battery.global_transform = Transform3D(bas, mid + jit)
	_battery.visible = true
	_bat_light.light_energy = randf_range(1.2, 3.0) * (1.0 + u * 1.6)
	_bat_light.omni_range = 3.0 + u * 1.6
	_bat_glow.emission_energy_multiplier = randf_range(2.0, 5.0) * (1.0 + u)
	if not _bat_hum.playing:
		_bat_hum.play()
	_buzz_ph += delta * lerpf(3.0, 17.0, u) * TAU
	_bat_hum.pitch_scale = 0.9 + u * 0.9
	_bat_hum.volume_db = -9.0 + u * 5.0 + (0.0 if sin(_buzz_ph) > 0.0 else -10.0 - u * 8.0)
	_click_t -= delta
	if _click_t <= 0.0:
		_click_t = lerpf(0.75, 0.09, u) * randf_range(0.8, 1.2)
		Fx.sfx("click", mid, -10.0 + u * 6.0, 1.4 + u * 0.6)
		if randf() < 0.35 + u * 0.5:
			_spark_burst(mid + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.2), randf_range(-0.2, 0.2)), 0.45 + u * 0.4)

func _update_cables(delta: float) -> void:
	for c in _cables:
		var pv: Node3D = c.pivot
		pv.rotation.z = sin(_clock * 0.8 + float(c.ph)) * 0.025
		pv.rotation.x = sin(_clock * 0.6 + float(c.ph) * 1.7) * 0.02
		c.t -= delta
		if c.t > 0.0:
			continue
		var tip := pv.to_global(c.tip)
		if c.live:
			c.t = randf_range(0.3, 1.5)
			c.flash = _clock + 0.12
			_spark_burst(tip, randf_range(0.6, 1.2))
			if randf() < 0.35:
				Fx.sfx("click", tip, -14.0, randf_range(0.7, 1.3))
		else:
			c.t = randf_range(1.2, 3.5)
			Fx.sparks(world, tip)

func _flicker_lights(delta: float) -> void:
	for f in _flicker:
		var l: Light3D = f.l
		f.t -= delta
		if f.t > 0.0:
			continue
		var on := true
		match int(f.kind):
			0:
				on = randf() > 0.45
				f.t = randf_range(0.03, 0.12) if randf() < 0.7 else randf_range(0.6, 2.2)
			1:
				on = randf() > 0.12
				f.t = randf_range(0.05, 0.1) if not on else randf_range(1.0, 3.0)
			_:
				on = l.light_energy < float(f.base) * 0.5
				f.t = 0.45
		l.light_energy = float(f.base) * (1.0 if on else 0.04)
		if f.has("m"):
			var m: StandardMaterial3D = f.m
			m.emission_energy_multiplier = float(f.e) if on else 0.1

func _spark_burst(pos: Vector3, power: float) -> void:
	Fx._burst(world, pos, Color(0.55, 0.8, 1.0), int(18.0 * power) + 4, 4.5 * power, 0.016, 0.4, 9.0)
	var l := OmniLight3D.new()
	l.light_color = Color(0.5, 0.75, 1.0)
	l.light_energy = 5.0 * power
	l.omni_range = 2.6 * power
	world.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.18)
	tw.tween_callback(l.queue_free)

func _draw_arcs(delta: float) -> void:
	_arc_t -= delta
	if _arc_t > 0.0:
		return
	_arc_t = 0.045
	_arc_mesh.clear_surfaces()
	var segs: Array = []
	if holder != -1 and _battery.visible:
		var c := _battery.global_position
		var u := _urgency()
		for k in 2 + int(u * 3.0):
			var to := c + Vector3(randf_range(-0.7, 0.7), randf_range(-1.1, 0.6), randf_range(-0.7, 0.7))
			to.y = maxf(to.y, 0.05)
			segs.append([c, to, 0.018 + u * 0.012])
	for id in _zap_fx:
		var p: LabPlayer3D = players[id]
		for k in 5:
			var a := p.position + Vector3(randf_range(-0.4, 0.4), randf_range(0.2, 1.8), randf_range(-0.4, 0.4))
			var b := p.position + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 1.9), randf_range(-0.6, 0.6))
			segs.append([a, b, 0.03])
	if _pass_arc.size() == 3 and _clock < float(_pass_arc[2]):
		segs.append([_pass_arc[0], _pass_arc[1], 0.035])
	for cab in _cables:
		if cab.live and float(cab.flash) > _clock:
			var pv: Node3D = cab.pivot
			var tip := pv.to_global(cab.tip)
			segs.append([tip, Vector3(tip.x + randf_range(-0.4, 0.4), 0.02, tip.z + randf_range(-0.4, 0.4)), 0.02])
	if segs.is_empty():
		return
	var cam := camera.global_position
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _arc_mat)
	for s in segs:
		_bolt(s[0], s[1], s[2], cam)
	_arc_mesh.surface_end()

func _bolt(a: Vector3, b: Vector3, w: float, cam: Vector3) -> void:
	var n := 6
	var prev := a
	var span := a.distance_to(b)
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var p := a.lerp(b, t)
		if i < n:
			p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * span * 0.12
		_quad(prev, p, w * (1.0 - t * 0.5), cam)
		prev = p

func _quad(a: Vector3, b: Vector3, w: float, cam: Vector3) -> void:
	var side := (b - a).cross(cam - a).normalized() * w
	_arc_mesh.surface_add_vertex(a - side)
	_arc_mesh.surface_add_vertex(a + side)
	_arc_mesh.surface_add_vertex(b + side)
	_arc_mesh.surface_add_vertex(a - side)
	_arc_mesh.surface_add_vertex(b + side)
	_arc_mesh.surface_add_vertex(b - side)

func _carry_library() -> AnimationLibrary:
	if _carry_lib:
		return _carry_lib
	var base := LabCharacter.shared_library()
	_carry_lib = AnimationLibrary.new()
	for n in base.get_animation_list():
		_carry_lib.add_animation(n, base.get_animation(n))
	for nm in ["Walk", "Jog_Fwd", "Sprint"]:
		_carry_lib.remove_animation(nm)
		_carry_lib.add_animation(nm, base.get_animation("Walk_Carry").duplicate())
	return _carry_lib

func _carry(sk: Skeleton3D) -> Dictionary:
	var key := sk.get_bone_count()
	if _carry_poses.has(key):
		return _carry_poses[key]
	var d: Dictionary = {}
	var a := LabCharacter.shared_library().get_animation("Walk_Carry")
	for tr in a.get_track_count():
		if a.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(a.track_get_path(tr)).get_slice(":", 1)
		if not (bone.ends_with("_r") or bone.ends_with("_l")):
			continue
		if bone.begins_with("thigh") or bone.begins_with("calf") or bone.begins_with("foot") or bone.begins_with("ball"):
			continue
		var bi := sk.find_bone(bone)
		if bi >= 0:
			d[bi] = a.rotation_track_interpolate(tr, a.length * 0.25)
	_carry_poses[key] = d
	return d

func _swap_lib(b: LabCharacter, lib: AnimationLibrary, spd: float) -> void:
	if b.is_dead():
		return
	b.anim.stop()
	b.anim.remove_animation_library("")
	b.anim.add_animation_library("", lib)
	b.anim.speed_scale = spd
	b._action_busy = false
	b._locomotion = ""
	b.set_motion(0.0)

func _give(id: int) -> void:
	var p: LabPlayer3D = players[id]
	p.speed = HOLD_SPEED
	p._label.modulate = Color("8fd8ff")
	_swap_lib(p.body, _carry_library(), 1.35)
	if not _carry_mods.has(id) and p.body.skeleton:
		var sk := p.body.skeleton
		var mod := ArmPose.new()
		sk.add_child(mod)
		mod.poses = _carry(sk)
		var hands: Array = [mod]
		for bn in ["hand_r", "hand_l"]:
			var att := BoneAttachment3D.new()
			att.bone_name = bn
			sk.add_child(att)
			hands.append(att)
		_carry_mods[id] = hands

func _take(id: int) -> void:
	var p: LabPlayer3D = players[id]
	p.speed = BASE_SPEED
	p._label.modulate = p.color.lightened(0.35)
	_swap_lib(p.body, LabCharacter.shared_library(), 1.0)
	_drop_mod(id)

func _drop_mod(id: int) -> void:
	if _carry_mods.has(id):
		for m in _carry_mods[id]:
			if is_instance_valid(m):
				(m as Node).queue_free()
		_carry_mods.erase(id)

func _run() -> void:
	await get_tree().create_timer(START_DELAY).timeout
	if players.size() < 2:
		_end()
		return
	_running = true
	_new_battery()

func _end() -> void:
	if _ending:
		return
	_ending = true
	_running = false
	get_tree().create_timer(ZAP_T + 0.8).timeout.connect(_finish)

func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit(survival_placement(elim_order))

func _new_battery() -> void:
	var c: Array = _survivors()
	if c.size() < 2:
		return
	var id: int = c[randi() % c.size()]
	_srv_fuse = randf_range(FUSE_MIN, FUSE_MAX)
	_hold_since = _game_t
	_no_back_id = -1
	bots[id].react = randf_range(0.35, 0.6)
	_rpc_arm.rpc(id, _srv_fuse)

func _zap(id: int) -> void:
	holder = -1
	elim_order.append(id)
	_wait_t = RESPAWN_T
	_rpc_zap.rpc(id)

func _physics_process(delta: float) -> void:
	if not NetworkManager.is_server() or not _running:
		return
	_game_t += delta
	if holder != -1:
		_srv_fuse -= delta
		if _srv_fuse <= 0.0:
			_zap(holder)
		else:
			_srv_passes(delta)
	else:
		_wait_t -= delta
		if _wait_t <= 0.0 and _survivors().size() > 1:
			_new_battery()
	if _survivors().size() <= 1:
		_end()
	elif _game_t >= TIME_LIMIT:
		if holder != -1:
			_zap(holder)
		_end()

func _srv_passes(delta: float) -> void:
	if _game_t - _hold_since < MIN_HOLD:
		return
	var t := _pass_target(holder, TOUCH_R)
	if t != -1:
		_do_pass(holder, t)
		return
	var hp: LabPlayer3D = players[holder]
	if not hp.is_bot:
		return
	var b: Dictionary = bots[holder]
	var near := _pass_target(holder, PASS_R)
	if near == -1:
		b.pass = randf_range(0.12, 0.35) if randf() > 0.12 else randf_range(0.5, 0.8)
		return
	b.pass -= delta
	if b.pass <= 0.0:
		_do_pass(holder, near)

func _pass_target(id: int, r: float) -> int:
	var p: LabPlayer3D = players[id]
	var best := -1
	var bd := r
	for o in _survivors():
		if o == id or (o == _no_back_id and _game_t < _no_back_until):
			continue
		var q: LabPlayer3D = players[o]
		var d := Vector2(q.position.x - p.position.x, q.position.z - p.position.z).length()
		if d < bd:
			bd = d
			best = o
	return best

func _do_pass(from: int, to: int) -> void:
	holder = to
	_no_back_id = from
	_no_back_until = _game_t + NO_BACK_T
	_hold_since = _game_t
	bots[to].react = randf_range(0.2, 0.45)
	bots[to].pass = randf_range(0.15, 0.35)
	bots[from].t = 0.0
	_rpc_pass.rpc(from, to)

@rpc("any_peer", "call_local", "reliable")
func _req_pass() -> void:
	if not multiplayer.is_server() or not _running or holder == -1:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	if id != holder or _game_t - _hold_since < MIN_HOLD:
		return
	var t := _pass_target(id, PASS_R)
	if t != -1:
		_do_pass(id, t)

@rpc("authority", "call_local", "reliable")
func _rpc_arm(id: int, fuse: float) -> void:
	holder = id
	_fuse_left = fuse
	_click_t = 0.0
	_give(id)
	var p: LabPlayer3D = players[id]
	_spark_burst(p.position + Vector3(0, 1.2, 0), 1.6)
	Fx.sfx("arm", p.position, -2.0, 0.7)
	Fx.sfx("hum", p.position, -4.0, 0.6)
	_announce("%s HAS THE LIVE ONE" % p.display_name, ARC_COL)
	_refresh_hud()

@rpc("authority", "call_local", "reliable")
func _rpc_pass(from: int, to: int) -> void:
	holder = to
	var a: LabPlayer3D = players[from]
	var b: LabPlayer3D = players[to]
	_take(from)
	_give(to)
	var dir := b.position - a.position
	dir.y = 0.0
	a.face(dir)
	b.face(-dir)
	b.body.play_action("Hit_Chest", 0.05, 1.8)
	var mid := (a.position + b.position) * 0.5 + Vector3(0, 1.2, 0)
	_pass_arc = [a.position + Vector3(0, 1.15, 0), b.position + Vector3(0, 1.15, 0), _clock + 0.18]
	_spark_burst(mid, 1.0)
	Fx.sfx("click", mid, -2.0, 0.8)
	Fx.sfx("whoosh", mid, -8.0, 1.4)
	if b.is_local_human():
		Fx.shake(0.18)
	_refresh_hud()

@rpc("authority", "call_local", "reliable")
func _rpc_zap(id: int) -> void:
	holder = -1
	if not elim_order.has(id):
		elim_order.append(id)
	var p: LabPlayer3D = players[id]
	_zap_fx[id] = true
	_drop_mod(id)
	p.speed = BASE_SPEED
	p.body.anim.speed_scale = 1.0
	if p.is_local_human():
		p.input_enabled = false
	var c := p.position + Vector3(0, 1.1, 0)
	_spark_burst(c, 2.6)
	Fx._burst(world, c, Color(0.9, 0.97, 1.0), 60, 7.0, 0.02, 0.6, 9.0)
	var fl := OmniLight3D.new()
	fl.light_color = Color(0.5, 0.75, 1.0)
	fl.light_energy = 18.0
	fl.omni_range = 10.0
	world.add_child(fl)
	fl.global_position = c + Vector3(0, 0.6, 0)
	var tw := fl.create_tween()
	tw.tween_property(fl, "light_energy", 3.0, 0.07)
	tw.tween_property(fl, "light_energy", 14.0, 0.06)
	tw.tween_property(fl, "light_energy", 0.0, 0.7)
	tw.tween_callback(fl.queue_free)
	_flash.color.a = 0.55
	_flash.create_tween().tween_property(_flash, "color:a", 0.0, 0.45)
	Fx.shake(0.55)
	Fx.sfx("buzzer", c, 0.0, 1.3)
	Fx.sfx("hum", c, 4.0, 0.5)
	Fx.sfx("hit", c, 0.0, 0.6)
	for k in 3:
		get_tree().create_timer(0.3 * k + 0.01).timeout.connect(_convulse.bind(id, k))
	get_tree().create_timer(ZAP_T).timeout.connect(_fry.bind(id))
	_announce("%s GOT FRIED" % p.display_name, Color("ff8a5a"))
	_refresh_hud()

func _convulse(id: int, k: int) -> void:
	var p: LabPlayer3D = players[id]
	if not is_instance_valid(p) or p.body.is_dead():
		return
	p.body.anim.stop()
	p.body.play_action("Hit_Chest", 0.03, 1.9)
	_spark_burst(p.position + Vector3(randf_range(-0.2, 0.2), randf_range(0.6, 1.6), randf_range(-0.2, 0.2)), 1.2)
	Fx.sfx("hit", p.position, -4.0, 0.5 + 0.15 * k)
	Fx.shake(0.3)
	if k == 1:
		_char(p)

func _char(p: LabPlayer3D) -> void:
	if p.body.suit_color == CHAR:
		return
	p.body.set_suit_color(CHAR)
	for mi in p.body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _char_mat

func _fry(id: int) -> void:
	_zap_fx.erase(id)
	var p: LabPlayer3D = players[id]
	if not is_instance_valid(p):
		return
	_char(p)
	eliminate(id, "Death01")
	Fx._smoke(world, p.position + Vector3(0, 0.6, 0), 0.7)
	var d := Decal.new()
	d.texture_albedo = Fx._splat_tex
	d.size = Vector3(2.2, 1.5, 2.2)
	d.modulate = Color(0.03, 0.03, 0.035)
	d.cull_mask = 1
	d.rotation.y = randf() * TAU
	world.add_child(d)
	d.global_position = Vector3(p.position.x, 0.2, p.position.z)
	_refresh_hud()

func _bot_brain(delta: float, id: int) -> Vector3:
	if not _running or _zap_fx.has(id) or elim_order.has(id):
		return Vector3.ZERO
	var p: LabPlayer3D = players[id]
	var b: Dictionary = bots[id]
	b.t -= delta
	if b.freeze > 0.0:
		b.freeze -= delta
		return Vector3.ZERO
	if holder == id:
		return _chase(id, p, b, delta)
	if holder == -1:
		return _idle(id, p, b)
	return _flee(id, p, b)

func _chase(id: int, p: LabPlayer3D, b: Dictionary, delta: float) -> Vector3:
	if b.react > 0.0:
		b.react -= delta
		return Vector3.ZERO
	if b.t <= 0.0:
		b.t = randf_range(0.2, 0.38)
		var cands: Array = []
		for o in _survivors():
			if o != id and not (o == _no_back_id and _game_t < _no_back_until):
				cands.append(o)
		if cands.is_empty():
			b.target = -1
		else:
			cands.sort_custom(func(x, y): return players[x].position.distance_to(p.position) < players[y].position.distance_to(p.position))
			var pick: int = cands[0]
			if cands.size() > 1 and randf() < 0.12:
				pick = cands[1]
			var tp: Vector3 = players[pick].position
			var prev: Vector3 = b.tp if int(b.tid) == pick else tp
			b.tid = pick
			b.tp = tp
			b.target = pick
			var aim: Vector3 = tp + (tp - prev) * 0.8 + Vector3(randf_range(-0.35, 0.35), 0.0, randf_range(-0.35, 0.35))
			aim.x = clampf(aim.x, 0.4, W - 0.4)
			aim.z = clampf(aim.z, 0.4, D - 0.4)
			b.aim = aim
			if randf() < 0.05:
				b.freeze = randf_range(0.2, 0.4)
	if int(b.target) == -1 or b.aim == Vector3.INF or not players.has(b.target):
		return Vector3.ZERO
	var to: Vector3 = b.aim - p.position
	to.y = 0.0
	if to.length() < 0.3:
		to = players[b.target].position - p.position
		to.y = 0.0
	if to.length() < 0.05:
		return Vector3.ZERO
	b.dir = to.normalized()
	return b.dir

func _flee(id: int, p: LabPlayer3D, b: Dictionary) -> Vector3:
	if b.t <= 0.0:
		b.t = randf_range(0.18, 0.42)
		var hp: Vector3 = players[holder].position
		var roll := randf()
		if roll < 0.05:
			b.freeze = randf_range(0.2, 0.45)
			return Vector3.ZERO
		var d := Vector2(hp.x - p.position.x, hp.z - p.position.z).length()
		if d > 6.5:
			b.dir = _drift(p, b, hp)
		elif roll < 0.1:
			var a := randf() * TAU
			b.dir = Vector3(cos(a), 0.0, sin(a))
		else:
			b.dir = _best_escape(id, p.position, hp, b.dir)
	return b.dir

func _best_escape(id: int, pos: Vector3, hp: Vector3, prev: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bs := -INF
	var others: Array = _survivors()
	for k in 16:
		var ang := float(k) / 16.0 * TAU
		var dv := Vector3(cos(ang), 0.0, sin(ang))
		var probe := pos + dv * 1.6
		var s := Vector2(probe.x - hp.x, probe.z - hp.z).length()
		var edge := minf(minf(probe.x, W - probe.x), minf(probe.z, D - probe.z))
		if edge < 0.4:
			s -= 4.0
		s += minf(edge, 2.2) * 0.8
		s += dv.dot(prev) * 0.35
		for o in others:
			if o != id and o != holder:
				var q: LabPlayer3D = players[o]
				if q.position.distance_to(probe) < 1.4:
					s -= 0.5
		s += randf() * 0.3
		if s > bs:
			bs = s
			best = dv
	return best

func _drift(p: LabPlayer3D, b: Dictionary, hp: Vector3) -> Vector3:
	var w: Vector3 = b.wander
	if w == Vector3.INF or p.position.distance_to(w) < 0.6 or randf() < 0.08:
		var bd := -INF
		for k in 6:
			var c := Vector3(randf_range(1.2, W - 1.2), 0.0, randf_range(1.2, D - 1.2))
			var s := c.distance_to(hp) - c.distance_to(p.position) * 0.3
			if s > bd:
				bd = s
				w = c
		b.wander = w
	var v := w - p.position
	v.y = 0.0
	return v.normalized() * 0.45 if v.length() > 0.2 else Vector3.ZERO

func _idle(id: int, p: LabPlayer3D, b: Dictionary) -> Vector3:
	if b.t <= 0.0:
		b.t = randf_range(0.3, 0.6)
		b.dir = Vector3.ZERO
		var nd := 2.5
		for o in _survivors():
			if o == id:
				continue
			var q: LabPlayer3D = players[o]
			var d := q.position.distance_to(p.position)
			if d < nd:
				nd = d
				var away := p.position - q.position
				away.y = 0.0
				b.dir = away.normalized() * 0.5
	return b.dir
