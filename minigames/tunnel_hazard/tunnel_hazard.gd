extends ArenaMinigame3D
## Tunnel Hazard: subjects race down a lit underground rail tunnel to the exit
## doors at the far end. Trains thunder down random lanes from ahead or behind;
## a lane's light strip turns red and its rails glow 1.5 s before one arrives.
## SPACE shoves a nearby rival sideways into the next lane. First through the
## exit wins, then survivors by distance run; the flattened place last.

const TIME_LIMIT: float = 50.0
const LANES: int = 4
const LANE_W: float = 2.5
const HALF: float = 5.0
const WALL_X: float = 6.3
const FINISH_Z: float = -90.0
const TUN_FRONT: float = -140.0
const TUN_BACK: float = 30.0
const WARN: float = 1.5
const RUN_SPEED: float = 4.2
const CAR_LEN: float = 11.0
const CAR_GAP: float = 0.6
const CARS: int = 2
const TRAIN_LEN: float = CAR_LEN * CARS + CAR_GAP * (CARS - 1)
const HIT_HALF: float = 1.45
const SHOVE_RANGE: float = 1.5
const SHOVE_DX: float = 2.3
const SHOVE_CD: float = 0.9
const STUN: float = 0.45

enum St { COUNTDOWN, RUN, DONE }

var st: St = St.COUNTDOWN
var clock: float = 0.0
var trains: Dictionary = {}
var finish_order: Array = []
var dead_order: Array = []
var _next_train_id: int = 1
var _next_train: float = 1.2
var _shove_ready: Dictionary = {}
var _stun_until: Dictionary = {}
var _bot: Dictionary = {}
var _sync_t: float = 0.0
var _space_down: bool = false
var _ended: bool = false
var _focus_z: float = 0.0

var _rail_mats: Array[StandardMaterial3D] = []
var _strip_mats: Array[StandardMaterial3D] = []
var _lane_lights: Array[OmniLight3D] = []
var _beacon: Node3D
var _big: Label
var _hint: Label
var _timer_label: Label
var _dist_label: Label

func begin() -> void:
	setup_arena(false)
	_tune_light()
	_build_tunnel()
	_build_exit()
	spawn_players(_spawns())
	for id in players:
		var p: LabPlayer3D = players[id]
		p.speed = RUN_SPEED
		p.bounds = AABB(Vector3(-HALF + 0.12, -5.0, FINISH_Z - 4.0), Vector3((HALF - 0.12) * 2.0, 20.0, 12.0 - FINISH_Z))
		p.input_enabled = false
		p.face(Vector3(0, 0, -1))
		p.bot_brain = _bot_brain.bind(id)
		_shove_ready[id] = 0.0
		_stun_until[id] = -1.0
		if p.is_bot:
			_bot[id] = {"react": randf_range(0.3, 0.65), "greed": randf_range(0.15, 0.32), "aggro": randf_range(0.35, 0.7), "think": 0.0, "lane": _lane_of(p.position.x), "wobble": randf_range(-0.4, 0.4)}
	camera.fov = 55.0
	_place_camera(1.0)
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _spawns() -> Array:
	var a: Array = []
	var n: int = NetworkManager.players.size()
	var i := 0
	for id in NetworkManager.players:
		var x: float = lerpf(-HALF + 0.8, HALF - 0.8, (float(i) + 0.5) / float(maxi(n, 1)))
		a.append(Vector3(x, 0.0, 1.0 + float(i % 2) * 1.2))
		i += 1
	return a

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.18
			n.shadow_enabled = false
	env.ambient_light_energy = 0.38
	env.ambient_light_color = Color(0.55, 0.56, 0.5)
	env.fog_density = 0.034
	env.fog_light_color = Color(0.07, 0.07, 0.06)
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05

func _lane_x(l: int) -> float:
	return -HALF + LANE_W * (float(l) + 0.5)

func _lane_of(x: float) -> int:
	return clampi(int(floor((x + HALF) / LANE_W)), 0, LANES - 1)

