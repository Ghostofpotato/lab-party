extends ArenaMinigame3D
## Lethal Rebound: a riveted steel floor hangs over a machinery pit, ringed by
## spinning saw blades. SPACE lunges and shoves: a hit rival flies back hard and
## repeated hits stack. Touch a saw and you are mince. Outer plates shake red and
## drop away while the saw rails close in, and saw carriages start sliding along
## floor tracks. Last subject standing wins; then kills (last shove within 2 s),
## then survival time.

const TIME_LIMIT: float = 45.0
const COLS: int = 10
const ROWS: int = 8
const CW: float = 1.6
const CD: float = 1.25
const EDGE_R: float = 0.74
const FIN_R: float = 0.6
const SLIDE_R: float = 0.78
const KILL_X: float = 0.48
const KILL_Z: float = 0.4
const SHOVE_REACH: float = 1.9
const SHOVE_CD: float = 0.75
const LUNGE: float = 1.3
const KNOCK: float = 1.5
const STACK_WINDOW: float = 1.6
const CREDIT: float = 2.0
const RING_WARN: float = 2.6
const RING_AT: Array = [12.0, 25.0]
const TRACK_WARN: float = 2.0
const TRACK_ROWS: Array = [3, 5, 2]
const TRACK_AT: Array = [6.0, 17.0, 19.0]
const SLIDE_W: float = 0.9
const BANK_SPEED: float = 1.5

enum St { COUNTDOWN, RUN, DONE }

var st: St = St.COUNTDOWN
var clock: float = 0.0
var ring: int = 0
var floor_rect: Rect2 = Rect2(0.0, 0.0, W, D)
var bank: Array[float] = [0.0, W, 0.0, D]
var bank_goal: Array[float] = [0.0, W, 0.0, D]
var kills: Dictionary = {}
var elim_order: Array = []
var last_shover: Dictionary = {}
var last_shove_t: Dictionary = {}
var stack: Dictionary = {}
var last_hit_t: Dictionary = {}
var shove_ready: Dictionary = {}
var lock_until: Dictionary = {}
var tracks: Array[Dictionary] = []

var _plates: Array[MeshInstance3D] = []
var _plate_ring: Array[int] = []
var _plate_base: Array[Vector3] = []
var _plate_mat: Array[Material] = []
var _plate_warn: Array[Material] = []
var _warn_plates: Array[int] = []
var _warn_mats: Array[StandardMaterial3D] = []
var _ring_warned: int = -1
var _ring_warn_t: float = -100.0
var _banks: Array[Node3D] = []
var _blades: Array[Dictionary] = []
var _spinners: Array[Node3D] = []
var _spin_speed: Array[float] = []
var _push_tw: Dictionary = {}
var _bot: Dictionary = {}
var _ev: Dictionary = {}
var _sync_t: float = 0.0
var _space_down: bool = false
var _ended: bool = false
var _blade_mesh_cache: Dictionary = {}
var _steel: StandardMaterial3D
var _hz: StandardMaterial3D
var _hum: AudioStreamPlayer
var _cam_base: Vector3
var _cam_look: Vector3

var _big: Label
var _hint: Label
var _timer_label: Label
var _board: Label

func begin() -> void:
	setup_arena(false)
	_tune_light()
	_steel = _blade_material()
	_hz = _hazard_mat()
	_build_room()
	_build_pit()
	_build_floor()
	_build_banks()
	_build_tracks()
	_build_dressing()
	spawn_players(_spawns())
	for id in players:
		var p: LabPlayer3D = players[id]
		p.speed = 4.4
		p.input_enabled = false
		p.bot_brain = _bot_brain.bind(id)
		kills[id] = 0
		last_shover[id] = -1
		last_shove_t[id] = -100.0
		stack[id] = 0
		last_hit_t[id] = -100.0
		shove_ready[id] = 0.0
		lock_until[id] = 0.0
		if p.is_bot:
			_bot[id] = {"react": randf_range(0.3, 0.6), "greed": randf_range(0.08, 0.22), "aggro": randf_range(0.35, 0.75),
				"dodge": randf_range(0.3, 0.55), "dodge_ready": 0.0, "think": 0.0, "lag": 0.5, "target": -1,
				"goal": Vector3(W * 0.5, 0.0, D * 0.5)}
	_update_bounds()
	camera.fov = 43.0
	_cam_base = Vector3(W * 0.5, 10.2, D + 4.6)
	_cam_look = Vector3(W * 0.5, 0.0, D * 0.5 + 0.4)
	_place_camera(1.0)
	_build_hud()
	_start_hum()
	if NetworkManager.is_server():
		_run.call_deferred()

func _spawns() -> Array:
	var a: Array = []
	var n: int = NetworkManager.players.size()
	for i in n:
		var ang: float = TAU * float(i) / float(maxi(n, 1)) + 0.4
		a.append(Vector3(W * 0.5 + cos(ang) * 3.6, 0.0, D * 0.5 + sin(ang) * 1.9))
	return a

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.32
			n.shadow_enabled = false
			n.light_color = Color(0.75, 0.9, 0.85)
	env.background_color = Color("060908")
	env.ambient_light_color = Color(0.45, 0.58, 0.54)
	env.ambient_light_energy = 0.48
	env.fog_light_color = Color(0.08, 0.11, 0.1)
	env.fog_density = 0.022
	env.tonemap_exposure = 1.05
	env.glow_intensity = 0.7
	env.adjustment_saturation = 0.85

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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		var z: float = thick * 0.5 * side
		for i in n:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[(i + 1) % n]
			for q in [Vector2.ZERO, p0, p1]:
				var v2: Vector2 = q
				st.set_normal(Vector3(0, 0, side))
				st.set_uv(Vector2(v2.x / r * 0.5 + 0.5, v2.y / r * 0.5 + 0.5))
				st.add_vertex(Vector3(v2.x, v2.y, z))
	for i in n:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % n]
		var nm := Vector3((p0 + p1).x, (p0 + p1).y, 0.0).normalized()
		var quad := [Vector3(p0.x, p0.y, thick * 0.5), Vector3(p1.x, p1.y, thick * 0.5), Vector3(p1.x, p1.y, -thick * 0.5),
			Vector3(p0.x, p0.y, thick * 0.5), Vector3(p1.x, p1.y, -thick * 0.5), Vector3(p0.x, p0.y, -thick * 0.5)]
		for v3 in quad:
			st.set_normal(nm)
			st.set_uv(Vector2(0.98, 0.5))
			st.add_vertex(v3)
	var mesh := st.commit()
	_blade_mesh_cache[key] = mesh
	return mesh

func _blade(parent: Node3D, pos: Vector3, r: float, speed: float, m: Material = null) -> Node3D:
	var b := Node3D.new()
	parent.add_child(b)
	b.position = pos
	var mi := MeshInstance3D.new()
	mi.mesh = _blade_mesh(r, int(r * 46.0), 0.035)
	mi.material_override = m if m else _steel
	b.add_child(mi)
	var hub_m := mat("rusty_metal_02", 3.0, Color(0.55, 0.52, 0.5))
	_cyl(r * 0.24, 0.09, hub_m, Vector3.ZERO, Vector3(90, 0, 0), b, 12)
	for k in 4:
		var a: float = TAU * float(k) / 4.0
		box(Vector3(0.04, 0.04, 0.12), Vector3(cos(a), sin(a), 0.0) * r * 0.14, _plain(Color(0.12, 0.11, 0.1), 0.5, 0.6), b)
	_spinners.append(b)
	_spin_speed.append(speed)
	return b

