extends ArenaMinigame3D
## Duck Hunt: a night scrapyard behind the lab. One subject is the Hunter, up a
## sniper tower with a bolt-action rifle, a laser sight everyone can see and
## limited ammo. The hunter relocates between two corner towers mid-round, and
## campers get spotted, then shocked out of cover. Everyone else runs between
## cover. Runners can win outright: carry 3 fuses to the fuse box, then ride the
## lift up the hunter's tower and execute him. A body hit leaves a runner
## limping, a second hit or a headshot kills. Hunter places by kills; runners
## place by survival time (survivors first, then the hunter, then the dead in
## reverse death order). If the hunter clears the yard, the hunter wins.

const ROUND_TIME: float = 45.0
const AMMO: int = 10
const BOLT_TIME: float = 1.2
const FOV_WIDE: float = 55.0
const FOV_ZOOM: float = 18.0
const RUN_SPEED: float = 4.3
const SPRINT_SPEED: float = 7.0
const LIMP: float = 0.62
const STAMINA_MAX: float = 2.6
const TOWERS := [Vector3(-1.2, 0.0, -1.4), Vector3(17.2, 0.0, 11.4)]
const PLATFORM_Y: float = 4.0
const CRATES := Vector3(8.2, 0.0, 1.4)
const FUSEBOX := Vector3(8.0, 0.0, 4.6)
const LIFTS := [Vector3(0.8, 0.0, 0.8), Vector3(15.2, 0.0, 9.2)]
const FUSES: int = 3
const CARRY_SLOW: float = 0.85
const BOX_HOLD: float = 1.0
const LIFT_HOLD: float = 1.5
const CABINET := Vector3(4.6, 0.0, 9.2)
const RELOCATE_AT := [20.0, 35.0]
const CAMP_RADIUS: float = 2.0
const SPOT_TIME: float = 5.0
const SHOCK_TIME: float = 8.0

static var _hunted: Array = []

var hunter: int = 0
var _tower: int = 0
var _eye := Vector3.ZERO
var _eyes: Array = []
var _tower_yaws: Array = []
var _relocating: bool = false
var _ended: bool = false
var _camp: Dictionary = {}
var _spotted: Dictionary = {}
var _spot_ms: Dictionary = {}
var _markers: Dictionary = {}
var _stun: Dictionary = {}
var _spot_sets: Array = []
var _rim_shader: Shader
var _black: ColorRect
var _reloc_label: Label
var _warn: Label
var _fuse_nodes: Array = []
var _fuse_pos: Array = []
var _fuse_state: Array = []
var _fuses_in: int = 0
var _lift_online: bool = false
var _executor: int = 0
var _hold: Dictionary = {}
var _hold_t: Dictionary = {}
var _hold_sent: bool = false
var _hold_local: float = 0.0
var _bot_role: Dictionary = {}
var _box_bulbs: Array = []
var _lift_cars: Array = []
var _lift_roofs: Array = []
var _lift_lamps: Array = []
var _lift_lights: Array = []
var _obj_label: Label
var _arrow: Label
var _hold_label: Label
var _dead_view: bool = false
var elim_order: Array = []
var _hits: Dictionary = {}
var _ammo: int = AMMO
var _live: bool = false
var _done: bool = false
var _time_left: float = ROUND_TIME
var _last_shot_ms: int = -100000
var _srv_shot_ms: int = -100000
var _yaw: float = 0.0
var _pitch: float = -0.62
var _aim := Vector3(0.0, -0.58, 0.81).normalized()
var _aim_send_t: float = 0.0
var _zoom: float = 0.0
var _kick: float = 0.0
var _stamina: float = STAMINA_MAX
var _fire_was_down: bool = false
var _solids: Array = []
var _bot: Dictionary = {}
var _bh_target: int = 0
var _bh_aim := Vector3(0.0, -0.58, 0.81).normalized()
var _bh_hold: float = 0.0
var _bh_need: float = 0.5
var _bh_react: float = 0.0
var _bh_head: bool = false
var _bh_check: float = 0.0
var _bh_sweep: float = 0.0
var _bh_vis: bool = false

var _laser: MeshInstance3D
var _laser_dot: MeshInstance3D
var _laser_light: OmniLight3D
var _viewmodel: Node3D
var _rifle: Node3D
var _muzzle: Marker3D
var _bolt_parts: Array = []
var _scope: ColorRect
var _dot: ColorRect
var _info: Label
var _ammo_label: Label
var _status: Label
var _hint: Label
var _flash_label: Label
var _stamina_bar: ProgressBar
var _fence_panel: Node3D
var _fence_post: Node3D

func begin() -> void:
	setup_arena(false)
	_night()
	_build_yard()
	for i in TOWERS.size():
		_build_tower(i)
	_eye = _eyes[0]
	_build_laser()
	spawn_players(_spawns())
	for id in players:
		players[id].speed = RUN_SPEED
		players[id].bot_brain = _bot_brain.bind(id)
		_hits[id] = 0
	hud_title("DUCK HUNT  ·  stay out of the laser")
	_build_hud()
	_runner_cam(W * 0.5)
	if NetworkManager.is_server():
		_run.call_deferred()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _spawns() -> Array:
	var pts := [Vector3(1.8, 0, 5.6), Vector3(6.6, 0, 5.4), Vector3(11.4, 0, 3.6), Vector3(15.0, 0, 3.8),
		Vector3(6.0, 0, 7.0), Vector3(8.6, 0, 9.4), Vector3(12.0, 0, 9.6), Vector3(2.2, 0, 0.7)]
	return pts

func _night() -> void:
	env.background_color = Color("05060a")
	env.ambient_light_color = Color(0.42, 0.48, 0.62)
	env.ambient_light_energy = 0.62
	env.fog_light_color = Color(0.07, 0.08, 0.11)
	env.fog_density = 0.03
	env.adjustment_saturation = 0.7
	env.tonemap_exposure = 1.25
	for c in world.get_children():
		if c is DirectionalLight3D:
			var dl: DirectionalLight3D = c
			dl.light_color = Color(0.62, 0.72, 1.0)
			dl.light_energy = 0.32
			dl.rotation_degrees = Vector3(-50.0, 150.0, 0.0)

func _solid(center: Vector3, size: Vector3, yaw_deg: float = 0.0) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	world.add_child(sb)
	sb.position = center
	sb.rotation_degrees.y = yaw_deg
	_solids.append({"c": center, "s": size, "yaw": yaw_deg})

func _build_yard() -> void:
	box(Vector3(70.0, 0.2, 70.0), Vector3(W * 0.5, -0.1, D * 0.5), mat("gravel_floor", 0.45))
	box(Vector3(W + 1.5, 0.04, D + 1.5), Vector3(W * 0.5, 0.0, D * 0.5), mat("damaged_concrete_floor", 0.3, Color(0.85, 0.85, 0.85)))
	box(Vector3(5.0, 0.05, 4.0), Vector3(13.6, 0.0, 1.4), mat("dirty_concrete", 0.4))
	box(Vector3(70.0, 0.04, 6.0), Vector3(W * 0.5, 0.0, D + 8.5), mat("asphalt_02", 0.3))
	box(Vector3(10.0, 0.05, 5.0), Vector3(W * 0.5, 0.0, -3.0), mat("concrete_floor_worn_001", 0.35))
	_container(Vector3(3.0, 0.0, 3.0), Vector3(4.6, 2.6, 2.4), Color(0.95, 0.55, 0.4))
	_container(Vector3(13.2, 0.0, 6.4), Vector3(2.4, 2.6, 5.8), Color(0.55, 0.72, 0.66))
	prop("covered_car", Vector3(9.4, 0.0, 7.8), 82.0)
	_solid(Vector3(9.4, 0.7, 7.8), Vector3(1.8, 1.4, 4.4), 82.0)
	var stack := [[0.0, 0.0], [12.0, 0.04], [-8.0, -0.05], [20.0, 0.06], [4.0, -0.02], [-15.0, 0.03], [8.0, 0.0]]
	for i in stack.size():
		prop("old_military_crate", Vector3(CRATES.x + stack[i][1], i * 0.3, CRATES.z), stack[i][0])
	_solid(CRATES + Vector3(0, 1.05, 0), Vector3(1.9, 2.1, 1.1))
	prop("wooden_crate_01", CRATES + Vector3(-0.2, 2.1, 0), 25.0)
	box(Vector3(1.5, 2.1, 0.9), CABINET + Vector3(0, 1.05, 0), _dull("green_metal_rust", 0.8, Color(0.95, 1.0, 0.95)), null, true)
	box(Vector3(1.6, 0.08, 1.0), CABINET + Vector3(0, 2.12, 0), _dull("rusty_metal", 0.8, Color(0.8, 0.8, 0.8)))
	prop("power_box_01", CABINET + Vector3(-0.5, 1.3, 0.47), 0.0, 1.4)
	prop("modular_electric_cables", CABINET + Vector3(0.4, 0.0, 0.6), 0.0, 1.0)
	_solids.append({"c": CABINET + Vector3(0, 1.05, 0), "s": Vector3(1.5, 2.1, 0.9), "yaw": 0.0})
	for k in 7:
		var tyre := prop("old_tyre", Vector3(11.0, 0.085 + k * 0.165, 1.8), k * 23.0)
		if tyre:
			tyre.rotation_degrees.x = 90.0
	for k in 5:
		var tyre2 := prop("old_tyre", Vector3(11.75, 0.085 + k * 0.165, 2.35), k * 41.0)
		if tyre2:
			tyre2.rotation_degrees.x = 90.0
	_solid(Vector3(11.35, 0.6, 2.05), Vector3(1.4, 1.2, 1.2))
	for b in [Vector3(1.0, 0, 7.9), Vector3(1.7, 0, 8.4), Vector3(1.15, 0, 8.95), Vector3(0.5, 0, 8.4)]:
		prop("barrel_03", b, randf() * 360.0)
	_solid(Vector3(1.1, 0.47, 8.4), Vector3(1.8, 0.94, 1.7))
	var tipped := prop("barrel_03", Vector3(2.6, 0.32, 7.6), 30.0)
	if tipped:
		tipped.rotation_degrees.z = 90.0
	for rb in [[Vector3(4.0, 0, 8.1), 0.0], [Vector3(5.65, 0, 8.25), 6.0], [Vector3(13.4, 0, 1.2), 5.0], [Vector3(2.4, 0, 6.6), 80.0]]:
		prop("concrete_road_barrier", rb[0], rb[1])
		_solid(rb[0] + Vector3(0, 0.42, 0), Vector3(1.55, 0.84, 0.64), rb[1])
	prop("portable_generator", Vector3(6.4, 0, 9.3), 190.0, 1.3)
	_solid(Vector3(6.4, 0.38, 9.3), Vector3(1.05, 0.76, 0.75), 190.0)
	prop("portable_generator", Vector3(15.5, 0, 5.8), 80.0, 1.3)
	prop("metal_jerrycan", Vector3(15.8, 0, 6.6), 20.0)
	prop("propane_tank", Vector3(0.4, 0, 2.6), 0.0)
	prop("cement_bag", Vector3(3.0, 0, 4.5), 40.0)
	prop("trashbag", Vector3(14.6, 0, 9.8), 0.0)
	prop("wooden_crate_02", Vector3(10.4, 0, 9.6), -12.0)
	prop("plastic_crate_01", Vector3(10.8, 0, 6.1), 30.0)
	prop("old_tyre", Vector3(6.3, 0.3, 4.6), 70.0)
	prop("can_rusted", Vector3(6.6, 0, 3.9), 0.0)
	_build_fusebox()
	for i in LIFTS.size():
		_build_lift(i)
	_refresh_lifts()
	for n in [Vector3(0.6, 0, 4.2), Vector3(6.2, 0, 2.2), Vector3(15.6, 0, 5.0), Vector3(10.4, 0, 0.6), Vector3(3.0, 0, 0.4)]:
		prop("nettle_plant", n, randf() * 360.0, 1.6)
	_fence_parts()
	_fence_line(Vector3(-3.0, 0, -6.5), Vector3(19.0, 0, -6.5))
	_fence_line(Vector3(-3.0, 0, -6.5), Vector3(-3.0, 0, 14.5))
	_fence_line(Vector3(19.0, 0, -6.5), Vector3(19.0, 0, 14.5))
	_fence_line(Vector3(-3.0, 0, 14.5), Vector3(19.0, 0, 14.5))
	for gx in [-2.0, 3.0, 9.0, 14.5]:
		prop("grass_medium_01", Vector3(gx, 0, 14.0), randf_range(-10, 10), 1.0)
		prop("grass_medium_01", Vector3(gx + 2.0, 0, -6.0), randf_range(170, 190), 1.0)
	for gz in [-3.0, 3.0, 9.0]:
		prop("grass_medium_01", Vector3(-2.6, 0, gz), 90.0, 1.0)
		prop("grass_medium_01", Vector3(18.6, 0, gz), -90.0, 1.0)
	for s in [Vector3(-7.0, 0, 15.0), Vector3(2.0, 0, 16.5), Vector3(11.0, 0, 15.6), Vector3(21.0, 0, 15.0), Vector3(-6.5, 0, 4.0), Vector3(23.0, 0, 5.0), Vector3(-6.0, 0, -8.0), Vector3(23.0, 0, -8.5)]:
		prop("shrub_02", s, randf() * 360.0, randf_range(0.9, 1.3))
	for o in [["barrel_03", -5.0, 13.6], ["old_tyre", -4.4, 14.1], ["wooden_crate_02", 20.5, 13.8], ["portable_generator", 21.0, 11.0], ["metal_trash_can", 20.6, -4.0],
			["old_military_crate", -5.0, 8.0], ["propane_tank", -4.6, -2.0], ["barrel_03", 21.0, 2.0], ["trashbag", 17.8, 11.6], ["cardboard_box_01", -2.0, 11.4]]:
		prop(o[0], Vector3(o[1], 0, o[2]), randf() * 360.0, 1.1)
	_lab_wall()
	_sconce(Vector3(11.95, 2.3, 8.6), -90.0)
	_sconce(Vector3(3.0, 2.3, 4.25), 0.0)
	_sconce(Vector3(13.2, 2.3, 9.35), 0.0)
	for sl in [[Vector3(-1.8, 0, 2.6), 1.0], [Vector3(17.8, 0, 0.5), -1.0], [Vector3(-1.8, 0, 8.0), 1.0], [Vector3(17.8, 0, 7.6), -1.0]]:
		_security_light(sl[0], sl[1])

