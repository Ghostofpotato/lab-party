extends ArenaMinigame3D
## Seat Assignment: deadly musical chairs in a grim clinic waiting room. A ring of
## chairs stands under flickering fluorescent tubes, one fewer chair than living
## subjects. While the old radio on the reception desk plays, everyone walks the
## yellow line around the chairs and must keep moving (stand still and the
## attendant fires a warning shot). The radio cuts at a random moment: walk into a
## free chair to sit. Whoever is still standing after 2 s is executed by the
## attendant, and orderlies drag one chair away. SPACE shoves. Up to 6 rounds or
## one left; placement is survival order.

const ROUNDS: int = 6
const TIME_LIMIT: float = 56.0
const SIT_WINDOW: float = 2.0
const SIT_REACH: float = 0.8
const MUSIC_SPEED: float = 2.5
const RUSH_SPEED: float = 5.0
const SHOVE_REACH: float = 1.4
const SHOVE_CD: float = 0.8
const LUNGE: float = 0.5
const KNOCK: float = 1.6
const STILL_WARN: float = 1.0
const STILL_SHOOT: float = 2.4
const C := Vector3(0.0, 0.0, 0.4)
const X0: float = -6.0
const X1: float = 6.0
const Z0: float = -4.5
const Z1: float = 5.6
const WALL_H: float = 6.5
const KINDS: Array = ["dining_chair_02", "SchoolChair_01", "GreenChair_01"]
const SEAT_OFF: Array = [0.35, 0.4, 0.34]
const MUZZLE := Vector3(0.18, 0.0, 0.0)
const DOOR_X: float = 4.4
const PILE_SLOTS: Array = [Vector3(0.0, 0.0, 0.6), Vector3(0.05, 0.0, 1.25), Vector3(0.0, 0.0, -0.05), Vector3(0.1, 0.47, 0.6), Vector3(-0.05, 0.47, 1.25), Vector3(0.0, 0.0, 1.9), Vector3(0.0, 0.47, -0.05)]

enum St { INTRO, PREP, MUSIC, SCRAMBLE, EXEC, DONE }

class ArmPose extends SkeletonModifier3D:
	var poses: Dictionary = {}
	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for bi in poses:
			sk.set_bone_pose_rotation(bi, poses[bi])

var st: St = St.INTRO
var clock: float = 0.0
var round_no: int = 0
var chairs: Array = []
var active: Array = []
var seated: Dictionary = {}
var dead: Array = []
var ticket: Dictionary = {}
var shove_ready: Dictionary = {}
var lock_until: Dictionary = {}
var _cut_t: float = 0.0
var _still: Dictionary = {}
var _last: Dictionary = {}
var _warned: Dictionary = {}
var _bot: Dictionary = {}
var _push_tw: Dictionary = {}
var _warn_l: Dictionary = {}
var _space_down: bool = false
var _ended: bool = false
var _guard_busy: bool = false
var _ring_r: float = 1.0
var _pile_n: Array = [0, 0]
var _font: Font
var _splat: ImageTexture
var _soft: Texture2D
var _gun_hand_xf: Transform3D

var _tubes: Array = []
var _flick_burst: float = 0.0
var _radio: AudioStreamPlayer
var _radio_light: OmniLight3D
var _dial_mat: StandardMaterial3D
var _needle: Node3D
var _line: MeshInstance3D
var _serving: Label3D
var _serving_light: OmniLight3D
var _disp_mat: StandardMaterial3D
var _tv_light: OmniLight3D
var _guard: LabCharacter
var _guard_mod: ArmPose
var _guard_gun: Node3D
var _orderlies: Array = []

var _cam_mode: int = 0
var _focus: Vector3 = Vector3.ZERO
var _look: Vector3 = Vector3(0.0, 0.6, 0.6)
var _big: Label
var _hint: Label
var _round_label: Label
var _count_label: Label
var _big_tw: Tween

func begin() -> void:
	setup_arena(false)
	_font = load("res://assets/ui/VT323-Regular.ttf")
	_soft = _soft_tex()
	_splat = _splat_tex()
	var gb := Basis(Vector3(0.03, 0.97, -0.24), Vector3(-0.03, 0.24, 0.97), Vector3(1.0, -0.02, 0.03)).orthonormalized()
	_gun_hand_xf = Transform3D(gb * Basis.from_scale(Vector3.ONE * 1.9), Vector3(0.0, 0.068, 0.015))
	_tune_light()
	_build_room()
	_build_reception()
	_build_display()
	_build_dressing()
	_build_tubes()
	_build_dust()
	_build_guard()
	_build_orderlies()
	_build_chairs(maxi(1, NetworkManager.players.size() - 1))
	_build_line()
	spawn_players(_spawns())
	_setup_players()
	_build_radio_audio()
	camera.fov = 50.0
	camera.position = Vector3(0.0, 6.4, 8.4)
	camera.look_at(_look, Vector3.UP)
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _exit_tree() -> void:
	if is_instance_valid(Fx._music):
		Fx._music.stream_paused = false

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.08
			n.shadow_enabled = false
	env.background_color = Color("050505")
	env.ambient_light_energy = 0.5
	env.ambient_light_color = Color(0.58, 0.62, 0.55)
	env.fog_density = 0.022
	env.fog_light_color = Color(0.17, 0.19, 0.16)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color(0.7, 0.74, 0.68)
	env.volumetric_fog_length = 16.0
	env.ssao_radius = 0.8
	env.glow_intensity = 0.7
	env.adjustment_saturation = 0.74

func _omni(pos: Vector3, color: Color, energy: float, rng: float, parent: Node = null) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng
	o.shadow_enabled = false
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

func _wall(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, material: Material, parent: Node) -> MeshInstance3D:
	return box(Vector3(x1 - x0, y1 - y0, z1 - z0), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), material, parent)

func _emit_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.8)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	return m

