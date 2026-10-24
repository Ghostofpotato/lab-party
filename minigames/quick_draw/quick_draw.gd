extends ArenaMinigame3D
## Quick Draw: subjects stand in a horseshoe around a steel table in a grim
## interrogation room, pistols holstered. The wall lamp says WAIT (red) for 2 to 5 s,
## sometimes flickering amber as a fake-out, then DRAW (green): press SPACE as fast
## as you can. Pressing early is a false start and the supervisor shoots you.
## The fastest draw shoots the slowest living subject. Up to 5 rounds or one left.
## Survivors rank by average reaction time, the dead rank in reverse order of death.

const ROUNDS: int = 5
const TIME_LIMIT: float = 62.0
const WAIT_MIN: float = 2.0
const WAIT_MAX: float = 5.0
const DRAW_WINDOW: float = 1.35
const DNF_MS: float = 1500.0
const RING_R: float = 2.2
const X0: float = -6.5
const X1: float = 6.5
const Z0: float = -5.4
const Z1: float = 7.0
const CEIL: float = 4.4
const MUZZLE := Vector3(0.18, 0.0, 0.0)
const BOARD_Z: float = Z0 + 0.14

enum St { COUNTDOWN, BETWEEN, WAIT, DRAW, RESOLVE, DONE }

class ArmPose extends SkeletonModifier3D:
	var poses: Dictionary = {}
	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for bi in poses:
			sk.set_bone_pose_rotation(bi, poses[bi])

var st: St = St.COUNTDOWN
var clock: float = 0.0
var round_no: int = 0
var subjects: Dictionary = {}
var dead_order: Array = []
var _times: Dictionary = {}
var _fs_done: Dictionary = {}
var _sum_ms: Dictionary = {}
var _cnt: Dictionary = {}
var _bot: Dictionary = {}
var _bot_plan: Dictionary = {}
var _sup_queue: Array = []
var _sup_busy: bool = false
var _draw_tick: int = 0
var _drew_local: bool = false
var _space_down: bool = false
var _ended: bool = false
var _cam_mode: int = 0
var _cam_t: float = 0.0
var _orbit_dir: float = 1.0
var _look: Vector3 = Vector3(0.0, 1.4, -0.8)
var _focus: Vector3 = Vector3.ZERO
var _wide_dir: float = 1.0
var _gun_hand_xf: Transform3D
var _gun_holster_xf: Transform3D
var _splat: ImageTexture
var _soft: Texture2D
var _red_mat: StandardMaterial3D
var _green_mat: StandardMaterial3D
var _led: Label3D
var _wash: OmniLight3D
var _lamp_pivot: Node3D
var _lamp_spot: SpotLight3D
var _clock_hand: Node3D
var _last_tick: int = -1
var _rec_mat: StandardMaterial3D
var _sup: LabCharacter
var _sup_mod: ArmPose
var _sup_gun: Node3D
var _big: Label
var _hint: Label
var _round_label: Label
var _flash: ColorRect
var _big_tw: Tween

func begin() -> void:
	setup_arena(false)
	_tune_light()
	_soft = _soft_tex()
	_splat = _splat_tex()
	var gb := Basis(Vector3(0.03, 0.97, -0.24), Vector3(-0.03, 0.24, 0.97), Vector3(1.0, -0.02, 0.03)).orthonormalized()
	_gun_hand_xf = Transform3D(gb * Basis.from_scale(Vector3.ONE * 1.9), Vector3(0.0, 0.068, 0.015))
	var hb := Basis(Vector3(0.0, -1.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0))
	_gun_holster_xf = Transform3D(hb * Basis.from_scale(Vector3.ONE * 1.7), Vector3(0.0, 0.04, 0.0))
	_build_room()
	_build_board()
	_build_table()
	_build_dressing()
	_build_observers()
	_build_dust()
	_line_up()
	_spawn_supervisor()
	camera.fov = 52.0
	_update_camera(0.0)
	_set_signal(0)
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.06
			n.shadow_enabled = false
	env.ambient_light_energy = 0.55
	env.ambient_light_color = Color(0.6, 0.58, 0.5)
	env.fog_density = 0.03
	env.fog_light_color = Color(0.2, 0.19, 0.16)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.03
	env.volumetric_fog_albedo = Color(0.72, 0.7, 0.64)
	env.volumetric_fog_length = 14.0
	env.ssao_radius = 0.8
	env.glow_intensity = 0.8

func _omni(pos: Vector3, color: Color, energy: float, rng: float, parent: Node = null) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng
	(parent if parent else world).add_child(o)
	o.position = pos
	return o

func _pipe(a: Vector3, b: Vector3, radius: float, material: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = a.distance_to(b)
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	parent.add_child(mi)
	mi.position = (a + b) * 0.5
	mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	return mi

func _wall(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, material: Material, parent: Node) -> void:
	box(Vector3(x1 - x0, y1 - y0, z1 - z0), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), material, parent)

