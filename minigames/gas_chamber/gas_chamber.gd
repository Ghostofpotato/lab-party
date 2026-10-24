extends ArenaMinigame3D
## Gas Chamber: the decontamination room is sealed and the vents pump sickly green
## gas. Gas masks drop from the ceiling hatches, always fewer than there are living
## subjects; walk over one to wear it. Without a mask your gas meter fills and when it
## is full you collapse foaming. Every filter cracks after 12 s, so you need the next
## wave (every 8 s, fewer each time) or a rival's face: SPACE next to a masked subject
## rips the mask off (50% you get it, otherwise it drops). Last one breathing wins;
## after 50 s the survivors place first, the dead in reverse order of choking.

const TIME_LIMIT: float = 50.0
const GAS_START: float = 1.0
const GAS_RAMP: float = 7.0
const FILL_TIME: float = 6.5
const DRAIN: float = 0.1
const FILTER_TIME: float = 12.0
const FIRST_WAVE: float = 3.2
const WAVE_GAP: float = 8.0
const WARN_T: float = 1.3
const FALL_T: float = 0.65
const PICK_R: float = 0.8
const RIP_R: float = 1.5
const RIP_CD: float = 0.9
const STUN_T: float = 0.6
const BAR_PX: int = 100
const CUT_Y: float = -0.28
const MASK_OFS: Vector3 = Vector3(0.0, 0.075, 0.065)
const MOUTH: Vector3 = Vector3(0.0, 0.05, 0.15)
const HATCHES: Array[Vector3] = [Vector3(3.0, 4.0, 2.4), Vector3(8.0, 4.0, 2.0), Vector3(13.0, 4.0, 2.4), Vector3(4.8, 5.2, 7.3), Vector3(11.2, 5.2, 7.3)]
const VENTS: Array = [[Vector3(0.4, 1.75, -2.78), 0.0], [Vector3(15.4, 1.75, -2.78), 0.0], [Vector3(-2.78, 1.7, 5.0), 90.0], [Vector3(18.78, 1.7, 5.0), -90.0]]
const GAS_GREEN: Color = Color(0.46, 0.66, 0.2)

var clock: float = 0.0
var running: bool = false
var level: float = 0.0
var _vis_level: float = 0.0
var _time_left: float = TIME_LIMIT
var _done: bool = false
var _ended_local: bool = false
var gas: Dictionary = {}
var filt: Dictionary = {}
var wearer: Dictionary = {}
var masks: Dictionary = {}
var rip_cd: Dictionary = {}
var stun: Dictionary = {}
var dead_order: Array = []
var _bot: Dictionary = {}
var _next_mid: int = 1
var _next_wave: float = FIRST_WAVE
var _wave_no: int = 0
var _first_count: int = 1
var _sync_t: float = 0.0
var _space_down: bool = false
var _gas_announced: bool = false
var _hiss_t: float = 0.0
var _push_tw: Dictionary = {}
var _overlaid: Array[GeometryInstance3D] = []

var _mask_mesh: Mesh
var _full_mask_mesh: Mesh
var _ring_mesh: TorusMesh
var _ring_mat: StandardMaterial3D
var _husk_mat: StandardMaterial3D
var _soft: Texture2D
var _grime: Texture2D
var _bar_tex: ImageTexture
var _font: Font

var _faces: Dictionary = {}
var _worn: Dictionary = {}
var _worn_fx: Dictionary = {}
var _skin: Dictionary = {}
var _gas_bar: Dictionary = {}
var _filter_bar: Dictionary = {}
var _cough_t: Dictionary = {}

var _flaps: Array[Node3D] = []
var _hatch_lights: Array[OmniLight3D] = []
var _hatch_lens: Array[StandardMaterial3D] = []
var _hatch_floor: Array[StandardMaterial3D] = []
var _hatch_warn: Array[float] = []
var _vent_fx: Array[GPUParticles3D] = []
var _vent_lights: Array[OmniLight3D] = []
var _haze_low: GPUParticles3D
var _haze_high: GPUParticles3D
var _beacon: SpotLight3D
var _beacon_glow: OmniLight3D
var _beacon_mat: StandardMaterial3D
var _fog_base: Color = Color(0.3, 0.31, 0.26)
var _amb_base: Color = Color(0.6, 0.62, 0.55)

var _tint: ColorRect
var _visor: TextureRect
var _big: Label
var _help: Label
var _hud_time: Label
var _hud_board: Label
var _status: Label
var _gas_fill: ColorRect
var _filter_fill: ColorRect
var _filter_bg: ColorRect
var _filter_cap: Label

func begin() -> void:
	setup_arena(false)
	_font = load("res://assets/ui/VT323-Regular.ttf")
	_soft = _soft_tex()
	_grime = _grime_tex(17)
	_build_mask_meshes()
	_tune_env()
	_build_room()
	_build_door()
	_build_vents()
	_build_hatches()
	_build_dressing()
	_build_lights()
	_build_haze()
	camera.fov = 48.0
	camera.position = Vector3(W * 0.5, 9.4, 14.6)
	camera.look_at(Vector3(W * 0.5, 0.0, 4.4), Vector3.UP)
	spawn_players(_spawns())
	for id in players:
		var p: LabPlayer3D = players[id]
		p.input_enabled = false
		p.bot_brain = _bot_brain.bind(id)
		gas[id] = 0.0
		wearer[id] = -1
		rip_cd[id] = 0.0
		stun[id] = 0.0
		_cough_t[id] = randf_range(0.4, 1.4)
		_setup_body(id)
		if p.is_bot:
			p.speed = randf_range(4.0, 4.45)
			_bot[id] = {"think": 0.0, "wait": 0.0, "mode": "roam", "target": -1, "victim": -1, "goal": p.position,
				"react": randf_range(0.3, 0.7), "desperate": randf_range(0.5, 0.78), "aggro": randf_range(0.12, 0.5),
				"home": randi() % HATCHES.size(), "err": Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2)),
				"swing_at": 0.0, "roam_at": 0.0}
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _exit_tree() -> void:
	for g in _overlaid:
		if is_instance_valid(g):
			g.material_overlay = null
	_overlaid.clear()

func _spawns() -> Array:
	var n: int = NetworkManager.players.size()
	var a: Array = []
	for i in n:
		var ang: float = TAU * float(i) / float(maxi(n, 1)) + 0.4
		a.append(Vector3(W * 0.5 + cos(ang) * 4.6, 0.0, D * 0.5 + sin(ang) * 2.9))
	return a

func _build_mask_meshes() -> void:
	var scn: Node3D = load(PH_MOD + "old_gas_mask/old_gas_mask.gltf").instantiate()
	var found: Array = scn.find_children("*", "MeshInstance3D", true, false)
	var mi: MeshInstance3D = found[0]
	var src: Mesh = mi.mesh
	_full_mask_mesh = src
	var mat0: Material = mi.get_surface_override_material(0)
	if mat0 == null:
		mat0 = src.surface_get_material(0)
	var arrays: Array = src.surface_get_arrays(0)
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for i in range(0, idx.size() - 2, 3):
			if verts[idx[i]].y > CUT_Y and verts[idx[i + 1]].y > CUT_Y and verts[idx[i + 2]].y > CUT_Y:
				keep.append(idx[i])
				keep.append(idx[i + 1])
				keep.append(idx[i + 2])
		arrays[Mesh.ARRAY_INDEX] = keep
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(0, mat0)
		_mask_mesh = am
	else:
		_mask_mesh = src
	scn.free()
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.36
	_ring_mesh.outer_radius = 0.45
	_ring_mesh.rings = 32
	_ring_mesh.ring_segments = 6
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(0.75, 1.0, 0.45)
	_husk_mat = StandardMaterial3D.new()
	_husk_mat.albedo_color = Color(0.05, 0.05, 0.04, 0.6)
	_husk_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_husk_mat.roughness = 1.0

func _tune_env() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.45
	env.ambient_light_color = _amb_base
	env.ambient_light_energy = 0.52
	env.tonemap_exposure = 1.05
	env.fog_light_color = _fog_base
	env.fog_density = 0.006
	env.fog_height = -1.5
	env.fog_height_density = 0.0
	env.adjustment_saturation = 0.8

func _plain(col: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m

func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.3)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

