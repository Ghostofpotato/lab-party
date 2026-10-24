extends ArenaMinigame3D
## Table Manners: subjects sit at a basement dining table, each with a plate of
## peas, watched by an armed boss at the head of the table. Mash SPACE to eat a
## spoonful. Eating too fast fills the red choke meter; at full you choke and die
## face down in your plate. Eat only while the boss has his back turned: he
## clicks his pistol and turns (HE'S TURNING), then watches, and anyone who takes
## a bite while he watches is shot dead. First to clear the plate wins, then most
## peas eaten; the dead place last.

const TIME_LIMIT: float = 40.0
const PEAS: int = 40
const PEAS_PER_BITE: int = 3
const CHOKE_PER_BITE: float = 0.15
const CHOKE_FAST_BONUS: float = 0.09
const FAST_GAP: float = 0.22
const CHOKE_DRAIN: float = 0.26
const TURN_T: float = 0.95
const WATCH_GRACE: float = 0.12
const TABLE_TOP: float = 0.745
const TABLE_HALF_W: float = 0.695
const BOSS_POS := Vector3(0.0, 0.0, -1.75)
const SLUMP := {"spine_02": 0.55, "spine_03": 0.45, "neck_01": 0.35, "Head": 0.3, "upperarm_l": -0.5, "upperarm_r": -0.5}
const BAR_PX: int = 100
const SPOON_REACH: float = 0.2
const MOUTH := Vector3(0.0, 0.035, 0.115)
const GUN_BASIS := Basis(Vector3(0.03, 0.97, -0.24), Vector3(-0.03, 0.24, 0.97), Vector3(1.0, -0.02, 0.03))
const FaceWrap := preload("res://minigames/table_manners/face_wrap.gd")
const MUZZLE := Vector3(0.12, 0.032, 0.0)

enum St { COUNTDOWN, EAT, DONE }
enum Boss { AWAY, TURN, WATCH }

class SpoonArm extends SkeletonModifier3D:
	var upper: int
	var lower: int
	var hand: int
	var head: int
	var clav: int
	var thumb_axis: Vector3
	var plate: Vector3
	var bite_t: float = 10.0
	var bowl: Vector3
	var aim: Vector3
	var grip: Dictionary = {}
	func setup(sk: Skeleton3D, plate_local: Vector3) -> void:
		clav = sk.find_bone("clavicle_r")
		upper = sk.find_bone("upperarm_r")
		lower = sk.find_bone("lowerarm_r")
		hand = sk.find_bone("hand_r")
		head = sk.find_bone("Head")
		var hr := sk.get_bone_global_rest(hand)
		var th := hr.affine_inverse() * sk.get_bone_global_rest(sk.find_bone("thumb_01_r")).origin
		thumb_axis = Vector3(th.x, 0.0, th.z).normalized()
		for f in ["index", "middle", "ring", "pinky", "thumb"]:
			for j in [1, 2, 3]:
				var bi := sk.find_bone("%s_0%d_r" % [f, j])
				if bi < 0:
					continue
				var ang: float = [0.0, 0.95, 1.15, 0.9][j] * (0.45 if f == "thumb" else (0.9 if f == "index" else 1.0))
				grip[bi] = sk.get_bone_rest(bi).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, ang)
		plate = plate_local
		bowl = _rest_bowl()
		aim = _rest_dir()
	func bite() -> void:
		bite_t = 0.0
	func _rest_bowl() -> Vector3:
		return plate + Vector3(-0.05, 0.075, -0.07)
	func _rest_dir() -> Vector3:
		return Vector3(0.35, -0.3, 1.0).normalized()
	func advance(delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		bite_t += delta
		var mouth := sk.get_bone_global_pose(head) * MOUTH
		var scoop_b := plate + Vector3(-0.02, 0.035, 0.0)
		var scoop_d := Vector3(0.25, -0.75, 1.0).normalized()
		var mouth_d := Vector3(0.4, 0.55, -1.0).normalized()
		var rest_b := _rest_bowl()
		var rest_d := _rest_dir()
		var want_b := rest_b
		var want_d := rest_d
		var s := bite_t
		if s < 0.12:
			var k := smoothstep(0.0, 0.12, s)
			want_b = rest_b.lerp(scoop_b, k)
			want_d = rest_d.slerp(scoop_d, k)
		elif s < 0.34:
			var k := smoothstep(0.12, 0.34, s)
			var mid := scoop_b.lerp(mouth, k) + Vector3(0.0, sin(k * PI) * 0.06, 0.0)
			want_b = mid
			want_d = scoop_d.slerp(mouth_d, k)
		elif s < 0.44:
			want_b = mouth
			want_d = mouth_d
		elif s < 0.7:
			var k := smoothstep(0.44, 0.7, s)
			want_b = mouth.lerp(rest_b, k)
			want_d = mouth_d.slerp(rest_d, k)
		var f := 1.0 - exp(-delta * 22.0)
		bowl = bowl.lerp(want_b, f)
		aim = aim.slerp(want_d, f).normalized()
	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or influence <= 0.001:
			return
		var pc := sk.get_bone_global_pose(clav)
		var pu := sk.get_bone_global_pose(upper)
		var pl := sk.get_bone_global_pose(lower)
		var ph := sk.get_bone_global_pose(hand)
		var target := bowl - aim * SPOON_REACH
		var a := pu.origin
		var b := pl.origin
		var c := ph.origin
		var l1 := a.distance_to(b)
		var l2 := b.distance_to(c)
		var d := clampf(a.distance_to(target), absf(l1 - l2) + 0.01, l1 + l2 - 0.005)
		var dir := (target - a).normalized()
		var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(0.0, l1 * l1 - along * along))
		var pole := Vector3(-1.0, -1.1, -0.35)
		var perp := (pole - dir * pole.dot(dir)).normalized()
		var elbow := a + dir * along + perp * h
		var r1 := Basis(Quaternion((b - a).normalized(), (elbow - a).normalized()))
		var b2 := a + r1 * (b - a)
		var c2 := b2 + r1 * (c - b)
		var r2 := Basis(Quaternion((c2 - b2).normalized(), (target - b2).normalized()))
		var ug := r1 * pu.basis.orthonormalized()
		var lg := r2 * r1 * pl.basis.orthonormalized()
		var hg0 := r2 * r1 * ph.basis.orthonormalized()
		var r3 := Basis(Quaternion((hg0 * Vector3.UP).normalized(), aim))
		var hg := r3 * hg0
		var want_thumb := Vector3(0.35, 1.0, 0.0)
		want_thumb = (want_thumb - aim * want_thumb.dot(aim)).normalized()
		var cur_thumb := hg * thumb_axis
		cur_thumb = (cur_thumb - aim * cur_thumb.dot(aim)).normalized()
		var twist := cur_thumb.signed_angle_to(want_thumb, aim)
		hg = Basis(aim, twist) * hg
		var w := influence
		var lu := (pc.basis.orthonormalized().inverse() * ug).get_rotation_quaternion()
		var ll := (ug.inverse() * lg).get_rotation_quaternion()
		var lh := (lg.inverse() * hg).get_rotation_quaternion()
		sk.set_bone_pose_rotation(upper, sk.get_bone_pose_rotation(upper).slerp(lu, w))
		sk.set_bone_pose_rotation(lower, sk.get_bone_pose_rotation(lower).slerp(ll, w))
		sk.set_bone_pose_rotation(hand, sk.get_bone_pose_rotation(hand).slerp(lh, w))
		for bi in grip:
			sk.set_bone_pose_rotation(bi, sk.get_bone_pose_rotation(bi).slerp(grip[bi], w))

