extends ArenaMinigame3D
## Spine Breaker: a hulking lab mutant bursts out of its cell and hunts the
## subjects through a cluttered cell block (pillar stumps, cages, low concrete
## walls). It is a bit slower than a sprinting subject, gets faster every second,
## lunges when close, and a second one breaks loose 15 s in. Caught = spine
## snapped. SPACE sprints while stamina lasts, E / click shoves a rival (into the
## mutant, ideally). 45 s or until one subject remains; ranked by survival order.

const TIME_LIMIT: float = 45.0
const SECOND_AT: float = 15.0
const SECOND_WARN: float = 2.5
const BASE_SPEED: float = 4.6
const SPRINT_SPEED: float = 7.2
const STAM_DRAIN: float = 0.5
const STAM_REGEN: float = 0.26
const STAM_MIN: float = 0.3
const MUT_SPEED0: float = 4.4
const MUT_SPEED1: float = 6.3
const LUNGE_SPEED: float = 8.2
const LUNGE_T: float = 0.3
const WIND_T: float = 0.38
const LUNGE_CD: float = 2.4
const LUNGE_R: float = 2.3
const RECOVER_T: float = 0.85
const CATCH_R: float = 0.85
const CATCH_R_LUNGE: float = 1.05
const FEED_T: float = 1.6
const SHOVE_REACH: float = 1.5
const SHOVE_CD: float = 1.2
const KNOCK: float = 2.1
const SHOVE_LOCK: float = 0.6
const FEED_CREDIT: float = 2.0
const CELL: float = 0.5
const GW: int = 32
const GH: int = 20
const CELLS: Array = [2.0, 6.0, 10.0, 14.0]
const MUT_CELLS: Array = [6.0, 10.0]
const MUT_SUIT: Color = Color(0.3, 0.34, 0.27)
const MUT_SKIN: Color = Color(0.52, 0.6, 0.44)

const MUT_SKIN_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.52, 0.6, 0.44);
void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	float g = dot(base, vec3(0.3, 0.55, 0.15));
	vec3 sick = mix(vec3(g), base, 0.25) * tint * 1.25;
	float vein = smoothstep(0.62, 0.7, sin(UV.x * 140.0 + sin(UV.y * 90.0) * 2.5) * 0.5 + 0.5) * 0.35;
	ALBEDO = mix(sick, sick * vec3(0.45, 0.35, 0.5), vein);
	vec3 orm = texture(orm_tex, UV).rgb;
	AO = orm.r;
	ROUGHNESS = 0.55;
	SPECULAR = 0.6;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