func _cyl(top: float, bottom: float, h: float, m: Material, pos: Vector3, rot: Vector3, parent: Node, seg: int = 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
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
	noise.seed = 9
	for y in n:
		for x in n:
			var stripe := int(floor(float(x + y) / 16.0)) % 2
			var g := 0.7 + noise.get_noise_2d(x, y) * 0.45
			var c := Color(0.82, 0.62, 0.08) if stripe == 0 else Color(0.06, 0.06, 0.05)
			img.set_pixel(x, y, Color(c.r * g, c.g * g, c.b * g))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.9
	return m

func _grime_tex(seed_v: int) -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.seed = seed_v
	for y in n:
		for x in n:
			var dx := (x - n * 0.5) / (n * 0.5)
			var dy := (y - n * 0.5) / (n * 0.5)
			var v := 1.0 - sqrt(dx * dx + dy * dy) + noise.get_noise_2d(x, y) * 0.6
			img.set_pixel(x, y, Color(1, 1, 1, clampf((v - 0.25) * 2.0, 0.0, 0.9)))
	return ImageTexture.create_from_image(img)

func _soft_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	return t

func _label3d(text: String, size: int, pos: Vector3, parent: Node3D, col: Color, px: float = 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.shaded = true
	l.position = pos
	parent.add_child(l)
	return l

func _decal(parent: Node, pos: Vector3, size: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> Decal:
	var d := Decal.new()
	d.texture_albedo = _grime
	d.size = size
	d.modulate = col
	d.cull_mask = 1
	d.rotation_degrees = rot
	parent.add_child(d)
	d.position = pos
	return d

func _build_room() -> void:
	var room := Node3D.new()
	room.name = "DeconRoom"
	world.add_child(room)
	var m := 3.0
	var h := 6.5
	var tile_floor := mat("dirty_tiles", 0.55, Color(0.8, 0.82, 0.74))
	var tile_wall := mat("dirty_tiles", 0.62, Color(0.74, 0.77, 0.7))
	var upper := mat("concrete_wall_006", 0.4, Color(0.5, 0.5, 0.46))
	var trim := mat("rusty_metal_02", 1.2, Color(0.6, 0.56, 0.5))
	var skirt := mat("dirty_concrete", 0.8, Color(0.42, 0.42, 0.36))
	box(Vector3(W + m * 2.0, 0.2, D + m * 2.0), Vector3(W * 0.5, -0.1, D * 0.5), tile_floor, room)
	box(Vector3(W + m * 2.0, 3.2, 0.4), Vector3(W * 0.5, 1.6, -m), tile_wall, room)
	box(Vector3(W + m * 2.0, h - 3.2, 0.4), Vector3(W * 0.5, 3.2 + (h - 3.2) * 0.5, -m), upper, room)
	for sx in [-m, W + m]:
		box(Vector3(0.4, 3.2, D + m * 2.0), Vector3(sx, 1.6, D * 0.5), tile_wall, room)
		box(Vector3(0.4, h - 3.2, D + m * 2.0), Vector3(sx, 3.2 + (h - 3.2) * 0.5, D * 0.5), upper, room)
	box(Vector3(W + m * 2.0, 0.14, 0.12), Vector3(W * 0.5, 3.2, -m + 0.24), trim, room)
	box(Vector3(W + m * 2.0, 0.22, 0.08), Vector3(W * 0.5, 0.11, -m + 0.22), skirt, room)
	for s in [-1.0, 1.0]:
		var wx: float = W * 0.5 + s * (W * 0.5 + m - 0.24)
		box(Vector3(0.12, 0.14, D + m * 2.0), Vector3(wx, 3.2, D * 0.5), trim, room)
		box(Vector3(0.08, 0.22, D + m * 2.0), Vector3(W * 0.5 + s * (W * 0.5 + m - 0.22), 0.11, D * 0.5), skirt, room)
	box(Vector3(W + m * 2.0, 0.6, 0.3), Vector3(W * 0.5, 0.3, D + m), trim, room)
	var grate := mat("metal_grate_rusty", 1.6, Color(0.5, 0.48, 0.44))
	var dark := _plain(Color(0.02, 0.02, 0.018), 1.0)
	box(Vector3(13.2, 0.02, 0.46), Vector3(W * 0.5, 0.006, D * 0.5), dark, room)
	box(Vector3(13.0, 0.02, 0.38), Vector3(W * 0.5, 0.02, D * 0.5), grate, room)
	for s in [-1.0, 1.0]:
		box(Vector3(13.3, 0.03, 0.05), Vector3(W * 0.5, 0.015, D * 0.5 + s * 0.235), trim, room)
	for dp in [Vector3(1.6, 0, 1.2), Vector3(14.4, 0, 1.2), Vector3(1.6, 0, 8.8), Vector3(14.4, 0, 8.8)]:
		_cyl(0.38, 0.38, 0.02, trim, dp + Vector3(0, 0.01, 0), Vector3.ZERO, room, 24)
		_cyl(0.31, 0.31, 0.022, grate, dp + Vector3(0, 0.014, 0), Vector3.ZERO, room, 24)
		_decal(room, dp + Vector3(0, 0.1, 0), Vector3(1.8, 0.4, 1.6), Color(0.16, 0.15, 0.06, 0.9))
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in 26:
		var sz := rng.randf_range(0.8, 2.8)
		var col := Color(0.14, 0.13, 0.08, 0.85) if i % 3 != 0 else Color(0.22, 0.25, 0.1, 0.7)
		_decal(room, Vector3(rng.randf_range(-2.0, W + 2.0), 0.1, rng.randf_range(-2.4, D + 1.5)), Vector3(sz, 0.5, sz * rng.randf_range(0.5, 1.0)), col, Vector3(0, rng.randf() * 360.0, 0))
	for i in 6:
		_decal(room, Vector3(W * 0.5 + rng.randf_range(-6.0, 6.0), 0.08, D * 0.5 + rng.randf_range(-0.6, 0.6)), Vector3(1.2, 0.3, 0.6), Color(0.1, 0.12, 0.05, 0.9), Vector3(0, rng.randf() * 360.0, 0))
	_decal(room, Vector3(6.6, 0.1, -1.4), Vector3(1.4, 0.4, 1.0), Color(0.3, 0.02, 0.02, 0.8))
	_decal(room, Vector3(12.8, 0.1, 9.2), Vector3(1.0, 0.4, 0.8), Color(0.32, 0.03, 0.02, 0.7), Vector3(0, 40, 0))
	var pud := StandardMaterial3D.new()
	pud.albedo_texture = _grime_tex(41)
	pud.albedo_color = Color(0.06, 0.08, 0.04, 0.8)
	pud.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pud.roughness = 0.04
	pud.metallic_specular = 1.0
	for pp in [Vector3(2.1, 0.03, 1.6), Vector3(13.9, 0.03, 8.3), Vector3(6.0, 0.03, 5.2), Vector3(10.6, 0.03, 4.7), Vector3(2.4, 0.03, 8.5)]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(rng.randf_range(1.2, 2.2), rng.randf_range(0.9, 1.6))
		mi.mesh = pm
		mi.material_override = pud
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.y = rng.randf() * TAU
		room.add_child(mi)
		mi.position = pp
	_build_showers(room, trim)

func _shower_head(parent: Node3D, base: Vector3, out: Vector3, pipe: Material, head: Material) -> void:
	_cyl(0.035, 0.035, 0.5, pipe, base + Vector3(0, -0.25, 0), Vector3.ZERO, parent, 8)
	var arm := base + Vector3(0, -0.5, 0) + out * 0.16
	var rot := Vector3(90, 0, 0) if absf(out.z) > 0.5 else Vector3(0, 0, 90)
	_cyl(0.03, 0.03, 0.32, pipe, arm, rot, parent, 8)
	var tip := base + Vector3(0, -0.56, 0) + out * 0.34
	var tilt := Vector3(-25.0 * out.z, 0, 25.0 * out.x)
	_cyl(0.045, 0.15, 0.09, head, tip, tilt, parent, 18)
	_cyl(0.025, 0.025, 0.1, pipe, base + Vector3(0, -1.3, 0) + out * 0.06, Vector3(90, 0, 0) if absf(out.z) > 0.5 else Vector3(0, 0, 90), parent, 8)
	_cyl(0.07, 0.07, 0.02, head, base + Vector3(0, -1.3, 0) + out * 0.12, Vector3(90, 0, 0) if absf(out.z) > 0.5 else Vector3(0, 0, 90), parent, 10)
	_cyl(0.02, 0.02, 0.85, pipe, base + Vector3(0, -0.95, 0), Vector3.ZERO, parent, 6)
	var rot_d := Vector3(90, 0, 0) if absf(out.z) > 0.5 else Vector3(0, 0, -90.0 * signf(out.x))
	_decal(parent, base + Vector3(0, -1.6, 0) + out * 0.25, Vector3(0.45, 0.6, 1.8), Color(0.3, 0.2, 0.08, 0.75), rot_d)

func _build_showers(room: Node3D, trim: Material) -> void:
	var pipe := mat("rusty_metal_02", 1.5)
	var head := mat("rusty_metal", 2.0, Color(0.55, 0.55, 0.5))
	var bz := -2.62
	_cyl(0.06, 0.06, W + 5.6, pipe, Vector3(W * 0.5, 3.02, bz), Vector3(0, 0, 90), room, 10)
	_cyl(0.035, 0.035, W + 5.6, pipe, Vector3(W * 0.5, 2.86, bz + 0.04), Vector3(0, 0, 90), room, 8)
	for x in [1.95, 13.9]:
		_shower_head(room, Vector3(x, 3.0, bz), Vector3(0, 0, 1), pipe, head)
	for s in [-1.0, 1.0]:
		var sx: float = W * 0.5 + s * (W * 0.5 + 2.62)
		_cyl(0.06, 0.06, D + 5.6, pipe, Vector3(sx, 3.02, D * 0.5), Vector3(90, 0, 0), room, 10)
		for z in [1.8, 8.3]:
			_shower_head(room, Vector3(sx, 3.0, z), Vector3(-s, 0, 0), pipe, head)
	for x in [-1.2, 5.0, 11.0, 17.2]:
		box(Vector3(0.06, 0.24, 0.08), Vector3(x, 3.1, bz + 0.02), trim, room)

func _build_door() -> void:
	var dr := Node3D.new()
	dr.name = "BlastDoor"
	world.add_child(dr)
	var frame := mat("rusty_metal", 0.8, Color(0.45, 0.42, 0.38))
	var slab := mat("blue_metal_plate", 0.9, Color(0.55, 0.6, 0.55))
	var hz := _hazard_mat()
	var steel := mat("rusty_metal_02", 1.4, Color(0.6, 0.58, 0.52))
	var cx := W * 0.5
	var z := -2.62
	box(Vector3(5.1, 0.42, 0.6), Vector3(cx, 2.96, z), frame, dr)
	for jx in [cx - 2.3, cx + 2.3]:
		box(Vector3(0.5, 2.96, 0.6), Vector3(jx, 1.48, z), frame, dr)
		for k in 5:
			var bolt := box(Vector3(0.07, 0.07, 0.05), Vector3(jx, 0.35 + 0.55 * float(k), z + 0.32), steel, dr)
			bolt.rotation_degrees.z = 45.0
	box(Vector3(4.1, 2.76, 0.26), Vector3(cx, 1.38, z + 0.02), slab, dr)
	box(Vector3(4.1, 0.32, 0.28), Vector3(cx, 0.24, z + 0.03), hz, dr)
	box(Vector3(4.1, 0.26, 0.28), Vector3(cx, 2.55, z + 0.03), hz, dr)
	box(Vector3(0.05, 2.0, 0.28), Vector3(cx, 1.38, z + 0.04), _plain(Color(0.03, 0.03, 0.025), 1.0), dr)
	var wheel := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.34
	tm.outer_radius = 0.44
	tm.rings = 36
	tm.ring_segments = 10
	wheel.mesh = tm
	wheel.material_override = steel
	wheel.rotation_degrees.x = 90.0
	dr.add_child(wheel)
	wheel.position = Vector3(cx, 1.36, z + 0.22)
	_cyl(0.09, 0.09, 0.2, steel, Vector3(cx, 1.36, z + 0.2), Vector3(90, 0, 0), dr, 12)
	for k in 3:
		var sp := box(Vector3(0.78, 0.05, 0.05), Vector3(cx, 1.36, z + 0.22), steel, dr)
		sp.rotation_degrees.z = 60.0 * float(k) + 15.0
	for k in 3:
		box(Vector3(0.9, 0.12, 0.1), Vector3(cx + (-1.4 if k < 2 else 1.4), 0.75 + 0.9 * float(k % 2), z + 0.2), frame, dr)
	var sealed := _label3d("SEALED", 120, Vector3(cx, 2.08, z + 0.16), dr, Color(0.62, 0.06, 0.04))
	sealed.pixel_size = 0.0034
	var dec := _label3d("DECON 04", 96, Vector3(cx, 2.96, z + 0.31), dr, Color(0.85, 0.82, 0.7))
	dec.pixel_size = 0.0028
	_decal(dr, Vector3(cx + 0.9, 0.9, z + 0.25), Vector3(1.2, 0.5, 1.4), Color(0.18, 0.12, 0.06, 0.8), Vector3(90, 0, 0))
	_decal(dr, Vector3(cx - 1.2, 0.4, z + 0.25), Vector3(1.4, 0.5, 0.7), Color(0.12, 0.1, 0.06, 0.8), Vector3(90, 0, 0))
	box(Vector3(0.18, 0.18, 0.08), Vector3(cx + 2.85, 2.35, z - 0.08), _glow(Color(1.0, 0.08, 0.04), 3.0), dr)
	var red := OmniLight3D.new()
	red.light_color = Color(1.0, 0.1, 0.05)
	red.light_energy = 0.8
	red.omni_range = 2.2
	dr.add_child(red)
	red.position = Vector3(cx + 2.85, 2.35, z + 0.3)
	box(Vector3(0.5, 0.14, 0.34), Vector3(cx, 3.24, z + 0.05), steel, dr)
	_beacon_mat = _glow(Color(1.0, 0.62, 0.08), 2.0)
	_cyl(0.13, 0.15, 0.24, _beacon_mat, Vector3(cx, 3.42, z + 0.05), Vector3.ZERO, dr, 16)
	_beacon = SpotLight3D.new()
	_beacon.light_color = Color(1.0, 0.66, 0.15)
	_beacon.light_energy = 9.0
	_beacon.spot_range = 22.0
	_beacon.spot_angle = 26.0
	_beacon.spot_attenuation = 0.8
	dr.add_child(_beacon)
	_beacon.position = Vector3(cx, 3.45, z + 0.3)
	_beacon_glow = OmniLight3D.new()
	_beacon_glow.light_color = Color(1.0, 0.62, 0.12)
	_beacon_glow.light_energy = 1.2
	_beacon_glow.omni_range = 5.0
	dr.add_child(_beacon_glow)
	_beacon_glow.position = Vector3(cx, 3.2, z + 0.7)

func _build_vents() -> void:
	var frame := mat("rusty_metal", 0.9, Color(0.5, 0.5, 0.44))
	var slat := mat("green_metal_rust", 1.2, Color(0.45, 0.48, 0.42))
	var dark := _plain(Color(0.015, 0.02, 0.012), 1.0)
	var names := ["VENT A", "VENT B", "VENT C", "VENT D"]
	for i in VENTS.size():
		var vp: Vector3 = VENTS[i][0]
		var yaw: float = VENTS[i][1]
		var v := Node3D.new()
		world.add_child(v)
		v.position = vp
		v.rotation_degrees.y = yaw
		box(Vector3(1.7, 0.14, 0.24), Vector3(0, 0.62, 0), frame, v)
		box(Vector3(1.7, 0.14, 0.24), Vector3(0, -0.62, 0), frame, v)
		box(Vector3(0.14, 1.38, 0.24), Vector3(0.85, 0, 0), frame, v)
		box(Vector3(0.14, 1.38, 0.24), Vector3(-0.85, 0, 0), frame, v)
		box(Vector3(1.56, 1.1, 0.04), Vector3(0, 0, -0.08), dark, v)
		for k in 6:
			var s := box(Vector3(1.56, 0.05, 0.17), Vector3(0, -0.45 + 0.18 * float(k), 0.02), slat, v)
			s.rotation_degrees.x = 38.0
		for k in 4:
			box(Vector3(0.06, 0.06, 0.05), Vector3(0.78 * (1.0 if k % 2 == 0 else -1.0), 0.56 * (1.0 if k < 2 else -1.0), 0.13), mat("rusty_metal_02", 2.0), v)
		var vl := _label3d(names[i], 72, Vector3(0, 0.86, 0.13), v, Color(0.85, 0.8, 0.55))
		vl.pixel_size = 0.0028
		_decal(v, Vector3(0, -1.0, 0.2), Vector3(1.6, 0.5, 1.4), Color(0.22, 0.26, 0.08, 0.75), Vector3(90, 0, 0))
		var gl := OmniLight3D.new()
		gl.light_color = Color(0.5, 1.0, 0.25)
		gl.light_energy = 0.0
		gl.omni_range = 3.2
		v.add_child(gl)
		gl.position = Vector3(0, 0, 0.5)
		_vent_lights.append(gl)
		var gp := GPUParticles3D.new()
		gp.amount = 34
		gp.lifetime = 3.6
		gp.local_coords = false
		gp.amount_ratio = 0.0
		gp.visibility_aabb = AABB(Vector3(-7, -4, -2), Vector3(14, 9, 14))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.65, 0.4, 0.05)
		pm.direction = Vector3(0, -0.2, 1)
		pm.spread = 22.0
		pm.initial_velocity_min = 1.3
		pm.initial_velocity_max = 2.6
		pm.damping_min = 0.4
		pm.damping_max = 0.8
		pm.gravity = Vector3(0, -0.12, 0)
		pm.scale_min = 0.7
		pm.scale_max = 1.3
		pm.scale_curve = _grow_curve(0.3)
		pm.color_ramp = _gas_ramp(0.3)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.8
		gp.process_material = pm
		gp.draw_pass_1 = _gas_quad(1.1)
		gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.add_child(gp)
		gp.position = Vector3(0, 0, 0.25)
		_vent_fx.append(gp)

func _grow_curve(start: float) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, start))
	c.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct

func _gas_ramp(alpha: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	g.colors = PackedColorArray([Color(0.62, 0.82, 0.3, 0.0), Color(0.55, 0.78, 0.26, alpha), Color(0.42, 0.6, 0.2, alpha * 0.6), Color(0.35, 0.5, 0.18, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

func _gas_quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft
	m.disable_receive_shadows = true
	q.material = m
	return q

func _build_hatches() -> void:
	var duct := mat("green_metal_rust", 0.6, Color(0.55, 0.58, 0.5))
	var hz := _hazard_mat()
	var rust := mat("rusty_metal", 1.0, Color(0.6, 0.55, 0.5))
	var dark := _plain(Color(0.01, 0.01, 0.01), 1.0)
	for i in HATCHES.size():
		var hp: Vector3 = HATCHES[i]
		var n := Node3D.new()
		world.add_child(n)
		n.position = hp
		box(Vector3(0.95, 6.0, 0.95), Vector3(0, 3.06, 0), duct, n)
		box(Vector3(1.06, 0.14, 1.06), Vector3(0, 0.07, 0), hz, n)
		box(Vector3(1.03, 0.1, 1.03), Vector3(0, 1.3, 0), rust, n)
		box(Vector3(1.03, 0.1, 1.03), Vector3(0, 2.6, 0), rust, n)
		box(Vector3(0.82, 0.02, 0.82), Vector3(0, 0.01, 0), dark, n)
		var hinge := Node3D.new()
		n.add_child(hinge)
		hinge.position = Vector3(-0.44, -0.03, 0)
		var flap := box(Vector3(0.88, 0.05, 0.88), Vector3(0.44, 0, 0), rust, hinge)
		flap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_flaps.append(hinge)
		var lens := _glow(Color(1.0, 0.6, 0.08), 0.2)
		box(Vector3(0.18, 0.18, 0.06), Vector3(0, 0.42, 0.49), lens, n)
		_hatch_lens.append(lens)
		var ml := _label3d("M%d" % (i + 1), 96, Vector3(0, 0.82, 0.48), n, Color(0.9, 0.85, 0.6))
		ml.pixel_size = 0.003
		var hl := OmniLight3D.new()
		hl.light_color = Color(1.0, 0.62, 0.15)
		hl.light_energy = 0.0
		hl.omni_range = hp.y + 1.5
		n.add_child(hl)
		hl.position = Vector3(0, -0.4, 0)
		_hatch_lights.append(hl)
		_hatch_warn.append(-10.0)
		var mk := Node3D.new()
		world.add_child(mk)
		mk.position = Vector3(hp.x, 0.012, hp.z)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.66
		tm.outer_radius = 0.82
		tm.rings = 40
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = hz
		ring.scale = Vector3(1.0, 0.04, 1.0)
		mk.add_child(ring)
		var inner := MeshInstance3D.new()
		var tm2 := TorusMesh.new()
		tm2.inner_radius = 0.5
		tm2.outer_radius = 0.56
		tm2.rings = 36
		tm2.ring_segments = 6
		inner.mesh = tm2
		var fm := _glow(Color(1.0, 0.6, 0.1), 0.0)
		inner.material_override = fm
		inner.scale = Vector3(1.0, 0.04, 1.0)
		mk.add_child(inner)
		_hatch_floor.append(fm)
		var txt := _label3d("MASK DROP", 64, Vector3(0, 0.01, 1.02), mk, Color(0.85, 0.7, 0.2, 0.75))
		txt.rotation_degrees.x = -90.0
		txt.pixel_size = 0.0035

func _build_dressing() -> void:
	var items := [["steel_frame_shelves_02", -1.8, -2.2, 0, 1.0], ["medical_box", -0.6, -2.35, 20, 1.2], ["barrel_03", 4.2, -1.9, 0, 1.1],
		["barrel_03", 3.5, -1.4, 50, 1.1], ["metal_trash_can", 11.4, -2.1, 0, 1.0], ["korean_fire_extinguisher_01", 10.95, -2.5, 0, 1.0],
		["WetFloorSign_01", 14.6, -1.2, 20, 1.0], ["plastic_bottle_gallon", 16.4, -2.3, 0, 1.3], ["bleach_bottle", 16.8, -2.0, 40, 1.4],
		["steel_frame_shelves_03", 17.9, -2.2, 0, 1.0], ["cardboard_box_01", 1.2, -1.5, 15, 1.1], ["trashbag", 12.5, -1.4, 60, 1.0],
		["old_military_crate", -2.0, 1.4, 90, 1.1], ["wooden_military_crate", -2.1, 3.1, 80, 1.0], ["hand_truck", -1.6, 7.8, 60, 1.1],
		["trashbag", -2.0, 9.4, 0, 1.0], ["propane_tank", -2.4, 6.6, 0, 1.0], ["metal_trash_can", -2.0, 10.6, 0, 1.0],
		["barrel_03", 18.0, 1.0, 0, 1.15], ["barrel_03", 17.4, 1.7, 30, 1.15], ["portable_generator", 17.8, 7.4, -90, 1.1],
		["cardboard_box_01", 18.1, 9.2, 10, 1.2], ["trashbag", 17.6, 3.4, 120, 1.0], ["plastic_crate_01", 17.9, 10.4, -15, 1.2],
		["WetFloorSign_01", 0.4, 11.0, 30, 1.0], ["old_tyre", 15.4, 11.2, 0, 1.0], ["medical_box", 17.5, 8.8, 70, 1.1],
		["bleach_bottle", -1.4, 4.6, 0, 1.4], ["plastic_bottle_gallon", -2.3, 5.4, 30, 1.3]]
	for it in items:
		prop(it[0], Vector3(it[1], 0.0, it[2]), it[3], it[4])
	prop("power_box_01", Vector3(-2.76, 1.9, 7.2), 90.0, 1.2)
	prop("fire_alarm", Vector3(13.95, 1.7, -2.76), 0.0, 1.4)
	prop("security_camera_01", Vector3(-2.4, 3.0, -2.4), -45.0, 1.5)
	prop("security_camera_01", Vector3(18.4, 3.0, -2.4), -135.0, 1.5)
	prop("wall_clock", Vector3(12.4, 2.92, -2.77), 0.0, 1.2)
	prop("utility_box_01", Vector3(18.76, 1.8, 7.2), -90.0, 1.2)
	prop("mounted_fluorescent_lights", Vector3(-2.7, 3.7, 3.0), 90.0, 1.2)
	prop("mounted_fluorescent_lights", Vector3(18.7, 3.7, 3.0), -90.0, 1.2)
	_mask_station()
	_sign(Vector3(12.4, 2.18, -2.77), 0.0, "WARNING", "TOXIC AGENT IN USE\nNO ENTRY WITHOUT MASK")
	_sign(Vector3(18.77, 2.3, 1.5), -90.0, "REMAIN CALM", "BREATHE SLOWLY\nMASKS ARE NOT GUARANTEED")
	_sign(Vector3(-2.77, 2.3, 1.5), 90.0, "DECONTAMINATION", "CHAMBER 04  ·  SUBJECTS ONLY\nDO NOT HOLD YOUR BREATH")

func _sign(pos: Vector3, yaw: float, title: String, body: String) -> void:
	var s := Node3D.new()
	world.add_child(s)
	s.position = pos
	s.rotation_degrees.y = yaw
	s.rotation_degrees.z = randf_range(-2.5, 2.5)
	var hz := _hazard_mat()
	box(Vector3(1.9, 0.86, 0.03), Vector3.ZERO, mat("painted_concrete", 1.0, Color(0.95, 0.82, 0.3)), s)
	for e in [[Vector3(1.96, 0.07, 0.04), Vector3(0, 0.43, 0)], [Vector3(1.96, 0.07, 0.04), Vector3(0, -0.43, 0)],
			[Vector3(0.07, 0.86, 0.04), Vector3(0.96, 0, 0)], [Vector3(0.07, 0.86, 0.04), Vector3(-0.96, 0, 0)]]:
		box(e[0], e[1], hz, s)
	var t := _label3d(title, 96, Vector3(0, 0.2, 0.02), s, Color(0.08, 0.07, 0.05))
	t.pixel_size = 0.0028
	var b := _label3d(body, 44, Vector3(0, -0.15, 0.02), s, Color(0.1, 0.09, 0.06))
	b.pixel_size = 0.0024
	_decal(s, Vector3(0.4, -0.2, 0.05), Vector3(0.9, 0.2, 0.5), Color(0.2, 0.15, 0.08, 0.8), Vector3(90, 0, 0))

func _mask_station() -> void:
	var s := Node3D.new()
	world.add_child(s)
	s.position = Vector3(3.75, 0.0, -2.76)
	var steel := mat("rusty_metal_02", 1.5)
	box(Vector3(2.3, 0.06, 0.08), Vector3(0, 2.32, 0.04), steel, s)
	for k in 5:
		var hx: float = -0.9 + 0.45 * float(k)
		box(Vector3(0.03, 0.03, 0.14), Vector3(hx, 2.27, 0.1), steel, s)
		var tag := _label3d("%02d" % (k + 1), 40, Vector3(hx, 2.42, 0.09), s, Color(0.8, 0.78, 0.7))
		tag.pixel_size = 0.0025
	var hang := MeshInstance3D.new()
	hang.mesh = _full_mask_mesh
	s.add_child(hang)
	hang.position = Vector3(0.45, 2.22, 0.16)
	hang.rotation_degrees.z = 6.0
	var t := _label3d("MASK STATION  ·  1 PER SUBJECT", 64, Vector3(0, 2.68, 0.05), s, Color(0.85, 0.82, 0.7))
	t.pixel_size = 0.0026
	box(Vector3(2.4, 0.24, 0.02), Vector3(0, 2.68, 0.02), _plain(Color(0.12, 0.13, 0.1), 0.8), s)
	var husk := MeshInstance3D.new()
	husk.mesh = _mask_mesh
	husk.material_overlay = _husk_mat
	_overlaid.append(husk)
	world.add_child(husk)
	husk.position = Vector3(2.9, 0.1, -2.15)
	husk.rotation_degrees = Vector3(-80, 40, 20)
	husk.scale = Vector3.ONE * 1.2

func _build_lights() -> void:
	for lx in [4.6, 11.4]:
		var sp := lamp(Vector3(lx, 6.4, 4.6), 9.5, Color(1.0, 0.86, 0.66))
		sp.spot_angle = 64.0
	var key := SpotLight3D.new()
	key.light_color = Color(0.95, 1.0, 0.85)
	key.light_energy = 3.2
	key.spot_range = 16.0
	key.spot_angle = 50.0
	key.shadow_enabled = true
	world.add_child(key)
	key.position = Vector3(W * 0.5, 11.0, 6.0)
	key.rotation_degrees.x = -90.0
	for s in [-1.0, 1.0]:
		var fl := OmniLight3D.new()
		fl.light_color = Color(0.75, 0.95, 0.85)
		fl.light_energy = 1.1
		fl.omni_range = 6.0
		world.add_child(fl)
		fl.position = Vector3(W * 0.5 + s * (W * 0.5 + 2.2), 3.4, 3.0)
	var back := OmniLight3D.new()
	back.light_color = Color(0.85, 0.9, 0.7)
	back.light_energy = 0.9
	back.omni_range = 9.0
	world.add_child(back)
	back.position = Vector3(W * 0.5, 2.6, -1.0)

func _build_haze() -> void:
	_haze_low = _haze_layer(Vector3(W * 0.5, 0.35, D * 0.5 - 0.5), Vector3(9.5, 0.3, 6.5), 70, 2.6, 0.13)
	_haze_high = _haze_layer(Vector3(W * 0.5, 1.5, D * 0.5 - 0.5), Vector3(9.5, 0.5, 6.5), 50, 2.8, 0.09)

func _haze_layer(pos: Vector3, ext: Vector3, n: int, size: float, alpha: float) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = n
	gp.lifetime = 7.0
	gp.preprocess = 4.0
	gp.amount_ratio = 0.0
	gp.local_coords = false
	gp.visibility_aabb = AABB(Vector3(-12, -3, -9), Vector3(24, 8, 18))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ext
	pm.direction = Vector3(1, 0.2, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, 0.05, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.scale_curve = _grow_curve(0.5)
	pm.color_ramp = _gas_ramp(alpha)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 6.0
	gp.process_material = pm
	gp.draw_pass_1 = _gas_quad(size)
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(gp)
	gp.position = pos
	return gp

func _setup_body(id: int) -> void:
	var p: LabPlayer3D = players[id]
	var b: LabCharacter = p.body
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.32, 0.58, 0.1, 0.0)
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skin.roughness = 1.0
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = skin
		_overlaid.append(mi)
	_skin[id] = skin
	var sk: Skeleton3D = b.skeleton
	var face := Node3D.new()
	if sk and sk.find_bone("Head") >= 0:
		var hb: int = sk.find_bone("Head")
		var att := BoneAttachment3D.new()
		att.bone_name = "Head"
		sk.add_child(att)
		att.add_child(face)
		var head_rest: Transform3D = sk.global_transform * sk.get_bone_global_rest(hb)
		var want := Transform3D(b.global_transform.basis.orthonormalized(), head_rest.origin)
		face.transform = head_rest.affine_inverse() * want
	else:
		b.add_child(face)
		face.position = Vector3(0, 1.6, 0)
	_faces[id] = face
	var wp := Node3D.new()
	wp.position = MASK_OFS
	wp.scale = Vector3.ONE * 1.1
	wp.visible = false
	face.add_child(wp)
	var wm := MeshInstance3D.new()
	wm.mesh = _mask_mesh
	wm.layers = 2
	var ov := StandardMaterial3D.new()
	ov.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ov.albedo_color = Color(1.0, 0.12, 0.05, 0.0)
	wm.material_overlay = ov
	_overlaid.append(wm)
	wp.add_child(wm)
	_worn[id] = wp
	_worn_fx[id] = ov
	_gas_bar[id] = _bar(p, Vector3(0, LabPlayer3D.HEIGHT + 0.36, 0), Color("9bd23a"), 5)
	_filter_bar[id] = _bar(p, Vector3(0, LabPlayer3D.HEIGHT + 0.26, 0), Color("5fd6e8"), 7)

func _bar(parent: Node3D, at: Vector3, col: Color, prio: int) -> Sprite3D:
	if not _bar_tex:
		var img := Image.create(BAR_PX, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_bar_tex = ImageTexture.create_from_image(img)
	var bg := Sprite3D.new()
	bg.texture = _bar_tex
	bg.pixel_size = 0.0011
	bg.fixed_size = true
	bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bg.no_depth_test = true
	bg.modulate = Color(0.02, 0.02, 0.02, 0.75)
	bg.scale = Vector3(0.82, 1.5, 1.0)
	bg.render_priority = prio - 1
	parent.add_child(bg)
	bg.position = at
	bg.visible = false
	var fill := Sprite3D.new()
	fill.texture = _bar_tex
	fill.pixel_size = 0.0011
	fill.fixed_size = true
	fill.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fill.no_depth_test = true
	fill.centered = false
	fill.offset = Vector2(-BAR_PX * 0.5, -4.0)
	fill.scale = Vector3(0.78, 1.0, 1.0)
	fill.region_enabled = true
	fill.region_rect = Rect2(0, 0, 0, 8)
	fill.modulate = col
	fill.render_priority = prio
	parent.add_child(fill)
	fill.position = at
	fill.visible = false
	fill.set_meta("bg", bg)
	return fill

func _set_bar(fill: Sprite3D, on: bool, frac: float, col: Color) -> void:
	fill.visible = on
	(fill.get_meta("bg") as Sprite3D).visible = on
	if on:
		fill.region_rect = Rect2(0, 0, maxf(0.001, clampf(frac, 0.0, 1.0) * BAR_PX), 8)
		fill.modulate = col

func _style(l: Label, size: int, c: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)

func _anchor(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob

func _build_hud() -> void:
	_tint = ColorRect.new()
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.color = Color(0.3, 0.55, 0.08, 0.0)
	hud.add_child(_tint)
	_anchor(_tint, 0, 0, 1, 1, 0, 0, 0, 0)
	_visor = TextureRect.new()
	_visor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.05), Color(0.0, 0.02, 0.0, 0.82)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 0.5)
	gt.width = 256
	gt.height = 256
	_visor.texture = gt
	_visor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_visor.stretch_mode = TextureRect.STRETCH_SCALE
	_visor.visible = false
	hud.add_child(_visor)
	_anchor(_visor, 0, 0, 1, 1, 0, 0, 0, 0)
	hud_title("GAS CHAMBER  ·  keep a mask on your face")
	_help = Label.new()
	_help.text = "WASD move  ·  walk over a mask to wear it  ·  SPACE next to a masked rival rips it off (50% it's yours)\nfilters crack after 12 s  ·  every wave drops fewer masks than there are lungs"
	_style(_help, 16, Color("e8e2c8"))
	hud.add_child(_help)
	_anchor(_help, 0, 0, 1, 0, 16, 42, -16, 90)
	_hud_time = Label.new()
	_hud_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(_hud_time, 28, Color("ffd34a"))
	hud.add_child(_hud_time)
	_anchor(_hud_time, 1, 0, 1, 0, -140, 8, -18, 44)
	_hud_board = Label.new()
	_hud_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(_hud_board, 15, Color("e8e2c8"))
	hud.add_child(_hud_board)
	_anchor(_hud_board, 1, 0, 1, 0, -300, 44, -18, 260)
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(panel)
	_anchor(panel, 0.5, 1, 0.5, 1, -230, -98, 230, -14)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.position = Vector2(0, 0)
	_status.size = Vector2(460, 28)
	_style(_status, 20, Color("e8e2c8"))
	panel.add_child(_status)
	var cap := Label.new()
	cap.text = "GAS"
	cap.position = Vector2(0, 30)
	_style(cap, 15, Color("b8e07a"))
	panel.add_child(cap)
	var gbg := ColorRect.new()
	gbg.color = Color(0.02, 0.03, 0.02, 0.8)
	gbg.position = Vector2(64, 34)
	gbg.size = Vector2(396, 16)
	panel.add_child(gbg)
	_gas_fill = ColorRect.new()
	_gas_fill.color = Color("9bd23a")
	_gas_fill.position = Vector2(66, 36)
	_gas_fill.size = Vector2(0, 12)
	panel.add_child(_gas_fill)
	_filter_cap = Label.new()
	_filter_cap.text = "FILTER"
	_filter_cap.position = Vector2(0, 54)
	_style(_filter_cap, 15, Color("8fe3f0"))
	panel.add_child(_filter_cap)
	_filter_bg = ColorRect.new()
	_filter_bg.color = Color(0.02, 0.03, 0.03, 0.8)
	_filter_bg.position = Vector2(64, 58)
	_filter_bg.size = Vector2(396, 16)
	panel.add_child(_filter_bg)
	_filter_fill = ColorRect.new()
	_filter_fill.color = Color("5fd6e8")
	_filter_fill.position = Vector2(66, 60)
	_filter_fill.size = Vector2(0, 12)
	panel.add_child(_filter_fill)
	_big = Label.new()
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big.add_theme_font_size_override("font_size", 64)
	_big.add_theme_color_override("font_outline_color", Color.BLACK)
	_big.add_theme_constant_override("outline_size", 12)
	hud.add_child(_big)
	_anchor(_big, 0, 0.26, 1, 0.46, 0, 0, 0, 0)
	_hud_time.text = "%d" % int(TIME_LIMIT)
	_refresh_board()

func _big_local(text: String, c: Color, hold: float) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", c)
	_big.modulate.a = 1.0
	if hold > 0.0:
		var tw := create_tween()
		tw.tween_interval(hold)
		tw.tween_property(_big, "modulate:a", 0.0, 0.4)

func _refresh_board() -> void:
	var ids: Array = players.keys()
	ids.sort_custom(func(a, b) -> bool:
		var pa: bool = players[a].alive
		var pb: bool = players[b].alive
		if pa != pb:
			return pa
		return float(gas.get(a, 0.0)) < float(gas.get(b, 0.0)))
	var lines: Array = ["BREATHING"]
	for id in ids:
		var p: LabPlayer3D = players[id]
		var st: String
		if not p.alive:
			st = "† CHOKED"
		elif int(wearer.get(id, -1)) >= 0:
			st = "MASK %d s" % int(ceil(float(filt.get(id, FILTER_TIME))))
		else:
			st = "GAS %d%%" % int(float(gas.get(id, 0.0)) * 100.0)
		lines.append("%s  %s" % [p.display_name, st])
	_hud_board.text = "\n".join(lines)

func _level_at(t: float) -> float:
	var lv: float = clampf((t - GAS_START) / GAS_RAMP, 0.0, 1.0)
	if t > 30.0:
		lv += clampf((t - 30.0) / 20.0, 0.0, 1.0) * 0.3
	return lv

func _process(delta: float) -> void:
	if not world:
		return
	if running:
		clock += delta
		if NetworkManager.is_server():
			_server_tick(delta)
		if not _gas_announced and clock >= GAS_START:
			_gas_announced = true
			_big_local("VENTS OPEN", Color("b8e07a"), 0.9)
			Fx.sfx("hum", null, -4.0, 0.55)
			Fx.sfx("whoosh", null, -4.0, 0.4)
	_animate_env(delta)
	_animate_hatches(delta)
	_animate_masks(delta)
	_animate_players(delta)
	_local_input()
	_local_hud()

func _animate_env(delta: float) -> void:
	_vis_level = lerpf(_vis_level, level, clampf(delta * 2.0, 0.0, 1.0))
	var lv: float = _vis_level
	var k: float = clampf(lv, 0.0, 1.0)
	env.fog_density = 0.006 + 0.016 * k + 0.006 * maxf(lv - 1.0, 0.0)
	env.fog_light_color = _fog_base.lerp(Color(0.34, 0.5, 0.16), clampf(k * 1.3, 0.0, 1.0))
	env.fog_height = lerpf(-1.5, 1.3, k) + maxf(lv - 1.0, 0.0) * 2.0
	env.fog_height_density = 0.35 * k
	env.ambient_light_color = _amb_base.lerp(Color(0.5, 0.66, 0.38), k * 0.7)
	_haze_low.amount_ratio = clampf(k * 1.4, 0.0, 1.0)
	_haze_high.amount_ratio = clampf((lv - 0.45) * 1.6, 0.0, 1.0)
	var pumping: bool = clock >= GAS_START and (running or not _ended_local)
	for i in _vent_fx.size():
		_vent_fx[i].amount_ratio = 1.0 if pumping else 0.0
		_vent_lights[i].light_energy = (0.8 + sin(clock * 3.0 + float(i)) * 0.2) if pumping else 0.0
	if pumping and running:
		_hiss_t -= delta
		if _hiss_t <= 0.0:
			_hiss_t = randf_range(2.5, 4.0)
			var vp: Vector3 = VENTS[randi() % VENTS.size()][0]
			Fx.sfx("whoosh", vp, -10.0, randf_range(0.35, 0.5))
	if _beacon:
		var spin: float = 5.0 if running else 1.5
		_beacon.rotation = Vector3(-0.42, clock * spin, 0.0)
		var pulse: float = 0.6 + 0.4 * sin(clock * spin * 2.0)
		_beacon_glow.light_energy = 0.6 + pulse * (1.2 + k)
		_beacon_mat.emission_energy_multiplier = 1.5 + pulse * 3.0

func _animate_hatches(_delta: float) -> void:
	for i in _hatch_lights.size():
		var warn: bool = clock < _hatch_warn[i]
		var f: float = 0.0
		if warn:
			f = 1.0 if fmod(clock * 5.0, 1.0) < 0.55 else 0.15
		_hatch_lights[i].light_energy = f * 4.0
		_hatch_lens[i].emission_energy_multiplier = 0.2 + f * 6.0
		_hatch_floor[i].emission_energy_multiplier = f * 4.0

func _animate_masks(delta: float) -> void:
	_ring_mat.albedo_color = Color(0.75, 1.0, 0.45).lerp(Color(1.0, 0.95, 0.5), 0.5 + 0.5 * sin(clock * 6.0))
	for mid in masks:
		var m: Dictionary = masks[mid]
		if m.state != "floor" or not m.has("node"):
			continue
		var n: Node3D = m.node
		if n.visible and n.get_meta("landed", false):
			var holder: Node3D = n.get_meta("holder")
			holder.rotation.y += delta * 1.4

func _mouth(id: int) -> Vector3:
	var f: Node3D = _faces[id]
	return f.global_transform * MOUTH

func _animate_players(delta: float) -> void:
	for id in players:
		var p: LabPlayer3D = players[id]
		var g: float = float(gas.get(id, 0.0))
		var masked: bool = int(wearer.get(id, -1)) >= 0
		var skin: StandardMaterial3D = _skin[id]
		skin.albedo_color.a = (g * 0.45) if p.alive else 0.42
		var gcol := Color("9bd23a").lerp(Color("e8361e"), smoothstep(0.45, 0.95, g))
		if g > 0.75 and fmod(clock, 0.3) < 0.15:
			gcol = Color("ffe14a")
		_set_bar(_gas_bar[id], p.alive and g > 0.01 and (running or _ended_local), g, gcol)
		var f: float = float(filt.get(id, FILTER_TIME))
		var fcol := Color("5fd6e8")
		if f < 3.0 and fmod(clock, 0.24) < 0.12:
			fcol = Color("ff4a2e")
		_set_bar(_filter_bar[id], p.alive and masked, f / FILTER_TIME, fcol)
		var ov: StandardMaterial3D = _worn_fx[id]
		ov.albedo_color.a = (0.45 if fmod(clock, 0.3) < 0.15 else 0.0) if (masked and f < 3.0) else 0.0
		if p.alive and running and not masked and g > 0.25:
			_cough_t[id] = float(_cough_t[id]) - delta
			if float(_cough_t[id]) <= 0.0:
				_cough_t[id] = lerpf(2.4, 0.8, g) * randf_range(0.8, 1.25)
				_cough(id)

func _cough(id: int) -> void:
	var p: LabPlayer3D = players[id]
	p.body.play_action("Hit_Chest", 0.1, 1.35)
	var at := _mouth(id)
	var fwd: Vector3 = (p.body.global_transform.basis * Vector3(0, -0.15, 1)).normalized()
	_puff(at, fwd, 8, 1.1, 0.22, Color(0.6, 0.72, 0.4), 0.22)
	Fx.sfx("hit", at, -14.0, randf_range(0.5, 0.65))

func _puff(at: Vector3, dir: Vector3, n: int, spd: float, alpha: float, col: Color, size: float) -> void:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.amount = n
	gp.lifetime = 1.4
	gp.explosiveness = 0.8
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = 30.0
	pm.initial_velocity_min = spd * 0.5
	pm.initial_velocity_max = spd
	pm.gravity = Vector3(0, 0.1, 0)
	pm.damping_min = 1.0
	pm.damping_max = 1.8
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.scale_curve = _grow_curve(0.25)
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, alpha))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	gp.process_material = pm
	gp.draw_pass_1 = _gas_quad(size)
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(gp)
	gp.global_position = at
	gp.emitting = true
	get_tree().create_timer(2.0).timeout.connect(gp.queue_free)

func _bits(at: Vector3, n: int, col: Color, spd: float, size: float, life: float, grav: float, dir: Vector3, spread: float, box_shape: bool) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.amount = n
	gp.lifetime = life
	gp.explosiveness = 0.9
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = spd * 0.4
	pm.initial_velocity_max = spd
	pm.gravity = Vector3(0, -grav, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.angular_velocity_min = -400.0
	pm.angular_velocity_max = 400.0
	pm.color = col
	gp.process_material = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.2
	if box_shape:
		var bm := BoxMesh.new()
		bm.size = Vector3(size, size * 0.3, size * 0.7)
		bm.material = m
		gp.draw_pass_1 = bm
	else:
		var sm := SphereMesh.new()
		sm.radius = size
		sm.height = size * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = m
		gp.draw_pass_1 = sm
	world.add_child(gp)
	gp.global_position = at
	gp.emitting = true
	get_tree().create_timer(life + 0.6).timeout.connect(gp.queue_free)
	return gp

func _local_input() -> void:
	var lp := local_player()
	if lp == null:
		return
	var down := Input.is_physical_key_pressed(KEY_SPACE)
	if down and not _space_down and lp.alive and running:
		if NetworkManager.is_server():
			_try_rip(multiplayer.get_unique_id())
		else:
			_req_rip.rpc_id(1)
	_space_down = down

func _local_hud() -> void:
	if not _status:
		return
	_hud_time.text = "%d" % ceili(_time_left)
	var me := multiplayer.get_unique_id()
	if not players.has(me):
		_status.text = ""
		_tint.color.a = 0.0
		return
	var p: LabPlayer3D = players[me]
	var g: float = float(gas.get(me, 0.0))
	var masked: bool = int(wearer.get(me, -1)) >= 0
	var f: float = float(filt.get(me, FILTER_TIME))
	var a: float = g * 0.3
	if g > 0.6:
		a += (0.5 + 0.5 * sin(clock * (6.0 + g * 8.0))) * 0.12
	if not p.alive:
		a = 0.1
	_tint.color = Color(0.28, 0.55, 0.06, a)
	_visor.visible = masked and p.alive
	_gas_fill.size = Vector2(392.0 * clampf(g, 0.0, 1.0), 12)
	_gas_fill.color = Color("9bd23a").lerp(Color("e8361e"), smoothstep(0.45, 0.95, g))
	_filter_fill.visible = masked and p.alive
	_filter_bg.visible = _filter_fill.visible
	_filter_cap.visible = _filter_fill.visible
	_filter_fill.size = Vector2(392.0 * clampf(f / FILTER_TIME, 0.0, 1.0), 12)
	_filter_fill.color = Color("ff4a2e") if f < 3.0 and fmod(clock, 0.24) < 0.12 else Color("5fd6e8")
	if not p.alive:
		_status.text = "YOU CHOKED"
		_status.add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
	elif masked:
		_status.text = "MASK ON  ·  filter %.1f s" % f if f >= 3.0 else "FILTER CRACKING  ·  %.1f s" % f
		_status.add_theme_color_override("font_color", Color("8fe3f0") if f >= 3.0 else Color("ff8a5a"))
	elif g > 0.55:
		_status.text = "CHOKING  ·  rip a mask off a rival  [SPACE]"
		_status.add_theme_color_override("font_color", Color("ff8a5a"))
	else:
		_status.text = "NO MASK  ·  stand under a drop hatch"
		_status.add_theme_color_override("font_color", Color("e8e2c8"))

@rpc("any_peer", "reliable")
func _req_rip() -> void:
	if NetworkManager.is_server():
		_try_rip(multiplayer.get_remote_sender_id())

func _fwd(p: LabPlayer3D) -> Vector3:
	return Vector3(sin(p._target_yaw), 0.0, cos(p._target_yaw))

func _rip_target(id: int) -> int:
	var p: LabPlayer3D = players[id]
	var f := _fwd(p)
	var best := -1
	var best_d := RIP_R
	for o in alive_ids():
		if o == id or int(wearer[o]) < 0:
			continue
		var to: Vector3 = players[o].position - p.position
		to.y = 0.0
		var d := to.length()
		if d > best_d:
			continue
		if d > 0.75 and f.dot(to / maxf(d, 0.01)) < 0.3:
			continue
		best = o
		best_d = d
	return best

func _clamp_floor(q: Vector3) -> Vector3:
	return Vector3(clampf(q.x, 0.5, W - 0.5), 0.0, clampf(q.z, 0.5, D - 0.5))

func _try_rip(id: int) -> void:
	if not running or not players.has(id) or not players[id].alive:
		return
	if clock < float(rip_cd[id]) or float(stun[id]) > 0.0:
		return
	rip_cd[id] = clock + RIP_CD
	var v := _rip_target(id)
	if v < 0:
		_rpc_rip.rpc(id, -1, -1, false, Vector3.ZERO, Vector3.ZERO, 0.0)
		return
	var pa: LabPlayer3D = players[id]
	var pv: LabPlayer3D = players[v]
	var mid: int = wearer[v]
	wearer[v] = -1
	stun[v] = STUN_T
	var to := pv.position - pa.position
	to.y = 0.0
	var dir: Vector3 = to.normalized() if to.length() > 0.05 else _fwd(pa)
	var taken: bool = int(wearer[id]) < 0 and randf() < 0.5
	var m: Dictionary = masks[mid]
	var drop := _clamp_floor(pv.position + dir * 1.1 + dir.cross(Vector3.UP) * randf_range(-0.5, 0.5))
	if taken:
		wearer[id] = mid
		m.state = "worn"
	else:
		m.state = "floor"
		m.pos = drop
		m.pick_after = clock + 0.45
	_rpc_rip.rpc(id, v, mid, taken, drop, _clamp_floor(pv.position + dir * 0.7), float(m.filter))

func _server_tick(delta: float) -> void:
	level = _level_at(clock)
	_server_waves()
	for id in stun:
		stun[id] = maxf(float(stun[id]) - delta, 0.0)
	for mid in masks:
		var m: Dictionary = masks[mid]
		if m.state == "incoming" and clock >= float(m.land_at):
			m.state = "floor"
			m.pick_after = float(m.land_at)
	var ids: Array = alive_ids()
	ids.shuffle()
	for id in ids:
		var mid: int = wearer[id]
		if mid >= 0:
			var m: Dictionary = masks[mid]
			m.filter = float(m.filter) - delta
			gas[id] = maxf(0.0, float(gas[id]) - DRAIN * delta)
			if float(m.filter) <= 0.0:
				m.filter = 0.0
				m.state = "dead"
				wearer[id] = -1
				_rpc_crack.rpc(id, mid)
			continue
		gas[id] = float(gas[id]) + level / FILL_TIME * delta
		if float(gas[id]) >= 1.0:
			gas[id] = 1.0
			dead_order.append(id)
			_rpc_collapse.rpc(id)
			continue
		if float(stun[id]) > 0.0:
			continue
		var p: LabPlayer3D = players[id]
		for mk in masks:
			var mm: Dictionary = masks[mk]
			if mm.state != "floor" or clock < float(mm.pick_after):
				continue
			var mp: Vector3 = mm.pos
			if Vector2(p.position.x - mp.x, p.position.z - mp.z).length() < PICK_R:
				mm.state = "worn"
				wearer[id] = mk
				_rpc_wear.rpc(id, mk, float(mm.filter))
				break
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.1
		var f: Dictionary = {}
		for id in wearer:
			if int(wearer[id]) >= 0:
				f[id] = float(masks[int(wearer[id])].filter)
		_rpc_sync.rpc(gas, f, level, maxf(0.0, TIME_LIMIT - clock))

func _server_waves() -> void:
	if clock < _next_wave - WARN_T or clock > TIME_LIMIT - 3.0:
		return
	var alive_n: int = alive_ids().size()
	var cap: int = alive_n - 1 if players.size() > 1 else 1
	if cap <= 0:
		_next_wave += WAVE_GAP
		return
	if _wave_no == 0:
		_first_count = cap
	var count: int = clampi(_first_count - _wave_no, 1, cap)
	var release: float = _next_wave
	_next_wave += WAVE_GAP
	_wave_no += 1
	var order: Array = range(HATCHES.size())
	order.shuffle()
	var mids: Array = []
	var hs: Array = []
	var lands: Array = []
	var delays: Array = []
	for i in count:
		var h: int = order[i % HATCHES.size()]
		var hp: Vector3 = HATCHES[h]
		var dl: float = float(i / HATCHES.size()) * 0.45
		var land := _clamp_floor(Vector3(hp.x + randf_range(-0.45, 0.45), 0.0, hp.z + randf_range(-0.45, 0.45)))
		var mid := _next_mid
		_next_mid += 1
		masks[mid] = {"state": "incoming", "filter": FILTER_TIME, "pos": land, "land_at": release + dl + FALL_T, "pick_after": 0.0, "warn_at": clock}
		mids.append(mid)
		hs.append(h)
		lands.append(land)
		delays.append(dl)
	_rpc_wave.rpc(mids, hs, lands, delays, release - clock, count, alive_n)

func _make_floor_mask() -> Node3D:
	var root := Node3D.new()
	world.add_child(root)
	var holder := Node3D.new()
	root.add_child(holder)
	holder.position.y = 0.17
	var mi := MeshInstance3D.new()
	mi.mesh = _mask_mesh
	mi.rotation_degrees.x = -90.0
	mi.scale = Vector3.ONE * 1.35
	holder.add_child(mi)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.material_override = _ring_mat
	ring.scale = Vector3(1.0, 0.05, 1.0)
	ring.position.y = 0.02
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	root.add_child(ring)
	root.set_meta("holder", holder)
	root.set_meta("ring", ring)
	root.set_meta("mesh", mi)
	root.set_meta("landed", false)
	return root

func _mask_node(mid: int) -> Node3D:
	var m: Dictionary = masks[mid]
	if not m.has("node"):
		var n := _make_floor_mask()
		n.visible = false
		m["node"] = n
	return m.node

func _show_on_floor(n: Node3D, pos: Vector3) -> void:
	n.visible = true
	n.position = pos
	(n.get_meta("ring") as Node3D).visible = true
	n.set_meta("landed", true)
	var holder: Node3D = n.get_meta("holder")
	holder.rotation = Vector3(0, holder.rotation.y, 0)
	holder.position.y = 0.17

@rpc("authority", "call_local", "reliable")
func _rpc_wave(mids: Array, hs: Array, lands: Array, delays: Array, lead: float, count: int, alive_n: int) -> void:
	for i in mids.size():
		var mid: int = mids[i]
		var h: int = hs[i]
		var land: Vector3 = lands[i]
		var dl: float = delays[i]
		if not masks.has(mid):
			masks[mid] = {"state": "incoming", "filter": FILTER_TIME, "pos": land, "land_at": clock + lead + dl + FALL_T, "pick_after": 0.0, "warn_at": clock}
		var n := _mask_node(mid)
		n.visible = false
		_hatch_warn[h] = maxf(_hatch_warn[h], clock + lead + dl)
		get_tree().create_timer(maxf(lead + dl, 0.01)).timeout.connect(_release.bind(h, mid))
	_big_local("%d MASKS  ·  %d LUNGS" % [count, alive_n], Color("ffb02e"), 1.3)
	Fx.sfx("beep", null, -3.0, 0.9)
	Fx.sfx("arm", null, -6.0, 0.8)

func _release(h: int, mid: int) -> void:
	if not is_instance_valid(world) or not masks.has(mid):
		return
	var m: Dictionary = masks[mid]
	var hp: Vector3 = HATCHES[h]
	var hinge: Node3D = _flaps[h]
	var ft := hinge.create_tween()
	ft.tween_property(hinge, "rotation:z", -1.95, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ft.tween_interval(1.1)
	ft.tween_property(hinge, "rotation:z", 0.0, 0.3).set_trans(Tween.TRANS_QUAD)
	Fx.sfx("click", hp, -2.0, 0.7)
	Fx.sfx("whoosh", hp, -4.0, 1.2)
	if m.state != "incoming" and m.state != "floor":
		return
	var n := _mask_node(mid)
	var land: Vector3 = m.pos
	n.visible = true
	n.position = Vector3(hp.x, hp.y - 0.15, hp.z)
	var holder: Node3D = n.get_meta("holder")
	holder.rotation = Vector3(randf_range(-1.0, 1.0), randf() * TAU, randf_range(-1.0, 1.0))
	var tw := n.create_tween()
	tw.tween_property(n, "position", land, FALL_T).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(holder, "rotation", Vector3(0.0, randf() * TAU, 0.0), FALL_T)
	tw.tween_callback(func() -> void:
		if m.state == "incoming":
			m.state = "floor"
		if m.state == "floor":
			_show_on_floor(n, land)
			var tb := n.create_tween()
			tb.tween_property(holder, "position:y", 0.34, 0.1).set_ease(Tween.EASE_OUT)
			tb.tween_property(holder, "position:y", 0.17, 0.12).set_ease(Tween.EASE_IN)
		_puff(land + Vector3(0, 0.1, 0), Vector3.UP, 8, 0.8, 0.25, Color(0.6, 0.62, 0.5), 0.4)
		Fx.sfx("hit", land, -8.0, 0.8))

@rpc("authority", "call_local", "reliable")
func _rpc_wear(id: int, mid: int, f: float) -> void:
	if not players.has(id) or not masks.has(mid):
		return
	var m: Dictionary = masks[mid]
	m.state = "worn"
	m.filter = f
	wearer[id] = mid
	filt[id] = f
	if m.has("node"):
		(m.node as Node3D).visible = false
	_pop_worn(id)
	var p: LabPlayer3D = players[id]
	Fx.sfx("click", p.position + Vector3(0, 1.6, 0), -2.0, 1.3)
	_puff(_mouth(id), Vector3.UP, 6, 0.5, 0.2, Color(0.8, 0.85, 0.75), 0.25)
	if p.is_local_human():
		_big_local("MASK ON", Color("8fe36a"), 0.6)
	_refresh_board()

func _pop_worn(id: int) -> void:
	var wm: Node3D = _worn[id]
	wm.visible = true
	wm.scale = Vector3.ONE * 0.6
	var tw := wm.create_tween()
	tw.tween_property(wm, "scale", Vector3.ONE * 1.1, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
		if is_instance_valid(p) and p.alive and running:
			p.input_enabled = true)

@rpc("authority", "call_local", "reliable")
func _rpc_rip(a: int, v: int, mid: int, taken: bool, drop: Vector3, push_to: Vector3, f: float) -> void:
	var pa: LabPlayer3D = players[a]
	if not pa.alive:
		return
	pa.body.play_action("Melee_Hook", 0.06, 1.5)
	Fx.sfx("whoosh", pa.position + Vector3(0, 1.2, 0), -4.0, 1.2)
	if v < 0 or not players.has(v):
		return
	var pv: LabPlayer3D = players[v]
	pa.face(pv.position - pa.position)
	pv.face(pa.position - pv.position)
	pv.body.play_action("Hit_Head", 0.05, 1.2)
	var from := _mouth(v)
	Fx.sfx("hit", from, 0.0, 0.9)
	Fx.shake(0.15)
	if pv.is_multiplayer_authority():
		_tween_move(v, push_to, 0.3)
	_lock_input(pv, STUN_T)
	wearer[v] = -1
	filt.erase(v)
	(_worn[v] as Node3D).visible = false
	_puff(from, Vector3.UP, 8, 0.6, 0.25, Color(0.8, 0.82, 0.7), 0.25)
	if not masks.has(mid):
		return
	var m: Dictionary = masks[mid]
	m.filter = f
	if taken:
		m.state = "worn"
		wearer[a] = mid
		filt[a] = f
		_pop_worn(a)
		Fx.sfx("click", pa.position + Vector3(0, 1.6, 0), 0.0, 1.4)
		if pa.is_local_human():
			_big_local("STOLEN!", Color("8fe36a"), 0.7)
	else:
		m.state = "floor"
		m.pos = drop
		var n := _mask_node(mid)
		n.visible = true
		n.set_meta("landed", false)
		(n.get_meta("ring") as Node3D).visible = false
		n.global_position = from
		var holder: Node3D = n.get_meta("holder")
		holder.position.y = 0.0
		var peak := (from + drop) * 0.5 + Vector3(0, 0.9, 0)
		var tw := n.create_tween()
		tw.tween_property(n, "global_position", peak, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(holder, "rotation", Vector3(randf_range(2.0, 4.0), randf() * TAU, randf_range(-2.0, 2.0)), 0.4)
		tw.tween_property(n, "global_position", drop, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			if m.state == "floor":
				_show_on_floor(n, drop)
			Fx.sfx("hit", drop, -8.0, 1.3))
		if pa.is_local_human():
			_big_local("IT SLIPPED", Color("ffb02e"), 0.6)
	if pv.is_local_human():
		_big_local("MASK RIPPED OFF", Color(1.0, 0.35, 0.2), 0.8)
	_refresh_board()

@rpc("authority", "call_local", "reliable")
func _rpc_crack(id: int, mid: int) -> void:
	wearer[id] = -1
	filt.erase(id)
	var p: LabPlayer3D = players[id]
	(_worn[id] as Node3D).visible = false
	var at := _mouth(id) + Vector3(0, 0.05, 0)
	_bits(at, 24, Color(0.82, 0.86, 0.8), 2.6, 0.035, 0.9, 9.0, Vector3.UP, 70.0, true)
	_puff(at, Vector3.UP, 10, 0.8, 0.28, Color(0.55, 0.7, 0.35), 0.3)
	Fx.sfx("hit", at, -2.0, 1.9)
	Fx.sfx("click", at, 0.0, 0.6)
	if masks.has(mid):
		var m: Dictionary = masks[mid]
		m.state = "dead"
		var n := _mask_node(mid)
		n.visible = true
		n.set_meta("landed", false)
		(n.get_meta("ring") as Node3D).visible = false
		var mi: MeshInstance3D = n.get_meta("mesh")
		mi.material_overlay = _husk_mat
		_overlaid.append(mi)
		n.global_position = at
		var holder: Node3D = n.get_meta("holder")
		holder.position.y = 0.0
		var land := p.position + Vector3(randf_range(-0.5, 0.5), 0.12, randf_range(-0.5, 0.5))
		var tw := n.create_tween()
		tw.tween_property(n, "global_position", land, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(holder, "rotation", Vector3(randf_range(-0.4, 0.4), randf() * TAU, PI * 0.45), 0.45)
	p.body.play_action("Hit_Head", 0.08, 1.0)
	if p.is_local_human():
		_big_local("FILTER CRACKED", Color(1.0, 0.4, 0.2), 0.9)
	_refresh_board()

@rpc("authority", "call_local", "reliable")
func _rpc_collapse(id: int) -> void:
	var p: LabPlayer3D = players[id]
	if not p.alive:
		return
	if not dead_order.has(id):
		dead_order.append(id)
	gas[id] = 1.0
	if _push_tw.has(id):
		var old: Tween = _push_tw[id]
		if old and old.is_valid():
			old.kill()
	p.set_alive(false)
	if p.is_local_human():
		p.input_enabled = false
		_big_local("YOU CHOKED", Color(0.7, 1.0, 0.3), 1.6)
	var b: LabCharacter = p.body
	for k in 3:
		get_tree().create_timer(0.28 * float(k)).timeout.connect(func() -> void:
			if not is_instance_valid(b) or b.is_dead():
				return
			b.play_action("Hit_Chest", 0.05, 1.6)
			var at := _mouth(id)
			_puff(at, (b.global_transform.basis * Vector3(0, -0.2, 1)).normalized(), 10, 1.3, 0.3, Color(0.62, 0.74, 0.4), 0.26)
			Fx.sfx("hit", at, -6.0, randf_range(0.45, 0.6)))
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if not is_instance_valid(b):
			return
		b.die("Death01")
		Fx.sfx("buzzer", null, -6.0, 0.7)
		Fx.sfx("splat", p.position, -4.0, 1.3)
		Fx.shake(0.25)
		_foam(id))
	get_tree().create_timer(2.6).timeout.connect(func() -> void:
		if not is_instance_valid(b):
			return
		var hp := _mouth(id)
		_decal(world, Vector3(hp.x, 0.15, hp.z), Vector3(0.9, 0.5, 0.75), Color(0.86, 0.92, 0.74, 0.9), Vector3(0, randf() * 360.0, 0))
		_decal(world, Vector3(hp.x, 0.15, hp.z), Vector3(0.45, 0.5, 0.35), Color(0.45, 0.05, 0.03, 0.85), Vector3(0, randf() * 360.0, 0)))
	_refresh_board()

func _foam(id: int) -> void:
	var face: Node3D = _faces[id]
	var gp := GPUParticles3D.new()
	gp.amount = 46
	gp.lifetime = 1.3
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -0.3, 1)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, -2.5, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.4
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.98, 0.88, 1.0))
	g.set_color(1, Color(0.78, 0.88, 0.6, 1.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	gp.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.028
	sm.height = 0.05
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.15
	sm.material = m
	gp.draw_pass_1 = sm
	face.add_child(gp)
	gp.position = MOUTH
	gp.emitting = true
	_bits(face.global_transform * MOUTH, 22, Color(0.42, 0.03, 0.03), 1.4, 0.016, 0.9, 9.0, Vector3(0, 0.3, 1), 30.0, false)
	get_tree().create_timer(3.6).timeout.connect(func() -> void:
		if is_instance_valid(gp):
			gp.emitting = false)

@rpc("authority", "call_local", "unreliable_ordered")
func _rpc_sync(g: Dictionary, f: Dictionary, lv: float, tl: float) -> void:
	gas = g
	filt = f
	level = lv
	_time_left = tl
	_refresh_board()

func _run() -> void:
	await get_tree().create_timer(0.4).timeout
	for n in ["3", "2", "1"]:
		_rpc_big.rpc(n, "e8e2c8")
		Fx.sfx("click")
		await get_tree().create_timer(0.6).timeout
	_rpc_start.rpc()
	while clock < TIME_LIMIT and not _over():
		await get_tree().process_frame
	_rpc_sync.rpc(gas, {}, level, maxf(0.0, TIME_LIMIT - clock))
	_rpc_end.rpc()
	await get_tree().create_timer(2.0).timeout
	if not _done:
		_done = true
		finished.emit(_placement())

func _over() -> bool:
	var a := alive_ids().size()
	return a == 0 or (a <= 1 and players.size() > 1)

func _placement() -> Array:
	var alive: Array = alive_ids()
	alive.sort_custom(func(a, b) -> bool: return float(gas[a]) < float(gas[b]))
	var res: Array = alive.duplicate()
	for i in range(dead_order.size() - 1, -1, -1):
		if not res.has(dead_order[i]):
			res.append(dead_order[i])
	for id in players:
		if not res.has(id):
			res.append(id)
	return res

@rpc("authority", "call_local", "reliable")
func _rpc_big(text: String, hex: String) -> void:
	_big_local(text, Color(hex), 0.0)

@rpc("authority", "call_local", "reliable")
func _rpc_start() -> void:
	running = true
	clock = 0.0
	for id in players:
		var p: LabPlayer3D = players[id]
		if p.is_local_human():
			p.input_enabled = true
	_big_local("BREATHE", Color("b8e07a"), 0.6)
	Fx.sfx("buzzer", null, -6.0, 0.6)
	var th := create_tween()
	th.tween_interval(8.0)
	th.tween_property(_help, "modulate:a", 0.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_end() -> void:
	running = false
	_ended_local = true
	for id in players:
		players[id].input_enabled = false
	var alive := alive_ids()
	alive.sort_custom(func(a, b) -> bool: return float(gas.get(a, 0.0)) < float(gas.get(b, 0.0)))
	var txt := "NOBODY KEPT BREATHING"
	if alive.size() == 1:
		txt = "%s KEPT BREATHING" % players[alive[0]].display_name
	elif alive.size() > 1:
		txt = "VENTS CLOSED  ·  %d STILL BREATHING" % alive.size()
	_big_local(txt, Color("e2c84b"), 0.0)
	Fx.sfx("buzzer", null, -6.0, 1.3)
	_refresh_board()

func _steer(id: int, from: Vector3, goal: Vector3) -> Vector3:
	var v := Vector3(goal.x - from.x, 0.0, goal.z - from.z)
	var dist := v.length()
	var out := Vector3.ZERO
	if dist > 0.12:
		out = v / dist * clampf(dist * 2.2, 0.3, 1.0)
	for o in alive_ids():
		if o == id:
			continue
		var d: Vector3 = from - players[o].position
		d.y = 0.0
		var l := d.length()
		if l < 0.7 and l > 0.01:
			out += d / l * (0.7 - l) * 1.1
	if out.length() > 1.0:
		out = out.normalized()
	return out

func _bot_brain(delta: float, id: int) -> Vector3:
	if not running:
		return Vector3.ZERO
	var p: LabPlayer3D = players[id]
	if float(stun[id]) > 0.0:
		return Vector3.ZERO
	var b: Dictionary = _bot[id]
	if float(b.wait) > 0.0:
		b.wait = float(b.wait) - delta
		return Vector3.ZERO
	b.think = float(b.think) - delta
	if float(b.think) <= 0.0:
		b.think = randf_range(0.22, 0.4)
		_bot_decide(id, b, p)
	var mode: String = b.mode
	if mode == "mask":
		var t: int = b.target
		if not masks.has(t) or (masks[t].state != "floor" and masks[t].state != "incoming") or int(wearer[id]) >= 0:
			b.think = 0.0
			return Vector3.ZERO
		var mp: Vector3 = masks[t].pos
		return _steer(id, p.position, mp + (b.err as Vector3) * 0.3)
	if mode == "rip":
		var v: int = b.victim
		if not players.has(v) or not players[v].alive or int(wearer[v]) < 0 or int(wearer[id]) >= 0:
			b.think = 0.0
			return Vector3.ZERO
		var pv: LabPlayer3D = players[v]
		var to: Vector3 = pv.position - p.position
		to.y = 0.0
		if to.length() < RIP_R - 0.4:
			p.face(to)
			if float(b.swing_at) <= 0.0:
				b.swing_at = clock + float(b.react) * 0.5
			if clock >= float(b.swing_at):
				b.swing_at = 0.0
				_try_rip(id)
				b.wait = 0.15
				b.think = 0.0
			return to.normalized() * 0.25
		return _steer(id, p.position, pv.position)
	var goal: Vector3 = b.goal
	return _steer(id, p.position, goal)

func _bot_decide(id: int, b: Dictionary, p: LabPlayer3D) -> void:
	var masked: bool = int(wearer[id]) >= 0
	var g: float = float(gas[id])
	if masked:
		var threat := -1
		var td := 3.2
		for o in alive_ids():
			if o == id or int(wearer[o]) >= 0:
				continue
			var d: float = players[o].position.distance_to(p.position)
			if d < td:
				td = d
				threat = o
		if threat >= 0:
			var away: Vector3 = p.position - players[threat].position
			away.y = 0.0
			b.mode = "flee"
			b.goal = _clamp_floor(p.position + away.normalized() * 3.0 + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)))
			return
		if clock >= float(b.roam_at) or b.mode != "roam":
			b.roam_at = clock + randf_range(1.5, 3.0)
			var hp: Vector3 = HATCHES[int(b.home)]
			var f: float = float(filt.get(id, FILTER_TIME))
			var mm: Dictionary = masks.get(int(wearer[id]), {})
			if not mm.is_empty():
				f = float(mm.filter)
			if f < 4.0:
				b.goal = _clamp_floor(Vector3(hp.x, 0.0, hp.z) + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)))
			else:
				b.goal = _clamp_floor(Vector3(randf_range(1.5, W - 1.5), 0.0, randf_range(1.5, D - 1.5)))
			b.mode = "roam"
		return
	var best := -1
	var best_s := INF
	for mid in masks:
		var m: Dictionary = masks[mid]
		var known: bool = m.state == "floor" or (m.state == "incoming" and clock >= float(m.warn_at) + float(b.react))
		if not known:
			continue
		var mp: Vector3 = m.pos
		var mine: float = Vector2(mp.x - p.position.x, mp.z - p.position.z).length()
		var s: float = mine
		for o in alive_ids():
			if o == id or int(wearer[o]) >= 0:
				continue
			var od: float = Vector2(mp.x - players[o].position.x, mp.z - players[o].position.z).length()
			if od < mine - 0.8:
				s += 3.5
				break
		if m.state == "incoming":
			s += 0.5
		if s < best_s:
			best_s = s
			best = mid
	var desperate: bool = g > float(b.desperate)
	var victim := -1
	var vd := INF
	for o in alive_ids():
		if o == id or int(wearer[o]) < 0:
			continue
		var d: float = players[o].position.distance_to(p.position)
		if d < vd:
			vd = d
			victim = o
	var opportunist: bool = victim >= 0 and vd < 1.8 and randf() < float(b.aggro) * 0.35
	if best >= 0 and not (desperate and best_s > 7.0 and victim >= 0 and vd < best_s) and not opportunist:
		b.mode = "mask"
		b.target = best
		return
	if victim >= 0 and (desperate or opportunist or (best < 0 and g > float(b.desperate) * 0.55 and randf() < float(b.aggro))):
		b.mode = "rip"
		b.victim = victim
		return
	if b.mode != "roam" or clock >= float(b.roam_at):
		b.roam_at = clock + randf_range(1.0, 2.0)
		var hp2: Vector3 = HATCHES[int(b.home)]
		b.goal = _clamp_floor(Vector3(hp2.x, 0.0, hp2.z) + Vector3(randf_range(-0.9, 0.9), 0.0, randf_range(-0.9, 0.9)))
		b.mode = "roam"