var st: St = St.COUNTDOWN
var clock: float = 0.0
var seats: Dictionary = {}
var eaten: Dictionary = {}
var choke: Dictionary = {}
var last_bite: Dictionary = {}
var dead_order: Array = []
var finish_order: Array = []
var boss_state: Boss = Boss.WATCH
var boss_from: float = 0.0
var _boss_until: float = 0.0
var _sync_t: float = 0.0
var _space_down: bool = false
var _ended: bool = false
var _bot: Dictionary = {}

var _boss: LabCharacter
var _boss_shades: Node
var _boss_masked: bool = false
var _face_local: bool = false
var _face_bytes := PackedByteArray()
var _face_waiting: Array[int] = []
var _boss_gun: Node3D
var _boss_tw: Tween
var _boss_lamp: OmniLight3D
var _status: Label
var _lib: AnimationLibrary
var _pea_mesh: SphereMesh
var _table_col: GPUParticlesCollisionBox3D
var _bar_tex: ImageTexture
var _big: Label
var _hint: Label
var _timer_label: Label

func begin() -> void:
	setup_arena(false)
	_tune_light()
	_lib = _make_lib()
	_build_room()
	_build_table()
	_seat_subjects()
	_build_boss()
	camera.fov = 58.0
	camera.position = Vector3(0.0, 1.8, 2.25)
	camera.look_at(Vector3(0.0, 0.78, -0.45), Vector3.UP)
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.12
			n.shadow_enabled = false
	env.ambient_light_energy = 0.42
	env.ambient_light_color = Color(0.6, 0.62, 0.52)
	env.fog_density = 0.03
	env.fog_light_color = Color(0.2, 0.21, 0.17)
	env.ssao_radius = 0.6

func _make_lib() -> AnimationLibrary:
	var sit: Animation = LabCharacter.shared_library().get_animation("Sitting_Idle")
	var slump := Animation.new()
	slump.length = 0.7
	for t in sit.get_track_count():
		var path := sit.track_get_path(t)
		var bone := String(path).get_slice(":", 1)
		var ty := sit.track_get_type(t)
		var nt := slump.add_track(ty)
		slump.track_set_path(nt, path)
		if ty == Animation.TYPE_ROTATION_3D:
			var q0: Quaternion = sit.rotation_track_interpolate(t, 0.0)
			var q1: Quaternion = q0 * Quaternion(Vector3.RIGHT, float(SLUMP.get(bone, 0.0)))
			slump.rotation_track_insert_key(nt, 0.0, q0)
			slump.rotation_track_insert_key(nt, 0.7, q1)
		elif ty == Animation.TYPE_POSITION_3D:
			var p0: Vector3 = sit.position_track_interpolate(t, 0.0)
			slump.position_track_insert_key(nt, 0.0, p0)
			slump.position_track_insert_key(nt, 0.7, p0 + Vector3(0.0, -0.02, 0.06))
	var lib := AnimationLibrary.new()
	lib.add_animation("Slump", slump)
	return lib