func _build_room() -> void:
	var room := Node3D.new()
	room.name = "WaitingRoom"
	world.add_child(room)
	var floor_m := mat("old_linoleum_flooring_01", 0.45, Color(0.62, 0.62, 0.55))
	var paper := mat("decrepit_wallpaper", 0.35, Color(0.62, 0.64, 0.55))
	var tile_m := mat("dirty_tiles", 0.55, Color(0.6, 0.64, 0.58))
	var upper := mat("dirty_concrete", 0.3, Color(0.3, 0.3, 0.27))
	var rust := mat("rusty_metal", 1.0, Color(0.48, 0.36, 0.3))
	var dark := mat("concrete_wall_008", 0.5, Color(0.08, 0.08, 0.08))
	box(Vector3(X1 - X0 + 1.0, 0.2, Z1 - Z0 + 1.0), Vector3(0.0, -0.1, (Z0 + Z1) * 0.5), floor_m, room)
	for seg in [[X0 - 0.4, DOOR_X - 0.7], [DOOR_X + 0.7, X1 + 0.4]]:
		_wall(seg[0], seg[1], Z0 - 0.4, Z0, 0.0, 1.3, tile_m, room)
		_wall(seg[0], seg[1], Z0 - 0.4, Z0, 1.3, 4.0, paper, room)
	_wall(DOOR_X - 0.7, DOOR_X + 0.7, Z0 - 0.4, Z0, 2.3, 4.0, paper, room)
	_wall(X0 - 0.4, X1 + 0.4, Z0 - 0.4, Z0, 4.0, WALL_H, upper, room)
	_wall(X0 - 0.4, X0, Z0, Z1, 0.0, 1.3, tile_m, room)
	_wall(X0 - 0.4, X0, Z0, Z1, 1.3, 4.0, paper, room)
	_wall(X0 - 0.4, X0, Z0, Z1, 4.0, WALL_H, upper, room)
	_wall(X1, X1 + 0.4, Z0, Z1, 0.0, 1.3, tile_m, room)
	_wall(X1, X1 + 0.4, Z0, Z1, 1.3, 4.0, paper, room)
	_wall(X1, X1 + 0.4, Z0, Z1, 4.0, WALL_H, upper, room)
	_wall(X0, X1, Z1, Z1 + 0.4, 0.0, 1.0, tile_m, room)
	_wall(X0, X1, Z0, Z0 + 0.06, 1.28, 1.36, rust, room)
	_wall(X0, X0 + 0.06, Z0, Z1, 1.28, 1.36, rust, room)
	_wall(X1 - 0.06, X1, Z0, Z1, 1.28, 1.36, rust, room)
	_wall(X0, X1, Z0, Z0 + 0.1, 3.95, 4.08, rust, room)
	_wall(X0, X0 + 0.1, Z0, Z1, 3.95, 4.08, rust, room)
	_wall(X1 - 0.1, X1, Z0, Z1, 3.95, 4.08, rust, room)
	var hall := _wall(DOOR_X - 1.4, DOOR_X + 1.4, Z0 - 1.6, Z0 - 0.4, 0.0, 2.4, dark, room)
	hall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var frame := mat("rusty_metal_02", 1.6, Color(0.45, 0.42, 0.38))
	_wall(DOOR_X - 0.78, DOOR_X - 0.66, Z0 - 0.05, Z0 + 0.08, 0.0, 2.36, frame, room)
	_wall(DOOR_X + 0.66, DOOR_X + 0.78, Z0 - 0.05, Z0 + 0.08, 0.0, 2.36, frame, room)
	_wall(DOOR_X - 0.78, DOOR_X + 0.78, Z0 - 0.05, Z0 + 0.08, 2.3, 2.42, frame, room)
	_omni(Vector3(DOOR_X, 1.6, Z0 - 1.0), Color(0.9, 0.12, 0.08), 1.2, 3.5, room)
	var pipe_m := mat("rusty_metal_02", 1.5)
	_pipe(Vector3(X0, 4.5, Z0 + 0.25), Vector3(X1, 4.5, Z0 + 0.25), 0.13, pipe_m, room)
	_pipe(Vector3(X0, 4.85, Z0 + 0.2), Vector3(X1, 4.85, Z0 + 0.2), 0.08, pipe_m, room)
	_pipe(Vector3(X0 + 0.25, 4.6, Z0), Vector3(X0 + 0.25, 4.6, Z1), 0.11, pipe_m, room)
	_pipe(Vector3(X1 - 0.25, 4.3, Z0), Vector3(X1 - 0.25, 4.3, Z1), 0.09, pipe_m, room)
	_pipe(Vector3(X0 + 0.22, 0.0, Z0 + 0.3), Vector3(X0 + 0.22, 4.6, Z0 + 0.3), 0.08, pipe_m, room)
	_pipe(Vector3(X1 - 0.3, 0.0, Z0 + 0.3), Vector3(X1 - 0.3, 4.3, Z0 + 0.3), 0.07, pipe_m, room)
	for z in [-1.5, 1.6, 4.4]:
		_wall(X0, X0 + 0.25, z - 0.12, z + 0.12, 4.0, WALL_H, rust, room)
		_wall(X1 - 0.25, X1, z - 0.12, z + 0.12, 4.0, WALL_H, rust, room)
	_omni(Vector3(-4.6, 2.6, 2.6), Color(1.0, 0.76, 0.5), 0.9, 6.0, room)
	_omni(Vector3(4.6, 2.6, 2.4), Color(0.6, 0.75, 0.68), 0.8, 6.0, room)
	_omni(Vector3(0.0, 2.2, 4.0), Color(0.9, 0.85, 0.72), 0.9, 7.0, room)

func _build_reception() -> void:
	var r := Node3D.new()
	r.name = "Reception"
	world.add_child(r)
	prop("metal_office_desk", Vector3(-4.3, 0.0, -3.95), 0.0, 1.0, r)
	prop("classic_laptop", Vector3(-4.85, 0.79, -4.05), 15.0, 1.0, r)
	prop("office_notepads", Vector3(-4.35, 0.79, -3.75), -10.0, 1.0, r)
	prop("binder_notebook", Vector3(-4.2, 0.79, -4.15), 30.0, 1.1, r)
	prop("desk_lamp_arm_01", Vector3(-5.1, 0.79, -4.15), 60.0, 1.0, r)
	_omni(Vector3(-4.9, 1.3, -3.6), Color(1.0, 0.74, 0.42), 1.6, 3.5, r)
	prop("GreenChair_01", Vector3(-4.4, 0.0, -4.35), 180.0, 1.0, r)
	var rad := Node3D.new()
	r.add_child(rad)
	rad.position = Vector3(-3.88, 0.79, -3.98)
	rad.rotation_degrees.y = 18.0
	rad.scale = Vector3.ONE * 1.35
	var wood := mat("worn_planks", 3.0, Color(0.55, 0.34, 0.2))
	box(Vector3(0.62, 0.36, 0.26), Vector3(0.0, 0.18, 0.0), wood, rad)
	box(Vector3(0.64, 0.03, 0.28), Vector3(0.0, 0.365, 0.0), mat("rusty_metal", 2.0, Color(0.3, 0.24, 0.2)), rad)
	box(Vector3(0.3, 0.25, 0.02), Vector3(-0.12, 0.17, 0.13), mat("metal_grate_rusty", 6.0, Color(0.35, 0.3, 0.25)), rad)
	_dial_mat = _emit_mat(Color(1.0, 0.62, 0.22), 2.2)
	box(Vector3(0.2, 0.08, 0.02), Vector3(0.17, 0.24, 0.13), _dial_mat, rad)
	_needle = box(Vector3(0.006, 0.07, 0.025), Vector3(0.12, 0.24, 0.135), _emit_mat(Color(1.0, 0.2, 0.1), 1.5), rad)
	var knob := mat("rusty_metal_02", 3.0, Color(0.2, 0.18, 0.16))
	for kx in [0.11, 0.23]:
		var k := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.04
		cm.height = 0.04
		k.mesh = cm
		k.material_override = knob
		rad.add_child(k)
		k.position = Vector3(kx, 0.1, 0.14)
		k.rotation_degrees.x = 90.0
	_pipe(Vector3(0.24, 0.36, -0.06), Vector3(0.45, 0.95, -0.12), 0.006, knob, rad)
	_radio_light = _omni(Vector3(-3.8, 1.35, -3.6), Color(1.0, 0.6, 0.25), 0.0, 2.6, r)
	var post := mat("rusty_metal_02", 2.0, Color(0.5, 0.48, 0.44))
	_pipe(Vector3(-2.7, 0.0, -3.95), Vector3(-2.7, 1.1, -3.95), 0.035, post, r)
	box(Vector3(0.36, 0.06, 0.36), Vector3(-2.7, 0.03, -3.95), post, r)
	box(Vector3(0.26, 0.32, 0.2), Vector3(-2.7, 1.25, -3.95), mat("rusty_metal", 1.5, Color(0.6, 0.12, 0.08)), r)
	var slip := box(Vector3(0.08, 0.002, 0.12), Vector3(-2.7, 1.2, -3.82), mat("grey_plaster_03", 3.0, Color(0.9, 0.86, 0.75)), r)
	slip.rotation_degrees.x = 70.0
	var notice := Label3D.new()
	notice.text = "TAKE A NUMBER\nWAIT TO BE SEATED"
	notice.font = _font
	notice.font_size = 48
	notice.pixel_size = 0.004
	notice.modulate = Color(0.85, 0.82, 0.7)
	notice.outline_size = 0
	r.add_child(notice)
	notice.position = Vector3(-2.7, 2.0, Z0 + 0.03)