func _glow_mat(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m

func _build_fusebox() -> void:
	prop("portable_generator", FUSEBOX + Vector3(0.0, 0.0, 0.1), 0.0, 1.7)
	box(Vector3(1.0, 0.75, 0.18), FUSEBOX + Vector3(0, 0.38, -0.55), _dull("green_metal_rust", 1.2, Color.WHITE))
	box(Vector3(1.0, 0.06, 0.24), FUSEBOX + Vector3(0, 0.78, -0.55), _dull("rusty_metal", 1.2, Color.WHITE))
	_solid(FUSEBOX + Vector3(0, 0.45, -0.15), Vector3(1.3, 0.9, 1.0))
	var to_a: Vector3 = (TOWERS[1] as Vector3) - FUSEBOX
	to_a.y = 0.0
	var wyaw := rad_to_deg(atan2(to_a.x, to_a.z))
	var wc := FUSEBOX + to_a.normalized() * 0.9 + Vector3(0, 0.95, 0)
	var wall := box(Vector3(2.0, 1.9, 0.1), wc, _dull("corrugated_iron", 0.7, Color(0.75, 0.7, 0.6)))
	wall.rotation_degrees.y = wyaw
	for k in [-1.15, 1.15]:
		var post := box(Vector3(0.1, 2.0, 0.1), wc + Vector3(k * 0.87, 0.05, 0.08).rotated(Vector3.UP, deg_to_rad(wyaw)), _dull("rusty_metal_02", 1.2, Color.WHITE))
		post.rotation_degrees.y = wyaw
	_solid(wc, Vector3(2.0, 1.9, 0.14), wyaw)
	for i in FUSES:
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		b.mesh = sm
		b.material_override = _glow_mat(Color(0.9, 0.1, 0.05), 2.5)
		world.add_child(b)
		b.position = FUSEBOX + Vector3(-0.3 + i * 0.3, 0.55, -0.66)
		_box_bulbs.append(b)
	var lb := Label3D.new()
	lb.text = "FUSE BOX"
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.font_size = 40
	lb.pixel_size = 0.006
	lb.outline_size = 8
	lb.modulate = Color(1.0, 0.85, 0.4)
	world.add_child(lb)
	lb.position = FUSEBOX + Vector3(0, 1.45, 0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.3)
	l.light_energy = 1.4
	l.omni_range = 3.0
	world.add_child(l)
	l.position = FUSEBOX + Vector3(0, 1.0, -0.9)

func _build_lift(i: int) -> void:
	var base: Vector3 = LIFTS[i]
	var metal := _dull("rusty_metal_02", 1.2, Color(0.85, 0.85, 0.8))
	box(Vector3(1.4, 0.1, 1.4), base + Vector3(0, 0.05, 0), mat("metal_grate_rusty", 1.2))
	var tower: Vector3 = TOWERS[i]
	var side := (Vector3(tower.x, 0, tower.z) - base).normalized()
	for k in [-1.0, 1.0]:
		var off: Vector3 = side.rotated(Vector3.UP, PI * 0.5) * 0.62 * k
		box(Vector3(0.1, PLATFORM_Y + 0.3, 0.1), base + off + Vector3(0, (PLATFORM_Y + 0.3) * 0.5, 0), metal)
	box(Vector3(1.4, 0.12, 0.12), base + Vector3(0, PLATFORM_Y + 0.25, 0), metal)
	var car := Node3D.new()
	world.add_child(car)
	car.position = base
	box(Vector3(1.2, 0.08, 1.2), Vector3(0, 0.12, 0), metal, car)
	for cx in [-0.55, 0.55]:
		for cz in [-0.55, 0.55]:
			box(Vector3(0.05, 1.1, 0.05), Vector3(cx, 0.65, cz), metal, car)
	for cx in [-0.7, 0.7]:
		for cz in [-0.7, 0.7]:
			box(Vector3(0.06, 2.1, 0.06), Vector3(cx, 1.15, cz), metal, car)
	var roof := box(Vector3(1.6, 0.08, 1.6), Vector3(0, 2.2, 0), _dull("corrugated_iron", 0.8, Color(0.6, 0.62, 0.55)), car, true)
	_lift_roofs.append(roof)
	_lift_cars.append(car)
	var lamp := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.3, 0.2, 0.3)
	lamp.mesh = lm
	lamp.material_override = _glow_mat(Color(0.6, 0.05, 0.03), 1.0)
	world.add_child(lamp)
	lamp.position = base + Vector3(0, PLATFORM_Y + 0.42, 0)
	_lift_lamps.append(lamp)
	var ll := OmniLight3D.new()
	ll.light_color = Color(1.0, 0.15, 0.05)
	ll.light_energy = 0.6
	ll.omni_range = 4.0
	world.add_child(ll)
	ll.position = base + Vector3(0, 2.0, 0)
	_lift_lights.append(ll)
	var lb := Label3D.new()
	lb.text = "LIFT"
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.font_size = 36
	lb.pixel_size = 0.006
	lb.outline_size = 8
	lb.modulate = Color(0.8, 0.8, 0.8)
	world.add_child(lb)
	lb.position = base + Vector3(0, 1.6, 0)

func _make_fuse() -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.1
	cm.height = 0.34
	body.mesh = cm
	body.material_override = _glow_mat(Color(1.0, 0.62, 0.12), 3.0)
	n.add_child(body)
	for y in [-0.19, 0.19]:
		var cap := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.12
		cc.bottom_radius = 0.12
		cc.height = 0.06
		cap.mesh = cc
		cap.material_override = _dull("rusty_metal", 2.0, Color(0.8, 0.8, 0.8))
		cap.position.y = y
		n.add_child(cap)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.15)
	l.light_energy = 1.6
	l.omni_range = 2.4
	n.add_child(l)
	return n

