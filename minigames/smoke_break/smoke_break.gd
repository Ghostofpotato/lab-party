extends ArenaMinigame3D
## Smoke Break: subjects stand in a row in front of a wall of giant ventilation
## fans. Hold SPACE to drag on your cigarette, release to exhale. When the warning
## light goes amber the fans spin up into a GUST: inhaling then, or holding one
## drag longer than 1.4 s, fills the cough meter fast; full meter = coughing fit
## and death. Stop smoking for 6 s and the supervisor shoots you for SLACKING.
## Most cigarettes smoked wins (fractions count); the dead place last.

const TIME_LIMIT: float = 40.0
const BURN_TIME: float = 2.5
const LONG_DRAG: float = 1.4
const SLACK_LIMIT: float = 6.0
const SLACK_WARN: float = 3.6
const COUGH_BASE: float = 0.05
const COUGH_GUST: float = 0.95
const COUGH_LONG: float = 0.85
const COUGH_DRAIN: float = 0.1
const RELIGHT: float = 0.7
const WARN_TIME: float = 1.8
const GUST_TIME: float = 1.5
const FAN_Z: float = -2.05
const WALL_Z: float = -2.6
const PATROL_Z: float = -0.95
const BAR_PX: int = 100
const MOUTH := Vector3(0.0, 0.05, 0.12)
const WRIST := Vector3(-0.07, -0.1, 0.14)
const CIG_HAND := Transform3D(Basis(Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)), Vector3(0.0, 0.085, 0.02))

enum St { COUNTDOWN, PLAY, DONE }
enum Gust { CALM, WARN, BLOW }

class SmokeArm extends SkeletonModifier3D:
	var clav: int
	var upper: int
	var lower: int
	var hand: int
	var head: int
	func setup(sk: Skeleton3D) -> void:
		clav = sk.find_bone("clavicle_r")
		upper = sk.find_bone("upperarm_r")
		lower = sk.find_bone("lowerarm_r")
		hand = sk.find_bone("hand_r")
		head = sk.find_bone("Head")
	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or influence <= 0.001:
			return
		var pc := sk.get_bone_global_pose(clav)
		var pu := sk.get_bone_global_pose(upper)
		var pl := sk.get_bone_global_pose(lower)
		var ph := sk.get_bone_global_pose(hand)
		var hd := sk.get_bone_global_pose(head).origin
		var mouth := hd + MOUTH
		var target := hd + WRIST
		var a := pu.origin
		var b := pl.origin
		var c := ph.origin
		var l1 := a.distance_to(b)
		var l2 := b.distance_to(c)
		var d := clampf(a.distance_to(target), absf(l1 - l2) + 0.01, l1 + l2 - 0.005)
		var dir := (target - a).normalized()
		var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(0.0, l1 * l1 - along * along))
		var pole := Vector3(-1.0, -0.9, -0.25)
		var perp := (pole - dir * pole.dot(dir)).normalized()
		var elbow := a + dir * along + perp * h
		var r1 := Basis(Quaternion((b - a).normalized(), (elbow - a).normalized()))
		var b2 := a + r1 * (b - a)
		var c2 := b2 + r1 * (c - b)
		var r2 := Basis(Quaternion((c2 - b2).normalized(), (target - b2).normalized()))
		var ug := (r1 * pu.basis.orthonormalized())
		var lg := (r2 * r1 * pl.basis.orthonormalized())
		var hg0 := r2 * r1 * ph.basis.orthonormalized()
		var fingers := (mouth + Vector3(0.0, -0.02, 0.04) - target).normalized()
		var r3 := Basis(Quaternion((hg0 * Vector3.UP).normalized(), fingers))
		var hg := r3 * hg0
		sk.set_bone_pose_rotation(upper, (pc.basis.orthonormalized().inverse() * ug).get_rotation_quaternion())
		sk.set_bone_pose_rotation(lower, (ug.inverse() * lg).get_rotation_quaternion())
		sk.set_bone_pose_rotation(hand, (lg.inverse() * hg).get_rotation_quaternion())

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
var gust: Gust = Gust.CALM
var gust_from: float = 0.0
var subjects: Dictionary = {}
var smoked: Dictionary = {}
var cough: Dictionary = {}
var burn: Dictionary = {}
var inhaling: Dictionary = {}
var idle_t: Dictionary = {}
var holding: Dictionary = {}
var hold_t: Dictionary = {}
var last_smoke: Dictionary = {}
var relight_until: Dictionary = {}
var dead_order: Array = []
var _shoot_queue: Array = []
var _shooting: bool = false
var _next_gust: float = 5.0
var _sync_t: float = 0.0
var _space_down: bool = false
var _ended: bool = false
var _bot: Dictionary = {}
var _fans: Array[Node3D] = []
var _fan_speed: float = 1.2
var _beacons: Array[OmniLight3D] = []
var _beacon_mat: StandardMaterial3D
var _tip_pm: ParticleProcessMaterial
var _haze: GPUParticles3D
var _soft: Texture2D
var _bar_tex: ImageTexture
var _splat: ImageTexture
var _sup: LabCharacter
var _sup_mod: ArmPose
var _sup_x: float = 0.0
var _sup_dir: float = 1.0
var _row_half: float = 2.0
var _big: Label
var _hint: Label
var _timer_label: Label

func begin() -> void:
	setup_arena(false)
	_tune_light()
	_soft = _soft_tex()
	_splat = _splat_tex()
	_build_room()
	_build_fans()
	_build_dressing()
	_line_up()
	_spawn_supervisor()
	_build_haze()
	camera.fov = 50.0
	camera.position = Vector3(1.3, 1.15, 3.15)
	camera.look_at(Vector3(0.1, 1.42, -0.4), Vector3.UP)
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.1
			n.shadow_enabled = false
	env.ambient_light_energy = 0.38
	env.ambient_light_color = Color(0.62, 0.58, 0.5)
	env.fog_density = 0.035
	env.fog_light_color = Color(0.24, 0.22, 0.18)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.035
	env.volumetric_fog_albedo = Color(0.75, 0.72, 0.66)
	env.volumetric_fog_length = 12.0
	env.ssao_radius = 0.7