func _build_display() -> void:
	var d := Node3D.new()
	d.name = "TicketDisplay"
	world.add_child(d)
	d.position = Vector3(0.0, 2.65, Z0 + 0.12)
	var frame := mat("rusty_metal", 1.0, Color(0.24, 0.22, 0.2))
	box(Vector3(2.7, 1.25, 0.22), Vector3.ZERO, frame, d)
	_disp_mat = _emit_mat(Color(0.25, 0.01, 0.0), 0.3)
	box(Vector3(2.45, 1.02, 0.04), Vector3(0.0, 0.0, 0.12), _disp_mat, d)
	for bx in [-1.25, 1.25]:
		for by in [-0.52, 0.52]:
			box(Vector3(0.08, 0.08, 0.05), Vector3(bx, by, 0.12), mat("rusty_metal", 2.0, Color(0.5, 0.45, 0.4)), d)
	var title := Label3D.new()
	title.text = "NOW SERVING"
	title.font = _font
	title.font_size = 56
	title.pixel_size = 0.005
	title.outline_size = 0
	title.shaded = false
	title.modulate = Color(2.6, 0.35, 0.2)
	d.add_child(title)
	title.position = Vector3(0.0, 0.33, 0.15)
	_serving = Label3D.new()
	_serving.text = "--"
	_serving.font = _font
	_serving.font_size = 140
	_serving.pixel_size = 0.005
	_serving.outline_size = 0
	_serving.shaded = false
	_serving.modulate = Color(3.0, 0.3, 0.15)
	d.add_child(_serving)
	_serving.position = Vector3(0.0, -0.13, 0.15)
	_serving_light = _omni(Vector3(0.0, 0.0, 1.0), Color(1.0, 0.15, 0.08), 1.0, 4.5, d)
	_pipe(Vector3(-0.9, 0.62, 0.0), Vector3(-0.8, 1.6, -0.08), 0.012, mat("rusty_metal", 2.0, Color(0.08, 0.08, 0.08)), d)
	_pipe(Vector3(0.9, 0.62, 0.0), Vector3(0.85, 1.6, -0.08), 0.012, mat("rusty_metal", 2.0, Color(0.08, 0.08, 0.08)), d)

func _build_dressing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in 30:
		var dc := Decal.new()
		dc.texture_albedo = _splat
		var sz: float = rng.randf_range(0.5, 2.4)
		dc.size = Vector3(sz, 0.5, sz * rng.randf_range(0.6, 1.0))
		var blood: bool = i % 4 == 0
		dc.modulate = Color(0.26, 0.03, 0.03, 0.9) if blood else Color(0.1, 0.09, 0.07, 0.85)
		dc.rotation.y = rng.randf() * TAU
		dc.cull_mask = 1
		world.add_child(dc)
		dc.position = Vector3(rng.randf_range(X0 + 0.6, X1 - 0.6), 0.1, rng.randf_range(Z0 + 0.6, Z1 - 0.6))
	for k in 8:
		var dc := Decal.new()
		dc.texture_albedo = _splat
		dc.size = Vector3(rng.randf_range(1.2, 2.4), 0.8, rng.randf_range(0.8, 2.2))
		dc.modulate = Color(0.12, 0.1, 0.06, 0.8) if k % 3 != 0 else Color(0.22, 0.03, 0.02, 0.85)
		dc.rotation_degrees.x = 90.0
		dc.cull_mask = 1
		world.add_child(dc)
		dc.position = Vector3(rng.randf_range(-5.5, 5.5), rng.randf_range(0.4, 3.4), Z0 + 0.02)
	for k in 6:
		var dc := Decal.new()
		dc.texture_albedo = _splat
		dc.size = Vector3(rng.randf_range(1.0, 2.0), 0.8, rng.randf_range(0.8, 2.4))
		dc.modulate = Color(0.12, 0.1, 0.06, 0.8)
		dc.cull_mask = 1
		world.add_child(dc)
		var lx: float = X0 + 0.02 if k % 2 == 0 else X1 - 0.02
		dc.position = Vector3(lx, rng.randf_range(0.4, 3.4), rng.randf_range(Z0 + 0.5, Z1 - 0.5))
		dc.rotation_degrees = Vector3(0.0, 0.0, -90.0 if k % 2 == 0 else 90.0)
	for z in [-2.3, -1.55, -0.8]:
		prop("GreenChair_01", Vector3(-5.55, 0.0, z), 90.0 + rng.randf_range(-5.0, 5.0), 1.0)
	prop("potted_plant_02", Vector3(-5.45, 0.0, 3.4), 30.0, 1.25)
	prop("metal_trash_can", Vector3(-5.55, 0.0, 4.25), 0.0, 1.0)
	prop("cardboard_box_01", Vector3(-5.5, 0.0, 5.25), 15.0, 1.1)
	prop("vintage_cabinet_01", Vector3(5.66, 0.0, -1.9), -90.0, 1.0)
	prop("medical_box", Vector3(5.6, 2.23, -2.1), -80.0, 1.0)
	prop("korean_fire_extinguisher_01", Vector3(5.72, 0.0, 3.2), 0.0, 1.0)
	prop("trashbag", Vector3(5.45, 0.0, 3.95), 40.0, 1.1)
	for z in [4.7, 5.3]:
		prop("SchoolChair_01", Vector3(5.5, 0.0, z), -90.0 + rng.randf_range(-12.0, 12.0), 1.0)
	var tipped := prop("GreenChair_01", Vector3(-4.7, 0.3, 5.1), 160.0, 1.0)
	if tipped:
		tipped.rotation_degrees.z = 86.0
	prop("WetFloorSign_01", Vector3(-3.4, 0.0, 5.25), 25.0, 1.0)
	prop("plastic_crate_01", Vector3(3.2, 0.0, 5.25), -15.0, 1.1)
	prop("utility_box_01", Vector3(-1.2, 0.0, Z0 + 0.25), 0.0, 1.0)
	prop("wall_clock", Vector3(-1.95, 2.95, Z0 + 0.02), 0.0, 2.8)
	prop("fire_alarm", Vector3(3.1, 1.7, Z0 + 0.05), 0.0, 1.5)
	prop("power_box_01", Vector3(1.9, 1.6, Z0 + 0.05), 0.0, 1.4)
	prop("security_light", Vector3(DOOR_X, 2.85, Z0 + 0.2), 0.0, 1.4)
	prop("security_camera_01", Vector3(X1 - 0.4, 3.7, Z0 + 0.5), -135.0, 1.6)
	prop("security_camera_01", Vector3(X0 + 0.4, 3.7, Z1 - 0.6), 45.0, 1.6)
	prop("industrial_caged_sconce", Vector3(X0 + 0.05, 2.5, -0.3), 90.0, 1.4)
	prop("industrial_caged_sconce", Vector3(X1 - 0.05, 2.5, 3.6), -90.0, 1.4)
	var bracket := mat("rusty_metal_02", 2.0, Color(0.4, 0.38, 0.35))
	box(Vector3(0.7, 0.05, 0.5), Vector3(2.75, 2.12, Z0 + 0.25), bracket)
	_pipe(Vector3(2.75, 2.1, Z0 + 0.05), Vector3(2.75, 1.7, Z0 + 0.02), 0.03, bracket, world)
	var tv := prop("Television_01", Vector3(2.75, 2.15, Z0 + 0.3), 0.0, 1.15)
	if tv:
		tv.rotation_degrees.x = 8.0
	var screen := box(Vector3(0.48, 0.34, 0.01), Vector3(2.68, 2.42, Z0 + 0.56), _emit_mat(Color(0.35, 0.55, 0.75), 0.9))
	screen.rotation_degrees.x = 8.0
	_tv_light = _omni(Vector3(2.75, 2.3, Z0 + 1.1), Color(0.45, 0.6, 0.9), 0.8, 4.0)