func _cyl(r: float, h: float, m: Material, pos: Vector3, rot: Vector3, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = m
	mi.rotation_degrees = rot
	mi.position = pos
	parent.add_child(mi)
	return mi

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

func _build_tunnel() -> void:
	var t := Node3D.new()
	t.name = "Tunnel"
	world.add_child(t)
	var L := TUN_BACK - TUN_FRONT
	var mid := (TUN_BACK + TUN_FRONT) * 0.5
	box(Vector3(WALL_X * 2.0 + 1.0, 0.2, L), Vector3(0, -0.12, mid), mat("damaged_concrete_floor", 0.4, Color(0.6, 0.58, 0.52)), t)
	for l in LANES:
		box(Vector3(LANE_W - 0.3, 0.1, L), Vector3(_lane_x(l), -0.03, mid), mat("gravel_floor", 0.5, Color(0.55, 0.52, 0.48)), t)
	for k in LANES + 1:
		box(Vector3(0.3, 0.12, L), Vector3(-HALF + LANE_W * k, 0.0, mid), mat("dirty_concrete", 0.6, Color(0.55, 0.55, 0.5)), t)
	for sx in [-1.0, 1.0]:
		var lw: float = WALL_X - HALF - 0.15
		box(Vector3(lw, 0.4, L), Vector3(sx * (HALF + 0.15 + lw * 0.5), 0.2, mid), mat("concrete_floor_worn_001", 0.45, Color(0.6, 0.58, 0.52)), t)
		box(Vector3(lw, 0.06, L), Vector3(sx * (HALF + 0.15 + lw * 0.5), 0.41, mid), mat("metal_grate_rusty", 0.8, Color(0.7, 0.66, 0.6)), t)
		_wall_segment(t, sx, TUN_BACK, FINISH_Z + 1.5)
		_wall_segment(t, sx, FINISH_Z - 3.5, TUN_FRONT)
		box(Vector3(0.5, 1.6, 5.0), Vector3(sx * (WALL_X + 0.25), 3.8, FINISH_Z - 1.0), mat("concrete_wall_008", 0.35, Color(0.62, 0.62, 0.56)), t)
		var slant := box(Vector3(5.5, 0.4, L), Vector3(sx * 4.3, 6.5, mid), mat("dirty_concrete", 0.4, Color(0.42, 0.42, 0.38)), t)
		slant.rotation.z = -sx * deg_to_rad(40.0)
		var cable_mat := _plain(Color(0.05, 0.05, 0.05), 0.55)
		for c in [[3.15, 0.045], [3.28, 0.06], [3.42, 0.04], [3.55, 0.07]]:
			_cyl(c[1], L, cable_mat, Vector3(sx * (WALL_X - 0.12), c[0], mid), Vector3(90, 0, 0), t)
		_cyl(0.13, L, mat("rusty_metal_02", 1.5), Vector3(sx * (WALL_X - 0.2), 4.05, mid), Vector3(90, 0, 0), t)
		_cyl(0.08, L, mat("rusty_metal", 1.5), Vector3(sx * (WALL_X - 0.16), 4.38, mid), Vector3(90, 0, 0), t)
		var z := TUN_BACK
		while z > TUN_FRONT:
			box(Vector3(0.2, 0.06, 0.5), Vector3(sx * (WALL_X - 0.15), 3.08, z), mat("rusty_metal", 1.0), t)
			z -= 3.5
	box(Vector3(5.2, 0.4, L), Vector3(0, 8.3, mid), mat("dirty_concrete", 0.4, Color(0.38, 0.38, 0.34)), t)
	box(Vector3(WALL_X * 2.0 + 1.0, 9.0, 0.5), Vector3(0, 4.5, TUN_FRONT), mat("dirty_concrete", 0.4, Color(0.3, 0.3, 0.28)), t)
	box(Vector3(WALL_X * 2.0 + 1.0, 9.0, 0.5), Vector3(0, 4.5, TUN_BACK), mat("dirty_concrete", 0.4, Color(0.3, 0.3, 0.28)), t)
	_build_tracks(t)
	_build_ribs_and_lamps(t)
	_build_clutter(t)

func _wall_segment(t: Node3D, sx: float, z0: float, z1: float) -> void:
	var seg_len := absf(z0 - z1)
	var mz := (z0 + z1) * 0.5
	box(Vector3(0.5, 4.8, seg_len), Vector3(sx * (WALL_X + 0.25), 2.4, mz), mat("concrete_wall_008", 0.35, Color(0.62, 0.62, 0.56)), t)
	box(Vector3(0.52, 1.2, seg_len), Vector3(sx * (WALL_X + 0.24), 1.0, mz), mat("dirty_concrete", 0.5, Color(0.45, 0.43, 0.38)), t)

func _build_tracks(t: Node3D) -> void:
	var L := TUN_BACK - TUN_FRONT
	var mid := (TUN_BACK + TUN_FRONT) * 0.5
	var sm := BoxMesh.new()
	sm.size = Vector3(2.0, 0.09, 0.24)
	sm.material = mat("worn_planks", 0.7, Color(0.42, 0.36, 0.3))
	var per := int(L / 0.7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	mm.instance_count = per * LANES
	for l in LANES:
		for i in per:
			var b := Basis(Vector3.UP, randf_range(-0.04, 0.04))
			mm.set_instance_transform(l * per + i, Transform3D(b, Vector3(_lane_x(l) + randf_range(-0.04, 0.04), 0.05, TUN_BACK - 0.35 - i * 0.7)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	t.add_child(mmi)
	for l in LANES:
		var rm: StandardMaterial3D = mat("rusty_metal", 1.6, Color(0.75, 0.7, 0.66)).duplicate()
		rm.emission_enabled = true
		rm.emission = Color(1.0, 0.25, 0.08)
		rm.emission_energy_multiplier = 0.0
		_rail_mats.append(rm)
		for dx in [-0.72, 0.72]:
			box(Vector3(0.08, 0.14, L), Vector3(_lane_x(l) + dx, 0.16, mid), rm, t)
		var sm2 := _glow(Color(1.0, 0.62, 0.2), 0.35)
		_strip_mats.append(sm2)
		box(Vector3(0.1, 0.03, L), Vector3(_lane_x(l), 0.115, mid), sm2, t)
		var ll := OmniLight3D.new()
		ll.light_color = Color(1.0, 0.12, 0.06)
		ll.light_energy = 0.0
		ll.omni_range = 9.0
		ll.omni_attenuation = 1.2
		world.add_child(ll)
		ll.position = Vector3(_lane_x(l), 0.8, 0.0)
		_lane_lights.append(ll)

func _build_ribs_and_lamps(t: Node3D) -> void:
	var z := TUN_BACK - 3.0
	var k := 0
	var rib := mat("concrete_wall_008", 0.35, Color(0.5, 0.5, 0.45))
	var steel := mat("rusty_metal", 1.0, Color(0.6, 0.55, 0.5))
	while z > TUN_FRONT + 2.0:
		var at_exit := z < FINISH_Z + 2.0 and z > FINISH_Z - 4.0
		for sx in [-1.0, 1.0]:
			if not at_exit:
				box(Vector3(0.4, 4.8, 0.7), Vector3(sx * (WALL_X - 0.1), 2.4, z), rib, t)
		box(Vector3(6.2, 0.3, 0.26), Vector3(0, 7.6, z), steel, t)
		var side: float = 1.0 if k % 2 == 0 else -1.0
		var sz := z - 3.5
		if not (sz < FINISH_Z + 2.0 and sz > FINISH_Z - 4.0):
			prop("industrial_caged_sconce", Vector3(side * (WALL_X - 0.02), 2.7, sz), -90.0 * side, 1.5, t)
			var o := OmniLight3D.new()
			o.light_color = Color(1.0, 0.76, 0.46)
			o.light_energy = 1.7
			o.omni_range = 7.5
			o.omni_attenuation = 1.3
			t.add_child(o)
			o.position = Vector3(side * (WALL_X - 0.6), 2.9, sz)
			box(Vector3(0.12, 0.1, 0.12), Vector3(side * (WALL_X - 0.02), 2.7, sz), _glow(Color(1.0, 0.8, 0.5), 3.0), t)
		if k % 2 == 0:
			var lx: float = _lane_x((k / 2) % LANES) if k % 4 == 0 else 0.0
			prop("caged_hanging_light", Vector3(lx, 7.45, z), 0.0, 1.0, t)
			var h := OmniLight3D.new()
			h.light_color = Color(1.0, 0.85, 0.6)
			h.light_energy = 2.4
			h.omni_range = 9.5
			h.omni_attenuation = 1.1
			h.shadow_enabled = k % 4 == 0 and z > -60.0
			t.add_child(h)
			h.position = Vector3(lx, 5.4, z)
		z -= 7.0
		k += 1
	var m := 10
	while m <= 90:
		for sx in [-1.0, 1.0]:
			var lab := Label3D.new()
			lab.text = "%d" % (90 - m) if m < 90 else "EXIT"
			lab.font_size = 160
			lab.pixel_size = 0.005
			lab.modulate = Color(0.85, 0.82, 0.7, 0.75)
			lab.outline_size = 0
			lab.shaded = true
			t.add_child(lab)
			lab.position = Vector3(sx * (WALL_X - 0.02), 1.6, -float(m) + 1.2)
			lab.rotation_degrees.y = -90.0 * sx
		m += 10

func _build_clutter(t: Node3D) -> void:
	var junk := ["barrel_03", "trashbag", "old_tyre", "cardboard_box_01", "wooden_crate_01", "cement_bag", "concrete_road_barrier", "metal_jerrycan", "utility_box_01", "plastic_crate_01", "old_military_crate", "metal_trash_can", "wooden_crate_02", "propane_tank"]
	var z := TUN_BACK - 4.0
	while z > TUN_FRONT + 4.0:
		for sx in [-1.0, 1.0]:
			if z < FINISH_Z + 2.5 and z > FINISH_Z - 4.5:
				continue
			if randf() < 0.75:
				var id: String = junk[randi() % junk.size()]
				var yaw: float = -90.0 * sx if id == "concrete_road_barrier" or id == "utility_box_01" else randf() * 360.0
				prop(id, Vector3(sx * randf_range(5.55, 5.9), 0.44, z + randf_range(-1.2, 1.2)), yaw, randf_range(0.95, 1.2), t)
		if randf() < 0.3:
			prop("power_box_01", Vector3(-WALL_X + 0.02, 1.8, z + 1.7), 90.0, 1.4, t)
		z -= randf_range(2.6, 4.2)
	for i in 34:
		var pm := _plain(Color(0.05, 0.045, 0.035, 0.86), 0.03, 0.2)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var px := randf_range(-HALF, HALF)
		var pz := randf_range(FINISH_Z - 20.0, 10.0)
		var pu := box(Vector3(randf_range(0.7, 2.2), 0.01, randf_range(0.6, 1.8)), Vector3(px, 0.075, pz), pm, t)
		pu.rotation.y = randf() * PI
	for i in 22:
		var id: String = ["cardboard_box_01", "can_rusted", "cement_bag", "old_tyre", "trashbag"][randi() % 5]
		var d := prop(id, Vector3(randf_range(-HALF + 0.3, HALF - 0.3), 0.04, randf_range(FINISH_Z - 30.0, 8.0)), randf() * 360.0, 0.9, t)
		if d and id == "old_tyre":
			d.rotation_degrees.x = 90.0

func _build_exit() -> void:
	var e := Node3D.new()
	e.name = "Exit"
	world.add_child(e)
	var hz := _glow(Color(0.95, 0.75, 0.1), 0.6)
	for i in 14:
		var stripe := box(Vector3(0.38, 0.02, 0.5), Vector3(-HALF + 0.36 + i * 0.72, 0.19, FINISH_Z), hz if i % 2 == 0 else _plain(Color(0.04, 0.04, 0.04), 0.8), e)
		stripe.rotation.y = 0.5
	box(Vector3(WALL_X * 2.0, 0.6, 0.5), Vector3(0, 4.3, FINISH_Z), mat("rusty_metal", 1.0, Color(0.5, 0.48, 0.42)), e)
	var exit_sign := Label3D.new()
	exit_sign.text = "EXIT  ◄   ►  EXIT"
	exit_sign.font_size = 120
	exit_sign.pixel_size = 0.006
	exit_sign.modulate = Color(0.45, 1.0, 0.5)
	exit_sign.outline_size = 0
	e.add_child(exit_sign)
	exit_sign.position = Vector3(0, 4.3, FINISH_Z + 0.27)
	for sx in [-1.0, 1.0]:
		var ax: float = sx * (WALL_X + 1.9)
		box(Vector3(3.4, 0.2, 5.0), Vector3(ax, 0.32, FINISH_Z - 1.0), mat("metal_grate_rusty", 0.8), e)
		box(Vector3(0.4, 4.0, 5.0), Vector3(sx * (WALL_X + 3.6), 2.0, FINISH_Z - 1.0), mat("factory_brick", 0.4, Color(0.6, 0.55, 0.5)), e)
		box(Vector3(3.4, 0.3, 5.0), Vector3(ax, 3.1, FINISH_Z - 1.0), mat("dirty_concrete", 0.4), e)
		for dz in [1.5, -3.5]:
			box(Vector3(3.4, 3.1, 0.3), Vector3(ax, 1.55, FINISH_Z + dz), mat("factory_brick", 0.4, Color(0.6, 0.55, 0.5)), e)
		var g := OmniLight3D.new()
		g.light_color = Color(0.4, 1.0, 0.5)
		g.light_energy = 3.0
		g.omni_range = 6.0
		e.add_child(g)
		g.position = Vector3(ax, 2.4, FINISH_Z - 1.0)
		box(Vector3(0.05, 0.25, 0.8), Vector3(sx * (WALL_X - 0.02), 3.4, FINISH_Z - 1.0), _glow(Color(0.3, 1.0, 0.4), 4.0), e)
		prop("security_light", Vector3(sx * (WALL_X + 0.0), 3.5, FINISH_Z + 1.9), -90.0 * sx, 1.4, e)
	_beacon = Node3D.new()
	e.add_child(_beacon)
	_beacon.position = Vector3(0, 3.85, FINISH_Z + 0.1)
	_cyl(0.16, 0.3, _glow(Color(1.0, 0.1, 0.05), 5.0), Vector3.ZERO, Vector3.ZERO, _beacon)
	for yaw in [0.0, 180.0]:
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.15, 0.05)
		sp.light_energy = 14.0
		sp.spot_range = 22.0
		sp.spot_angle = 22.0
		_beacon.add_child(sp)
		sp.rotation_degrees = Vector3(-12.0, yaw, 0.0)
	var red := OmniLight3D.new()
	red.light_color = Color(1.0, 0.2, 0.08)
	red.light_energy = 2.0
	red.omni_range = 7.0
	_beacon.add_child(red)

func _build_train(s: int) -> Node3D:
	var tr := Node3D.new()
	var shell := mat("corrugated_iron", 0.9, Color(0.55, 0.58, 0.55))
	var skirt := mat("green_metal_rust", 0.8, Color(0.5, 0.52, 0.48))
	var roof := mat("rusty_metal_02", 0.9, Color(0.6, 0.58, 0.55))
	var dark := mat("rusty_metal", 1.2, Color(0.28, 0.27, 0.25))
	var win := _glow(Color(1.0, 0.82, 0.5), 0.9)
	var band := mat("blue_metal_plate", 1.0, Color(0.7, 0.18, 0.12))
	for c in CARS:
		var o: float = c * (CAR_LEN + CAR_GAP)
		var cz: float = o + CAR_LEN * 0.5
		box(Vector3(2.32, 0.55, CAR_LEN - 0.2), Vector3(0, 0.62, cz), skirt, tr)
		box(Vector3(2.4, 1.95, CAR_LEN), Vector3(0, 1.85, cz), shell, tr)
		box(Vector3(2.42, 0.14, CAR_LEN), Vector3(0, 1.2, cz), band, tr)
		box(Vector3(2.2, 0.32, CAR_LEN - 0.3), Vector3(0, 2.96, cz), roof, tr)
		box(Vector3(1.2, 0.18, CAR_LEN * 0.6), Vector3(0, 3.18, cz), dark, tr)
		for sx in [-1.0, 1.0]:
			var wz: float = o + 1.4
			while wz < o + CAR_LEN - 1.0:
				box(Vector3(0.05, 0.62, 1.15), Vector3(sx * 1.2, 2.08, wz), win, tr)
				wz += 1.55
			for dz in [CAR_LEN * 0.3, CAR_LEN * 0.72]:
				box(Vector3(0.06, 1.75, 1.0), Vector3(sx * 1.2, 1.78, o + dz), dark, tr)
				box(Vector3(0.07, 0.55, 0.36), Vector3(sx * 1.2, 2.15, o + dz - 0.24), win, tr)
				box(Vector3(0.07, 0.55, 0.36), Vector3(sx * 1.2, 2.15, o + dz + 0.24), win, tr)
		for bz in [o + 2.0, o + CAR_LEN - 2.0]:
			box(Vector3(1.9, 0.38, 2.4), Vector3(0, 0.38, bz), dark, tr)
			for wz in [bz - 0.75, bz + 0.75]:
				for sx in [-0.78, 0.78]:
					_cyl(0.3, 0.12, dark, Vector3(sx, 0.3, wz), Vector3(0, 0, 90), tr)
		if c > 0:
			box(Vector3(1.4, 2.1, CAR_GAP + 0.1), Vector3(0, 1.8, o - CAR_GAP * 0.5), _plain(Color(0.06, 0.06, 0.06), 0.9), tr)
	box(Vector3(2.44, 2.5, 0.2), Vector3(0, 1.65, -0.05), mat("blue_metal_plate", 1.0, Color(0.95, 0.72, 0.2)), tr)
	box(Vector3(1.9, 0.75, 0.06), Vector3(0, 2.2, -0.17), _plain(Color(0.03, 0.035, 0.04), 0.05, 0.6), tr)
	box(Vector3(2.0, 0.2, 0.3), Vector3(0, 0.5, -0.2), dark, tr)
	for sx in [-0.78, 0.78]:
		box(Vector3(0.32, 0.22, 0.06), Vector3(sx, 1.0, -0.17), _glow(Color(1.0, 0.95, 0.8), 9.0), tr)
	box(Vector3(0.5, 0.14, 0.06), Vector3(0, 2.75, -0.17), _glow(Color(1.0, 0.9, 0.6), 4.0), tr)
	for sx in [-0.85, 0.85]:
		box(Vector3(0.25, 0.18, 0.06), Vector3(sx, 1.0, TRAIN_LEN + 0.03), _glow(Color(1.0, 0.05, 0.03), 5.0), tr)
	var head := SpotLight3D.new()
	head.light_color = Color(1.0, 0.93, 0.78)
	head.light_energy = 16.0
	head.spot_range = 38.0
	head.spot_angle = 24.0
	head.spot_attenuation = 0.7
	tr.add_child(head)
	head.position = Vector3(0, 1.3, -0.4)
	head.rotation_degrees.x = -3.0
	var pool := OmniLight3D.new()
	pool.light_color = Color(1.0, 0.9, 0.7)
	pool.light_energy = 2.5
	pool.omni_range = 6.0
	tr.add_child(pool)
	pool.position = Vector3(0, 1.0, -1.5)
	var cabin := OmniLight3D.new()
	cabin.light_color = Color(1.0, 0.8, 0.5)
	cabin.light_energy = 1.2
	cabin.omni_range = 5.0
	tr.add_child(cabin)
	cabin.position = Vector3(1.8, 2.0, CAR_LEN * 0.5)
	if s > 0:
		tr.rotation.y = PI
	world.add_child(tr)
	return tr

func _build_hud() -> void:
	hud_title("TUNNEL HAZARD  ·  reach the exit, mind the red lanes")
	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-120, 10)
	_timer_label.size = Vector2(100, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.add_theme_font_size_override("font_size", 26)
	_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_timer_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_timer_label)
	_dist_label = Label.new()
	_dist_label.position = Vector2(16, 40)
	_dist_label.add_theme_font_size_override("font_size", 20)
	_dist_label.add_theme_color_override("font_color", Color("e8e2c8"))
	_dist_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_dist_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_dist_label)
	_big = _center_label(84, 0.3)
	_hint = _center_label(26, 0.86)
	_hint.text = "W  RUN   ·   A / D  CHANGE LANE   ·   SPACE  SHOVE\nred lane + glowing rails = train coming"
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

func _runners() -> Array:
	return alive_ids().filter(func(id): return not finish_order.has(id))

func _place_camera(k: float) -> void:
	var r := _runners()
	if not r.is_empty():
		var lead := INF
		var sum := 0.0
		for id in r:
			var z: float = players[id].position.z
			lead = minf(lead, z)
			sum += z
		var want := lerpf(sum / float(r.size()), lead, 0.55)
		_focus_z = lerpf(_focus_z, want, k)
	var cz := maxf(_focus_z, FINISH_Z + 4.0)
	camera.position = Vector3(0.9, 5.9, cz + 7.2)
	camera.look_at(Vector3(0.2, 0.5, cz - 5.0), Vector3.UP)

func _process(delta: float) -> void:
	if not world:
		return
	_place_camera(1.0 - exp(-2.5 * delta))
	if _beacon:
		_beacon.rotation.y += delta * 5.0
	if st == St.RUN:
		clock += delta
		_handle_input()
	_move_trains(delta)
	_update_lanes()
	var me := local_player()
	if me and _dist_label:
		if finish_order.has(me.peer_id):
			_dist_label.text = "OUT  ·  #%d through the exit" % (finish_order.find(me.peer_id) + 1)
		elif me.alive:
			_dist_label.text = "%d m to the exit" % int(ceil(maxf(0.0, me.position.z - FINISH_Z)))
		else:
			_dist_label.text = "flattened"
	if st == St.RUN and NetworkManager.is_server():
		_server_tick(delta)

func _handle_input() -> void:
	var down := Input.is_physical_key_pressed(KEY_SPACE)
	if down and not _space_down:
		var me := multiplayer.get_unique_id()
		if NetworkManager.is_server():
			_try_shove(me)
		else:
			_rpc_press.rpc_id(1)
	_space_down = down

@rpc("any_peer", "reliable")
func _rpc_press() -> void:
	if NetworkManager.is_server():
		_try_shove(multiplayer.get_remote_sender_id())

func _try_shove(id: int) -> bool:
	if st != St.RUN or not players.has(id) or not players[id].alive or finish_order.has(id):
		return false
	if clock < float(_shove_ready[id]) or clock < float(_stun_until[id]):
		return false
	var me: LabPlayer3D = players[id]
	var best := -1
	var best_d := SHOVE_RANGE
	for o in _runners():
		if o == id:
			continue
		var d: float = me.position.distance_to(players[o].position)
		if d < best_d:
			best_d = d
			best = o
	_shove_ready[id] = clock + SHOVE_CD
	if best < 0:
		_rpc_whiff.rpc(id)
		return false
	var dx: float = players[best].position.x - me.position.x
	var dir: float = signf(dx) if absf(dx) > 0.15 else (1.0 if randf() < 0.5 else -1.0)
	_stun_until[best] = clock + STUN
	_rpc_shove.rpc(id, best, dir * SHOVE_DX)
	return true

@rpc("authority", "call_local", "reliable")
func _rpc_whiff(id: int) -> void:
	if players.has(id) and players[id].alive:
		players[id].body.play_action("Punch_Cross", 0.08, 1.6)
		Fx.sfx("whoosh", players[id].position, -8.0)

@rpc("authority", "call_local", "reliable")
func _rpc_shove(a: int, v: int, dx: float) -> void:
	var pa: LabPlayer3D = players[a]
	var pv: LabPlayer3D = players[v]
	pa.face(pv.position - pa.position)
	pa.body.play_action("Punch_Cross", 0.06, 1.6)
	pv.body.play_action("Hit_Knockback", 0.06, 1.3)
	Fx.sfx("hit", pv.position, -2.0)
	Fx.shake(0.12)
	_stun_until[v] = clock + STUN
	if pv.is_multiplayer_authority():
		if pv.is_local_human():
			pv.input_enabled = false
			get_tree().create_timer(STUN).timeout.connect(func() -> void:
				if pv.alive:
					pv.input_enabled = true)
		var tx := clampf(pv.position.x + dx, pv.bounds.position.x, pv.bounds.end.x)
		var tw := create_tween()
		tw.tween_property(pv, "position:x", tx, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _move_trains(delta: float) -> void:
	for tid in trains.keys():
		var tr: Dictionary = trains[tid]
		tr.front = float(tr.front) + float(tr.s) * float(tr.v) * delta
		var node: Node3D = tr.node
		node.position = Vector3(_lane_x(tr.lane), 0.0, tr.front)
		if not tr.rumbled and absf(float(tr.front) - _focus_z) < 7.0:
			tr.rumbled = true
			Fx.shake(0.22)
			Fx.sfx("whoosh", node.position, 2.0, 0.55)
			Fx.sfx("hum", node.position, 0.0, 0.5)
		if not tr.cleared:
			var r := _runners()
			var passed := true
			for id in r:
				if absf(players[id].position.x - _lane_x(tr.lane)) < HIT_HALF + 0.6 and _threat(tr, players[id].position.z) < INF:
					passed = false
					break
			if passed and r.size() > 0 and clock - float(tr.t0) > WARN:
				tr.cleared = true
		var gone: bool = (tr.s < 0 and float(tr.front) + TRAIN_LEN < TUN_FRONT) or (tr.s > 0 and float(tr.front) - TRAIN_LEN > TUN_BACK)
		if gone:
			node.queue_free()
			trains.erase(tid)

func _update_lanes() -> void:
	var blink := fmod(clock, 0.3) < 0.15
	for l in LANES:
		var warn := false
		for tid in trains:
			if int(trains[tid].lane) == l and not trains[tid].cleared:
				warn = true
		var sm: StandardMaterial3D = _strip_mats[l]
		var rm: StandardMaterial3D = _rail_mats[l]
		if warn:
			sm.emission = Color(1.0, 0.06, 0.03)
			sm.emission_energy_multiplier = 5.0 if blink else 2.0
			rm.emission_energy_multiplier = 1.4 if blink else 0.9
			_lane_lights[l].light_energy = 3.5 if blink else 2.2
		else:
			sm.emission = Color(1.0, 0.62, 0.2)
			sm.emission_energy_multiplier = 0.35
			rm.emission_energy_multiplier = 0.0
			_lane_lights[l].light_energy = 0.0
		_lane_lights[l].position.z = _focus_z - 2.0

func _threat(tr: Dictionary, z: float) -> float:
	var f: float = tr.front
	if int(tr.s) < 0:
		if z > f + TRAIN_LEN + 0.3:
			return INF
		if z >= f - 0.3:
			return 0.0
		return (f - z) / maxf(float(tr.v) - RUN_SPEED, 4.0)
	if z < f - TRAIN_LEN - 0.3:
		return INF
	if z <= f + 0.3:
		return 0.0
	return (z - f) / (float(tr.v) + RUN_SPEED)

func _lane_eta(l: int, z: float, known_after: float) -> float:
	var best := INF
	for tid in trains:
		var tr: Dictionary = trains[tid]
		if int(tr.lane) != l or clock - float(tr.t0) < known_after:
			continue
		best = minf(best, _threat(tr, z))
	return best

func _server_tick(delta: float) -> void:
	_next_train -= delta
	if _next_train <= 0.0 and clock < TIME_LIMIT - 1.0:
		_spawn_train()
		_next_train = lerpf(1.8, 0.8, clampf(clock / 38.0, 0.0, 1.0)) * randf_range(0.8, 1.2)
	for tid in trains:
		var tr: Dictionary = trains[tid]
		var lx := _lane_x(tr.lane)
		for id in _runners():
			var p: LabPlayer3D = players[id]
			if absf(p.position.x - lx) < HIT_HALF and _threat(tr, p.position.z) == 0.0:
				dead_order.append(id)
				_rpc_hit.rpc(id, int(tr.s), lx)
	for id in _runners():
		if players[id].position.z <= FINISH_Z:
			finish_order.append(id)
			_rpc_finish.rpc(id, finish_order.size())
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.25
		_rpc_sync.rpc(maxf(0.0, TIME_LIMIT - clock))

func _spawn_train() -> void:
	var busy: Array = []
	for tid in trains:
		busy.append(int(trains[tid].lane))
	var free: Array = []
	for l in LANES:
		if not busy.has(l):
			free.append(l)
	if free.size() < 2:
		return
	var r := _runners()
	if r.is_empty():
		return
	var lane: int = free[randi() % free.size()]
	if randf() < 0.65:
		var target: int = _lane_of(players[r[randi() % r.size()]].position.x)
		if free.has(target):
			lane = target
	var lead := INF
	var last := -INF
	for id in r:
		lead = minf(lead, players[id].position.z)
		last = maxf(last, players[id].position.z)
	var s: int = -1 if randf() < 0.45 else 1
	var v: float = randf_range(21.0, 27.0)
	var front: float
	if s > 0:
		front = lead - WARN * (v + RUN_SPEED) - 1.0
	else:
		front = last + 1.0 + WARN * maxf(v - RUN_SPEED, 4.0)
	_rpc_train.rpc(_next_train_id, lane, s, front, v)
	_next_train_id += 1

@rpc("authority", "call_local", "reliable")
func _rpc_train(tid: int, lane: int, s: int, front: float, v: float) -> void:
	var node := _build_train(s)
	node.position = Vector3(_lane_x(lane), 0.0, front)
	trains[tid] = {"lane": lane, "s": s, "front": front, "v": v, "node": node, "t0": clock, "cleared": false, "rumbled": false}
	Fx.sfx("buzzer", Vector3(_lane_x(lane), 1.0, _focus_z), -2.0, 0.7)
	Fx.sfx("beep", null, -10.0, 0.6)

@rpc("authority", "call_local", "reliable")
func _rpc_hit(id: int, s: int, lane_x: float) -> void:
	if not dead_order.has(id):
		dead_order.append(id)
	var p: LabPlayer3D = players[id]
	if p.is_local_human():
		p.input_enabled = false
	eliminate(id, "Death01")
	Fx.sfx("hit", p.position, 4.0, 0.6)
	Fx.sfx("splat", p.position, 2.0)
	Fx.shake(0.75)
	Fx.blood(world, p.position + Vector3(0, 1.2, float(s) * 0.4), 90)
	var side: float = signf(p.position.x - lane_x)
	if side == 0.0:
		side = 1.0
	var land := Vector3(side * randf_range(1.0, 1.8), 0.0, float(s) * randf_range(6.0, 9.0))
	var b: LabCharacter = p.body
	var tw := create_tween().set_parallel(true)
	tw.tween_property(b, "position:x", land.x, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "position:z", land.z, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "rotation:z", side * TAU, 0.65)
	var up := create_tween()
	up.tween_property(b, "position:y", randf_range(1.8, 2.6), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	up.tween_property(b, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	up.tween_callback(func() -> void:
		Fx.blood(world, p.position + land + Vector3(0, 0.3, 0), 50)
		Fx.sfx("splat", p.position + land, 0.0, 0.8)
		Fx.shake(0.3))

@rpc("authority", "call_local", "reliable")
func _rpc_finish(id: int, place: int) -> void:
	if not finish_order.has(id):
		finish_order.append(id)
	var p: LabPlayer3D = players[id]
	p.bounds = AABB(Vector3(-WALL_X - 3.2, -5.0, FINISH_Z - 3.2), Vector3((WALL_X + 3.2) * 2.0, 20.0, 4.4))
	Fx.sfx("win", p.position, -6.0)
	if p.is_local_human():
		_rpc_big_local("EXIT #%d" % place, "8fe36a", 1.4)

func _rpc_big_local(text: String, hex: String, hold: float) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", Color(hex))
	_big.modulate.a = 1.0
	if hold > 0.0:
		var tw := create_tween()
		tw.tween_interval(hold)
		tw.tween_property(_big, "modulate:a", 0.0, 0.4)

@rpc("authority", "call_local", "reliable")
func _rpc_big(text: String, hex: String, hold: float) -> void:
	_rpc_big_local(text, hex, hold)

@rpc("authority", "call_local", "reliable")
func _rpc_start() -> void:
	st = St.RUN
	clock = 0.0
	for id in players:
		var p: LabPlayer3D = players[id]
		if p.is_local_human():
			p.input_enabled = true
	_rpc_big_local("RUN!", "8fe36a", 0.7)
	Fx.sfx("beep", null, -4.0, 1.4)
	var th := create_tween()
	th.tween_interval(5.0)
	th.tween_property(_hint, "modulate:a", 0.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_sync(time_left: float) -> void:
	_timer_label.text = "%d s" % int(ceil(time_left))

@rpc("authority", "call_local", "reliable")
func _rpc_end(timeout: bool) -> void:
	st = St.DONE
	for id in players:
		players[id].input_enabled = false
	_rpc_big_local("TIME!" if timeout else "LINE CLEAR", "e2c84b", 0.0)
	Fx.sfx("buzzer", null, -6.0, 1.3)

func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	for n in ["3", "2", "1"]:
		_rpc_big.rpc(n, "e8e2c8", 0.0)
		Fx.sfx("click")
		await get_tree().create_timer(0.8).timeout
	_rpc_start.rpc()
	while clock < TIME_LIMIT and not _runners().is_empty():
		await get_tree().process_frame
	_rpc_end.rpc(clock >= TIME_LIMIT)
	await get_tree().create_timer(2.4).timeout
	if not _ended:
		_ended = true
		finished.emit(_placement())

func _placement() -> Array:
	var out: Array = finish_order.duplicate()
	var living: Array = players.keys().filter(func(id): return not out.has(id) and not dead_order.has(id))
	living.sort_custom(func(a, b): return players[a].position.z < players[b].position.z)
	out.append_array(living)
	for i in range(dead_order.size() - 1, -1, -1):
		if not out.has(dead_order[i]):
			out.append(dead_order[i])
	return out

func _bot_brain(delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	if st != St.RUN or clock < float(_stun_until[id]):
		return Vector3.ZERO
	var b: Dictionary = _bot[id]
	if finish_order.has(id):
		var door := Vector3(signf(p.position.x + 0.01) * (WALL_X + 1.8), 0.0, FINISH_Z - 1.0)
		var to := door - p.position
		to.y = 0.0
		return to.normalized() if to.length() > 0.4 else Vector3.ZERO
	b.think = float(b.think) - delta
	var cur := _lane_of(p.position.x)
	var z := p.position.z
	if float(b.think) <= 0.0:
		b.think = randf_range(0.12, 0.22)
		var react: float = float(b.react)
		if randf() < float(b.greed):
			react += randf_range(0.6, 1.3)
		var target: int = int(b.lane)
		var eta_t := _lane_eta(target, z, react)
		if eta_t < 1.9:
			var best := target
			var best_score := -INF
			for l in LANES:
				var e := _lane_eta(l, z, react)
				var score: float = minf(e, 6.0) - absf(float(l - cur)) * 0.9
				if score > best_score:
					best_score = score
					best = l
			target = best
		elif randf() < 0.04:
			var nl := clampi(cur + (1 if randf() < 0.5 else -1), 0, LANES - 1)
			if _lane_eta(nl, z, react) > 3.0:
				target = nl
		b.lane = target
		if randf() < float(b.aggro) * 0.35:
			for o in _runners():
				if o == id or players[o].position.distance_to(p.position) > SHOVE_RANGE * 0.9:
					continue
				var push_dir: int = 1 if players[o].position.x > p.position.x else -1
				var into := clampi(_lane_of(players[o].position.x) + push_dir, 0, LANES - 1)
				if _lane_eta(into, players[o].position.z, 0.0) < 2.5 or randf() < 0.4:
					_try_shove(id)
				break
	var tx: float = _lane_x(int(b.lane)) + float(b.wobble)
	var dx := tx - p.position.x
	var side := clampf(dx * 1.6, -1.0, 1.0)
	var fwd := -1.0
	if absf(dx) > 0.6:
		fwd = -0.45
	if _lane_eta(cur, z, float(b.react)) < 0.25 and absf(dx) > 0.3:
		fwd = -0.15
	return Vector3(side, 0.0, fwd).normalized()