func _build_room() -> void:
	var room := Node3D.new()
	room.name = "VentRoom"
	world.add_child(room)
	var floor_m := mat("concrete_floor_worn_001", 0.45, Color(0.62, 0.58, 0.52))
	var wall := mat("concrete_wall_008", 0.45, Color(0.7, 0.66, 0.6))
	var lower := mat("peeling_painted_wall", 0.6, Color(0.55, 0.6, 0.5))
	box(Vector3(10.0, 0.2, 8.0), Vector3(0, -0.1, 0.8), floor_m, room)
	box(Vector3(10.0, 0.2, 8.0), Vector3(0, 3.8, 0.8), mat("ceiling_interior", 0.5, Color(0.42, 0.4, 0.36)), room)
	box(Vector3(10.0, 4.0, 0.3), Vector3(0, 1.9, WALL_Z - 0.15), mat("dark_brick_wall", 0.5, Color(0.6, 0.55, 0.5)), room)
	box(Vector3(0.3, 4.0, 8.0), Vector3(-4.8, 1.9, 0.8), wall, room)
	box(Vector3(0.3, 4.0, 8.0), Vector3(4.8, 1.9, 0.8), wall, room)
	box(Vector3(0.32, 1.1, 8.0), Vector3(-4.78, 0.55, 0.8), lower, room)
	box(Vector3(0.32, 1.1, 8.0), Vector3(4.78, 0.55, 0.8), lower, room)
	box(Vector3(10.0, 0.25, 0.32), Vector3(0, 0.12, WALL_Z - 0.1), mat("dirty_concrete", 0.7, Color(0.4, 0.38, 0.33)), room)
	var pipe_mat := mat("rusty_metal_02", 1.5)
	for p in [[Vector3(0, 3.45, WALL_Z + 0.15), 10.0, 0.11, 90.0], [Vector3(0, 3.22, WALL_Z + 0.12), 10.0, 0.06, 90.0],
			[Vector3(-4.45, 1.8, WALL_Z + 0.2), 3.8, 0.09, 0.0], [Vector3(4.4, 1.8, WALL_Z + 0.18), 3.8, 0.07, 0.0],
			[Vector3(-4.5, 3.3, 0.8), 8.0, 0.12, -1.0], [Vector3(4.45, 2.9, 0.8), 8.0, 0.08, -1.0], [Vector3(0.9, 3.55, 0.8), 8.0, 0.05, -1.0]]:
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
	for x in [-3.3, -1.0, 1.4, 3.4]:
		box(Vector3(0.05, 0.3, 0.05), Vector3(x, 3.38, WALL_Z + 0.15), mat("rusty_metal", 1.0, Color(0.3, 0.28, 0.25)), room)
	prop("hanging_industrial_lamp", Vector3(0.0, 3.7, 0.35), 0.0, 1.0, room)
	var sp := SpotLight3D.new()
	sp.light_color = Color(1.0, 0.78, 0.5)
	sp.light_energy = 9.0
	sp.spot_range = 6.0
	sp.spot_angle = 62.0
	sp.spot_attenuation = 0.7
	sp.shadow_enabled = true
	room.add_child(sp)
	sp.position = Vector3(0.0, 3.0, 0.35)
	sp.rotation_degrees = Vector3(-80.0, 0.0, 0.0)
	var bulb := OmniLight3D.new()
	bulb.light_color = Color(1.0, 0.72, 0.42)
	bulb.light_energy = 1.4
	bulb.omni_range = 5.0
	room.add_child(bulb)
	bulb.position = Vector3(0.0, 3.0, 0.45)
	var front := OmniLight3D.new()
	front.light_color = Color(1.0, 0.8, 0.6)
	front.light_energy = 1.1
	front.omni_range = 4.5
	room.add_child(front)
	front.position = Vector3(0.8, 1.9, 2.2)
	var back := OmniLight3D.new()
	back.light_color = Color(0.55, 0.7, 0.62)
	back.light_energy = 1.0
	back.omni_range = 4.0
	room.add_child(back)
	back.position = Vector3(0.0, 2.6, -1.6)

func _build_fans() -> void:
	var housing := mat("rusty_metal", 0.9, Color(0.75, 0.42, 0.36)).duplicate()
	housing.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame_m := mat("green_metal_rust", 0.8, Color(0.55, 0.52, 0.46))
	var blade_m := mat("green_metal_rust", 1.6, Color(0.42, 0.42, 0.4))
	var grille_m := mat("rusty_metal", 2.0, Color(0.35, 0.32, 0.3))
	var dark := mat("rusty_metal", 1.0, Color(0.12, 0.1, 0.09))
	for i in 3:
		var cx: float = -2.65 + 2.65 * float(i)
		var c := Vector3(cx, 1.62, FAN_Z)
		var fan := Node3D.new()
		world.add_child(fan)
		fan.position = c
		var shroud := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.18
		cm.bottom_radius = 1.18
		cm.height = 0.55
		cm.cap_top = false
		cm.cap_bottom = false
		cm.radial_segments = 40
		shroud.mesh = cm
		shroud.material_override = housing
		shroud.rotation_degrees.x = 90.0
		fan.add_child(shroud)
		var lip := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.14
		tm.outer_radius = 1.3
		tm.rings = 40
		lip.mesh = tm
		lip.material_override = housing
		lip.rotation_degrees.x = 90.0
		lip.scale = Vector3(1.0, 0.6, 1.0)
		lip.position.z = 0.28
		fan.add_child(lip)
		var back_disc := MeshInstance3D.new()
		var bd := CylinderMesh.new()
		bd.top_radius = 1.18
		bd.bottom_radius = 1.18
		bd.height = 0.04
		back_disc.mesh = bd
		back_disc.material_override = dark
		back_disc.rotation_degrees.x = 90.0
		back_disc.position.z = -0.26
		fan.add_child(back_disc)
		for e in [[Vector3(2.75, 0.22, 0.3), Vector3(0, 1.28, 0)], [Vector3(2.75, 0.22, 0.3), Vector3(0, -1.28, 0)],
				[Vector3(0.22, 2.75, 0.3), Vector3(1.28, 0, 0)], [Vector3(0.22, 2.75, 0.3), Vector3(-1.28, 0, 0)]]:
			box(e[0], e[1] + Vector3(0, 0, -0.05), frame_m, fan)
		for k in 4:
			var bolt := box(Vector3(0.07, 0.07, 0.06), Vector3(1.28 * (1.0 if k % 2 == 0 else -1.0), 1.28 * (1.0 if k < 2 else -1.0), 0.13), grille_m, fan)
			bolt.rotation_degrees.z = 45.0
		var motor := MeshInstance3D.new()
		var mm := CylinderMesh.new()
		mm.top_radius = 0.24
		mm.bottom_radius = 0.3
		mm.height = 0.36
		motor.mesh = mm
		motor.material_override = frame_m
		motor.rotation_degrees.x = 90.0
		motor.position.z = -0.1
		fan.add_child(motor)
		var rotor := Node3D.new()
		fan.add_child(rotor)
		rotor.position.z = 0.05
		rotor.rotation.z = randf() * TAU
		var hub := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.12
		hm.bottom_radius = 0.2
		hm.height = 0.16
		hub.mesh = hm
		hub.material_override = blade_m
		hub.rotation_degrees.x = 90.0
		hub.position.z = 0.06
		rotor.add_child(hub)
		for bi in 6:
			var arm := Node3D.new()
			rotor.add_child(arm)
			arm.rotation.z = TAU * float(bi) / 6.0
			var blade := box(Vector3(0.36, 0.92, 0.025), Vector3(0, 0.62, 0), blade_m, arm)
			blade.rotation_degrees.y = 28.0
			var tip := box(Vector3(0.42, 0.14, 0.03), Vector3(0, 1.02, 0), blade_m, arm)
			tip.rotation_degrees.y = 28.0
		_fans.append(rotor)
		for r in [0.38, 0.72, 1.05]:
			var ring := MeshInstance3D.new()
			var rt := TorusMesh.new()
			rt.inner_radius = r - 0.012
			rt.outer_radius = r + 0.012
			rt.rings = 36
			rt.ring_segments = 6
			ring.mesh = rt
			ring.material_override = grille_m
			ring.rotation_degrees.x = 90.0
			ring.position.z = 0.3
			fan.add_child(ring)
		for s in 4:
			var spoke := box(Vector3(0.025, 2.3, 0.025), Vector3(0, 0, 0.31), grille_m, fan)
			spoke.rotation_degrees.z = 45.0 * float(s)
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.9, 0.35, 0.25)
		glow.light_energy = 0.7
		glow.omni_range = 1.6
		fan.add_child(glow)
		glow.position = Vector3(0, 0, -0.15)
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(0.5, 0.32, 0.08)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color("ff9a1a")
	_beacon_mat.emission_energy_multiplier = 0.0
	_beacon_mat.roughness = 0.3
	for bx in [-1.33, 1.33]:
		box(Vector3(0.18, 0.12, 0.12), Vector3(bx, 3.0, WALL_Z + 0.06), mat("rusty_metal", 1.0, Color(0.25, 0.24, 0.22)))
		var lens := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.07
		lm.bottom_radius = 0.08
		lm.height = 0.16
		lens.mesh = lm
		lens.material_override = _beacon_mat
		world.add_child(lens)
		lens.position = Vector3(bx, 3.13, WALL_Z + 0.08)
		var bl := OmniLight3D.new()
		bl.light_color = Color("ff9a1a")
		bl.light_energy = 0.0
		bl.omni_range = 5.0
		world.add_child(bl)
		bl.position = Vector3(bx, 3.0, WALL_Z + 0.35)
		_beacons.append(bl)