func _build_room() -> void:
	var room := Node3D.new()
	room.name = "InterrogationRoom"
	world.add_child(room)
	var cx: float = (X0 + X1) * 0.5
	var cz: float = (Z0 + Z1) * 0.5
	var floor_m := mat("damaged_concrete_floor", 0.4, Color(0.5, 0.47, 0.44))
	var wall_m := mat("concrete_wall_008", 0.4, Color(0.55, 0.52, 0.47))
	var tile_m := mat("dirty_tiles", 0.55, Color(0.55, 0.56, 0.5))
	var rust := mat("rusty_metal", 1.0, Color(0.5, 0.36, 0.3))
	var ceil_m := mat("grey_plaster_03", 0.5, Color(0.3, 0.28, 0.25))
	box(Vector3(X1 - X0 + 1.0, 0.2, Z1 - Z0 + 1.0), Vector3(cx, -0.1, cz), floor_m, room)
	box(Vector3(X1 - X0 + 1.0, 0.2, Z1 - Z0 + 1.0), Vector3(cx, CEIL + 0.1, cz), ceil_m, room)
	_wall(X0 - 0.5, X1 + 0.5, Z0 - 0.4, Z0, 0.0, CEIL, wall_m, room)
	_wall(X0 - 0.5, X1 + 0.5, Z1, Z1 + 0.4, 0.0, CEIL, wall_m, room)
	_wall(X0 - 0.4, X0, Z0, Z1, 0.0, CEIL, wall_m, room)
	_wall(X1, X1 + 0.4, Z0, -2.7, 0.0, CEIL, wall_m, room)
	_wall(X1, X1 + 0.4, 0.3, Z1, 0.0, CEIL, wall_m, room)
	_wall(X1, X1 + 0.4, -2.7, 0.3, 0.0, 1.2, wall_m, room)
	_wall(X1, X1 + 0.4, -2.7, 0.3, 2.7, CEIL, wall_m, room)
	_wall(X0 - 0.5, X1 + 0.5, Z0, Z0 + 0.04, 0.0, 1.25, tile_m, room)
	_wall(X0, X0 + 0.04, Z0, Z1, 0.0, 1.25, tile_m, room)
	_wall(X1 - 0.04, X1, Z0, Z1, 0.0, 1.25, tile_m, room)
	_wall(X0, X1, Z1 - 0.04, Z1, 0.0, 1.25, tile_m, room)
	_wall(X0, X1, Z0, Z0 + 0.06, 1.25, 1.33, rust, room)
	_wall(X0, X0 + 0.06, Z0, Z1, 1.25, 1.33, rust, room)
	_wall(X1 - 0.06, X1, Z0, Z1, 1.25, 1.33, rust, room)
	for b in [-4.5, -1.5, 1.5, 4.5]:
		_wall(b - 0.15, b + 0.15, Z0 + 0.0, Z0 + 0.35, CEIL - 0.45, CEIL, rust, room)
	for z in [-3.2, 0.0, 3.2, 6.0]:
		_wall(X0, X1, z - 0.15, z + 0.15, CEIL - 0.4, CEIL, rust, room)
	var pipe_m := mat("rusty_metal_02", 1.5)
	_pipe(Vector3(X0, CEIL - 0.3, Z0 + 0.25), Vector3(X1, CEIL - 0.3, Z0 + 0.25), 0.12, pipe_m, room)
	_pipe(Vector3(X0, CEIL - 0.62, Z0 + 0.2), Vector3(X1, CEIL - 0.62, Z0 + 0.2), 0.07, pipe_m, room)
	_pipe(Vector3(X0 + 0.22, 0.0, Z0 + 0.3), Vector3(X0 + 0.22, CEIL, Z0 + 0.3), 0.09, pipe_m, room)
	_pipe(Vector3(X0 + 0.25, CEIL - 0.4, Z0), Vector3(X0 + 0.25, CEIL - 0.4, Z1), 0.1, pipe_m, room)
	_pipe(Vector3(X0 + 0.5, CEIL - 0.7, Z0), Vector3(X0 + 0.5, CEIL - 0.7, Z1), 0.055, pipe_m, room)
	_pipe(Vector3(X1 - 0.3, 0.0, Z0 + 0.5), Vector3(X1 - 0.3, CEIL, Z0 + 0.5), 0.08, pipe_m, room)
	var key := _omni(Vector3(0.0, 2.2, 3.2), Color(1.0, 0.82, 0.62), 2.0, 9.0, room)
	key.shadow_enabled = false
	_omni(Vector3(-3.6, 2.4, -2.6), Color(0.5, 0.72, 0.64), 1.5, 8.0, room)
	_omni(Vector3(3.8, 2.4, 2.4), Color(1.0, 0.7, 0.45), 1.3, 8.0, room)
	_omni(Vector3(-4.8, 2.5, 3.5), Color(1.0, 0.75, 0.5), 0.8, 5.0, room)
	_lamp_pivot = Node3D.new()
	room.add_child(_lamp_pivot)
	_lamp_pivot.position = Vector3(0.0, CEIL, 0.0)
	_pipe(Vector3(0, 0, 0), Vector3(0, -0.35, 0), 0.012, mat("rusty_metal", 2.0, Color(0.2, 0.18, 0.16)), _lamp_pivot)
	prop("hanging_industrial_lamp", Vector3(0.0, -0.35, 0.0), 0.0, 1.0, _lamp_pivot)
	_lamp_spot = SpotLight3D.new()
	_lamp_spot.light_color = Color(1.0, 0.78, 0.5)
	_lamp_spot.light_energy = 13.0
	_lamp_spot.spot_range = 7.0
	_lamp_spot.spot_angle = 58.0
	_lamp_spot.spot_attenuation = 0.8
	_lamp_spot.shadow_enabled = true
	_lamp_pivot.add_child(_lamp_spot)
	_lamp_spot.position = Vector3(0.0, -1.3, 0.0)
	_lamp_spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var bulb := _omni(Vector3(0.0, -1.4, 0.0), Color(1.0, 0.72, 0.42), 2.4, 6.0, _lamp_pivot)
	bulb.shadow_enabled = false

func _build_board() -> void:
	var cz: float = BOARD_Z
	var frame := mat("rusty_metal", 1.0, Color(0.22, 0.2, 0.18))
	box(Vector3(5.0, 1.75, 0.2), Vector3(0.0, 3.25, cz), frame)
	box(Vector3(4.7, 1.5, 0.05), Vector3(0.0, 3.25, cz + 0.12), mat("rusty_metal", 1.0, Color(0.03, 0.03, 0.03)))
	for bx in [-2.4, 2.4]:
		for by in [2.5, 4.0]:
			box(Vector3(0.1, 0.1, 0.06), Vector3(bx, by, cz + 0.12), mat("rusty_metal", 2.0, Color(0.5, 0.45, 0.4)))
	_red_mat = _emit_mat(Color("ff2a1a"), 0.2)
	_green_mat = _emit_mat(Color("2aff5a"), 0.2)
	for side in [-1.0, 1.0]:
		var lens := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.55
		cm.bottom_radius = 0.6
		cm.height = 0.14
		lens.mesh = cm
		lens.material_override = _red_mat if side < 0.0 else _green_mat
		lens.rotation_degrees.x = 90.0
		lens.position = Vector3(side * 1.95, 3.25, cz + 0.2)
		world.add_child(lens)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.58
		tm.outer_radius = 0.72
		ring.mesh = tm
		ring.material_override = frame
		ring.rotation_degrees.x = 90.0
		ring.position = Vector3(side * 1.95, 3.25, cz + 0.2)
		world.add_child(ring)
	_led = Label3D.new()
	_led.text = "READY"
	_led.font_size = 200
	_led.pixel_size = 0.0042
	_led.outline_size = 0
	_led.shaded = false
	_led.modulate = Color(1.0, 0.5, 0.1)
	world.add_child(_led)
	_led.position = Vector3(0.0, 3.25, cz + 0.17)
	_wash = _omni(Vector3(0.0, 2.8, Z0 + 1.6), Color("ff2a1a"), 2.0, 9.0)
	var clock_n := prop("wall_clock", Vector3(-4.1, 3.1, Z0 + 0.02), 0.0, 2.8)
	if clock_n:
		_clock_hand = Node3D.new()
		clock_n.add_child(_clock_hand)
		_clock_hand.position = Vector3(0.0, 0.0, 0.03)
		var hand := box(Vector3(0.006, 0.12, 0.004), Vector3(0.0, 0.06, 0.0), _emit_mat(Color("c01a10"), 0.6), _clock_hand)
		hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _emit_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.8)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	return m