func _build_room() -> void:
	var room := Node3D.new()
	room.name = "DiningRoom"
	world.add_child(room)
	var wall := mat("concrete_wall_006", 0.6, Color(0.82, 0.84, 0.76))
	var damp := mat("dirty_concrete", 0.7, Color(0.55, 0.58, 0.48))
	box(Vector3(6.4, 0.2, 8.0), Vector3(0, -0.1, 0.2), mat("damaged_concrete_floor", 0.45, Color(0.8, 0.78, 0.7)), room)
	box(Vector3(6.4, 0.2, 8.0), Vector3(0, 3.0, 0.2), mat("grey_plaster_03", 0.5, Color(0.5, 0.5, 0.45)), room)
	box(Vector3(6.4, 3.2, 0.3), Vector3(0, 1.5, -3.15), wall, room)
	box(Vector3(0.3, 3.2, 8.0), Vector3(-2.75, 1.5, 0.2), wall, room)
	box(Vector3(0.3, 3.2, 8.0), Vector3(2.75, 1.5, 0.2), wall, room)
	box(Vector3(6.4, 0.9, 0.32), Vector3(0, 0.45, -3.13), damp, room)
	box(Vector3(0.32, 0.9, 8.0), Vector3(-2.73, 0.45, 0.2), damp, room)
	box(Vector3(0.32, 0.9, 8.0), Vector3(2.73, 0.45, 0.2), damp, room)
	for c in [Vector3(-2.45, 1.5, -2.85), Vector3(2.45, 1.5, -2.85)]:
		box(Vector3(0.4, 3.2, 0.4), c, mat("painted_concrete", 0.6, Color(0.6, 0.62, 0.55)), room)
	var pipe_mat := mat("rusty_metal_02", 1.5)
	for p in [[Vector3(0, 2.7, -2.85), 6.0, 0.09, 90.0], [Vector3(0, 2.55, -2.9), 6.0, 0.05, 90.0], [Vector3(-2.45, 2.75, 0.4), 7.0, 0.11, -1.0], [Vector3(1.9, 1.4, -2.9), 2.8, 0.06, 0.0], [Vector3(2.45, 2.6, 0.6), 7.0, 0.07, -1.0]]:
		var pipe := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = p[2]
		cm.bottom_radius = p[2]
		cm.height = p[1]
		pipe.mesh = cm
		pipe.material_override = pipe_mat
		if p[3] > 0.0:
			pipe.rotation_degrees.z = p[3]
		elif p[3] < 0.0:
			pipe.rotation_degrees.x = 90.0
		pipe.position = p[0]
		room.add_child(pipe)
	_can_shelves(room)
	prop("steel_frame_shelves_02", Vector3(-2.25, 0.0, -1.0), 90.0, 1.0, room)
	prop("steel_frame_shelves_02", Vector3(2.25, 0.0, -1.3), -90.0, 1.0, room)
	for c in [["cardboard_box_01", -2.25, 1.08, -1.0, 80.0], ["cardboard_box_01", 2.25, 0.02, -1.3, -95.0], ["wine_bottles_01", 2.15, 1.5, -1.5, -90.0]]:
		prop(c[0], Vector3(c[1], c[2], c[3]), c[4], 1.2, room)
	var clutter := [["cardboard_box_01", -2.2, -2.5, 20.0, 1.4], ["cardboard_box_01", -1.85, -2.65, -15.0, 1.2], ["barrel_03", 2.1, -2.4, 0.0, 0.9],
		["WetFloorSign_01", -2.15, 1.6, 30.0, 1.0], ["trashbag", 2.1, 1.2, 0.0, 1.0], ["metal_trash_can", 2.2, 0.3, 0.0, 0.9],
		["cement_bag", -2.2, 0.4, 70.0, 1.0], ["plastic_crate_01", 1.6, -2.65, 10.0, 1.1], ["WoodenTable_02", -2.1, -1.95, 0.0, 1.6],
		["power_box_01", 1.2, -2.98, 0.0, 1.0]]
	for c in clutter:
		prop(c[0], Vector3(c[1], 0.0, c[2]), c[3], c[4], room)
	prop("power_box_01", Vector3(-1.4, 1.7, -2.98), 0.0, 1.2, room)
	prop("fire_alarm", Vector3(1.2, 2.1, -2.98), 0.0, 1.4, room)
	prop("can_rusted", Vector3(-2.1, 0.415 * 1.6, -1.95), 30.0, 1.0, room)
	prop("hanging_industrial_lamp", Vector3(0.0, 2.9, 0.3), 0.0, 0.85, room)
	var sp := SpotLight3D.new()
	sp.light_color = Color(1.0, 0.8, 0.52)
	sp.light_energy = 7.0
	sp.spot_range = 5.0
	sp.spot_angle = 58.0
	sp.spot_attenuation = 0.8
	sp.shadow_enabled = true
	room.add_child(sp)
	sp.position = Vector3(0.0, 1.75, 0.3)
	sp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var bulb := OmniLight3D.new()
	bulb.light_color = Color(1.0, 0.75, 0.45)
	bulb.light_energy = 1.2
	bulb.omni_range = 4.5
	room.add_child(bulb)
	bulb.position = Vector3(0.0, 1.95, 0.3)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.5, 0.66, 0.55)
	fill.light_energy = 0.7
	fill.omni_range = 6.0
	room.add_child(fill)
	fill.position = Vector3(0.0, 1.8, -2.4)

func _can_shelves(room: Node3D) -> void:
	var steel := mat("rusty_metal", 1.2, Color(0.7, 0.68, 0.62))
	for x in [-2.0, -0.7, 0.7, 2.0]:
		box(Vector3(0.05, 2.2, 0.05), Vector3(x, 1.1, -2.62), steel, room)
		box(Vector3(0.05, 2.2, 0.05), Vector3(x, 1.1, -2.98), steel, room)
	for y in [0.55, 1.05, 1.55, 2.05]:
		box(Vector3(4.1, 0.03, 0.4), Vector3(0, y, -2.8), steel, room)
		var x := -1.95
		while x < 1.95:
			var r := randf()
			if r < 0.55:
				prop("can_rusted", Vector3(x, y + 0.015, -2.75 + randf_range(-0.06, 0.06)), randf() * 360.0, 1.0, room)
				if randf() < 0.35:
					prop("can_rusted", Vector3(x, y + 0.165, -2.75), randf() * 360.0, 1.0, room)
				x += 0.14
			elif r < 0.8:
				prop("russian_food_cans_01", Vector3(x + 0.05, y + 0.015, -2.75), randf_range(-20.0, 20.0), 1.0, room)
				x += 0.17
			elif r < 0.9:
				prop("cardboard_box_01", Vector3(x + 0.2, y + 0.015, -2.78), 90.0 + randf_range(-8.0, 8.0), 0.9, room)
				x += 0.5
			else:
				x += 0.2