func _dull(tex: String, tile: float, tint: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = mat(tex, tile, tint).duplicate()
	m.metallic = 0.2
	return m

func _container(base: Vector3, size: Vector3, tint: Color) -> void:
	var c := base + Vector3(0, size.y * 0.5, 0)
	box(size, c, _dull("corrugated_iron", 0.6, tint), null, true)
	_solids.append({"c": c, "s": size, "yaw": 0.0})
	box(Vector3(size.x + 0.06, 0.12, size.z + 0.06), base + Vector3(0, size.y - 0.04, 0), mat("rusty_metal", 0.8, tint.darkened(0.2)))
	box(Vector3(size.x + 0.06, 0.12, size.z + 0.06), base + Vector3(0, 0.06, 0), mat("rusty_metal", 0.8, tint.darkened(0.3)))

func _fence_parts() -> void:
	var src: Node3D = load(PH_MOD + "modular_chainlink_fence/modular_chainlink_fence.gltf").instantiate()
	_fence_panel = _extract(src, "modular_chainlink_fence_double")
	_fence_post = _extract(src, "modular_chainlink_fence_post")
	src.free()

func _extract(src: Node3D, child_name: String) -> Node3D:
	var holder := Node3D.new()
	var ch: Node3D = src.find_child(child_name, false, false)
	if not ch:
		return holder
	var bb := _bounds(ch, ch.transform)
	ch.owner = null
	src.remove_child(ch)
	holder.add_child(ch)
	ch.owner = holder
	for d in ch.find_children("*", "", true, false):
		d.owner = holder
	ch.position -= Vector3(bb.position.x, 0.0, bb.position.z + bb.size.z * 0.5)
	return holder

func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is MeshInstance3D:
		out = xf * (n as MeshInstance3D).get_aabb()
		first = false
	for c in n.get_children():
		if c is Node3D:
			var b := _bounds(c, xf * (c as Node3D).transform)
			if b.size != Vector3.ZERO:
				out = b if first else out.merge(b)
				first = false
	return out

func _fence_line(a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var count := int(ceil(dir.length() / 2.0))
	var step := dir / float(count)
	var yaw := atan2(-dir.z, dir.x)
	for i in count:
		var p: Node3D = _fence_panel.duplicate()
		world.add_child(p)
		p.position = a + step * i + step.normalized() * 0.05
		p.rotation.y = yaw
		p.scale = Vector3(step.length() / 1.92, 1.0, 1.0)
		var post: Node3D = _fence_post.duplicate()
		world.add_child(post)
		post.position = a + step * i - step.normalized() * 0.07
		post.rotation.y = yaw
	var last: Node3D = _fence_post.duplicate()
	world.add_child(last)
	last.position = b - dir.normalized() * 0.07

func _lab_wall() -> void:
	box(Vector3(52.0, 10.0, 0.6), Vector3(W * 0.5, 5.0, -12.0), mat("factory_brick", 0.35, Color(0.8, 0.78, 0.74)))
	box(Vector3(52.0, 1.2, 0.8), Vector3(W * 0.5, 0.6, -11.8), mat("concrete_wall_008", 0.5))
	prop("rollershutter_door", Vector3(1.0, 0, -11.65), 0.0, 1.4)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.2, 0.18, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.78, 0.4)
	glow.emission_energy_multiplier = 1.6
	for wx in [-8.0, -4.0, 6.0, 10.0, 14.0, 22.0]:
		box(Vector3(1.6, 1.1, 0.1), Vector3(wx, 5.6, -11.68), glow if wx != 10.0 else mat("dirty_concrete", 0.6, Color(0.2, 0.2, 0.2)))
	for lx in [-3.0, 8.0, 18.0]:
		_lamp_box(Vector3(lx, 3.7, -11.55))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.light_energy = 2.2
		l.omni_range = 6.0
		world.add_child(l)
		l.position = Vector3(lx, 3.4, -11.2)
	var pipe := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = 10.0
	pipe.mesh = cm
	pipe.material_override = mat("rusty_metal_02", 1.5)
	world.add_child(pipe)
	pipe.position = Vector3(12.2, 5.0, -11.5)

func _lamp_box(pos: Vector3) -> void:
	box(Vector3(0.42, 0.2, 0.34), pos, _dull("rusty_metal_02", 1.5, Color(0.6, 0.6, 0.6)))
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(1, 1, 1)
	lens.emission_enabled = true
	lens.emission = Color(1.0, 0.82, 0.55)
	lens.emission_energy_multiplier = 5.0
	box(Vector3(0.34, 0.04, 0.26), pos + Vector3(0, -0.11, 0), lens)
	box(Vector3(0.05, 0.05, 0.3), pos + Vector3(0, 0.0, 0.0), _dull("rusty_metal_02", 1.5, Color.WHITE))

func _sconce(pos: Vector3, yaw: float) -> void:
	_lamp_box(pos + Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw))) * 0.12)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.52)
	l.light_energy = 3.2
	l.omni_range = 6.5
	l.shadow_enabled = true
	world.add_child(l)
	l.position = pos + Vector3(0, -0.15, 0) + Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw))) * 0.35

func _security_light(base: Vector3, side: float) -> void:
	var pole_m := mat("rusty_metal_02", 1.2)
	box(Vector3(0.16, 5.6, 0.16), base + Vector3(0, 2.8, 0), pole_m)
	box(Vector3(0.9, 0.1, 0.1), base + Vector3(side * 0.4, 5.4, 0), pole_m)
	var head := prop("security_light", base + Vector3(side * 0.8, 5.25, 0), 90.0 * side, 1.6)
	if head:
		head.rotation_degrees.x = -25.0
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(1, 1, 1)
	lens.emission_enabled = true
	lens.emission = Color(1.0, 0.95, 0.85)
	lens.emission_energy_multiplier = 6.0
	box(Vector3(0.12, 0.3, 0.42), base + Vector3(side * 0.95, 5.05, 0), lens)
	var sp := SpotLight3D.new()
	sp.light_color = Color(1.0, 0.92, 0.78)
	sp.light_energy = 16.0
	sp.spot_range = 14.0
	sp.spot_angle = 34.0
	sp.spot_attenuation = 0.9
	sp.shadow_enabled = true
	world.add_child(sp)
	sp.position = base + Vector3(side * 0.95, 5.0, 0)
	var target := base + Vector3(side * 4.2, 0.0, 0.3)
	sp.look_at(target, Vector3.UP)

func _build_tower(idx: int) -> void:
	var base: Vector3 = TOWERS[idx]
	var to_yard := Vector3(W * 0.5, 0, D * 0.5) - base
	var yaw := atan2(to_yard.x, to_yard.z)
	var pivot := Node3D.new()
	world.add_child(pivot)
	pivot.position = base
	pivot.rotation.y = yaw
	_tower_yaws.append(yaw)
	_eyes.append(base + Vector3(0, PLATFORM_Y + 1.62, 1.15).rotated(Vector3.UP, yaw))
	var leg_m := _dull("rusty_metal_02", 1.0, Color(0.9, 0.85, 0.8))
	var h := PLATFORM_Y
	for cx in [-1.2, 1.2]:
		for cz in [-1.2, 1.2]:
			box(Vector3(0.18, h, 0.18), Vector3(cx, h * 0.5, cz), leg_m, pivot)
			box(Vector3(0.12, 2.6, 0.12), Vector3(cx, h + 1.3, cz), leg_m, pivot)
	for y in [1.4, 2.7, 3.9]:
		box(Vector3(2.5, 0.1, 0.1), Vector3(0, y, -1.2), leg_m, pivot)
		box(Vector3(2.5, 0.1, 0.1), Vector3(0, y, 1.2), leg_m, pivot)
		box(Vector3(0.1, 0.1, 2.5), Vector3(-1.2, y, 0), leg_m, pivot)
		box(Vector3(0.1, 0.1, 2.5), Vector3(1.2, y, 0), leg_m, pivot)
	for k in 2:
		var br := box(Vector3(0.08, 3.0, 0.08), Vector3(0, 2.0, -1.2 + k * 2.4), leg_m, pivot)
		br.rotation_degrees.z = 52.0 if k == 0 else -52.0
	box(Vector3(3.0, 0.16, 3.0), Vector3(0, h, 0), mat("black_painted_planks", 0.9, Color(0.6, 0.52, 0.42)), pivot)
	var wall_m := _dull("corrugated_iron", 0.7, Color(0.8, 0.78, 0.72))
	box(Vector3(3.0, 0.08, 0.08), Vector3(0, h + 0.95, 1.5), leg_m, pivot)
	box(Vector3(3.0, 0.08, 0.08), Vector3(0, h + 0.5, 1.5), leg_m, pivot)
	box(Vector3(3.0, 0.3, 0.04), Vector3(0, h + 0.15, 1.5), wall_m, pivot)
	box(Vector3(0.06, 1.0, 3.0), Vector3(-1.5, h + 0.55, 0), wall_m, pivot)
	box(Vector3(0.06, 1.0, 3.0), Vector3(1.5, h + 0.55, 0), wall_m, pivot)
	box(Vector3(3.0, 1.0, 0.06), Vector3(0, h + 0.55, -1.5), wall_m, pivot)
	var roof := box(Vector3(3.5, 0.06, 3.5), Vector3(0, h + 2.65, 0), mat("corrugated_iron", 0.8, Color(0.5, 0.45, 0.4)), pivot)
	roof.rotation_degrees.x = -6.0
	for k in 8:
		box(Vector3(0.6, 0.05, 0.05), Vector3(0, 0.4 + k * 0.5, -1.35), leg_m, pivot)
	prop("portable_searchlight", Vector3(-1.2, h + 1.12, -1.2), 200.0, 2.4, pivot)
	var bulb := OmniLight3D.new()
	bulb.light_color = Color(1.0, 0.75, 0.45)
	bulb.light_energy = 1.6
	bulb.omni_range = 3.2
	world.add_child(bulb)
	bulb.position = base + Vector3(0, h + 2.3, 0)
	prop("caged_hanging_light", Vector3(0, h + 2.55, 0), 0.0, 1.2, pivot)

func _build_laser() -> void:
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.08, 0.05, 0.75)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_laser = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, 1.0)
	_laser.mesh = bm
	_laser.material_override = lm
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.visible = false
	world.add_child(_laser)
	_laser_dot = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	_laser_dot.mesh = sm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1.0, 0.15, 0.1)
	_laser_dot.material_override = dm
	_laser_dot.visible = false
	world.add_child(_laser_dot)
	_laser_light = OmniLight3D.new()
	_laser_light.light_color = Color(1.0, 0.1, 0.05)
	_laser_light.light_energy = 2.5
	_laser_light.omni_range = 1.1
	_laser_light.visible = false
	world.add_child(_laser_light)

func _build_hud() -> void:
	_info = _label(Vector2(16, 40), 18, Color("e8e0c8"))
	_status = _label(Vector2(16, 64), 18, Color("ff9a7a"))
	_ammo_label = _label(Vector2.ZERO, 30, Color("f0d890"))
	_pin(_ammo_label, Vector2(0.0, 1.0), Rect2(24, -96, 600, 40))
	_hint = _label(Vector2.ZERO, 20, Color("b8f5c4"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_hint, Vector2(0.5, 1.0), Rect2(-460, -52, 920, 30))
	_flash_label = _label(Vector2.ZERO, 34, Color("ff4030"))
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_flash_label, Vector2(0.5, 0.5), Rect2(-200, 50, 400, 44))
	_stamina_bar = ProgressBar.new()
	_stamina_bar.show_percentage = false
	_stamina_bar.max_value = STAMINA_MAX
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("c9e07a")
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	_stamina_bar.add_theme_stylebox_override("fill", fill)
	_stamina_bar.add_theme_stylebox_override("background", bg)
	_stamina_bar.visible = false
	hud.add_child(_stamina_bar)
	_pin(_stamina_bar, Vector2(0.0, 1.0), Rect2(24, -40, 220, 14))
	_scope = ColorRect.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(uv);
	float a = smoothstep(0.405, 0.415, r);
	a = max(a, smoothstep(0.22, 0.41, r) * 0.65);
	float thin = (abs(uv.x) < 0.0011 || abs(uv.y) < 0.0011) ? 1.0 : 0.0;
	float post = ((abs(uv.x) < 0.0045 && abs(uv.y) > 0.13) || (abs(uv.y) < 0.0045 && abs(uv.x) > 0.13)) ? 1.0 : 0.0;
	a = max(a, max(thin * 0.85, post));
	float mil = (abs(uv.y) < 0.006 && abs(fract(uv.x * 25.0 + 0.5) - 0.5) < 0.03 && abs(uv.x) < 0.13) ? 0.8 : 0.0;
	a = max(a, mil);
	COLOR = vec4(0.0, 0.0, 0.0, a * strength);
}"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	_scope.material = smat
	_scope.visible = false
	hud.add_child(_scope)
	hud.move_child(_scope, 0)
	_black = ColorRect.new()
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.color = Color(0, 0, 0, 0)
	hud.add_child(_black)
	hud.move_child(_black, 1)
	_reloc_label = _label(Vector2.ZERO, 40, Color("ffb020"))
	_reloc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_reloc_label, Vector2(0.5, 0.5), Rect2(-400, -120, 800, 50))
	_reloc_label.visible = false
	_obj_label = _label(Vector2.ZERO, 22, Color("ffc860"))
	_obj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pin(_obj_label, Vector2(1.0, 0.0), Rect2(-620, 12, 600, 30))
	_arrow = _label(Vector2.ZERO, 20, Color("ffd060"))
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow.size = Vector2(160, 54)
	_arrow.visible = false
	_hold_label = _label(Vector2.ZERO, 26, Color("e0ffd0"))
	_hold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_hold_label, Vector2(0.5, 1.0), Rect2(-400, -110, 800, 36))
	_hold_label.visible = false
	_warn = _label(Vector2.ZERO, 36, Color("ff3020"))
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_warn, Vector2(0.5, 0.0), Rect2(-400, 90, 800, 50))
	_warn.visible = false
	_dot = ColorRect.new()
	_dot.color = Color(1, 0.3, 0.2, 0.9)
	_dot.visible = false
	hud.add_child(_dot)
	_pin(_dot, Vector2(0.5, 0.5), Rect2(-2, -2, 4, 4))