func _build_table() -> void:
	var steel := mat("blue_metal_plate", 1.2, Color(0.55, 0.57, 0.58))
	var legs := mat("rusty_metal_02", 1.5, Color(0.6, 0.55, 0.5))
	var table := Node3D.new()
	world.add_child(table)
	box(Vector3(2.0, 0.07, 0.95), Vector3(0.0, 0.8, 0.0), steel, table)
	box(Vector3(2.04, 0.04, 0.99), Vector3(0.0, 0.75, 0.0), legs, table)
	for lx in [-0.92, 0.92]:
		for lz in [-0.4, 0.4]:
			box(Vector3(0.06, 0.78, 0.06), Vector3(lx, 0.39, lz), legs, table)
	box(Vector3(1.8, 0.04, 0.8), Vector3(0.0, 0.25, 0.0), legs, table)
	prop("desk_lamp_arm_01", Vector3(-0.75, 0.835, -0.15), 90.0, 1.0)
	prop("binder_notebook", Vector3(0.35, 0.835, 0.12), 20.0, 1.2)
	prop("metal_toolbox", Vector3(0.7, 0.835, -0.15), -15.0, 1.0)
	var saw := prop("rusted_hacksaw", Vector3(-0.15, 0.835, 0.2), 65.0, 1.0)
	if saw:
		saw.rotation_degrees.x = 0.0
	var wr := prop("pipe_wrench", Vector3(0.1, 0.84, -0.18), 80.0, 1.1)
	if wr:
		wr.rotation_degrees.z = 90.0
	var drain_m := mat("metal_grate_rusty", 2.0, Color(0.5, 0.48, 0.46))
	box(Vector3(1.0, 0.03, 0.7), Vector3(0.0, 0.015, 0.0), mat("rusty_metal", 1.0, Color(0.2, 0.18, 0.16)))
	box(Vector3(0.9, 0.035, 0.6), Vector3(0.0, 0.02, 0.0), drain_m)
	var gut := mat("metal_grate_rusty", 3.0, Color(0.32, 0.3, 0.28))
	box(Vector3(0.2, 0.025, 5.8), Vector3(0.0, 0.012, -2.9 - 0.3), gut)
	box(Vector3(0.2, 0.025, 5.0), Vector3(0.0, 0.012, 3.0), gut)
	box(Vector3(6.2, 0.025, 0.2), Vector3(-3.4, 0.012, 0.0), gut)
	box(Vector3(6.2, 0.025, 0.2), Vector3(3.4, 0.012, 0.0), gut)

func _build_dressing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 26:
		var d := Decal.new()
		d.texture_albedo = _splat
		var sz: float = rng.randf_range(0.5, 2.2)
		d.size = Vector3(sz, 0.5, sz * rng.randf_range(0.6, 1.0))
		var blood: bool = i % 3 == 0
		d.modulate = Color(0.26, 0.03, 0.03, 0.95) if blood else Color(0.1, 0.09, 0.08, 0.9)
		d.rotation.y = rng.randf() * TAU
		d.cull_mask = 1
		world.add_child(d)
		d.position = Vector3(rng.randf_range(X0 + 0.8, X1 - 0.8), 0.1, rng.randf_range(Z0 + 0.8, Z1 - 0.8))
	for k in 6:
		var d := Decal.new()
		d.texture_albedo = _splat
		d.size = Vector3(1.8, 0.8, 0.5 + rng.randf() * 0.4)
		d.modulate = Color(0.2, 0.02, 0.02, 0.9)
		d.rotation_degrees.x = 90.0
		d.cull_mask = 1
		world.add_child(d)
		d.position = Vector3(rng.randf_range(-5.5, 5.5), rng.randf_range(0.3, 1.1), Z0 + 0.02)
	var clutter := [["drawer_cabinet", -5.9, -3.4, 90.0, 1.0], ["tool_cart", -5.8, -0.4, 85.0, 1.0], ["barrel_03", -6.0, -4.8, 0.0, 1.0],
		["barrel_03", -5.3, -5.0, 40.0, 1.0], ["metal_trash_can", -6.0, 3.0, 0.0, 1.0], ["trashbag", -5.6, 3.7, 20.0, 1.0],
		["cardboard_box_01", -5.9, 5.2, 10.0, 1.3], ["hand_truck", -5.0, 6.1, 70.0, 1.0], ["WetFloorSign_01", -3.6, 4.6, 30.0, 1.0],
		["metal_jerrycan", -5.7, 1.4, 25.0, 1.0], ["wooden_crate_01", 3.0, -4.7, 15.0, 1.15], ["wooden_crate_02", 4.0, -4.9, -20.0, 1.0],
		["old_military_crate", -2.6, -4.7, 5.0, 1.0], ["portable_generator", 1.4, -4.8, 180.0, 1.0], ["propane_tank", 2.4, -5.0, 0.0, 1.0],
		["korean_fire_extinguisher_01", 5.9, -3.3, 0.0, 1.0], ["old_tyre", 5.4, 3.4, 0.0, 1.0], ["plastic_crate_01", 5.7, 4.6, 30.0, 1.2],
		["medical_box", 5.5, 5.8, 0.0, 1.0], ["cement_bag", 4.4, 6.2, 60.0, 1.0], ["barrel_stove", -4.4, 5.4, 0.0, 1.0]]
	for c in clutter:
		prop(c[0], Vector3(c[1], 0.0, c[2]), c[3], c[4])
	prop("dining_chair_02", Vector3(-3.9, 0.0, -3.6), 120.0, 1.1)
	var tipped := prop("dining_chair_02", Vector3(3.4, 0.28, 3.9), -40.0, 1.1)
	if tipped:
		tipped.rotation_degrees.x = 88.0
	prop("bleach_bottle", Vector3(-5.8, 0.96, -0.2), 0.0, 1.0)
	prop("large_iron_gate", Vector3(X0 + 0.08, 0.0, 4.1), 90.0, 1.0)
	var cable := mat("rusty_metal", 2.0, Color(0.08, 0.08, 0.08))
	for k in 5:
		var x0: float = -3.4 + float(k) * 0.12
		_pipe(Vector3(x0, CEIL - 0.3, Z0 + 0.3), Vector3(x0 - 0.2, 2.9, Z0 + 0.12), 0.012, cable, world)
		_pipe(Vector3(x0 - 0.2, 2.9, Z0 + 0.12), Vector3(x0 - 0.3, 1.9, Z0 + 0.1), 0.012, cable, world)
	for k in 4:
		var x1: float = 3.6 + float(k) * 0.1
		_pipe(Vector3(x1, CEIL - 0.3, Z0 + 0.3), Vector3(x1 + 0.15, 2.6, Z0 + 0.12), 0.011, cable, world)
		_pipe(Vector3(x1 + 0.15, 2.6, Z0 + 0.12), Vector3(x1 + 0.1, 1.7, Z0 + 0.1), 0.011, cable, world)
	prop("power_box_01", Vector3(-5.0, 1.8, Z0 + 0.05), 0.0, 1.5)
	prop("fire_alarm", Vector3(5.0, 1.8, Z0 + 0.05), 0.0, 1.5)
	prop("industrial_caged_sconce", Vector3(X0 + 0.05, 2.5, 0.8), 90.0, 1.4)
	prop("security_light", Vector3(X1 - 0.2, 3.9, 3.5), -90.0, 1.5)
	prop("security_camera_01", Vector3(-6.2, 4.0, 5.9), 135.0, 1.6)
	prop("caged_hanging_light", Vector3(5.1, CEIL, -3.8), 0.0, 1.2)
	var lamp_pt := _omni(Vector3(5.0, 3.2, -3.6), Color(1.0, 0.76, 0.5), 1.5, 4.5)
	lamp_pt.shadow_enabled = false
	_build_tripod(Vector3(-5.6, 0.0, -4.3))