func _build_dressing() -> void:
	var sign_plate := box(Vector3(1.25, 0.46, 0.03), Vector3(-1.33, 2.98, -1.45), mat("painted_concrete", 1.2, Color(0.85, 0.8, 0.66)))
	sign_plate.rotation_degrees = Vector3(4.0, 8.0, -3.0)
	for cx in [-0.5, 0.5]:
		box(Vector3(0.012, 0.75, 0.012), Vector3(cx, 0.6, 0), mat("rusty_metal", 2.0, Color(0.3, 0.28, 0.26)), sign_plate)
	for e in [[Vector3(1.25, 0.04, 0.035), Vector3(0, 0.21, 0)], [Vector3(1.25, 0.04, 0.035), Vector3(0, -0.21, 0)],
			[Vector3(0.04, 0.46, 0.035), Vector3(0.6, 0, 0)], [Vector3(0.04, 0.46, 0.035), Vector3(-0.6, 0, 0)]]:
		box(e[0], e[1], mat("rusty_metal", 1.5, Color(0.6, 0.12, 0.08)), sign_plate)
	var lbl := Label3D.new()
	lbl.text = "NO SMOKING"
	lbl.font_size = 96
	lbl.pixel_size = 0.0021
	lbl.outline_size = 0
	lbl.modulate = Color(0.55, 0.06, 0.04)
	lbl.shaded = true
	sign_plate.add_child(lbl)
	lbl.position = Vector3(0, 0.035, 0.02)
	var sub := Label3D.new()
	sub.text = "BY ORDER OF THE MANAGEMENT"
	sub.font_size = 32
	sub.pixel_size = 0.0019
	sub.outline_size = 0
	sub.modulate = Color(0.18, 0.15, 0.12)
	sub.shaded = true
	sign_plate.add_child(sub)
	sub.position = Vector3(0, -0.13, 0.02)
	var grime := Decal.new()
	grime.texture_albedo = _splat
	grime.modulate = Color(0.2, 0.16, 0.1, 0.8)
	grime.size = Vector3(0.9, 0.1, 0.5)
	grime.rotation_degrees.x = 90.0
	sign_plate.add_child(grime)
	grime.position = Vector3(0.3, -0.05, 0.03)
	var wood := mat("worn_planks", 1.4, Color(0.7, 0.6, 0.5))
	var steel := mat("rusty_metal_02", 1.5)
	var bench := Node3D.new()
	world.add_child(bench)
	bench.position = Vector3(3.75, 0.0, -0.4)
	bench.rotation_degrees.y = -80.0
	for z in [-0.12, 0.0, 0.12]:
		box(Vector3(1.6, 0.04, 0.1), Vector3(0, 0.46, z), wood, bench)
	for x in [-0.7, 0.7]:
		box(Vector3(0.05, 0.46, 0.34), Vector3(x, 0.23, 0), steel, bench)
	prop("cigarette_pack", Vector3(3.72, 0.48, -0.1), 30.0, 1.4)
	prop("old_gas_mask", Vector3(3.8, 0.48, -0.75), -60.0, 1.0)
	var stand := Node3D.new()
	world.add_child(stand)
	stand.position = Vector3(-3.45, 0.0, 0.25)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = 0.85
	var pole := MeshInstance3D.new()
	pole.mesh = cm
	pole.material_override = steel
	stand.add_child(pole)
	pole.position.y = 0.43
	var base_m := CylinderMesh.new()
	base_m.top_radius = 0.16
	base_m.bottom_radius = 0.2
	base_m.height = 0.05
	var base := MeshInstance3D.new()
	base.mesh = base_m
	base.material_override = steel
	stand.add_child(base)
	base.position.y = 0.025
	var bowl_m := CylinderMesh.new()
	bowl_m.top_radius = 0.17
	bowl_m.bottom_radius = 0.1
	bowl_m.height = 0.1
	var bowl := MeshInstance3D.new()
	bowl.mesh = bowl_m
	bowl.material_override = mat("rusty_metal", 2.0, Color(0.5, 0.48, 0.45))
	stand.add_child(bowl)
	bowl.position.y = 0.9
	var ash_m := CylinderMesh.new()
	ash_m.top_radius = 0.155
	ash_m.bottom_radius = 0.155
	ash_m.height = 0.01
	var ash := MeshInstance3D.new()
	ash.mesh = ash_m
	ash.material_override = mat("gravel_floor", 4.0, Color(0.42, 0.4, 0.38))
	stand.add_child(ash)
	ash.position.y = 0.945
	_butts(Vector3(-3.45, 0.955, 0.25), 18, 0.12, 0.0)
	_butts(Vector3(0.0, 0.005, 0.2), 170, 3.6, 1.6)
	var clutter := [["barrel_03", -4.2, -1.9, 0.0, 1.0], ["barrel_03", -3.6, -2.15, 40.0, 1.0], ["metal_trash_can", 4.25, 0.9, 0.0, 0.95],
		["trashbag", 4.2, 1.6, 0.0, 1.0], ["cardboard_box_01", -4.25, 1.1, 20.0, 1.3], ["cardboard_box_01", -4.15, 1.1, -10.0, 1.1],
		["korean_fire_extinguisher_01", 4.45, -1.6, 0.0, 1.0], ["wooden_crate_01", 4.0, -2.0, 15.0, 1.1], ["plastic_crate_01", -4.1, -0.6, 70.0, 1.2],
		["WetFloorSign_01", -3.3, 1.9, 30.0, 1.0], ["propane_tank", 3.6, -2.25, 0.0, 1.0]]
	for c in clutter:
		prop(c[0], Vector3(c[1], 0.0, c[2]), c[3], c[4])
	prop("power_box_01", Vector3(-4.62, 1.5, -1.2), 90.0, 1.2)
	prop("fire_alarm", Vector3(4.62, 2.0, -0.8), -90.0, 1.3)
	prop("industrial_caged_sconce", Vector3(-4.62, 2.5, 0.6), 90.0, 1.3)
	var sc := OmniLight3D.new()
	sc.light_color = Color(1.0, 0.75, 0.45)
	sc.light_energy = 0.9
	sc.omni_range = 3.0
	world.add_child(sc)
	sc.position = Vector3(-4.3, 2.4, 0.6)
	for k in 4:
		var pk := prop("cigarette_pack", Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(0.6, 1.8)), randf() * 360.0, 1.3)
		if pk:
			pk.rotation_degrees.x = 90.0 if k % 2 == 0 else 0.0
			pk.scale = Vector3(1.3, 1.3, 0.6)
			pk.position.y = 0.03 if k % 2 == 0 else 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in 14:
		var d := Decal.new()
		d.texture_albedo = _splat
		var sz := rng.randf_range(0.4, 1.6)
		d.size = Vector3(sz, 0.4, sz * rng.randf_range(0.6, 1.0))
		d.modulate = Color(0.16, 0.15, 0.14, 0.9) if i % 3 != 0 else Color(0.32, 0.3, 0.28, 0.8)
		d.rotation.y = rng.randf() * TAU
		world.add_child(d)
		d.position = Vector3(rng.randf_range(-4.0, 4.0), 0.05, rng.randf_range(-2.2, 2.4))