func _build_tubes() -> void:
	var chain := mat("rusty_metal", 2.0, Color(0.15, 0.14, 0.13))
	var spots := [[Vector3(-1.3, 3.75, 0.2), true, 20.0], [Vector3(1.4, 3.75, 0.7), false, -15.0], [Vector3(-4.1, 3.5, -3.2), false, 0.0]]
	for s in spots:
		var pos: Vector3 = s[0]
		var root := Node3D.new()
		world.add_child(root)
		root.position = pos
		root.rotation_degrees.y = s[2]
		prop("mounted_fluorescent_lights", Vector3.ZERO, 0.0, 1.5, root)
		var m := _emit_mat(Color(0.82, 1.0, 0.9), 4.0)
		for tz in [-0.16, 0.16]:
			var tube := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.03
			cm.height = 1.25
			tube.mesh = cm
			tube.material_override = m
			tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(tube)
			tube.position = Vector3(0.0, -0.08, tz)
			tube.rotation_degrees.z = 90.0
		for cx in [-0.55, 0.55]:
			_pipe(Vector3(cx, 0.0, 0.0), Vector3(cx, WALL_H - pos.y, 0.0), 0.008, chain, root)
		var sp := SpotLight3D.new()
		sp.light_color = Color(0.82, 1.0, 0.88)
		sp.light_energy = 9.0
		sp.spot_range = 8.0
		sp.spot_angle = 72.0
		sp.spot_attenuation = 0.7
		sp.shadow_enabled = bool(s[1])
		root.add_child(sp)
		sp.position = Vector3(0.0, -0.2, 0.0)
		sp.rotation_degrees.x = -90.0
		_tubes.append({"mat": m, "spot": sp, "bad": bool(s[1]), "t": 0.0, "on": true, "base": 9.0})

func _build_dust() -> void:
	var gp := GPUParticles3D.new()
	gp.amount = 60
	gp.lifetime = 7.0
	gp.local_coords = false
	gp.visibility_aabb = AABB(Vector3(-5, 0, -5), Vector3(10, 5, 10))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3.5, 1.6, 3.0)
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
	m.albedo_color = Color(0.9, 1.0, 0.9, 0.5)
	q.material = m
	gp.draw_pass_1 = q
	world.add_child(gp)
	gp.position = Vector3(0.0, 2.0, 0.4)

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
	noise.seed = 9
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

func _npc_tag(host: Node3D, text: String) -> void:
	var tag := Label3D.new()
	tag.text = text
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.0008
	tag.fixed_size = true
	tag.font_size = 20
	tag.outline_size = 8
	tag.modulate = Color(0.75, 0.75, 0.72)
	host.add_child(tag)
	tag.position = Vector3(0, 2.1, 0)

func _build_guard() -> void:
	_guard = LabCharacter.new()
	_guard.sex = "male"
	_guard.hat = "tophat"
	_guard.suit_color = Color(0.28, 0.3, 0.32)
	world.add_child(_guard)
	_guard.position = Vector3(DOOR_X, 0.0, Z0 + 0.75)
	_guard.rotation.y = atan2(C.x - _guard.position.x, C.z - _guard.position.z)
	_guard.play_loop("Idle")
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	_guard.skeleton.add_child(att)
	_guard_gun = _make_gun()
	att.add_child(_guard_gun)
	_guard_gun.transform = _gun_hand_xf
	_guard_mod = ArmPose.new()
	_guard.skeleton.add_child(_guard_mod)
	_guard_mod.poses = _arm_pose("Pistol_Idle", _guard.skeleton)
	_npc_tag(_guard, "ATTENDANT")

func _build_orderlies() -> void:
	for side in [-1.0, 1.0]:
		var o := LabCharacter.new()
		o.sex = "male" if side < 0.0 else "female"
		o.hat = "bucket" if side < 0.0 else "beanie"
		o.suit_color = Color(0.62, 0.64, 0.6)
		world.add_child(o)
		var home := Vector3(side * 5.35, 0.0, 2.45)
		o.position = home
		o.rotation.y = atan2(C.x - home.x, C.z - home.z)
		o.play_loop("Idle_FoldArms")
		o.anim.seek(randf() * 2.0, true)
		_npc_tag(o, "ORDERLY")
		_orderlies.append({"body": o, "home": home, "tw": null, "busy_until": 0.0})

func _ring_radius(n: int) -> float:
	return 0.0 if n <= 1 else maxf(0.75, 0.26 * float(n))

func _r_min() -> float:
	return _ring_r + 1.3 + (0.3 if active.size() <= 1 else 0.0)

func _slot(k: int, n: int, offset: float) -> Array:
	if n <= 1:
		return [C, offset]
	var a: float = offset + TAU * float(k) / float(n)
	return [C + Vector3(sin(a), 0.0, cos(a)) * _ring_radius(n), a]

func _build_chairs(n: int) -> void:
	for i in n:
		var kind: int = i % 3
		var s: Array = _slot(i, n, 0.0)
		var node := prop(KINDS[kind], s[0], rad_to_deg(float(s[1])), 1.0)
		if node == null:
			node = Node3D.new()
			world.add_child(node)
			node.position = s[0]
			node.rotation.y = float(s[1])
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.46, 0.6, 0.46)
		cs.shape = sh
		cs.position = Vector3(0.0, 0.3, -0.03)
		sb.add_child(cs)
		node.add_child(sb)
		chairs.append({"node": node, "kind": kind, "sb": sb})
		active.append(i)
	_ring_r = _ring_radius(n)

func _chair_yaw(ci: int) -> float:
	return (chairs[ci].node as Node3D).rotation.y

func _seat_root(ci: int) -> Vector3:
	var n: Node3D = chairs[ci].node
	var y := n.rotation.y
	var p := n.position + Vector3(sin(y), 0.0, cos(y)) * float(SEAT_OFF[int(chairs[ci].kind)])
	p.y = 0.0
	return p

func _occupant(ci: int) -> int:
	for id in seated:
		if int(seated[id]) == ci:
			return id
	return -1

func _build_line() -> void:
	_line = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.955
	tm.outer_radius = 1.0
	tm.rings = 64
	tm.ring_segments = 4
	_line.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.5, 0.12)
	m.roughness = 0.9
	m.albedo_texture = load(PH_TEX + "painted_concrete/diff.jpg") if ResourceLoader.exists(PH_TEX + "painted_concrete/diff.jpg") else null
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.0
	_line.material_override = m
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_line)
	_line.position = C + Vector3(0.0, 0.006, 0.0)
	var r := _r_min()
	_line.scale = Vector3(r, 0.04, r)

func _spawns() -> Array:
	var a: Array = []
	var n: int = NetworkManager.players.size()
	var r := _r_min() + 0.45
	for i in n:
		var ang: float = TAU * (float(i) + 0.5) / float(n)
		a.append(C + Vector3(sin(ang), 0.0, cos(ang)) * r)
	return a

func _setup_players() -> void:
	var ids: Array = players.keys()
	ids.sort()
	for i in ids.size():
		var id: int = ids[i]
		ticket[id] = 41 + i
		var p: LabPlayer3D = players[id]
		p.bounds = AABB(Vector3(-5.0, -5.0, -3.15), Vector3(10.0, 20.0, 7.85))
		p.speed = MUSIC_SPEED
		p.input_enabled = false
		p.bot_brain = _bot_brain.bind(id)
		var rel := p.position - C
		p.face(Vector3(rel.z, 0.0, -rel.x))
		p._label.text = "%s  #%d" % [p.display_name, int(ticket[id])]
		shove_ready[id] = 0.0
		lock_until[id] = 0.0
		_still[id] = 0.0
		_last[id] = p.position
		_warned[id] = false
		var wl := Label3D.new()
		wl.text = "KEEP MOVING"
		wl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		wl.no_depth_test = true
		wl.fixed_size = true
		wl.pixel_size = 0.0011
		wl.font_size = 24
		wl.outline_size = 10
		wl.modulate = Color("ff4a3a")
		wl.position = Vector3(0.0, 2.55, 0.0)
		wl.visible = false
		p.add_child(wl)
		_warn_l[id] = wl
		if p.is_bot:
			_bot[id] = {"react": randf_range(0.3, 0.62), "lane": randf_range(0.15, 0.55), "aggro": randf_range(0.25, 0.75),
				"sly": randf() < 0.5, "think": 0.0, "target": -1, "slow": 0.0}

