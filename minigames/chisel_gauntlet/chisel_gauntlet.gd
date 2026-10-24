extends ArenaMinigame3D
## Chisel Gauntlet: every subject stands at a carving station with a 3x3x3 stone
## block on a turntable. MEMORIZE (4 s): the target shape glows as a green
## hologram. CARVE (15 s): click segments to chisel them off (A/D or drag turns
## the block, RESET restores it, SUBMIT locks it in). Removing a wrong segment or
## leaving a target one is an error. The worst carver of every round is executed
## by the ceiling press or the foreman's sledgehammer. 3 rounds, shapes get harder.
## Survivors place by total accuracy, then the dead in reverse order.

const ROUNDS: int = 3
const MEMO_TIME: float = 4.0
const CARVE_TIME: float = 15.0
const JUDGE_TIME: float = 2.6
const EXEC_TIME: float = 4.4
const REMOVE_COUNT: Array[int] = [3, 5, 7]
const CELL: float = 0.13
const CELL_SIZE: float = 0.122
const TOP_Y: float = 1.01
const SUBJECT_Z: float = 0.62
const ROOM_HALF: float = 6.6
const CEIL: float = 3.9
const PRESS_UP: float = 3.55
const HOLO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.25, 1.0, 0.45, 1.0);
uniform float half_size = 0.061;
uniform float strength = 1.0;
varying vec3 lp;
varying vec3 wp;
void vertex() {
	lp = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 a = abs(lp) / half_size;
	float c = step(0.84, a.x) + step(0.84, a.y) + step(0.84, a.z);
	float e = step(1.5, c);
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float scan = 0.65 + 0.35 * sin(wp.y * 240.0 - TIME * 9.0);
	float flick = 0.88 + 0.12 * sin(TIME * 41.0) * sin(TIME * 7.0);
	ALBEDO = tint.rgb * (0.16 + e * 1.7 + fres * 0.4) * scan * flick * strength;
}
"""

enum Ph { INTRO, MEMO, CARVE, JUDGE, EXEC, DONE }

class ArmIK extends SkeletonModifier3D:
	var upper: int
	var lower: int
	var hand: int
	var target: Vector3
	var pole: Vector3
	func setup(sk: Skeleton3D, side: String, pole_dir: Vector3) -> void:
		upper = sk.find_bone("upperarm_" + side)
		lower = sk.find_bone("lowerarm_" + side)
		hand = sk.find_bone("hand_" + side)
		pole = pole_dir
	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or influence <= 0.001:
			return
		var pc := sk.get_bone_global_pose(sk.get_bone_parent(upper))
		var pu := sk.get_bone_global_pose(upper)
		var pl := sk.get_bone_global_pose(lower)
		var ph := sk.get_bone_global_pose(hand)
		var a := pu.origin
		var b := pl.origin
		var c := ph.origin
		var l1 := a.distance_to(b)
		var l2 := b.distance_to(c)
		var d := clampf(a.distance_to(target), absf(l1 - l2) + 0.01, l1 + l2 - 0.005)
		var dir := (target - a).normalized()
		var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(0.0, l1 * l1 - along * along))
		var perp := (pole - dir * pole.dot(dir)).normalized()
		var elbow := a + dir * along + perp * h
		var r1 := Basis(Quaternion((b - a).normalized(), (elbow - a).normalized()))
		var b2 := a + r1 * (b - a)
		var c2 := b2 + r1 * (c - b)
		var r2 := Basis(Quaternion((c2 - b2).normalized(), (target - b2).normalized()))
		var ug := r1 * pu.basis.orthonormalized()
		var lg := r2 * r1 * pl.basis.orthonormalized()
		var hg := r2 * r1 * ph.basis.orthonormalized()
		sk.set_bone_pose_rotation(upper, (pc.basis.orthonormalized().inverse() * ug).get_rotation_quaternion())
		sk.set_bone_pose_rotation(lower, (ug.inverse() * lg).get_rotation_quaternion())
		sk.set_bone_pose_rotation(hand, (lg.inverse() * hg).get_rotation_quaternion())

var phase: Ph = Ph.INTRO
var clock: float = 0.0
var phase_end: float = 0.0
var round_i: int = 0
var target: int = 0
var stations: Dictionary = {}
var removed: Dictionary = {}
var submitted: Dictionary = {}
var submit_t: Dictionary = {}
var total: Dictionary = {}
var errs: Dictionary = {}
var dead_order: Array = []
var _bot: Dictionary = {}
var _carve_t: float = 0.0
var _carving: bool = false
var _ended: bool = false
var _me: int = 0
var _fp: bool = false
var _autotest: bool = false
var _yaw: float = 0.0
var _press_down: bool = false
var _drag: bool = false
var _drag_px: float = 0.0
var _keys: Dictionary = {}
var _hover: int = -1
var _stone_mats: Array[StandardMaterial3D] = []
var _holo_mat: StandardMaterial3D
var _ghost_mat: ShaderMaterial
var _hover_mat: StandardMaterial3D
var _wrong_mat: StandardMaterial3D
var _cell_mesh: ArrayMesh
var _soft: Texture2D
var _splat: ImageTexture
var _led_font: SystemFont
var _marquee: Array[Label3D] = []
var _marquee_text: String = "CARVE.  SUBMIT.  "
var _marquee_t: float = 0.0
var _marquee_off: int = 0
var _big_holo: Node3D
var _big_cells: Array[MeshInstance3D] = []
var _projector: OmniLight3D
var _foreman: LabCharacter
var _foreman_home: Vector3
var _exec_cam: Camera3D
var _vm: Node3D
var _vm_hammer: Node3D
var _cam_base: Transform3D
var _big: Label
var _hint: Label
var _timer_label: Label
var _round_label: Label

func begin() -> void:
	setup_arena(false)
	_me = multiplayer.get_unique_id()
	var args := OS.get_cmdline_user_args()
	_autotest = Globals.forced_minigame != "" and args.size() > 0
	_tune_light()
	_make_materials()
	_build_room()
	_build_hub()
	_place_stations()
	_build_foreman()
	_exec_cam = Camera3D.new()
	_exec_cam.fov = 58.0
	world.add_child(_exec_cam)
	var mine: Dictionary = NetworkManager.players.get(_me, {})
	_fp = stations.has(_me) and not bool(mine.get("is_bot", true)) and (not _autotest or args.has("fp"))
	if _fp:
		_setup_first_person()
	else:
		_setup_overview()
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.08
			n.shadow_enabled = false
	env.ambient_light_energy = 0.36
	env.ambient_light_color = Color(0.62, 0.58, 0.5)
	env.fog_density = 0.03
	env.fog_light_color = Color(0.22, 0.2, 0.17)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.018
	env.volumetric_fog_albedo = Color(0.8, 0.74, 0.64)
	env.volumetric_fog_length = 14.0
	env.ssao_radius = 0.8
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 0.9

func _make_materials() -> void:
	for k in 4:
		var m: StandardMaterial3D = mat("rock_boulder_dry", 1.1, Color(1.12, 1.1, 1.05)).duplicate()
		m.uv1_world_triplanar = false
		m.uv1_offset = Vector3(0.05 + 0.21 * float(k), 0.12 + 0.17 * float(k), 0.31 * float(k))
		m.metallic = 0.0
		m.metallic_texture = null
		m.roughness = 1.0
		m.roughness_texture = null
		m.metallic_specular = 0.2
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_stone_mats.append(m)
	var sh := Shader.new()
	sh.code = HOLO_SHADER
	_holo_mat = StandardMaterial3D.new()
	_holo_mat.albedo_color = Color(0.93, 0.62, 0.16)
	_holo_mat.roughness = 0.55
	_holo_mat.emission_enabled = true
	_holo_mat.emission = Color(0.55, 0.32, 0.05)
	_holo_mat.emission_energy_multiplier = 0.6
	_ghost_mat = ShaderMaterial.new()
	_ghost_mat.shader = sh
	_ghost_mat.set_shader_parameter("tint", Color(1.0, 0.12, 0.08))
	_hover_mat = StandardMaterial3D.new()
	_hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_hover_mat.albedo_color = Color(0.5, 0.42, 0.25, 0.5)
	_wrong_mat = StandardMaterial3D.new()
	_wrong_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wrong_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wrong_mat.albedo_color = Color(0.95, 0.05, 0.03, 0.55)
	_cell_mesh = _chamfer_cube(CELL_SIZE * 0.5, 0.013)
	_soft = _soft_tex()
	_splat = _splat_tex()
	_led_font = SystemFont.new()
	_led_font.font_names = PackedStringArray(["DejaVu Sans Mono", "Noto Sans Mono", "Liberation Mono", "Monospace"])
	_led_font.font_weight = 700

func _build_room() -> void:
	var room := Node3D.new()
	room.name = "Workshop"
	world.add_child(room)
	var s := ROOM_HALF * 2.0
	var wall := mat("concrete_wall_008", 0.45, Color(0.66, 0.62, 0.56))
	var lower := mat("dirty_concrete", 0.6, Color(0.5, 0.47, 0.42))
	box(Vector3(s, 0.2, s), Vector3(0, -0.1, 0), mat("damaged_concrete_floor", 0.4, Color(0.7, 0.66, 0.6)), room)
	box(Vector3(s, 0.2, s), Vector3(0, CEIL + 0.1, 0), mat("corrugated_iron", 0.6, Color(0.32, 0.3, 0.27)), room)
	for side in [-1.0, 1.0]:
		box(Vector3(s, CEIL, 0.3), Vector3(0, CEIL * 0.5, side * ROOM_HALF), wall, room)
		box(Vector3(0.3, CEIL, s), Vector3(side * ROOM_HALF, CEIL * 0.5, 0), wall, room)
		box(Vector3(s, 1.1, 0.34), Vector3(0, 0.55, side * (ROOM_HALF - 0.02)), lower, room)
		box(Vector3(0.34, 1.1, s), Vector3(side * (ROOM_HALF - 0.02), 0.55, 0), lower, room)
	var pillar := mat("concrete_wall_006", 0.6, Color(0.75, 0.72, 0.66))
	for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		box(Vector3(0.6, CEIL, 0.6), Vector3(c.x * (ROOM_HALF - 0.3), CEIL * 0.5, c.z * (ROOM_HALF - 0.3)), pillar, room)
	for k in 4:
		box(Vector3(s, 0.32, 0.26), Vector3(0, CEIL - 0.16, -ROOM_HALF + 2.2 + 2.9 * float(k)), mat("rusty_metal", 0.8, Color(0.5, 0.42, 0.36)), room)
	var pipe_mat := mat("rusty_metal_02", 1.5)
	for p in [[Vector3(0, 3.5, -ROOM_HALF + 0.3), s, 0.12, 0], [Vector3(0, 3.25, -ROOM_HALF + 0.28), s, 0.07, 0],
			[Vector3(-ROOM_HALF + 0.3, 3.4, 0), s, 0.1, 1], [Vector3(ROOM_HALF - 0.3, 3.3, 0), s, 0.09, 1],
			[Vector3(0, 3.45, ROOM_HALF - 0.3), s, 0.1, 0], [Vector3(2.4, CEIL - 0.45, 0), s, 0.06, 1]]:
		var pipe := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = p[2]
		cm.bottom_radius = p[2]
		cm.height = p[1]
		pipe.mesh = cm
		pipe.material_override = pipe_mat
		if int(p[3]) == 0:
			pipe.rotation_degrees.z = 90.0
		else:
			pipe.rotation_degrees.x = 90.0
		pipe.position = p[0]
		room.add_child(pipe)
	_tool_wall(Vector3(0, 0, -ROOM_HALF + 0.2), 0.0, room)
	_tool_wall(Vector3(-ROOM_HALF + 0.2, 0, 0), 90.0, room)
	_tool_wall(Vector3(ROOM_HALF - 0.2, 0, 0), -90.0, room)
	_tool_wall(Vector3(0, 0, ROOM_HALF - 0.2), 180.0, room)
	var clutter := [["steel_frame_shelves_02", -4.6, -6.1, 0.0, 1.1], ["steel_frame_shelves_02", 4.6, 6.1, 180.0, 1.1],
		["worn_metal_rack", 6.1, -4.4, -90.0, 1.1], ["worn_metal_rack", -6.1, 4.4, 90.0, 1.1],
		["barrel_03", -5.7, -2.6, 0.0, 1.0], ["barrel_03", -5.3, -3.2, 40.0, 1.0], ["barrel_03", 5.6, 2.9, 10.0, 1.0],
		["cement_bag", 5.5, -2.4, 20.0, 1.2], ["cement_bag", 5.7, -1.9, 80.0, 1.2], ["cement_bag", -2.3, 5.8, 10.0, 1.2],
		["wooden_crate_01", -5.6, 2.2, 15.0, 1.2], ["wooden_crate_02", 2.6, -5.8, -10.0, 1.2], ["old_military_crate", -2.8, -5.8, 0.0, 1.2],
		["metal_tool_chest", 5.6, 4.6, -90.0, 1.1], ["tool_cart", -4.4, 5.6, 160.0, 1.1], ["portable_generator", 4.2, -5.7, 180.0, 1.1],
		["propane_tank", -5.9, -5.2, 0.0, 1.0], ["trashbag", 5.8, 0.6, 0.0, 1.0], ["metal_trash_can", 5.9, 1.4, 0.0, 1.0],
		["old_drill_press", -5.8, -0.6, 90.0, 1.1], ["hand_truck", 2.0, 5.9, 200.0, 1.1], ["WetFloorSign_01", -1.0, -5.6, 20.0, 1.0],
		["old_tyre", 3.6, 5.8, 0.0, 1.0], ["plastic_crate_01", -3.8, -5.9, 12.0, 1.1], ["concrete_road_barrier", 0.4, 6.0, 180.0, 1.0]]
	for c in clutter:
		prop(c[0], Vector3(c[1], 0.0, c[2]), c[3], c[4], room)
	prop("power_box_01", Vector3(-1.6, 1.7, -ROOM_HALF + 0.18), 0.0, 1.3, room)
	prop("fire_alarm", Vector3(1.6, 2.1, -ROOM_HALF + 0.18), 0.0, 1.4, room)
	prop("power_box_01", Vector3(ROOM_HALF - 0.18, 1.7, 1.8), -90.0, 1.3, room)
	prop("security_camera_01", Vector3(ROOM_HALF - 0.5, 3.4, -ROOM_HALF + 0.5), -135.0, 1.4, room)
	for sc in [[Vector3(-ROOM_HALF + 0.18, 2.5, -2.4), 90.0, Vector3(0.3, 0, 0)], [Vector3(ROOM_HALF - 0.18, 2.5, 2.4), -90.0, Vector3(-0.3, 0, 0)], [Vector3(2.4, 2.5, ROOM_HALF - 0.18), 180.0, Vector3(0, 0, -0.3)]]:
		prop("industrial_caged_sconce", sc[0], sc[1], 1.3, room)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.42)
		l.light_energy = 0.9
		l.omni_range = 3.2
		room.add_child(l)
		l.position = sc[0] + sc[2]
	_rubble(room)
	_dust_motes(room)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 22:
		var d := Decal.new()
		d.texture_albedo = _splat
		var sz := rng.randf_range(0.6, 2.2)
		d.size = Vector3(sz, 0.4, sz * rng.randf_range(0.6, 1.0))
		d.modulate = Color(0.14, 0.13, 0.11, 0.85) if i % 3 != 0 else Color(0.36, 0.34, 0.3, 0.7)
		d.rotation.y = rng.randf() * TAU
		room.add_child(d)
		d.position = Vector3(rng.randf_range(-6.0, 6.0), 0.05, rng.randf_range(-6.0, 6.0))
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.76, 0.62)
	fill.light_energy = 0.55
	fill.omni_range = 9.0
	room.add_child(fill)
	fill.position = Vector3(0, 3.2, 0)

func _tool_wall(at: Vector3, yaw: float, room: Node3D) -> void:
	var n := Node3D.new()
	room.add_child(n)
	n.position = at
	n.rotation_degrees.y = yaw
	var board := box(Vector3(2.6, 1.3, 0.05), Vector3(-0.6, 1.75, 0.05), mat("black_painted_planks", 0.9, Color(0.5, 0.46, 0.4)), n)
	board.name = "ToolBoard"
	box(Vector3(2.7, 0.06, 0.08), Vector3(-0.6, 2.42, 0.08), mat("rusty_metal", 1.0, Color(0.5, 0.4, 0.32)), n)
	var tools := [["sledgehammer_01", -1.6, 1.85, 1.0], ["pipe_wrench", -1.05, 1.95, 1.3], ["cross_pein_hammer", -0.6, 2.0, 1.5],
		["rusted_hacksaw", -0.05, 1.95, 1.1], ["cross_pein_hammer", 0.35, 1.95, 1.4], ["pipe_wrench", 0.62, 1.85, 1.2]]
	for t in tools:
		var p := prop(t[0], Vector3(t[1], t[2], 0.12), 0.0, t[3], n)
		if p:
			p.rotation_degrees = Vector3(90.0, 0.0, randf_range(-12.0, 12.0)) if t[0] == "rusted_hacksaw" else Vector3(0.0, 0.0, randf_range(-14.0, 14.0))
			if t[0] == "sledgehammer_01":
				p.position.y = 1.55
	var bench := Node3D.new()
	n.add_child(bench)
	bench.position = Vector3(1.6, 0, 0.45)
	var wood := mat("worn_planks", 1.2, Color(0.62, 0.55, 0.46))
	var steel := mat("rusty_metal_02", 1.4)
	box(Vector3(1.5, 0.07, 0.7), Vector3(0, 0.88, 0), wood, bench)
	for x in [-0.68, 0.68]:
		for z in [-0.3, 0.3]:
			box(Vector3(0.06, 0.88, 0.06), Vector3(x, 0.44, z), steel, bench)
	box(Vector3(1.4, 0.04, 0.6), Vector3(0, 0.25, 0), steel, bench)
	prop("bench_vice_01", Vector3(-0.45, 0.915, 0.1), 180.0, 1.4, bench)
	var hm := prop("cross_pein_hammer", Vector3(0.2, 0.93, 0.05), 0.0, 1.4, bench)
	if hm:
		hm.rotation_degrees = Vector3(90.0, 0.0, 60.0)
	var wr := prop("pipe_wrench", Vector3(0.45, 0.93, -0.12), 0.0, 1.2, bench)
	if wr:
		wr.rotation_degrees = Vector3(90.0, 0.0, -30.0)
	prop("metal_toolbox", Vector3(0.1, 0.25, 0.0), 10.0, 1.1, bench)
	for k in 3:
		var chunk := MeshInstance3D.new()
		chunk.mesh = _cell_mesh
		chunk.material_override = _stone_mats[k]
		bench.add_child(chunk)
		chunk.position = Vector3(0.2 + 0.15 * float(k), 0.98, 0.18)
		chunk.rotation_degrees = Vector3(0, randf() * 90.0, 0)
	var sl := prop("sledgehammer_01", Vector3(1.05, 0.0, 0.05), 0.0, 1.0, n)
	if sl:
		sl.rotation_degrees = Vector3(-14.0, 0.0, 8.0)
		sl.position.y = 0.72

func _rubble(room: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var piles := [Vector3(-4.6, 0, -4.4), Vector3(4.7, 0, 4.0), Vector3(-4.2, 0, 4.6), Vector3(4.4, 0, -4.2), Vector3(0.0, 0, -5.2), Vector3(-5.2, 0, 1.2)]
	for p in piles:
		for i in 5:
			var r := prop("rock_07", p + Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5)), rng.randf() * 360.0, rng.randf_range(0.6, 1.6), room)
			if r:
				r.rotation_degrees.x = rng.randf_range(-20.0, 20.0)
		for i in 9:
			var chunk := MeshInstance3D.new()
			chunk.mesh = _cell_mesh
			chunk.material_override = _stone_mats[i % 4]
			room.add_child(chunk)
			var sc := rng.randf_range(0.5, 1.1)
			chunk.scale = Vector3.ONE * sc
			chunk.position = p + Vector3(rng.randf_range(-0.8, 0.8), CELL_SIZE * 0.5 * sc, rng.randf_range(-0.8, 0.8))
			chunk.rotation = Vector3(0, rng.randf() * TAU, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var grit := BoxMesh.new()
	grit.size = Vector3(0.03, 0.02, 0.025)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.34, 0.31)
	gm.roughness = 0.95
	grit.material = gm
	mm.mesh = grit
	mm.instance_count = 320
	for i in 320:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.2, 5.8)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.5, 2.0))
		mm.set_instance_transform(i, Transform3D(b, Vector3(cos(a) * r, 0.01, sin(a) * r)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	room.add_child(mi)

func _dust_motes(room: Node3D) -> void:
	var gp := GPUParticles3D.new()
	gp.amount = 160
	gp.lifetime = 9.0
	gp.preprocess = 9.0
	gp.visibility_aabb = AABB(Vector3(-7, -1, -7), Vector3(14, 6, 14))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(5.5, 1.6, 5.5)
	pm.direction = Vector3(0.3, 0.1, 0.2)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.gravity = Vector3(0, -0.01, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.3
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	pm.color = Color(0.9, 0.85, 0.72, 0.35)
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.02)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft
	q.material = m
	gp.draw_pass_1 = q
	room.add_child(gp)
	gp.position = Vector3(0, 1.8, 0)

func _build_hub() -> void:
	var hub := Node3D.new()
	hub.name = "Hub"
	world.add_child(hub)
	var body_m := mat("rusty_metal", 1.0, Color(0.62, 0.56, 0.5))
	var trim := mat("green_metal_rust", 1.0, Color(0.5, 0.5, 0.45))
	_cyl(0.78, 0.86, 0.95, Vector3(0, 0.475, 0), body_m, hub)
	_cyl(0.84, 0.84, 0.08, Vector3(0, 0.99, 0), trim, hub)
	_cyl(0.5, 0.62, 0.22, Vector3(0, 1.14, 0), body_m, hub)
	_cyl(0.18, 0.24, 0.16, Vector3(0, 1.32, 0), trim, hub)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.15
	lm.bottom_radius = 0.15
	lm.height = 0.03
	lens.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.1, 0.3, 0.15)
	lmat.emission_enabled = true
	lmat.emission = Color(0.3, 1.0, 0.45)
	lmat.emission_energy_multiplier = 2.5
	lens.material_override = lmat
	hub.add_child(lens)
	lens.position = Vector3(0, 1.41, 0)
	for k in 8:
		var a := TAU * float(k) / 8.0
		var rib := box(Vector3(0.08, 0.9, 0.05), Vector3(cos(a) * 0.8, 0.47, sin(a) * 0.8), trim, hub)
		rib.rotation.y = -a
	_projector = OmniLight3D.new()
	_projector.light_color = Color(0.3, 1.0, 0.45)
	_projector.light_energy = 0.0
	_projector.omni_range = 4.0
	hub.add_child(_projector)
	_projector.position = Vector3(0, 1.8, 0)
	_big_holo = Node3D.new()
	hub.add_child(_big_holo)
	_big_holo.position = Vector3(0, 1.62, 0)
	_big_holo.scale = Vector3.ONE * 2.6
	for i in 27:
		var c := MeshInstance3D.new()
		c.mesh = _cell_mesh
		c.material_override = _holo_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_big_holo.add_child(c)
		c.position = _cell_pos(i) - Vector3(0, CELL * 1.5, 0)
		_big_cells.append(c)
	_big_holo.visible = false
	var mq := Node3D.new()
	mq.name = "Marquee"
	world.add_child(mq)
	mq.position = Vector3(0, 2.62, 0)
	var shell := mat("rusty_metal", 1.2, Color(0.3, 0.27, 0.24))
	var wq: float = 2.1
	for k in 4:
		var face := Node3D.new()
		mq.add_child(face)
		face.rotation.y = float(k) * PI * 0.5
		box(Vector3(wq + 0.12, 0.5, 0.12), Vector3(0, 0, wq * 0.5), shell, face)
		var screen := box(Vector3(wq - 0.06, 0.36, 0.02), Vector3(0, 0, wq * 0.5 + 0.065), null, face)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.05, 0.02, 0.02)
		sm.roughness = 0.4
		sm.emission_enabled = true
		sm.emission = Color(0.25, 0.02, 0.03)
		sm.emission_energy_multiplier = 0.4
		screen.material_override = sm
		var l := Label3D.new()
		l.font = _led_font
		l.font_size = 72
		l.pixel_size = 0.0034
		l.outline_size = 0
		l.modulate = Color(2.2, 0.35, 0.45)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		face.add_child(l)
		l.position = Vector3(0, -0.01, wq * 0.5 + 0.08)
		_marquee.append(l)
	box(Vector3(wq + 0.2, 0.06, wq + 0.2), Vector3(0, 0.28, 0), shell, mq)
	box(Vector3(wq + 0.2, 0.06, wq + 0.2), Vector3(0, -0.28, 0), shell, mq)
	for c in [Vector3(-0.8, 0, -0.8), Vector3(0.8, 0, -0.8), Vector3(-0.8, 0, 0.8), Vector3(0.8, 0, 0.8)]:
		_cyl(0.025, 0.025, CEIL - 2.62, c + Vector3(0, (CEIL - 2.62) * 0.5, 0), shell, mq)
	var red := OmniLight3D.new()
	red.light_color = Color(1.0, 0.18, 0.2)
	red.light_energy = 1.4
	red.omni_range = 3.4
	mq.add_child(red)
	red.position = Vector3(0, -0.5, 0)

func _cyl(r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 28
	mi.mesh = cm
	mi.material_override = m
	parent.add_child(mi)
	mi.position = pos
	return mi

func _chamfer_cube(h: float, b: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := h - b
	for a in 3:
		for sg in [-1.0, 1.0]:
			var u := (a + 1) % 3
			var v := (a + 2) % 3
			var pts: Array[Vector3] = []
			for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[a] = sg * h
				p[u] = q.x * k
				p[v] = q.y * k
				pts.append(p)
			var n := Vector3.ZERO
			n[a] = sg
			_poly(st, pts, n)
	for a1 in 3:
		for a2 in range(a1 + 1, 3):
			var a3 := 3 - a1 - a2
			for s1 in [-1.0, 1.0]:
				for s2 in [-1.0, 1.0]:
					var pts: Array[Vector3] = []
					for e in [[h, k, -k], [h, k, k], [k, h, k], [k, h, -k]]:
						var p := Vector3.ZERO
						p[a1] = s1 * float(e[0])
						p[a2] = s2 * float(e[1])
						p[a3] = float(e[2])
						pts.append(p)
					var n := Vector3.ZERO
					n[a1] = s1
					n[a2] = s2
					_poly(st, pts, n.normalized())
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var pts: Array[Vector3] = [Vector3(sx * h, sy * k, sz * k), Vector3(sx * k, sy * h, sz * k), Vector3(sx * k, sy * k, sz * h)]
				_poly(st, pts, Vector3(sx, sy, sz).normalized())
	return st.commit()

func _poly(st: SurfaceTool, pts: Array[Vector3], n: Vector3) -> void:
	for i in range(1, pts.size() - 1):
		for p in [pts[0], pts[i], pts[i + 1]]:
			st.set_normal(n)
			st.add_vertex(p)

func _cell_pos(i: int) -> Vector3:
	var x := i % 3
	var y := (i / 3) % 3
	var z := i / 9
	return Vector3(float(x - 1) * CELL, CELL * 0.5 + float(y) * CELL, float(z - 1) * CELL)

func _place_stations() -> void:
	var ids: Array = NetworkManager.players.keys()
	var n: int = ids.size()
	var r: float = 2.5 + 0.17 * float(n)
	var off: float = 0.0
	if ids.has(_me):
		off = -TAU * float(ids.find(_me)) / float(maxi(n, 1))
	for i in n:
		var id: int = ids[i]
		var info: Dictionary = NetworkManager.players[id]
		var a: float = TAU * float(i) / float(maxi(n, 1)) + off
		var st := Node3D.new()
		world.add_child(st)
		st.position = Vector3(sin(a) * r, 0.0, cos(a) * r)
		st.rotation.y = a
		var s := _build_station(st, id, info)
		stations[id] = s
		removed[id] = 0
		submitted[id] = false
		submit_t[id] = 99.0
		total[id] = 0.0
		errs[id] = 0
		if info.is_bot or (_autotest and NetworkManager.is_server()):
			_bot[id] = {"err": randf_range(0.03, 0.15), "plan": [], "next": 0.0, "done": false}

func _build_station(st: Node3D, id: int, info: Dictionary) -> Dictionary:
	var panel := mat("dirty_concrete", 1.1, Color(0.8, 0.77, 0.7))
	var metal := mat("rusty_metal_02", 1.4, Color(0.7, 0.66, 0.6))
	var dark := mat("rusty_metal", 1.6, Color(0.16, 0.15, 0.14))
	box(Vector3(1.34, 0.9, 0.72), Vector3(0, 0.45, 0), panel, st)
	box(Vector3(1.4, 0.06, 0.78), Vector3(0, 0.93, 0), metal, st)
	box(Vector3(1.36, 0.12, 0.05), Vector3(0, 0.16, 0.37), dark, st)
	for x in [-0.5, -0.17, 0.17, 0.5]:
		var vent := box(Vector3(0.22, 0.1, 0.02), Vector3(x, 0.5, 0.365), dark, st)
		vent.name = "Vent"
	box(Vector3(0.3, 0.52, 0.04), Vector3(-0.42, 0.55, 0.37), mat("rusty_metal", 1.2, Color(0.45, 0.4, 0.35)), st)
	_cyl(0.27, 0.27, 0.04, Vector3(0, 0.98, 0), dark, st)
	var turn := Node3D.new()
	st.add_child(turn)
	turn.position = Vector3(0, TOP_Y, 0)
	_cyl(0.25, 0.25, 0.02, Vector3(0, -0.01, 0), metal, turn)
	var cells: Array[MeshInstance3D] = []
	var holo_cells: Array[MeshInstance3D] = []
	var holo := Node3D.new()
	turn.add_child(holo)
	holo.visible = false
	for i in 27:
		var c := MeshInstance3D.new()
		c.mesh = _cell_mesh
		c.material_override = _stone_mats[(i * 7 + absi(id)) % 4]
		turn.add_child(c)
		c.position = _cell_pos(i)
		c.rotation_degrees = Vector3(0, float((i * 5) % 4) * 90.0, 0)
		cells.append(c)
		var h := MeshInstance3D.new()
		h.mesh = _cell_mesh
		h.material_override = _holo_mat
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holo.add_child(h)
		h.position = _cell_pos(i)
		h.visible = false
		holo_cells.append(h)
	var btn_s := _button(st, Vector3(-0.44, 0.985, 0.16), "SUBMIT")
	var btn_r := _button(st, Vector3(0.44, 0.985, 0.16), "RESET")
	var lcd := _led_box(st, Vector3(-0.44, 1.07, -0.16), "00:00")
	var status := _led_box(st, Vector3(0.44, 1.07, -0.16), "- ---")
	var bulb := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.03
	bm.height = 0.04
	bulb.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.3, 0.05, 0.03)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.2, 0.1)
	bmat.emission_energy_multiplier = 1.5
	bulb.material_override = bmat
	st.add_child(bulb)
	bulb.position = Vector3(0, 0.97, 0.33)
	for side in [-1.0, 1.0]:
		_cable(st, Vector3(side * 0.3, 0.04, -0.36), side)
	var body := LabCharacter.new()
	body.sex = info.get("sex", "male")
	body.hat = info.get("hat", "hardhat")
	body.suit_color = info.color
	st.add_child(body)
	body.position = Vector3(0, 0, SUBJECT_Z)
	body.rotation.y = PI
	body.play_loop("Idle")
	body.anim.seek(randf() * 2.0, true)
	var ik_l := ArmIK.new()
	body.skeleton.add_child(ik_l)
	ik_l.setup(body.skeleton, "l", Vector3(0.9, -0.9, -0.5))
	var ik_r := ArmIK.new()
	body.skeleton.add_child(ik_r)
	ik_r.setup(body.skeleton, "r", Vector3(-1.0, -0.3, -0.4))
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	body.skeleton.add_child(att)
	var hammer := prop("cross_pein_hammer", Vector3.ZERO, 0.0, 1.0, att)
	if hammer:
		hammer.transform = Transform3D(Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)) * Basis.from_scale(Vector3.ONE * 1.5), Vector3(0.0, 0.08, 0.06))
	var chisel := _make_chisel()
	turn.add_child(chisel)
	var name_l := Label3D.new()
	name_l.text = info.name + ("  (YOU)" if id == _me else "")
	name_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_l.no_depth_test = true
	name_l.pixel_size = 0.0009
	name_l.fixed_size = true
	name_l.font_size = 24
	name_l.outline_size = 10
	name_l.modulate = info.color.lightened(0.35)
	name_l.render_priority = 3
	st.add_child(name_l)
	name_l.position = Vector3(0, 2.12, SUBJECT_Z)
	var score_l := Label3D.new()
	score_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	score_l.no_depth_test = true
	score_l.pixel_size = 0.0009
	score_l.fixed_size = true
	score_l.font_size = 34
	score_l.outline_size = 12
	score_l.render_priority = 4
	score_l.visible = false
	st.add_child(score_l)
	score_l.position = Vector3(0, 2.26, SUBJECT_Z)
	var press := Node3D.new()
	st.add_child(press)
	press.position = Vector3(0, PRESS_UP, SUBJECT_Z + 0.06)
	var plate_m := mat("rusty_metal", 1.0, Color(0.55, 0.45, 0.38))
	box(Vector3(0.95, 0.2, 0.62), Vector3(0, 0, 0), plate_m, press)
	box(Vector3(0.99, 0.06, 0.66), Vector3(0, -0.12, 0), _hazard_mat(), press)
	for x in [-0.3, 0.3]:
		_cyl(0.05, 0.05, 3.6, Vector3(x, 1.9, 0), mat("rusty_metal_02", 2.0, Color(0.8, 0.78, 0.74)), press)
	if id != _me:
		prop("hanging_industrial_lamp", Vector3(0, CEIL, 0.25), 0.0, 0.75, st)
	var sp := SpotLight3D.new()
	sp.light_color = Color(1.0, 0.8, 0.55)
	sp.light_energy = 6.0
	sp.spot_range = 4.5
	sp.spot_angle = 50.0
	sp.spot_attenuation = 0.7
	sp.shadow_enabled = true
	st.add_child(sp)
	sp.position = Vector3(0, 2.85, 0.25)
	sp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	return {"node": st, "body": body, "ik_l": ik_l, "ik_r": ik_r, "turn": turn, "cells": cells, "holo": holo, "holo_cells": holo_cells,
		"chisel": chisel, "hammer": hammer, "lcd": lcd, "status": status, "submit": btn_s, "reset": btn_r, "bulb": bmat,
		"name": name_l, "score": score_l, "press": press, "swing": 0.0, "work": 22, "yaw": 0.0, "yaw_goal": 0.0, "crush": false, "debris": []}

func _button(st: Node3D, at: Vector3, text: String) -> MeshInstance3D:
	box(Vector3(0.36, 0.05, 0.2), at + Vector3(0, -0.02, 0), mat("rusty_metal", 1.5, Color(0.12, 0.11, 0.1)), st)
	var b := box(Vector3(0.32, 0.05, 0.16), at + Vector3(0, 0.015, 0), mat("grey_plaster_03", 3.0, Color(1.0, 0.97, 0.88)), st)
	var l := Label3D.new()
	l.text = text
	l.font = _led_font
	l.font_size = 64
	l.pixel_size = 0.0011
	l.outline_size = 0
	l.modulate = Color(0.08, 0.07, 0.06)
	l.shaded = true
	b.add_child(l)
	l.position = Vector3(0, 0.026, 0.0)
	l.rotation_degrees.x = -90.0
	b.set_meta("rest", b.position)
	return b

func _led_box(st: Node3D, at: Vector3, text: String) -> Label3D:
	var n := Node3D.new()
	st.add_child(n)
	n.position = at
	n.rotation_degrees.x = -22.0
	box(Vector3(0.36, 0.15, 0.1), Vector3.ZERO, mat("rusty_metal", 1.5, Color(0.2, 0.19, 0.18)), n)
	var glass := box(Vector3(0.31, 0.1, 0.01), Vector3(0, 0, 0.05), null, n)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.03, 0.01, 0.01)
	gm.roughness = 0.2
	glass.material_override = gm
	var l := Label3D.new()
	l.text = text
	l.font = _led_font
	l.font_size = 64
	l.pixel_size = 0.0012
	l.outline_size = 0
	l.modulate = Color(2.0, 0.12, 0.1)
	n.add_child(l)
	l.position = Vector3(0, 0, 0.057)
	return l

func _cable(st: Node3D, from: Vector3, side: float) -> void:
	var m := mat("rubber_tiles", 2.0, Color(0.12, 0.12, 0.12))
	var pts: Array[Vector3] = []
	var to := Vector3(side * 0.18, 0.04, -st.position.length() + 0.95)
	for k in 9:
		var t := float(k) / 8.0
		var p := from.lerp(to, t)
		p.x += sin(t * PI * 2.0 + side) * 0.12
		pts.append(p)
	for k in 8:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.035
		cm.height = a.distance_to(b) + 0.03
		cm.radial_segments = 8
		seg.mesh = cm
		seg.material_override = m
		st.add_child(seg)
		seg.position = (a + b) * 0.5
		seg.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))

func _make_chisel() -> Node3D:
	var n := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.42, 0.4)
	steel.metallic = 0.8
	steel.roughness = 0.45
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.011
	cm.bottom_radius = 0.009
	cm.height = 0.17
	cm.radial_segments = 8
	shaft.mesh = cm
	shaft.material_override = steel
	n.add_child(shaft)
	shaft.position.y = 0.11
	var tip := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.026, 0.03, 0.006)
	tip.mesh = tm
	tip.material_override = steel
	n.add_child(tip)
	tip.position.y = 0.015
	var cap := MeshInstance3D.new()
	var cp := CylinderMesh.new()
	cp.top_radius = 0.014
	cp.bottom_radius = 0.012
	cp.height = 0.02
	cap.mesh = cp
	cap.material_override = mat("rusty_metal", 4.0, Color(0.5, 0.4, 0.3))
	n.add_child(cap)
	cap.position.y = 0.2
	return n

func _hazard_mat() -> StandardMaterial3D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var stripe := int(floor(float(x + y) / 8.0)) % 2
			img.set_pixel(x, y, Color(0.78, 0.58, 0.08) if stripe == 0 else Color(0.06, 0.06, 0.05))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.0
	return m

func _build_foreman() -> void:
	_foreman = LabCharacter.new()
	_foreman.sex = "male"
	_foreman.hat = "tophat"
	_foreman.suit_color = Color(0.3, 0.3, 0.31)
	world.add_child(_foreman)
	var n: int = maxi(stations.size(), 1)
	var a: float = PI / float(n) + PI
	_foreman_home = Vector3(sin(a) * 1.25, 0.0, cos(a) * 1.25)
	_foreman.position = _foreman_home
	_foreman.rotation.y = atan2(_foreman_home.x, _foreman_home.z)
	_foreman.play_loop("Idle_FoldArms")
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	_foreman.skeleton.add_child(att)
	var sl := prop("sledgehammer_01", Vector3.ZERO, 0.0, 1.0, att)
	if sl:
		sl.transform = Transform3D(Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)), Vector3(0.0, 0.08, 0.0))
		_foreman.set_meta("sledge", sl)
	var tag := Label3D.new()
	tag.text = "FOREMAN"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.0008
	tag.fixed_size = true
	tag.font_size = 20
	tag.outline_size = 8
	tag.modulate = Color(0.75, 0.75, 0.72)
	_foreman.add_child(tag)
	tag.position = Vector3(0, 2.1, 0)

func _setup_first_person() -> void:
	var s: Dictionary = stations[_me]
	var st: Node3D = s.node
	(s.body as LabCharacter).visible = false
	(s.chisel as Node3D).visible = false
	camera.fov = 72.0
	var eye := st.global_transform * Vector3(0.0, 1.98, 1.2)
	var look := st.global_transform * Vector3(0.0, 0.9, -1.6)
	camera.position = eye
	camera.look_at(look, Vector3.UP)
	_cam_base = camera.global_transform
	_vm = Node3D.new()
	camera.add_child(_vm)
	_vm.position = Vector3(0.4, -0.3, -0.52)
	_vm.rotation_degrees = Vector3(12.0, -14.0, 16.0)
	_vm_hammer = Node3D.new()
	_vm.add_child(_vm_hammer)
	var hm := prop("cross_pein_hammer", Vector3.ZERO, 0.0, 1.0, _vm_hammer)
	if hm:
		hm.scale = Vector3.ONE * 1.7
		hm.rotation_degrees = Vector3(0, 15.0, 0)
		hm.position = Vector3(0, 0.14, 0)
	var glove := mat("dirty_carpet", 6.0, Color(0.42, 0.3, 0.2))
	var fist := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.045
	cap.height = 0.16
	fist.mesh = cap
	fist.material_override = glove
	_vm_hammer.add_child(fist)
	fist.rotation_degrees = Vector3(0, 0, 90.0)
	var info: Dictionary = NetworkManager.players[_me]
	var sleeve := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.052
	sm.bottom_radius = 0.07
	sm.height = 0.5
	sleeve.mesh = sm
	var sleeve_m := StandardMaterial3D.new()
	sleeve_m.albedo_color = (info.color as Color).darkened(0.2)
	sleeve_m.roughness = 0.9
	sleeve.material_override = sleeve_m
	_vm_hammer.add_child(sleeve)
	sleeve.position = Vector3(0.24, -0.08, 0.06)
	sleeve.rotation_degrees = Vector3(10.0, 0, 75.0)

func _setup_overview() -> void:
	camera.fov = 60.0
	var r: float = 2.5 + 0.17 * float(stations.size())
	var a: float = PI / float(maxi(stations.size(), 1))
	camera.position = Vector3(sin(a) * (r + 2.2), 3.4, cos(a) * (r + 2.2))
	camera.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)
	_cam_base = camera.global_transform

func _build_hud() -> void:
	hud_title("CHISEL GAUNTLET  ·  memorize the shape, carve it, submit")
	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-240, 10)
	_timer_label.size = Vector2(220, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.add_theme_font_size_override("font_size", 26)
	_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_timer_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_timer_label)
	_round_label = Label.new()
	_round_label.position = Vector2(16, 40)
	_round_label.add_theme_font_size_override("font_size", 18)
	_round_label.add_theme_color_override("font_color", Color("e8e2c8"))
	_round_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_round_label.add_theme_constant_override("outline_size", 5)
	hud.add_child(_round_label)
	_big = _center_label(72, 0.2)
	_hint = _center_label(22, 0.9)
	if _fp:
		_hint.text = "CLICK a segment to chisel it off  ·  A / D or drag to turn the block\nSUBMIT (Space) locks it in  ·  RESET (R) restores the stone  ·  worst carver dies"
	else:
		_hint.text = "memorize the green shape  ·  carve it  ·  the worst carver of each round dies"
	_hint.add_theme_color_override("font_color", Color("e8e2c8"))

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

func _splat_tex() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.08
	for y in n:
		for x in n:
			var r := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
			var v := 1.0 - r + noise.get_noise_2d(x, y) * 0.6
			img.set_pixel(x, y, Color(1, 1, 1, clampf((v - 0.25) * 2.2, 0.0, 0.9)))
	return ImageTexture.create_from_image(img)

static func _bit(i: int) -> int:
	return 1 << i

static func _count(bits: int) -> int:
	var c := 0
	for i in 27:
		if bits & (1 << i):
			c += 1
	return c

static func _exposed(i: int, bits: int) -> bool:
	var x := i % 3
	var y := (i / 3) % 3
	var z := i / 9
	if x == 0 or x == 2 or z == 0 or z == 2 or y == 2:
		return true
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		var nz: int = z + d.z
		if nx < 0 or nx > 2 or ny < 0 or ny > 2 or nz < 0 or nz > 2:
			continue
		if bits & (1 << (nx + ny * 3 + nz * 9)):
			return true
	return false

static func _adjacent(i: int, bits: int) -> bool:
	var x := i % 3
	var y := (i / 3) % 3
	var z := i / 9
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		var nz: int = z + d.z
		if nx >= 0 and nx <= 2 and ny >= 0 and ny <= 2 and nz >= 0 and nz <= 2 and bits & (1 << (nx + ny * 3 + nz * 9)):
			return true
	return false

func _gen_target(n: int) -> int:
	var bits := 0
	for k in n:
		var cand: Array = []
		var adj: Array = []
		for i in 27:
			if bits & _bit(i) or not _exposed(i, bits):
				continue
			if i / 3 % 3 == 0 and randf() < 0.6:
				continue
			cand.append(i)
			if _adjacent(i, bits):
				adj.append(i)
		if cand.is_empty():
			break
		var pick: int = adj.pick_random() if not adj.is_empty() and randf() < 0.5 else cand.pick_random()
		bits |= _bit(pick)
	return bits

func _alive() -> Array:
	return stations.keys().filter(func(id): return not dead_order.has(id))


func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	_rpc_intro.rpc()
	await get_tree().create_timer(1.8).timeout
	for r in ROUNDS:
		if stations.size() > 1 and _alive().size() <= 1:
			break
		var t := _gen_target(REMOVE_COUNT[r] + (randi() % 2))
		_rpc_round.rpc(r, t)
		for id in _bot:
			_plan_bot(id, r, t)
		await get_tree().create_timer(MEMO_TIME).timeout
		_rpc_carve.rpc()
		_carve_t = 0.0
		_carving = true
		while _carve_t < CARVE_TIME and not _all_submitted():
			await get_tree().process_frame
		_carving = false
		for id in _alive():
			if not submitted[id]:
				submitted[id] = true
				submit_t[id] = CARVE_TIME + 1.0
		var e: Dictionary = {}
		for id in _alive():
			e[id] = _count(int(removed[id]) ^ target)
			total[id] = float(total[id]) + float(27 - int(e[id])) / 27.0
		_rpc_judge.rpc(e, removed)
		await get_tree().create_timer(JUDGE_TIME).timeout
		var victim := _pick_victim(e)
		if victim != 0:
			dead_order.append(victim)
			_rpc_execute.rpc(victim, r % 2)
			await get_tree().create_timer(EXEC_TIME).timeout
		else:
			_rpc_spared.rpc()
			await get_tree().create_timer(1.8).timeout
	_rpc_end.rpc()
	await get_tree().create_timer(2.8).timeout
	if not _ended:
		_ended = true
		finished.emit(_placement())

func _all_submitted() -> bool:
	for id in _alive():
		if not submitted[id]:
			return false
	return true

func _pick_victim(e: Dictionary) -> int:
	var worst := 0
	var best_id := 0
	for id in e:
		var v: int = e[id]
		if v > worst or (v == worst and v > 0 and (float(submit_t[id]) > float(submit_t[best_id]) or (float(submit_t[id]) == float(submit_t[best_id]) and randf() < 0.5))):
			worst = v
			best_id = id
	return best_id if worst > 0 else 0

func _placement() -> Array:
	var living: Array = _alive()
	living.sort_custom(func(a, b): return float(total[a]) > float(total[b]))
	var out: Array = living
	for i in range(dead_order.size() - 1, -1, -1):
		out.append(dead_order[i])
	return out

func _plan_bot(id: int, r: int, t: int) -> void:
	var b: Dictionary = _bot[id]
	var err: float = float(b.err) * (1.0 + 0.85 * float(r))
	var want := 0
	for i in 27:
		if (t & _bit(i)) == 0:
			continue
		if randf() < err:
			if randf() < 0.55:
				var nb: Array = []
				for j in 27:
					if (t & _bit(j)) == 0 and _adjacent(j, _bit(i)) and _exposed(j, t):
						nb.append(j)
				if not nb.is_empty():
					want |= _bit(nb.pick_random())
			continue
		want |= _bit(i)
	while randf() < err * 0.6:
		var extra: Array = []
		for j in 27:
			if ((t | want) & _bit(j)) == 0 and _exposed(j, want):
				extra.append(j)
		if extra.is_empty():
			break
		want |= _bit(extra.pick_random())
	var plan: Array = []
	var sim := 0
	while true:
		var ready: Array = []
		for i in 27:
			if want & _bit(i) and not sim & _bit(i) and _exposed(i, sim):
				ready.append(i)
		if ready.is_empty():
			break
		var p: int = ready.pick_random()
		plan.append(p)
		sim |= _bit(p)
	b.plan = plan
	b.done = false

func _server_bots(delta: float) -> void:
	_carve_t += delta
	for id in _bot:
		if dead_order.has(id) or submitted[id]:
			continue
		var b: Dictionary = _bot[id]
		if float(b.next) <= 0.0:
			b.next = _carve_t + randf_range(0.9, 1.7)
			continue
		if _carve_t < float(b.next):
			continue
		var plan: Array = b.plan
		if plan.is_empty():
			if bool(b.done):
				_try_submit(id)
			else:
				b.done = true
				b.next = _carve_t + randf_range(0.4, 1.3)
			continue
		var c: int = plan.pop_front()
		_try_carve(id, c)
		b.next = _carve_t + randf_range(0.45, 0.85) + (randf_range(0.5, 1.3) if randf() < 0.14 else 0.0)

func _try_carve(id: int, c: int) -> void:
	if phase != Ph.CARVE or not _carving or dead_order.has(id) or bool(submitted[id]) or c < 0 or c > 26:
		return
	var bits: int = removed[id]
	if bits & _bit(c) or not _exposed(c, bits):
		return
	removed[id] = bits | _bit(c)
	_rpc_carved.rpc(id, c, int(removed[id]))

func _try_reset(id: int) -> void:
	if phase != Ph.CARVE or not _carving or dead_order.has(id) or bool(submitted[id]):
		return
	removed[id] = 0
	_rpc_reset.rpc(id)

func _try_submit(id: int) -> void:
	if phase != Ph.CARVE or not _carving or dead_order.has(id) or bool(submitted[id]):
		return
	submitted[id] = true
	submit_t[id] = _carve_t
	_rpc_submitted.rpc(id)

@rpc("any_peer", "reliable")
func _rq_carve(c: int) -> void:
	if NetworkManager.is_server():
		_try_carve(multiplayer.get_remote_sender_id(), c)

@rpc("any_peer", "reliable")
func _rq_reset() -> void:
	if NetworkManager.is_server():
		_try_reset(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _rq_submit() -> void:
	if NetworkManager.is_server():
		_try_submit(multiplayer.get_remote_sender_id())

func _ask(what: String, c: int = -1) -> void:
	if NetworkManager.is_server():
		match what:
			"carve": _try_carve(_me, c)
			"reset": _try_reset(_me)
			"submit": _try_submit(_me)
	else:
		match what:
			"carve": _rq_carve.rpc_id(1, c)
			"reset": _rq_reset.rpc_id(1)
			"submit": _rq_submit.rpc_id(1)


func _process(delta: float) -> void:
	clock += delta
	if NetworkManager.is_server() and _carving:
		_server_bots(delta)
	_local_input(delta)
	_marquee_tick(delta)
	if _big_holo.visible:
		_big_holo.rotation.y += delta * 0.7
	for id in stations:
		_animate_station(id, delta)
	var left: float = maxf(0.0, phase_end - clock)
	if phase == Ph.MEMO or phase == Ph.CARVE:
		_timer_label.text = "%s  %d s" % ["MEMORIZE" if phase == Ph.MEMO else "CARVE", int(ceil(left))]
	else:
		_timer_label.text = ""
	if not _fp and camera.current:
		var sway := sin(clock * 0.21) * 0.35
		camera.global_transform = _cam_base.translated(_cam_base.basis.x * sway)
		camera.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)

func _local_input(delta: float) -> void:
	if not _fp:
		return
	var turn_in := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		turn_in -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		turn_in += 1.0
	_yaw += turn_in * delta * 2.4
	if phase == Ph.MEMO and turn_in == 0.0:
		_yaw += delta * 0.9
	for k in [KEY_SPACE, KEY_ENTER, KEY_R]:
		var down := Input.is_physical_key_pressed(k)
		if down and not bool(_keys.get(k, false)) and phase == Ph.CARVE:
			_ask("reset" if k == KEY_R else "submit")
		_keys[k] = down
	var s: Dictionary = stations[_me]
	var cells: Array[MeshInstance3D] = s.cells
	var h := -1
	if phase == Ph.CARVE and not bool(submitted[_me]) and not dead_order.has(_me):
		h = _pick_cell(get_viewport().get_mouse_position())
	if h != _hover:
		if _hover >= 0:
			cells[_hover].material_overlay = null
		if h >= 0:
			cells[h].material_overlay = _hover_mat
		_hover = h

func _unhandled_input(event: InputEvent) -> void:
	if not _fp:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_down = true
			_drag = false
			_drag_px = 0.0
		else:
			if _press_down and not _drag:
				_click(event.position)
			_press_down = false
	elif event is InputEventMouseMotion and _press_down:
		_drag_px += absf(event.relative.x) + absf(event.relative.y)
		if _drag_px > 8.0:
			_drag = true
		if _drag:
			_yaw += event.relative.x * 0.012

func _ray_local(node: Node3D, pos: Vector2) -> Array:
	var o := camera.project_ray_origin(pos)
	var d := camera.project_ray_normal(pos)
	var inv := node.global_transform.affine_inverse()
	return [inv * o, (inv.basis * d).normalized()]

static func _ray_box(o: Vector3, d: Vector3, c: Vector3, h: Vector3) -> float:
	var tmin := -INF
	var tmax := INF
	for k in 3:
		if absf(d[k]) < 0.00001:
			if o[k] < c[k] - h[k] or o[k] > c[k] + h[k]:
				return -1.0
			continue
		var t1 := (c[k] - h[k] - o[k]) / d[k]
		var t2 := (c[k] + h[k] - o[k]) / d[k]
		tmin = maxf(tmin, minf(t1, t2))
		tmax = minf(tmax, maxf(t1, t2))
	if tmax < maxf(tmin, 0.0):
		return -1.0
	return tmin

func _pick_cell(pos: Vector2) -> int:
	var s: Dictionary = stations[_me]
	var r := _ray_local(s.turn, pos)
	var bits: int = removed[_me]
	var best := -1
	var best_t := INF
	for i in 27:
		if bits & _bit(i):
			continue
		var t := _ray_box(r[0], r[1], _cell_pos(i), Vector3.ONE * CELL * 0.5)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = i
	return best

func _click(pos: Vector2) -> void:
	if phase != Ph.CARVE or dead_order.has(_me):
		return
	var s: Dictionary = stations[_me]
	for k in ["submit", "reset"]:
		var b: MeshInstance3D = s[k]
		var r := _ray_local(b, pos)
		if _ray_box(r[0], r[1], Vector3.ZERO, Vector3(0.16, 0.04, 0.08)) >= 0.0:
			_ask(k)
			return
	var c := _pick_cell(pos)
	if c >= 0 and not bool(submitted[_me]):
		_ask("carve", c)

func _marquee_tick(delta: float) -> void:
	_marquee_t += delta
	if _marquee_t < 0.13:
		return
	_marquee_t = 0.0
	_marquee_off = (_marquee_off + 1) % _marquee_text.length()
	var doubled := _marquee_text + _marquee_text + _marquee_text
	var win := doubled.substr(_marquee_off, 15)
	for l in _marquee:
		l.text = win

func _animate_station(id: int, delta: float) -> void:
	var s: Dictionary = stations[id]
	var turn: Node3D = s.turn
	var body: LabCharacter = s.body
	if id == _me and _fp:
		turn.rotation.y = _yaw
	else:
		if phase == Ph.MEMO:
			s.yaw = float(s.yaw) + delta * 0.8
		else:
			s.yaw = lerp_angle(float(s.yaw), float(s.yaw_goal), clampf(delta * 3.0, 0.0, 1.0))
		turn.rotation.y = float(s.yaw)
	var lcd: Label3D = s.lcd
	if dead_order.has(id) and phase != Ph.JUDGE:
		lcd.text = "--:--"
	elif phase == Ph.MEMO or phase == Ph.CARVE:
		lcd.text = "00:%02d" % int(ceil(maxf(0.0, phase_end - clock)))
	var bulb: StandardMaterial3D = s.bulb
	bulb.emission = Color(0.2, 1.0, 0.3) if bool(submitted.get(id, false)) else Color(1.0, 0.2, 0.1)
	bulb.emission_energy_multiplier = 1.6 if bool(submitted.get(id, false)) or fmod(clock, 0.8) < 0.4 else 0.2
	if bool(s.crush):
		var press: Node3D = s.press
		body.scale.y = minf(body.scale.y, clampf((press.position.y - 0.08) / 1.9, 0.12, 1.0))
	if body.is_dead() or not body.visible:
		return
	var sw: float = s.swing
	var chisel: Node3D = s.chisel
	var sk := body.skeleton
	var inv := sk.global_transform.affine_inverse()
	var ik_l: ArmIK = s.ik_l
	var ik_r: ArmIK = s.ik_r
	var st: Node3D = s.node
	var working := phase == Ph.CARVE and not bool(submitted.get(id, false))
	var want: float = 1.0 if working or phase == Ph.MEMO else 0.0
	ik_l.influence = move_toward(ik_l.influence, want, delta * 3.0)
	ik_r.influence = ik_l.influence
	chisel.visible = ik_l.influence > 0.3 and not (id == _me and _fp)
	var top: Vector3 = chisel.global_position + Vector3(0, 0.21, 0)
	ik_l.target = inv * (chisel.global_position + Vector3(0, 0.12, 0) + st.global_transform.basis * Vector3(0.03, 0, 0.04))
	var raised: Vector3 = top + st.global_transform.basis * Vector3(0.22, 0.34, 0.16)
	var strike: Vector3 = top + st.global_transform.basis * Vector3(0.1, 0.07, 0.1)
	ik_r.target = inv * raised.lerp(strike, sw)

func _set_work(id: int, c: int) -> void:
	var s: Dictionary = stations[id]
	s.work = c
	var chisel: Node3D = s.chisel
	var p := _cell_pos(c)
	var bits: int = removed.get(id, 0)
	var y := 2
	var col := c % 3 + (c / 9) * 9
	while y >= 0 and bits & _bit(col + y * 3):
		y -= 1
	chisel.position = Vector3(p.x, CELL * float(y + 1) - 0.01, p.z)
	chisel.rotation_degrees = Vector3(randf_range(-10.0, 10.0), randf() * 360.0, randf_range(-10.0, 10.0))

func _swing(id: int) -> void:
	var s: Dictionary = stations[id]
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: s.swing = v, 0.0, 1.0, 0.09).set_ease(Tween.EASE_IN)
	tw.tween_method(func(v: float) -> void: s.swing = v, 1.0, 0.0, 0.3).set_ease(Tween.EASE_OUT)
	var body: LabCharacter = s.body
	if not body.is_dead() and body.visible:
		body.play_action("Sword_Regular_A", 0.1, 1.5)
	if id == _me and _fp and _vm:
		var vt := create_tween()
		vt.tween_property(_vm_hammer, "rotation_degrees", Vector3(-55.0, 0.0, 10.0), 0.07)
		vt.tween_property(_vm_hammer, "rotation_degrees", Vector3.ZERO, 0.25)
		Fx.shake(0.05)


@rpc("authority", "call_local", "reliable")
func _rpc_intro() -> void:
	_show_big("CHISEL GAUNTLET", "e8e2c8", 1.6)
	_marquee_text = "CARVE.  SUBMIT.  "
	Fx.sfx("hum", null, -8.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_round(r: int, t: int) -> void:
	round_i = r
	target = t
	phase = Ph.MEMO
	phase_end = clock + MEMO_TIME
	_round_label.text = "ROUND %d / %d   ·   %d segments to remove" % [r + 1, ROUNDS, _count(t)]
	_marquee_text = "MEMORIZE.  MEMORIZE.  "
	_show_big("MEMORIZE", "7dff9a", MEMO_TIME - 0.6)
	Fx.sfx("beep", null, -4.0, 1.2)
	_projector.light_energy = 2.2
	_big_holo.visible = true
	for i in 27:
		_big_cells[i].visible = (t & _bit(i)) == 0
	for id in stations:
		removed[id] = 0
		submitted[id] = false
		var s: Dictionary = stations[id]
		var score_l: Label3D = s.score
		score_l.visible = false
		if dead_order.has(id):
			continue
		(s.status as Label3D).text = "MEMO"
		var cells: Array[MeshInstance3D] = s.cells
		var hc: Array[MeshInstance3D] = s.holo_cells
		for i in 27:
			cells[i].visible = false
			cells[i].material_overlay = null
			cells[i].scale = Vector3.ONE
			hc[i].visible = (t & _bit(i)) == 0
			hc[i].material_override = _holo_mat
		(s.holo as Node3D).visible = true
		_set_work(id, 22)

@rpc("authority", "call_local", "reliable")
func _rpc_carve() -> void:
	phase = Ph.CARVE
	phase_end = clock + CARVE_TIME
	_marquee_text = "CARVE.  SUBMIT.  "
	_show_big("CARVE!", "f0a040", 0.9)
	Fx.sfx("buzzer", null, -10.0, 1.6)
	_projector.light_energy = 0.0
	_big_holo.visible = false
	if round_i == 0:
		var th := create_tween()
		th.tween_interval(6.0)
		th.tween_property(_hint, "modulate:a", 0.0, 0.8)
	for id in stations:
		if dead_order.has(id):
			continue
		var s: Dictionary = stations[id]
		(s.holo as Node3D).visible = false
		(s.status as Label3D).text = "WORK"
		s.yaw_goal = round(float(s.yaw) / (PI * 0.5)) * PI * 0.5
		var cells: Array[MeshInstance3D] = s.cells
		for i in 27:
			cells[i].visible = true

@rpc("authority", "call_local", "reliable")
func _rpc_carved(id: int, c: int, bits: int) -> void:
	removed[id] = bits
	var s: Dictionary = stations[id]
	var cells: Array[MeshInstance3D] = s.cells
	var cell := cells[c]
	if c == _hover:
		cell.material_overlay = null
		_hover = -1
	_swing(id)
	if not (id == _me and _fp):
		_set_work(id, c)
	var delay := 0.08
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if not is_instance_valid(cell) or not (int(removed[id]) & _bit(c)):
			return
		cell.visible = false
		var at := cell.global_position
		_debris(s, cell, at)
		_dust(at)
		Fx.sfx("hit", at, -2.0 if id == _me else -8.0, randf_range(1.1, 1.4))
	)

@rpc("authority", "call_local", "reliable")
func _rpc_reset(id: int) -> void:
	removed[id] = 0
	var s: Dictionary = stations[id]
	_press_btn(s.reset)
	var cells: Array[MeshInstance3D] = s.cells
	for i in 27:
		if not cells[i].visible:
			cells[i].visible = true
			cells[i].scale = Vector3.ONE * 0.2
			var tw := cells[i].create_tween()
			tw.tween_property(cells[i], "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Fx.sfx("click", (s.node as Node3D).global_position + Vector3(0, 1, 0), -4.0, 0.7)
	Fx.sfx("whoosh", (s.node as Node3D).global_position + Vector3(0, 1, 0), -10.0, 1.6)

@rpc("authority", "call_local", "reliable")
func _rpc_submitted(id: int) -> void:
	submitted[id] = true
	var s: Dictionary = stations[id]
	_press_btn(s.submit)
	(s.status as Label3D).text = "LOCK"
	Fx.sfx("click", (s.node as Node3D).global_position + Vector3(0, 1, 0), -3.0, 1.0)
	if id == _me:
		Fx.sfx("beep", null, -6.0, 1.6)
		if _hover >= 0:
			(s.cells[_hover] as MeshInstance3D).material_overlay = null
			_hover = -1

func _press_btn(b: MeshInstance3D) -> void:
	var rest: Vector3 = b.get_meta("rest")
	var tw := b.create_tween()
	tw.tween_property(b, "position", rest - Vector3(0, 0.025, 0), 0.06)
	tw.tween_property(b, "position", rest, 0.18)

@rpc("authority", "call_local", "reliable")
func _rpc_judge(e: Dictionary, rem: Dictionary) -> void:
	phase = Ph.JUDGE
	errs = e
	_marquee_text = "JUDGEMENT.  "
	Fx.sfx("arm", null, -6.0, 0.9)
	for id in e:
		removed[id] = rem[id]
		submitted[id] = true
		var s: Dictionary = stations[id]
		var n: int = e[id]
		(s.status as Label3D).text = "ERR %d" % n
		(s.lcd as Label3D).text = "%3d%%" % int(round(100.0 * float(27 - n) / 27.0))
		var score_l: Label3D = s.score
		score_l.visible = true
		score_l.text = "PERFECT" if n == 0 else "%d ERROR%s" % [n, "" if n == 1 else "S"]
		score_l.modulate = Color("8fe36a") if n == 0 else (Color("ffb13a") if n <= 2 else Color("ff3b2e"))
		var cells: Array[MeshInstance3D] = s.cells
		var hc: Array[MeshInstance3D] = s.holo_cells
		var bits: int = rem[id]
		for i in 27:
			cells[i].material_overlay = null
			hc[i].visible = false
			var should_go: bool = (target & _bit(i)) != 0
			var gone: bool = (bits & _bit(i)) != 0
			if should_go and not gone:
				cells[i].visible = true
				cells[i].material_overlay = _wrong_mat
			elif gone and not should_go:
				hc[i].visible = true
				hc[i].material_override = _ghost_mat
		(s.holo as Node3D).visible = true
	var worst := 0
	for id in e:
		worst = maxi(worst, int(e[id]))
	if _fp and e.has(_me):
		var mine: int = e[_me]
		_show_big("PERFECT" if mine == 0 else "%d ERROR%s" % [mine, "" if mine == 1 else "S"], "8fe36a" if mine == 0 else ("ff3b2e" if mine == worst else "ffb13a"), JUDGE_TIME)
	else:
		_show_big("JUDGEMENT", "e2c84b", JUDGE_TIME - 0.4)

@rpc("authority", "call_local", "reliable")
func _rpc_spared() -> void:
	_show_big("ALL PERFECT.  NOBODY DIES.  YET.", "8fe36a", 1.6)
	Fx.sfx("win", null, -8.0)

@rpc("authority", "call_local", "reliable")
func _rpc_execute(victim: int, method: int) -> void:
	phase = Ph.EXEC
	if not dead_order.has(victim):
		dead_order.append(victim)
	_marquee_text = "EXECUTION.  "
	var s: Dictionary = stations[victim]
	var body: LabCharacter = s.body
	var st: Node3D = s.node
	body.visible = true
	(s.status as Label3D).text = "VOID"
	(s.name as Label3D).text = NetworkManager.players[victim].name + "  ·  SUBSTANDARD"
	(s.name as Label3D).modulate = Color("ff6a5a")
	(s.ik_l as ArmIK).influence = 0.0
	(s.ik_r as ArmIK).influence = 0.0
	(s.chisel as Node3D).visible = false
	_show_big("%s  WILL BE REMOVED" % String(NetworkManager.players[victim].name).to_upper(), "ff3b2e", EXEC_TIME - 1.0)
	Fx.sfx("buzzer", null, -2.0, 0.8)
	_exec_cam.global_position = st.global_transform * Vector3(-1.35, 2.55, -0.55)
	_exec_cam.look_at(st.global_transform * Vector3(0.2, 0.75, SUBJECT_Z + 0.1), Vector3.UP)
	var alarm := OmniLight3D.new()
	alarm.light_color = Color(1.0, 0.15, 0.1)
	alarm.omni_range = 3.5
	st.add_child(alarm)
	alarm.position = Vector3(-0.6, 2.4, 0.2)
	var at := alarm.create_tween().set_loops(6)
	at.tween_property(alarm, "light_energy", 3.5, 0.15)
	at.tween_property(alarm, "light_energy", 0.4, 0.35)
	get_tree().create_timer(EXEC_TIME).timeout.connect(alarm.queue_free)
	_exec_cam.make_current()
	if victim == _me and _fp:
		_fp = false
		_hover = -1
		_vm.visible = false
		_setup_overview()
	if method == 0:
		_crush(victim)
	else:
		_hammer(victim)
	get_tree().create_timer(EXEC_TIME - 0.3).timeout.connect(func() -> void:
		camera.make_current()
	)

func _crush(id: int) -> void:
	var s: Dictionary = stations[id]
	var press: Node3D = s.press
	var body: LabCharacter = s.body
	var st: Node3D = s.node
	Fx.sfx("hum", st.global_position + Vector3(0, 3, 0), 0.0, 0.6)
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_callback(func() -> void:
		s.crush = true
		body.play_action("Hit_Head", 0.1)
	)
	tw.tween_property(press, "position:y", 0.3, 0.22).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		body.die("Death01")
		var at := st.global_transform * Vector3(0, 0.3, SUBJECT_Z)
		Fx.blood(world, at, 90)
		Fx.blood(world, at + st.global_transform.basis * Vector3(0.4, 0, 0.2), 40)
		_dust(at + Vector3(0, 0.1, 0), 2.2)
		Fx.sfx("explosion", at, -4.0, 0.55)
		Fx.sfx("splat", at, 2.0, 0.8)
		Fx.shake(0.7)
	)
	tw.tween_interval(1.1)
	tw.tween_property(press, "position:y", PRESS_UP, 1.6).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: s.crush = false)

func _hammer(id: int) -> void:
	var s: Dictionary = stations[id]
	var body: LabCharacter = s.body
	var st: Node3D = s.node
	var n: int = maxi(stations.size(), 1)
	var a: float = st.rotation.y + PI / float(n)
	var a0: float = atan2(_foreman_home.x, _foreman_home.z)
	var a1: float = a0 + wrapf(a - a0, -PI, PI)
	var r1: float = st.position.length() - 0.2
	var p1 := Vector3(sin(a) * r1, 0, cos(a) * r1)
	var p2 := st.global_transform * Vector3(0.8, 0, SUBJECT_Z + 0.05)
	var orbit := func(v: float) -> void:
		var np := Vector3(sin(v) * 1.3, 0, cos(v) * 1.3)
		var d := np - _foreman.position
		if d.length() > 0.001:
			_foreman.rotation.y = atan2(d.x, d.z)
		_foreman.position = np
	var tw := create_tween()
	_foreman.play_loop("Jog_Fwd")
	tw.tween_method(orbit, a0, a1, clampf(absf(a1 - a0) * 1.3 / 3.4, 0.15, 1.0))
	tw.tween_callback(func() -> void: _foreman.rotation.y = atan2(p1.x - _foreman.position.x, p1.z - _foreman.position.z))
	tw.tween_property(_foreman, "position", p1, clampf((r1 - 1.3) / 3.4, 0.2, 1.0))
	tw.tween_callback(func() -> void: _foreman.rotation.y = atan2(p2.x - p1.x, p2.z - p1.z))
	tw.tween_property(_foreman, "position", p2, clampf(p1.distance_to(p2) / 3.4, 0.15, 0.8))
	tw.tween_callback(func() -> void:
		var to := body.global_position - _foreman.position
		_foreman.rotation.y = atan2(to.x, to.z)
		_foreman.play_action("Sword_Regular_A", 0.05, 0.9)
		body.play_action("Idle_No", 0.1)
	)
	tw.tween_interval(0.3)
	tw.tween_callback(func() -> void:
		body.die("Death01")
		var head := body.global_position + Vector3(0, 1.55, 0)
		Fx.blood(world, head, 90)
		_dust(head, 0.8)
		Fx.sfx("hit", head, 4.0, 0.5)
		Fx.sfx("splat", head, 0.0, 0.9)
		Fx.shake(0.6)
	)
	tw.tween_interval(1.0)
	tw.tween_callback(func() -> void:
		_foreman.play_loop("Walk")
		_foreman.rotation.y = atan2(p1.x - p2.x, p1.z - p2.z)
	)
	tw.tween_property(_foreman, "position", p1, 0.5)
	tw.tween_property(_foreman, "position", Vector3(sin(a) * 1.3, 0, cos(a) * 1.3), 0.7)
	tw.tween_method(orbit, a1, a0, clampf(absf(a1 - a0) * 1.3 / 2.0, 0.15, 1.4))
	tw.tween_callback(func() -> void:
		_foreman.rotation.y = a0
		_foreman.play_loop("Idle_FoldArms")
	)

@rpc("authority", "call_local", "reliable")
func _rpc_end() -> void:
	phase = Ph.DONE
	_marquee_text = "TEST COMPLETE.  "
	_show_big("TEST COMPLETE", "e2c84b", 2.4)
	Fx.sfx("buzzer", null, -6.0, 1.3)

func _show_big(text: String, hex: String, hold: float) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", Color(hex))
	_big.modulate.a = 1.0
	var tw := _big.create_tween()
	tw.tween_interval(hold)
	tw.tween_property(_big, "modulate:a", 0.0, 0.4)


func _debris(s: Dictionary, cell: MeshInstance3D, at: Vector3) -> void:
	var st: Node3D = s.node
	var d := MeshInstance3D.new()
	d.mesh = _cell_mesh
	d.material_override = cell.material_override
	world.add_child(d)
	d.global_transform = cell.global_transform
	var out: Vector3 = (at - (s.turn as Node3D).global_position)
	out.y = 0.0
	if out.length() < 0.01:
		out = st.global_transform.basis * Vector3(1, 0, 0)
	out = out.normalized()
	var side := st.global_transform.basis * Vector3(1.0 if randf() < 0.5 else -1.0, 0, 0)
	var land := at + out * randf_range(0.15, 0.3) + side * randf_range(0.6, 0.85)
	land.y = CELL_SIZE * 0.35
	var peak := at.lerp(land, 0.3) + Vector3(0, 0.25, 0)
	var tw := d.create_tween()
	tw.tween_property(d, "global_position", peak, 0.16).set_ease(Tween.EASE_OUT)
	tw.tween_property(d, "global_position", land, 0.32).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(d, "rotation", Vector3(randf_range(-2, 2), randf_range(-3, 3), randf_range(-2, 2)), 0.48)
	tw.parallel().tween_property(d, "scale", Vector3.ONE * 0.7, 0.48)
	var list: Array = s.debris
	list.append(d)
	if list.size() > 30:
		var old: Node3D = list.pop_front()
		if is_instance_valid(old):
			old.queue_free()

func _dust(at: Vector3, power: float = 1.0) -> void:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.amount = int(10 * power)
	gp.lifetime = 1.6
	gp.explosiveness = 0.9
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.7 * power
	pm.gravity = Vector3(0, -0.15, 0)
	pm.damping_min = 0.8
	pm.damping_max = 1.6
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(0.78, 0.75, 0.7, 0.28))
	g.set_color(1, Color(0.7, 0.66, 0.6, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09) * power
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft
	q.material = m
	gp.draw_pass_1 = q
	world.add_child(gp)
	gp.global_position = at
	gp.emitting = true
	get_tree().create_timer(2.0).timeout.connect(gp.queue_free)
	var chips := GPUParticles3D.new()
	chips.one_shot = true
	chips.amount = int(14 * power)
	chips.lifetime = 0.9
	chips.explosiveness = 1.0
	chips.local_coords = false
	var cm := ParticleProcessMaterial.new()
	cm.direction = Vector3.UP
	cm.spread = 70.0
	cm.initial_velocity_min = 0.6
	cm.initial_velocity_max = 1.8 * power
	cm.gravity = Vector3(0, -9.8, 0)
	cm.scale_min = 0.5
	cm.scale_max = 1.3
	chips.process_material = cm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.016, 0.012, 0.014)
	bm.material = _stone_mats[2]
	chips.draw_pass_1 = bm
	world.add_child(chips)
	chips.global_position = at
	chips.emitting = true
	get_tree().create_timer(1.4).timeout.connect(chips.queue_free)