func _butts(at: Vector3, n: int, spread_x: float, spread_z: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0055
	cm.bottom_radius = 0.0055
	cm.height = 0.032
	cm.radial_segments = 6
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.72, 0.6)
	m.roughness = 0.8
	cm.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	world.add_child(mi)
	mi.position = at
	var sz: float = spread_z if spread_z > 0.0 else spread_x
	for i in n:
		var b := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5)
		var r := pow(randf(), 0.8)
		var a := randf() * TAU
		mm.set_instance_transform(i, Transform3D(b, Vector3(cos(a) * r * spread_x, 0.0055, sin(a) * r * sz)))

func _line_up() -> void:
	var ids: Array = NetworkManager.players.keys()
	var n: int = ids.size()
	var gap: float = minf(0.88, 4.6 / maxf(1.0, float(n - 1)))
	_row_half = gap * float(n - 1) * 0.5
	for i in n:
		var id: int = ids[i]
		var info: Dictionary = NetworkManager.players[id]
		var x: float = -_row_half + gap * float(i)
		var body := LabCharacter.new()
		body.sex = info.get("sex", "male")
		body.hat = info.get("hat", "hardhat")
		body.suit_color = info.color
		body.position = Vector3(x, 0.0, randf_range(-0.08, 0.08))
		body.rotation.y = deg_to_rad(randf_range(8.0, 22.0))
		world.add_child(body)
		body.play_loop("Idle_FoldArms" if i % 2 == 1 else "Idle")
		body.anim.seek(randf() * 2.0, true)
		var arm := SmokeArm.new()
		body.skeleton.add_child(arm)
		arm.setup(body.skeleton)
		arm.influence = 0.0
		var att := BoneAttachment3D.new()
		att.bone_name = "hand_r"
		body.skeleton.add_child(att)
		var cig := _make_cigarette()
		var head := Vector3(x, 1.88, body.position.z)
		var name_l := Label3D.new()
		name_l.text = info.name + ("  (YOU)" if id == multiplayer.get_unique_id() else "")
		name_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_l.no_depth_test = true
		name_l.pixel_size = 0.0009
		name_l.fixed_size = true
		name_l.font_size = 24
		name_l.outline_size = 10
		name_l.modulate = info.color.lightened(0.35)
		name_l.render_priority = 3
		world.add_child(name_l)
		name_l.position = head + Vector3(0, 0.2, 0)
		var count_l := Label3D.new()
		count_l.text = "0.0"
		count_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		count_l.no_depth_test = true
		count_l.pixel_size = 0.0009
		count_l.fixed_size = true
		count_l.font_size = 30
		count_l.outline_size = 12
		count_l.modulate = Color("f2e6c4")
		count_l.render_priority = 3
		world.add_child(count_l)
		count_l.position = head + Vector3(0, 0.12, 0)
		var warn_l := Label3D.new()
		warn_l.text = "SLACKING"
		warn_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		warn_l.no_depth_test = true
		warn_l.pixel_size = 0.0009
		warn_l.fixed_size = true
		warn_l.font_size = 30
		warn_l.outline_size = 12
		warn_l.modulate = Color("ff3b2e")
		warn_l.render_priority = 4
		warn_l.visible = false
		world.add_child(warn_l)
		warn_l.position = head + Vector3(0, 0.3, 0)
		var bar := _bar(head + Vector3(0, 0.04, 0), Color("d01c1c"), 5)
		subjects[id] = {"body": body, "arm": arm, "att": att, "cig": cig, "name": name_l, "count": count_l, "warn": warn_l, "bar": bar, "w": 0.0, "was_in": false}
		smoked[id] = 0.0
		cough[id] = 0.0
		burn[id] = randf_range(0.0, 0.2)
		inhaling[id] = false
		idle_t[id] = 0.0
		holding[id] = false
		hold_t[id] = 0.0
		last_smoke[id] = 0.0
		relight_until[id] = 0.0
		if info.is_bot:
			_bot[id] = {"puff": false, "until": randf_range(0.2, 1.2), "target": 1.0, "react_at": 0.0, "ignore": false, "reckless": false,
				"slack": randf_range(3.6, 5.0) if randf() < 0.7 else randf_range(5.2, 5.85), "risk": randf_range(0.45, 0.7), "greed": randf_range(0.04, 0.16)}