func _build_tripod(at: Vector3) -> void:
	var root := Node3D.new()
	world.add_child(root)
	root.position = at
	var leg_m := mat("rusty_metal", 2.0, Color(0.22, 0.2, 0.18))
	var head := Vector3(0.0, 1.45, 0.0)
	for k in 3:
		var a: float = TAU * float(k) / 3.0 + 0.4
		_pipe(Vector3(cos(a) * 0.5, 0.0, sin(a) * 0.5), head, 0.017, leg_m, root)
	box(Vector3(0.12, 0.08, 0.12), head + Vector3(0, 0.02, 0), leg_m, root)
	var cam := prop("Camera_01", Vector3.ZERO, 0.0, 2.6, root)
	if cam:
		cam.position = head + Vector3(0.0, 0.14, 0.0)
		cam.rotation.y = atan2(-at.x, -at.z) + PI
	_rec_mat = _emit_mat(Color("ff1a1a"), 3.0)
	var rec := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.016
	sm.height = 0.032
	rec.mesh = sm
	rec.material_override = _rec_mat
	root.add_child(rec)
	rec.position = head + Vector3(0.0, 0.3, 0.0) + Vector3(sin(atan2(-at.x, -at.z)), 0.0, cos(atan2(-at.x, -at.z))) * 0.08

func _build_observers() -> void:
	var dark := mat("concrete_wall_008", 0.5, Color(0.22, 0.22, 0.22))
	var frame := mat("rusty_metal", 1.0, Color(0.2, 0.18, 0.16))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.09, 0.1, 0.5)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.9
	glass.roughness = 0.08
	box(Vector3(0.03, 1.5, 3.0), Vector3(X1 + 0.15, 1.95, -1.2), glass)
	for e in [[Vector3(0.12, 0.1, 3.2), Vector3(X1 + 0.1, 2.72, -1.2)], [Vector3(0.12, 0.1, 3.2), Vector3(X1 + 0.1, 1.18, -1.2)],
			[Vector3(0.12, 1.6, 0.1), Vector3(X1 + 0.1, 1.95, 0.32)], [Vector3(0.12, 1.6, 0.1), Vector3(X1 + 0.1, 1.95, -2.72)]]:
		box(e[0], e[1], frame)
	_wall(X1 + 0.4, X1 + 3.0, -3.2, 1.0, -0.2, 0.0, dark, world)
	_wall(X1 + 0.4, X1 + 3.0, -3.2, 1.0, CEIL, CEIL + 0.2, dark, world)
	_wall(X1 + 2.8, X1 + 3.0, -3.2, 1.0, 0.0, CEIL, dark, world)
	_wall(X1 + 0.4, X1 + 3.0, -3.4, -3.2, 0.0, CEIL, dark, world)
	_wall(X1 + 0.4, X1 + 3.0, 1.0, 1.2, 0.0, CEIL, dark, world)
	var glow := _omni(Vector3(X1 + 1.2, 3.0, -1.2), Color(0.8, 0.9, 1.0), 1.6, 3.6)
	glow.shadow_enabled = false
	var zs := [-2.1, -0.4]
	for i in 2:
		var o := LabCharacter.new()
		o.sex = "male" if i == 0 else "female"
		o.hat = "tophat" if i == 0 else "hardhat"
		o.suit_color = Color(0.2, 0.22, 0.24)
		world.add_child(o)
		o.position = Vector3(X1 + 1.3, 0.0, zs[i])
		o.rotation.y = -PI * 0.5
		o.play_loop("Idle_FoldArms" if i == 0 else "Idle_Talking")
		o.anim.seek(randf() * 2.0, true)