func _sparker(parent: Node3D, pos: Vector3, dir: Vector3, amount: int = 26) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = amount
	gp.lifetime = 0.42
	gp.randomness = 0.5
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 28.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -11.0, 0)
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	gp.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.014, 0.13, 0.014)
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

func _chain(top: Vector3, length: float, parent: Node3D, hook: bool = true) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.035
	tm.outer_radius = 0.075
	tm.rings = 10
	tm.ring_segments = 6
	tm.material = mat("rusty_metal", 2.0, Color(0.6, 0.5, 0.42))
	var count := int(length / 0.12)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tm
	mm.instance_count = count
	for i in count:
		var b := Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.0, 1.7))
		if i % 2 == 1:
			b = Basis(Vector3.UP, PI * 0.5) * b
		mm.set_instance_transform(i, Transform3D(b, top - Vector3(0, i * 0.12, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)
	if hook:
		var h := MeshInstance3D.new()
		var hm := TorusMesh.new()
		hm.inner_radius = 0.12
		hm.outer_radius = 0.2
		h.mesh = hm
		h.material_override = mat("rusty_metal_02", 2.0)
		parent.add_child(h)
		h.position = top - Vector3(0, length + 0.15, 0)
		h.rotation_degrees.x = 90.0

func _build_room() -> void:
	var rm := Node3D.new()
	rm.name = "Room"
	world.add_child(rm)
	var brick := mat("factory_brick", 0.35, Color(0.5, 0.5, 0.46))
	var conc := mat("concrete_wall_008", 0.35, Color(0.5, 0.52, 0.48))
	var dirty := mat("dirty_concrete", 0.35, Color(0.4, 0.42, 0.38))
	var grate := mat("metal_grate_rusty", 0.8, Color(0.7, 0.68, 0.62))
	var band := mat("green_metal_rust", 0.6, Color(0.55, 0.6, 0.55))
	box(Vector3(W + 14.0, 16.0, 0.6), Vector3(W * 0.5, 0.8, -6.3), brick, rm)
	box(Vector3(0.6, 16.0, D + 16.0), Vector3(-6.3, 0.8, D * 0.5 + 1.0), conc, rm)
	box(Vector3(0.6, 16.0, D + 16.0), Vector3(W + 6.3, 0.8, D * 0.5 + 1.0), conc, rm)
	box(Vector3(W + 14.0, 7.4, 0.6), Vector3(W * 0.5, -3.7, D + 9.0), dirty, rm)
	box(Vector3(W + 12.0, 0.25, 2.7), Vector3(W * 0.5, -0.125, -4.65), grate, rm)
	box(Vector3(2.7, 0.25, D + 14.0), Vector3(-4.65, -0.125, D * 0.5 + 1.0), grate, rm)
	box(Vector3(2.7, 0.25, D + 14.0), Vector3(W + 4.65, -0.125, D * 0.5 + 1.0), grate, rm)
	box(Vector3(W + 12.0, 0.6, 0.2), Vector3(W * 0.5, -0.4, -3.3), _hz, rm)
	box(Vector3(0.2, 0.6, D + 14.0), Vector3(-3.3, -0.4, D * 0.5 + 1.0), _hz, rm)
	box(Vector3(0.2, 0.6, D + 14.0), Vector3(W + 3.3, -0.4, D * 0.5 + 1.0), _hz, rm)
	box(Vector3(W + 12.0, 1.4, 0.3), Vector3(W * 0.5, 0.7, -5.9), band, rm)
	box(Vector3(0.3, 1.4, D + 14.0), Vector3(-5.9, 0.7, D * 0.5 + 1.0), band, rm)
	box(Vector3(0.3, 1.4, D + 14.0), Vector3(W + 5.9, 0.7, D * 0.5 + 1.0), band, rm)
	var rail := mat("rusty_metal_02", 1.5, Color(0.55, 0.5, 0.45))
	var x := -5.5
	while x <= W + 5.5:
		_cyl(0.035, 1.0, rail, Vector3(x, 0.5, -3.45), Vector3.ZERO, rm, 6)
		x += 1.6
	_cyl(0.04, W + 11.0, rail, Vector3(W * 0.5, 1.0, -3.45), Vector3(0, 0, 90), rm, 6)
	_cyl(0.03, W + 11.0, rail, Vector3(W * 0.5, 0.55, -3.45), Vector3(0, 0, 90), rm, 6)
	for sx in [-1.0, 1.0]:
		var rx: float = W * 0.5 + sx * (W * 0.5 + 3.45)
		var z := -3.4
		while z <= D + 6.0:
			_cyl(0.035, 1.0, rail, Vector3(rx, 0.5, z), Vector3.ZERO, rm, 6)
			z += 1.6
		_cyl(0.04, D + 9.5, rail, Vector3(rx, 1.0, D * 0.5 + 1.2), Vector3(90, 0, 0), rm, 6)
		_cyl(0.03, D + 9.5, rail, Vector3(rx, 0.55, D * 0.5 + 1.2), Vector3(90, 0, 0), rm, 6)
	var pipe := mat("rusty_metal_02", 1.5)
	for y in [2.2, 2.7, 3.6]:
		_cyl(0.18 if y < 3.0 else 0.28, W + 12.0, pipe, Vector3(W * 0.5, y, -5.75), Vector3(0, 0, 90), rm, 12)
	for sx in [-1.0, 1.0]:
		for y in [2.4, 3.1]:
			_cyl(0.16, D + 14.0, pipe, Vector3(W * 0.5 + sx * (W * 0.5 + 5.75), y, D * 0.5 + 1.0), Vector3(90, 0, 0), rm, 12)
	for px in [-2.0, 4.5, 11.5, W + 2.0]:
		_cyl(0.2, 10.0, pipe, Vector3(px, -2.0, -5.7), Vector3.ZERO, rm, 12)
	prop("power_box_01", Vector3(2.0, 1.6, -5.95), 0.0, 1.6, rm)
	prop("power_box_01", Vector3(W - 3.0, 1.6, -5.95), 0.0, 1.6, rm)
	prop("fire_alarm", Vector3(W * 0.5 + 1.2, 1.8, -5.95), 0.0, 1.6, rm)
	prop("security_camera_01", Vector3(-5.8, 3.6, -5.8), 45.0, 1.6, rm)
	for sc in [[-1.0, -5.95, 0.0], [W * 0.5, -5.95, 0.0], [W + 1.0, -5.95, 0.0], [-5.95, 4.0, 90.0], [W + 5.95, 4.0, -90.0]]:
		var pos := Vector3(sc[0], 1.9, sc[1])
		prop("industrial_caged_sconce", pos, sc[2], 1.6, rm)
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.74, 0.42)
		o.light_energy = 1.6
		o.omni_range = 5.5
		rm.add_child(o)
		o.position = pos + Vector3(0, 0.1, 0.45 if sc[2] == 0.0 else 0.0) + (Vector3(0.45 * signf(-pos.x), 0, 0) if sc[2] != 0.0 else Vector3.ZERO)
	for i in 3:
		prop("modular_chainlink_fence", Vector3(-4.6, 0.0, -1.0 + i * 3.0), 90.0, 1.0, rm)
	for d in [["barrel_03", -5.2, -5.3, 0, 1.15], ["barrel_03", -4.4, -5.4, 40, 1.15], ["wooden_crate_01", 1.0, -5.2, 15, 1.15],
		["metal_tool_chest", 4.0, -5.4, 0, 1.2], ["portable_generator", 7.6, -5.0, 180, 1.15], ["old_military_crate", 10.0, -5.3, 0, 1.15],
		["steel_frame_shelves_03", 13.4, -5.6, 0, 1.0], ["cement_bag", 15.6, -4.6, 30, 1.15], ["propane_tank", W + 4.9, -5.2, 0, 1.15],
		["wooden_crate_02", W + 4.8, -2.4, 10, 1.15], ["trashbag", W + 4.3, 0.6, 0, 1.15], ["metal_trash_can", W + 5.0, 2.4, 0, 1.15],
		["portable_welding_cart", W + 4.6, 5.0, -80, 1.15], ["barrel_03", W + 5.1, 7.6, 0, 1.15], ["old_tyre", W + 4.4, 9.2, 0, 1.15],
		["worn_metal_rack", -5.2, 5.0, 90, 1.15], ["metal_jerrycan", -4.4, 7.2, 60, 1.15], ["wooden_military_crate", -5.0, 8.8, 90, 1.2],
		["can_rusted", -4.2, 3.0, 0, 1.6], ["tool_cart", -4.6, 10.8, 20, 1.15], ["old_military_compressor", W + 4.7, 11.6, 90, 1.15]]:
		prop(d[0], Vector3(d[1], 0.0, d[2]), d[3], d[4], rm)
	var hs := [[2.6, -4.2, 20.0], [12.8, -4.4, -35.0], [-4.0, 1.4, 75.0], [W + 4.0, 3.6, -100.0]]
	for h in hs:
		var n := prop("rusted_hacksaw", Vector3(h[0], 0.04, h[1]), h[2], 1.8, rm)
		if n:
			n.rotation_degrees.x = 90.0
	for c in [[Vector3(-1.9, 9.0, -1.8), 7.6], [Vector3(W + 1.9, 9.0, -1.2), 8.4], [Vector3(-2.1, 9.0, 4.0), 9.6],
		[Vector3(W + 2.0, 9.0, 6.0), 10.4], [Vector3(5.0, 9.0, -2.6), 6.6], [Vector3(11.0, 9.0, -2.4), 7.8], [Vector3(-1.8, 9.0, 9.0), 12.0]]:
		_chain(c[0], c[1], rm)
	for lx in [W * 0.3, W * 0.7]:
		var sp := lamp(Vector3(lx, 7.2, D * 0.45), 6.0, Color(0.95, 0.88, 0.72), rm)
		sp.shadow_enabled = false
		sp.spot_angle = 65.0
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.74)
	key.light_energy = 11.0
	key.spot_range = 24.0
	key.spot_angle = 42.0
	key.spot_attenuation = 0.5
	key.shadow_enabled = true
	rm.add_child(key)
	key.position = Vector3(W * 0.5, 13.0, D * 0.5 + 0.5)
	key.rotation_degrees.x = -90.0
	var fill := SpotLight3D.new()
	fill.light_color = Color(0.7, 0.9, 0.85)
	fill.light_energy = 4.0
	fill.spot_range = 20.0
	fill.spot_angle = 45.0
	rm.add_child(fill)
	fill.position = Vector3(W * 0.5, 10.0, D + 3.0)
	fill.look_at(Vector3(W * 0.5, 0.0, D * 0.5), Vector3.UP)