func _pin(c: Control, anchor: Vector2, r: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y

func _label(pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)
	hud.add_child(l)
	return l

func _is_local_hunter() -> bool:
	return hunter != 0 and hunter == multiplayer.get_unique_id() and players.has(hunter) and not players[hunter].is_bot

func _bot_hunter() -> bool:
	return hunter != 0 and players.has(hunter) and players[hunter].is_bot

func _runners() -> Array:
	return players.keys().filter(func(id): return id != hunter)

func _runners_alive() -> Array:
	return alive_ids().filter(func(id): return id != hunter)

func _pick_hunter() -> int:
	var ids: Array = NetworkManager.players.keys()
	if OS.get_cmdline_user_args().has("--hunter-bot"):
		var bots: Array = ids.filter(func(id): return NetworkManager.players[id].is_bot)
		if not bots.is_empty():
			return bots.pick_random()
	var pool: Array = ids.filter(func(id): return not _hunted.has(id))
	if pool.is_empty():
		_hunted.clear()
		pool = ids
	var humans: Array = pool.filter(func(id): return not NetworkManager.players[id].is_bot)
	var pick: int = humans.pick_random() if NetworkManager.human_peer_ids().size() == 1 and not humans.is_empty() else pool.pick_random()
	_hunted.append(pick)
	return pick

func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	_rpc_roles.rpc(_pick_hunter())
	_rpc_fuses.rpc(_fuse_spawns())
	var bots: Array = _runners().filter(func(id): return players[id].is_bot)
	bots.shuffle()
	for i in bots.size():
		_bot_role[bots[i]] = "fuse" if i % 2 == 0 else "hide"
	await get_tree().create_timer(2.0).timeout
	_rpc_go.rpc()
	var t := 0.0
	var reloc := 0
	while t < ROUND_TIME:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		if reloc < RELOCATE_AT.size() and t >= RELOCATE_AT[reloc] and players.has(hunter) and players[hunter].alive:
			reloc += 1
			_rpc_relocate.rpc(1 - _tower)
		if _runners_alive().is_empty() or _executor != 0:
			break
		if _ammo <= 0 and Time.get_ticks_msec() - _srv_shot_ms > 1800:
			break
	if _executor != 0:
		await get_tree().create_timer(3.2).timeout
	_rpc_end.rpc()
	await get_tree().create_timer(1.4).timeout
	if not _done:
		_done = true
		finished.emit(_placement())

func _placement() -> Array:
	var placement: Array = []
	var survivors := _runners_alive()
	survivors.sort_custom(func(a, b): return _hits.get(a, 0) < _hits.get(b, 0))
	if _executor != 0:
		placement.append(_executor)
		for id in survivors:
			if id != _executor:
				placement.append(id)
		placement.append(hunter)
	elif survivors.is_empty():
		placement.append(hunter)
	else:
		placement.append_array(survivors)
		placement.append(hunter)
	for i in range(elim_order.size() - 1, -1, -1):
		if not placement.has(elim_order[i]):
			placement.append(elim_order[i])
	for id in players:
		if not placement.has(id):
			placement.append(id)
	return placement

@rpc("authority", "call_local", "reliable")
func _rpc_roles(h: int) -> void:
	hunter = h
	if not players.has(h):
		return
	var hp: LabPlayer3D = players[h]
	hp.bounds = AABB()
	hp.input_enabled = false
	_place_hunter()
	hp.bot_brain = func(_d: float) -> Vector3: return Vector3.ZERO
	var name_s: String = NetworkManager.players.get(h, {}).get("name", "?")
	if _is_local_hunter():
		hp.body.visible = false
		for id in players:
			players[id]._label.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_yaw = 0.0
		_pitch = -0.62
		camera.fov = FOV_WIDE
		camera.near = 0.03
		_apply_hunter_cam()
		_build_viewmodel()
		_dot.visible = true
		_hint.text = "MOUSE aim  ·  RMB / SHIFT scope  ·  LMB / SPACE fire  ·  %d rounds" % AMMO
		_status.text = "YOU ARE THE HUNTER"
	else:
		_hint.text = "WASD run  ·  SHIFT sprint  ·  hide behind cover, stay out of the red laser"
		_status.text = "HUNTER: %s" % name_s
		_stamina_bar.visible = local_player() != null and multiplayer.get_unique_id() != h
	_update_hud()

func _place_hunter() -> void:
	var hp: LabPlayer3D = players[hunter]
	var yaw: float = _tower_yaws[_tower]
	hp.position = (TOWERS[_tower] as Vector3) + Vector3(0, PLATFORM_Y + 0.08, 0.95).rotated(Vector3.UP, yaw)
	hp._target = hp.position
	hp.face(Vector3(sin(yaw), 0, cos(yaw)))
	_aim = Vector3(sin(yaw) * 0.8, -0.6, cos(yaw) * 0.8).normalized()
	_bh_aim = _aim

@rpc("authority", "call_local", "reliable")
func _rpc_relocate(to: int) -> void:
	_relocating = true
	_siren()
	_reloc_label.visible = true
	_reloc_label.text = "RELOCATING..." if _is_local_hunter() else "HUNTER RELOCATING  ·  find new cover"
	if _is_local_hunter():
		var tw := _black.create_tween()
		tw.tween_property(_black, "color:a", 1.0, 0.35)
	await get_tree().create_timer(0.75).timeout
	if not is_inside_tree() or _ended:
		return
	_tower = to
	_eye = _eyes[to]
	_refresh_lifts()
	if players.has(hunter):
		_place_hunter()
	_bh_target = 0
	if _is_local_hunter():
		_yaw = 0.0
		_pitch = -0.62
		_zoom = 0.0
		_apply_hunter_cam()
	if NetworkManager.is_server():
		for k in _bot:
			_bot[k].goal = _pick_spot(players[k].position, _eye, k, 0.0)
			_bot[k].via = null
			_bot[k].flee = true
	await get_tree().create_timer(0.75).timeout
	if not is_inside_tree():
		return
	_relocating = false
	_reloc_label.visible = false
	if _is_local_hunter():
		var tw2 := _black.create_tween()
		tw2.tween_property(_black, "color:a", 0.0, 0.3)

func _siren() -> void:
	for i in 4:
		if not is_inside_tree():
			return
		Fx.sfx("buzzer", null, -5.0, 0.62 if i % 2 == 0 else 0.86)
		await get_tree().create_timer(0.38).timeout

@rpc("authority", "call_local", "reliable")
func _rpc_go() -> void:
	_live = true
	_time_left = ROUND_TIME
	Fx.sfx("buzzer", null, -6.0)

@rpc("authority", "call_local", "reliable")
func _rpc_end() -> void:
	_live = false
	_ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_warn.visible = false
	for id in players:
		var p: LabPlayer3D = players[id]
		p.velocity = Vector3.ZERO
		p.set_physics_process(false)

func _apply_hunter_cam() -> void:
	camera.position = _eye
	camera.basis = Basis.from_euler(Vector3(_pitch + _kick, PI + float(_tower_yaws[_tower]) + _yaw, 0.0))
	_aim = -camera.basis.z

func _build_viewmodel() -> void:
	_viewmodel = Node3D.new()
	camera.add_child(_viewmodel)
	_viewmodel.position = Vector3(0.2, -0.2, -0.5)
	_rifle = prop("bolt_action_rifle_7_62", Vector3.ZERO, 90.0, 1.0, _viewmodel)
	if not _rifle:
		return
	_rifle.rotation_degrees = Vector3(0.0, 93.0, 2.0)
	for mi in _rifle.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as MeshInstance3D).layers = 2
	for nm in ["bolt_action_rifle_7_62_bolt_a", "bolt_action_rifle_7_62_bolt_b"]:
		var bp: Node3D = _rifle.find_child(nm, true, false)
		if bp:
			_bolt_parts.append([bp, bp.position])
	_muzzle = Marker3D.new()
	_rifle.add_child(_muzzle)
	_muzzle.position = Vector3(0.6, 0.0, -0.02)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.8, 0.75)
	fill.light_energy = 0.9
	fill.omni_range = 1.4
	fill.light_cull_mask = 2
	camera.add_child(fill)
	fill.position = Vector3(0.1, 0.3, 0.1)

func _muzzle_world() -> Vector3:
	if _is_local_hunter() and _muzzle:
		return _muzzle.global_position
	var fwd := _aim.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	return _eye + fwd * 0.9 + right * 0.2 + Vector3(0, -0.16, 0)

func _excl() -> Array:
	var out: Array = []
	for id in players:
		var p: LabPlayer3D = players[id]
		if id == hunter or not p.alive:
			out.append(p.get_rid())
	return out

func _cast(from: Vector3, dir: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * 80.0)
	q.exclude = _excl()
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		var d := dir.normalized()
		var t := 60.0
		if d.y < -0.01:
			t = -from.y / d.y
		return {"position": from + d * t, "collider": null}
	return hit

func _visible_from_eye(id: int, h: float = 1.2) -> bool:
	var p: LabPlayer3D = players[id]
	var tgt := p.global_position + Vector3(0, h, 0)
	var hit := _cast(_eye, tgt - _eye)
	return hit.collider == p