func _build_radio_audio() -> void:
	if is_instance_valid(Fx._music):
		Fx._music.stream_paused = true
	_radio = AudioStreamPlayer.new()
	var s: AudioStream = load("res://assets/music/game2.ogg")
	if s is AudioStreamOggVorbis:
		s.loop = true
	_radio.stream = s
	_radio.volume_db = -11.0
	_radio.pitch_scale = 0.93
	add_child(_radio)

func _build_hud() -> void:
	hud_title("SEAT ASSIGNMENT  ·  when the radio stops, sit down")
	_round_label = Label.new()
	_round_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_round_label.position = Vector2(-220, 10)
	_round_label.size = Vector2(200, 30)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(_round_label, 26, Color("ffd34a"))
	hud.add_child(_round_label)
	_count_label = Label.new()
	_count_label.position = Vector2(16, 40)
	_style(_count_label, 18, Color("e8e2c8"))
	hud.add_child(_count_label)
	_big = _center_label(84, 0.42)
	_hint = _center_label(23, 0.88)
	_hint.text = "WASD  WALK AROUND THE CHAIRS   ·   SPACE  SHOVE\nkeep moving while the radio plays · when it stops, walk into a free chair"
	_hint.add_theme_color_override("font_color", Color("e8e2c8"))
	_update_counts()

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
	l.add_theme_constant_override("outline_size", 14)
	hud.add_child(l)
	return l

func _say(text: String, hex: String, hold: float, size: int = 84) -> void:
	if _big_tw:
		_big_tw.kill()
	_big.text = text
	_big.add_theme_font_size_override("font_size", size)
	_big.add_theme_color_override("font_color", Color(hex))
	_big.modulate.a = 1.0
	if hold > 0.0:
		_big_tw = create_tween()
		_big_tw.tween_interval(hold)
		_big_tw.tween_property(_big, "modulate:a", 0.0, 0.3)

func _update_counts() -> void:
	if _count_label:
		_count_label.text = "chairs: %d   ·   subjects: %d" % [active.size(), _living().size()]

func _living() -> Array:
	return players.keys().filter(func(i): return not dead.has(i))

func _standing() -> Array:
	return players.keys().filter(func(i): return not dead.has(i) and not seated.has(i))

func _process(delta: float) -> void:
	if _hint == null:
		return
	clock += delta
	if st == St.MUSIC or st == St.SCRAMBLE or st == St.PREP:
		_handle_input()
	_animate_set(delta)
	_update_camera(delta)

func _animate_set(delta: float) -> void:
	_flick_burst = maxf(_flick_burst - delta, 0.0)
	for t in _tubes:
		var on: bool = true
		t.t = float(t.t) - delta
		if _flick_burst > 0.0:
			on = randf() > 0.45
		elif bool(t.bad):
			if float(t.t) <= 0.0:
				t.on = not bool(t.on) if randf() < 0.6 else true
				t.t = randf_range(0.03, 0.16) if not bool(t.on) else randf_range(0.2, 2.6)
			on = bool(t.on)
		elif fmod(clock + float(t.base), 5.3) < 0.06:
			on = false
		var sp: SpotLight3D = t.spot
		var m: StandardMaterial3D = t.mat
		sp.light_energy = (float(t.base) + sin(clock * 50.0) * 0.25) if on else 0.4
		m.emission_energy_multiplier = 4.0 if on else 0.15
	var playing: bool = _radio != null and _radio.playing and not _radio.stream_paused
	if _dial_mat:
		_dial_mat.emission_energy_multiplier = (2.2 + sin(clock * 9.0) * 0.3) if playing else 0.12
		_radio_light.light_energy = 1.2 if playing else 0.0
		_needle.position.x = 0.12 + sin(clock * 0.7) * 0.05 if playing else _needle.position.x
	_tv_light.light_energy = 0.7 + sin(clock * 13.0) * 0.12 + (randf() * 0.3 if fmod(clock, 2.7) < 0.1 else 0.0)

func _update_camera(delta: float) -> void:
	var pos: Vector3
	var look: Vector3
	if _cam_mode == 1:
		pos = Vector3(0.0, 5.5, 7.1)
		look = C + Vector3(0.0, 0.3, -0.1)
	elif _cam_mode == 2:
		pos = Vector3(_focus.x * 0.8, 2.9, _focus.z + 4.6)
		look = _focus + Vector3(0.0, 0.9, 0.0)
	else:
		pos = Vector3(sin(clock * 0.12) * 0.7, 6.4, 8.4)
		look = C + Vector3(0.0, 0.5, 0.2)
	var k: float = 1.0 - exp(-(3.2 if _cam_mode == 1 else 2.0) * delta)
	camera.position = camera.position.lerp(pos, k)
	_look = _look.lerp(look, k)
	camera.look_at(_look, Vector3.UP)

func _handle_input() -> void:
	var me := local_player()
	if not me or dead.has(me.peer_id) or seated.has(me.peer_id):
		return
	var press := Input.is_physical_key_pressed(KEY_SPACE)
	if press and not _space_down:
		if NetworkManager.is_server():
			_try_shove(multiplayer.get_unique_id())
		else:
			_rpc_press.rpc_id(1)
	_space_down = press

@rpc("any_peer", "reliable")
func _rpc_press() -> void:
	if NetworkManager.is_server():
		_try_shove(multiplayer.get_remote_sender_id())

func _fwd(p: LabPlayer3D) -> Vector3:
	return Vector3(sin(p._target_yaw), 0.0, cos(p._target_yaw))

func _try_shove(id: int) -> void:
	if not (st == St.MUSIC or st == St.SCRAMBLE or st == St.PREP) or not players.has(id) or dead.has(id) or seated.has(id):
		return
	if clock < float(shove_ready[id]) or clock < float(lock_until[id]):
		return
	shove_ready[id] = clock + SHOVE_CD
	lock_until[id] = clock + 0.2
	var p: LabPlayer3D = players[id]
	var f := _fwd(p)
	var best := -1
	var best_d := SHOVE_REACH
	for o in _standing():
		if o == id:
			continue
		var to: Vector3 = players[o].position - p.position
		to.y = 0.0
		var d := to.length()
		if d > best_d:
			continue
		if d > 0.6 and f.dot(to / d) < 0.4:
			continue
		best = o
		best_d = d
	if best < 0:
		_rpc_shove.rpc(id, -1, p.position + f * LUNGE, Vector3.ZERO)
		return
	var v: LabPlayer3D = players[best]
	var to_v: Vector3 = v.position - p.position
	to_v.y = 0.0
	var dir: Vector3 = to_v.normalized() if to_v.length() > 0.05 else f
	if not p.is_bot:
		dir = (dir * 0.6 + f * 0.4).normalized()
	lock_until[best] = clock + 0.55
	_rpc_shove.rpc(id, best, p.position + dir * maxf(best_d - 0.6, 0.0), v.position + dir * KNOCK)

func _kill_push(id: int) -> void:
	if _push_tw.has(id):
		var old: Tween = _push_tw[id]
		if old and old.is_valid():
			old.kill()
		_push_tw.erase(id)