func _build_pit() -> void:
	var pit := Node3D.new()
	pit.name = "Pit"
	world.add_child(pit)
	box(Vector3(W + 14.0, 0.4, D + 16.0), Vector3(W * 0.5, -7.2, D * 0.5 + 1.0), mat("damaged_concrete_floor", 0.3, Color(0.32, 0.3, 0.28)), pit)
	var rust := mat("rusty_metal", 1.0, Color(0.55, 0.5, 0.45))
	var rust2 := mat("rusty_metal_02", 1.0, Color(0.6, 0.58, 0.55))
	var green := mat("green_metal_rust", 0.7, Color(0.5, 0.58, 0.54))
	for c in COLS + 1:
		box(Vector3(0.14, 0.32, D + 0.4), Vector3(c * CW, -0.33, D * 0.5), rust, pit)
	for r in ROWS + 1:
		box(Vector3(W + 0.4, 0.32, 0.14), Vector3(W * 0.5, -0.33, r * CD), rust, pit)
	for c in range(0, COLS + 1, 2):
		for r in range(0, ROWS + 1, 4):
			box(Vector3(0.3, 6.6, 0.3), Vector3(c * CW, -3.8, r * CD), rust2, pit)
	for t in [[-1.9, -1.7, 1.25], [W + 1.9, -1.7, 1.25], [-1.9, D * 0.5, 1.0], [W + 1.9, D * 0.5 + 0.4, 1.0], [-1.9, D + 2.0, 1.25], [W + 1.9, D + 2.0, 1.25]]:
		var tx: float = t[0]
		var tz: float = t[1]
		var tr: float = t[2]
		_cyl(tr, 7.4, green, Vector3(tx, -3.4, tz), Vector3.ZERO, pit, 24)
		_cyl(tr + 0.12, 0.22, rust2, Vector3(tx, 0.1, tz), Vector3.ZERO, pit, 24)
		var rings_m := _glow(Color(0.85, 0.05, 0.04), 0.9)
		for k in 3:
			var tor := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = tr * (0.25 + k * 0.22)
			tm.outer_radius = tm.inner_radius + 0.06
			tm.rings = 32
			tor.mesh = tm
			tor.material_override = rings_m
			pit.add_child(tor)
			tor.position = Vector3(tx, 0.215, tz)
			tor.scale = Vector3(1.0, 0.15, 1.0)
		for y in [-1.0, -2.6, -4.4]:
			_cyl(tr + 0.08, 0.2, rust, Vector3(tx, y, tz), Vector3.ZERO, pit, 24)
	for y in [-1.4, -2.2, -3.8]:
		_cyl(0.22, W + 10.0, rust2, Vector3(W * 0.5, y, -2.0 + absf(y)), Vector3(0, 0, 90), pit, 12)
		_cyl(0.18, D + 10.0, rust2, Vector3(-1.2 - absf(y) * 0.2, y - 0.5, D * 0.5), Vector3(90, 0, 0), pit, 12)
		_cyl(0.18, D + 10.0, rust2, Vector3(W + 1.2 + absf(y) * 0.2, y - 0.3, D * 0.5), Vector3(90, 0, 0), pit, 12)
	var gear_m := mat("rusty_metal", 1.6, Color(0.5, 0.44, 0.38))
	for g in [[3.0, -2.4, 3.0, 1.5, 0.6], [8.0, -3.2, 5.6, 2.0, -0.4], [13.0, -2.6, 3.4, 1.4, 0.7], [5.5, -4.6, 8.0, 1.8, -0.5], [11.5, -4.0, 8.4, 1.6, 0.5], [-1.8, -1.6, 7.6, 0.9, 1.2]]:
		var holder := Node3D.new()
		pit.add_child(holder)
		holder.position = Vector3(g[0], g[1], g[2])
		holder.rotation_degrees.x = -90.0
		var gb := Node3D.new()
		holder.add_child(gb)
		var mi := MeshInstance3D.new()
		var gm := _blade_mesh(g[3], int(float(g[3]) * 14.0), 0.3)
		mi.mesh = gm
		mi.material_override = gear_m
		gb.add_child(mi)
		_cyl(float(g[3]) * 0.3, 0.5, rust2, Vector3.ZERO, Vector3(90, 0, 0), gb, 12)
		_spinners.append(gb)
		_spin_speed.append(g[4])
	for rz in [D * 0.5 - 0.6, D * 0.5 + 0.6]:
		var roller := Node3D.new()
		pit.add_child(roller)
		roller.position = Vector3(W * 0.5, -6.5, rz)
		roller.rotation_degrees.y = 90.0
		var rb := Node3D.new()
		roller.add_child(rb)
		_cyl(0.5, W + 4.0, rust, Vector3.ZERO, Vector3(90, 0, 0), rb, 14)
		var k := 0.0
		while k < W + 3.0:
			box(Vector3(0.12, 1.3, 0.12), Vector3(0, 0, -W * 0.5 - 1.5 + k), rust2, rb)
			k += 0.7
		_spinners.append(rb)
		_spin_speed.append(2.5 if rz < D * 0.5 else -2.5)
	box(Vector3(W + 4.0, 0.06, 0.4), Vector3(W * 0.5, -6.98, D * 0.5), _glow(Color(1.0, 0.25, 0.05), 3.0), pit)
	for pl in [[W * 0.5, -5.0, D * 0.5, Color(1.0, 0.25, 0.08), 4.0, 12.0], [-1.8, -3.0, 3.0, Color(1.0, 0.2, 0.08), 2.4, 7.0],
		[W + 1.8, -3.0, 7.0, Color(1.0, 0.2, 0.08), 2.4, 7.0], [W * 0.5, -2.0, -2.0, Color(0.4, 0.8, 0.7), 2.0, 8.0], [W * 0.5, -3.0, D + 3.0, Color(1.0, 0.3, 0.1), 2.5, 9.0]]:
		var o := OmniLight3D.new()
		o.position = Vector3(pl[0], pl[1], pl[2])
		o.light_color = pl[3]
		o.light_energy = pl[4]
		o.omni_range = pl[5]
		pit.add_child(o)