func _process(delta: float) -> void:
	if not world:
		return
	if _live:
		_time_left = maxf(_time_left - delta, 0.0)
	if hunter != 0 and players.has(hunter):
		_hunter_pose()
		if _is_local_hunter():
			_hunter_input(delta)
		if NetworkManager.is_server() and _bot_hunter():
			_bot_hunter_think(delta)
		_update_laser()
		_local_runner(delta)
		if NetworkManager.is_server() and _live and not _ended:
			_camp_tick(delta)
			_obj_tick(delta)
		_fuse_anim(delta)
		_local_objective(delta)
		_update_markers()
	if _executor != 0 and players.has(_executor) and players.has(hunter):
		_exec_cam(delta)
	elif not _is_local_hunter() or _dead_view:
		var me := local_player()
		var want_x := W * 0.5
		if me and me.alive:
			want_x = lerpf(W * 0.5, me.position.x, 0.4)
		_runner_cam(lerpf(camera.position.x, want_x, 1.0 - exp(-3.0 * delta)))
	_kick = move_toward(_kick, 0.0, delta * 0.25)
	if _flash_label.modulate.a > 0.0:
		_flash_label.modulate.a = maxf(_flash_label.modulate.a - delta * 0.8, 0.0)
	if _hint.modulate.a > 0.0 and _live and _time_left < ROUND_TIME - 6.0:
		_hint.modulate.a = maxf(_hint.modulate.a - delta, 0.0)
	_update_hud()

func _hunter_pose() -> void:
	var hp: LabPlayer3D = players[hunter]
	if not hp.alive:
		return
	hp.face(Vector3(_aim.x, 0.0, _aim.z))
	var b: LabCharacter = hp.body
	if b.anim and b.anim.current_animation != "Pistol_Aim_Down":
		b.play_action("Pistol_Aim_Down", 0.25)

func _hunter_input(delta: float) -> void:
	var zoom_on := _live and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_physical_key_pressed(KEY_SHIFT))
	_zoom = move_toward(_zoom, 1.0 if zoom_on else 0.0, delta * 6.0)
	camera.fov = lerpf(FOV_WIDE, FOV_ZOOM, _zoom)
	_scope.visible = _zoom > 0.5
	(_scope.material as ShaderMaterial).set_shader_parameter("strength", clampf((_zoom - 0.5) * 2.0, 0.0, 1.0))
	_dot.visible = _zoom <= 0.5
	if _viewmodel:
		_viewmodel.visible = _zoom < 0.6
		var cyc := clampf(1.0 - float(Time.get_ticks_msec() - _last_shot_ms) / 260.0, 0.0, 1.0)
		_viewmodel.position = Vector3(0.2 - _zoom * 0.2, -0.2 + _zoom * 0.08, -0.5 + cyc * 0.09)
		_viewmodel.rotation.x = cyc * 0.16
		_bolt_cycle()
	_apply_hunter_cam()
	var fire_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE)
	if fire_down and not _fire_was_down and _live and not _relocating and _ammo > 0 and _bolt_ready():
		_last_shot_ms = Time.get_ticks_msec()
		_rpc_fire_request.rpc_id(1, camera.global_position, _aim)
	_fire_was_down = fire_down
	_aim_send_t -= delta
	if _aim_send_t <= 0.0 and _live and not _ended:
		_aim_send_t = 0.05
		_rpc_aim.rpc(_aim)

func _runner_cam(x: float) -> void:
	camera.fov = 44.0
	camera.position = Vector3(x, 8.0, D + 7.0)
	camera.look_at(Vector3(x, 0.6, D * 0.32), Vector3.UP)

func _bolt_cycle() -> void:
	var t := float(Time.get_ticks_msec() - _last_shot_ms) / 1000.0
	var k := 0.0
	if t > 0.35 and t < BOLT_TIME:
		k = sin(clampf((t - 0.35) / (BOLT_TIME - 0.45), 0.0, 1.0) * PI)
	for bp in _bolt_parts:
		(bp[0] as Node3D).position = (bp[1] as Vector3) + Vector3(-0.08 * k, 0.015 * k, 0)
	if _rifle:
		_rifle.rotation_degrees.x = -18.0 * k

func _bolt_ready() -> bool:
	return Time.get_ticks_msec() - _last_shot_ms >= int(BOLT_TIME * 1000.0)

func _input(event: InputEvent) -> void:
	if not _is_local_hunter() or not _live:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m: InputEventMouseMotion = event
		var sens := 0.0024 * camera.fov / FOV_WIDE
		_yaw = clampf(_yaw - m.relative.x * sens, -1.05, 1.05)
		_pitch = clampf(_pitch - m.relative.y * sens, -1.25, -0.08)

@rpc("any_peer", "unreliable_ordered")
func _rpc_aim(dir: Vector3) -> void:
	var s := multiplayer.get_remote_sender_id()
	if s == hunter or s == 1:
		_aim = dir.normalized()

func _update_laser() -> void:
	var hp: LabPlayer3D = players[hunter]
	var on := _live and hp.alive and _ammo > 0 and not _relocating and _executor == 0
	_laser.visible = on
	_laser_dot.visible = on
	_laser_light.visible = on
	if not on:
		return
	var a := _muzzle_world()
	var hit := _cast(_eye, _aim)
	var b: Vector3 = hit.position
	var len := a.distance_to(b)
	if len < 0.1:
		return
	_laser.global_position = (a + b) * 0.5
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.98 else Vector3.RIGHT
	_laser.look_at(b, up)
	_laser.visible = not (_is_local_hunter() and _zoom > 0.5)
	var thick := 0.45 if _is_local_hunter() else 1.0
	_laser.scale = Vector3(thick, thick, len)
	_laser_dot.global_position = b - _aim.normalized() * 0.03
	_laser_light.global_position = b - _aim.normalized() * 0.25

func _local_runner(delta: float) -> void:
	var me := local_player()
	if not me or me.peer_id == hunter or me.is_bot:
		return
	var limp := LIMP if int(_hits.get(me.peer_id, 0)) > 0 else 1.0
	var moving := me._input_dir().length() > 0.1
	var sprint := Input.is_physical_key_pressed(KEY_SHIFT) and moving and _stamina > 0.05 and me.alive
	if sprint:
		_stamina = maxf(_stamina - delta, 0.0)
	else:
		_stamina = minf(_stamina + delta * 0.55, STAMINA_MAX)
	me.speed = (SPRINT_SPEED if sprint else RUN_SPEED) * limp * (CARRY_SLOW if _carried_by(me.peer_id) >= 0 else 1.0)
	_stamina_bar.value = _stamina

func _fuse_spawns() -> Array:
	var space := world.get_world_3d().direct_space_state
	var ex: Array = []
	for id in players:
		ex.append(players[id].get_rid())
	var cands: Array = []
	var x := 0.8
	while x < W - 0.7:
		var z := 0.8
		while z < D - 0.7:
			var pt := Vector3(x, 0, z)
			var ok := pt.distance_to(FUSEBOX) > 3.0
			for lp in LIFTS:
				if pt.distance_to(lp) < 2.5:
					ok = false
			for sd in _solids:
				if _inside(pt, sd, 0.7):
					ok = false
			if ok:
				for e in _eyes:
					var q := PhysicsRayQueryParameters3D.create(e, pt + Vector3(0, 0.25, 0))
					q.exclude = ex
					if not space.intersect_ray(q).is_empty():
						ok = false
			if ok:
				cands.append(pt)
			z += 0.5
		x += 0.5
	cands.shuffle()
	var out: Array = []
	for c in cands:
		var far := true
		for o in out:
			if (o as Vector3).distance_to(c) < 3.5:
				far = false
		if far:
			out.append(c)
		if out.size() >= FUSES:
			break
	while out.size() < FUSES:
		out.append(Vector3(randf_range(2.0, W - 2.0), 0, randf_range(5.0, D - 1.0)))
	return out

@rpc("authority", "call_local", "reliable")
func _rpc_fuses(pos: Array) -> void:
	for n in _fuse_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_fuse_nodes.clear()
	_fuse_pos = pos.duplicate()
	_fuse_state = []
	for i in pos.size():
		var n := _make_fuse()
		world.add_child(n)
		n.position = (pos[i] as Vector3) + Vector3(0, 0.45, 0)
		n.scale = Vector3.ONE * 1.5
		_fuse_nodes.append(n)
		_fuse_state.append(0)
	_refresh_lifts()

func _carried_by(id: int) -> int:
	for i in _fuse_state.size():
		if int(_fuse_state[i]) == id:
			return i
	return -1

@rpc("authority", "call_local", "reliable")
func _rpc_fuse(i: int, state: int, pos: Vector3) -> void:
	if i < 0 or i >= _fuse_nodes.size():
		return
	_fuse_state[i] = state
	var n: Node3D = _fuse_nodes[i]
	if not is_instance_valid(n):
		return
	if state > 0 and players.has(state):
		n.reparent(players[state].body, false)
		n.position = Vector3(0.0, 1.2, -0.26)
		n.rotation = Vector3(0.0, 0.0, 0.35)
		n.scale = Vector3.ONE
		Fx.sfx("click", players[state].global_position, 0.0, 1.2)
	elif state == 0:
		n.reparent(world, false)
		_fuse_pos[i] = pos
		n.position = pos + Vector3(0, 0.45, 0)
		n.rotation = Vector3.ZERO
		n.scale = Vector3.ONE * 1.5
	else:
		n.visible = false
		_fuses_in += 1
		Fx.sparks(world, FUSEBOX + Vector3(0, 0.9, -0.55))
		Fx.sfx("arm", FUSEBOX, 0.0, 1.4)
		for k in _box_bulbs.size():
			(_box_bulbs[k] as MeshInstance3D).material_override = _glow_mat(Color(0.2, 1.0, 0.25) if k < _fuses_in else Color(0.9, 0.1, 0.05), 3.0)
		_flash("FUSE %d/%d IN" % [_fuses_in, FUSES])