func _build_table() -> void:
	var t := prop("dining_table", Vector3(0.0, 0.0, 0.0), 90.0)
	t.scale = Vector3(1.4, 0.85, 1.0)
	for c in [Vector3(0.05, TABLE_TOP, -0.35), Vector3(-0.12, TABLE_TOP, 0.55), Vector3(0.1, TABLE_TOP, 1.2)]:
		prop("can_rusted", c, randf() * 360.0, 1.0)
	var tipped := prop("can_rusted", Vector3(0.0, TABLE_TOP + 0.062, 0.12), 0.0, 1.0)
	tipped.rotation_degrees = Vector3(0.0, 35.0, 90.0)
	_spill(Vector3(0.12, TABLE_TOP, 0.2), 26, 0.16)
	_spill(Vector3(-0.2, TABLE_TOP, -0.9), 8, 0.2)
	prop("russian_food_cans_01", Vector3(0.12, TABLE_TOP, -1.2), 20.0, 1.0)
	prop("wooden_spoon", Vector3(-0.08, TABLE_TOP + 0.01, -0.7), 50.0, 1.0)

func _pea_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.6, 0.12)
	m.roughness = 0.35
	m.metallic_specular = 0.6
	return m

func _peas_mm(count: int) -> MultiMeshInstance3D:
	if not _pea_mesh:
		_pea_mesh = SphereMesh.new()
		_pea_mesh.radius = 0.0125
		_pea_mesh.height = 0.025
		_pea_mesh.radial_segments = 8
		_pea_mesh.rings = 4
		_pea_mesh.material = _pea_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _pea_mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	return mi

func _spill(at: Vector3, n: int, spread: float) -> void:
	var mi := _peas_mm(n)
	world.add_child(mi)
	mi.position = at
	for i in n:
		var a := randf() * TAU
		var r := pow(randf(), 1.6) * spread
		mi.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(cos(a) * r * 1.6, 0.012, sin(a) * r)))

func _plate(at: Vector3) -> MultiMeshInstance3D:
	var plate := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.15
	cm.bottom_radius = 0.09
	cm.height = 0.022
	cm.radial_segments = 32
	plate.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.84, 0.83, 0.77)
	pm.roughness = 0.22
	plate.material_override = pm
	world.add_child(plate)
	plate.position = at + Vector3(0, 0.011, 0)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.118
	tm.outer_radius = 0.142
	rim.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.25, 0.32, 0.58)
	rm.roughness = 0.3
	rim.material_override = rm
	rim.scale = Vector3(1.0, 0.25, 1.0)
	plate.add_child(rim)
	rim.position = Vector3(0, 0.011, 0)
	var mi := _peas_mm(PEAS * PEAS_PER_BITE)
	world.add_child(mi)
	mi.position = at + Vector3(0, 0.022, 0)
	var pts: Array = []
	for i in PEAS * PEAS_PER_BITE:
		var a := randf() * TAU
		var r := sqrt(randf()) * 0.085
		var h := 0.012 + (1.0 - r / 0.085) * 0.035 + randf() * 0.008
		pts.append(Vector3(cos(a) * r, h, sin(a) * r))
	pts.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.y < q.y)
	for i in pts.size():
		mi.multimesh.set_instance_transform(i, Transform3D(Basis(), pts[i]))
	return mi

func _seat_subjects() -> void:
	var ids: Array = NetworkManager.players.keys()
	var per_side: int = clampi(int(ceil(ids.size() / 2.0)), 2, 4)
	var span: float = 2.4
	for i in ids.size():
		var id: int = ids[i]
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var slot: int = i / 2
		var z: float = -span * 0.5 + span * (float(slot) + 0.5) / float(per_side)
		var info: Dictionary = NetworkManager.players[id]
		var yaw: float = PI * 0.5 if side < 0.0 else -PI * 0.5
		var root_pos := Vector3(side * (TABLE_HALF_W + 0.12), 0.0, z)
		var chair_id := "dining_chair_02" if (i % 3) != 2 else "SchoolChair_01"
		prop(chair_id, Vector3(side * (TABLE_HALF_W + 0.47), 0.0, z), rad_to_deg(yaw) + randf_range(-6.0, 6.0))
		var body := LabCharacter.new()
		body.sex = info.get("sex", "male")
		body.hat = info.get("hat", "hardhat")
		body.suit_color = info.color
		body.position = root_pos
		body.rotation.y = yaw
		world.add_child(body)
		body.anim.add_animation_library("tm", _lib)
		body.play_loop("Sitting_Idle")
		body.anim.seek(randf() * 1.5, true)
		_attach_spoon(body)
		var plate_pos := Vector3(side * (TABLE_HALF_W - 0.25), TABLE_TOP, z)
		var peas := _plate(plate_pos)
		var arm := SpoonArm.new()
		body.skeleton.add_child(arm)
		arm.setup(body.skeleton, body.to_local(plate_pos))
		var name_l := Label3D.new()
		name_l.text = info.name
		name_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_l.no_depth_test = true
		name_l.pixel_size = 0.0009
		name_l.fixed_size = true
		name_l.font_size = 26
		name_l.outline_size = 10
		name_l.modulate = info.color.lightened(0.35)
		name_l.render_priority = 3
		world.add_child(name_l)
		var head := Vector3(root_pos.x + side * 0.19, 1.5, z)
		name_l.position = head + Vector3(0, 0.12, 0)
		var plate_bar := _bar(head + Vector3(0, 0.05, 0), info.color, 7)
		var choke_bar := _bar(head, Color("d01c1c"), 5)
		seats[id] = {"body": body, "arm": arm, "peas": peas, "plate": plate_pos, "name": name_l, "plate_bar": plate_bar, "choke_bar": choke_bar, "side": side}
		eaten[id] = 0
		choke[id] = 0.0
		last_bite[id] = -10.0
		if info.is_bot:
			_bot[id] = {"risk": randf_range(0.6, 0.85), "next": randf_range(0.2, 0.8), "react": 0.25, "resume": randf_range(0.1, 0.45), "ignore": false, "greedy_until": -1.0, "greedy_risk": 1.0, "greed": randf_range(0.04, 0.11)}