func _rect_for(k: int) -> Rect2:
	return Rect2(k * CW, k * CD, W - 2.0 * k * CW, D - 2.0 * k * CD)

func _build_floor() -> void:
	var fl := Node3D.new()
	fl.name = "Floor"
	world.add_child(fl)
	var m_plate := mat("rusty_metal_02", 0.7, Color(0.42, 0.45, 0.44))
	var m_grate := mat("metal_grate_rusty", 0.9, Color(0.6, 0.6, 0.57))
	var m_rust := mat("blue_metal_plate", 0.8, Color(0.55, 0.55, 0.5))
	var srcs: Array[StandardMaterial3D] = [m_plate, m_grate, m_rust]
	var warns: Array[StandardMaterial3D] = []
	for s in srcs:
		var wm: StandardMaterial3D = s.duplicate()
		wm.albedo_color = Color(1.0, 0.45, 0.4)
		wm.emission_enabled = true
		wm.emission = Color(1.0, 0.05, 0.03)
		wm.emission_energy_multiplier = 0.8
		warns.append(wm)
		_warn_mats.append(wm)
	var rivet := CylinderMesh.new()
	rivet.top_radius = 0.03
	rivet.bottom_radius = 0.04
	rivet.height = 0.03
	rivet.radial_segments = 8
	rivet.material = mat("rusty_metal_02", 3.0, Color(0.7, 0.66, 0.6))
	var edge := mat("rusty_metal_02", 1.2, Color(0.45, 0.42, 0.38))
	for r in ROWS:
		for c in COLS:
			var h: int = (c * 7 + r * 13) % 9
			var k: int = 1 if h == 0 or h == 4 else (2 if h == 7 else 0)
			var pos := Vector3((c + 0.5) * CW, -0.07, (r + 0.5) * CD)
			var mi := box(Vector3(CW - 0.06, 0.14, CD - 0.06), pos, srcs[k], fl)
			for sz in [-1.0, 1.0]:
				box(Vector3(CW - 0.06, 0.03, 0.05), Vector3(0, 0.07, sz * (CD * 0.5 - 0.055)), edge, mi)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var rv := MeshInstance3D.new()
					rv.mesh = rivet
					mi.add_child(rv)
					rv.position = Vector3(sx * (CW * 0.5 - 0.12), 0.08, sz * (CD * 0.5 - 0.12))
			_plates.append(mi)
			_plate_ring.append(mini(mini(c, COLS - 1 - c), mini(r, ROWS - 1 - r)))
			_plate_base.append(pos)
			_plate_mat.append(srcs[k])
			_plate_warn.append(warns[k])
	_grime(fl)

func _grime(parent: Node3D) -> void:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.seed = 17
	for y in n:
		for x in n:
			var dx := (x - n * 0.5) / (n * 0.5)
			var dy := (y - n * 0.5) / (n * 0.5)
			var v := 1.0 - sqrt(dx * dx + dy * dy) + noise.get_noise_2d(x, y) * 0.6
			img.set_pixel(x, y, Color(1, 1, 1, clampf((v - 0.25) * 2.0, 0.0, 0.85)))
	var tex := ImageTexture.create_from_image(img)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 22:
		var d := Decal.new()
		d.texture_albedo = tex
		var sz := rng.randf_range(1.0, 2.8)
		d.size = Vector3(sz, 0.8, sz * rng.randf_range(0.6, 1.0))
		var old_blood := i % 4 == 0
		d.modulate = Color(0.28, 0.04, 0.03, 0.9) if old_blood else (Color(0.1, 0.09, 0.06) if i % 3 != 0 else Color(0.24, 0.15, 0.07))
		d.rotation.y = rng.randf() * TAU
		parent.add_child(d)
		var edge_bias := rng.randf() < 0.6
		var px := rng.randf_range(0.3, 2.0) if edge_bias and rng.randf() < 0.5 else rng.randf_range(0.5, W - 0.5)
		if edge_bias and rng.randf() < 0.5:
			px = W - px
		d.position = Vector3(px, 0.1, rng.randf_range(0.3, D - 0.3))

func _build_banks() -> void:
	var beam := mat("rusty_metal", 1.0, Color(0.5, 0.45, 0.4))
	var guard := mat("rusty_metal_02", 1.0, Color(0.5, 0.48, 0.44))
	var motor := mat("green_metal_rust", 0.8, Color(0.45, 0.5, 0.46))
	for side in 4:
		var bk := Node3D.new()
		bk.name = "SawBank%d" % side
		world.add_child(bk)
		_banks.append(bk)
		if side == 1 or side == 3:
			bk.position = Vector3(W, 0.0, D)
			bk.rotation.y = PI
		if side < 2:
			box(Vector3(0.5, 0.5, D + 8.0), Vector3(-0.27, -0.3, D * 0.5), beam, bk)
			box(Vector3(0.08, 0.06, D + 8.0), Vector3(-0.02, -0.03, D * 0.5), _hz, bk)
			box(Vector3(0.1, 0.55, D + 8.0), Vector3(-0.62, 0.2, D * 0.5), guard, bk)
			for r in ROWS:
				var z := (r + 0.5) * CD
				var b := _blade(bk, Vector3(-0.12, -0.08, z), FIN_R, 17.0 if side == 0 else -17.0)
				var wz: float = z if side == 0 else D - z
				var sp: GPUParticles3D = null
				if r % 2 == 0:
					sp = _sparker(bk, Vector3(-0.12, -0.02, z + 0.55), Vector3(0.0, 1.0, 0.7), 18)
				_blades.append({"node": b, "c": wz, "axis": 1, "sp": sp})
			for ez in [-3.6, D + 3.6]:
				box(Vector3(1.0, 1.0, 1.4), Vector3(-0.4, 0.0, ez), motor, bk)
				_cyl(0.3, 1.1, beam, Vector3(-0.4, 0.0, ez), Vector3(0, 0, 90), bk, 12)
		else:
			box(Vector3(W + 8.0, 0.5, 0.5), Vector3(W * 0.5, -0.3, -0.27), beam, bk)
			box(Vector3(W + 8.0, 0.06, 0.08), Vector3(W * 0.5, -0.03, -0.02), _hz, bk)
			if side == 2:
				box(Vector3(W + 8.0, 0.75, 0.1), Vector3(W * 0.5, 0.3, -0.6), guard, bk)
			for c in COLS:
				var x := (c + 0.5) * CW
				var b := _blade(bk, Vector3(x, -0.12, -0.04), EDGE_R, 15.0 if side == 2 else -15.0)
				var wx: float = x if side == 2 else W - x
				var sp: GPUParticles3D = null
				if c % 2 == 1:
					sp = _sparker(bk, Vector3(x + 0.62, -0.02, -0.04), Vector3(1.0, 1.2, 0.3), 20)
				_blades.append({"node": b, "c": wx, "axis": 0, "sp": sp})
			for ex in [-3.6, W + 3.6]:
				box(Vector3(1.4, 1.0, 1.0), Vector3(ex, 0.0, -0.4), motor, bk)
				_cyl(0.3, 1.1, beam, Vector3(ex, 0.0, -0.4), Vector3(90, 0, 0), bk, 12)
			var hl := OmniLight3D.new()
			hl.light_color = Color(1.0, 0.55, 0.25)
			hl.light_energy = 1.1
			hl.omni_range = 4.0
			bk.add_child(hl)
			hl.position = Vector3(W * 0.5, 0.6, 0.3)
	_update_banks()