func _build_dust() -> void:
	var gp := GPUParticles3D.new()
	gp.amount = 60
	gp.lifetime = 7.0
	gp.local_coords = false
	gp.visibility_aabb = AABB(Vector3(-4, 0, -4), Vector3(8, 5, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2.4, 1.6, 2.4)
	pm.direction = Vector3(0.2, -0.1, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.gravity = Vector3(0, -0.01, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.15
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _soft
	m.albedo_color = Color(1.0, 0.9, 0.7, 0.55)
	q.material = m
	gp.draw_pass_1 = q
	world.add_child(gp)
	gp.position = Vector3(0.0, 2.0, 0.0)

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

func _make_gun() -> Node3D:
	var g: Node3D = load(PH_MOD + "service_pistol/service_pistol.gltf").instantiate()
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm.ends_with("_b") or nm.contains("magazine") or nm.contains("bullet"):
			mi.visible = false
	return g

func _label3(text: String, size: int, color: Color, outline: int, prio: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.0009
	l.fixed_size = true
	l.font_size = size
	l.outline_size = outline
	l.modulate = color
	l.render_priority = prio
	world.add_child(l)
	return l

func _line_up() -> void:
	var ids: Array = NetworkManager.players.keys()
	var n: int = ids.size()
	var span: float = clampf(36.0 * float(n - 1), 50.0, 250.0)
	for i in n:
		var id: int = ids[i]
		var info: Dictionary = NetworkManager.players[id]
		var a: float = deg_to_rad(-span * 0.5 + span * float(i) / maxf(1.0, float(n - 1)))
		var pos := Vector3(sin(a) * RING_R, 0.0, -cos(a) * RING_R)
		if n == 1:
			pos = Vector3(0.0, 0.0, -RING_R)
		var body := LabCharacter.new()
		body.sex = info.get("sex", "male")
		body.hat = info.get("hat", "hardhat")
		body.suit_color = info.color
		body.position = pos
		var yaw: float = atan2(-pos.x, -pos.z)
		body.rotation.y = yaw
		world.add_child(body)
		body.play_loop("Idle")
		body.anim.seek(randf() * 2.0, true)
		var att := BoneAttachment3D.new()
		att.bone_name = "hand_r"
		body.skeleton.add_child(att)
		var hand_gun := _make_gun()
		att.add_child(hand_gun)
		hand_gun.transform = _gun_hand_xf
		hand_gun.visible = false
		var hol := Node3D.new()
		body.add_child(hol)
		hol.position = Vector3(-0.25, 0.9, 0.03)
		var hgun := _make_gun()
		hol.add_child(hgun)
		hgun.transform = _gun_holster_xf
		var pouch := box(Vector3(0.09, 0.22, 0.13), Vector3(0.0, -0.12, -0.01), mat("rubber_tiles", 2.0, Color(0.34, 0.22, 0.14)), hol)
		pouch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var head := pos + Vector3(0.0, 1.9, 0.0)
		var name_l := _label3(info.name + ("  (YOU)" if id == multiplayer.get_unique_id() else ""), 24, info.color.lightened(0.35), 10, 3)
		name_l.position = head + Vector3(0, 0.3, 0)
		var ms_l := _label3("", 34, Color("f2e6c4"), 12, 4)
		ms_l.position = head + Vector3(0, 0.15, 0)
		subjects[id] = {"body": body, "hand_gun": hand_gun, "holster": hol, "name": name_l, "ms": ms_l, "yaw": yaw, "pos": pos}
		_sum_ms[id] = 0.0
		_cnt[id] = 0
		if info.is_bot:
			_bot[id] = {"mean": randf_range(215.0, 360.0), "sd": randf_range(18.0, 40.0)}

func _spawn_supervisor() -> void:
	_sup = LabCharacter.new()
	_sup.sex = "male"
	_sup.hat = "tophat"
	_sup.suit_color = Color(0.3, 0.31, 0.33)
	world.add_child(_sup)
	_sup.position = Vector3(5.3, 0.0, -4.3)
	_sup.rotation.y = atan2(-5.3, 4.3)
	_sup.play_loop("Idle")
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	_sup.skeleton.add_child(att)
	_sup_gun = _make_gun()
	att.add_child(_sup_gun)
	_sup_gun.transform = _gun_hand_xf
	_sup_mod = ArmPose.new()
	_sup.skeleton.add_child(_sup_mod)
	_sup_mod.poses = _arm_pose("Pistol_Idle", _sup.skeleton)
	var tag := Label3D.new()
	tag.text = "SUPERVISOR"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.0008
	tag.fixed_size = true
	tag.font_size = 20
	tag.outline_size = 8
	tag.modulate = Color(0.75, 0.75, 0.72)
	_sup.add_child(tag)
	tag.position = Vector3(0, 2.1, 0)

func _arm_pose(anim_name: String, sk: Skeleton3D) -> Dictionary:
	var a := LabCharacter.shared_library().get_animation(anim_name)
	var d: Dictionary = {}
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(a.track_get_path(t)).get_slice(":", 1)
		if not bone.ends_with("_r") or bone.begins_with("thigh") or bone.begins_with("calf") or bone.begins_with("foot") or bone.begins_with("ball"):
			continue
		var bi := sk.find_bone(bone)
		if bi >= 0:
			d[bi] = a.rotation_track_interpolate(t, minf(0.4, a.length * 0.5))
	return d

func _build_hud() -> void:
	hud_title("QUICK DRAW  ·  fastest draw shoots the slowest")
	_round_label = Label.new()
	_round_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_round_label.position = Vector2(-220, 10)
	_round_label.size = Vector2(200, 30)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_round_label.add_theme_font_size_override("font_size", 26)
	_round_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_round_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_round_label)
	_big = _center_label(84, 0.74)
	_hint = _center_label(22, 0.92)
	_hint.text = "WAIT FOR GREEN, THEN HIT  SPACE\nearly press = false start = the supervisor shoots you"
	_hint.add_theme_color_override("font_color", Color("e8e2c8"))
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0.7, 1.0, 0.75, 0.0)
	hud.add_child(_flash)

func _center_label(size: int, y: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.anchor_top = y - 0.1
	l.anchor_bottom = y + 0.1
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 14)
	hud.add_child(l)
	return l

func _say(text: String, hex: String, hold: float) -> void:
	if _big_tw:
		_big_tw.kill()
	_big.text = text
	_big.add_theme_color_override("font_color", Color(hex))
	_big.modulate.a = 1.0
	if hold > 0.0:
		_big_tw = create_tween()
		_big_tw.tween_interval(hold)
		_big_tw.tween_property(_big, "modulate:a", 0.0, 0.3)

func _set_signal(mode: int) -> void:
	var red_on: bool = mode == 1
	var green_on: bool = mode == 2
	_red_mat.emission = Color("ff2a1a")
	_red_mat.emission_energy_multiplier = 3.0 if red_on else (0.9 if mode == 0 else 0.08)
	_green_mat.emission_energy_multiplier = 3.0 if green_on else 0.08
	match mode:
		0:
			_led.text = "READY"
			_led.modulate = Color(1.6, 0.8, 0.15)
			_wash.light_color = Color("ffa020")
			_wash.light_energy = 0.8
		1:
			_led.text = "WAIT"
			_led.modulate = Color(3.0, 0.25, 0.15)
			_wash.light_color = Color("ff2a1a")
			_wash.light_energy = 3.5
		2:
			_led.text = "DRAW"
			_led.modulate = Color(0.3, 3.0, 0.6)
			_wash.light_color = Color("2aff5a")
			_wash.light_energy = 5.0

func _amber(on: bool) -> void:
	if st != St.WAIT:
		return
	if on:
		_red_mat.emission = Color("ffa020")
		_red_mat.emission_energy_multiplier = 4.5
		_led.modulate = Color(3.0, 1.6, 0.2)
		_wash.light_color = Color("ffa020")
	else:
		_red_mat.emission = Color("ff2a1a")
		_red_mat.emission_energy_multiplier = 3.0
		_led.modulate = Color(3.0, 0.25, 0.15)
		_wash.light_color = Color("ff2a1a")

func _process(delta: float) -> void:
	if _hint == null:
		return
	var down := Input.is_physical_key_pressed(KEY_SPACE)
	if down and not _space_down:
		_local_press()
	_space_down = down
	clock += delta
	_cam_t += delta
	_update_camera(delta)
	_animate_set(delta)

func _animate_set(delta: float) -> void:
	_lamp_pivot.rotation = Vector3(sin(clock * 0.9) * 0.035, 0.0, sin(clock * 0.7 + 1.0) * 0.045)
	_lamp_spot.light_energy = 20.0 + sin(clock * 23.0) * 0.4 + (randf() * 3.0 if fmod(clock, 4.3) < 0.12 else 0.0)
	if _clock_hand:
		var sec: int = int(clock)
		_clock_hand.rotation.z = -float(sec) * TAU / 60.0
		if sec != _last_tick:
			_last_tick = sec
			Fx.sfx("click", Vector3(-4.1, 3.1, Z0 + 0.3), -26.0, 1.9)
	if _rec_mat:
		_rec_mat.emission_energy_multiplier = 3.0 if fmod(clock, 1.6) < 0.8 else 0.0

func _update_camera(delta: float) -> void:
	var pos: Vector3
	var look: Vector3
	if _cam_mode == 0:
		var u: float = clampf(_cam_t / 6.5, 0.0, 1.0)
		var th: float = _orbit_dir * lerpf(-0.55, 0.55, u)
		var r: float = lerpf(5.0, 3.5, u)
		var h: float = lerpf(1.85, 1.55, u)
		pos = Vector3(sin(th) * r, h, cos(th) * r - 0.2)
		look = Vector3(0.0, 1.85, -1.1)
		camera.position = pos
		_look = _look.lerp(look, 1.0 if delta <= 0.0 else clampf(delta * 6.0, 0.0, 1.0))
	elif _cam_mode == 1:
		var th2: float = _wide_dir * 0.7
		var r2: float = 6.3 - minf(_cam_t, 3.0) * 0.18
		pos = Vector3(sin(th2) * r2, 2.8 - minf(_cam_t, 3.0) * 0.08, cos(th2) * r2)
		look = Vector3(0.0, 2.0, -1.6)
		camera.position = pos
		_look = look
	else:
		var dir := Vector3(sin(_wide_dir * 0.7), 0.0, cos(_wide_dir * 0.7))
		var want := Vector3(_focus.x, 1.55, _focus.z) + dir * 3.1
		camera.position = camera.position.lerp(want, 1.0 - exp(-2.2 * delta))
		_look = _look.lerp(_focus + Vector3(0.0, 0.9, 0.0), 1.0 - exp(-3.0 * delta))
	camera.look_at(_look, Vector3.UP)

func _local_press() -> void:
	var me: int = multiplayer.get_unique_id()
	if not subjects.has(me) or dead_order.has(me):
		return
	if st == St.DRAW:
		if _drew_local:
			return
		_drew_local = true
		_send_press(me, float(Time.get_ticks_msec() - _draw_tick))
	elif st == St.WAIT:
		_send_press(me, -1.0)

func _send_press(id: int, ms: float) -> void:
	if NetworkManager.is_server():
		_srv_press(id, ms)
	else:
		_rpc_press.rpc_id(1, ms)

@rpc("any_peer", "reliable")
func _rpc_press(ms: float) -> void:
	if NetworkManager.is_server():
		_srv_press(multiplayer.get_remote_sender_id(), ms)

func _srv_press(id: int, ms: float) -> void:
	if not subjects.has(id) or dead_order.has(id):
		return
	if st == St.WAIT:
		_srv_false_start(id)
	elif st == St.DRAW:
		_srv_register(id, clampf(ms, 90.0, DRAW_WINDOW * 1000.0))

func _srv_false_start(id: int) -> void:
	if dead_order.has(id) or _fs_done.has(id) or _alive_count() <= 1:
		return
	_fs_done[id] = true
	dead_order.append(id)
	_sup_queue.append(id)
	_rpc_false_start.rpc(id)

func _srv_register(id: int, ms: float) -> void:
	if _times.has(id) or dead_order.has(id) or st != St.DRAW:
		return
	_times[id] = ms
	_rpc_drew.rpc(id, ms)

func _alive_count() -> int:
	return subjects.size() - dead_order.size()

func _alive_list() -> Array:
	return subjects.keys().filter(func(i): return not dead_order.has(i))

func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	_rpc_say.rpc("GET READY", "e8e2c8", 1.5)
	await get_tree().create_timer(1.8).timeout
	var n: int = 0
	while n < ROUNDS and _alive_count() > 1 and clock < TIME_LIMIT - 9.0:
		n += 1
		await _play_round(n)
	var living: Array = _alive_list()
	var msg: String = "DUEL OVER"
	if living.size() == 1:
		msg = "%s  STANDS ALONE" % String(NetworkManager.players[living[0]].name).to_upper()
	_rpc_end.rpc(msg)
	await get_tree().create_timer(3.0).timeout
	if not _ended:
		_ended = true
		finished.emit(_placement())

func _placement() -> Array:
	var living: Array = _alive_list()
	living.sort_custom(func(a, b): return _avg(a) < _avg(b))
	var out: Array = living
	for i in range(dead_order.size() - 1, -1, -1):
		out.append(dead_order[i])
	return out

func _avg(id: int) -> float:
	var c: int = int(_cnt.get(id, 0))
	return float(_sum_ms.get(id, 0.0)) / float(c) if c > 0 else 9999.0

func _play_round(n: int) -> void:
	_times.clear()
	_bot_plan.clear()
	_rpc_round.rpc(n)
	await get_tree().create_timer(1.3).timeout
	if _alive_count() <= 1:
		return
	_rpc_wait.rpc()
	var wait: float = randf_range(WAIT_MIN, WAIT_MAX)
	var fake_at: float = -1.0
	if randf() < 0.55 and wait > 2.8:
		fake_at = randf_range(1.0, wait - 1.0)
	var jumpy: Dictionary = {}
	for id in _bot:
		if not dead_order.has(id) and randf() < 0.04:
			jumpy[id] = randf_range(0.4, wait - 0.2)
	var t0: int = Time.get_ticks_msec()
	while true:
		var el: float = float(Time.get_ticks_msec() - t0) / 1000.0
		if el >= wait and not _sup_busy and _sup_queue.is_empty():
			break
		if el >= wait + 3.5:
			break
		if fake_at >= 0.0 and el >= fake_at:
			fake_at = -1.0
			_rpc_fake.rpc()
			for id in _bot:
				if not dead_order.has(id) and not jumpy.has(id) and randf() < 0.04:
					jumpy[id] = el + randf_range(0.12, 0.32)
		for id in jumpy.keys():
			if el >= float(jumpy[id]):
				jumpy.erase(id)
				_srv_false_start(id)
		if _alive_count() <= 1:
			return
		await get_tree().process_frame
	for id in _bot:
		if not dead_order.has(id):
			var b: Dictionary = _bot[id]
			_bot_plan[id] = clampf(randfn(float(b.mean), float(b.sd)), 180.0, 450.0)
	_rpc_draw.rpc()
	var d0: int = Time.get_ticks_msec()
	while true:
		var ms: float = float(Time.get_ticks_msec() - d0)
		for id in _bot_plan.keys():
			if ms >= float(_bot_plan[id]):
				var planned: float = float(_bot_plan[id])
				_bot_plan.erase(id)
				_srv_register(id, planned)
		var living: Array = _alive_list()
		if living.all(func(i): return _times.has(i)) or ms >= DRAW_WINDOW * 1000.0:
			break
		await get_tree().process_frame
	var alive: Array = _alive_list()
	var res: Dictionary = {}
	for id in alive:
		res[id] = float(_times.get(id, DNF_MS))
		_sum_ms[id] = float(_sum_ms[id]) + float(res[id])
		_cnt[id] = int(_cnt[id]) + 1
	var pressed: Array = alive.filter(func(i): return _times.has(i))
	var shooter: int = -1
	var victim: int = -1
	if not pressed.is_empty() and alive.size() > 1:
		pressed.sort_custom(func(a, b): return float(_times[a]) < float(_times[b]))
		shooter = pressed[0]
		var order: Array = alive.duplicate()
		order.shuffle()
		order.sort_custom(func(a, b): return float(res[a]) > float(res[b]))
		victim = order[0]
		if victim == shooter:
			victim = -1
	if victim != -1:
		dead_order.append(victim)
	_rpc_resolve.rpc(shooter, victim, res)
	await get_tree().create_timer(3.0).timeout

@rpc("authority", "call_local", "reliable")
func _rpc_say(text: String, hex: String, hold: float) -> void:
	_say(text, hex, hold)

@rpc("authority", "call_local", "reliable")
func _rpc_round(n: int) -> void:
	st = St.BETWEEN
	round_no = n
	_drew_local = false
	_cam_mode = 0
	_cam_t = 0.0
	_orbit_dir = 1.0 if n % 2 == 1 else -1.0
	_round_label.text = "ROUND %d / %d" % [n, ROUNDS]
	_set_signal(0)
	for id in subjects:
		var s: Dictionary = subjects[id]
		(s.ms as Label3D).text = ""
		if dead_order.has(id):
			continue
		var body: LabCharacter = s.body
		(s.hand_gun as Node3D).visible = false
		(s.holster as Node3D).visible = true
		body.anim.play("Idle", 0.3)
		var tw := body.create_tween()
		tw.tween_property(body, "rotation:y", body.rotation.y + angle_difference(body.rotation.y, float(s.yaw)), 0.3)
	_say("ROUND %d" % n, "e8e2c8", 1.0)
	var th := create_tween()
	th.tween_interval(6.0)
	th.tween_property(_hint, "modulate:a", 0.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_wait() -> void:
	st = St.WAIT
	_set_signal(1)
	_say("WAIT...", "ff3b2e", 0.0)
	Fx.sfx("hum", null, -8.0, 0.6)

@rpc("authority", "call_local", "reliable")
func _rpc_fake() -> void:
	if st != St.WAIT:
		return
	Fx.sfx("click", null, -2.0, 0.7)
	var tw := create_tween()
	tw.tween_callback(_amber.bind(true))
	tw.tween_interval(0.1)
	tw.tween_callback(_amber.bind(false))
	tw.tween_interval(0.07)
	tw.tween_callback(_amber.bind(true))
	tw.tween_interval(0.12)
	tw.tween_callback(_amber.bind(false))

@rpc("authority", "call_local", "reliable")
func _rpc_draw() -> void:
	st = St.DRAW
	_draw_tick = Time.get_ticks_msec()
	_drew_local = false
	_cam_mode = 1
	_cam_t = 0.0
	_wide_dir = _orbit_dir
	_set_signal(2)
	_say("DRAW!", "3dff6a", 0.7)
	Fx.sfx("beep", null, 2.0, 1.7)
	Fx.shake(0.12)
	_flash.color.a = 0.28
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.2)

func _draw_gun(id: int, speed: float) -> void:
	var s: Dictionary = subjects[id]
	var body: LabCharacter = s.body
	(s.holster as Node3D).visible = false
	(s.hand_gun as Node3D).visible = true
	body.anim.play("Pistol_Aim_Neutral", 0.03, speed)

@rpc("authority", "call_local", "reliable")
func _rpc_drew(id: int, ms: float) -> void:
	if not subjects.has(id):
		return
	_draw_gun(id, 1.0)
	var s: Dictionary = subjects[id]
	var l: Label3D = s.ms
	l.text = "%d ms" % int(ms)
	l.modulate = Color("f2e6c4")
	Fx.sfx("click", (s.body as Node3D).position + Vector3(0, 1.0, 0), -4.0, 1.4)

@rpc("authority", "call_local", "reliable")
func _rpc_false_start(id: int) -> void:
	if not dead_order.has(id):
		dead_order.append(id)
	var s: Dictionary = subjects[id]
	_draw_gun(id, 1.0)
	var l: Label3D = s.ms
	l.text = "FALSE START"
	l.modulate = Color("ff3b2e")
	_say("FALSE START!", "ff3b2e", 1.0)
	Fx.sfx("buzzer", null, -4.0, 1.2)
	get_tree().create_timer(1.4).timeout.connect(func() -> void:
		if st == St.WAIT:
			_say("WAIT...", "ff3b2e", 0.0)
	)

func _process_queue() -> void:
	if _sup_busy or _sup_queue.is_empty():
		return
	_rpc_sup_shoot.rpc(_sup_queue.pop_front())

func _physics_process(_delta: float) -> void:
	if NetworkManager.is_server():
		_process_queue()

@rpc("authority", "call_local", "reliable")
func _rpc_sup_shoot(id: int) -> void:
	_sup_busy = true
	var s: Dictionary = subjects[id]
	var body: LabCharacter = s.body
	(s.name as Label3D).modulate = Color("ff6a5a")
	var to: Vector3 = body.position - _sup.position
	var tw := create_tween()
	tw.tween_property(_sup, "rotation:y", _sup.rotation.y + angle_difference(_sup.rotation.y, atan2(to.x, to.z)), 0.25)
	tw.tween_callback(func() -> void:
		_sup_mod.active = false
		_sup.anim.play("Pistol_Shoot", 0.05)
	)
	tw.tween_interval(0.22)
	tw.tween_callback(func() -> void:
		_fire(_sup_gun, body.position + Vector3(0, 1.25, 0))
		_kill(id)
		_focus = body.position
		_cam_mode = 2
	)
	tw.tween_interval(1.1)
	tw.tween_callback(func() -> void:
		_sup_mod.active = true
		_sup.anim.play("Idle", 0.3)
		_sup_busy = false
		if st == St.WAIT:
			_cam_mode = 0
	)

func _fire(gun: Node3D, end: Vector3) -> void:
	var from: Vector3 = gun.global_transform * MUZZLE
	Fx.sfx("gunshot", from, 2.0)
	Fx.shake(0.45)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.75, 0.35)
	fl.light_energy = 14.0
	fl.omni_range = 5.0
	world.add_child(fl)
	fl.global_position = from
	var ftw := fl.create_tween()
	ftw.tween_property(fl, "light_energy", 0.0, 0.12)
	ftw.tween_callback(fl.queue_free)
	var mf := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.0, 0.8, 0.4)
	sm.material = mm
	mf.mesh = sm
	world.add_child(mf)
	mf.global_position = from
	mf.look_at(end, Vector3.UP)
	mf.scale = Vector3(1.0, 1.0, 2.6)
	var mtw := mf.create_tween()
	mtw.tween_property(mf, "scale", Vector3(0.05, 0.05, 0.05), 0.07)
	mtw.tween_callback(mf.queue_free)
	var tr := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.035, 1.0)
	tr.mesh = bm
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_color = Color(1.0, 0.85, 0.4, 0.9)
	tr.material_override = tm
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(tr)
	var len: float = from.distance_to(end)
	tr.global_position = (from + end) * 0.5
	if len > 0.05:
		tr.look_at(end, Vector3.UP)
	tr.scale = Vector3(1.0, 1.0, len)
	var ttw := tr.create_tween()
	ttw.tween_property(tm, "albedo_color:a", 0.0, 0.2)
	ttw.tween_callback(tr.queue_free)