func _fuse_anim(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for i in _fuse_nodes.size():
		var n: Node3D = _fuse_nodes[i]
		if is_instance_valid(n) and int(_fuse_state[i]) == 0:
			n.position.y = 0.45 + sin(t * 3.0 + i) * 0.08
			n.rotation.y = t * 1.5 + i

func _obj_tick(delta: float) -> void:
	for id in _runners_alive():
		var p: LabPlayer3D = players[id]
		var flat := Vector3(p.position.x, 0, p.position.z)
		var carry := _carried_by(id)
		if carry < 0 and not _lift_online:
			for i in _fuse_state.size():
				if int(_fuse_state[i]) == 0 and flat.distance_to(_fuse_pos[i]) < 0.9:
					_rpc_fuse.rpc(i, id, Vector3.ZERO)
					carry = i
					break
		var holding: bool = _hold.get(id, false) and not _stun.has(id)
		var t: float = _hold_t.get(id, 0.0)
		var at_box := carry >= 0 and flat.distance_to(FUSEBOX) < 2.2
		var at_lift := _lift_online and not _relocating and flat.distance_to(LIFTS[_tower]) < 1.3
		if holding and (at_box or at_lift):
			if t == 0.0:
				_rpc_act_one.rpc(id, "Interact")
			t += delta
			if at_box and t >= BOX_HOLD:
				t = 0.0
				_rpc_fuse.rpc(carry, -1, Vector3.ZERO)
				var done := 0
				for st in _fuse_state:
					if int(st) == -1:
						done += 1
				if done >= FUSES:
					_rpc_lift_online.rpc()
			elif at_lift and t >= LIFT_HOLD:
				_executor = id
				_rpc_execute.rpc(id)
				return
		else:
			t = 0.0
		_hold_t[id] = t

@rpc("authority", "call_local", "reliable")
func _rpc_act_one(id: int, anim_name: String) -> void:
	if players.has(id) and players[id].alive:
		players[id].body.play_action(anim_name)

@rpc("any_peer", "call_local", "reliable")
func _rpc_hold(on: bool) -> void:
	if not NetworkManager.is_server():
		return
	var s := multiplayer.get_remote_sender_id()
	if s == 0:
		s = multiplayer.get_unique_id()
	if players.has(s) and s != hunter:
		_hold[s] = on

@rpc("authority", "call_local", "reliable")
func _rpc_lift_online() -> void:
	_lift_online = true
	for i in _fuse_state.size():
		_fuse_state[i] = -1
	_refresh_lifts()
	_siren()
	Fx.shake(0.4)
	_flash_label.text = "LIFT ONLINE" if not _is_local_hunter() else "THEY'RE COMING UP"
	_flash_label.modulate.a = 1.0

func _refresh_lifts() -> void:
	for i in _lift_lamps.size():
		var active := _lift_online and i == _tower
		(_lift_lamps[i] as MeshInstance3D).material_override = _glow_mat(Color(0.2, 1.0, 0.3) if active else Color(0.6, 0.05, 0.03), 4.0 if active else 1.0)
		var ll: OmniLight3D = _lift_lights[i]
		ll.light_color = Color(0.3, 1.0, 0.35) if active else Color(1.0, 0.15, 0.05)
		ll.light_energy = 3.0 if active else 0.6
		var roof: MeshInstance3D = _lift_roofs[i]
		roof.visible = active
		for sb in roof.get_children():
			if sb is StaticBody3D:
				(sb as StaticBody3D).collision_layer = 1 if active else 0

@rpc("authority", "call_local", "reliable")
func _rpc_execute(id: int) -> void:
	_executor = id
	_hold_label.visible = false
	if not players.has(id) or not players.has(hunter):
		return
	var p: LabPlayer3D = players[id]
	var hp: LabPlayer3D = players[hunter]
	var yaw: float = _tower_yaws[_tower]
	var lift: Vector3 = LIFTS[_tower]
	var car: Node3D = _lift_cars[_tower]
	var top := (TOWERS[_tower] as Vector3) + Vector3(0.75, PLATFORM_Y + 0.08, 0.35).rotated(Vector3.UP, yaw)
	p.bounds = AABB()
	p.input_enabled = false
	_stun[id] = 10.0
	Fx.sfx("hum", lift, 2.0, 0.8)
	var mover := func(v: Vector3) -> void:
		if is_instance_valid(p):
			p.position = v
			p._target = v
	var tw := p.create_tween()
	tw.tween_method(mover, p.position, Vector3(lift.x, 0.12, lift.z), 0.25)
	tw.tween_method(mover, Vector3(lift.x, 0.12, lift.z), Vector3(lift.x, PLATFORM_Y + 0.12, lift.z), 1.0)
	tw.parallel().tween_property(car, "position:y", PLATFORM_Y, 1.0)
	tw.tween_method(mover, Vector3(lift.x, PLATFORM_Y + 0.12, lift.z), top, 0.35)
	await tw.finished
	if not is_inside_tree() or not is_instance_valid(p):
		return
	p.face(hp.position - p.position)
	p.body.play_action("Punch_Cross")
	await get_tree().create_timer(0.35).timeout
	Fx.sfx("hit", hp.global_position, 2.0, 0.8)
	Fx.shake(0.5)
	p.body.play_action("Melee_Hook")
	await get_tree().create_timer(0.4).timeout
	if not is_inside_tree():
		return
	if _is_local_hunter():
		_dead_view = true
		hp.body.visible = true
		if _viewmodel:
			_viewmodel.visible = false
		_scope.visible = false
		_dot.visible = false
	eliminate(hunter, "Death01")
	Fx.blood(world, hp.global_position + Vector3(0, 1.4, 0), 120)
	Fx.shake(1.2)
	Fx.sfx("splat", null, 2.0)
	_flash_label.text = "HUNTER EXECUTED"
	_flash_label.modulate.a = 1.0
	var start := hp.position
	var land := start + Vector3(sin(yaw), 0, cos(yaw)) * 2.6
	land.y = 0.0
	var fall := func(k: float) -> void:
		if is_instance_valid(hp):
			var v := start.lerp(land, k)
			v.y = lerpf(start.y, 0.0, k * k) + sin(k * PI) * 0.6
			hp.position = v
			hp._target = v
	var tw2 := hp.create_tween()
	tw2.tween_method(fall, 0.0, 1.0, 0.7)
	tw2.tween_callback(func() -> void: Fx.blood(world, land + Vector3(0, 0.3, 0), 80))

func _exec_cam(delta: float) -> void:
	var yaw: float = _tower_yaws[_tower]
	var top := (TOWERS[_tower] as Vector3) + Vector3(0, PLATFORM_Y + 1.0, 0.6).rotated(Vector3.UP, yaw)
	var want := top + Vector3(sin(yaw + 0.35), 0, cos(yaw + 0.35)) * 7.5 + Vector3(0, 2.6, 0)
	if _viewmodel:
		_viewmodel.visible = false
	_scope.visible = false
	_dot.visible = false
	_black.color.a = 0.0
	camera.fov = 50.0
	camera.position = camera.position.lerp(want, 1.0 - exp(-4.0 * delta))
	camera.look_at(top, Vector3.UP)
	if _is_local_hunter():
		players[hunter].body.visible = true

func _local_objective(delta: float) -> void:
	var me := local_player()
	if not me or me.peer_id == hunter or me.is_bot or not me.alive or not _live or _ended or _executor != 0:
		_arrow.visible = false
		_hold_label.visible = false
		if _hold_sent and not _ended:
			_hold_sent = false
			_rpc_hold.rpc_id(1, false)
		return
	var flat := Vector3(me.position.x, 0, me.position.z)
	var carry := _carried_by(me.peer_id)
	var target: Variant = null
	var tag := ""
	if _lift_online:
		target = LIFTS[_tower]
		tag = "LIFT"
	elif carry >= 0:
		target = FUSEBOX
		tag = "FUSE BOX"
	else:
		var best := INF
		for i in _fuse_state.size():
			if int(_fuse_state[i]) == 0 and flat.distance_to(_fuse_pos[i]) < best:
				best = flat.distance_to(_fuse_pos[i])
				target = _fuse_pos[i]
				tag = "FUSE"
	_arrow.visible = target != null
	if target != null:
		var tp: Vector3 = target
		var sp := camera.unproject_position(tp + Vector3(0, 1.9, 0))
		var vs := get_viewport().get_visible_rect().size
		sp.x = clampf(sp.x, 90.0, vs.x - 90.0)
		sp.y = clampf(sp.y, 70.0, vs.y - 70.0)
		_arrow.text = "%s\n▼" % tag
		_arrow.position = sp - Vector2(80, 54)
		_arrow.modulate.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.01)
	var zone := (carry >= 0 and flat.distance_to(FUSEBOX) < 2.2) or (_lift_online and not _relocating and flat.distance_to(LIFTS[_tower]) < 1.3)
	var press := Input.is_physical_key_pressed(KEY_SPACE)
	if press != _hold_sent:
		_hold_sent = press
		_rpc_hold.rpc_id(1, press)
	_hold_local = _hold_local + delta if (press and zone) else 0.0
	_hold_label.visible = zone
	if zone:
		var need := LIFT_HOLD if _lift_online else BOX_HOLD
		var k := clampi(int(_hold_local / need * 10.0), 0, 10)
		_hold_label.text = "HOLD SPACE  %s" % ("#".repeat(k) + "-".repeat(10 - k)) if press else ("HOLD SPACE to %s" % ("ride the lift" if _lift_online else "plug in the fuse"))

func _camp_tick(delta: float) -> void:
	for id in _runners_alive():
		var p: LabPlayer3D = players[id]
		if not _camp.has(id):
			_camp[id] = {"a": p.position, "t": 0.0}
		var c: Dictionary = _camp[id]
		var off: Vector3 = p.position - (c.a as Vector3)
		if Vector2(off.x, off.z).length() > CAMP_RADIUS:
			c.a = p.position
			c.t = 0.0
			if _spotted.get(id, false):
				_rpc_spot.rpc(id, false)
			continue
		c.t += delta
		if c.t >= SPOT_TIME and not _spotted.get(id, false):
			_rpc_spot.rpc(id, true)
		if c.t >= SHOCK_TIME:
			var target := _fling_target(p.position)
			c.t = 0.0
			c.a = target
			_rpc_shock.rpc(id, target)

func _camp_time(id: int) -> float:
	return float(_camp[id].t) if _camp.has(id) else 0.0

func _fling_target(pos: Vector3) -> Vector3:
	var best_c := Vector3(W * 0.5, 0, D * 0.5)
	var best_d := INF
	for sd in _solids:
		var c: Vector3 = sd.c
		var d := Vector2(pos.x - c.x, pos.z - c.z).length() - maxf(sd.s.x, sd.s.z) * 0.3
		if d < best_d:
			best_d = d
			best_c = c
	var away := Vector3(pos.x - best_c.x, 0, pos.z - best_c.z)
	if away.length() < 0.05:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	for k in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, PI]:
		var t: Vector3 = pos + away.rotated(Vector3.UP, k) * 3.0
		t.x = clampf(t.x, 0.4, W - 0.4)
		t.z = clampf(t.z, 0.4, D - 0.4)
		t.y = 0.0
		var clear := true
		for sd in _solids:
			if _inside(t, sd, 0.45):
				clear = false
				break
		if clear and t.distance_to(pos) > 1.5:
			return t
	return pos

@rpc("authority", "call_local", "reliable")
func _rpc_spot(id: int, on: bool) -> void:
	_spotted[id] = on
	_spot_ms[id] = Time.get_ticks_msec()
	if on:
		var me := local_player()
		if me and me.peer_id == id:
			Fx.sfx("beep", null, -2.0, 1.3)
			Fx.sfx("arm", null, -6.0)
		elif _is_local_hunter():
			Fx.sfx("beep", null, -10.0, 0.9)

@rpc("authority", "call_local", "reliable")
func _rpc_shock(id: int, target: Vector3) -> void:
	_spotted[id] = false
	if not players.has(id):
		return
	var p: LabPlayer3D = players[id]
	if not p.alive:
		return
	Fx.sparks(world, p.global_position + Vector3(0, 1.0, 0))
	Fx.sparks(world, p.global_position + Vector3(0, 0.4, 0))
	Fx.sfx("buzzer", p.global_position, 2.0, 1.7)
	Fx.sfx("hit", p.global_position, -2.0, 0.7)
	p.body.play_action("Hit_Knockback")
	var me := local_player()
	if me and me.peer_id == id:
		Fx.shake(0.7)
		_flash_label.text = "ZAPPED"
		_flash_label.modulate.a = 1.0
	if p.is_multiplayer_authority():
		_stun[id] = 0.8
		p.input_enabled = false
		var start := p.position
		var fly := func(k: float) -> void:
			if is_instance_valid(p):
				p.position = start.lerp(target, k) + Vector3(0, sin(k * PI) * 0.9, 0)
		var land := func() -> void:
			if is_instance_valid(p):
				p.position.y = 0.0
		var tw := p.create_tween()
		tw.tween_method(fly, 0.0, 1.0, 0.4)
		tw.tween_callback(land)
		await get_tree().create_timer(0.8).timeout
		_stun.erase(id)
		if is_instance_valid(p) and not p.is_bot and p.peer_id != hunter:
			p.input_enabled = true