func _make_cigarette() -> Dictionary:
	var root := Node3D.new()
	world.add_child(root)
	var filt := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.0068
	fm.bottom_radius = 0.0068
	fm.height = 0.028
	fm.radial_segments = 10
	fm.rings = 1
	filt.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.85, 0.55, 0.25)
	fmat.roughness = 0.7
	filt.material_override = fmat
	filt.rotation_degrees.x = 90.0
	filt.position.z = -0.014
	root.add_child(filt)
	var paper_pivot := Node3D.new()
	root.add_child(paper_pivot)
	paper_pivot.position.z = -0.028
	var paper := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.0066
	pm.bottom_radius = 0.0066
	pm.height = 1.0
	pm.radial_segments = 10
	pm.rings = 1
	paper.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.95, 0.94, 0.9)
	pmat.roughness = 0.6
	paper.material_override = pmat
	paper.rotation_degrees.x = 90.0
	paper.position.z = -0.5
	paper_pivot.add_child(paper)
	var ember := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.0075
	em.height = 0.012
	em.radial_segments = 8
	em.rings = 4
	ember.mesh = em
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.3, 0.1, 0.05)
	emat.emission_enabled = true
	emat.emission = Color(1.0, 0.38, 0.08)
	emat.emission_energy_multiplier = 2.0
	ember.material_override = emat
	root.add_child(ember)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.15)
	light.light_energy = 0.25
	light.omni_range = 0.45
	light.shadow_enabled = false
	ember.add_child(light)
	var smoke := GPUParticles3D.new()
	smoke.amount = 14
	smoke.lifetime = 2.2
	smoke.local_coords = false
	if not _tip_pm:
		_tip_pm = ParticleProcessMaterial.new()
		_tip_pm.direction = Vector3.UP
		_tip_pm.spread = 12.0
		_tip_pm.initial_velocity_min = 0.08
		_tip_pm.initial_velocity_max = 0.18
		_tip_pm.gravity = Vector3(0, 0.12, 0)
		_tip_pm.damping_min = 0.1
		_tip_pm.damping_max = 0.3
		_tip_pm.scale_min = 0.6
		_tip_pm.scale_max = 1.1
		_tip_pm.scale_curve = _grow_curve(0.25)
		_tip_pm.color_ramp = _smoke_ramp(0.11)
		_tip_pm.turbulence_enabled = true
		_tip_pm.turbulence_noise_strength = 0.4
		_tip_pm.turbulence_noise_scale = 2.0
	smoke.process_material = _tip_pm
	smoke.draw_pass_1 = _smoke_quad(0.1)
	ember.add_child(smoke)
	return {"root": root, "paper": paper_pivot, "ember": ember, "emat": emat, "light": light, "smoke": smoke}

func _grow_curve(start: float) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, start))
	c.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct

func _smoke_ramp(alpha: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(0.72, 0.71, 0.68, alpha))
	g.set_color(1, Color(0.5, 0.5, 0.48, 0.0))
	g.add_point(0.2, Color(0.68, 0.67, 0.64, alpha))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

func _smoke_quad(size: float) -> QuadMesh:
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

func _spawn_supervisor() -> void:
	_sup = LabCharacter.new()
	_sup.sex = "male"
	_sup.hat = "tophat"
	_sup.suit_color = Color(0.36, 0.37, 0.38)
	world.add_child(_sup)
	_sup_x = -_row_half - 0.6
	_sup.position = Vector3(_sup_x, 0.0, PATROL_Z)
	_sup.play_loop("Walk")
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	_sup.skeleton.add_child(att)
	var g: Node3D = load(PH_MOD + "service_pistol/service_pistol.gltf").instantiate()
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm.ends_with("_b") or nm.contains("magazine") or nm.contains("bullet"):
			mi.visible = false
	att.add_child(g)
	var gb := Basis(Vector3(0.03, 0.97, -0.24), Vector3(-0.03, 0.24, 0.97), Vector3(1.0, -0.02, 0.03)).orthonormalized()
	g.transform = Transform3D(gb * Basis.from_scale(Vector3.ONE * 1.9), Vector3(0.0, 0.068, 0.015))
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
	tag.position = Vector3(0, 2.05, 0)

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

func _build_haze() -> void:
	_haze = GPUParticles3D.new()
	_haze.amount = 70
	_haze.lifetime = 1.6
	_haze.emitting = false
	_haze.local_coords = false
	_haze.visibility_aabb = AABB(Vector3(-6, -2, -2), Vector3(12, 6, 10))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3.8, 1.0, 0.2)
	pm.direction = Vector3(0, 0.05, 1)
	pm.spread = 15.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.scale_curve = _grow_curve(0.4)
	pm.color_ramp = _smoke_ramp(0.16)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	_haze.process_material = pm
	_haze.draw_pass_1 = _smoke_quad(0.9)
	world.add_child(_haze)
	_haze.position = Vector3(0, 1.5, FAN_Z + 0.5)

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
	bg.scale = Vector3(0.82, 1.5, 1.0)
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
	fill.scale = Vector3(0.78, 1.0, 1.0)
	fill.region_enabled = true
	fill.region_rect = Rect2(0, 0, 0, 8)
	fill.modulate = col
	fill.render_priority = prio
	world.add_child(fill)
	fill.position = at
	fill.set_meta("bg", bg)
	return fill

func _build_hud() -> void:
	hud_title("SMOKE BREAK  ·  smoke the most, mind the fans")
	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-120, 10)
	_timer_label.size = Vector2(100, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.add_theme_font_size_override("font_size", 26)
	_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_timer_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_timer_label)
	_big = _center_label(72, 0.22)
	_hint = _center_label(24, 0.88)
	_hint.text = "HOLD  SPACE  TO INHALE  ·  RELEASE TO EXHALE\nnot during a GUST  ·  no drags over 1.4 s  ·  stop for 6 s and you get shot"
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
	if down != _space_down:
		if NetworkManager.is_server():
			_set_hold(multiplayer.get_unique_id(), down)
		else:
			_rpc_hold.rpc_id(1, down)
	_space_down = down
	if st == St.PLAY:
		clock += delta
		if NetworkManager.is_server():
			_server_tick(delta)
	_animate_fans(delta)
	_animate_supervisor(delta)
	for id in subjects:
		_animate_subject(id, delta)