func _attach_spoon(body: LabCharacter) -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	body.skeleton.add_child(att)
	var sp := prop("wooden_spoon", Vector3.ZERO, 0.0, 0.9, att)
	if sp:
		sp.transform = Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0)).scaled(Vector3.ONE * 0.9), Vector3(0.0, 0.17, 0.025))

func _bar(at: Vector3, col: Color, prio: int) -> Sprite3D:
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
	bg.scale = Vector3(1.06, 1.5, 1.0)
	bg.render_priority = prio - 1
	world.add_child(bg)
	bg.position = at
	var fill := Sprite3D.new()
	fill.texture = _bar_tex
	fill.pixel_size = 0.0011
	fill.fixed_size = true
	fill.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fill.no_depth_test = true
	fill.centered = false
	fill.offset = Vector2(-BAR_PX * 0.5, -4.0)
	fill.region_enabled = true
	fill.region_rect = Rect2(0, 0, 0, 8)
	fill.modulate = col
	fill.render_priority = prio
	world.add_child(fill)
	fill.position = at
	fill.set_meta("bg", bg)
	return fill

func _hide_bars(s: Dictionary) -> void:
	for k in ["plate_bar", "choke_bar"]:
		var fill: Sprite3D = s[k]
		fill.visible = false
		var bg: Sprite3D = fill.get_meta("bg")
		bg.visible = false

func _set_bar(bar: Sprite3D, frac: float) -> void:
	bar.region_rect = Rect2(0, 0, maxf(0.001, clampf(frac, 0.0, 1.0) * BAR_PX), 8)

func _build_boss() -> void:
	_boss = LabCharacter.new()
	_boss.owner_peer = -1
	_boss.sex = "male"
	_boss.hat = "tophat"
	_boss.suit_color = Color(0.07, 0.07, 0.08)
	_boss.hair_color = Color("120d0a")
	_boss.position = BOSS_POS
	world.add_child(_boss)
	_attach_shades(_boss)
	_share_face()
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	_boss.skeleton.add_child(att)
	_boss_gun = Node3D.new()
	att.add_child(_boss_gun)
	_boss_gun.transform = Transform3D(GUN_BASIS.orthonormalized().scaled(Vector3.ONE * 1.3), Vector3(0.0, 0.07, 0.015))
	var gm: StandardMaterial3D = mat("rusty_metal", 3.0, Color(0.3, 0.31, 0.34)).duplicate()
	gm.metallic = 0.75
	gm.roughness = 0.38
	box(Vector3(0.2, 0.034, 0.03), Vector3(0.02, 0.032, 0.0), gm, _boss_gun)
	box(Vector3(0.17, 0.02, 0.026), Vector3(0.025, 0.008, 0.0), gm, _boss_gun)
	var grip := box(Vector3(0.045, 0.11, 0.03), Vector3(-0.055, -0.04, 0.0), gm, _boss_gun)
	grip.rotation_degrees.z = 14.0
	box(Vector3(0.05, 0.008, 0.012), Vector3(-0.005, -0.03, 0.0), gm, _boss_gun)
	box(Vector3(0.008, 0.03, 0.012), Vector3(0.02, -0.018, 0.0), gm, _boss_gun)
	_boss.play_loop("Pistol_Idle")
	_boss_lamp = OmniLight3D.new()
	_boss_lamp.light_color = Color(1.0, 0.18, 0.12)
	_boss_lamp.light_energy = 0.0
	_boss_lamp.omni_range = 2.6
	world.add_child(_boss_lamp)
	_boss_lamp.position = BOSS_POS + Vector3(0.0, 2.1, 0.55)
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.82, 0.6)
	key.light_energy = 3.0
	key.spot_range = 3.5
	key.spot_angle = 30.0
	world.add_child(key)
	key.position = BOSS_POS + Vector3(0.0, 2.75, 0.9)
	key.look_at(BOSS_POS + Vector3(0.0, 1.2, 0.0), Vector3.UP)

func _office_face_bytes() -> PackedByteArray:
	var dirs: Array[String] = [OS.get_executable_path().get_base_dir() + "/office", ProjectSettings.globalize_path("user://office")]
	for d in dirs:
		for ext in ["png", "jpg", "jpeg", "webp"]:
			var p: String = "%s/boss_face.%s" % [d, ext]
			if not FileAccess.file_exists(p):
				continue
			var img := Image.load_from_file(p)
			if img == null or img.is_empty():
				continue
			if img.get_height() > 384:
				img.resize(int(384.0 * img.get_width() / img.get_height()), 384, Image.INTERPOLATE_LANCZOS)
			print("[LP] office face ", p)
			return img.save_png_to_buffer()
	return PackedByteArray()

func _face_image(bytes: PackedByteArray) -> Image:
	var img := Image.new()
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	if img.detect_alpha() == Image.ALPHA_NONE:
		var w: int = img.get_width()
		var h: int = img.get_height()
		for y in h:
			for x in w:
				var dx: float = (x - w * 0.5) / (w * 0.44)
				var dy: float = (y - h * 0.5) / (h * 0.5)
				if dx * dx + dy * dy > 1.0:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img

func _apply_face(bytes: PackedByteArray) -> void:
	if _boss_masked or not is_instance_valid(_boss):
		return
	var img := _face_image(bytes)
	if img == null:
		return
	var mipped: Image = img.duplicate()
	mipped.generate_mipmaps()
	if not FaceWrap.apply(_boss, ImageTexture.create_from_image(mipped), img):
		return
	if _boss_shades and is_instance_valid(_boss_shades):
		_boss_shades.queue_free()
	_boss_masked = true
	print("[LP] office face applied")

func _share_face() -> void:
	var own := _office_face_bytes()
	_face_local = not own.is_empty()
	if _face_local:
		_apply_face(own)
	if NetworkManager.is_server():
		if _face_local and _face_bytes.is_empty():
			_server_take_face(own)
		elif not _face_bytes.is_empty():
			_apply_face(_face_bytes)
		return
	if _face_local:
		_rpc_offer_face.rpc_id(1, own)
	_rpc_face_ready.rpc_id(1)