func _tween_move(id: int, to: Vector3, t: float) -> void:
	var p: LabPlayer3D = players[id]
	var dest := Vector3(clampf(to.x, p.bounds.position.x, p.bounds.end.x), p.position.y, clampf(to.z, p.bounds.position.z, p.bounds.end.z))
	_kill_push(id)
	var tw := create_tween()
	tw.tween_property(p, "position", dest, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_push_tw[id] = tw

func _lock_input(p: LabPlayer3D, t: float) -> void:
	if not p.is_local_human():
		return
	p.input_enabled = false
	get_tree().create_timer(t).timeout.connect(func() -> void:
		if is_instance_valid(p) and not dead.has(p.peer_id) and not seated.has(p.peer_id) and (st == St.MUSIC or st == St.SCRAMBLE or st == St.PREP):
			p.input_enabled = true)

@rpc("authority", "call_local", "reliable")
func _rpc_shove(a: int, v: int, lunge_to: Vector3, push_to: Vector3) -> void:
	var pa: LabPlayer3D = players[a]
	if dead.has(a) or seated.has(a):
		return
	pa.face(lunge_to - pa.position)
	pa.body.play_action("Shield_Dash", 0.05, 1.6)
	Fx.sfx("whoosh", pa.position, -4.0, 1.1)
	if pa.is_multiplayer_authority():
		_tween_move(a, lunge_to, 0.16)
	_lock_input(pa, 0.2)
	if v < 0 or dead.has(v) or seated.has(v):
		return
	var pv: LabPlayer3D = players[v]
	pv.face(pa.position - pv.position)
	pv.body.play_action("Hit_Knockback", 0.05, 1.2)
	Fx.sfx("hit", pv.position, -1.0, 1.0)
	Fx.shake(0.18)
	if pv.is_multiplayer_authority():
		_tween_move(v, push_to, 0.38)
	_lock_input(pv, 0.55)

func _physics_process(delta: float) -> void:
	if _hint == null:
		return
	if st == St.MUSIC:
		var rmin := _r_min()
		for id in _standing():
			var p: LabPlayer3D = players[id]
			if not p.is_multiplayer_authority():
				continue
			var rel := p.position - C
			rel.y = 0.0
			if rel.length() < rmin:
				var dir := rel.normalized() if rel.length() > 0.01 else Vector3.BACK
				p.position = C + dir * rmin + Vector3(0.0, p.position.y, 0.0)
				_kill_push(id)
	if not NetworkManager.is_server():
		return
	if st == St.MUSIC:
		_check_moving(delta)
	elif st == St.SCRAMBLE:
		_check_sits()

func _check_moving(delta: float) -> void:
	for id in _standing():
		var p: LabPlayer3D = players[id]
		var last: Vector3 = _last[id]
		var spd := Vector2(p.position.x - last.x, p.position.z - last.z).length() / maxf(delta, 0.0001)
		_last[id] = p.position
		if spd < 0.5 and clock >= float(lock_until[id]):
			_still[id] = float(_still[id]) + delta
		else:
			_still[id] = maxf(0.0, float(_still[id]) - delta * 2.0)
			if float(_still[id]) <= 0.0:
				_warned[id] = false
		if float(_still[id]) > STILL_WARN and not bool(_warned[id]):
			_warned[id] = true
			_rpc_warn.rpc(id)
		if float(_still[id]) > STILL_SHOOT and not _guard_busy:
			_still[id] = 0.0
			_warned[id] = false
			lock_until[id] = clock + 1.0
			var miss := Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5))
			_rpc_warn_shot.rpc(id, p.position + miss)

func _check_sits() -> void:
	for id in _standing():
		var p: LabPlayer3D = players[id]
		var best := -1
		var best_d := SIT_REACH
		for ci in active:
			if _occupant(ci) != -1:
				continue
			var d := Vector2(p.position.x - _seat_root(ci).x, p.position.z - _seat_root(ci).z).length()
			if d < best_d:
				best_d = d
				best = ci
		if best >= 0:
			seated[id] = best
			_rpc_sit.rpc(id, best)

@rpc("authority", "call_local", "reliable")
func _rpc_warn(id: int) -> void:
	var wl: Label3D = _warn_l[id]
	wl.visible = true
	Fx.sfx("buzzer", players[id].position, -6.0, 1.5)
	get_tree().create_timer(1.3).timeout.connect(func() -> void:
		if is_instance_valid(wl):
			wl.visible = false)
	var me := local_player()
	if me and me.peer_id == id:
		_say("KEEP MOVING", "ff4a3a", 0.9, 56)

@rpc("authority", "call_local", "reliable")
func _rpc_warn_shot(id: int, at: Vector3) -> void:
	if dead.has(id):
		return
	_guard_busy = true
	var p: LabPlayer3D = players[id]
	_lock_input(p, 1.0)
	var tw := create_tween()
	_guard_shot_steps(tw, at, func() -> void:
		Fx.sparks(world, at + Vector3(0.0, 0.05, 0.0))
		Fx.sfx("hit", at, -6.0, 1.6)
		if not dead.has(id) and not seated.has(id):
			p.body.play_action("Hit_Head", 0.05, 1.3))
	tw.tween_interval(0.5)
	tw.tween_callback(_guard_rest)

func _guard_shot_steps(tw: Tween, aim: Vector3, effect: Callable) -> void:
	tw.tween_callback(func() -> void:
		var to: Vector3 = aim - _guard.position
		var t2 := create_tween()
		t2.tween_property(_guard, "rotation:y", _guard.rotation.y + angle_difference(_guard.rotation.y, atan2(to.x, to.z)), 0.2))
	tw.tween_interval(0.2)
	tw.tween_callback(func() -> void:
		_guard_mod.active = false
		_guard.anim.play("Pistol_Shoot", 0.05))
	tw.tween_interval(0.17)
	tw.tween_callback(func() -> void:
		_fire(_guard_gun, aim)
		effect.call())

func _guard_rest() -> void:
	_guard_mod.active = true
	_guard.anim.play("Idle", 0.3)
	_guard_busy = false

func _fire(gun: Node3D, end: Vector3) -> void:
	var from: Vector3 = gun.global_transform * MUZZLE
	Fx.sfx("gunshot", from, 2.0)
	Fx.shake(0.4)
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
	if from.distance_to(end) > 0.05:
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
	tr.scale = Vector3(1.0, 1.0, maxf(len, 0.01))
	var ttw := tr.create_tween()
	ttw.tween_property(tm, "albedo_color:a", 0.0, 0.2)
	ttw.tween_callback(tr.queue_free)

func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	_rpc_say.rpc("TAKE A SEAT", "e8e2c8", 1.2, 72)
	await get_tree().create_timer(1.4).timeout
	var n := 0
	while n < ROUNDS and _living().size() > 1 and clock < TIME_LIMIT - 9.5:
		n += 1
		await _play_round(n)
	var living := _living()
	var msg := "NOBODY LEFT"
	if living.size() == 1:
		msg = "#%d  %s  KEEPS THE SEAT" % [int(ticket[living[0]]), String(players[living[0]].display_name).to_upper()]
	elif living.size() > 1:
		msg = "TIME.  %d STILL SEATED" % living.size()
	_rpc_end.rpc(msg)
	await get_tree().create_timer(2.4).timeout
	if not _ended:
		_ended = true
		finished.emit(_placement())

func _placement() -> Array:
	var out: Array = _living()
	for i in range(dead.size() - 1, -1, -1):
		if not out.has(dead[i]):
			out.append(dead[i])
	return out

func _play_round(n: int) -> void:
	var want: int = maxi(1, _living().size() - 1)
	var remove: Array = []
	if active.size() > want:
		var empty: Array = active.filter(func(ci): return _occupant(ci) == -1)
		var full: Array = active.filter(func(ci): return _occupant(ci) != -1)
		empty.shuffle()
		full.shuffle()
		var pool: Array = empty + full
		for k in active.size() - want:
			remove.append(pool[k])
	var keep: Array = active.filter(func(ci): return not remove.has(ci))
	keep.sort_custom(func(a, b): return _angle_of(a) < _angle_of(b))
	var offset: float = _angle_of(keep[0]) if keep.size() > 1 else randf() * TAU
	_rpc_prep.rpc(n, remove, keep, offset)
	await get_tree().create_timer(1.0 if n == 1 else 1.55).timeout
	if _living().size() <= 1:
		return
	_rpc_music.rpc()
	var dur: float = randf_range(4.0, 6.0) if n == 1 else randf_range(3.0, 5.6)
	await get_tree().create_timer(dur).timeout
	_rpc_cut.rpc()
	var t0 := clock
	var full_t := -1.0
	while clock - t0 < SIT_WINDOW:
		if full_t < 0.0 and active.all(func(ci): return _occupant(ci) != -1):
			full_t = clock
		if full_t >= 0.0 and clock - full_t > 0.55:
			break
		await get_tree().process_frame
	var standing := _standing()
	for id in standing:
		if not dead.has(id):
			dead.append(id)
	_rpc_exec.rpc(standing)
	await get_tree().create_timer(0.75 * float(standing.size()) + 1.1).timeout