func _animate_fans(delta: float) -> void:
	var want: float = 1.2
	if gust == Gust.WARN:
		want = 4.0 + 10.0 * clampf((clock - gust_from) / WARN_TIME, 0.0, 1.0)
	elif gust == Gust.BLOW:
		want = 26.0
	_fan_speed = lerpf(_fan_speed, want, clampf(delta * 2.2, 0.0, 1.0))
	for i in _fans.size():
		_fans[i].rotation.z -= _fan_speed * delta * (1.0 + 0.07 * float(i))
	var flash: float = 0.0
	if gust == Gust.WARN:
		flash = 1.0 if fmod(clock - gust_from, 0.4) < 0.22 else 0.15
	elif gust == Gust.BLOW:
		flash = 1.0 if fmod(clock - gust_from, 0.2) < 0.12 else 0.4
	for b in _beacons:
		b.light_energy = flash * 3.5
		b.light_color = Color("ff9a1a") if gust != Gust.BLOW else Color("ff3a1a")
	_beacon_mat.emission_energy_multiplier = flash * 6.0
	_beacon_mat.emission = Color("ff9a1a") if gust != Gust.BLOW else Color("ff3a1a")
	if gust == Gust.BLOW:
		Fx.shake(0.06)

func _animate_subject(id: int, delta: float) -> void:
	var s: Dictionary = subjects[id]
	var body: LabCharacter = s.body
	var arm: SmokeArm = s.arm
	var on: bool = bool(inhaling.get(id, false)) and not body.is_dead()
	var w: float = move_toward(float(s.w), 1.0 if on else 0.0, delta * (4.5 if on else 3.0))
	s.w = w
	arm.influence = smoothstep(0.0, 1.0, w)
	var cig: Dictionary = s.cig
	var root: Node3D = cig.root
	var att: BoneAttachment3D = s.att
	var hand_xf: Transform3D = att.global_transform * CIG_HAND
	var hd: Vector3 = body.skeleton.get_bone_global_pose(arm.head).origin
	var mouth_pt: Vector3 = body.skeleton.global_transform * (hd + MOUTH + Vector3(-0.01, -0.012, 0.0))
	var fwd: Vector3 = body.global_transform.basis * Vector3(-0.25, -0.3, 1.0)
	var mouth_xf := Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), mouth_pt)
	var k: float = smoothstep(0.55, 1.0, w)
	root.global_transform = hand_xf.interpolate_with(mouth_xf, k)
	var b: float = float(burn.get(id, 0.0))
	var paper: Node3D = cig.paper
	var plen: float = 0.085 * (1.0 - 0.8 * b)
	paper.scale = Vector3(1.0, 1.0, plen)
	var ember: MeshInstance3D = cig.ember
	ember.position = Vector3(0, 0, -0.028 - plen - 0.002)
	var emat: StandardMaterial3D = cig.emat
	var light: OmniLight3D = cig.light
	var glow: float = 1.0 if on else 0.0
	if body.is_dead():
		glow = -0.6
	emat.emission_energy_multiplier = lerpf(emat.emission_energy_multiplier, 2.0 + glow * 3.5 + randf() * 0.5, clampf(delta * 10.0, 0.0, 1.0))
	light.light_energy = lerpf(light.light_energy, 0.3 + glow * 1.0, clampf(delta * 10.0, 0.0, 1.0))
	(cig.smoke as GPUParticles3D).emitting = w < 0.3 and not body.is_dead()
	if bool(s.was_in) and not on and not body.is_dead():
		_exhale(id)
	s.was_in = on
	var c: float = float(cough.get(id, 0.0))
	var bar: Sprite3D = s.bar
	if bar.visible:
		bar.region_rect = Rect2(0, 0, maxf(0.001, clampf(c, 0.0, 1.0) * BAR_PX), 8)
		bar.modulate = Color("d01c1c") if c < 0.7 or fmod(clock, 0.24) < 0.12 else Color("ffe14a")
	var cl: Label3D = s.count
	if not body.is_dead():
		cl.text = "%.1f" % float(smoked.get(id, 0.0))
	var wl: Label3D = s.warn
	var it: float = float(idle_t.get(id, 0.0))
	wl.visible = st == St.PLAY and not body.is_dead() and it > SLACK_WARN and fmod(clock, 0.3) < 0.2

func _exhale(id: int) -> void:
	var s: Dictionary = subjects[id]
	var body: LabCharacter = s.body
	var arm: SmokeArm = s.arm
	var hd: Vector3 = body.skeleton.get_bone_global_pose(arm.head).origin
	var at: Vector3 = body.skeleton.global_transform * (hd + MOUTH)
	var fwd: Vector3 = (body.global_transform.basis * Vector3(-0.55, 0.75, 0.45)).normalized()
	var blow_back: bool = gust == Gust.BLOW
	_puff(at, fwd if not blow_back else Vector3(0, 0.6, -0.4), 16 if not blow_back else 26, 0.9 if not blow_back else 0.5, 0.09 if not blow_back else 0.14)

func _puff(at: Vector3, dir: Vector3, n: int, spd: float, alpha: float) -> void:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.amount = n
	gp.lifetime = 1.8
	gp.explosiveness = 0.75
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = 28.0
	pm.initial_velocity_min = spd * 0.5
	pm.initial_velocity_max = spd
	pm.gravity = Vector3(0, 0.18, 0) if gust != Gust.BLOW else Vector3(0, 0.2, 1.8)
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.scale_curve = _grow_curve(0.2)
	pm.color_ramp = _smoke_ramp(alpha)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	gp.process_material = pm
	gp.draw_pass_1 = _smoke_quad(0.32)
	world.add_child(gp)
	gp.global_position = at
	gp.emitting = true
	get_tree().create_timer(2.4).timeout.connect(gp.queue_free)

func _animate_supervisor(delta: float) -> void:
	if _shooting or _sup == null:
		return
	if st == St.DONE:
		_sup.play_loop("Idle")
		return
	_sup_x += _sup_dir * 0.85 * delta
	var lim: float = _row_half + 0.5
	if _sup_x > lim:
		_sup_dir = -1.0
	elif _sup_x < -lim:
		_sup_dir = 1.0
	_sup.position = Vector3(_sup_x, 0.0, PATROL_Z)
	_sup.rotation.y = lerp_angle(_sup.rotation.y, PI * 0.5 * _sup_dir, clampf(delta * 6.0, 0.0, 1.0))
	_sup.play_loop("Walk")