func _server_take_face(bytes: PackedByteArray) -> void:
	_face_bytes = bytes
	_apply_face(bytes)
	for id in _face_waiting:
		_rpc_face.rpc_id(id, bytes)
	_face_waiting.clear()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_offer_face(bytes: PackedByteArray) -> void:
	if not NetworkManager.is_server() or not _face_bytes.is_empty() or _face_image(bytes) == null:
		return
	_cache_face(bytes)
	_server_take_face(bytes)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_face_ready() -> void:
	if not NetworkManager.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if _face_bytes.is_empty():
		if not id in _face_waiting:
			_face_waiting.append(id)
	else:
		_rpc_face.rpc_id(id, _face_bytes)

@rpc("authority", "call_remote", "reliable")
func _rpc_face(bytes: PackedByteArray) -> void:
	if _face_image(bytes) == null:
		return
	_cache_face(bytes)
	_apply_face(bytes)

func _cache_face(bytes: PackedByteArray) -> void:
	if _face_local or OS.get_environment("LP_NO_FACE_CACHE") == "1":
		return
	var path := "user://office/boss_face.png"
	if FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == bytes:
		return
	DirAccess.make_dir_recursive_absolute("user://office")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		print("[LP] office face cached")

func _attach_shades(body: LabCharacter) -> void:
	var path := "res://assets/hats/hat_shades.glb"
	if not ResourceLoader.exists(path):
		return
	var sk := body.skeleton
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	sk.add_child(att)
	_boss_shades = att
	var h: Node3D = load(path).instantiate()
	att.add_child(h)
	var head_rest := sk.global_transform * sk.get_bone_global_rest(sk.find_bone("Head"))
	var want := Transform3D(body.global_transform.basis * Basis(Vector3.UP, PI), body.global_transform * Vector3(0.0, LabCharacter.HAT_HEIGHT["male"] - 0.005, 0.0))
	h.transform = head_rest.affine_inverse() * want

func _build_hud() -> void:
	hud_title("TABLE MANNERS  ·  eat while the boss looks away")
	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-120, 10)
	_timer_label.size = Vector2(100, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.add_theme_font_size_override("font_size", 26)
	_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_timer_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_timer_label)
	_big = _center_label(84, 0.30)
	_status = _center_label(40, 0.70)
	_hint = _center_label(26, 0.86)
	_hint.text = "MASH  SPACE  TO EAT\neat only while his back is turned  ·  he clicks and turns = STOP  ·  too fast = you choke"
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

func _process(delta: float) -> void:
	var down := Input.is_physical_key_pressed(KEY_SPACE)
	if st == St.EAT and down and not _space_down:
		var me := multiplayer.get_unique_id()
		if NetworkManager.is_server():
			_register_bite(me)
		else:
			_rpc_press.rpc_id(1)
	_space_down = down
	for id in seats:
		var c: float = float(choke.get(id, 0.0))
		var bar: Sprite3D = seats[id].choke_bar
		_set_bar(bar, c)
		bar.modulate = Color("d01c1c") if c < 0.72 or fmod(clock, 0.24) < 0.12 else Color("ffe14a")
		(seats[id].arm as SpoonArm).advance(delta)
	if st == St.EAT and boss_state == Boss.TURN:
		_status.modulate.a = 1.0 if fmod(clock, 0.2) < 0.13 else 0.35
	if st == St.EAT:
		clock += delta
		if NetworkManager.is_server():
			_server_tick(delta)

func _server_tick(delta: float) -> void:
	for id in choke:
		if not dead_order.has(id):
			choke[id] = maxf(0.0, float(choke[id]) - CHOKE_DRAIN * delta)
	if clock >= _boss_until:
		match boss_state:
			Boss.AWAY:
				if clock < TIME_LIMIT - 3.0:
					_set_boss(Boss.TURN, TURN_T)
					for id in _bot:
						var b: Dictionary = _bot[id]
						b.react = randf_range(0.12, 0.5)
						b.ignore = randf() < float(b.greed)
				else:
					_boss_until = TIME_LIMIT + 10.0
			Boss.TURN:
				_set_boss(Boss.WATCH, randf_range(1.5, 2.8))
			Boss.WATCH:
				_set_boss(Boss.AWAY, randf_range(2.8, 5.2))
	for id in _bot:
		_bot_think(id)
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.1
		_rpc_sync.rpc(choke, maxf(0.0, TIME_LIMIT - clock))

func _set_boss(s: Boss, dur: float) -> void:
	_boss_until = clock + dur
	_rpc_boss.rpc(int(s), clock)

func _bot_think(id: int) -> void:
	if dead_order.has(id) or finish_order.has(id) or clock < float(_bot[id].next):
		return
	var b: Dictionary = _bot[id]
	if not bool(b.ignore):
		if boss_state == Boss.TURN and clock >= boss_from + float(b.react):
			return
		if boss_state == Boss.WATCH:
			return
		if boss_state == Boss.AWAY and clock < boss_from + float(b.resume):
			return
	if clock > float(b.greedy_until) and randf() < 0.02:
		b.greedy_until = clock + randf_range(0.6, 1.4)
		b.greedy_risk = randf_range(0.9, 1.12)
	var greedy: bool = clock < float(b.greedy_until)
	var gain: float = CHOKE_PER_BITE + (CHOKE_FAST_BONUS if clock - float(last_bite[id]) < FAST_GAP else 0.0)
	if float(choke[id]) + gain < (float(b.greedy_risk) if greedy else float(b.risk)):
		_register_bite(id)
		b.next = clock + (randf_range(0.12, 0.2) if greedy else randf_range(0.24, 0.42))
	else:
		b.next = clock + randf_range(0.08, 0.2)