func _rim() -> Shader:
	if _rim_shader:
		return _rim_shader
	_rim_shader = Shader.new()
	_rim_shader.code = """shader_type spatial;
render_mode unshaded, depth_test_disabled, blend_add, cull_back, shadows_disabled;
uniform float pulse = 1.0;
void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = vec3(1.0, 0.07, 0.04) * (0.18 + 2.4 * pow(rim, 2.0)) * pulse;
}"""
	return _rim_shader

func _marker(id: int) -> Node3D:
	if _markers.has(id):
		return _markers[id]
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.36
	cap.height = 1.85
	mi.mesh = cap
	var sm := ShaderMaterial.new()
	sm.shader = _rim()
	sm.render_priority = 10
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.92
	root.add_child(mi)
	var lb := Label3D.new()
	lb.text = "SPOTTED"
	lb.no_depth_test = true
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.modulate = Color(1.0, 0.2, 0.15)
	lb.outline_size = 8
	lb.font_size = 44
	lb.pixel_size = 0.006
	lb.position.y = 2.3
	lb.render_priority = 11
	root.add_child(lb)
	players[id].add_child(root)
	_markers[id] = root
	root.set_meta("mat", sm)
	return root

func _update_markers() -> void:
	var hunter_view := _is_local_hunter()
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
	for id in players:
		var on: bool = hunter_view and _spotted.get(id, false) and players[id].alive and not _ended
		if on or _markers.has(id):
			var m := _marker(id)
			m.visible = on
			(m.get_meta("mat") as ShaderMaterial).set_shader_parameter("pulse", pulse)
	var me := local_player()
	if me and me.peer_id != hunter and not hunter_view:
		var sp: bool = _spotted.get(me.peer_id, false) and me.alive and _live
		_warn.visible = sp
		if sp:
			var left := SHOCK_TIME - SPOT_TIME - float(Time.get_ticks_msec() - int(_spot_ms.get(me.peer_id, 0))) / 1000.0
			_warn.text = "SPOTTED!  MOVE OR GET SHOCKED  %.0f" % maxf(ceil(left), 0.0)
			_warn.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.015)

func _update_hud() -> void:
	if not _info:
		return
	_info.text = "runners alive: %d   ·   %ds" % [_runners_alive().size(), int(ceil(_time_left))]
	var done := 0
	for st in _fuse_state:
		if int(st) == -1:
			done += 1
	if _lift_online:
		_obj_label.text = "LIFT ONLINE: THEY'RE COMING UP" if _is_local_hunter() else "LIFT ONLINE: GET UP THERE"
		_obj_label.add_theme_color_override("font_color", Color("80ff90"))
	else:
		_obj_label.text = ("FUSES IN %d/%d  ·  guard the fuse box" if _is_local_hunter() else "FUSES %d/%d  ·  plug them in, then take the lift") % [done, FUSES]
	if _is_local_hunter():
		var shells := ""
		for i in AMMO:
			shells += "|" if i < _ammo else "."
		_ammo_label.text = "%s  %d/%d%s" % [shells, _ammo, AMMO, "   CYCLING" if not _bolt_ready() and _ammo > 0 else ""]
	else:
		_ammo_label.text = ""
		var me := local_player()
		if me and me.peer_id != hunter:
			var hits := int(_hits.get(me.peer_id, 0))
			if not me.alive:
				_status.text = "YOU GOT SHOT"
			elif hits > 0:
				_status.text = "HIT  ·  limping, one more and you're done"