func _server_tick(delta: float) -> void:
	_server_gust()
	for id in subjects:
		if dead_order.has(id):
			continue
		var on: bool = bool(holding[id]) and clock >= float(relight_until[id])
		if on:
			hold_t[id] = float(hold_t[id]) + delta
			burn[id] = float(burn[id]) + delta / BURN_TIME
			smoked[id] = float(smoked[id]) + delta / BURN_TIME
			last_smoke[id] = clock
			var g: float = COUGH_BASE
			if gust == Gust.BLOW:
				g += COUGH_GUST
			if float(hold_t[id]) > LONG_DRAG:
				g += COUGH_LONG
			cough[id] = float(cough[id]) + g * delta
			if float(burn[id]) >= 1.0:
				burn[id] = 0.0
				hold_t[id] = 0.0
				relight_until[id] = clock + RELIGHT
				_rpc_relight.rpc(id)
		else:
			if not bool(holding[id]):
				hold_t[id] = 0.0
			cough[id] = maxf(0.0, float(cough[id]) - COUGH_DRAIN * delta)
		inhaling[id] = on
		idle_t[id] = clock - float(last_smoke[id])
		if float(cough[id]) >= 1.0:
			cough[id] = 1.0
			dead_order.append(id)
			_rpc_cough_out.rpc(id)
		elif float(idle_t[id]) >= SLACK_LIMIT and not _shoot_queue.has(id):
			_shoot_queue.append(id)
	for id in _bot:
		_bot_think(id)
	if not _shooting and not _shoot_queue.is_empty():
		_shoot_next()
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.08
		_rpc_sync.rpc(smoked, cough, burn, inhaling, idle_t, maxf(0.0, TIME_LIMIT - clock))

func _server_gust() -> void:
	if gust == Gust.CALM and clock >= _next_gust and clock < TIME_LIMIT - 3.6:
		_rpc_gust.rpc(Gust.WARN, clock)
		for id in _bot:
			var b: Dictionary = _bot[id]
			b.react_at = clock + (randf_range(0.2, 0.55) if randf() > 0.2 else randf_range(0.7, 1.3))
			b.ignore = randf() < float(b.greed)
			b.reckless = bool(b.ignore) and randf() < 0.5
	elif gust == Gust.WARN and clock >= gust_from + WARN_TIME:
		_rpc_gust.rpc(Gust.BLOW, clock)
	elif gust == Gust.BLOW and clock >= gust_from + GUST_TIME:
		_rpc_gust.rpc(Gust.CALM, clock)
		_next_gust = clock + randf_range(4.0, 7.0)

func _bot_think(id: int) -> void:
	if dead_order.has(id) or _shoot_queue.has(id):
		if holding[id]:
			_set_hold(id, false)
		return
	var b: Dictionary = _bot[id]
	var danger: bool = gust != Gust.CALM and clock >= float(b.react_at) and not bool(b.ignore)
	var desperate: bool = float(idle_t[id]) > float(b.slack)
	if bool(b.puff):
		var stop: bool = float(hold_t[id]) >= float(b.target) or (danger and not desperate) or (float(cough[id]) > float(b.risk) + 0.25 and not (bool(b.reckless) and gust == Gust.BLOW))
		if desperate and float(hold_t[id]) < 0.25:
			stop = false
		if stop:
			b.puff = false
			b.until = clock + randf_range(0.35, 1.1)
			_set_hold(id, false)
	else:
		var ready: bool = clock >= float(b.until) and not danger and float(cough[id]) < float(b.risk)
		if ready or desperate:
			b.puff = true
			var greedy: bool = randf() < float(b.greed) * 0.6
			b.target = randf_range(1.6, 2.6) if greedy else randf_range(0.75, 1.3)
			if desperate and not ready:
				b.target = randf_range(0.3, 0.6)
			_set_hold(id, true)

@rpc("any_peer", "reliable")
func _rpc_hold(down: bool) -> void:
	if NetworkManager.is_server():
		_set_hold(multiplayer.get_remote_sender_id(), down)

func _set_hold(id: int, down: bool) -> void:
	if not subjects.has(id):
		return
	holding[id] = down and st == St.PLAY and not dead_order.has(id)

func _shoot_next() -> void:
	var id: int = _shoot_queue.pop_front()
	if dead_order.has(id):
		return
	dead_order.append(id)
	_rpc_shoot.rpc(id)

func _alive_count() -> int:
	return subjects.size() - dead_order.size()

func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	for n in ["3", "2", "1"]:
		_rpc_big.rpc(n, "e8e2c8")
		Fx.sfx("click")
		await get_tree().create_timer(0.8).timeout
	_rpc_start.rpc()
	while clock < TIME_LIMIT and _alive_count() > 0:
		await get_tree().process_frame
	while _shooting:
		await get_tree().process_frame
	_rpc_end.rpc(smoked, cough)
	await get_tree().create_timer(2.6).timeout
	if not _ended:
		_ended = true
		finished.emit(_placement())

func _placement() -> Array:
	var living: Array = subjects.keys().filter(func(id): return not dead_order.has(id))
	living.sort_custom(func(a, b): return float(smoked[a]) > float(smoked[b]))
	var out: Array = living
	for i in range(dead_order.size() - 1, -1, -1):
		out.append(dead_order[i])
	return out

@rpc("authority", "call_local", "reliable")
func _rpc_big(text: String, hex: String) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", Color(hex))
	_big.modulate.a = 1.0