func _kill(id: int) -> void:
	var s: Dictionary = subjects[id]
	var body: LabCharacter = s.body
	(s.hand_gun as Node3D).visible = false
	body.die("Death01")
	Fx.blood(world, body.position + Vector3(0, 1.25, 0), 90)
	Fx.shake(0.6)
	var nl: Label3D = s.name
	nl.modulate.a = 0.45

@rpc("authority", "call_local", "reliable")
func _rpc_resolve(shooter: int, victim: int, res: Dictionary) -> void:
	st = St.RESOLVE
	if victim != -1 and not dead_order.has(victim):
		dead_order.append(victim)
	_set_signal(0)
	var fastest_ms: float = 99999.0
	for id in res:
		if shooter != -1 and id == shooter:
			fastest_ms = float(res[id])
		var s: Dictionary = subjects[id]
		var l: Label3D = s.ms
		var ms: float = float(res[id])
		if ms >= DNF_MS - 0.5:
			l.text = "TOO SLOW"
			l.modulate = Color("ff6a5a")
		else:
			l.text = "%d ms" % int(ms)
			l.modulate = Color("ffd24a") if id == shooter else (Color("ff6a5a") if id == victim else Color("f2e6c4"))
	if shooter == -1:
		_say("NOBODY DREW", "e8e2c8", 1.4)
		return
	var sh: Dictionary = subjects[shooter]
	var vs: Dictionary = subjects[victim]
	var sname: String = NetworkManager.players[shooter].name
	var vname: String = NetworkManager.players[victim].name
	_say("%s  SHOOTS  %s" % [sname.to_upper(), vname.to_upper()], "ffd24a", 2.0)
	_hint.text = "%s  %d ms   ·   %s  %s" % [sname, int(fastest_ms), vname, "too slow" if float(res[victim]) >= DNF_MS - 0.5 else "%d ms" % int(res[victim])]
	_hint.modulate.a = 1.0
	_hint.add_theme_color_override("font_color", Color("ffd24a"))
	var sbody: LabCharacter = sh.body
	var vbody: LabCharacter = vs.body
	_draw_gun(shooter, 1.0)
	var to: Vector3 = vbody.position - sbody.position
	var tw := create_tween()
	tw.tween_property(sbody, "rotation:y", sbody.rotation.y + angle_difference(sbody.rotation.y, atan2(to.x, to.z)), 0.25)
	tw.tween_callback(func() -> void:
		sbody.anim.play("Pistol_Shoot", 0.04)
	)
	tw.tween_interval(0.18)
	tw.tween_callback(func() -> void:
		_fire(sh.hand_gun, vbody.position + Vector3(0, 1.25, 0))
		_kill(victim)
		_focus = vbody.position
		_cam_mode = 2
	)

@rpc("authority", "call_local", "reliable")
func _rpc_end(text: String) -> void:
	st = St.DONE
	_set_signal(0)
	_say(text, "e2c84b", 0.0)
	Fx.sfx("buzzer", null, -6.0, 1.3)