"""

class Deform extends SkeletonModifier3D:
	var scales: Dictionary = {}
	var lean: float = 0.0
	var spine: int = -1
	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for b in scales:
			sk.set_bone_pose_scale(b, scales[b])
		if spine >= 0 and absf(lean) > 0.001:
			sk.set_bone_pose_rotation(spine, Quaternion(Vector3.RIGHT, lean) * sk.get_bone_pose_rotation(spine))

enum St { COUNTDOWN, RUN, DONE }

var st: St = St.COUNTDOWN
var clock: float = 0.0
var blocked := PackedByteArray()
var mblock := PackedByteArray()
var walls: Array[Rect2] = []
var mutants: Array[Dictionary] = []
var elim_order: Array = []
var bots: Dictionary = {}
var stam: Dictionary = {}
var tired: Dictionary = {}
var shove_ready: Dictionary = {}
var lock_until: Dictionary = {}
var shoved_by: Dictionary = {}
var vel: Dictionary = {}
var _last_pos: Dictionary = {}
var _push_tw: Dictionary = {}
var _gates: Array[Node3D] = []
var _beacons: Array[Node3D] = []
var _flicker: Array[Dictionary] = []
var _hz: StandardMaterial3D
var _skin_shader: Shader
var _ended: bool = false
var _warned2: bool = false
var _released: Array[bool] = [false, false]
var _space_down: bool = false
var _shove_down: bool = false
var _cam_t: Vector3 = Vector3(W * 0.5, 0.0, D * 0.5)
var _cam_o: Vector3 = Vector3(0.0, 12.5, 7.0)
var _hud_time: Label
var _hud_board: Label
var _hud_help: Label
var _big: Label
var _stam_bg: ColorRect
var _stam_fill: ColorRect

func begin() -> void:
	setup_arena(false)
	_tune_light()
	blocked.resize(GW * GH)
	mblock.resize(GW * GH)
	_hz = _hazard_mat()
	_build_block()
	camera.fov = 46.0
	camera.position = Vector3(W * 0.5, 12.5, D + 6.5)
	camera.look_at(Vector3(W * 0.5, 0.0, D * 0.5), Vector3.UP)
	spawn_players(_spawns())
	for id in players:
		var p: LabPlayer3D = players[id]
		p.speed = BASE_SPEED
		p.bot_brain = _bot_brain.bind(id)
		stam[id] = 1.0
		tired[id] = false
		shove_ready[id] = 0.0
		lock_until[id] = 0.0
		vel[id] = Vector3.ZERO
		_last_pos[id] = p.position
		bots[id] = {"think": randf_range(0.0, 0.3), "path": [], "goal": Vector3.INF, "panic": randf_range(3.0, 4.2),
			"dirty": randf_range(0.12, 0.35), "shove_t": randf_range(1.5, 3.0)}
		if p.is_local_human():
			p.input_enabled = false
	for i in MUT_CELLS.size():
		_make_mutant(i, float(MUT_CELLS[i]))
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.26
			n.light_color = Color(0.8, 0.9, 0.85)
			n.shadow_enabled = false
	env.background_color = Color("070807")
	env.ambient_light_color = Color(0.5, 0.56, 0.5)
	env.ambient_light_energy = 0.42
	env.fog_light_color = Color(0.12, 0.13, 0.11)
	env.fog_density = 0.018
	env.tonemap_exposure = 1.08
	env.adjustment_saturation = 0.74

func _spawns() -> Array:
	var pts: Array = [Vector3(8.0, 0, 9.3), Vector3(1.5, 0, 9.2), Vector3(14.5, 0, 9.2), Vector3(4.0, 0, 9.5),
		Vector3(11.8, 0, 9.2), Vector3(1.6, 0, 6.6), Vector3(14.4, 0, 6.6), Vector3(8.0, 0, 6.7)]
	var a: Array = []
	for i in NetworkManager.players.size():
		a.append(pts[i % pts.size()])
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

func _cyl(r: float, h: float, m: Material, pos: Vector3, rot: Vector3, parent: Node, seg: int = 12) -> MeshInstance3D:
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

func _chain(top: Vector3, length: float, parent: Node3D, hook: bool = true, link: float = 0.075) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = top
	var tm := TorusMesh.new()
	tm.inner_radius = link * 0.47
	tm.outer_radius = link
	tm.rings = 10
	tm.ring_segments = 6
	tm.material = mat("rusty_metal", 2.0, Color(0.6, 0.5, 0.42))
	var pitch := link * 1.6
	var count := maxi(int(length / pitch), 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tm
	mm.instance_count = count
	for i in count:
		var b := Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.0, 1.7))
		if i % 2 == 1:
			b = Basis(Vector3.UP, PI * 0.5) * b
		mm.set_instance_transform(i, Transform3D(b, Vector3(0, -float(i) * pitch, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	holder.add_child(mmi)
	if hook:
		var h := MeshInstance3D.new()
		var hm := TorusMesh.new()
		hm.inner_radius = link * 1.6
		hm.outer_radius = link * 2.6
		h.mesh = hm
		h.material_override = mat("rusty_metal_02", 2.0)
		holder.add_child(h)
		h.position = Vector3(0, -length - link * 2.0, 0)
		h.rotation_degrees.x = 90.0
	return holder

func _solid(r: Rect2, h: float, opaque: bool, visual: Material = null, parent: Node = null) -> void:
	var c := Vector3(r.get_center().x, h * 0.5, r.get_center().y)
	var size := Vector3(r.size.x, h, r.size.y)
	if visual:
		box(size, c, visual, parent, true)
	else:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		(parent if parent else world).add_child(sb)
		sb.position = c
	var g := r.grow(0.25)
	var gm := r.grow(0.4)
	for i in GW * GH:
		var p := _center(i)
		var p2 := Vector2(p.x, p.z)
		if g.has_point(p2):
			blocked[i] = 1
		if gm.has_point(p2):
			mblock[i] = 1
	if opaque:
		walls.append(r)

func _build_block() -> void:
	var blk := Node3D.new()
	blk.name = "CellBlock"
	world.add_child(blk)
	var floor_m := mat("damaged_concrete_floor", 0.3, Color(0.62, 0.6, 0.55))
	var wall := mat("concrete_wall_006", 0.4, Color(0.55, 0.56, 0.5))
	var brick := mat("dark_brick_wall", 0.45, Color(0.6, 0.58, 0.52))
	var band := mat("green_metal_rust", 0.6, Color(0.5, 0.58, 0.52))
	var rust := mat("rusty_metal_02", 1.5, Color(0.55, 0.52, 0.48))
	box(Vector3(W + 4.0, 0.2, D + 8.0), Vector3(W * 0.5, -0.1, D * 0.5 + 0.5), floor_m, blk)
	box(Vector3(0.4, 4.6, D + 7.2), Vector3(-0.8, 2.3, D * 0.5 + 0.45), wall, blk)
	box(Vector3(0.4, 4.6, D + 7.2), Vector3(W + 0.8, 2.3, D * 0.5 + 0.45), wall, blk)
	box(Vector3(0.06, 1.1, D + 7.2), Vector3(-0.58, 0.55, D * 0.5 + 0.45), band, blk)
	box(Vector3(0.06, 1.1, D + 7.2), Vector3(W + 0.58, 0.55, D * 0.5 + 0.45), band, blk)
	box(Vector3(0.05, 0.06, D + 7.2), Vector3(-0.56, 1.12, D * 0.5 + 0.45), rust, blk)
	box(Vector3(0.05, 0.06, D + 7.2), Vector3(W + 0.56, 1.12, D * 0.5 + 0.45), rust, blk)
	_cell_front(blk, brick, band, rust)
	for cx in CELLS:
		_build_cell(float(cx), blk)
	box(Vector3(W + 1.6, 0.012, 0.16), Vector3(W * 0.5, 0.006, 0.45), _hz, blk)
	for c in [Vector2(3.0, 2.6), Vector2(13.0, 2.6), Vector2(3.0, 7.4), Vector2(13.0, 7.4)]:
		_pillar(c, blk, band)
	_barrier(Vector3(6.07, 0, 2.31), 0.0, blk)
	_barrier(Vector3(7.61, 0, 2.31), 4.0, blk)
	_barrier(Vector3(8.39, 0, 7.71), -3.0, blk)
	_barrier(Vector3(9.93, 0, 7.71), 2.0, blk)
	_barrier(Vector3(5.41, 0, 5.02), 90.0, blk)
	_barrier(Vector3(10.61, 0, 5.02), -88.0, blk)
	_solid(Rect2(5.3, 2.0, 3.08, 0.62), 0.82, false, null, blk)
	_solid(Rect2(7.62, 7.4, 3.08, 0.62), 0.82, false, null, blk)
	_solid(Rect2(5.1, 4.25, 0.62, 1.54), 0.82, false, null, blk)
	_solid(Rect2(10.3, 4.25, 0.62, 1.54), 0.82, false, null, blk)
	_cage(Rect2(6.85, 4.2, 2.3, 1.6), 2.3, blk)
	_cage(Rect2(9.4, 2.4, 1.2, 1.0), 1.05, blk)
	_cage(Rect2(4.6, 8.2, 1.2, 1.0), 1.05, blk)
	_corpse(Vector3(7.7, 0, 5.1), 70.0, Color(0.85, 0.55, 0.2), blk)
	var ch := prop("SchoolChair_01", Vector3(8.6, 0.28, 4.7), 0.0, 1.0, blk)
	if ch:
		ch.rotation_degrees = Vector3(80.0, 30.0, 0.0)
	prop("medical_box", Vector3(7.2, 0, 4.55), 25.0, 1.2, blk)
	prop("old_gas_mask", Vector3(8.95, 2.1, 5.7), 180.0, 1.3, blk)
	_chain(Vector3(7.4, 2.28, 4.4), 1.1, blk)
	_chain(Vector3(8.5, 2.28, 5.5), 0.8, blk)
	prop("cardboard_box_01", Vector3(10.0, 0, 2.9), 20.0, 1.0, blk)
	prop("can_rusted", Vector3(9.75, 0, 2.7), 0.0, 1.4, blk)
	prop("trashbag", Vector3(5.2, 0, 8.7), 0.0, 0.9, blk)
	_lockers(blk)
	_dressing(blk)
	_lights(blk)
	_stains(blk)

func _cell_front(parent: Node3D, brick: Material, band: Material, rust: Material) -> void:
	var piers: Array = [[-1.0, 0.65], [3.35, 4.65], [7.35, 8.65], [11.35, 12.65], [15.35, 17.0]]
	for pr in piers:
		var x0: float = pr[0]
		var x1: float = pr[1]
		box(Vector3(x1 - x0, 2.75, 0.3), Vector3((x0 + x1) * 0.5, 1.375, -0.15), brick, parent)
		box(Vector3(x1 - x0 + 0.04, 0.9, 0.34), Vector3((x0 + x1) * 0.5, 0.45, -0.15), band, parent)
	box(Vector3(W + 2.0, 1.85, 0.3), Vector3(W * 0.5, 3.675, -0.15), brick, parent)
	box(Vector3(W + 2.0, 0.14, 0.4), Vector3(W * 0.5, 2.8, -0.12), rust, parent)
	box(Vector3(W + 2.0, 4.8, 0.3), Vector3(W * 0.5, 2.4, -3.05), mat("concrete_wall_008", 0.4, Color(0.42, 0.43, 0.38)), parent)
	box(Vector3(W + 2.0, 0.3, 3.2), Vector3(W * 0.5, 4.75, -1.6), mat("dirty_concrete", 0.4, Color(0.32, 0.32, 0.3)), parent)
	for x in [4.0, 8.0, 12.0]:
		box(Vector3(0.25, 4.6, 2.8), Vector3(x, 2.3, -1.7), mat("concrete_wall_006", 0.45, Color(0.45, 0.45, 0.4)), parent)
	var pipe := mat("rusty_metal_02", 1.5)
	for y in [3.3, 3.75]:
		_cyl(0.13 if y < 3.5 else 0.2, W + 2.0, pipe, Vector3(W * 0.5, y, 0.14), Vector3(0, 0, 90), parent)
	for x in [0.0, 4.0, 8.0, 12.0, 16.0]:
		box(Vector3(0.08, 0.5, 0.1), Vector3(x, 3.5, 0.08), rust, parent)
	prop("modular_electric_cables", Vector3(1.4, 3.7, 0.02), 0.0, 1.0, parent)
	prop("security_camera_01", Vector3(W - 0.4, 4.3, 0.2), -150.0, 1.5, parent)
	prop("fire_alarm", Vector3(8.0, 2.2, 0.02), 0.0, 1.5, parent)
	prop("power_box_01", Vector3(12.0, 1.6, 0.0), 0.0, 1.4, parent)
	prop("wall_clock", Vector3(4.0, 3.2, 0.02), 0.0, 1.3, parent)
	var plate := mat("blue_metal_plate", 2.0, Color(0.7, 0.72, 0.68))
	for cx in CELLS:
		box(Vector3(0.5, 0.3, 0.03), Vector3(float(cx) - 1.0, 3.05, 0.02), plate, parent)
	for cx in CELLS:
		var g := prop("large_iron_gate", Vector3(float(cx), 0.0, -0.05), 0.0, 0.95, parent)
		_gates.append(g)
	for cx in MUT_CELLS:
		var b := Node3D.new()
		parent.add_child(b)
		b.position = Vector3(float(cx), 3.12, 0.44)
		_cyl(0.11, 0.18, _plain(Color(0.15, 0.14, 0.13), 0.6, 0.5), Vector3(0, -0.12, 0), Vector3.ZERO, b, 10)
		box(Vector3(0.06, 0.06, 0.44), Vector3(0, -0.2, -0.22), mat("rusty_metal_02", 2.0), b)
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.16
		dome.mesh = sm
		dome.material_override = _glow(Color(1.0, 0.1, 0.05), 0.4)
		b.add_child(dome)
		var spin := Node3D.new()
		b.add_child(spin)
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.12, 0.06)
		sp.light_energy = 0.0
		sp.spot_range = 10.0
		sp.spot_angle = 28.0
		spin.add_child(sp)
		sp.rotation_degrees = Vector3(-35.0, 0.0, 0.0)
		b.set_meta("spin", spin)
		b.set_meta("light", sp)
		b.set_meta("dome", dome)
		_beacons.append(b)

func _build_cell(cx: float, parent: Node3D) -> void:
	var cell := Node3D.new()
	parent.add_child(cell)
	var mutant_cell := MUT_CELLS.has(cx)
	var lt := OmniLight3D.new()
	lt.light_color = Color(0.65, 0.9, 0.35) if mutant_cell else Color(1.0, 0.72, 0.45)
	lt.light_energy = 1.4 if mutant_cell else 0.9
	lt.omni_range = 3.8
	cell.add_child(lt)
	lt.position = Vector3(cx, 2.3, -1.3)
	prop("caged_hanging_light", Vector3(cx, 3.0, -1.5), 0.0, 1.0, cell)
	_flicker.append({"l": lt, "base": lt.light_energy, "t": randf(), "kind": 2 if mutant_cell else 1})
	var cot_m := mat("rusty_metal", 1.6, Color(0.5, 0.45, 0.4))
	var matt := mat("dirty_carpet", 1.0, Color(0.5, 0.44, 0.33))
	if cx == 2.0 or cx == 14.0:
		var sx: float = cx - 1.1 if cx == 2.0 else cx + 1.1
		box(Vector3(0.8, 0.08, 2.0), Vector3(sx, 0.45, -1.8), cot_m, cell)
		box(Vector3(0.72, 0.12, 1.9), Vector3(sx, 0.55, -1.8), matt, cell)
		for k in [-0.9, 0.9]:
			box(Vector3(0.05, 0.45, 0.05), Vector3(sx - 0.35, 0.22, -1.8 + k), cot_m, cell)
			box(Vector3(0.05, 0.45, 0.05), Vector3(sx + 0.35, 0.22, -1.8 + k), cot_m, cell)
		prop("metal_trash_can", Vector3(cx + (0.9 if cx == 2.0 else -0.9), 0, -2.4), 0.0, 0.8, cell)
	if cx == 2.0:
		_corpse(Vector3(2.4, 0, -1.2), 200.0, Color(0.3, 0.45, 0.7), cell)
	if cx == 14.0:
		for k in 3:
			_blood_decal(Vector3(13.6 + k * 0.4, 0.0, -1.0 - k * 0.3), 1.2, cell)
		_chain(Vector3(14.6, 2.0, -2.85), 0.9, cell)
	if mutant_cell:
		_chain(Vector3(cx - 0.8, 2.4, -2.85), 1.5, cell)
		_chain(Vector3(cx + 0.8, 2.4, -2.85), 1.3, cell)
		var bucket := prop("metal_trash_can", Vector3(cx + 1.2, 0.25, -2.2), 0.0, 0.7, cell)
		if bucket:
			bucket.rotation_degrees = Vector3(0.0, 40.0, 90.0)
		_blood_decal(Vector3(cx, 0.0, -1.6), 1.8, cell)
		for k in 6:
			var sc := box(Vector3(0.02, randf_range(0.3, 0.9), 0.01), Vector3(cx - 0.6 + k * 0.22, 1.3 + randf_range(-0.2, 0.2), -2.89), _plain(Color(0.12, 0.05, 0.04), 0.9), cell)
			sc.rotation.z = randf_range(-0.2, 0.2)

func _pillar(c: Vector2, parent: Node3D, band: Material) -> void:
	_solid(Rect2(c - Vector2(0.4, 0.4), Vector2(0.8, 0.8)), 2.6, true, mat("concrete_wall_008", 0.5, Color(0.62, 0.6, 0.55)), parent)
	box(Vector3(0.86, 0.9, 0.86), Vector3(c.x, 0.45, c.y), band, parent)
	box(Vector3(0.87, 0.12, 0.87), Vector3(c.x, 0.96, c.y), _hz, parent)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.x * 13.0 + c.y * 7.0)
	var chunk := mat("concrete_wall_008", 0.6, Color(0.55, 0.53, 0.5))
	for k in 3:
		var s := Vector3(rng.randf_range(0.25, 0.45), rng.randf_range(0.15, 0.35), rng.randf_range(0.25, 0.45))
		var b := box(s, Vector3(c.x + rng.randf_range(-0.2, 0.2), 2.6 + s.y * 0.3, c.y + rng.randf_range(-0.2, 0.2)), chunk, parent)
		b.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.0, TAU), rng.randf_range(-0.4, 0.4))
	var rebar := mat("rusty_metal", 3.0, Color(0.45, 0.32, 0.22))
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.6
		var h := rng.randf_range(0.4, 0.9)
		_cyl(0.015, h, rebar, Vector3(c.x + cos(a) * 0.28, 2.6 + h * 0.45, c.y + sin(a) * 0.28), Vector3(rng.randf_range(-25, 25), 0, rng.randf_range(-25, 25)), parent, 5)
	_chain(Vector3(c.x + 0.43, 2.3, c.y), 0.9, parent)
	box(Vector3(0.12, 0.08, 0.12), Vector3(c.x + 0.43, 2.32, c.y), mat("rusty_metal_02", 2.0), parent)

func _barrier(pos: Vector3, yaw: float, parent: Node3D) -> void:
	prop("concrete_road_barrier", pos, yaw, 1.0, parent)

func _cage(r: Rect2, h: float, parent: Node3D) -> void:
	_solid(r, h, false, null, parent)
	var frame := mat("rusty_metal", 1.6, Color(0.5, 0.45, 0.4))
	var bar_m := mat("rusty_metal_02", 2.0, Color(0.5, 0.47, 0.44))
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	for y in [0.04, h * 0.5, h - 0.03]:
		box(Vector3(r.size.x, 0.06, 0.06), Vector3(r.get_center().x, y, z0), frame, parent)
		box(Vector3(r.size.x, 0.06, 0.06), Vector3(r.get_center().x, y, z1), frame, parent)
		box(Vector3(0.06, 0.06, r.size.y), Vector3(x0, y, r.get_center().y), frame, parent)
		box(Vector3(0.06, 0.06, r.size.y), Vector3(x1, y, r.get_center().y), frame, parent)
	for p in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x0, z1), Vector2(x1, z1)]:
		box(Vector3(0.08, h, 0.08), Vector3(p.x, h * 0.5, p.y), frame, parent)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.018
	cm.height = h
	cm.radial_segments = 5
	cm.material = bar_m
	var xforms: Array[Transform3D] = []
	var step := 0.16
	var nx := int(r.size.x / step)
	var nz := int(r.size.y / step)
	for i in range(1, nx):
		for z in [z0, z1]:
			xforms.append(Transform3D(Basis(), Vector3(x0 + float(i) * r.size.x / float(nx), h * 0.5, z)))
	for i in range(1, nz):
		for x in [x0, x1]:
			xforms.append(Transform3D(Basis(), Vector3(x, h * 0.5, z0 + float(i) * r.size.y / float(nz))))
	var top_b := Basis(Vector3.RIGHT, PI * 0.5)
	var ntop := int(r.size.x / 0.3)
	for i in range(1, ntop):
		xforms.append(Transform3D(top_b * Basis().scaled(Vector3(1.0, r.size.y / h, 1.0)), Vector3(x0 + float(i) * r.size.x / float(ntop), h - 0.03, r.get_center().y)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)
	box(Vector3(r.size.x - 0.1, 0.02, r.size.y - 0.1), Vector3(r.get_center().x, 0.012, r.get_center().y), mat("metal_grate_rusty", 1.2, Color(0.5, 0.48, 0.44)), parent)

func _corpse(pos: Vector3, yaw: float, col: Color, parent: Node3D) -> void:
	var c := LabCharacter.new()
	c.suit_color = col
	c.hat = ""
	parent.add_child(c)
	c.position = pos
	c.rotation_degrees.y = yaw
	c.die("Death01")
	c.anim.seek(c.anim.current_animation_length, true)
	_blood_decal(pos + Vector3(0.2, 0, 0.1), 1.6, parent)

var _stain_tex: Texture2D

func _stain() -> Texture2D:
	if _stain_tex:
		return _stain_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.045
	noise.seed = 13
	for y in n:
		for x in n:
			var dx := (x - n * 0.5) / (n * 0.5)
			var dy := (y - n * 0.5) / (n * 0.5)
			var v := 1.0 - sqrt(dx * dx + dy * dy) + noise.get_noise_2d(x, y) * 0.7
			var ring := 1.0 - absf(v - 0.3) * 6.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(maxf((v - 0.25) * 1.6, ring * 0.9), 0.0, 0.9)))
	_stain_tex = ImageTexture.create_from_image(img)
	return _stain_tex

func _blood_decal(pos: Vector3, size: float, parent: Node3D) -> void:
	var d := Decal.new()
	d.texture_albedo = _stain()
	d.size = Vector3(size, 0.8, size * randf_range(0.6, 1.0))
	d.modulate = Color(0.3, 0.02, 0.02)
	d.cull_mask = 1
	d.rotation.y = randf() * TAU
	parent.add_child(d)
	d.position = Vector3(pos.x, 0.1, pos.z)

func _lockers(parent: Node3D) -> void:
	prop("vintage_cabinet_01", Vector3(0.33, 0, 5.2), 90.0, 1.0, parent)
	prop("vintage_cabinet_01", Vector3(W - 0.33, 0, 5.2), -90.0, 1.0, parent)
	_solid(Rect2(0.0, 4.2, 0.72, 2.0), 2.2, true, null, parent)
	_solid(Rect2(W - 0.72, 4.2, 0.72, 2.0), 2.2, true, null, parent)

func _dressing(parent: Node3D) -> void:
	var deco := [["worn_metal_rack", -0.45, 1.4, 90.0, 1.0], ["barrel_03", -0.35, 3.0, 0.0, 1.1], ["metal_jerrycan", -0.4, 7.0, 60.0, 1.1],
		["cement_bag", -0.35, 8.6, 30.0, 1.1], ["barrel_03", -0.3, 9.6, 40.0, 1.1],
		["steel_frame_shelves_02", W + 0.45, 1.5, -90.0, 1.0], ["propane_tank", W + 0.35, 3.0, 0.0, 1.1], ["metal_tool_chest", W + 0.4, 7.2, -90.0, 1.1],
		["trashbag", W + 0.35, 8.8, 0.0, 1.1], ["wooden_crate_02", W + 0.35, 9.8, 15.0, 1.1],
		["barrel_03", 0.9, D + 0.9, 0.0, 1.15], ["metal_trash_can", 3.2, D + 0.8, 0.0, 1.0], ["WetFloorSign_01", 5.4, D + 0.7, 30.0, 1.2],
		["medical_box", 7.0, D + 0.6, -10.0, 1.4], ["cardboard_box_01", 9.0, D + 0.9, 20.0, 1.2], ["trashbag", 11.0, D + 0.8, 0.0, 1.2],
		["old_tyre", 13.2, D + 1.0, 0.0, 1.1], ["wooden_crate_01", 15.2, D + 0.9, -20.0, 1.2], ["concrete_road_barrier", 2.0, D + 2.0, 8.0, 1.0],
		["concrete_road_barrier", 13.6, D + 2.1, -6.0, 1.0], ["old_military_crate", 8.0, D + 2.0, 0.0, 1.1], ["hand_truck", 10.6, D + 2.0, 50.0, 1.1]]
	for d in deco:
		prop(d[0], Vector3(d[1], 0.0, d[2]), d[3], d[4], parent)
	for x in [-0.55, W + 0.55]:
		prop("industrial_caged_sconce", Vector3(x, 2.6, 3.0), 90.0 if x < 0.0 else -90.0, 1.4, parent)
		var wl := OmniLight3D.new()
		wl.light_color = Color(1.0, 0.76, 0.5)
		wl.light_energy = 1.6
		wl.omni_range = 4.5
		parent.add_child(wl)
		wl.position = Vector3(x + (0.5 if x < 0.0 else -0.5), 2.6, 3.0)
	prop("modular_pipes", Vector3(-0.58, 0.0, 8.0), 90.0, 1.0, parent)
	prop("power_box_01", Vector3(W + 0.58, 1.6, 6.8), -90.0, 1.4, parent)
	var grate := mat("metal_grate_rusty", 1.4, Color(0.55, 0.52, 0.48))
	for g in [Vector3(2.0, 0.0, 4.6), Vector3(14.0, 0.0, 4.6), Vector3(8.0, 0.0, 3.3), Vector3(11.5, 0.0, 9.0)]:
		box(Vector3(0.6, 0.02, 0.6), g + Vector3(0, 0.01, 0), grate, parent)
	for c in [[Vector3(1.4, 4.6, 6.4), 2.6], [Vector3(14.7, 4.6, 8.4), 2.2], [Vector3(15.2, 4.6, 0.8), 2.0]]:
		_chain(c[0], c[1], parent)

func _lights(parent: Node3D) -> void:
	var spots := [Vector3(4.2, 6.2, 4.4), Vector3(11.8, 6.2, 4.4), Vector3(8.0, 6.2, 8.4)]
	for i in spots.size():
		var sp := lamp(spots[i], 10.0, Color(1.0, 0.82, 0.58), parent)
		sp.shadow_enabled = i < 2
		sp.spot_angle = 60.0
		if i == 2:
			_flicker.append({"l": sp, "base": sp.light_energy, "t": 0.0, "kind": 0})
	var fill := SpotLight3D.new()
	fill.light_color = Color(0.7, 0.85, 0.75)
	fill.light_energy = 2.6
	fill.spot_range = 22.0
	fill.spot_angle = 40.0
	parent.add_child(fill)
	fill.position = Vector3(W * 0.5, 11.0, D + 4.0)
	fill.look_at(Vector3(W * 0.5, 0.0, D * 0.45), Vector3.UP)

func _stains(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 20:
		var d := Decal.new()
		d.texture_albedo = _stain()
		var sz := rng.randf_range(1.0, 3.2)
		d.size = Vector3(sz, 1.0, sz * rng.randf_range(0.55, 1.0))
		d.modulate = Color(0.2, 0.15, 0.08) if i % 3 != 0 else Color(0.1, 0.11, 0.07)
		if i % 5 == 0:
			d.modulate = Color(0.26, 0.03, 0.02)
		d.cull_mask = 1
		d.rotation.y = rng.randf() * TAU
		parent.add_child(d)
		d.position = Vector3(rng.randf_range(-0.4, W + 0.4), 0.1, rng.randf_range(-0.3, D + 1.4))
	for k in 9:
		var t := float(k) / 8.0
		var p := Vector3(2.2, 0, 0.6).lerp(Vector3(6.6, 0, 4.8), t) + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var d := Decal.new()
		d.texture_albedo = _stain()
		d.size = Vector3(0.5, 0.6, 1.0)
		d.modulate = Color(0.24, 0.02, 0.02)
		d.cull_mask = 1
		d.rotation.y = atan2(4.4, 4.2) + rng.randf_range(-0.3, 0.3)
		parent.add_child(d)
		d.position = Vector3(p.x, 0.1, p.z)
	for i in 6:
		var d := Decal.new()
		d.texture_albedo = _stain()
		d.size = Vector3(rng.randf_range(0.8, 2.0), 0.6, rng.randf_range(1.5, 3.0))
		d.modulate = Color(0.22, 0.16, 0.08)
		d.cull_mask = 1
		parent.add_child(d)
		d.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		d.position = Vector3(rng.randf_range(0.0, W), rng.randf_range(1.6, 3.4), 0.02)

func _make_mutant(i: int, cx: float) -> void:
	var root := Node3D.new()
	root.name = "Mutant%d" % i
	world.add_child(root)
	root.position = Vector3(cx, 0.0, -1.25)
	var b := LabCharacter.new()
	b.sex = "male"
	b.hat = ""
	b.suit_color = MUT_SUIT
	root.add_child(b)
	b.scale = Vector3.ONE * 1.6
	_mutate(b)
	var sk := b.skeleton
	var head := BoneAttachment3D.new()
	head.bone_name = "Head"
	sk.add_child(head)
	var eye := OmniLight3D.new()
	eye.light_color = Color(1.0, 0.82, 0.3)
	eye.light_energy = 2.4
	eye.omni_range = 2.6
	eye.omni_attenuation = 1.4
	head.add_child(eye)
	eye.position = Vector3(0.0, 0.08, 0.0)
	var chains: Array = []
	for bone in ["hand_l", "hand_r", "neck_01"]:
		var att := BoneAttachment3D.new()
		att.bone_name = bone
		sk.add_child(att)
		var cuff := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.05 if bone != "neck_01" else 0.085
		tm.outer_radius = 0.075 if bone != "neck_01" else 0.115
		cuff.mesh = tm
		cuff.material_override = mat("rusty_metal_02", 3.0, Color(0.5, 0.45, 0.4))
		att.add_child(cuff)
		var hang := _chain(Vector3.ZERO, 1.1 if bone == "neck_01" else 0.75, world, false, 0.06)
		hang.top_level = true
		chains.append({"att": att, "node": hang, "prev": Vector3.ZERO, "rot": Vector3.ZERO})
	mutants.append({"node": root, "body": b, "eye": eye, "chains": chains, "cx": cx, "mode": 0, "pos": root.position,
		"yaw": 0.0, "tpos": root.position, "tyaw": 0.0, "target": -1, "think": 0.0, "path": [], "last": Vector3.INF,
		"lunge_t": 0.0, "wind": 0.0, "lunge_cd": 0.0, "lunge_dir": Vector3.ZERO, "recover": 0.0, "feed": 0.0, "spd": 0.0,
		"prev": root.position, "step_t": 0.0, "growl_t": randf_range(1.0, 3.0), "sync_t": 0.0, "lean": 0.0, "flare": 0.0, "mod": null})
	var dm := Deform.new()
	sk.add_child(dm)
	var sc := {"spine_03": Vector3(1.24, 1.1, 1.2), "neck_01": Vector3(0.95, 0.9, 0.95), "Head": Vector3(0.68, 0.7, 0.72),
		"clavicle_l": Vector3(1.1, 1.1, 1.1), "clavicle_r": Vector3(1.15, 1.15, 1.15), "lowerarm_l": Vector3(1.05, 1.08, 1.05),
		"lowerarm_r": Vector3(1.22, 1.2, 1.22), "hand_l": Vector3(1.3, 1.3, 1.3), "hand_r": Vector3(1.4, 1.4, 1.4),
		"thigh_l": Vector3(1.12, 0.95, 1.12), "thigh_r": Vector3(1.12, 0.95, 1.12)}
	for n in sc:
		var bi := sk.find_bone(n)
		if bi >= 0:
			dm.scales[bi] = sc[n]
	dm.spine = sk.find_bone("spine_02")
	mutants[i].mod = dm

func _mutate(b: LabCharacter) -> void:
	if _skin_shader == null:
		_skin_shader = Shader.new()
		_skin_shader.code = MUT_SKIN_SHADER
	var eye_m := _glow(Color(1.0, 0.85, 0.25), 5.0)
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			if not (src is StandardMaterial3D):
				continue
			var nm := String(src.resource_name)
			if nm.begins_with("MI_Hair"):
				m.visible = false
			elif nm.begins_with("MI_Eyes"):
				m.set_surface_override_material(s, eye_m)
			elif nm.begins_with("MI_Peasant"):
				var ov := m.get_surface_override_material(s) as ShaderMaterial
				if ov:
					ov.set_shader_parameter("grime", 0.95)
			else:
				var sm := ShaderMaterial.new()
				sm.shader = _skin_shader
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("normal_tex", src.normal_texture)
				sm.set_shader_parameter("orm_tex", src.roughness_texture)
				sm.set_shader_parameter("tint", MUT_SKIN)
				m.set_surface_override_material(s, sm)

func _build_hud() -> void:
	hud_title("SPINE BREAKER  ·  don't let it catch you")
	_hud_help = Label.new()
	_hud_help.text = "WASD move  ·  hold SPACE sprint (stamina)  ·  E / click shove"
	_hud_help.position = Vector2(16, 42)
	_style(_hud_help, 16, Color("e8e2c8"))
	hud.add_child(_hud_help)
	_hud_time = Label.new()
	_hud_time.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud_time.position = Vector2(-120, 10)
	_hud_time.size = Vector2(100, 30)
	_hud_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(_hud_time, 26, Color("ffd34a"))
	hud.add_child(_hud_time)
	_hud_board = Label.new()
	_hud_board.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud_board.position = Vector2(-240, 46)
	_hud_board.size = Vector2(220, 220)
	_hud_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(_hud_board, 16, Color("e8e2c8"))
	hud.add_child(_hud_board)
	_big = Label.new()
	_big.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big.anchor_top = 0.2
	_big.anchor_bottom = 0.4
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big.add_theme_font_size_override("font_size", 72)
	_big.add_theme_color_override("font_outline_color", Color.BLACK)
	_big.add_theme_constant_override("outline_size", 12)
	hud.add_child(_big)
	_stam_bg = ColorRect.new()
	_stam_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stam_bg.position = Vector2(-120, -46)
	_stam_bg.size = Vector2(240, 12)
	_stam_bg.color = Color(0.05, 0.05, 0.04, 0.8)
	hud.add_child(_stam_bg)
	_stam_fill = ColorRect.new()
	_stam_fill.position = Vector2(2, 2)
	_stam_fill.size = Vector2(236, 8)
	_stam_fill.color = Color("b8f5c4")
	_stam_bg.add_child(_stam_fill)
	var sl := Label.new()
	sl.text = "STAMINA"
	sl.position = Vector2(0, -22)
	_style(sl, 13, Color("e8e2c8"))
	_stam_bg.add_child(sl)
	_refresh_board()

func _style(l: Label, size: int, c: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)

func _big_local(text: String, hex: String, hold: float, size: int = 72) -> void:
	_big.text = text
	_big.add_theme_font_size_override("font_size", size)
	_big.add_theme_color_override("font_color", Color(hex))
	_big.modulate.a = 1.0
	if hold > 0.0:
		var tw := create_tween()
		tw.tween_interval(hold)
		tw.tween_property(_big, "modulate:a", 0.0, 0.4)

func _refresh_board() -> void:
	if not _hud_board:
		return
	var lines: Array = []
	for id in players:
		var p: LabPlayer3D = players[id]
		lines.append("%s%s" % ["" if p.alive else "† ", p.display_name])
	_hud_board.text = "ALIVE %d\n%s" % [alive_ids().size(), "\n".join(lines)]

func _running() -> bool:
	return st == St.RUN

func _mut_speed() -> float:
	return lerpf(MUT_SPEED0, MUT_SPEED1, clampf(clock / TIME_LIMIT, 0.0, 1.0))

func _stamina(id: int, want: bool, delta: float) -> bool:
	var s: float = stam[id]
	var t: bool = tired[id]
	var sprint := want and not t and s > 0.0
	if sprint:
		s -= STAM_DRAIN * delta
		if s <= 0.0:
			s = 0.0
			t = true
	else:
		s = minf(s + STAM_REGEN * delta, 1.0)
		if t and s >= STAM_MIN:
			t = false
	stam[id] = s
	tired[id] = t
	return sprint

func _process(delta: float) -> void:
	if not world:
		return
	if st == St.RUN:
		clock += delta
		_handle_input(delta)
	if _hud_time:
		_hud_time.text = "%d" % ceili(clampf(TIME_LIMIT - clock, 0.0, TIME_LIMIT))
		_hud_help.modulate.a = clampf(10.0 - clock, 0.0, 1.0) if st == St.RUN else 1.0
		var lp := local_player()
		var show := lp != null and lp.alive
		_stam_bg.visible = show
		if show:
			var s: float = stam.get(lp.peer_id, 1.0)
			_stam_fill.size.x = 236.0 * s
			_stam_fill.color = Color("ff6a5a") if tired.get(lp.peer_id, false) else Color("b8f5c4")
	_update_mutants(delta)
	_update_beacons(delta)
	_flick(delta)
	_update_cam(delta)

func _handle_input(delta: float) -> void:
	var lp := local_player()
	if lp == null or not lp.alive:
		return
	var moving := lp.input_enabled and lp._input_dir().length() > 0.1
	var sprint := _stamina(lp.peer_id, Input.is_physical_key_pressed(KEY_SPACE) and moving, delta)
	lp.speed = SPRINT_SPEED if sprint else BASE_SPEED
	var down := Input.is_physical_key_pressed(KEY_E) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if down and not _shove_down and lp.input_enabled:
		if NetworkManager.is_server():
			_try_shove(multiplayer.get_unique_id())
		else:
			_rpc_press.rpc_id(1)
	_shove_down = down

@rpc("any_peer", "reliable")
func _rpc_press() -> void:
	if NetworkManager.is_server():
		_try_shove(multiplayer.get_remote_sender_id())

func _fwd(p: LabPlayer3D) -> Vector3:
	return Vector3(sin(p._target_yaw), 0.0, cos(p._target_yaw))

func _nearest_mutant(pos: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for m in mutants:
		if int(m.mode) < 1:
			continue
		var mp: Vector3 = m.pos if NetworkManager.is_server() else m.tpos
		var d := Vector2(mp.x - pos.x, mp.z - pos.z).length()
		if d < bd:
			bd = d
			best = mp
	return best

func _try_shove(id: int) -> void:
	if st != St.RUN or not players.has(id) or not players[id].alive:
		return
	if clock < float(shove_ready[id]) or clock < float(lock_until[id]):
		return
	shove_ready[id] = clock + SHOVE_CD
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
		if d > 0.6 and f.dot(to / d) < 0.35:
			continue
		best = o
		best_d = d
	if best < 0:
		_rpc_shove.rpc(id, -1, _clip(p.position, p.position + f * 0.5), Vector3.ZERO)
		return
	var v: LabPlayer3D = players[best]
	var to_v: Vector3 = v.position - p.position
	to_v.y = 0.0
	var base: Vector3 = to_v.normalized() if to_v.length() > 0.05 else f
	var dir := base
	var mp := _nearest_mutant(v.position)
	if p.is_bot and mp != Vector3.INF:
		var tm := Vector3(mp.x - v.position.x, 0.0, mp.z - v.position.z).normalized()
		if base.dot(tm) > -0.2:
			dir = (base * 0.4 + tm * 0.6).normalized()
	elif not p.is_bot:
		dir = (base * 0.6 + f * 0.4).normalized()
	lock_until[best] = clock + SHOVE_LOCK
	shoved_by[best] = [id, clock]
	if bots.has(best):
		bots[best].path = []
		bots[best].think = 0.0
	_rpc_shove.rpc(id, best, _clip(p.position, p.position + base * maxf(best_d - 0.6, 0.0)), _clip(v.position, v.position + dir * KNOCK))

func _clip(a: Vector3, b: Vector3) -> Vector3:
	var n := int(a.distance_to(b) / 0.1) + 1
	var last := a
	for k in range(1, n + 1):
		var q := a.lerp(b, float(k) / float(n))
		q.x = clampf(q.x, 0.3, W - 0.3)
		q.z = clampf(q.z, 0.3, D - 0.3)
		if blocked[_cell(q)] == 1:
			break
		last = q
	return Vector3(last.x, a.y, last.z)

func _tween_move(id: int, to: Vector3, t: float) -> void:
	var p: LabPlayer3D = players[id]
	if _push_tw.has(id):
		var old: Tween = _push_tw[id]
		if old and old.is_valid():
			old.kill()
	var tw := create_tween()
	tw.tween_property(p, "position", Vector3(to.x, p.position.y, to.z), t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_push_tw[id] = tw

func _lock_input(p: LabPlayer3D, t: float) -> void:
	if not p.is_local_human():
		return
	p.input_enabled = false
	get_tree().create_timer(t).timeout.connect(func() -> void:
		if is_instance_valid(p) and p.alive and st == St.RUN:
			p.input_enabled = true)

@rpc("authority", "call_local", "reliable")
func _rpc_shove(a: int, v: int, lunge_to: Vector3, push_to: Vector3) -> void:
	var pa: LabPlayer3D = players[a]
	if not pa.alive:
		return
	pa.face(lunge_to - pa.position)
	pa.body.play_action("Shield_Dash", 0.05, 1.6)
	Fx.sfx("whoosh", pa.position, -4.0, 1.1)
	if pa.is_multiplayer_authority():
		_tween_move(a, lunge_to, 0.15)
	_lock_input(pa, 0.18)
	if v < 0 or not players[v].alive:
		return
	var pv: LabPlayer3D = players[v]
	pv.face(pa.position - pv.position)
	pv.body.play_action("Hit_Knockback", 0.05, 1.2)
	Fx.sfx("hit", pv.position, -2.0, 1.1)
	Fx.shake(0.15)
	if pv.is_multiplayer_authority():
		_tween_move(v, push_to, 0.35)
	_lock_input(pv, SHOVE_LOCK)

func _physics_process(delta: float) -> void:
	if not world or not NetworkManager.is_server():
		return
	for id in players:
		var pp: Vector3 = players[id].position
		var lp: Vector3 = _last_pos[id]
		var v: Vector3 = vel[id]
		vel[id] = v.lerp((pp - lp) / maxf(delta, 0.0001), 0.3)
		_last_pos[id] = pp
	for i in mutants.size():
		if st == St.RUN or int(mutants[i].mode) == 1:
			_mutant_tick(i, delta)
		var m: Dictionary = mutants[i]
		m.sync_t = float(m.sync_t) - delta
		if float(m.sync_t) <= 0.0 and int(m.mode) > 0:
			m.sync_t = 0.05
			_rpc_msync.rpc(i, m.pos, float(m.yaw))

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_msync(i: int, p: Vector3, yaw: float) -> void:
	if i < mutants.size():
		mutants[i].tpos = p
		mutants[i].tyaw = yaw
		if int(mutants[i].mode) == 0:
			mutants[i].mode = 2

func _mfree(p: Vector3) -> bool:
	if p.x < 0.3 or p.x > W - 0.3 or p.z < 0.3 or p.z > D - 0.3:
		return false
	return mblock[_cell(p)] == 0

func _mut_slide(a: Vector3, b: Vector3) -> Vector3:
	if not _mfree(a):
		return Vector3(clampf(b.x, 0.3, W - 0.3), 0.0, clampf(b.z, 0.3, D - 0.3))
	if _mfree(b):
		return b
	var bx := Vector3(b.x, 0.0, a.z)
	if _mfree(bx):
		return bx
	var bz := Vector3(a.x, 0.0, b.z)
	if _mfree(bz):
		return bz
	return a

func _mutant_tick(i: int, delta: float) -> void:
	var m: Dictionary = mutants[i]
	var mode: int = m.mode
	if mode == 0:
		return
	var pos: Vector3 = m.pos
	if mode == 1:
		var entry := Vector3(float(m.cx), 0.0, 1.0)
		var ev := entry - pos
		ev.y = 0.0
		if ev.length() < 0.08:
			m.mode = 2
			m.think = 0.0
		else:
			pos += ev.normalized() * minf(ev.length(), 3.4 * delta)
			m.yaw = atan2(ev.x, ev.z)
		m.pos = pos
		return
	if mode == 3:
		m.feed = float(m.feed) - delta
		if float(m.feed) <= 0.0:
			m.mode = 2
			m.think = 0.0
		return
	m.lunge_cd = float(m.lunge_cd) - delta
	m.think = float(m.think) - delta
	var spd := _mut_speed()
	var dir := Vector3.ZERO
	var lunging := float(m.lunge_t) > 0.0
	if float(m.wind) > 0.0:
		m.wind = float(m.wind) - delta
		var wt: int = m.target
		var aim := Vector3(sin(float(m.yaw)), 0.0, cos(float(m.yaw)))
		if wt != -1 and players.has(wt) and players[wt].alive:
			var wp: Vector3 = players[wt].position
			var wv: Vector3 = vel.get(wt, Vector3.ZERO)
			var la := wp + wv * 0.22 - pos
			la.y = 0.0
			if la.length() > 0.05:
				aim = la.normalized()
		m.yaw = lerp_angle(float(m.yaw), atan2(aim.x, aim.z), 1.0 - exp(-10.0 * delta))
		if float(m.wind) <= 0.0:
			m.lunge_t = LUNGE_T
			m.lunge_dir = aim
			_rpc_lunge.rpc(i, 1)
	elif lunging:
		m.lunge_t = float(m.lunge_t) - delta
		dir = m.lunge_dir
		spd = LUNGE_SPEED
		if float(m.lunge_t) <= 0.0:
			m.recover = RECOVER_T
	else:
		if float(m.recover) > 0.0:
			m.recover = float(m.recover) - delta
			spd *= 0.35
		if float(m.think) <= 0.0:
			m.think = randf_range(0.2, 0.3)
			_mutant_think(i)
		var tgt: int = m.target
		if tgt != -1 and players.has(tgt) and players[tgt].alive:
			var tp: Vector3 = players[tgt].position
			var d := Vector2(tp.x - pos.x, tp.z - pos.z).length()
			if d < 7.0 and _los(pos, tp) and _walk_clear(mblock, pos, tp):
				var tv: Vector3 = vel.get(tgt, Vector3.ZERO)
				var lead := tp + tv * clampf(d / 9.0, 0.05, 0.35) - pos
				lead.y = 0.0
				dir = lead.normalized() if lead.length() > 0.05 else Vector3.ZERO
				if d < LUNGE_R and float(m.lunge_cd) <= 0.0 and float(m.recover) <= 0.0 and dir != Vector3.ZERO:
					m.wind = WIND_T
					m.lunge_cd = LUNGE_CD
					_rpc_lunge.rpc(i, 0)
					m.pos = pos
					return
		if dir == Vector3.ZERO:
			dir = _follow_path(m, pos)
	for j in mutants.size():
		if j == i or int(mutants[j].mode) < 2:
			continue
		var op: Vector3 = mutants[j].pos
		var off := pos - op
		off.y = 0.0
		if off.length() < 1.6 and off.length() > 0.01:
			dir = (dir + off.normalized() * 0.8).normalized()
	if dir.length() > 0.01:
		var np := _mut_slide(pos, pos + dir * spd * delta)
		if lunging and np.distance_to(pos) < spd * delta * 0.3:
			m.lunge_t = 0.0
			m.recover = RECOVER_T
		m.yaw = lerp_angle(float(m.yaw), atan2(dir.x, dir.z), 1.0 - exp(-(20.0 if lunging else 10.0) * delta))
		pos = np
	m.pos = pos
	var reach := CATCH_R_LUNGE if float(m.lunge_t) > 0.0 else CATCH_R
	for id in alive_ids():
		var pp: Vector3 = players[id].position
		if Vector2(pp.x - pos.x, pp.z - pos.z).length() < reach:
			_catch(i, id)
			break

func _mutant_think(i: int) -> void:
	var m: Dictionary = mutants[i]
	var pos: Vector3 = m.pos
	var best := -1
	var bd := INF
	for id in alive_ids():
		var pp: Vector3 = players[id].position
		var d := pos.distance_to(pp)
		if d > 16.0 or not _los(pos, pp):
			continue
		var s := d
		for j in mutants.size():
			if j != i and int(mutants[j].mode) >= 2 and int(mutants[j].target) == id:
				var jp: Vector3 = mutants[j].pos
				if jp.distance_to(pp) < d:
					s += 3.0
		if int(m.target) == id:
			s -= 0.8
		if s < bd:
			bd = s
			best = id
	var goal := Vector3.INF
	var last: Vector3 = m.last
	if best != -1:
		m.target = best
		goal = players[best].position
		m.last = goal
	elif last != Vector3.INF and last.distance_to(pos) > 1.0:
		m.target = -1
		goal = last
	else:
		var nd := INF
		for id in alive_ids():
			var d: float = players[id].position.distance_to(pos)
			if d < nd:
				nd = d
				best = id
		m.target = best
		if best != -1:
			goal = players[best].position
		m.last = Vector3.INF
	if goal != Vector3.INF:
		m.path = _path_to(mblock, pos, goal)

func _follow_path(m: Dictionary, pos: Vector3) -> Vector3:
	var path: Array = m.path
	while path.size() > 1:
		var w: Vector3 = path[0]
		if Vector2(w.x - pos.x, w.z - pos.z).length() < 0.35:
			path.pop_front()
		else:
			break
	if path.size() > 1:
		var ahead: Vector3 = path[1]
		if _walk_clear(mblock, pos, ahead):
			path.pop_front()
	if path.is_empty():
		return Vector3.ZERO
	var w2: Vector3 = path[0]
	var v := Vector3(w2.x - pos.x, 0.0, w2.z - pos.z)
	if v.length() < 0.1:
		path.pop_front()
		return Vector3.ZERO
	return v.normalized()

func _catch(i: int, id: int) -> void:
	var m: Dictionary = mutants[i]
	elim_order.append(id)
	m.mode = 3
	m.feed = FEED_T
	m.lunge_t = 0.0
	m.wind = 0.0
	m.recover = 0.0
	m.target = -1
	m.last = Vector3.INF
	m.path = []
	var feeder := -1
	if shoved_by.has(id):
		var sb: Array = shoved_by[id]
		if clock - float(sb[1]) < FEED_CREDIT and int(sb[0]) != id:
			feeder = int(sb[0])
	var pp: Vector3 = players[id].position
	var mp: Vector3 = m.pos
	m.yaw = atan2(pp.x - mp.x, pp.z - mp.z)
	_rpc_catch.rpc(i, id, m.pos, feeder)

@rpc("authority", "call_local", "reliable")
func _rpc_lunge(i: int, phase: int) -> void:
	var m: Dictionary = mutants[i]
	var n: Node3D = m.node
	var b: LabCharacter = m.body
	var eye: OmniLight3D = m.eye
	if phase == 0:
		m.lean = -0.35
		m.flare = 0.5
		b.anim.speed_scale = 0.4
		Fx.sfx("hum", n.position + Vector3(0, 2.0, 0), -2.0, 0.34)
		Fx.sfx("buzzer", n.position + Vector3(0, 2.0, 0), -14.0, 0.45)
	else:
		m.lean = 0.5
		Fx.sfx("whoosh", n.position + Vector3(0, 1.4, 0), 2.0, 0.55)
		Fx.shake(0.12)

@rpc("authority", "call_local", "reliable")
func _rpc_catch(i: int, id: int, mpos: Vector3, feeder: int) -> void:
	if not elim_order.has(id):
		elim_order.append(id)
	var m: Dictionary = mutants[i]
	var p: LabPlayer3D = players[id]
	if _push_tw.has(id):
		var old: Tween = _push_tw[id]
		if old and old.is_valid():
			old.kill()
	var to := p.position - mpos
	to.y = 0.0
	if to.length() < 0.05:
		to = Vector3(0, 0, 1)
	m.tyaw = atan2(to.x, to.z)
	m.lean = 0.0
	var b: LabCharacter = m.body
	b.rotation.y = atan2(to.x, to.z)
	b.anim.speed_scale = 1.0
	b.play_action("Melee_Hook", 0.05, 1.25)
	p.face(-to)
	if p.is_local_human():
		p.input_enabled = false
	eliminate(id, "Death01")
	var at := p.position + Vector3(0, 1.0, 0)
	Fx.sfx("hit", at, 6.0, 0.45)
	get_tree().create_timer(0.08).timeout.connect(func() -> void: Fx.sfx("hit", at, 3.0, 0.72))
	Fx.sfx("splat", at, 4.0, 0.6)
	Fx.blood(world, at, 140)
	Fx.blood(world, at + to.normalized() * 0.7 - Vector3(0, 0.4, 0), 40)
	Fx.shake(0.65)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.15, 0.08)
	fl.light_energy = 7.0
	fl.omni_range = 4.0
	world.add_child(fl)
	fl.global_position = at
	var ft := fl.create_tween()
	ft.tween_property(fl, "light_energy", 0.0, 0.4)
	ft.tween_callback(fl.queue_free)
	var me := local_player()
	if me and me.peer_id == id:
		_big_local("SPINE SNAPPED", "ff4040", 1.6, 72)
	elif feeder >= 0 and players.has(feeder):
		_big_local("%s FED %s TO IT" % [players[feeder].display_name, p.display_name], "ff8a4a", 1.4, 40)
	else:
		_big_local("%s SNAPPED" % p.display_name, "ff6a5a", 1.0, 40)
	_refresh_board()

func _update_mutants(delta: float) -> void:
	var server := NetworkManager.is_server()
	for i in mutants.size():
		var m: Dictionary = mutants[i]
		var n: Node3D = m.node
		var b: LabCharacter = m.body
		var yaw: float
		if server:
			n.position = m.pos
			yaw = m.yaw
		elif _released[i]:
			n.position = n.position.lerp(m.tpos, 1.0 - exp(-16.0 * delta))
			yaw = m.tyaw
		else:
			yaw = 0.0
		b.rotation.y = lerp_angle(b.rotation.y, yaw, 1.0 - exp(-12.0 * delta))
		var prev: Vector3 = m.prev
		var flat := Vector3(n.position.x - prev.x, 0.0, n.position.z - prev.z)
		m.prev = n.position
		m.spd = lerpf(float(m.spd), flat.length() / maxf(delta, 0.0001), 0.2)
		var spd: float = m.spd
		if not _released[i]:
			if not b._action_busy:
				b.anim.speed_scale = randf_range(0.85, 1.15)
				b.play_action("Zombie_Scratch", 0.25)
		elif not b._action_busy and float(m.flare) <= 0.0:
			if spd > 0.4:
				b.play_loop("Zombie_Walk_Fwd")
				b.anim.speed_scale = clampf(spd / 2.3, 0.9, 2.8)
			else:
				b.play_loop("Zombie_Idle")
				b.anim.speed_scale = 1.0
		m.lean = move_toward(float(m.lean), 0.0, delta * 0.9)
		var dm: Deform = m.mod
		if dm:
			dm.lean = float(m.lean)
		if spd > 0.5:
			m.step_t = float(m.step_t) - delta * clampf(spd / 3.0, 0.6, 2.2)
			if float(m.step_t) <= 0.0:
				m.step_t = 0.42
				Fx.sfx("step", n.position, 3.0, 0.45)
		m.growl_t = float(m.growl_t) - delta
		if float(m.growl_t) <= 0.0:
			m.growl_t = randf_range(3.5, 6.0)
			Fx.sfx("hum", n.position + Vector3(0, 2.0, 0), -9.0, randf_range(0.38, 0.5))
		var eye: OmniLight3D = m.eye
		m.flare = maxf(float(m.flare) - delta, 0.0)
		eye.light_energy = randf_range(1.9, 2.7) + float(m.flare) * 12.0
		eye.light_color = Color(1.0, 0.82, 0.3).lerp(Color(1.0, 0.25, 0.1), clampf(float(m.flare) * 2.0, 0.0, 1.0))
		for c in m.chains:
			var att: Node3D = c.att
			var ch: Node3D = c.node
			var gp := att.global_position
			var cp: Vector3 = c.prev
			var v := (gp - cp) / maxf(delta, 0.0001)
			c.prev = gp
			var want := Vector3(clampf(v.z * 0.1, -0.9, 0.9), 0.0, clampf(-v.x * 0.1, -0.9, 0.9))
			var r: Vector3 = c.rot
			r = r.lerp(want, 1.0 - exp(-6.0 * delta))
			c.rot = r
			ch.global_position = gp
			ch.rotation = r

func _update_beacons(delta: float) -> void:
	for k in _beacons.size():
		var bc: Node3D = _beacons[k]
		var sp: SpotLight3D = bc.get_meta("light")
		var spin: Node3D = bc.get_meta("spin")
		var dome: MeshInstance3D = bc.get_meta("dome")
		var on := _released[k] or (k == 1 and _warned2)
		sp.light_energy = 6.0 if on else 0.0
		var dm: StandardMaterial3D = dome.material_override
		dm.emission_energy_multiplier = (3.5 + sin(clock * 20.0)) if on else 0.4
		if on:
			spin.rotation.y += delta * 7.0

func _flick(delta: float) -> void:
	for f in _flicker:
		var l: Light3D = f.l
		f.t = float(f.t) - delta
		if float(f.t) > 0.0:
			continue
		match int(f.kind):
			0:
				var on := randf() > 0.4
				f.t = randf_range(0.03, 0.12) if randf() < 0.7 else randf_range(0.6, 1.8)
				l.light_energy = float(f.base) * (1.0 if on else 0.05)
				if on and randf() < 0.2:
					Fx.sfx("hum", l.global_position, -24.0, 1.6)
			1:
				var on1 := randf() > 0.1
				f.t = randf_range(0.05, 0.1) if not on1 else randf_range(1.0, 3.0)
				l.light_energy = float(f.base) * (1.0 if on1 else 0.1)
			_:
				l.light_energy = float(f.base) * randf_range(0.65, 1.1)
				f.t = randf_range(0.05, 0.12)

func _update_cam(delta: float) -> void:
	var lp := local_player()
	var tgt := Vector3(W * 0.5, 0.0, D * 0.5 - 0.6)
	var off := Vector3(0.0, 12.5, 7.0)
	if lp and lp.alive and st != St.DONE:
		tgt = Vector3(lerpf(W * 0.5, lp.position.x, 0.45), 0.0, lerpf(D * 0.5, lp.position.z, 0.5) - 0.4)
		off = Vector3(0.0, 9.2, 6.2)
	_cam_t = _cam_t.lerp(tgt, 1.0 - exp(-3.0 * delta))
	_cam_o = _cam_o.lerp(off, 1.0 - exp(-2.0 * delta))
	camera.position = _cam_t + _cam_o
	camera.look_at(_cam_t + Vector3(0.0, 0.6, 0.0), Vector3.UP)

@rpc("authority", "call_local", "reliable")
func _rpc_big(text: String, hex: String, hold: float) -> void:
	_big_local(text, hex, hold)
	Fx.sfx("click")

@rpc("authority", "call_local", "reliable")
func _rpc_start() -> void:
	st = St.RUN
	clock = 0.0
	for id in players:
		var p: LabPlayer3D = players[id]
		if p.is_local_human():
			p.input_enabled = true
	_release(0)

func _release(i: int) -> void:
	_released[i] = true
	var m: Dictionary = mutants[i]
	if NetworkManager.is_server():
		m.mode = 1
	var cx: float = m.cx
	var gate: Node3D = _gates[CELLS.find(cx)]
	if gate:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(gate, "rotation_degrees:x", 90.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(gate, "position", Vector3(cx + randf_range(-0.3, 0.3), 0.06, 0.25), 0.42)
		tw.tween_property(gate, "rotation_degrees:y", randf_range(-14.0, 14.0), 0.42)
		tw.chain().tween_callback(func() -> void:
			Fx.sparks(world, Vector3(cx, 0.1, 1.6))
			Fx.sparks(world, Vector3(cx - 0.8, 0.1, 2.4))
			Fx.sfx("hit", Vector3(cx, 0.2, 1.5), 4.0, 0.5)
			Fx.shake(0.5))
	var b: LabCharacter = m.body
	b.anim.speed_scale = 1.0
	b.play_action("Melee_Hook", 0.05, 0.9)
	Fx.sparks(world, Vector3(cx - 1.2, 1.6, 0.1))
	Fx.sparks(world, Vector3(cx + 1.2, 2.2, 0.1))
	Fx.sfx("explosion", Vector3(cx, 1.5, 0.0), -6.0, 0.7)
	Fx.sfx("buzzer", null, -5.0, 0.7)
	Fx.shake(0.7)
	_big_local("IT'S LOOSE  ·  RUN" if i == 0 else "A SECOND ONE GOT OUT", "ff5a4a", 1.4, 64 if i == 0 else 52)

@rpc("authority", "call_local", "reliable")
func _rpc_release(i: int) -> void:
	_release(i)

@rpc("authority", "call_local", "reliable")
func _rpc_warn2() -> void:
	_warned2 = true
	var cx: float = mutants[1].cx
	var gate: Node3D = _gates[CELLS.find(cx)]
	if gate:
		var base := gate.position
		var tw := create_tween()
		for k in 6:
			tw.tween_property(gate, "position", base + Vector3(randf_range(-0.06, 0.06), 0.0, randf_range(0.02, 0.1)), 0.06)
			tw.tween_property(gate, "position", base, 0.12)
			tw.tween_interval(0.18)
	for k in 4:
		get_tree().create_timer(0.36 * float(k)).timeout.connect(func() -> void:
			Fx.sfx("hit", Vector3(cx, 1.4, -0.2), 2.0, randf_range(0.4, 0.55))
			Fx.shake(0.15))
	Fx.sfx("buzzer", null, -6.0, 0.55)
	_big_local("SOMETHING ELSE IS AWAKE", "ffb04a", 1.4, 44)

@rpc("authority", "call_local", "reliable")
func _rpc_end(timeout: bool) -> void:
	st = St.DONE
	for id in players:
		players[id].input_enabled = false
	var alive := alive_ids()
	var txt := "TIME!"
	if alive.size() == 1:
		txt = "%s SURVIVES" % players[alive[0]].display_name
	elif alive.is_empty():
		txt = "NOBODY SURVIVES"
	elif timeout:
		txt = "TIME!  %d SURVIVE" % alive.size()
	_big_local(txt, "e2c84b", 0.0, 56)
	Fx.sfx("buzzer", null, -6.0, 1.3)

func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	for n in ["3", "2", "1"]:
		_rpc_big.rpc(n, "e8e2c8", 0.0)
		await get_tree().create_timer(0.8).timeout
	_rpc_start.rpc()
	while clock < TIME_LIMIT and alive_ids().size() > 1:
		if not _warned2 and clock >= SECOND_AT - SECOND_WARN:
			_rpc_warn2.rpc()
		if not _released[1] and clock >= SECOND_AT:
			_rpc_release.rpc(1)
		await get_tree().process_frame
	_rpc_end.rpc(clock >= TIME_LIMIT)
	await get_tree().create_timer(2.4).timeout
	if not _ended:
		_ended = true
		finished.emit(survival_placement(elim_order))

func _center(i: int) -> Vector3:
	return Vector3((float(i % GW) + 0.5) * CELL, 0.0, (float(i / GW) + 0.5) * CELL)

func _cell(p: Vector3) -> int:
	return clampi(int(p.z / CELL), 0, GH - 1) * GW + clampi(int(p.x / CELL), 0, GW - 1)

func _seg_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for ax in 2:
		var lo: float = r.position[ax]
		var hi: float = r.end[ax]
		if absf(d[ax]) < 0.00001:
			if a[ax] < lo or a[ax] > hi:
				return false
			continue
		var ta := (lo - a[ax]) / d[ax]
		var tb := (hi - a[ax]) / d[ax]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true

func _los(a: Vector3, b: Vector3) -> bool:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	for r in walls:
		if _seg_hits(a2, b2, r):
			return false
	return true

func _walk_clear(grid: PackedByteArray, a: Vector3, b: Vector3) -> bool:
	var n := int(a.distance_to(b) / 0.2) + 1
	for k in n + 1:
		var q := a.lerp(b, float(k) / float(n))
		if grid[_cell(q)] == 1:
			return false
	return true

func _bfs(grid: PackedByteArray, sources: Array) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(GW * GH)
	dist.fill(-1)
	var q: Array[int] = []
	for s in sources:
		var si: int = s
		if dist[si] == -1:
			dist[si] = 0
			q.append(si)
	var h := 0
	while h < q.size():
		var c: int = q[h]
		h += 1
		var cx := c % GW
		var cy := c / GW
		for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + o[0]
			var ny: int = cy + o[1]
			if nx < 0 or ny < 0 or nx >= GW or ny >= GH:
				continue
			var nn := ny * GW + nx
			if dist[nn] != -1 or grid[nn] == 1:
				continue
			dist[nn] = dist[c] + 1
			q.append(nn)
	return dist

func _nearest_free(grid: PackedByteArray, i: int) -> int:
	if grid[i] == 0:
		return i
	var best := i
	var bd := INF
	var c := _center(i)
	for j in GW * GH:
		if grid[j] == 0:
			var d := _center(j).distance_squared_to(c)
			if d < bd:
				bd = d
				best = j
	return best

func _path_to(grid: PackedByteArray, from: Vector3, goal: Vector3) -> Array:
	var gi := _nearest_free(grid, _cell(goal))
	var dist := _bfs(grid, [gi])
	var c := _nearest_free(grid, _cell(from))
	if dist[c] == -1:
		return [goal]
	var path: Array = []
	var guard := 0
	while c != gi and guard < 300:
		var cx := c % GW
		var cy := c / GW
		var nxt := -1
		for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + o[0]
			var ny: int = cy + o[1]
			if nx < 0 or ny < 0 or nx >= GW or ny >= GH:
				continue
			var nn := ny * GW + nx
			if dist[nn] != -1 and dist[nn] < dist[c]:
				nxt = nn
				break
		if nxt == -1:
			break
		c = nxt
		path.append(_center(c))
		guard += 1
	path.append(goal)
	return path

func _corner(i: int) -> float:
	var cx := i % GW
	var cy := i / GW
	var n := 0.0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var x: int = cx + dx
			var y: int = cy + dy
			if x < 0 or y < 0 or x >= GW or y >= GH or blocked[y * GW + x] == 1:
				n += 1.0
	return n

func _threats() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in mutants.size():
		var m: Dictionary = mutants[k]
		if int(m.mode) >= 1:
			var mp: Vector3 = m.pos
			out.append(Vector3(mp.x, 0.0, maxf(mp.z, 0.3)))
		elif k == 0 or _warned2:
			out.append(Vector3(float(m.cx), 0.0, 0.6))
	return out

func _lunging_near(pos: Vector3, r: float) -> bool:
	for m in mutants:
		var mp: Vector3 = m.pos
		if (float(m.lunge_t) > 0.0 or float(m.wind) > 0.0) and mp.distance_to(pos) < r:
			return true
	return false

func _bot_brain(delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	if st != St.RUN or clock < float(lock_until[id]):
		p.speed = BASE_SPEED
		_stamina(id, false, delta)
		return Vector3.ZERO
	var b: Dictionary = bots[id]
	var threats := _threats()
	var dn := INF
	var mp := Vector3.ZERO
	for t in threats:
		var d := Vector2(t.x - p.position.x, t.z - p.position.z).length()
		if d < dn:
			dn = d
			mp = t
	var want := dn < float(b.panic) or _lunging_near(p.position, 5.0)
	p.speed = SPRINT_SPEED if _stamina(id, want, delta) else BASE_SPEED
	b.shove_t = float(b.shove_t) - delta
	if float(b.shove_t) <= 0.0:
		b.shove_t = randf_range(0.2, 0.35)
		if _bot_shove(id, p, b, mp, dn):
			return Vector3.ZERO
	if dn < 2.2:
		var away := p.position - mp
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3(0, 0, 1)
		var bestv := Vector3.ZERO
		var bs := -INF
		for k in 14:
			var dv := away.rotated(Vector3.UP, (float(k) - 6.5) * 0.4)
			var probe := p.position + dv * 0.9
			if probe.x < 0.4 or probe.x > W - 0.4 or probe.z < 0.4 or probe.z > D - 0.4 or blocked[_cell(probe)] == 1:
				continue
			var s := dv.dot(away)
			var far := p.position + dv * 2.0
			if far.x > 0.4 and far.x < W - 0.4 and far.z > 0.4 and far.z < D - 0.4 and blocked[_cell(far)] == 0:
				s += 0.5
			if s > bs:
				bs = s
				bestv = dv
		if bestv != Vector3.ZERO:
			b.think = minf(float(b.think), 0.12)
			return bestv
	b.think = float(b.think) - delta
	if float(b.think) <= 0.0:
		b.think = randf_range(0.3, 0.45)
		_bot_plan(id, p, b, threats)
	return _follow(p, b)

func _bot_shove(id: int, p: LabPlayer3D, b: Dictionary, mp: Vector3, dn: float) -> bool:
	if clock < float(shove_ready[id]):
		return false
	for o in alive_ids():
		if o == id:
			continue
		var op: Vector3 = players[o].position
		var to := op - p.position
		to.y = 0.0
		var d := to.length()
		if d > SHOVE_REACH - 0.15 or d < 0.05:
			continue
		var dirty := false
		if dn < 5.5:
			var tm := Vector3(mp.x - p.position.x, 0.0, mp.z - p.position.z)
			var od := Vector2(mp.x - op.x, mp.z - op.z).length()
			dirty = to.dot(tm) > 0.0 and od < dn + 0.3
		var roll := randf()
		if (dirty and roll < float(b.dirty)) or (not dirty and dn > 7.0 and roll < 0.03):
			b.shove_t = randf_range(2.0, 3.5)
			p.face(to)
			p._target_yaw = atan2(to.x, to.z)
			_try_shove(id)
			return true
	return false

func _bot_plan(id: int, p: LabPlayer3D, b: Dictionary, threats: Array[Vector3]) -> void:
	var src: Array = []
	for t in threats:
		src.append(_nearest_free(mblock, _cell(t)))
	var danger := _bfs(mblock, src) if not src.is_empty() else PackedInt32Array()
	var mine := _bfs(blocked, [_nearest_free(blocked, _cell(p.position))])
	var others: Array[Vector3] = []
	for o in alive_ids():
		if o != id:
			others.append(players[o].position)
	var best := -1
	var bs := -INF
	for i in GW * GH:
		if mine[i] < 0:
			continue
		var dg := 40.0
		if not danger.is_empty() and danger[i] >= 0:
			dg = float(danger[i])
		if mine[i] > 2 and float(mine[i]) >= dg * 0.85:
			continue
		var c := _center(i)
		var s := minf(dg, 24.0) - float(mine[i]) * 0.3 - _corner(i) * 0.7 + randf() * 0.6
		for op in others:
			var od: float = op.distance_to(c)
			if od < 2.2:
				s -= 2.2 - od
		if c.z < 1.2:
			s -= 2.0
		if s + 2.5 <= bs:
			continue
		var hidden := not threats.is_empty()
		for t in threats:
			if _los(t, c):
				hidden = false
				break
		if hidden:
			s += 2.5
		if s > bs:
			bs = s
			best = i
	if best != -1:
		b.goal = _center(best)
		b.path = _path_to(blocked, p.position, b.goal)

func _follow(p: LabPlayer3D, b: Dictionary) -> Vector3:
	var path: Array = b.path
	while path.size() > 1:
		var w: Vector3 = path[0]
		if Vector2(w.x - p.position.x, w.z - p.position.z).length() < 0.35:
			path.pop_front()
		else:
			break
	if path.size() > 1:
		var ahead: Vector3 = path[1]
		if _walk_clear(blocked, p.position, ahead):
			path.pop_front()
	if path.is_empty():
		return Vector3.ZERO
	var w2: Vector3 = path[0]
	var v := Vector3(w2.x - p.position.x, 0.0, w2.z - p.position.z)
	if v.length() < 0.12:
		if path.size() == 1:
			path.pop_front()
		return Vector3.ZERO
	return v.normalized()