@rpc("authority", "call_local", "reliable")
func _rpc_start() -> void:
	st = St.PLAY
	clock = 0.0
	_rpc_big("LIGHT UP!", "f0a040")
	Fx.sfx("click", null, -2.0, 0.8)
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(_big, "modulate:a", 0.0, 0.4)
	var th := create_tween()
	th.tween_interval(5.0)
	th.tween_property(_hint, "modulate:a", 0.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_gust(phase: int, at: float) -> void:
	gust = phase as Gust
	gust_from = at
	if gust == Gust.WARN:
		_rpc_big("FANS SPINNING UP", "ffa21a")
		Fx.sfx("beep", null, -2.0, 0.8)
		Fx.sfx("hum", null, -6.0, 0.7)
	elif gust == Gust.BLOW:
		_rpc_big("GUST!  DON'T INHALE", "ff3b2e")
		Fx.sfx("whoosh", null, 2.0, 0.6)
		Fx.sfx("hum", null, 0.0, 1.2)
		_haze.emitting = true
		_tip_pm.gravity = Vector3(0, 0.3, 2.6)
	else:
		_haze.emitting = false
		_tip_pm.gravity = Vector3(0, 0.12, 0)
		var tw := create_tween()
		tw.tween_property(_big, "modulate:a", 0.0, 0.3)

@rpc("authority", "call_local", "reliable")
func _rpc_relight(id: int) -> void:
	var s: Dictionary = subjects[id]
	var cig: Dictionary = s.cig
	var ember: MeshInstance3D = cig.ember
	Fx.sfx("click", ember.global_position, -6.0, randf_range(1.2, 1.5))
	var flame := OmniLight3D.new()
	flame.light_color = Color(1.0, 0.7, 0.3)
	flame.light_energy = 2.5
	flame.omni_range = 1.0
	world.add_child(flame)
	flame.global_position = ember.global_position + Vector3(0, 0.05, 0.05)
	var tw := flame.create_tween()
	tw.tween_property(flame, "light_energy", 0.0, 0.5)
	tw.tween_callback(flame.queue_free)
	_puff(ember.global_position, Vector3.UP, 6, 0.3, 0.15)
	var butt := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0065
	cm.bottom_radius = 0.0065
	cm.height = 0.04
	butt.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.62, 0.4)
	butt.material_override = m
	world.add_child(butt)
	var body: LabCharacter = s.body
	var land: Vector3 = body.position + Vector3(randf_range(-0.3, 0.3), 0.007, randf_range(0.15, 0.55))
	butt.global_position = ember.global_position
	var bt := butt.create_tween()
	bt.tween_property(butt, "global_position", land, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	bt.parallel().tween_property(butt, "rotation", Vector3(PI * 0.5, randf() * TAU, 0), 0.45)

@rpc("authority", "call_local", "reliable")
func _rpc_cough_out(id: int) -> void:
	if not dead_order.has(id):
		dead_order.append(id)
	inhaling[id] = false
	var s: Dictionary = subjects[id]
	var body: LabCharacter = s.body
	var arm: SmokeArm = s.arm
	(s.name as Label3D).text = NetworkManager.players[id].name + "  ·  COUGHED UP A LUNG"
	(s.name as Label3D).modulate.a = 0.7
	_hide_hud(s)
	for k in 4:
		get_tree().create_timer(0.3 * float(k)).timeout.connect(func() -> void:
			if not is_instance_valid(body):
				return
			body.anim.play("Hit_Chest", 0.05, 1.3)
			var hd: Vector3 = body.skeleton.get_bone_global_pose(arm.head).origin
			var at: Vector3 = body.skeleton.global_transform * (hd + MOUTH)
			_puff(at, (body.global_transform.basis * Vector3(0, -0.2, 1)).normalized(), 12, 1.4, 0.2)
			Fx.sfx("hit", at, -8.0, randf_range(0.6, 0.8))
		)
	get_tree().create_timer(1.25).timeout.connect(func() -> void:
		if not is_instance_valid(body):
			return
		body.die("Death01")
		var hd: Vector3 = body.skeleton.get_bone_global_pose(arm.head).origin
		var at: Vector3 = body.skeleton.global_transform * (hd + MOUTH)
		Fx.blood(world, at, 70)
		_mouth_blood(at, body)
		Fx.sfx("buzzer", null, -4.0)
		Fx.shake(0.3)
	)

func _mouth_blood(at: Vector3, body: LabCharacter) -> void:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.amount = 40
	gp.lifetime = 1.0
	gp.explosiveness = 0.6
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = (body.global_transform.basis * Vector3(0, 0.2, 1)).normalized()
	pm.spread = 20.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, -9.8, 0)
	gp.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.014
	sm.height = 0.028
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.02, 0.03)
	m.roughness = 0.25
	sm.material = m
	gp.draw_pass_1 = sm
	world.add_child(gp)
	gp.global_position = at
	gp.emitting = true
	get_tree().create_timer(1.6).timeout.connect(gp.queue_free)
	var d := Decal.new()
	d.texture_albedo = _splat
	d.modulate = Color(0.5, 0.02, 0.03)
	d.size = Vector3(0.9, 0.6, 0.7)
	world.add_child(d)
	d.global_position = Vector3(at.x, 0.1, at.z) + body.global_transform.basis * Vector3(0, 0, 0.5)

@rpc("authority", "call_local", "reliable")
func _rpc_shoot(id: int) -> void:
	if not dead_order.has(id):
		dead_order.append(id)
	inhaling[id] = false
	_shooting = true
	var s: Dictionary = subjects[id]
	var body: LabCharacter = s.body
	_hide_hud(s)
	(s.name as Label3D).text = NetworkManager.players[id].name + "  ·  SLACKING"
	(s.name as Label3D).modulate = Color("ff6a5a")
	var aim_from := Vector3(clampf(body.position.x + (0.45 if _sup_x > body.position.x else -0.45), -_row_half - 0.6, _row_half + 0.6), 0.0, PATROL_Z + 0.15)
	var tw := create_tween()
	_sup.play_loop("Walk")
	tw.tween_property(_sup, "position", aim_from, clampf(_sup.position.distance_to(aim_from) / 2.2, 0.15, 0.9))
	tw.tween_callback(func() -> void:
		var to: Vector3 = body.position - _sup.position
		_sup.rotation.y = atan2(to.x, to.z)
		_sup_mod.active = false
		_sup.play_action("Pistol_Shoot", 0.05)
	)
	tw.tween_interval(0.22)
	tw.tween_callback(func() -> void:
		Fx.sfx("gunshot", _sup.position + Vector3(0, 1.4, 0), 2.0)
		var flash := OmniLight3D.new()
		flash.light_color = Color(1.0, 0.75, 0.4)
		flash.light_energy = 6.0
		flash.omni_range = 3.0
		world.add_child(flash)
		flash.global_position = _sup.position + Vector3(0, 1.4, 0) + _sup.global_transform.basis.z * 0.6
		var ft := flash.create_tween()
		ft.tween_property(flash, "light_energy", 0.0, 0.12)
		ft.tween_callback(flash.queue_free)
		body.die("Death01")
		Fx.blood(world, body.position + Vector3(0, 1.25, 0))
		Fx.shake(0.4)
	)
	tw.tween_interval(0.7)
	tw.tween_callback(func() -> void:
		_sup_x = _sup.position.x
		_sup_mod.active = true
		_sup.play_loop("Walk")
		_shooting = false
	)

func _hide_hud(s: Dictionary) -> void:
	var bar: Sprite3D = s.bar
	bar.visible = false
	(bar.get_meta("bg") as Sprite3D).visible = false
	(s.warn as Label3D).visible = false

@rpc("authority", "call_local", "unreliable_ordered")
func _rpc_sync(sm: Dictionary, c: Dictionary, bu: Dictionary, inh: Dictionary, it: Dictionary, time_left: float) -> void:
	smoked = sm
	cough = c
	burn = bu
	inhaling = inh
	idle_t = it
	_timer_label.text = "%d s" % int(ceil(time_left))

@rpc("authority", "call_local", "reliable")
func _rpc_end(sm: Dictionary, c: Dictionary) -> void:
	st = St.DONE
	smoked = sm
	cough = c
	for id in inhaling:
		inhaling[id] = false
	gust = Gust.CALM
	_haze.emitting = false
	_rpc_big("BREAK'S OVER", "e2c84b")
	Fx.sfx("buzzer", null, -6.0, 1.3)