func _build_tracks() -> void:
	var dark := mat("rusty_metal", 1.6, Color(0.22, 0.2, 0.18))
	for i in TRACK_ROWS.size():
		var row: int = TRACK_ROWS[i]
		var tz: float = (row + 0.5) * CD
		var gm := _glow(Color(1.0, 0.4, 0.1), 0.25)
		for c in COLS:
			var mi: MeshInstance3D = _plates[row * COLS + c]
			box(Vector3(CW - 0.04, 0.02, 0.3), Vector3(0, 0.075, 0), dark, mi)
			box(Vector3(CW - 0.04, 0.024, 0.07), Vector3(0, 0.078, 0), gm, mi)
			for s in [-1.0, 1.0]:
				box(Vector3(CW - 0.04, 0.022, 0.06), Vector3(0, 0.077, s * 0.19), _hz, mi)
		var saw := Node3D.new()
		world.add_child(saw)
		saw.position = Vector3(1.0, -1.4, tz)
		box(Vector3(1.0, 0.34, 0.44), Vector3(0, 0.0, 0), mat("green_metal_rust", 1.0, Color(0.45, 0.48, 0.42)), saw)
		box(Vector3(1.04, 0.06, 0.48), Vector3(0, 0.18, 0), _hz, saw)
		for sx in [-0.42, 0.42]:
			_cyl(0.07, 0.5, mat("rusty_metal_02", 2.0), Vector3(sx, 0.05, 0), Vector3(90, 0, 0), saw, 8)
		_blade(saw, Vector3(0, 0.22, 0), SLIDE_R, 20.0 if i % 2 == 0 else -20.0)
		var sp1 := _sparker(saw, Vector3(0.62, 0.12, 0), Vector3(1.0, 1.1, 0.0), 40)
		var sp2 := _sparker(saw, Vector3(-0.62, 0.12, 0), Vector3(-1.0, 1.1, 0.0), 40)
		sp1.emitting = false
		sp2.emitting = false
		var lt := OmniLight3D.new()
		lt.light_color = Color(1.0, 0.55, 0.2)
		lt.light_energy = 0.0
		lt.omni_range = 3.5
		saw.add_child(lt)
		lt.position = Vector3(0, 1.0, 0.6)
		var au := AudioStreamPlayer3D.new()
		au.stream = _loop_stream()
		au.unit_size = 6.0
		au.pitch_scale = 1.5
		au.volume_db = -6.0
		saw.add_child(au)
		tracks.append({"row": row, "z": tz, "state": 0, "t_warn": -100.0, "t_on": 0.0, "dir": 1.0 if i % 2 == 0 else -1.0,
			"node": saw, "glow": gm, "sp": [sp1, sp2], "light": lt, "audio": au})

func _build_dressing() -> void:
	var d := Node3D.new()
	world.add_child(d)
	for h in [[-0.9, 1.0, 10.0], [W + 0.9, 8.6, 170.0]]:
		var n := prop("rusted_hacksaw", Vector3(h[0], 0.02, h[1]), h[2], 1.6, d)
		if n:
			n.rotation_degrees.x = 90.0

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
	_hum.volume_db = -15.0
	_hum.pitch_scale = 0.75
	add_child(_hum)
	_hum.play()