@rpc("any_peer", "reliable")
func _rpc_press() -> void:
	if NetworkManager.is_server():
		_register_bite(multiplayer.get_remote_sender_id())

func _register_bite(id: int) -> void:
	if st != St.EAT or not seats.has(id) or dead_order.has(id) or finish_order.has(id):
		return
	if boss_state == Boss.WATCH and clock >= boss_from + WATCH_GRACE:
		dead_order.append(id)
		choke[id] = 0.0
		_rpc_shot.rpc(id)
		return
	var gain: float = CHOKE_PER_BITE + (CHOKE_FAST_BONUS if clock - float(last_bite[id]) < FAST_GAP else 0.0)
	last_bite[id] = clock
	choke[id] = float(choke[id]) + gain
	eaten[id] = int(eaten[id]) + 1
	_rpc_bite.rpc(id, int(eaten[id]), float(choke[id]))
	if float(choke[id]) >= 1.0:
		_choke_out(id)
	elif int(eaten[id]) >= PEAS:
		finish_order.append(id)
		_rpc_cleared.rpc(id, finish_order.size())

func _choke_out(id: int) -> void:
	dead_order.append(id)
	choke[id] = 1.0
	_rpc_choke.rpc(id)

func _everyone_done() -> bool:
	return dead_order.size() + finish_order.size() >= seats.size()

func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	for n in ["3", "2", "1"]:
		_rpc_big.rpc(n, "e8e2c8")
		Fx.sfx("click")
		await get_tree().create_timer(0.8).timeout
	_rpc_start.rpc()
	_set_boss(Boss.AWAY, randf_range(2.6, 3.8))
	while clock < TIME_LIMIT and not _everyone_done():
		await get_tree().process_frame
	_rpc_end.rpc(_everyone_done(), choke, eaten)
	await get_tree().create_timer(2.6).timeout
	if not _ended:
		_ended = true
		finished.emit(_placement())

func _placement() -> Array:
	var out: Array = finish_order.duplicate()
	var living: Array = seats.keys().filter(func(id): return not out.has(id) and not dead_order.has(id))
	living.sort_custom(func(a, b): return int(eaten[a]) > int(eaten[b]))
	out.append_array(living)
	for i in range(dead_order.size() - 1, -1, -1):
		out.append(dead_order[i])
	return out

func _boss_turn(yaw: float, t: float) -> void:
	if _boss_tw:
		_boss_tw.kill()
	_boss_tw = create_tween()
	_boss_tw.tween_property(_boss, "rotation:y", yaw, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _set_status(text: String, hex: String) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(hex))
	_status.modulate.a = 1.0

@rpc("authority", "call_local", "reliable")
func _rpc_big(text: String, hex: String) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", Color(hex))
	_big.modulate.a = 1.0