func _angle_of(ci: int) -> float:
	var p: Vector3 = (chairs[ci].node as Node3D).position - C
	return fposmod(atan2(p.x, p.z), TAU)

@rpc("authority", "call_local", "reliable")
func _rpc_say(text: String, hex: String, hold: float, size: int) -> void:
	_say(text, hex, hold, size)

@rpc("authority", "call_local", "reliable")
func _rpc_prep(n: int, remove: Array, keep: Array, offset: float) -> void:
	st = St.PREP
	round_no = n
	_cam_mode = 0
	_round_label.text = "ROUND %d / %d" % [n, ROUNDS]
	var was_seated: Dictionary = seated.duplicate()
	seated.clear()
	active = keep.duplicate()
	_ring_r = _ring_radius(active.size())
	var rmin := _r_min()
	var ltw := create_tween()
	ltw.tween_property(_line, "scale", Vector3(rmin, 0.04, rmin), 0.9).set_delay(0.4)
	for id in was_seated:
		_stand_up(id, rmin)
	for id in _standing():
		var p: LabPlayer3D = players[id]
		p.speed = MUSIC_SPEED
		if was_seated.has(id):
			continue
		if p.is_local_human():
			p.input_enabled = true
		if p.is_multiplayer_authority():
			var rel := p.position - C
			rel.y = 0.0
			if rel.length() < rmin + 0.1:
				var dir := rel.normalized() if rel.length() > 0.01 else Vector3.BACK
				_tween_move(id, C + dir * (rmin + 0.35), 0.6)
	var dly: float = 0.0 if n == 1 else 0.75
	for k in keep.size():
		var ci: int = keep[k]
		var s: Array = _slot(k, keep.size(), offset)
		var node: Node3D = chairs[ci].node
		var tw := create_tween().set_parallel(true)
		tw.tween_property(node, "position", s[0], 0.7).set_delay(dly).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(node, "rotation:y", node.rotation.y + angle_difference(node.rotation.y, float(s[1])), 0.7).set_delay(dly)
	if n > 1 and not keep.is_empty():
		get_tree().create_timer(dly).timeout.connect(func() -> void: Fx.sfx("whoosh", C, -12.0, 0.4))
	for ci in remove:
		_drag_away(ci)
	_update_counts()
	_serving.modulate = Color(3.0, 0.3, 0.15)
	_say("ROUND %d" % n, "e8e2c8", 0.8, 64)
	if n == 1:
		var th := create_tween()
		th.tween_interval(7.0)
		th.tween_property(_hint, "modulate:a", 0.0, 0.8)

func _stand_up(id: int, rmin: float) -> void:
	var p: LabPlayer3D = players[id]
	var seat := p.position
	p.alive = true
	p.velocity = Vector3.ZERO
	p.body._action_busy = false
	p.body.play_action("Sitting_Exit", 0.12, 1.5)
	lock_until[id] = clock + 1.0
	_lock_input(p, 1.0)
	if p.is_multiplayer_authority():
		var rel := seat - C
		rel.y = 0.0
		var dir := rel.normalized() if rel.length() > 0.05 else Vector3(sin(p._target_yaw), 0.0, cos(p._target_yaw))
		var dest := C + dir * (rmin + 0.4)
		_kill_push(id)
		var tw := create_tween()
		tw.tween_interval(0.55)
		tw.tween_property(p, "position", dest, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		_push_tw[id] = tw

func _drag_away(ci: int) -> void:
	var node: Node3D = chairs[ci].node
	var sb: StaticBody3D = chairs[ci].sb
	if is_instance_valid(sb):
		sb.queue_free()
	var side: int = 0 if node.position.x < C.x else 1
	var o: Dictionary = _orderlies[side]
	var body: LabCharacter = o.body
	var home: Vector3 = o.home
	var slot_i: int = int(_pile_n[side]) % PILE_SLOTS.size()
	_pile_n[side] = int(_pile_n[side]) + 1
	var sl: Vector3 = PILE_SLOTS[slot_i]
	var pile := Vector3((-5.45 if side == 0 else 5.45) + sl.x * (1.0 if side == 0 else -1.0), sl.y, sl.z)
	var start_delay: float = maxf(0.0, float(o.busy_until) - clock)
	var chair_pos := node.position
	var away := (pile - chair_pos)
	away.y = 0.0
	var dn := away.normalized() if away.length() > 0.05 else Vector3.RIGHT
	var grab := chair_pos - dn * 0.55
	var d1: float = maxf(0.4, body.position.distance_to(grab) / 4.0)
	var d2: float = maxf(0.6, Vector2(chair_pos.x - pile.x, chair_pos.z - pile.z).length() / 2.6)
	var d3: float = maxf(0.4, pile.distance_to(home) / 2.4)
	o.busy_until = clock + start_delay + d1 + d2 + d3 + 0.4
	var tw := create_tween()
	if start_delay > 0.0:
		tw.tween_interval(start_delay)
	tw.tween_callback(func() -> void:
		body.play_loop("Jog_Fwd")
		var to := grab - body.position
		body.rotation.y = atan2(to.x, to.z))
	tw.tween_property(body, "position", grab, d1)
	tw.tween_callback(func() -> void:
		body.play_loop("Push")
		body.rotation.y = atan2(dn.x, dn.z)
		Fx.sfx("whoosh", chair_pos, -8.0, 0.35)
		Fx.sfx("step", chair_pos, -4.0, 0.5))
	var flat_pile := Vector3(pile.x, 0.0, pile.z)
	tw.set_parallel(true)
	tw.tween_property(node, "position", flat_pile + Vector3(0.0, pile.y, 0.0), d2)
	tw.tween_property(body, "position", flat_pile - dn * 0.55, d2)
	tw.tween_property(node, "rotation", Vector3(deg_to_rad(80.0) if pile.y > 0.1 else 0.0, randf() * TAU, deg_to_rad(randf_range(-10.0, 10.0))), d2)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		Fx.sfx("hit", flat_pile, -6.0, 0.55)
		body.play_loop("Walk")
		var to := home - body.position
		body.rotation.y = atan2(to.x, to.z))
	tw.tween_property(body, "position", home, d3)
	tw.tween_callback(func() -> void:
		body.play_loop("Idle_FoldArms")
		body.rotation.y = atan2(C.x - home.x, C.z - home.z))

@rpc("authority", "call_local", "reliable")
func _rpc_music() -> void:
	st = St.MUSIC
	_cam_mode = 0
	for id in _standing():
		var p: LabPlayer3D = players[id]
		p.speed = MUSIC_SPEED
		_still[id] = 0.0
		_last[id] = p.position
		_warned[id] = false
		if p.is_local_human():
			p.input_enabled = true
	Fx.sfx("click", Vector3(-3.6, 1.0, -3.9), -2.0, 0.8)
	Fx.sfx("hum", null, -18.0, 1.7)
	if _radio:
		if _radio.playing:
			_radio.stream_paused = false
		else:
			_radio.play(randf_range(0.0, 20.0))
	_say("WALK", "e2c84b", 0.6, 64)

@rpc("authority", "call_local", "reliable")
func _rpc_cut() -> void:
	st = St.SCRAMBLE
	_cut_t = clock
	_cam_mode = 1
	if _radio:
		_radio.stream_paused = true
	Fx.sfx("click", Vector3(-3.6, 1.0, -3.9), 4.0, 0.55)
	Fx.sfx("hum", null, -10.0, 0.5)
	_flick_burst = 0.35
	Fx.shake(0.12)
	for id in _standing():
		players[id].speed = RUSH_SPEED
		(_warn_l[id] as Label3D).visible = false
	_say("SIT!", "ff3b2e", 1.0, 110)