func _bot_brain(delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	if id == hunter or hunter == 0 or _stun.has(id) or _ended:
		return Vector3.ZERO
	if _spot_sets.is_empty():
		_make_spots()
	if not _bot.has(id):
		_bot[id] = {"goal": p.position, "rest": randf_range(0.2, 1.2), "stam": STAMINA_MAX, "stuck": 0.0, "last": p.position, "side": Vector3.ZERO, "side_t": 0.0, "flee": false, "via": null, "obj_wait": 0.0}
	var s: Dictionary = _bot[id]
	var limp := LIMP if int(_hits.get(id, 0)) > 0 else 1.0
	var laser_pt := _cast(_eye, _aim).position as Vector3
	var exposed := _visible_from_eye(id)
	var near_laser := Vector2(laser_pt.x - p.position.x, laser_pt.z - p.position.z).length() < 2.8
	var brave: bool = _lift_online or (_bot_role.get(id, "hide") == "fuse" and int(_hits.get(id, 0)) == 0)
	if _live and exposed and near_laser and not s.flee and not brave:
		s.goal = _pick_spot(p.position, laser_pt, id, 0.0)
		s.flee = true
		s.rest = randf_range(1.5, 3.5)
	s.obj_wait = maxf(float(s.get("obj_wait", 0.0)) - delta, 0.0)
	_hold[id] = false
	var obj: Variant = _bot_obj(id)
	if obj != null and not s.flee and s.obj_wait <= 0.0:
		var ov: Vector3 = obj
		var reach := 0.35 if _lift_online else 0.5
		if Vector2(ov.x - p.position.x, ov.z - p.position.z).length() < reach:
			_hold[id] = _carried_by(id) >= 0 or _lift_online
			p.speed = RUN_SPEED * limp
			s.via = null
			return Vector3.ZERO
		if (s.goal as Vector3).distance_to(ov) > 0.2:
			s.via = null
		s.goal = ov
	var to: Vector3 = s.goal - p.position
	to.y = 0.0
	if to.length() < 0.35:
		s.via = null
		if s.flee:
			s.obj_wait = randf_range(0.6, 1.8)
		s.flee = false
		s.rest -= delta
		var camping := _camp_time(id) > randf_range(2.6, 3.6)
		if s.rest <= 0.0 or camping or (exposed and _live and randf() < delta * 2.0):
			s.goal = _pick_spot(p.position, laser_pt, id, 2.6 if camping or _camp_time(id) > 2.0 else 0.0)
			s.rest = randf_range(1.2, 3.5)
		s.stam = minf(s.stam + delta * 0.55, STAMINA_MAX)
		p.speed = RUN_SPEED * limp
		return Vector3.ZERO
	var sprint: bool = (s.flee or exposed or _spotted.get(id, false)) and s.stam > 0.1 and to.length() > 1.5
	s.stam = maxf(s.stam - delta, 0.0) if sprint else minf(s.stam + delta * 0.55, STAMINA_MAX)
	p.speed = (SPRINT_SPEED if sprint else RUN_SPEED) * limp * (CARRY_SLOW if _carried_by(id) >= 0 else 1.0)
	s.stuck += delta
	if s.stuck > 0.5:
		if (p.position - (s.last as Vector3)).length() < 0.25 and s.side_t <= 0.0:
			s.side = Vector3(-to.z, 0, to.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
			s.side_t = 0.6
		s.stuck = 0.0
		s.last = p.position
	var waypoint := _route(p.position, s)
	var dir := Vector3(waypoint.x - p.position.x, 0.0, waypoint.z - p.position.z).normalized()
	if s.side_t > 0.0:
		s.side_t -= delta
		dir = (dir * 0.3 + (s.side as Vector3)).normalized()
	return dir

func _bot_obj(id: int) -> Variant:
	if _lift_online and not _relocating:
		return _approach(LIFTS[_tower], players[id].position, 0.0)
	if _bot_role.get(id, "hide") != "fuse" or not _live:
		return null
	if _carried_by(id) >= 0:
		var away_b: Vector3 = FUSEBOX - (TOWERS[1] as Vector3)
		away_b.y = 0.0
		away_b = away_b.normalized()
		var best_p := FUSEBOX
		var best_dd := INF
		for ang in [-1.2, 0.0, 1.2]:
			var cand: Vector3 = FUSEBOX + away_b.rotated(Vector3.UP, ang) * 1.25
			var dd := cand.distance_to(players[id].position)
			if dd < best_dd:
				best_dd = dd
				best_p = cand
		return best_p
	var best: Variant = null
	var best_d := INF
	for i in _fuse_state.size():
		if int(_fuse_state[i]) == 0:
			var fp: Vector3 = _fuse_pos[i]
			var d := fp.distance_to(players[id].position)
			if d < best_d:
				best_d = d
				best = fp
	return best

func _approach(target: Vector3, from: Vector3, r: float) -> Vector3:
	var d := Vector3(from.x - target.x, 0, from.z - target.z)
	if d.length() < 0.01 or r <= 0.0:
		return Vector3(target.x, 0, target.z)
	return Vector3(target.x, 0, target.z) + d.normalized() * r

func _route(from: Vector3, s: Dictionary) -> Vector3:
	var goal: Vector3 = s.goal
	if s.via != null:
		if Vector2(from.x - s.via.x, from.z - s.via.z).length() > 0.45 and _blocker(from, s.via, 0.25) < 0:
			return s.via
		s.via = null
	var bi := _blocker(from, goal, 0.35)
	if bi < 0:
		return goal
	var sd: Dictionary = _solids[bi]
	var hs: Vector3 = sd.s * 0.5 + Vector3(0.75, 0, 0.75)
	var best := goal
	var best_d := INF
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var corner: Vector3 = sd.c + Vector3(hs.x * cx, 0, hs.z * cz).rotated(Vector3.UP, deg_to_rad(float(sd.yaw)))
			corner.y = 0.0
			corner.x = clampf(corner.x, 0.35, W - 0.35)
			corner.z = clampf(corner.z, 0.35, D - 0.35)
			var d := from.distance_to(corner) + corner.distance_to(goal)
			if _blocker(from, corner, 0.2) >= 0:
				d += 30.0
			if d < best_d:
				best_d = d
				best = corner
	s.via = best
	return best

func _blocker(a: Vector3, b: Vector3, pad: float) -> int:
	for i in _solids.size():
		var sd: Dictionary = _solids[i]
		var c: Vector3 = sd.c
		var yaw := deg_to_rad(float(sd.yaw))
		var la := (a - c).rotated(Vector3.UP, -yaw)
		var lb := (b - c).rotated(Vector3.UP, -yaw)
		var hx: float = sd.s.x * 0.5 + pad
		var hz: float = sd.s.z * 0.5 + pad
		var t0 := 0.0
		var t1 := 1.0
		var ok := true
		for axis in 2:
			var p0: float = la.x if axis == 0 else la.z
			var d: float = (lb.x - la.x) if axis == 0 else (lb.z - la.z)
			var h: float = hx if axis == 0 else hz
			if absf(d) < 0.00001:
				if absf(p0) > h:
					ok = false
			else:
				var e0 := (-h - p0) / d
				var e1 := (h - p0) / d
				t0 = maxf(t0, minf(e0, e1))
				t1 = minf(t1, maxf(e0, e1))
		if ok and t0 <= t1:
			return i
	return -1

func _make_spots() -> void:
	for ti in _eyes.size():
		var eye: Vector3 = _eyes[ti]
		var eye_flat := Vector3(eye.x, 0, eye.z)
		var spots_i: Array = []
		for sd in _solids:
			var c: Vector3 = sd.c
			var hs: Vector3 = sd.s * 0.5
			if sd.s.y < 1.0:
				continue
			var offs := [0.0]
			if maxf(hs.x, hs.z) > 1.0:
				offs = [-0.85, -0.4, 0.0, 0.4, 0.85]
			for o in offs:
				var along := Vector3(hs.x * o, 0, 0) if hs.x > hs.z else Vector3(0, 0, hs.z * o)
				var base: Vector3 = c + along.rotated(Vector3.UP, deg_to_rad(float(sd.yaw)))
				base.y = 0.0
				var away := (base - eye_flat).normalized()
				var spot := _push_out(base, away, sd)
				if spot.x > 0.4 and spot.x < W - 0.4 and spot.z > 0.4 and spot.z < D - 0.4:
					spots_i.append(spot)
		if spots_i.is_empty():
			spots_i.append(Vector3(W * 0.5, 0, D * 0.8))
		_spot_sets.append(spots_i)

func _push_out(base: Vector3, away: Vector3, sd: Dictionary) -> Vector3:
	var p := base
	for i in 40:
		if not _inside(p, sd, 0.5):
			break
		p += away * 0.1
	return p + away * 0.15

func _inside(p: Vector3, sd: Dictionary, pad: float) -> bool:
	var c: Vector3 = sd.c
	var hs: Vector3 = sd.s * 0.5
	var local := (p - c).rotated(Vector3.UP, -deg_to_rad(float(sd.yaw)))
	return absf(local.x) < hs.x + pad and absf(local.z) < hs.z + pad

func _pick_spot(from: Vector3, danger: Vector3, id: int, min_d: float) -> Vector3:
	if _spot_sets.is_empty():
		_make_spots()
	var taken: Array = []
	for k in _bot:
		if k != id:
			taken.append(_bot[k].goal)
	var best := from
	var best_s := -INF
	var anchor: Vector3 = _camp[id].a if _camp.has(id) else from
	for sp in _spot_sets[_tower]:
		if Vector2(sp.x - anchor.x, sp.z - anchor.z).length() < min_d:
			continue
		var score := -from.distance_to(sp) * 0.3 + Vector2(sp.x - danger.x, sp.z - danger.z).length() * 0.5 + randf() * 3.5
		for t in taken:
			if (t as Vector3).distance_to(sp) < 1.6:
				score -= 4.0
		if from.distance_to(sp) < 0.6:
			score -= 3.0
		if score > best_s:
			best_s = score
			best = sp
	return best

func _bot_hunter_think(delta: float) -> void:
	if not _live:
		return
	_bh_check -= delta
	if _bh_check <= 0.0:
		_bh_check = 0.25
		var spotted_vis := 0
		var spotted_any := 0
		var nearest := 0
		var best_a := INF
		for id in _runners_alive():
			var vis := _visible_from_eye(id)
			if _spotted.get(id, false):
				spotted_any = id
				if vis:
					spotted_vis = id
			if vis:
				var d: Vector3 = players[id].global_position + Vector3(0, 1.2, 0) - _eye
				var ang := _bh_aim.angle_to(d)
				if ang < best_a:
					best_a = ang
					nearest = id
		var keep: bool = _bh_target != 0 and players.has(_bh_target) and players[_bh_target].alive and (_visible_from_eye(_bh_target) or _spotted.get(_bh_target, false))
		var pick: int = _bh_target if keep else 0
		var carrier_vis := 0
		for id in _runners_alive():
			if (_carried_by(id) >= 0 or float(_hold_t.get(id, 0.0)) > 0.0) and _visible_from_eye(id):
				carrier_vis = id
		if carrier_vis != 0:
			pick = carrier_vis
		elif spotted_vis != 0:
			pick = spotted_vis
		elif not keep:
			pick = spotted_any if spotted_any != 0 else nearest
		if pick != _bh_target:
			_bh_target = pick
			_bh_hold = 0.0
			if pick != 0:
				_bh_react = randf_range(0.5, 1.0)
				_bh_hold = 0.0
				_bh_need = randf_range(0.25, 0.75)
				_bh_head = randf() < 0.22
		_bh_vis = _bh_target != 0 and _visible_from_eye(_bh_target)
	var want := _bh_aim
	if _bh_target != 0:
		var tp: LabPlayer3D = players[_bh_target]
		want = (tp.global_position + Vector3(0, 1.55 if _bh_head else 1.15, 0) - _eye).normalized()
	else:
		_bh_sweep += delta * 0.6
		want = (Vector3(W * 0.5 + sin(_bh_sweep) * 7.0, 0.8, D * 0.5 + cos(_bh_sweep * 0.7) * 3.0) - _eye).normalized()
	if _bh_react > 0.0:
		_bh_react -= delta
	else:
		var wob := Vector3(sin(Time.get_ticks_msec() * 0.0021), sin(Time.get_ticks_msec() * 0.0017) * 0.5, cos(Time.get_ticks_msec() * 0.0013)) * 0.008
		_bh_aim = _bh_aim.slerp((want + wob).normalized(), clampf(delta * 4.5, 0.0, 1.0)).normalized()
	_aim = _bh_aim
	_aim_send_t -= delta
	if _aim_send_t <= 0.0 and not _ended:
		_aim_send_t = 0.05
		_rpc_aim.rpc(_aim)
	if _bh_target != 0 and _bh_aim.angle_to(want) < deg_to_rad(1.6):
		_bh_hold += delta
	if _bh_target != 0 and _bh_vis and not _relocating and _bh_hold >= _bh_need and Time.get_ticks_msec() - _srv_shot_ms >= 2200 and _ammo > 0:
		var spread := Vector3(randfn(0.0, 1.0), randfn(0.0, 0.6), randfn(0.0, 1.0)) * 0.025
		_bh_hold = 0.0
		_bh_need = randf_range(0.6, 1.3)
		_bh_head = randf() < 0.22
		_server_fire(_eye, (_bh_aim + spread).normalized())

@rpc("any_peer", "call_local", "reliable")
func _rpc_fire_request(origin: Vector3, dir: Vector3) -> void:
	if not NetworkManager.is_server():
		return
	var s := multiplayer.get_remote_sender_id()
	if s == 0:
		s = multiplayer.get_unique_id()
	if s != hunter or not _live:
		return
	if origin.distance_to(_eye) > 1.0:
		origin = _eye
	_server_fire(origin, dir)

func _server_fire(origin: Vector3, dir: Vector3) -> void:
	if not _live or _ammo <= 0 or _relocating or _executor != 0:
		return
	if Time.get_ticks_msec() - _srv_shot_ms < int(BOLT_TIME * 1000.0) - 150:
		return
	_srv_shot_ms = Time.get_ticks_msec()
	_ammo -= 1
	var hit := _cast(origin, dir)
	var pt: Vector3 = hit.position
	var kind := 0
	var victim := 0
	var head := false
	if hit.collider is LabPlayer3D:
		var p: LabPlayer3D = hit.collider
		if p.alive and p.peer_id != hunter:
			victim = p.peer_id
			head = _is_headshot(p, pt)
			_hits[victim] = int(_hits.get(victim, 0)) + 1
			kind = 3 if head or int(_hits[victim]) >= 2 or _carried_by(victim) >= 0 else 2
			if kind == 3:
				elim_order.append(victim)
	elif hit.collider != null:
		kind = 1
	_rpc_shot.rpc(pt, kind, victim, head, _ammo, int(_hits.get(victim, 0)))
	if kind == 3 and _carried_by(victim) >= 0:
		_rpc_fuse.rpc(_carried_by(victim), 0, Vector3(players[victim].position.x, 0.0, players[victim].position.z))

func _is_headshot(p: LabPlayer3D, pt: Vector3) -> bool:
	var sk: Skeleton3D = p.body.skeleton
	if sk:
		var bi := sk.find_bone("Head")
		if bi >= 0:
			var hp: Vector3 = sk.global_transform * sk.get_bone_global_pose(bi).origin
			if pt.distance_to(hp + Vector3(0, 0.08, 0)) < 0.3:
				return true
	return pt.y > p.global_position.y + 1.5

@rpc("authority", "call_local", "reliable")
func _rpc_shot(pt: Vector3, kind: int, victim: int, head: bool, ammo_left: int, hits: int) -> void:
	_ammo = ammo_left
	if not _is_local_hunter():
		_last_shot_ms = Time.get_ticks_msec()
	var from := _muzzle_world()
	_muzzle_flash(from)
	_tracer(from, pt)
	if _is_local_hunter():
		Fx.sfx("gunshot", null, 2.0, 0.85)
		Fx.shake(0.45)
		_kick = 0.045
	else:
		Fx.sfx("gunshot", _eye, 4.0, 0.8)
		Fx.shake(0.12)
	match kind:
		1:
			Fx.sparks(world, pt)
			Fx.sfx("hit", pt, -6.0, 1.4)
		0:
			Fx.sparks(world, pt + Vector3(0, 0.05, 0))
		2:
			_hits[victim] = hits
			if players.has(victim):
				var p: LabPlayer3D = players[victim]
				p.body.play_action("Hit_Chest")
				p.speed = RUN_SPEED * LIMP
				Fx.blood(world, pt, 28)
				Fx.sfx("hit", pt, 0.0)
			_flash("HIT" if _is_local_hunter() else "")
		3:
			_hits[victim] = hits
			if not elim_order.has(victim):
				elim_order.append(victim)
			if head and players.has(victim):
				Fx.blood(world, pt, 90)
			eliminate(victim, "Death01")
			_flash(("HEADSHOT" if head else "KILL") if _is_local_hunter() else "")
	if victim != 0 and victim == multiplayer.get_unique_id():
		Fx.shake(0.6)

func _flash(text: String) -> void:
	if text == "":
		return
	_flash_label.text = text
	_flash_label.modulate.a = 1.0

func _muzzle_flash(at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 9.0
	l.omni_range = 6.0
	world.add_child(l)
	l.global_position = at
	var f := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	f.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.5)
	f.material_override = m
	f.layers = 2
	f.visible = not (_is_local_hunter() and _zoom > 0.5)
	world.add_child(f)
	f.global_position = at
	f.scale = Vector3(1.0, 1.0, 2.2)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.09)
	tw.tween_callback(l.queue_free)
	tw.tween_callback(f.queue_free)

func _tracer(a: Vector3, b: Vector3) -> void:
	if a.distance_to(b) < 0.1:
		return
	var t := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 1.0)
	t.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	t.material_override = m
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(t)
	t.global_position = (a + b) * 0.5
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.98 else Vector3.RIGHT
	t.look_at(b, up)
	t.scale = Vector3(1.0, 1.0, a.distance_to(b))
	var tw := t.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(t.queue_free)