@rpc("authority", "call_local", "reliable")
func _rpc_start() -> void:
	st = St.EAT
	clock = 0.0
	_rpc_big("EAT!", "8fe36a")
	Fx.sfx("beep", null, -4.0, 1.4)
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(_big, "modulate:a", 0.0, 0.4)
	var th := create_tween()
	th.tween_interval(6.0)
	th.tween_property(_hint, "modulate:a", 0.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_boss(s: int, at: float) -> void:
	boss_state = s as Boss
	boss_from = at
	match boss_state:
		Boss.AWAY:
			_boss_turn(PI, 0.5)
			_boss.anim.play("Pistol_Idle", 0.3)
			_boss_lamp.light_energy = 0.0
			_set_status("BACK TURNED  ·  EAT", "8fe36a")
		Boss.TURN:
			_boss_turn(PI * 0.42, TURN_T * 0.85)
			Fx.sfx("click", _boss.global_position + Vector3(0, 1.2, 0), 2.0, 0.8)
			Fx.sfx("beep", null, -2.0, 0.75)
			_boss_lamp.light_energy = 0.8
			_set_status("HE'S TURNING!", "ffd23a")
		Boss.WATCH:
			_boss_turn(0.0, 0.16)
			_boss.anim.play("Pistol_Aim_Neutral", 0.12)
			Fx.sfx("beep", null, -3.0, 0.5)
			_boss_lamp.light_energy = 2.2
			_set_status("HE'S WATCHING  ·  DON'T EAT", "ff3b2e")

@rpc("authority", "call_local", "reliable")
func _rpc_bite(id: int, n: int, c: float) -> void:
	eaten[id] = n
	choke[id] = c
	var s: Dictionary = seats[id]
	var mi: MultiMeshInstance3D = s.peas
	mi.multimesh.visible_instance_count = maxi(0, (PEAS - n) * PEAS_PER_BITE)
	_set_bar(s.plate_bar, float(n) / float(PEAS))
	var body: LabCharacter = s.body
	if not body.is_dead():
		(s.arm as SpoonArm).bite()
	Fx.sfx("click", s.plate, -14.0, randf_range(0.7, 0.9))

func _release_arm(s: Dictionary) -> void:
	var arm: SpoonArm = s.arm
	var tw := create_tween()
	tw.tween_property(arm, "influence", 0.0, 0.3)

@rpc("authority", "call_local", "reliable")
func _rpc_cleared(id: int, place: int) -> void:
	var s: Dictionary = seats[id]
	var body: LabCharacter = s.body
	_release_arm(s)
	body.anim.play("Sitting_Talking", 0.3)
	_hide_bars(s)
	(s.name as Label3D).text = "%s  ·  CLEAN #%d" % [NetworkManager.players[id].name, place]
	Fx.sfx("win", s.plate, -6.0)

func _slump(id: int, tag: String, shake: bool) -> void:
	if not dead_order.has(id):
		dead_order.append(id)
	var s: Dictionary = seats[id]
	var body: LabCharacter = s.body
	(s.name as Label3D).modulate.a = 0.6
	_hide_bars(s)
	(s.name as Label3D).text = "%s  ·  %s" % [NetworkManager.players[id].name, tag]
	_release_arm(s)
	body.anim.play("Sitting_Idle", 0.1)
	body.die("tm/Slump")
	body.anim.speed_scale = 1.0
	if shake:
		var base := body.position
		var tw := create_tween()
		for k in 6:
			tw.tween_property(body, "position", base + Vector3(randf_range(-0.03, 0.03), 0.0, randf_range(-0.03, 0.03)), 0.05)
		tw.tween_property(body, "position", base, 0.05)
	var plate: Vector3 = s.plate
	var side: float = s.side
	get_tree().create_timer(0.55).timeout.connect(func() -> void:
		_burst(plate + Vector3(0, 0.12, 0), Color(0.42, 0.02, 0.03), 46, 2.6, 0.016)
		Fx.sfx("splat", plate, -2.0)
		_table_splat(plate, side)
		_pea_burst(plate + Vector3(0, 0.06, 0))
		Fx.shake(0.35)
	)

@rpc("authority", "call_local", "reliable")
func _rpc_choke(id: int) -> void:
	choke[id] = 1.0
	_slump(id, "CHOKED", true)
	get_tree().create_timer(0.55).timeout.connect(func() -> void: Fx.sfx("buzzer", null, -4.0))

@rpc("authority", "call_local", "reliable")
func _rpc_shot(id: int) -> void:
	choke[id] = 0.0
	var s: Dictionary = seats[id]
	var body: LabCharacter = s.body
	var sk := body.skeleton
	var head: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
	var to := head - _boss.global_position
	_boss_turn(atan2(to.x, to.z), 0.07)
	_boss.anim.play("Pistol_Shoot", 0.05)
	get_tree().create_timer(0.09).timeout.connect(func() -> void:
		_fire(head)
		Fx.blood(world, head, 45)
		_slump(id, "SHOT", false)
	)
	get_tree().create_timer(0.75).timeout.connect(func() -> void:
		if boss_state == Boss.WATCH:
			_boss.anim.play("Pistol_Aim_Neutral", 0.15)
			_boss_turn(0.0, 0.25)
	)

func _fire(end: Vector3) -> void:
	var from: Vector3 = _boss_gun.global_transform * MUZZLE
	Fx.sfx("gunshot", from, 2.0)
	Fx.shake(0.5)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.75, 0.35)
	fl.light_energy = 14.0
	fl.omni_range = 5.0
	world.add_child(fl)
	fl.global_position = from
	var ftw := fl.create_tween()
	ftw.tween_property(fl, "light_energy", 0.0, 0.14)
	ftw.tween_callback(fl.queue_free)
	var um := StandardMaterial3D.new()
	um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	um.albedo_color = Color(1.0, 0.82, 0.42)
	var mf := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.material = um
	mf.mesh = sm
	world.add_child(mf)
	mf.global_position = from
	mf.look_at(end, Vector3.UP)
	mf.scale = Vector3(1.0, 1.0, 2.8)
	var mtw := mf.create_tween()
	mtw.tween_property(mf, "scale", Vector3(0.05, 0.05, 0.05), 0.08)
	mtw.tween_callback(mf.queue_free)
	var tr := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var dist := from.distance_to(end)
	bm.size = Vector3(0.018, 0.018, dist)
	bm.material = um
	tr.mesh = bm
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(tr)
	tr.global_position = from.lerp(end, 0.5)
	tr.look_at(end, Vector3.UP)
	var ttw := tr.create_tween()
	ttw.tween_property(tr, "scale", Vector3(0.1, 0.1, 1.0), 0.09)
	ttw.tween_callback(tr.queue_free)

func _table_splat(at: Vector3, side: float) -> void:
	var d := Decal.new()
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.09
	for y in 64:
		for x in 64:
			var r := Vector2(x - 32, y - 32).length() / 32.0
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if 1.0 - r + noise.get_noise_2d(x, y) * 0.6 > 0.4 else 0.0))
	d.texture_albedo = ImageTexture.create_from_image(img)
	d.modulate = Color(0.5, 0.02, 0.03)
	d.size = Vector3(0.7, 0.3, 0.55)
	world.add_child(d)
	d.position = at + Vector3(-side * 0.05, 0.05, 0)

func _pea_burst(at: Vector3) -> void:
	var gp := _burst(at, Color.WHITE, 28, 1.8, 0.0)
	gp.draw_pass_1 = _pea_mesh
	_spill(at - Vector3(0, 0.06, 0), 14, 0.22)

func _burst(at: Vector3, col: Color, n: int, spd: float, size: float) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.amount = n
	gp.lifetime = 1.4
	gp.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = spd * 0.35
	pm.initial_velocity_max = spd
	pm.gravity = Vector3(0, -9.8, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.2
	pm.collision_friction = 0.8
	gp.process_material = pm
	if size > 0.0:
		var sm := SphereMesh.new()
		sm.radius = size
		sm.height = size * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.25
		sm.material = m
		gp.draw_pass_1 = sm
	world.add_child(gp)
	gp.position = at
	gp.emitting = true
	if not _table_col:
		_table_col = GPUParticlesCollisionBox3D.new()
		_table_col.size = Vector3(1.4, 0.1, 3.1)
		world.add_child(_table_col)
		_table_col.position = Vector3(0, TABLE_TOP - 0.05, 0)
	get_tree().create_timer(3.0).timeout.connect(gp.queue_free)
	return gp

@rpc("authority", "call_local", "reliable")
func _rpc_sync(c: Dictionary, time_left: float) -> void:
	choke = c
	_timer_label.text = "%d s" % int(ceil(time_left))

@rpc("authority", "call_local", "reliable")
func _rpc_end(cleared: bool, c: Dictionary, e: Dictionary) -> void:
	st = St.DONE
	choke = c
	eaten = e
	_rpc_big("PLATES DOWN" if cleared else "TIME!", "e2c84b")
	_status.text = ""
	Fx.sfx("buzzer", null, -6.0, 1.3)