@rpc("authority", "call_local", "reliable")
func _rpc_sit(id: int, ci: int) -> void:
	seated[id] = ci
	var p: LabPlayer3D = players[id]
	_kill_push(id)
	p.alive = false
	p.velocity = Vector3.ZERO
	if p.is_local_human():
		p.input_enabled = false
	var seat := _seat_root(ci)
	var yaw := _chair_yaw(ci)
	p.position = seat
	p._target = seat
	p._target_yaw = yaw
	p.body.rotation.y = yaw
	p.body._action_busy = false
	p.body._locomotion = ""
	p.body.anim.play("Sitting_Enter", 0.1, 1.7)
	p.body.anim.queue("Sitting_Idle")
	(_warn_l[id] as Label3D).visible = false
	Fx.sfx("hit", seat, -8.0, 0.5)
	Fx.sfx("step", seat, -6.0, 0.7)
	_update_counts()
	var me := local_player()
	if me and me.peer_id == id:
		_say("SEATED", "8fe36a", 0.8, 64)

@rpc("authority", "call_local", "reliable")
func _rpc_exec(ids: Array) -> void:
	st = St.EXEC
	for id in players:
		var p: LabPlayer3D = players[id]
		p.input_enabled = false
		(_warn_l[id] as Label3D).visible = false
	for id in ids:
		if not dead.has(id):
			dead.append(id)
		var p: LabPlayer3D = players[id]
		p.face(_guard.position - p.position)
		p.body.play_action("Idle_No", 0.1)
	if ids.is_empty():
		_say("EVERYONE SEATED", "e8e2c8", 1.0, 56)
		return
	_focus = players[ids[0]].position
	_cam_mode = 2
	var names := PackedStringArray()
	for id in ids:
		names.append("#%d" % int(ticket[id]))
	_say("STANDING:  " + "  ".join(names), "ff6a5a", 1.6, 56)
	var me := local_player()
	if me and ids.has(me.peer_id):
		_say("YOU'RE STANDING", "ff3b2e", 1.6, 72)
	_guard_busy = true
	var tw := create_tween()
	tw.tween_interval(0.35)
	for id in ids:
		var p: LabPlayer3D = players[id]
		tw.tween_callback(func() -> void: _focus = p.position)
		_guard_shot_steps(tw, p.position + Vector3(0.0, 1.25, 0.0), func() -> void: _execute(id))
		tw.tween_interval(0.3)
	tw.tween_interval(0.3)
	tw.tween_callback(_guard_rest)

func _execute(id: int) -> void:
	var p: LabPlayer3D = players[id]
	_kill_push(id)
	p.set_alive(false)
	p.velocity = Vector3.ZERO
	p.collision_layer = 0
	p.collision_mask = 0
	p.body.die("Death01")
	Fx.blood(world, p.position + Vector3(0.0, 1.2, 0.0), 90)
	Fx.shake(0.55)
	_serving.text = "%d" % int(ticket[id])
	_serving.modulate = Color(4.0, 0.5, 0.25)
	var dtw := create_tween()
	dtw.tween_property(_serving, "modulate", Color(3.0, 0.3, 0.15), 0.6)
	_disp_mat.emission_energy_multiplier = 1.2
	var mtw := create_tween()
	mtw.tween_property(_disp_mat, "emission_energy_multiplier", 0.3, 0.7)
	_serving_light.light_energy = 3.0
	var ltw := create_tween()
	ltw.tween_property(_serving_light, "light_energy", 1.0, 0.7)
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		Fx.sfx("beep", Vector3(0.0, 2.6, Z0 + 0.5), -2.0, 1.6)
		get_tree().create_timer(0.22).timeout.connect(func() -> void: Fx.sfx("beep", Vector3(0.0, 2.6, Z0 + 0.5), -2.0, 1.2)))
	_update_counts()

@rpc("authority", "call_local", "reliable")
func _rpc_end(text: String) -> void:
	st = St.DONE
	_cam_mode = 0
	if _radio:
		_radio.stop()
	for id in players:
		players[id].input_enabled = false
	_say(text, "e2c84b", 0.0, 52)
	Fx.sfx("buzzer", null, -6.0, 1.3)

func _bot_brain(delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	if dead.has(id) or seated.has(id) or clock < float(lock_until[id]):
		return Vector3.ZERO
	if not (st == St.PREP or st == St.MUSIC or st == St.SCRAMBLE):
		return Vector3.ZERO
	var b: Dictionary = _bot[id]
	var rel := p.position - C
	rel.y = 0.0
	var r := rel.length()
	var radial := rel / r if r > 0.01 else Vector3.BACK
	var tangent := Vector3(radial.z, 0.0, -radial.x)
	if st == St.SCRAMBLE and clock - _cut_t >= float(b.react):
		return _bot_rush(delta, id, p, b, r, radial, tangent)
	var want_r := _r_min() + float(b.lane)
	var dir := tangent + radial * clampf((want_r - r) * 1.4, -1.0, 1.0)
	var factor := 1.0
	b.slow = float(b.slow) - delta
	if bool(b.sly) and st == St.MUSIC:
		for ci in active:
			var to_c := _seat_root(ci) - p.position
			to_c.y = 0.0
			if to_c.length() < 1.1:
				factor = 0.6
				break
	if st == St.MUSIC:
		b.think = float(b.think) - delta
		if float(b.think) <= 0.0:
			b.think = randf_range(0.25, 0.45)
			for o in _standing():
				if o == id:
					continue
				var to: Vector3 = players[o].position - p.position
				to.y = 0.0
				if to.length() < 0.95 and to.normalized().dot(tangent) > 0.5 and clock >= float(shove_ready[id]) and randf() < float(b.aggro) * 0.12:
					p.face(to)
					_try_shove(id)
					return Vector3.ZERO
	return dir.normalized() * factor

func _bot_rush(delta: float, id: int, p: LabPlayer3D, b: Dictionary, r: float, radial: Vector3, tangent: Vector3) -> Vector3:
	b.think = float(b.think) - delta
	var t: int = int(b.target)
	if float(b.think) <= 0.0 or t < 0 or not active.has(t) or _occupant(t) != -1:
		b.think = randf_range(0.1, 0.18)
		t = -1
		var best_s := INF
		for ci in active:
			if _occupant(ci) != -1:
				continue
			var mine := p.position.distance_to(_seat_root(ci))
			var s := mine + randf() * 0.25
			for o in _standing():
				if o != id and players[o].position.distance_to(_seat_root(ci)) < mine - 0.2:
					s += 0.7
			if s < best_s:
				best_s = s
				t = ci
		b.target = t
		if t >= 0:
			for o in _standing():
				if o == id:
					continue
				var to: Vector3 = players[o].position - p.position
				to.y = 0.0
				if to.length() < 1.1 and players[o].position.distance_to(_seat_root(t)) < 1.7 and clock >= float(shove_ready[id]) and randf() < float(b.aggro) * 0.4:
					p.face(to)
					_try_shove(id)
					return Vector3.ZERO
	if t < 0:
		return (tangent * 0.6 - radial * 0.3).normalized()
	var goal := _seat_root(t)
	var gr := goal - C
	gr.y = 0.0
	var ga: float = atan2(gr.x, gr.z)
	var ma: float = atan2(radial.x, radial.z)
	var diff: float = angle_difference(ma, ga)
	if absf(diff) > 0.6 and r > _ring_r + 0.2:
		var keep_r := maxf(_ring_r + 1.0, gr.length() + 0.6)
		var d := tangent if diff > 0.0 else -tangent
		return (d + radial * clampf((keep_r - r) * 1.5, -1.0, 1.0)).normalized()
	var v := goal - p.position
	v.y = 0.0
	if v.length() < 0.05:
		return Vector3.ZERO
	return v.normalized()