func _build_hud() -> void:
	hud_title("LETHAL REBOUND  ·  shove them into the saws")
	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-120, 10)
	_timer_label.size = Vector2(100, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(_timer_label, 26, Color("ffd34a"))
	hud.add_child(_timer_label)
	_board = Label.new()
	_board.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_board.position = Vector2(-220, 46)
	_board.size = Vector2(200, 200)
	_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(_board, 16, Color("e8e2c8"))
	hud.add_child(_board)
	_big = _center_label(84, 0.3)
	_hint = _center_label(24, 0.88)
	_hint.text = "WASD  MOVE   ·   SPACE  SHOVE\nhits stack · saws kill · the floor drops away"
	_hint.add_theme_color_override("font_color", Color("e8e2c8"))
	_refresh_board()

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

func _refresh_board() -> void:
	if not _board:
		return
	var ids: Array = players.keys()
	ids.sort_custom(func(a, b): return int(kills[a]) > int(kills[b]))
	var lines: Array = []
	for id in ids:
		var p: LabPlayer3D = players[id]
		lines.append("%s%s  %d" % ["" if p.alive else "† ", p.display_name, int(kills[id])])
	_board.text = "KILLS\n" + "\n".join(lines)

func _place_camera(k: float) -> void:
	var shrink: float = 1.0 - (bank[1] - bank[0]) / W
	var want := _cam_base.lerp(Vector3(_cam_look.x, 9.6, _cam_look.z + 5.0), clampf(shrink * 1.6, 0.0, 1.0))
	camera.position = camera.position.lerp(want, k)
	camera.look_at(_cam_look, Vector3.UP)

func _process(delta: float) -> void:
	if not world:
		return
	if st == St.RUN:
		clock += delta
		_handle_input()
	for i in _spinners.size():
		_spinners[i].rotation.z += _spin_speed[i] * delta
	var moved := false
	for i in 4:
		if bank[i] != bank_goal[i]:
			bank[i] = move_toward(bank[i], bank_goal[i], BANK_SPEED * delta)
			moved = true
	if moved:
		_update_banks()
		_update_bounds()
	_place_camera(1.0 - exp(-1.5 * delta))
	_update_plates()
	_update_tracks(delta)
	if st == St.RUN and NetworkManager.is_server():
		_server_tick(delta)

func _update_banks() -> void:
	_banks[0].position.x = bank[0]
	_banks[1].position.x = bank[1]
	_banks[2].position.z = bank[2]
	_banks[3].position.z = bank[3]
	for b in _blades:
		var c: float = b.c
		var vis: bool
		if int(b.axis) == 0:
			vis = c > bank[0] + 0.3 and c < bank[1] - 0.3
		else:
			vis = c > bank[2] + 0.2 and c < bank[3] - 0.2
		var n: Node3D = b.node
		n.visible = vis
		var sp: GPUParticles3D = b.sp
		if sp:
			sp.visible = vis
			sp.emitting = vis

func _update_bounds() -> void:
	for id in players:
		var p: LabPlayer3D = players[id]
		p.bounds = AABB(Vector3(bank[0] + 0.15, -5.0, bank[2] + 0.12), Vector3(bank[1] - bank[0] - 0.3, 20.0, bank[3] - bank[2] - 0.24))

func _update_plates() -> void:
	if _warn_plates.is_empty():
		return
	var t := clock - _ring_warn_t
	var blink := fmod(t, 0.36) < 0.18
	for wm in _warn_mats:
		wm.emission_energy_multiplier = 2.4 if blink else 0.6
	var amp := 0.012 + clampf(t / RING_WARN, 0.0, 1.0) * 0.04
	for i in _warn_plates:
		var mi := _plates[i]
		mi.position = _plate_base[i] + Vector3(randf_range(-amp, amp), randf_range(-amp, amp) * 0.5, randf_range(-amp, amp))
		mi.rotation = Vector3(randf_range(-amp, amp), 0.0, randf_range(-amp, amp)) * 0.6

func _saw_x(tr: Dictionary, at: float) -> float:
	var cx := (bank[0] + bank[1]) * 0.5
	var amp := maxf((bank[1] - bank[0]) * 0.5 - 0.95, 0.5)
	return cx + amp * float(tr.dir) * sin((at - float(tr.t_on)) * SLIDE_W - PI * 0.5)

func _update_tracks(delta: float) -> void:
	var blink := fmod(clock, 0.3) < 0.15
	for tr in tracks:
		var gm: StandardMaterial3D = tr.glow
		var node: Node3D = tr.node
		var s: int = tr.state
		if s == 1:
			gm.emission = Color(1.0, 0.05, 0.03)
			gm.emission_energy_multiplier = 4.0 if blink else 1.2
			node.position.x = _saw_x(tr, float(tr.t_on))
			node.position.y = move_toward(node.position.y, 0.0, delta * 1.2)
		elif s == 2:
			gm.emission = Color(1.0, 0.08, 0.04)
			gm.emission_energy_multiplier = 1.6
			node.position = Vector3(_saw_x(tr, clock), 0.0, float(tr.z))
			var lt: OmniLight3D = tr.light
			lt.light_energy = randf_range(1.2, 2.4)

func _handle_input() -> void:
	var me := local_player()
	if not me or not me.alive:
		return
	var down := Input.is_physical_key_pressed(KEY_SPACE)
	if down and not _space_down:
		if NetworkManager.is_server():
			_try_shove(multiplayer.get_unique_id())
		else:
			_rpc_press.rpc_id(1)
	_space_down = down

@rpc("any_peer", "reliable")
func _rpc_press() -> void:
	if NetworkManager.is_server():
		_try_shove(multiplayer.get_remote_sender_id())

func _fwd(p: LabPlayer3D) -> Vector3:
	return Vector3(sin(p._target_yaw), 0.0, cos(p._target_yaw))

func _try_shove(id: int) -> void:
	if st != St.RUN or not players.has(id) or not players[id].alive:
		return
	if clock < float(shove_ready[id]) or clock < float(lock_until[id]):
		return
	shove_ready[id] = clock + SHOVE_CD
	lock_until[id] = clock + 0.2
	var p: LabPlayer3D = players[id]
	var f := _fwd(p)
	var best := -1
	var best_d := SHOVE_REACH
	for o in alive_ids():
		if o == id:
			continue
		var to: Vector3 = players[o].position - p.position
		to.y = 0.0
		var d := to.length()
		if d > best_d:
			continue
		if d > 0.7 and f.dot(to / d) < 0.5:
			continue
		best = o
		best_d = d
	if best < 0:
		_rpc_shove.rpc(id, -1, p.position + f * LUNGE, Vector3.ZERO, 0)
		return
	var v: LabPlayer3D = players[best]
	var to_v: Vector3 = v.position - p.position
	to_v.y = 0.0
	var base: Vector3 = to_v.normalized() if to_v.length() > 0.05 else f
	if v.is_bot and _bot.has(best) and best_d > 0.6 and clock >= float(_bot[best].dodge_ready) and randf() < float(_bot[best].dodge):
		_bot[best].dodge_ready = clock + 2.5
		var side := Vector3(-base.z, 0.0, base.x)
		var c := Vector3((bank[0] + bank[1]) * 0.5, 0.0, (bank[2] + bank[3]) * 0.5)
		if side.dot(c - v.position) < 0.0:
			side = -side
		lock_until[best] = clock + 0.25
		_rpc_dodge.rpc(best, v.position + side * 1.5)
		_rpc_shove.rpc(id, -1, p.position + f * LUNGE, Vector3.ZERO, 0)
		return
	var dir := base
	if p.is_bot:
		var th: Array = _nearest_threat(v.position, 0.0)
		var sd: Vector3 = th[0]
		if base.dot(sd) > 0.2:
			dir = (base * 0.45 + sd * 0.55).normalized()
	else:
		dir = (base * 0.6 + f * 0.4).normalized()
	var stk: int = 0
	if clock - float(last_hit_t[best]) < STACK_WINDOW:
		stk = mini(int(stack[best]) + 1, 4)
	stack[best] = stk
	last_hit_t[best] = clock
	last_shover[best] = id
	last_shove_t[best] = clock
	lock_until[best] = clock + 0.5 + 0.12 * stk
	var dist: float = KNOCK * pow(1.7, stk)
	_rpc_shove.rpc(id, best, p.position + base * maxf(best_d - 0.65, 0.0), v.position + dir * dist, stk)

func _tween_move(id: int, to: Vector3, t: float) -> void:
	var p: LabPlayer3D = players[id]
	var dest := Vector3(clampf(to.x, p.bounds.position.x, p.bounds.end.x), p.position.y, clampf(to.z, p.bounds.position.z, p.bounds.end.z))
	if _push_tw.has(id):
		var old: Tween = _push_tw[id]
		if old and old.is_valid():
			old.kill()
	var tw := create_tween()
	tw.tween_property(p, "position", dest, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_push_tw[id] = tw

func _lock_input(p: LabPlayer3D, t: float) -> void:
	if not p.is_local_human():
		return
	p.input_enabled = false
	get_tree().create_timer(t).timeout.connect(func() -> void:
		if is_instance_valid(p) and p.alive and st == St.RUN:
			p.input_enabled = true)

@rpc("authority", "call_local", "reliable")
func _rpc_shove(a: int, v: int, lunge_to: Vector3, push_to: Vector3, stk: int) -> void:
	var pa: LabPlayer3D = players[a]
	if not pa.alive:
		return
	pa.face(lunge_to - pa.position)
	pa.body.play_action("Shield_Dash", 0.05, 1.6)
	Fx.sfx("whoosh", pa.position, -4.0, 1.1)
	if pa.is_multiplayer_authority():
		_tween_move(a, lunge_to, 0.17)
	_lock_input(pa, 0.2)
	if v < 0 or not players[v].alive:
		return
	var pv: LabPlayer3D = players[v]
	pv.face(pa.position - pv.position)
	pv.body.play_action("Hit_Knockback", 0.05, 1.2)
	Fx.sfx("hit", pv.position, -1.0 + float(stk) * 2.0, 1.0 - 0.08 * float(stk))
	if stk > 0:
		Fx.sparks(world, pv.position + Vector3(0, 1.1, 0))
	Fx.shake(0.15 + 0.1 * float(stk))
	if pv.is_multiplayer_authority():
		_tween_move(v, push_to, 0.36 + 0.05 * float(stk))
	_lock_input(pv, 0.5 + 0.12 * float(stk))

@rpc("authority", "call_local", "reliable")
func _rpc_dodge(id: int, dest: Vector3) -> void:
	var p: LabPlayer3D = players[id]
	if not p.alive:
		return
	p.face(dest - p.position)
	p.body.play_action("Shield_Dash", 0.05, 1.7)
	Fx.sfx("whoosh", p.position, -6.0, 1.3)
	if p.is_multiplayer_authority():
		_tween_move(id, dest, 0.2)

func _server_tick(delta: float) -> void:
	for k in RING_AT.size():
		var at: float = RING_AT[k]
		if not _ev.has("rw%d" % k) and clock >= at - RING_WARN:
			_ev["rw%d" % k] = true
			_rpc_ring_warn.rpc(k)
		if not _ev.has("rd%d" % k) and clock >= at:
			_ev["rd%d" % k] = true
			_rpc_ring_drop.rpc(k)
	for i in TRACK_ROWS.size():
		var at: float = TRACK_AT[i]
		if not _ev.has("tw%d" % i) and clock >= at - TRACK_WARN:
			_ev["tw%d" % i] = true
			_rpc_track_warn.rpc(i, clock + TRACK_WARN)
		if not _ev.has("to%d" % i) and clock >= at:
			_ev["to%d" % i] = true
			_rpc_track_on.rpc(i)
	for id in alive_ids():
		var pos: Vector3 = players[id].position
		var kind := -1
		var at := Vector3.ZERO
		if pos.x - bank[0] < KILL_X:
			kind = 0
			at = Vector3(bank[0], 0.4, pos.z)
		elif bank[1] - pos.x < KILL_X:
			kind = 0
			at = Vector3(bank[1], 0.4, pos.z)
		elif pos.z - bank[2] < KILL_Z:
			kind = 0
			at = Vector3(pos.x, 0.4, bank[2])
		elif bank[3] - pos.z < KILL_Z:
			kind = 0
			at = Vector3(pos.x, 0.4, bank[3])
		else:
			for tr in tracks:
				if int(tr.state) != 2:
					continue
				var sx := _saw_x(tr, clock)
				if absf(pos.z - float(tr.z)) < 0.45 and absf(pos.x - sx) < SLIDE_R + 0.25:
					kind = 1
					at = Vector3(sx, 0.4, float(tr.z))
					break
		if kind < 0 and not floor_rect.grow(0.05).has_point(Vector2(pos.x, pos.z)):
			kind = 2
			at = pos
		if kind >= 0:
			var killer: int = int(last_shover[id]) if clock - float(last_shove_t[id]) < CREDIT else -1
			if killer == id:
				killer = -1
			elim_order.append(id)
			_rpc_die.rpc(id, kind, at, killer)
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.25
		_rpc_sync.rpc(maxf(0.0, TIME_LIMIT - clock))

@rpc("authority", "call_local", "reliable")
func _rpc_ring_warn(k: int) -> void:
	_ring_warned = k
	_ring_warn_t = clock
	for i in _plates.size():
		if _plate_ring[i] == k:
			_warn_plates.append(i)
			_plates[i].material_override = _plate_warn[i]
	Fx.sfx("buzzer", null, -6.0, 0.6)
	Fx.sfx("arm", null, -6.0, 0.8)
	Fx.shake(0.12)
	_big_local("THE FLOOR IS GIVING WAY", "ff5a4a", 1.2, 46)

@rpc("authority", "call_local", "reliable")
func _rpc_ring_drop(k: int) -> void:
	ring = k + 1
	floor_rect = _rect_for(ring)
	bank_goal = [floor_rect.position.x, floor_rect.end.x, floor_rect.position.y, floor_rect.end.y]
	var n := 0
	for i in _warn_plates:
		var mi := _plates[i]
		mi.material_override = _plate_mat[i]
		var tw := create_tween().set_parallel(true)
		var delay := randf_range(0.0, 0.25)
		tw.tween_property(mi, "position:y", -9.0, 1.5).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(mi, "rotation", Vector3(randf_range(-1.2, 1.2), randf_range(-0.6, 0.6), randf_range(-1.2, 1.2)), 1.5).set_delay(delay)
		tw.chain().tween_callback(mi.hide)
		if n % 5 == 0:
			Fx.sparks(world, _plate_base[i] + Vector3(0, 0.1, 0))
		n += 1
	_warn_plates.clear()
	for id in players:
		var p: LabPlayer3D = players[id]
		if not p.alive and not floor_rect.has_point(Vector2(p.position.x, p.position.z)):
			var bt := create_tween()
			bt.tween_property(p.body, "position:y", -6.6, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Fx.sfx("hit", null, 0.0, 0.5)
	Fx.sfx("whoosh", null, -2.0, 0.6)
	Fx.sfx("hum", null, -4.0, 0.5)
	Fx.shake(0.55)

@rpc("authority", "call_local", "reliable")
func _rpc_track_warn(i: int, t_on: float) -> void:
	var tr: Dictionary = tracks[i]
	tr.state = 1
	tr.t_warn = clock
	tr.t_on = t_on
	var node: Node3D = tr.node
	node.position = Vector3(_saw_x(tr, t_on), -1.4, float(tr.z))
	var au: AudioStreamPlayer3D = tr.audio
	au.play()
	Fx.sfx("buzzer", Vector3(W * 0.5, 0.5, float(tr.z)), -4.0, 0.8)
	_big_local("SAW TRACK LIVE", "ff7a3a", 1.0, 46)

@rpc("authority", "call_local", "reliable")
func _rpc_track_on(i: int) -> void:
	var tr: Dictionary = tracks[i]
	tr.state = 2
	for sp in tr.sp:
		var g: GPUParticles3D = sp
		g.emitting = true
	var node: Node3D = tr.node
	Fx.sparks(world, node.position + Vector3(0, 0.3, 0))
	Fx.shake(0.2)

@rpc("authority", "call_local", "reliable")
func _rpc_die(id: int, kind: int, at: Vector3, killer: int) -> void:
	if not elim_order.has(id):
		elim_order.append(id)
	if killer >= 0 and kills.has(killer):
		kills[killer] = int(kills[killer]) + 1
	var p: LabPlayer3D = players[id]
	if _push_tw.has(id):
		var old: Tween = _push_tw[id]
		if old and old.is_valid():
			old.kill()
	if p.is_local_human():
		p.input_enabled = false
	if kind == 2:
		p.set_alive(false)
		p.body.die("Death01")
		Fx.sfx("whoosh", p.position, 0.0, 0.7)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(p.body, "position:y", -6.6, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(p.body, "rotation:x", randf_range(-1.5, 1.5), 0.95)
		tw.chain().tween_callback(func() -> void:
			var bottom := p.position + Vector3(0, -6.4, 0)
			Fx.sparks(world, bottom)
			Fx.sfx("splat", bottom, 4.0, 0.7)
			Fx.sfx("hit", bottom, 2.0, 0.5)
			Fx.shake(0.3))
	else:
		eliminate(id, "Death01")
		Fx.blood(world, at + Vector3(0, 0.5, 0), 150)
		Fx.sparks(world, at + Vector3(0, 0.4, 0))
		Fx.sparks(world, at + Vector3(0, 0.8, 0))
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
		var c := Vector3((bank[0] + bank[1]) * 0.5, 0.0, (bank[2] + bank[3]) * 0.5)
		var away := Vector3(p.position.x - at.x, 0.0, p.position.z - at.z)
		if away.length() < 0.05:
			away = c - p.position
		away.y = 0.0
		away = away.normalized()
		var land := away * randf_range(1.2, 1.9)
		var b: LabCharacter = p.body
		var tw := create_tween().set_parallel(true)
		tw.tween_property(b, "position:x", land.x, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "position:z", land.z, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var up := create_tween()
		up.tween_property(b, "position:y", randf_range(1.0, 1.6), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		up.tween_property(b, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		up.tween_callback(func() -> void:
			var spot := p.position + land
			if floor_rect.has_point(Vector2(spot.x, spot.z)):
				Fx.blood(world, spot + Vector3(0, 0.3, 0), 60)
			else:
				var fall := create_tween()
				fall.tween_property(b, "position:y", -6.6, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			Fx.sfx("splat", spot, 0.0, 0.9))
		for k in 2:
			var drip := at.lerp(p.position + land, 0.35 + 0.3 * k) + Vector3(randf_range(-0.4, 0.4), 0.3, randf_range(-0.4, 0.4))
			Fx.blood(world, drip, 30)
	_refresh_board()
	var me := local_player()
	if me and me.peer_id == id:
		_big_local("SHREDDED" if kind < 2 else "FELL", "ff4040", 1.4, 72)
	elif killer >= 0 and me and me.peer_id == killer:
		_big_local("KILL", "8fe36a", 0.8, 64)

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
	_big_local("FIGHT!", "8fe36a", 0.7)
	Fx.sfx("beep", null, -4.0, 1.4)
	var th := create_tween()
	th.tween_interval(6.0)
	th.tween_property(_hint, "modulate:a", 0.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_sync(time_left: float) -> void:
	_timer_label.text = "%d s" % int(ceil(time_left))

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
	while clock < TIME_LIMIT and alive_ids().size() > 1:
		await get_tree().process_frame
	_rpc_end.rpc(clock >= TIME_LIMIT)
	await get_tree().create_timer(2.4).timeout
	if not _ended:
		_ended = true
		finished.emit(_placement())

func _placement() -> Array:
	var ids: Array = players.keys()
	ids.sort_custom(func(a, b): return _rank(a) > _rank(b))
	return ids

func _rank(id: int) -> float:
	var alive := alive_ids()
	var r: float = float(kills.get(id, 0)) * 1000.0
	if players[id].alive:
		r += 500.0
		if alive.size() == 1:
			r += 100000.0
		return r
	return r + float(elim_order.find(id))

func _safe_rect(lag: float) -> Rect2:
	if _ring_warned >= ring and clock - _ring_warn_t > lag:
		return _rect_for(_ring_warned + 1)
	return Rect2(bank[0], bank[2], bank[1] - bank[0], bank[3] - bank[2])

func _nearest_threat(pos: Vector3, lag: float) -> Array:
	var r := _safe_rect(lag)
	var best_d: float = pos.x - r.position.x
	var best_dir := Vector3(-1, 0, 0)
	var cands := [[r.end.x - pos.x, Vector3(1, 0, 0)], [pos.z - r.position.y, Vector3(0, 0, -1)], [r.end.y - pos.z, Vector3(0, 0, 1)]]
	for c in cands:
		if float(c[0]) < best_d:
			best_d = c[0]
			best_dir = c[1]
	for tr in tracks:
		if int(tr.state) != 2:
			continue
		var sx := _saw_x(tr, clock)
		var dv := Vector3(sx - pos.x, 0.0, float(tr.z) - pos.z)
		var d := dv.length() - 0.6
		if d < best_d and dv.length() > 0.05:
			best_d = d
			best_dir = dv.normalized()
	return [best_dir, best_d]

func _pick_target(id: int) -> int:
	var p: LabPlayer3D = players[id]
	var best := -1
	var best_s := INF
	for o in alive_ids():
		if o == id:
			continue
		var op: Vector3 = players[o].position
		var th: Array = _nearest_threat(op, 0.5)
		var s: float = op.distance_to(p.position) + float(th[1]) * 0.7 + randf() * 1.5
		if s < best_s:
			best_s = s
			best = o
	return best

func _bot_brain(delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	if st != St.RUN or clock < float(lock_until[id]):
		return Vector3.ZERO
	var b: Dictionary = _bot[id]
	b.think = float(b.think) - delta
	if float(b.think) <= 0.0:
		b.think = randf_range(0.12, 0.24)
		b.lag = float(b.react) + (randf_range(0.6, 1.2) if randf() < float(b.greed) else 0.0)
		var t: int = b.target
		if t < 0 or not players.has(t) or not players[t].alive or randf() < 0.07:
			t = _pick_target(id)
		b.target = t
		if t >= 0:
			var tp: Vector3 = players[t].position
			var th: Array = _nearest_threat(tp, float(b.lag))
			var sd: Vector3 = th[0]
			b.goal = tp - sd * 1.05
			var to: Vector3 = tp - p.position
			to.y = 0.0
			if to.length() < 1.75 and clock >= float(shove_ready[id]):
				var reach: float = KNOCK * pow(1.7, int(stack[t]) + 1 if clock - float(last_hit_t[t]) < STACK_WINDOW else 0) + 0.6
				var aligned: bool = to.normalized().dot(sd) > 0.45 and float(th[1]) < reach
				if aligned and randf() < float(b.aggro) * 0.6:
					p.face(to)
					_try_shove(id)
					shove_ready[id] = float(shove_ready[id]) + randf_range(0.6, 1.4)
					return Vector3.ZERO
		else:
			b.goal = Vector3((bank[0] + bank[1]) * 0.5, 0.0, (bank[2] + bank[3]) * 0.5)
	var lag: float = b.lag
	var safe := _safe_rect(lag)
	var goal: Vector3 = b.goal
	goal.x = clampf(goal.x, safe.position.x + 1.1, maxf(safe.end.x - 1.1, safe.position.x + 1.1))
	goal.z = clampf(goal.z, safe.position.y + 0.95, maxf(safe.end.y - 0.95, safe.position.y + 0.95))
	var v := goal - p.position
	v.y = 0.0
	var mv := Vector3.ZERO
	if v.length() > 0.15:
		mv = v.normalized() * clampf(v.length() * 1.5, 0.0, 1.0)
	var push := Vector3.ZERO
	var m := 1.25
	var near := 99.0
	for o in alive_ids():
		if o != id:
			near = minf(near, p.position.distance_to(players[o].position))
	if near < 2.4:
		m = 2.0
		var own: Array = _nearest_threat(p.position, lag)
		if float(own[1]) < 2.6:
			var away: Vector3 = own[0]
			push -= away * 1.2
	if p.position.x < safe.position.x + m:
		push.x += (safe.position.x + m - p.position.x) * 2.2
	if p.position.x > safe.end.x - m:
		push.x -= (p.position.x - safe.end.x + m) * 2.2
	if p.position.z < safe.position.y + m:
		push.z += (safe.position.y + m - p.position.z) * 2.2
	if p.position.z > safe.end.y - m:
		push.z -= (p.position.z - safe.end.y + m) * 2.2
	for tr in tracks:
		var s: int = tr.state
		if s == 0 or clock - float(tr.t_warn) < lag:
			continue
		var dz: float = p.position.z - float(tr.z)
		if absf(dz) > 1.2:
			continue
		var sx: float = _saw_x(tr, clock) if s == 2 else _saw_x(tr, float(tr.t_on))
		if absf(sx - p.position.x) < 4.0:
			var sgn: float = signf(dz) if absf(dz) > 0.05 else signf((bank[2] + bank[3]) * 0.5 - float(tr.z) + 0.01)
			push.z += sgn * (1.2 - absf(dz)) * 3.2
			mv.z *= 0.3
	var out := mv + push
	return out.normalized() if out.length() > 0.05 else Vector3.ZERO
