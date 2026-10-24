extends ArenaMinigame3D
## Forklift Certified: every subject drives a forklift through a grim warehouse.
## Drive the forks under a pallet and lift to pick it up, then haul it into your
## coloured bay to score. Ram a rival carrying a load to make them drop it.
## Take turns too fast with a load up and the forklift tips and blows; drive off
## the loading dock edge and you crash into the pit. Most deliveries in 50 s
## wins; the dead place last.

const TIME_LIMIT: float = 50.0
const AW: float = 30.0
const AD: float = 22.0
const EDGE_X: float = 30.0
const PIT_Y: float = -4.2
const PIT_FAR: float = 38.5
const ROOF_Y: float = 9.5
const MAX_V: float = 6.2
const REV_V: float = 3.2
const ACCEL: float = 5.5
const BRAKE: float = 10.0
const DRAG: float = 2.4
const TURN: float = 2.0
const LIFT_RATE: float = 0.9
const CARRY_LIFT: float = 0.42
const CARRY_MIN: float = 0.26
const TIP_LIFT: float = 0.62
const TIP_LAT_HIGH: float = 5.0
const TIP_LAT: float = 9.6
const TIP_TIME: float = 0.32
const FORK_Y0: float = 0.09
const FORK_SPAN: float = 1.75
const FORK_REACH: float = 1.65
const PICK_R: float = 0.7
const RAM_V: float = 2.4
const RAM_CD: float = 1.0
const HIDE_LAYER: int = 4
const FALL: int = 0
const TIP: int = 1
const RACKS: Array[Rect2] = [Rect2(7.5, 7.4, 6.0, 1.2), Rect2(17.5, 7.4, 6.0, 1.2), Rect2(7.5, 13.4, 6.0, 1.2), Rect2(17.5, 13.4, 6.0, 1.2)]
const ZONES: Array = [[5.5, 1.5, 0, 5.5, 5.0, PI], [5.5, 20.5, 1, 5.5, 17.0, 0.0], [15.5, 1.5, 0, 15.5, 5.0, PI], [15.5, 20.5, 1, 15.5, 17.0, 0.0],
	[25.5, 1.5, 0, 25.5, 5.0, PI], [25.5, 20.5, 1, 25.5, 17.0, 0.0], [1.5, 11.0, 2, 4.8, 11.0, -PI * 0.5], [10.5, 20.5, 1, 10.5, 17.2, -PI * 0.5]]
const SPOTS: Array = [[4.5, 11.0, 90], [9.5, 11.0, 90], [12.8, 11.0, 90], [18.2, 11.0, 90], [22.0, 11.0, 90], [26.5, 11.0, 0],
	[15.5, 5.6, 0], [15.5, 16.4, 0], [10.5, 5.0, 90], [20.5, 5.0, 90], [10.5, 17.0, 90], [20.5, 17.0, 90], [27.0, 7.5, 90], [27.0, 14.5, 90], [24.5, 11.0, 0]]

enum St { COUNTDOWN, RUN, DONE }

static var _paint_cache: StandardMaterial3D
static var _hazard_cache: StandardMaterial3D

var st: St = St.COUNTDOWN
var clock: float = 0.0
var T: Dictionary = {}
var P: Array = []
var order: Array = []
var deliveries: Dictionary = {}
var dead_order: Array = []
var zone_of: Dictionary = {}
var _bot: Dictionary = {}
var _ram_cd: Dictionary = {}
var _last_deliver: Dictionary = {}
var _zone_stacks: Dictionary = {}
var _zone_labels: Dictionary = {}
var _auto: bool = false
var _ended: bool = false
var _sync_n: int = 0
var _pal_sync_t: float = 0.0
var _pal_dirty: bool = false
var _tick_t: float = 0.0
var _space_down: bool = false
var _cam_cockpit: bool = false
var _cam_switch_t: float = 0.0
var _dead_cam_t: float = -1.0
var _bob_t: float = 0.0
var _jolt: float = 0.0
var _overview_xf: Transform3D
var _beacon_t: float = 0.0
var _local_lift_target: float = 0.0

var _hud_time: Label
var _hud_board: RichTextLabel
var _hud_hint: Label
var _hud_status: Label
var _hud_warn: Label
var _hud_big: Label
var _lift_bar: ProgressBar
var _lift_fill: StyleBoxFlat

func begin() -> void:
	setup_arena(false)
	_auto = get_tree().root.has_node("AutoTest")
	_tune_light()
	_build_warehouse()
	_build_pit()
	_build_racks()
	_build_dressing()
	var i := 0
	for id in NetworkManager.players:
		order.append(id)
		zone_of[id] = i % ZONES.size()
		deliveries[id] = 0
		_ram_cd[id] = 0.0
		_last_deliver[id] = 0.0
		_build_zone(id, i % ZONES.size())
		var z: Array = ZONES[i % ZONES.size()]
		T[id] = _build_truck(id, Vector3(z[3], 0.0, z[4]), z[5])
		if _ai(id):
			_bot_init(id)
		i += 1
	_spawn_initial_pallets()
	camera.fov = 50.0
	camera.position = Vector3(20.0, 18.0, 29.5)
	camera.look_at(Vector3(19.0, 0.0, 10.4), Vector3.UP)
	_overview_xf = camera.global_transform
	camera.cull_mask = 0xFFFFF & ~HIDE_LAYER
	_cam_cockpit = not local_truck().is_empty() and not _auto
	_apply_cam_mode()
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _ai(id: int) -> bool:
	if not NetworkManager.players.has(id):
		return false
	return bool(NetworkManager.players[id].is_bot) or (_auto and id == multiplayer.get_unique_id())

func _is_auth(id: int) -> bool:
	if not NetworkManager.players.has(id):
		return false
	if bool(NetworkManager.players[id].is_bot):
		return multiplayer.is_server()
	return id == multiplayer.get_unique_id()

func local_truck() -> Dictionary:
	return T.get(multiplayer.get_unique_id(), {})

func _fwd(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func _axis(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))

func _fork_point(t: Dictionary) -> Vector3:
	var n: CharacterBody3D = t.node
	return n.position + _fwd(float(t.yaw)) * FORK_REACH

func _zone_rect(id: int) -> Rect2:
	var z: Array = ZONES[zone_of[id]]
	var s := Vector2(3.2, 2.6) if int(z[2]) < 2 else Vector2(2.6, 3.2)
	return Rect2(Vector2(z[0], z[1]) - s * 0.5, s)


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

func _local(tex: String, tile: float, tint: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = mat(tex, tile, tint).duplicate()
	m.uv1_world_triplanar = false
	return m

func _paint() -> StandardMaterial3D:
	if _paint_cache:
		return _paint_cache
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var chip := FastNoiseLite.new()
	chip.frequency = 0.05
	chip.seed = 7
	chip.fractal_octaves = 4
	var dirt := FastNoiseLite.new()
	dirt.frequency = 0.014
	dirt.seed = 19
	for y in n:
		for x in n:
			var c := chip.get_noise_2d(x, y)
			var g := 0.8 + dirt.get_noise_2d(x, y) * 0.38 + randf_range(-0.04, 0.04)
			var col := Color(0.88, 0.62, 0.06)
			if c > 0.36:
				col = Color(0.17, 0.16, 0.15)
			elif c > 0.28:
				col = Color(0.4, 0.22, 0.08)
			img.set_pixel(x, y, Color(col.r * g, col.g * g, col.b * g))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.6
	m.metallic = 0.15
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.9
	if ResourceLoader.exists(PH_TEX + "rusty_metal/nor.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(PH_TEX + "rusty_metal/nor.jpg")
		m.normal_scale = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_paint_cache = m
	return m

func _hazard() -> StandardMaterial3D:
	if _hazard_cache:
		return _hazard_cache
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.045
	noise.seed = 3
	for y in n:
		for x in n:
			var stripe := int(floor(float(x + y) / 16.0)) % 2
			var g := 0.7 + noise.get_noise_2d(x, y) * 0.42
			var c := Color(0.82, 0.6, 0.08) if stripe == 0 else Color(0.06, 0.06, 0.05)
			img.set_pixel(x, y, Color(c.r * g, c.g * g, c.b * g))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.9
	_hazard_cache = m
	return m

func _cyl(r: float, h: float, m: Material, pos: Vector3, rot: Vector3, parent: Node, segs: int = 14) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = m
	mi.rotation_degrees = rot
	mi.position = pos
	parent.add_child(mi)
	return mi

func _solid(center: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	world.add_child(sb)
	sb.position = center

func _hide_from_overview(n: Node) -> void:
	if n is VisualInstance3D and not n is Light3D:
		(n as VisualInstance3D).layers = HIDE_LAYER
	for c in n.get_children():
		_hide_from_overview(c)


func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.22
			n.shadow_enabled = false
	env.ambient_light_color = Color(0.55, 0.55, 0.5)
	env.ambient_light_energy = 0.55
	env.tonemap_exposure = 1.05
	env.fog_density = 0.014
	env.fog_light_color = Color(0.12, 0.11, 0.09)
	env.glow_intensity = 0.7
	env.background_color = Color("070706")

func _build_warehouse() -> void:
	var r := Node3D.new()
	r.name = "Warehouse"
	world.add_child(r)
	box(Vector3(EDGE_X + 1.0, 4.4, AD + 2.0), Vector3(EDGE_X * 0.5 - 0.5, -2.2, AD * 0.5), mat("concrete_floor_worn_001", 0.28, Color(0.62, 0.58, 0.52)), r)
	_solid(Vector3(EDGE_X * 0.5 - 0.5, -2.2, AD * 0.5), Vector3(EDGE_X + 1.0, 4.4, AD + 2.0))
	box(Vector3(EDGE_X - 0.4, 0.01, AD - 0.4), Vector3(EDGE_X * 0.5, 0.004, AD * 0.5), mat("hangar_concrete_floor", 0.22, Color(0.62, 0.6, 0.55)), r)
	var wall_h := ROOF_Y - PIT_Y
	var wall_y := (ROOF_Y + PIT_Y) * 0.5
	var long := PIT_FAR + 1.2
	var brick := mat("factory_brick", 0.4, Color(0.62, 0.56, 0.5))
	var band := mat("dirty_concrete", 0.45, Color(0.5, 0.48, 0.42))
	var north := Node3D.new()
	r.add_child(north)
	box(Vector3(long, wall_h, 0.6), Vector3(long * 0.5 - 0.6, wall_y, -0.3), brick, north)
	box(Vector3(long, 1.3, 0.12), Vector3(long * 0.5 - 0.6, 0.65, 0.02), band, north)
	_solid(Vector3(long * 0.5 - 0.6, wall_y, -0.3), Vector3(long, wall_h, 0.6))
	var south := Node3D.new()
	r.add_child(south)
	box(Vector3(long, wall_h, 0.6), Vector3(long * 0.5 - 0.6, wall_y, AD + 0.3), brick, south)
	box(Vector3(long, 1.3, 0.12), Vector3(long * 0.5 - 0.6, 0.65, AD - 0.02), band, south)
	_solid(Vector3(long * 0.5 - 0.6, wall_y, AD + 0.3), Vector3(long, wall_h, 0.6))
	box(Vector3(0.6, wall_h, AD + 1.2), Vector3(-0.3, wall_y, AD * 0.5), brick, r)
	box(Vector3(0.12, 1.3, AD), Vector3(0.02, 0.65, AD * 0.5), band, r)
	_solid(Vector3(-0.3, wall_y, AD * 0.5), Vector3(0.6, wall_h, AD + 1.2))
	box(Vector3(0.6, wall_h, AD + 1.2), Vector3(PIT_FAR + 0.3, wall_y, AD * 0.5), brick, r)
	var roof := Node3D.new()
	r.add_child(roof)
	box(Vector3(long, 0.3, AD + 1.2), Vector3(long * 0.5 - 0.6, ROOF_Y + 0.15, AD * 0.5), mat("corrugated_iron", 0.5, Color(0.3, 0.3, 0.28)), roof)
	var steel := mat("rusty_metal_02", 1.0, Color(0.5, 0.48, 0.44))
	var x := 2.5
	while x < PIT_FAR:
		box(Vector3(0.3, 0.6, AD), Vector3(x, ROOF_Y - 0.3, AD * 0.5), steel, roof)
		x += 5.0
	for z in [3.0, 11.0, 19.0]:
		box(Vector3(long, 0.25, 0.2), Vector3(long * 0.5 - 0.6, ROOF_Y - 0.75, z), steel, roof)
	_hide_from_overview(south)
	_hide_from_overview(roof)
	var pipe_mat := mat("rusty_metal_02", 1.5)
	for y in [5.4, 5.8]:
		_cyl(0.16, long, pipe_mat, Vector3(long * 0.5 - 0.6, y, 0.4), Vector3(0, 0, 90), north)
	_cyl(0.12, AD, pipe_mat, Vector3(0.35, 5.0, AD * 0.5), Vector3(90, 0, 0), r)
	for dx in [10.5, 20.5]:
		var door := prop("rollershutter_door", Vector3(dx - 1.3, 0.0, 0.18), 0.0, 1.3, north)
		if door:
			box(Vector3(4.3, 0.25, 0.3), Vector3(dx, 3.25, 0.15), mat("rusty_metal", 1.0), north)
		box(Vector3(4.2, 0.02, 1.2), Vector3(dx, 0.012, 0.9), _hazard(), north)
	prop("power_box_01", Vector3(8.0, 2.2, 0.25), 0.0, 1.6, north)
	prop("fire_alarm", Vector3(13.4, 2.4, 0.2), 0.0, 1.6, north)
	prop("industrial_caged_sconce", Vector3(3.0, 3.2, 0.2), 0.0, 1.6, north)
	prop("industrial_caged_sconce", Vector3(28.0, 3.2, 0.2), 0.0, 1.6, north)
	prop("security_camera_01", Vector3(29.4, 5.4, 0.5), -135.0, 1.6, north)
	prop("industrial_caged_sconce", Vector3(0.2, 3.2, 6.0), 90.0, 1.6, r)
	prop("industrial_caged_sconce", Vector3(0.2, 3.2, 16.0), 90.0, 1.6, r)
	prop("power_box_01", Vector3(0.25, 2.0, 3.0), 90.0, 1.6, r)
	for p in [Vector3(3.0, 3.0, 0.7), Vector3(28.0, 3.0, 0.7), Vector3(0.7, 3.0, 6.0), Vector3(0.7, 3.0, 16.0)]:
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.75, 0.45)
		o.light_energy = 1.4
		o.omni_range = 6.0
		r.add_child(o)
		o.position = p
	for i in 8:
		var lp: Vector3 = [Vector3(5.0, 7.4, 5.0), Vector3(15.5, 7.4, 5.0), Vector3(25.5, 7.4, 5.0), Vector3(5.0, 7.4, 17.0),
			Vector3(15.5, 7.4, 17.0), Vector3(25.5, 7.4, 17.0), Vector3(11.0, 7.4, 11.0), Vector3(20.0, 7.4, 11.0)][i]
		var sp := lamp(lp, 20.0, Color(1.0, 0.8, 0.55), r)
		sp.spot_angle = 70.0
		sp.position.y = lp.y - 1.6
		sp.shadow_enabled = i >= 6 or i % 2 == 0
		var cable := box(Vector3(0.03, ROOF_Y - lp.y, 0.03), Vector3(lp.x, (ROOF_Y + lp.y) * 0.5, lp.z), _plain(Color(0.05, 0.05, 0.05), 0.6), r)
		cable.layers = HIDE_LAYER

func _build_pit() -> void:
	var pit := Node3D.new()
	pit.name = "Pit"
	world.add_child(pit)
	var w := PIT_FAR - EDGE_X
	box(Vector3(w, 0.2, AD + 1.0), Vector3(EDGE_X + w * 0.5, PIT_Y - 0.1, AD * 0.5), mat("damaged_concrete_floor", 0.4, Color(0.35, 0.33, 0.3)), pit)
	box(Vector3(0.14, 0.1, AD), Vector3(EDGE_X - 0.07, 0.01, AD * 0.5), mat("rusty_metal", 1.0, Color(0.7, 0.66, 0.6)), pit)
	box(Vector3(0.9, 0.02, AD), Vector3(EDGE_X - 0.55, 0.012, AD * 0.5), _hazard(), pit)
	var rubber := _plain(Color(0.04, 0.04, 0.04), 0.9)
	var z := 1.6
	while z < AD - 1.0:
		box(Vector3(0.22, 0.5, 0.6), Vector3(EDGE_X + 0.11, -0.55, z), rubber, pit)
		z += 3.2
	for zz in [4.0, 11.0, 18.0]:
		prop("rollershutter_door", Vector3(PIT_FAR - 0.2, PIT_Y, zz - 1.3), -90.0, 1.5, pit)
		box(Vector3(0.3, 0.3, 4.9), Vector3(PIT_FAR - 0.1, PIT_Y + 3.75, zz), mat("rusty_metal", 1.0), pit)
	for i in 12:
		var pm := _plain(Color(0.05, 0.05, 0.045, 0.6), 0.03, 0.3)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var pu := box(Vector3(randf_range(0.8, 2.4), 0.01, randf_range(0.8, 2.0)), Vector3(randf_range(EDGE_X + 0.8, PIT_FAR - 0.8), PIT_Y + 0.01, randf_range(1.0, AD - 1.0)), pm, pit)
		pu.rotation.y = randf() * PI
	var junk := [["old_tyre", 31.5, 3.0], ["old_tyre", 33.0, 15.0], ["barrel_03", 37.1, 1.2], ["barrel_03", 37.3, 8.0], ["trashbag", 31.0, 19.5],
		["cardboard_box_01", 32.0, 9.5], ["wooden_crate_01", 36.8, 13.5], ["metal_trash_can", 37.5, 20.6], ["cement_bag", 31.4, 6.6], ["concrete_road_barrier", 34.5, 11.0]]
	for j in junk:
		var d := prop(j[0], Vector3(j[1], PIT_Y, j[2]), randf() * 360.0, 1.2, pit)
		if d and j[0] == "old_tyre":
			d.rotation_degrees.x = 90.0
			d.position.y = PIT_Y + 0.1
	var red := OmniLight3D.new()
	red.light_color = Color(1.0, 0.3, 0.12)
	red.light_energy = 1.6
	red.omni_range = 9.0
	pit.add_child(red)
	red.position = Vector3(EDGE_X + 3.0, PIT_Y + 2.0, AD * 0.5)
	for zz in [3.0, 19.0]:
		var wl := OmniLight3D.new()
		wl.light_color = Color(1.0, 0.55, 0.25)
		wl.light_energy = 2.6
		wl.omni_range = 8.0
		pit.add_child(wl)
		wl.position = Vector3(PIT_FAR - 1.5, PIT_Y + 3.2, zz)
		prop("security_light", Vector3(PIT_FAR - 0.05, PIT_Y + 3.4, zz), -90.0, 1.4, pit)
	for zz in [5.0, 17.0]:
		var lab := Label3D.new()
		lab.text = "DOCK EDGE  ·  NO RAILING"
		lab.font_size = 120
		lab.pixel_size = 0.006
		lab.modulate = Color(0.85, 0.7, 0.2, 0.7)
		lab.outline_size = 0
		lab.shaded = true
		pit.add_child(lab)
		lab.position = Vector3(EDGE_X - 1.5, 0.02, zz)
		lab.rotation_degrees = Vector3(-90, 90, 0)

func _build_racks() -> void:
	var rk := Node3D.new()
	rk.name = "Racks"
	world.add_child(rk)
	var upright := mat("blue_metal_plate", 1.2, Color(0.42, 0.5, 0.62))
	var beam := mat("rusty_metal_02", 1.0, Color(1.0, 0.48, 0.2))
	var deck := mat("metal_grate_rusty", 1.4, Color(0.7, 0.66, 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for rect in RACKS:
		var x0 := rect.position.x
		var z0 := rect.position.y
		var dep := rect.size.y
		_solid(Vector3(rect.get_center().x, 2.8, rect.get_center().y), Vector3(rect.size.x, 5.6, dep))
		for ux in [x0 + 0.05, x0 + 3.0, x0 + rect.size.x - 0.05]:
			for uz in [z0 + 0.05, z0 + dep - 0.05]:
				box(Vector3(0.1, 5.6, 0.1), Vector3(ux, 2.8, uz), upright, rk)
			for by in [0.7, 2.1, 3.5, 4.9]:
				box(Vector3(0.05, 0.05, dep - 0.1), Vector3(ux, by, z0 + dep * 0.5), upright, rk)
			box(Vector3(0.2, 0.5, 0.2), Vector3(ux, 0.25, z0 - 0.05), _hazard(), rk)
			box(Vector3(0.2, 0.5, 0.2), Vector3(ux, 0.25, z0 + dep + 0.05), _hazard(), rk)
		box(Vector3(rect.size.x + 0.5, 0.02, 0.25), Vector3(rect.get_center().x, 0.01, z0 - 0.3), _hazard(), rk)
		box(Vector3(rect.size.x + 0.5, 0.02, 0.25), Vector3(rect.get_center().x, 0.01, z0 + dep + 0.3), _hazard(), rk)
		for bay in 2:
			var cx := x0 + 1.5 + float(bay) * 3.0
			for lvl in 4:
				var ly: float = [0.0, 1.85, 3.65, 5.45][lvl]
				if lvl > 0:
					for bz in [z0 + 0.08, z0 + dep - 0.08]:
						box(Vector3(2.95, 0.14, 0.07), Vector3(cx, ly, bz), beam, rk)
					box(Vector3(2.9, 0.02, dep - 0.15), Vector3(cx, ly + 0.08, z0 + dep * 0.5), deck, rk)
				if lvl == 3:
					continue
				for side in [-0.72, 0.72]:
					if rng.randf() < 0.72:
						var pal := _make_pallet([0, 2, 4, 0][rng.randi() % 4], rng)
						rk.add_child(pal)
						pal.position = Vector3(cx + side, ly + (0.09 if lvl > 0 else 0.0), z0 + dep * 0.5)
						pal.rotation.y = rng.randf_range(-0.05, 0.05)
					elif lvl > 0 and rng.randf() < 0.5:
						prop(["barrel_03", "cardboard_box_01", "plastic_crate_01"][rng.randi() % 3], Vector3(cx + side, ly + 0.09, z0 + dep * 0.5), rng.randf() * 360.0, 1.2, rk)

func _build_dressing() -> void:
	var d := Node3D.new()
	d.name = "Dressing"
	world.add_child(d)
	var clutter := [["steel_frame_shelves_03", 1.0, 0.5, 4.8, 90], ["steel_frame_shelves_03", 1.0, 0.5, 17.2, 90], ["worn_metal_rack", 0.9, 0.45, 1.2, 90],
		["worn_metal_rack", 0.9, 0.45, 20.8, 90], ["barrel_03", 1.15, 8.0, 0.6, 0], ["barrel_03", 1.15, 8.7, 0.7, 30], ["cement_bag", 1.2, 13.0, 0.6, 20],
		["wooden_crate_02", 1.15, 18.2, 0.8, 90], ["barrel_03", 1.15, 23.0, 0.6, 0], ["propane_tank", 1.15, 28.8, 0.6, 0], ["barrel_03", 1.15, 29.2, 1.4, 50],
		["metal_trash_can", 1.15, 8.0, 21.4, 0], ["hand_truck", 1.15, 13.2, 21.4, 180], ["WetFloorSign_01", 1.3, 18.5, 21.0, 30], ["steel_frame_shelves_02", 1.3, 20.6, 21.6, 0],
		["old_military_crate", 1.0, 22.8, 21.3, 0], ["barrel_03", 1.15, 28.8, 21.4, 0], ["plastic_crate_01", 1.6, 29.3, 20.6, 15], ["trashbag", 1.15, 0.8, 8.0, 0],
		["cardboard_box_01", 1.2, 0.8, 14.2, 20], ["portable_generator", 1.15, 0.9, 19.0, 90], ["metal_tool_chest", 1.15, 0.7, 3.2, 90]]
	for c in clutter:
		var p := Vector3(c[2], 0.0, c[3])
		prop(c[0], p, c[4], c[1], d)
		_solid(p + Vector3(0, 0.8, 0), Vector3(1.0, 1.6, 1.0))
	if NetworkManager.players.size() < 7:
		prop("old_military_crate", Vector3(0.9, 0.0, 11.0), 90.0, 1.0, d)
	var yel := _plain(Color(0.72, 0.56, 0.1), 0.8)
	for lz in [3.2, 18.8]:
		box(Vector3(EDGE_X - 4.0, 0.012, 0.12), Vector3(EDGE_X * 0.5 - 0.5, 0.008, lz), yel, d)
	for lx in [3.4, 24.6]:
		box(Vector3(0.12, 0.012, AD - 7.0), Vector3(lx, 0.008, AD * 0.5), yel, d)
	_grime(d)
	for i in 14:
		var pm := _plain(Color(0.06, 0.055, 0.05, 0.5), 0.02, 0.3)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var pu := box(Vector3(randf_range(0.7, 2.0), 0.006, randf_range(0.6, 1.6)), Vector3(randf_range(2.0, EDGE_X - 2.0), 0.014, randf_range(3.0, AD - 3.0)), pm, d)
		pu.rotation.y = randf() * PI

func _grime(parent: Node) -> void:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.seed = 11
	for y in n:
		for x in n:
			var dx := (x - n * 0.5) / (n * 0.5)
			var dy := (y - n * 0.5) / (n * 0.5)
			var v := 1.0 - sqrt(dx * dx + dy * dy) + noise.get_noise_2d(x, y) * 0.6
			img.set_pixel(x, y, Color(1, 1, 1, clampf((v - 0.25) * 2.0, 0.0, 0.9)))
	var tex := ImageTexture.create_from_image(img)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 26:
		var d := Decal.new()
		d.texture_albedo = tex
		var sz := rng.randf_range(1.2, 3.4)
		d.size = Vector3(sz, 1.0, sz * rng.randf_range(0.5, 1.0))
		d.modulate = Color(0.06, 0.05, 0.04) if i % 3 != 0 else Color(0.22, 0.15, 0.07)
		d.rotation.y = rng.randf() * TAU
		d.cull_mask = 1
		parent.add_child(d)
		d.position = Vector3(rng.randf_range(1.0, EDGE_X - 1.0), 0.1, rng.randf_range(1.0, AD - 1.0))

func _build_zone(id: int, zi: int) -> void:
	var z: Array = ZONES[zi]
	var col: Color = NetworkManager.players[id].color
	var r := _zone_rect(id)
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	var paint := _plain(col.darkened(0.25), 0.8)
	paint.emission_enabled = true
	paint.emission = col
	paint.emission_energy_multiplier = 0.18
	box(Vector3(r.size.x, 0.012, r.size.y), c + Vector3(0, 0.01, 0), paint)
	var hz := _hazard()
	box(Vector3(r.size.x + 0.4, 0.016, 0.2), c + Vector3(0, 0.012, -r.size.y * 0.5 - 0.1), hz)
	box(Vector3(r.size.x + 0.4, 0.016, 0.2), c + Vector3(0, 0.012, r.size.y * 0.5 + 0.1), hz)
	box(Vector3(0.2, 0.016, r.size.y), c + Vector3(-r.size.x * 0.5 - 0.1, 0.012, 0), hz)
	box(Vector3(0.2, 0.016, r.size.y), c + Vector3(r.size.x * 0.5 + 0.1, 0.012, 0), hz)
	var lab := Label3D.new()
	lab.text = "%s\n0" % NetworkManager.players[id].name
	lab.font_size = 96
	lab.pixel_size = 0.0055
	lab.modulate = col.lightened(0.3)
	lab.outline_size = 18
	lab.outline_modulate = Color(0, 0, 0, 0.8)
	world.add_child(lab)
	lab.position = c + Vector3(0, 0.03, 0)
	var face: float = [0.0, 180.0, -90.0][int(z[2])]
	lab.rotation_degrees = Vector3(-90, face, 0)
	_zone_labels[id] = lab
	var o := OmniLight3D.new()
	o.light_color = col
	o.light_energy = 1.0
	o.omni_range = 3.2
	world.add_child(o)
	o.position = c + Vector3(0, 1.4, 0)
	_zone_stacks[id] = 0


func _make_pallet(kind: int, rng: RandomNumberGenerator) -> Node3D:
	var p := Node3D.new()
	var wood := mat("worn_planks", 1.2, Color(0.78, 0.66, 0.52))
	for sx in [-0.55, 0.0, 0.55]:
		box(Vector3(0.1, 0.08, 1.0), Vector3(sx, 0.06, 0.0), wood, p)
	for sz in [-0.44, -0.22, 0.0, 0.22, 0.44]:
		box(Vector3(1.2, 0.024, 0.12), Vector3(0.0, 0.112, sz), wood, p)
	for sz in [-0.44, 0.0, 0.44]:
		box(Vector3(1.2, 0.02, 0.12), Vector3(0.0, 0.01, sz), wood, p)
	var top := 0.124
	match kind:
		0:
			for lv in 2:
				for sz in [-0.21, 0.21]:
					prop("wooden_crate_01", Vector3(0.0, top + lv * 0.35, sz), rng.randf_range(-4.0, 4.0), 1.0, p)
		1:
			for lv in 2:
				for sx in [-0.39, 0.0, 0.39]:
					for sz in [-0.26, 0.26]:
						prop("cardboard_box_01", Vector3(sx, top + lv * 0.34, sz), rng.randf_range(-6.0, 6.0), 1.0, p)
		2:
			for lv in 4:
				for sx in [-0.25, 0.25]:
					prop("cement_bag", Vector3(sx, top + lv * 0.17, 0.0), (90.0 if lv % 2 == 1 else 0.0) + rng.randf_range(-6.0, 6.0), 1.0, p)
		3:
			for lv in 3:
				for sx in [-0.4, 0.0, 0.4]:
					for sz in [-0.22, 0.22]:
						prop("plastic_crate_01", Vector3(sx, top + lv * 0.26, sz), 0.0, 1.0, p)
		_:
			for sx in [-0.29, 0.29]:
				prop("wooden_crate_02", Vector3(sx, top, 0.0), rng.randf_range(-3.0, 3.0), 1.0, p)
			prop("wooden_crate_02", Vector3(0.0, top + 0.46, 0.0), 90.0 + rng.randf_range(-5.0, 5.0), 1.0, p)
	return p

func _spawn_initial_pallets() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var count := mini(order.size() + 3, 11)
	var spots: Array = []
	for i in SPOTS.size():
		spots.append(i)
	var picked: Array = []
	for si in spots:
		var s: Array = SPOTS[si]
		var ok := true
		for id in T:
			var n: CharacterBody3D = T[id].node
			if Vector2(s[0], s[1]).distance_to(Vector2(n.position.x, n.position.z)) < 3.2:
				ok = false
		if ok:
			picked.append(si)
	var order_rng: Array = picked.duplicate()
	for i in order_rng.size():
		var j := rng.randi_range(i, order_rng.size() - 1)
		var tmp: int = order_rng[i]
		order_rng[i] = order_rng[j]
		order_rng[j] = tmp
	for k in mini(count, order_rng.size()):
		var s: Array = SPOTS[order_rng[k]]
		var node := _make_pallet(rng.randi() % 5, rng)
		world.add_child(node)
		var yaw := deg_to_rad(float(s[2]) + rng.randf_range(-8.0, 8.0))
		node.position = Vector3(s[0], 0.0, s[1])
		node.rotation.y = yaw
		P.append({"node": node, "pos": node.position, "yaw": yaw, "carrier": -1, "spot": order_rng[k]})

func _free_spot(avoid: int) -> Array:
	var best: Array = []
	var best_s := -INF
	for si in SPOTS.size():
		var s: Array = SPOTS[si]
		var sp := Vector3(s[0], 0.0, s[1])
		var near := INF
		for pd in P:
			if int(pd.carrier) < 0 and si != avoid:
				near = minf(near, sp.distance_to(pd.pos))
		for id in T:
			var n: CharacterBody3D = T[id].node
			near = minf(near, sp.distance_to(n.position) + 0.5)
		var score := minf(near, 6.0) + randf() * 2.0
		if si != avoid and score > best_s:
			best_s = score
			best = [sp, deg_to_rad(float(s[2]) + randf_range(-8.0, 8.0)), si]
	return best


func _build_truck(id: int, pos: Vector3, yaw: float) -> Dictionary:
	var info: Dictionary = NetworkManager.players[id]
	var col: Color = info.color
	var n := CharacterBody3D.new()
	n.name = "Truck_%d" % id
	n.collision_layer = 2
	n.collision_mask = 3
	n.set_meta("fid", id)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.24, 1.4, 3.5)
	cs.shape = sh
	cs.position = Vector3(0, 0.75, -0.45)
	n.add_child(cs)
	world.add_child(n)
	n.position = pos
	n.rotation.y = yaw
	var paint := _paint()
	var steel := _local("rusty_metal_02", 3.0, Color(0.3, 0.29, 0.28))
	var black := _plain(Color(0.05, 0.05, 0.05), 0.75, 0.2)
	var rubber := _local("rubber_tiles", 3.0, Color(0.16, 0.16, 0.16))
	var colm := _plain(col, 0.5)
	colm.emission_enabled = true
	colm.emission = col
	colm.emission_energy_multiplier = 0.35
	box(Vector3(1.16, 0.42, 1.9), Vector3(0, 0.42, 0.15), paint, n)
	box(Vector3(1.02, 0.06, 0.62), Vector3(0, 0.66, -0.3), _local("metal_grate_rusty", 2.0, Color(0.6, 0.58, 0.55)), n)
	box(Vector3(1.0, 0.34, 0.72), Vector3(0, 0.8, 0.45), paint, n)
	box(Vector3(0.52, 0.12, 0.46), Vector3(0, 1.03, 0.38), black, n)
	box(Vector3(0.52, 0.52, 0.1), Vector3(0, 1.32, 0.64), black, n)
	box(Vector3(1.24, 0.78, 0.46), Vector3(0, 0.74, 1.06), paint, n)
	box(Vector3(1.0, 0.24, 0.02), Vector3(0, 0.62, 1.295), _hazard(), n)
	box(Vector3(0.02, 0.16, 1.5), Vector3(0.59, 0.52, 0.15), colm, n)
	box(Vector3(0.02, 0.16, 1.5), Vector3(-0.59, 0.52, 0.15), colm, n)
	box(Vector3(1.0, 0.24, 0.26), Vector3(0, 0.75, -0.7), paint, n)
	box(Vector3(0.5, 0.08, 0.2), Vector3(0, 0.9, -0.64), black, n)
	_cyl(0.03, 0.5, black, Vector3(0, 1.08, -0.47), Vector3(-38, 0, 0), n, 8)
	var wheel := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.12
	tm.outer_radius = 0.155
	tm.rings = 16
	tm.ring_segments = 8
	wheel.mesh = tm
	wheel.material_override = black
	n.add_child(wheel)
	wheel.position = Vector3(0, 1.28, -0.34)
	wheel.rotation_degrees.x = -50.0
	_cyl(0.025, 0.24, black, Vector3(0, 1.28, -0.34), Vector3(40, 0, 90), n, 6)
	box(Vector3(0.05, 0.12, 0.05), Vector3(0.2, 1.37, -0.27), _plain(Color(0.1, 0.1, 0.1), 0.6), n)
	for sx in [-0.52, 0.52]:
		box(Vector3(0.07, 1.4, 0.07), Vector3(sx, 1.52, -0.62), black, n)
		box(Vector3(0.07, 1.1, 0.07), Vector3(sx, 1.67, 0.82), black, n)
		box(Vector3(0.07, 0.06, 1.5), Vector3(sx, 2.22, 0.1), black, n)
	for gz in [-0.62, 0.82]:
		box(Vector3(1.12, 0.06, 0.08), Vector3(0, 2.22, gz), black, n)
	for gx in [-0.33, -0.11, 0.11, 0.33]:
		box(Vector3(0.04, 0.04, 1.44), Vector3(gx, 2.23, 0.1), black, n)
	box(Vector3(1.14, 0.04, 0.16), Vector3(0, 2.27, 0.82), colm, n)
	_cyl(0.045, 0.7, steel, Vector3(0.42, 1.55, 0.98), Vector3.ZERO, n, 8)
	_cyl(0.008, 1.1, black, Vector3(-0.5, 2.8, 0.85), Vector3.ZERO, n, 4)
	box(Vector3(0.02, 0.2, 0.3), Vector3(-0.5, 3.25, 0.99), colm, n)
	for sx in [-0.38, 0.38]:
		box(Vector3(0.09, 2.3, 0.13), Vector3(sx, 1.24, -0.98), steel, n)
		_cyl(0.04, 0.9, steel, Vector3(sx * 1.2, 0.85, -0.78), Vector3(-60, 0, 0), n, 8)
	box(Vector3(0.86, 0.1, 0.12), Vector3(0, 2.36, -0.98), steel, n)
	box(Vector3(0.86, 0.12, 0.12), Vector3(0, 0.22, -0.98), steel, n)
	for sx in [-0.15, 0.15]:
		box(Vector3(0.03, 2.05, 0.02), Vector3(sx, 1.3, -0.96), black, n)
	var carriage := Node3D.new()
	n.add_child(carriage)
	carriage.position = Vector3(0, FORK_Y0, 0)
	var fsteel := _local("rusty_metal_02", 2.0, Color(0.42, 0.4, 0.38))
	box(Vector3(1.0, 0.3, 0.06), Vector3(0, 0.15, -1.08), fsteel, carriage)
	for sx in [-0.46, 0.46]:
		box(Vector3(0.05, 0.95, 0.05), Vector3(sx, 0.5, -1.08), black, carriage)
	for by in [0.55, 0.95]:
		box(Vector3(0.97, 0.05, 0.05), Vector3(0, by, -1.08), black, carriage)
	for sx in [-0.23, 0.0, 0.23]:
		box(Vector3(0.03, 0.68, 0.03), Vector3(sx, 0.62, -1.08), black, carriage)
	for sx in [-0.3, 0.3]:
		box(Vector3(0.11, 0.55, 0.05), Vector3(sx, 0.27, -1.13), fsteel, carriage)
		box(Vector3(0.11, 0.045, 1.15), Vector3(sx, -0.0225, -1.7), fsteel, carriage)
	var spins: Array = []
	var pivots: Array = []
	for w in [[-0.5, -0.55, 0.32, false], [0.5, -0.55, 0.32, false], [-0.5, 0.88, 0.26, true], [0.5, 0.88, 0.26, true]]:
		var pv := Node3D.new()
		n.add_child(pv)
		pv.position = Vector3(w[0], w[2], w[1])
		var sp := Node3D.new()
		pv.add_child(sp)
		var rr: float = w[2]
		_cyl(rr, 0.24, rubber, Vector3.ZERO, Vector3(0, 0, 90), sp, 18)
		_cyl(rr * 0.55, 0.25, paint, Vector3.ZERO, Vector3(0, 0, 90), sp, 10)
		for k in 4:
			var a := float(k) * TAU / 4.0
			box(Vector3(0.27, 0.035, 0.035), Vector3(0, cos(a) * rr * 0.32, sin(a) * rr * 0.32), black, sp)
		spins.append([sp, rr])
		if w[3]:
			pivots.append(pv)
	var lamp_m := _glow(Color(1.0, 0.92, 0.75), 6.0)
	for sx in [-0.45, 0.45]:
		box(Vector3(0.13, 0.1, 0.03), Vector3(sx, 2.12, -0.7), lamp_m, n)
		box(Vector3(0.16, 0.13, 0.1), Vector3(sx, 2.12, -0.64), black, n)
		box(Vector3(0.1, 0.07, 0.03), Vector3(sx, 0.95, 1.29), _glow(Color(1.0, 0.08, 0.04), 3.0), n)
	var head := SpotLight3D.new()
	head.light_color = Color(1.0, 0.92, 0.78)
	head.light_energy = 5.0
	head.spot_range = 12.0
	head.spot_angle = 34.0
	head.spot_attenuation = 0.8
	n.add_child(head)
	head.position = Vector3(0, 2.05, -0.75)
	head.rotation_degrees.x = -16.0
	var beacon := Node3D.new()
	n.add_child(beacon)
	beacon.position = Vector3(0.3, 2.3, 0.62)
	_cyl(0.075, 0.05, black, Vector3.ZERO, Vector3.ZERO, beacon, 10)
	var dome_m := _glow(Color(1.0, 0.45, 0.05), 3.0)
	_cyl(0.065, 0.13, dome_m, Vector3(0, 0.09, 0), Vector3.ZERO, beacon, 10)
	var refl := Node3D.new()
	beacon.add_child(refl)
	refl.position = Vector3(0, 0.09, 0)
	box(Vector3(0.11, 0.08, 0.02), Vector3(0, 0, 0.02), _glow(Color(1.0, 0.7, 0.2), 9.0), refl)
	var bl := OmniLight3D.new()
	bl.light_color = Color(1.0, 0.5, 0.1)
	bl.light_energy = 1.5
	bl.omni_range = 4.0
	beacon.add_child(bl)
	bl.position = Vector3(0, 0.25, 0)
	var body := LabCharacter.new()
	body.sex = info.get("sex", "male")
	body.hat = info.get("hat", "hardhat")
	body.suit_color = col
	n.add_child(body)
	body.position = Vector3(0, 0.55, 0.42)
	body.rotation.y = PI
	body.play_loop("Driving", 0.0)
	var label := Label3D.new()
	label.text = info.name
	label.position = Vector3(0, 3.0, 0.2)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 26
	label.outline_size = 10
	label.modulate = col.lightened(0.35)
	n.add_child(label)
	return {"node": n, "yaw": yaw, "v": 0.0, "steer": 0.0, "lift": 0.0, "lift_t": 0.0, "push": Vector3.ZERO, "alive": true, "carry": -1,
		"carriage": carriage, "spins": spins, "pivots": pivots, "body": body, "beacon": beacon, "refl": refl, "blight": bl, "head": head,
		"label": label, "tpos": pos, "tyaw": yaw, "tip": 0.0, "tip_sent": false, "cand": -1, "color": col, "name": info.name}

func _animate_truck(id: int, delta: float) -> void:
	var t: Dictionary = T[id]
	var c: Node3D = t.carriage
	c.position.y = FORK_Y0 + float(t.lift) * FORK_SPAN
	if not bool(t.alive):
		return
	var v: float = t.v
	for s in t.spins:
		var sp: Node3D = s[0]
		sp.rotation.x -= v / float(s[1]) * delta
	for pv in t.pivots:
		(pv as Node3D).rotation.y = -float(t.steer) * 0.55
	var refl: Node3D = t.refl
	refl.rotation.y = _beacon_t * 9.0 + float(id % 7)
	var bl: OmniLight3D = t.blight
	bl.light_energy = 0.6 + 1.6 * maxf(0.0, sin(_beacon_t * 9.0 + float(id % 7)))


func _physics_process(delta: float) -> void:
	if not world or T.is_empty():
		return
	_sync_n += 1
	for id in T:
		var t: Dictionary = T[id]
		var n: CharacterBody3D = t.node
		if bool(t.alive):
			if _is_auth(id):
				var cmd := Vector3(0.0, 0.0, float(t.lift_t))
				if st == St.RUN:
					cmd = _bot_cmd(id, delta) if _ai(id) else _key_cmd(id, delta)
				_drive(id, cmd, delta)
				if _sync_n % 2 == 0:
					_rpc_state.rpc(id, n.position, float(t.yaw), float(t.v), float(t.lift), float(t.steer))
			else:
				var tp: Vector3 = t.tpos
				n.position = n.position.lerp(tp, 0.3)
				t.yaw = lerp_angle(float(t.yaw), float(t.tyaw), 0.3)
				n.rotation.y = float(t.yaw)
		_animate_truck(id, delta)
	if multiplayer.is_server() and st == St.RUN:
		_server_rules(delta)

func _key_cmd(id: int, delta: float) -> Vector3:
	var thr := 0.0
	var steer := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): thr += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): thr -= 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): steer += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): steer -= 1.0
	var lt: float = T[id].lift_t
	if Input.is_physical_key_pressed(KEY_E): lt += LIFT_RATE * delta
	if Input.is_physical_key_pressed(KEY_Q): lt -= LIFT_RATE * delta
	var sp := Input.is_physical_key_pressed(KEY_SPACE)
	if sp and not _space_down:
		lt = 0.0 if lt > 0.2 else CARRY_LIFT
	_space_down = sp
	return Vector3(thr, steer, clampf(lt, 0.0, 1.0))

func _drive(id: int, cmd: Vector3, delta: float) -> void:
	var t: Dictionary = T[id]
	var n: CharacterBody3D = t.node
	var v: float = t.v
	var thr := cmd.x
	if thr > 0.05:
		v = move_toward(v, 0.0, BRAKE * delta) if v < 0.0 else move_toward(v, MAX_V * thr, ACCEL * delta)
	elif thr < -0.05:
		v = move_toward(v, 0.0, BRAKE * delta) if v > 0.0 else move_toward(v, REV_V * thr, ACCEL * 0.7 * delta)
	else:
		v = move_toward(v, 0.0, DRAG * delta)
	t.steer = move_toward(float(t.steer), clampf(cmd.y, -1.0, 1.0), 4.5 * delta)
	var yr: float = float(t.steer) * TURN * clampf(absf(v) / 1.8, 0.0, 1.0) * signf(v)
	t.yaw = float(t.yaw) + yr * delta
	t.lift_t = clampf(cmd.z, 0.0, 1.0)
	t.lift = move_toward(float(t.lift), float(t.lift_t), LIFT_RATE * delta)
	var f := _fwd(float(t.yaw))
	var push: Vector3 = t.push
	n.rotation.y = float(t.yaw)
	n.velocity = f * v + push
	n.move_and_slide()
	n.position.y = 0.0
	var hit_truck := -1
	var head_on := false
	for i in n.get_slide_collision_count():
		var col := n.get_slide_collision(i)
		var into := -col.get_normal().dot(f * signf(v))
		if into > 0.45:
			head_on = true
			var other: Object = col.get_collider()
			if other is CharacterBody3D and (other as Node).has_meta("fid"):
				hit_truck = int((other as Node).get_meta("fid"))
	if head_on:
		if hit_truck >= 0 and absf(v) > RAM_V:
			if multiplayer.is_server():
				_server_ram(id, hit_truck)
			else:
				_req_ram.rpc_id(1, id, hit_truck)
		v *= 0.3
		_jolt = maxf(_jolt, 0.5) if id == multiplayer.get_unique_id() else _jolt
	t.push = push.move_toward(Vector3.ZERO, 8.0 * delta)
	t.v = v
	var lat := absf(v * yr)
	var risky := int(t.carry) >= 0 and (lat > TIP_LAT or (float(t.lift) > TIP_LIFT and lat > TIP_LAT_HIGH))
	t.tip = float(t.tip) + delta if risky else maxf(0.0, float(t.tip) - delta * 2.0)
	if float(t.tip) > TIP_TIME and not bool(t.tip_sent):
		t.tip_sent = true
		var side := signf(yr) if yr != 0.0 else 1.0
		if multiplayer.is_server():
			_server_crash(id, TIP, side)
		else:
			_req_tip.rpc_id(1, side)

@rpc("any_peer", "unreliable_ordered")
func _rpc_state(id: int, p: Vector3, yaw: float, v: float, lift: float, steer: float) -> void:
	if not T.has(id) or _is_auth(id):
		return
	var t: Dictionary = T[id]
	if not bool(t.alive):
		return
	t.tpos = p
	t.tyaw = yaw
	t.v = v
	t.lift = lift
	t.steer = steer

@rpc("any_peer", "reliable")
func _req_tip(side: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if T.has(id) and bool(T[id].alive) and int(T[id].carry) >= 0:
		_server_crash(id, TIP, side)

@rpc("any_peer", "reliable")
func _req_ram(a: int, b: int) -> void:
	if multiplayer.get_remote_sender_id() == a:
		_server_ram(a, b)


func _server_rules(delta: float) -> void:
	for id in T:
		var t: Dictionary = T[id]
		if not bool(t.alive):
			continue
		var n: CharacterBody3D = t.node
		if n.position.x > EDGE_X + 0.1:
			_server_crash(id, FALL, signf(float(t.v)) if float(t.v) != 0.0 else 1.0)
			continue
		var fp := _fork_point(t)
		var ci: int = t.carry
		if ci < 0:
			var near := -1
			for i in P.size():
				var pd: Dictionary = P[i]
				if int(pd.carrier) != -1:
					continue
				var pp: Vector3 = pd.pos
				if Vector2(fp.x - pp.x, fp.z - pp.z).length() < PICK_R and _aligned(float(t.yaw), float(pd.yaw)):
					near = i
					break
			if near < 0:
				t.cand = -1
			elif float(t.lift) < 0.18:
				t.cand = near
			elif float(t.lift) >= CARRY_MIN and int(t.cand) == near:
				t.cand = -1
				_rpc_pick.rpc(id, near)
		else:
			if _zone_rect(id).grow(0.15).has_point(Vector2(fp.x, fp.z)):
				deliveries[id] = int(deliveries[id]) + 1
				_last_deliver[id] = clock
				var sp := _free_spot(int(P[ci].spot))
				P[ci].spot = sp[2]
				_rpc_deliver.rpc(id, ci, sp[0], sp[1], int(deliveries[id]))
			elif float(t.lift) < CARRY_MIN - 0.1:
				_rpc_drop.rpc(ci, Vector3(fp.x, 0.0, fp.z), float(t.yaw))
	_nudge_pallets()
	_pal_sync_t -= delta
	if _pal_dirty and _pal_sync_t <= 0.0:
		_pal_sync_t = 0.1
		_pal_dirty = false
		var arr: Array = []
		for i in P.size():
			var pd: Dictionary = P[i]
			if int(pd.carrier) == -1:
				var pp: Vector3 = pd.pos
				arr.append([i, pp.x, pp.z])
		_rpc_pallets.rpc(arr)
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = 0.25
		_rpc_tick.rpc(maxf(0.0, TIME_LIMIT - clock))

func _aligned(tyaw: float, pyaw: float) -> bool:
	var d := absf(wrapf(pyaw - tyaw, -PI * 0.5, PI * 0.5))
	return d < deg_to_rad(36.0)

func _nudge_pallets() -> void:
	for i in P.size():
		var pd: Dictionary = P[i]
		if int(pd.carrier) != -1:
			continue
		var pp: Vector3 = pd.pos
		for id in T:
			var t: Dictionary = T[id]
			var n: CharacterBody3D = t.node
			var rel := pp - n.position
			var f := _fwd(float(t.yaw))
			var r := f.cross(Vector3.UP)
			var lz := -rel.dot(f)
			var lx := rel.dot(r)
			if absf(lx) < 1.15 and lz > -1.0 and lz < 1.55:
				var away := Vector3(rel.x, 0.0, rel.z).normalized()
				if absf(float(t.v)) > 0.3:
					away = (away + f * signf(float(t.v))).normalized()
				pp += away * 0.09
				_pal_dirty = true
		pp.x = clampf(pp.x, 0.9, EDGE_X - 0.8)
		pp.z = clampf(pp.z, 0.9, AD - 0.9)
		for rect in RACKS:
			var g := rect.grow(0.55)
			if g.has_point(Vector2(pp.x, pp.z)):
				var c := g.get_center()
				if absf(pp.z - c.y) / g.size.y > absf(pp.x - c.x) / g.size.x:
					pp.z = g.position.y if pp.z < c.y else g.end.y
				else:
					pp.x = g.position.x if pp.x < c.x else g.end.x
		pd.pos = pp

func _server_ram(a: int, b: int) -> void:
	if st != St.RUN or not T.has(a) or not T.has(b) or a == b:
		return
	if not bool(T[a].alive) or not bool(T[b].alive) or clock < float(_ram_cd[a]):
		return
	_ram_cd[a] = clock + RAM_CD
	var na: CharacterBody3D = T[a].node
	var nb: CharacterBody3D = T[b].node
	var dir := nb.position - na.position
	dir.y = 0.0
	dir = (dir.normalized() + _fwd(float(T[a].yaw)) * signf(float(T[a].v))).normalized()
	var ci: int = T[b].carry
	var dpos := Vector3.ZERO
	if ci >= 0:
		var fp := _fork_point(T[b])
		dpos = fp + dir * 1.1
		dpos.x = clampf(dpos.x, 0.9, EDGE_X - 0.8)
		dpos.z = clampf(dpos.z, 0.9, AD - 0.9)
		dpos.y = 0.0
	_rpc_ram.rpc(a, b, dir, ci, dpos, float(T[b].yaw) + randf_range(-0.5, 0.5))

func _server_crash(id: int, kind: int, side: float) -> void:
	if not T.has(id) or not bool(T[id].alive) or st == St.DONE:
		return
	var t: Dictionary = T[id]
	var ci: int = t.carry
	var dpos := Vector3.ZERO
	if ci >= 0 and kind == TIP:
		var n: CharacterBody3D = t.node
		var f := _fwd(float(t.yaw))
		dpos = n.position + f * 1.9 + f.cross(Vector3.UP) * (-side) * 1.4
		dpos.x = clampf(dpos.x, 0.9, EDGE_X - 0.8)
		dpos.z = clampf(dpos.z, 0.9, AD - 0.9)
	_rpc_crash.rpc(id, kind, side, ci, dpos)
	if ci >= 0 and kind == FALL:
		get_tree().create_timer(1.6).timeout.connect(func() -> void:
			if st == St.DONE or int(P[ci].carrier) != id:
				return
			var sp := _free_spot(-1)
			P[ci].spot = sp[2]
			_rpc_respawn.rpc(ci, sp[0], sp[1]))


@rpc("authority", "call_local", "reliable")
func _rpc_pick(id: int, idx: int) -> void:
	var t: Dictionary = T[id]
	var pd: Dictionary = P[idx]
	pd.carrier = id
	t.carry = idx
	var node: Node3D = pd.node
	var c: Node3D = t.carriage
	node.reparent(c, true)
	var ly := wrapf(node.rotation.y, -PI, PI)
	var want := PI if absf(ly) > PI * 0.5 else 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(node, "position", Vector3(0.0, -0.1, -FORK_REACH), 0.18)
	tw.tween_property(node, "rotation", Vector3(0.0, want, 0.0), 0.18)
	Fx.sfx("click", node.global_position, -2.0, 0.8)
	Fx.sfx("hum", node.global_position, -10.0, 0.6)

func _detach_pallet(idx: int) -> Node3D:
	var pd: Dictionary = P[idx]
	var cid: int = pd.carrier
	if cid >= 0 and T.has(cid) and int(T[cid].carry) == idx:
		T[cid].carry = -1
	pd.carrier = -1
	var node: Node3D = pd.node
	node.reparent(world, true)
	return node

@rpc("authority", "call_local", "reliable")
func _rpc_drop(idx: int, pos: Vector3, yaw: float) -> void:
	var node := _detach_pallet(idx)
	P[idx].pos = pos
	P[idx].yaw = yaw
	var tw := create_tween().set_parallel(true)
	tw.tween_property(node, "position", pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "rotation", Vector3(0.0, yaw, 0.0), 0.25)
	Fx.sfx("hit", pos, -10.0, 0.7)

@rpc("authority", "call_local", "reliable")
func _rpc_pallets(arr: Array) -> void:
	for e in arr:
		var i: int = e[0]
		if i >= P.size() or int(P[i].carrier) != -1:
			continue
		var p := Vector3(e[1], 0.0, e[2])
		P[i].pos = p
		var node: Node3D = P[i].node
		node.position = p

@rpc("authority", "call_local", "reliable")
func _rpc_deliver(id: int, idx: int, npos: Vector3, nyaw: float, count: int) -> void:
	deliveries[id] = count
	var node := _detach_pallet(idx)
	var stacks: int = _zone_stacks[id]
	if stacks < 2:
		var r := _zone_rect(id)
		var z: Array = ZONES[zone_of[id]]
		var off := Vector3(-0.75 + float(stacks) * 1.5, 0.0, 0.0) if int(z[2]) < 2 else Vector3(0.0, 0.0, -0.75 + float(stacks) * 1.5)
		var copy: Node3D = node.duplicate()
		world.add_child(copy)
		copy.global_transform = node.global_transform
		var tw := create_tween().set_parallel(true)
		tw.tween_property(copy, "position", Vector3(r.get_center().x, 0.02, r.get_center().y) + off, 0.3)
		tw.tween_property(copy, "rotation", Vector3(0.0, 0.0 if int(z[2]) < 2 else PI * 0.5, 0.0), 0.3)
	_zone_stacks[id] = stacks + 1
	var lab: Label3D = _zone_labels[id]
	lab.text = "%s\n%d" % [NetworkManager.players[id].name, count]
	_place_new_pallet(idx, node, npos, nyaw)
	Fx.sfx("win", node.global_position, -8.0, 1.2)
	if id == multiplayer.get_unique_id():
		_big_local("DELIVERED  +1", "8fe36a", 0.9)
	_refresh_board()

func _place_new_pallet(idx: int, node: Node3D, npos: Vector3, nyaw: float) -> void:
	P[idx].pos = npos
	P[idx].yaw = nyaw
	node.position = npos + Vector3(0, 6.0, 0)
	node.rotation = Vector3(0.0, nyaw, 0.0)
	node.visible = true
	var tw := create_tween()
	tw.tween_property(node, "position", npos, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: Fx.sfx("hit", npos, -12.0, 0.6))

@rpc("authority", "call_local", "reliable")
func _rpc_respawn(idx: int, npos: Vector3, nyaw: float) -> void:
	var node: Node3D = P[idx].node
	var wreck: Node3D = node.duplicate()
	node.get_parent().add_child(wreck)
	wreck.transform = node.transform
	var n := _detach_pallet(idx)
	_place_new_pallet(idx, n, npos, nyaw)

@rpc("authority", "call_local", "reliable")
func _rpc_ram(a: int, b: int, dir: Vector3, ci: int, dpos: Vector3, dyaw: float) -> void:
	var nb: CharacterBody3D = T[b].node
	var na: CharacterBody3D = T[a].node
	var hit := (na.position + nb.position) * 0.5 + Vector3(0, 0.8, 0)
	Fx.sparks(world, hit)
	Fx.sfx("hit", hit, 2.0, 0.7)
	Fx.sfx("explosion", hit, -16.0, 1.8)
	if a == multiplayer.get_unique_id() or b == multiplayer.get_unique_id():
		Fx.shake(0.35)
		_jolt = 1.0
	if _is_auth(b):
		T[b].push = dir * 6.5
		T[b].v = float(T[b].v) * 0.2
	if _is_auth(a):
		T[a].v = float(T[a].v) * 0.35
	var lb: LabCharacter = T[b].body
	if bool(T[b].alive):
		lb.play_action("Hit_Knockback", 0.06, 1.4)
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			if T.has(b) and bool(T[b].alive):
				lb.play_loop("Driving", 0.2))
	if ci >= 0:
		var node := _detach_pallet(ci)
		P[ci].pos = dpos
		P[ci].yaw = dyaw
		var tw := create_tween().set_parallel(true)
		tw.tween_property(node, "position:x", dpos.x, 0.45)
		tw.tween_property(node, "position:z", dpos.z, 0.45)
		tw.tween_property(node, "rotation", Vector3(0.0, dyaw, 0.0), 0.45)
		var up := create_tween()
		up.tween_property(node, "position:y", node.position.y + 0.6, 0.18).set_ease(Tween.EASE_OUT)
		up.tween_property(node, "position:y", 0.0, 0.27).set_ease(Tween.EASE_IN)
		if b == multiplayer.get_unique_id():
			_big_local("RAMMED  ·  LOAD DROPPED", "ff7a4a", 1.0)

@rpc("authority", "call_local", "reliable")
func _rpc_crash(id: int, kind: int, side: float, ci: int, dpos: Vector3) -> void:
	var t: Dictionary = T[id]
	if not bool(t.alive):
		return
	t.alive = false
	t.v = 0.0
	dead_order.append(id)
	var n: CharacterBody3D = t.node
	n.collision_layer = 0
	n.collision_mask = 0
	var head: SpotLight3D = t.head
	var beacon: Node3D = t.beacon
	var label: Label3D = t.label
	label.modulate.a = 0.35
	var body: LabCharacter = t.body
	var f := _fwd(float(t.yaw))
	var right := f.cross(Vector3.UP)
	var land: Vector3
	var throw_to: Vector3
	if kind == FALL:
		var m := f * side
		land = n.position + m * 2.4 + Vector3(0, PIT_Y, 0)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(n, "position:x", land.x, 0.8)
		tw.tween_property(n, "position:z", land.z, 0.8)
		tw.tween_property(n, "position:y", PIT_Y + 0.2, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(n, "rotation:x", -0.95 * side, 0.7)
		tw.tween_property(n, "rotation:z", randf_range(-0.3, 0.3), 0.7)
		throw_to = land + m * 1.6 + right * randf_range(-1.0, 1.0)
		throw_to.y = PIT_Y
		Fx.sfx("whoosh", n.position, 0.0, 0.6)
		if id == multiplayer.get_unique_id():
			_big_local("OFF THE DOCK", "ff4030", 2.0)
	else:
		land = n.position + right * side * 0.55
		var tw := create_tween().set_parallel(true)
		tw.tween_property(n, "rotation:z", -1.5 * side, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(n, "position", land + Vector3(0, 0.55, 0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		throw_to = n.position + right * side * 2.3 + f * 0.6
		throw_to.y = 0.0
		Fx.sfx("hit", n.position, 2.0, 0.5)
		if id == multiplayer.get_unique_id():
			_big_local("TIPPED OVER", "ff4030", 2.0)
		if ci >= 0:
			var node := _detach_pallet(ci)
			P[ci].pos = dpos
			P[ci].yaw = float(t.yaw) + side * 0.6
			var tp := create_tween().set_parallel(true)
			tp.tween_property(node, "position", dpos, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tp.tween_property(node, "rotation", Vector3(0.0, float(P[ci].yaw), 0.0), 0.5)
	var start := body.global_transform
	body.reparent(world, false)
	body.global_transform = start
	body.die("Death01")
	var bt := create_tween().set_parallel(true)
	var dur := 0.85 if kind == FALL else 0.55
	bt.tween_property(body, "position:x", throw_to.x, dur)
	bt.tween_property(body, "position:z", throw_to.z, dur)
	bt.tween_property(body, "rotation:y", body.rotation.y + side * 2.2, dur)
	var bu := create_tween()
	bu.tween_property(body, "position:y", body.position.y + 0.9, dur * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bu.tween_property(body, "position:y", throw_to.y, dur * 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	bu.tween_callback(func() -> void:
		Fx.blood(world, throw_to + Vector3(0, 0.4, 0), 70)
		Fx.sfx("splat", throw_to, 0.0))
	var boom := create_tween()
	boom.tween_interval(0.8 if kind == FALL else 0.6)
	boom.tween_callback(func() -> void:
		Fx.explosion(world, n.position + Vector3(0, 0.6, 0), 1.3)
		head.visible = false
		beacon.visible = false
		Fx.shake(0.7))
	if id == multiplayer.get_unique_id():
		_dead_cam_t = 1.6
	_refresh_board()


func _bot_init(id: int) -> void:
	_bot[id] = {"mode": "", "pal": -1, "side": 1.0, "phase": 0, "wp": Vector3.ZERO, "goal": Vector3.ZERO, "think": randf() * 0.3,
		"stuck": 0.0, "back_until": -1.0, "back_thr": -0.8, "back_steer": 0.0, "victim": 0, "until": 0.0, "insert_t": 0.0,
		"aggro": randf_range(0.15, 0.85), "greed": randf(), "care": randf_range(0.75, 1.2), "lift": 0.0,
		"best_d": INF, "prog_t": 0.0, "ban": -1, "ban_until": 0.0}

func _bot_plan(id: int) -> void:
	var t: Dictionary = T[id]
	var b: Dictionary = _bot[id]
	var n: CharacterBody3D = t.node
	var pos := n.position
	if int(t.carry) >= 0:
		b.mode = "deliver"
		var r := _zone_rect(id)
		var zc := Vector3(r.get_center().x, 0.0, r.get_center().y)
		var stage := zc + _zone_in(id) * 3.6
		b.goal = zc
		b.wp = _route(pos, stage)
		return
	if b.mode == "hunt":
		var vid: int = b.victim
		if clock < float(b.until) and bool(T[vid].alive) and int(T[vid].carry) >= 0:
			var vn: CharacterBody3D = T[vid].node
			b.goal = vn.position
			b.wp = _route(pos, b.goal)
			return
		b.mode = ""
	if randf() < float(b.aggro) * 0.12:
		for o in T:
			if o == id or not bool(T[o].alive) or int(T[o].carry) < 0:
				continue
			var on: CharacterBody3D = T[o].node
			if on.position.distance_to(pos) < 7.5 and _clear(pos, on.position):
				b.mode = "hunt"
				b.victim = o
				b.until = clock + 3.5
				b.goal = on.position
				b.wp = _route(pos, b.goal)
				return
	var pal: int = b.pal
	var keep: bool = b.mode == "fetch" and pal >= 0 and int(P[pal].carrier) == -1 and float(b.insert_t) < 4.0
	if not keep:
		var best := -1
		var best_s := INF
		var best_side := 1.0
		for i in P.size():
			var pd: Dictionary = P[i]
			if int(pd.carrier) != -1:
				continue
			var pp: Vector3 = pd.pos
			if i == int(b.ban) and clock < float(b.ban_until):
				continue
			var claimed := false
			for o in _bot:
				if o != id and _bot[o].mode == "fetch" and int(_bot[o].pal) == i:
					claimed = true
			for s in [1.0, -1.0]:
				var a: Vector3 = pp + _axis(float(pd.yaw)) * s * 3.4
				if not _ok_ground(a, 1.2):
					continue
				var sc := pos.distance_to(a) + (6.0 if claimed else 0.0) + (8.0 if i == pal else 0.0) + maxf(0.0, a.x - (EDGE_X - 5.0)) * 1.5
				if sc < best_s:
					best_s = sc
					best = i
					best_side = s
		b.mode = "fetch"
		b.pal = best
		b.side = best_side
		b.phase = 0
		b.insert_t = 0.0
	if int(b.pal) >= 0:
		var pd2: Dictionary = P[b.pal]
		var pp2: Vector3 = pd2.pos
		if int(b.phase) == 1:
			b.goal = pp2

func _zone_in(id: int) -> Vector3:
	var z: Array = ZONES[zone_of[id]]
	return [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0)][int(z[2])]

func _ok_ground(p: Vector3, margin: float) -> bool:
	if p.x < margin or p.z < margin or p.z > AD - margin or p.x > EDGE_X - margin - 0.6:
		return false
	for rect in RACKS:
		if rect.grow(margin).has_point(Vector2(p.x, p.z)):
			return false
	return true

func _bot_cmd(id: int, delta: float) -> Vector3:
	var t: Dictionary = T[id]
	var b: Dictionary = _bot[id]
	var n: CharacterBody3D = t.node
	var pos := n.position
	var f := _fwd(float(t.yaw))
	b.think = float(b.think) - delta
	if float(b.think) <= 0.0:
		b.think = randf_range(0.2, 0.3)
		_bot_plan(id)
	var carry_lift := 0.74 if float(b.greed) > 0.9 else CARRY_LIFT
	var gnow: Vector3 = b.goal
	if gnow.distance_to(b.get("pgoal", Vector3.INF)) > 0.6:
		b.pgoal = gnow
		b.best_d = INF
		b.prog_t = 0.0
	var gd := pos.distance_to(gnow)
	if gd < float(b.best_d) - 0.4:
		b.best_d = gd
		b.prog_t = 0.0
	else:
		b.prog_t = float(b.prog_t) + delta
	if float(b.prog_t) > 3.5:
		b.prog_t = 0.0
		b.best_d = INF
		b.back_until = clock + randf_range(0.8, 1.2)
		b.back_thr = -signf(float(t.v)) * 0.8 if absf(float(t.v)) > 0.1 else -0.8
		b.back_steer = 1.0 if randf() < 0.5 else -1.0
		if String(b.mode) == "fetch":
			b.ban = b.pal
			b.ban_until = clock + 6.0
			b.mode = ""
			b.pal = -1
	if clock < float(b.back_until):
		return Vector3(float(b.back_thr), float(b.back_steer), float(b.lift))
	var cmd := Vector3.ZERO
	match String(b.mode):
		"deliver":
			b.lift = carry_lift
			var gw: Vector3 = b.goal
			var inw := _zone_in(id)
			var stage := gw + inw * 3.6
			var rel := pos - gw
			var inline := rel.dot(inw) > 1.2 and (rel - inw * rel.dot(inw)).length() < 0.8 and f.dot(-inw) > 0.8
			if inline:
				cmd = _steer_to(id, gw, 0.6, false)
			else:
				var wpv: Vector3 = b.wp
				if wpv.distance_to(pos) < 1.2:
					b.wp = stage if pos.distance_to(stage) > 1.0 else gw
					if pos.distance_to(stage) > 1.0:
						b.wp = _route(pos, stage)
				var near_stage := pos.distance_to(stage) < 1.0
				cmd = _steer_to(id, gw if near_stage else wpv, 0.55 if pos.distance_to(stage) < 3.0 else 1.0, not near_stage)
		"hunt":
			b.lift = 0.0
			var vn: CharacterBody3D = T[int(b.victim)].node
			cmd = _steer_to(id, _route(pos, vn.position), 1.0, false)
		"fetch":
			if int(b.pal) < 0:
				b.lift = 0.0
				cmd = _steer_to(id, Vector3(AW * 0.5 - 1.0, 0.0, AD * 0.5), 0.5, true)
			else:
				cmd = _bot_fetch(id, delta)
	cmd.z = float(b.lift)
	if absf(float(t.v)) < 0.25 and absf(cmd.x) > 0.15:
		b.stuck = float(b.stuck) + delta
		if float(b.stuck) > 0.8:
			b.stuck = 0.0
			b.back_until = clock + randf_range(0.7, 1.1)
			b.back_thr = -signf(cmd.x) * 0.8
			b.back_steer = -cmd.y if absf(cmd.y) > 0.2 else (1.0 if randf() < 0.5 else -1.0)
			b.phase = 0
			if String(b.mode) == "hunt":
				b.mode = ""
	else:
		b.stuck = maxf(0.0, float(b.stuck) - delta)
	return cmd

func _bot_fetch(id: int, delta: float) -> Vector3:
	var t: Dictionary = T[id]
	var b: Dictionary = _bot[id]
	var n: CharacterBody3D = t.node
	var pos := n.position
	var f := _fwd(float(t.yaw))
	var pd: Dictionary = P[b.pal]
	var pp: Vector3 = pd.pos
	var ax := _axis(float(pd.yaw)) * float(b.side)
	var rel := pos - pp
	rel.y = 0.0
	var along := rel.dot(ax)
	var lateral := (rel - ax * along).length()
	var facing := f.dot(-ax)
	var aligned := along > 1.9 and along < 4.6 and lateral < 0.6 and facing > 0.8
	if int(b.phase) != 1:
		var a := pp + ax * 3.4
		var a2 := pp + ax * 5.6
		if not _ok_ground(a2, 1.0):
			a2 = a
		if aligned:
			b.phase = 1
			b.insert_t = 0.0
			b.goal = pp
		else:
			b.lift = 0.0
			if int(b.phase) == 0 and pos.distance_to(a2) < 1.4:
				b.phase = 2
			if int(b.phase) == 2:
				b.goal = a
				if pos.distance_to(a) < 0.7 or along < 1.9:
					b.phase = 0
				return _steer_to(id, a, 0.5, false)
			b.goal = a2
			var wp := _route(pos, a2)
			b.wp = wp
			var slow := 0.6 if pos.distance_to(a2) < 3.0 else 1.0
			return _steer_to(id, wp, slow, true)
	b.insert_t = float(b.insert_t) + delta
	if lateral > 1.1 or along > 5.0 or along < 0.8 or (facing < 0.55 and along < 3.0) or float(b.insert_t) > 4.0:
		b.phase = 0
		b.back_until = clock + 0.7
		b.back_thr = -0.8
		b.back_steer = 0.0
		if float(b.insert_t) > 4.0:
			b.mode = ""
		return Vector3(-0.8, 0.0, 0.0)
	var c := pp + ax * maxf(along - 1.3, FORK_REACH)
	if along < FORK_REACH + 0.22:
		b.lift = 0.5
		return Vector3(-0.1 if float(t.v) > 0.2 else 0.0, 0.0, 0.5)
	b.lift = 0.0
	var aim := pp + ax * (FORK_REACH - 0.4)
	if along - FORK_REACH > 1.0:
		aim = c.lerp(aim, 0.3)
	return _steer_to(id, aim, 0.42, false)

func _steer_to(id: int, goal: Vector3, thr_max: float, avoid: bool) -> Vector3:
	var t: Dictionary = T[id]
	var b: Dictionary = _bot[id]
	var n: CharacterBody3D = t.node
	var pos := n.position
	var f := _fwd(float(t.yaw))
	var v: float = t.v
	goal.x = minf(goal.x, EDGE_X - 1.7)
	var d := goal - pos
	d.y = 0.0
	var dist := d.length()
	if dist < 0.05:
		return Vector3.ZERO
	d = d / dist
	var ang := atan2(f.cross(d).y, f.dot(d))
	var thr: float
	var steer: float
	if (absf(ang) > 2.2 and dist < 4.5) or (absf(ang) > 1.1 and dist < 3.0):
		thr = -0.6
		steer = -signf(ang)
	else:
		thr = thr_max * (1.0 if absf(ang) < 0.45 else 0.5)
		steer = clampf(ang * 2.4, -1.0, 1.0)
	if avoid and thr > 0.0:
		var c := _ray(id, 0.0)
		if c < 3.2 and dist > c:
			var l := _ray(id, 0.6)
			var r := _ray(id, -0.6)
			steer = clampf(steer + (1.0 if l > r else -1.0) * 0.9, -1.0, 1.0)
			thr *= 0.6
	if int(t.carry) >= 0 and absf(steer) > 0.45 and v > 3.6 / float(b.care) and float(b.greed) < 0.84:
		thr = minf(thr, 0.0)
	var look := pos + f * signf(v if absf(v) > 0.2 else thr) * (2.4 + absf(v) * 0.45 * float(b.care))
	if look.x > EDGE_X - 0.4:
		var sv := signf(v) if absf(v) > 0.2 else signf(thr)
		thr = -sv
		steer = -signf(f.z if absf(f.z) > 0.05 else 1.0) * sv
	return Vector3(thr, steer, 0.0)

func _ray(id: int, off: float) -> float:
	var t: Dictionary = T[id]
	var n: CharacterBody3D = t.node
	var dir := _fwd(float(t.yaw) + off)
	var from := n.position + Vector3(0, 0.6, 0) + _fwd(float(t.yaw)) * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 3.6, 3)
	q.exclude = [n.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return 99.0
	return from.distance_to(hit.position)

func _route(from: Vector3, to: Vector3) -> Vector3:
	var hit := -1
	var best_t := INF
	for i in RACKS.size():
		var tt := _seg_rect(from, to, RACKS[i].grow(1.3))
		if tt < best_t:
			best_t = tt
			hit = i
	if hit < 0:
		return to
	var g: Rect2 = RACKS[hit].grow(2.3)
	var corners := [Vector3(g.position.x, 0, g.position.y), Vector3(g.end.x, 0, g.position.y), Vector3(g.position.x, 0, g.end.y), Vector3(g.end.x, 0, g.end.y)]
	var best: Vector3 = to
	var best_l := INF
	for c in corners:
		var cv: Vector3 = c
		var l := from.distance_to(cv) + cv.distance_to(to)
		if _seg_rect(from, cv, RACKS[hit].grow(1.3)) < INF:
			l += 20.0
		if l < best_l:
			best_l = l
			best = cv
	return best

func _clear(a: Vector3, b: Vector3) -> bool:
	for r in RACKS:
		if _seg_rect(a, b, r.grow(0.7)) < INF:
			return false
	return true

func _seg_rect(a: Vector3, b: Vector3, r: Rect2) -> float:
	var steps := 28
	for i in steps + 1:
		var k := float(i) / float(steps)
		var p := a.lerp(b, k)
		if r.has_point(Vector2(p.x, p.z)):
			return k
	return INF


func _apply_cam_mode() -> void:
	var lt := local_truck()
	var cock := _cam_cockpit and not lt.is_empty()
	for id in T:
		var t: Dictionary = T[id]
		var mine: bool = id == multiplayer.get_unique_id()
		var body: LabCharacter = t.body
		if bool(t.alive):
			body.visible = not (cock and mine)
		var lab: Label3D = t.label
		lab.visible = not (cock and mine)
	if cock:
		camera.fov = 76.0
		camera.near = 0.04
		camera.cull_mask = 0xFFFFF
	else:
		camera.fov = 50.0
		camera.near = 0.05
		camera.cull_mask = 0xFFFFF & ~HIDE_LAYER
		camera.global_transform = _overview_xf

func _process(delta: float) -> void:
	if not world or T.is_empty():
		return
	_beacon_t += delta
	if st == St.RUN:
		clock += delta
	if _auto:
		_cam_switch_t += delta
		if _cam_switch_t > 7.5:
			_cam_switch_t = 0.0
			_cam_cockpit = not _cam_cockpit and bool(local_truck().get("alive", false))
			_apply_cam_mode()
	if _dead_cam_t > 0.0:
		_dead_cam_t -= delta
		if _dead_cam_t <= 0.0 and _cam_cockpit:
			_cam_cockpit = false
			_apply_cam_mode()
	var lt := local_truck()
	if _cam_cockpit and not lt.is_empty():
		var n: CharacterBody3D = lt.node
		var v: float = lt.v
		_bob_t += delta * (3.0 + absf(v) * 1.8)
		_jolt = move_toward(_jolt, 0.0, delta * 2.5)
		var amp := 0.012 + absf(v) / MAX_V * 0.022
		var bob := Vector3(cos(_bob_t) * amp * 0.5, sin(_bob_t * 2.0) * amp + sin(_beacon_t * 37.0) * _jolt * 0.04, 0.0)
		var pitch := -0.3 + sin(_bob_t * 2.0) * amp * 0.4 - _jolt * 0.06
		var roll := float(lt.steer) * absf(v) * 0.006 + sin(_beacon_t * 31.0) * _jolt * 0.03
		camera.global_transform = n.global_transform * Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)), Vector3(0.0, 2.0, 0.5) + bob)
	_update_hud(delta)

func _build_hud() -> void:
	hud_title("FORKLIFT CERTIFIED  ·  haul pallets to your bay")
	_hud_time = _label(26, Color("ffd34a"))
	_pin(_hud_time, Vector2(0.5, 0.0), Rect2(-60, 8, 120, 34))
	_hud_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_board = RichTextLabel.new()
	_hud_board.bbcode_enabled = true
	_hud_board.fit_content = true
	_hud_board.scroll_active = false
	_hud_board.add_theme_font_size_override("normal_font_size", 16)
	_hud_board.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_board.add_theme_constant_override("outline_size", 6)
	hud.add_child(_hud_board)
	_pin(_hud_board, Vector2(1.0, 0.0), Rect2(-230, 10, 220, 240))
	_hud_hint = _label(18, Color("e8e2c8"))
	_hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_hint.text = "W / S  drive   ·   A / D  steer   ·   E / Q  forks up / down   ·   SPACE  forks to carry height\nforks under a pallet, then lift   ·   drive it to your bay   ·   ram loaded rivals   ·   slow down in turns   ·   mind the dock edge"
	_pin(_hud_hint, Vector2(0.5, 1.0), Rect2(-560, -128, 1120, 56))
	_hud_status = _label(18, Color("e8e2c8"))
	_pin(_hud_status, Vector2(0.0, 1.0), Rect2(20, -64, 520, 26))
	_lift_bar = ProgressBar.new()
	_lift_bar.show_percentage = false
	_lift_bar.max_value = 1.0
	_lift_fill = StyleBoxFlat.new()
	_lift_fill.bg_color = Color("e2b33a")
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.border_color = Color(0.4, 0.4, 0.35)
	bg.set_border_width_all(1)
	_lift_bar.add_theme_stylebox_override("fill", _lift_fill)
	_lift_bar.add_theme_stylebox_override("background", bg)
	hud.add_child(_lift_bar)
	_pin(_lift_bar, Vector2(0.0, 1.0), Rect2(20, -34, 240, 14))
	_hud_warn = _label(40, Color("ff4030"))
	_hud_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_hud_warn, Vector2(0.5, 0.5), Rect2(-300, 60, 600, 54))
	_hud_big = _label(72, Color("e8e2c8"))
	_hud_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_big.add_theme_constant_override("outline_size", 12)
	_pin(_hud_big, Vector2(0.5, 0.5), Rect2(-500, -150, 1000, 100))
	var lt := local_truck()
	_lift_bar.visible = not lt.is_empty()
	_hud_status.visible = not lt.is_empty()
	_refresh_board()

func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)
	hud.add_child(l)
	return l

func _pin(c: Control, anchor: Vector2, r: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y

func _refresh_board() -> void:
	if not _hud_board:
		return
	var ids: Array = order.duplicate()
	ids.sort_custom(func(a, b): return int(deliveries[a]) > int(deliveries[b]))
	var lines: Array = ["[color=#e8e2c8]DELIVERIES[/color]"]
	for id in ids:
		var t: Dictionary = T[id]
		var col: Color = t.color
		var dead := not bool(t.alive)
		lines.append("[color=#%s]%s%s[/color]  [color=#ffd34a]%d[/color]" % [col.lightened(0.3).to_html(false) if not dead else "777777", "† " if dead else "", t.name, int(deliveries[id])])
	_hud_board.text = "\n".join(lines)

func _update_hud(delta: float) -> void:
	if _hud_hint.modulate.a > 0.0 and st == St.RUN and clock > 8.0:
		_hud_hint.modulate.a = maxf(0.0, _hud_hint.modulate.a - delta)
	var lt := local_truck()
	if lt.is_empty():
		return
	var lift: float = lt.lift
	_lift_bar.value = lift
	var carrying := int(lt.carry) >= 0
	var hot := carrying and lift > TIP_LIFT
	_lift_fill.bg_color = Color("ff4a30") if hot else (Color("8fe36a") if carrying else Color("e2b33a"))
	if not bool(lt.alive):
		_hud_status.text = "WRECKED"
		_hud_warn.text = ""
		return
	var bay: Color = lt.color
	if carrying:
		_hud_status.text = "LOADED  ·  bring it to your bay  ·  %d km/h" % int(absf(float(lt.v)) * 3.6)
	else:
		_hud_status.text = "FORKS  ·  find a pallet  ·  %d km/h" % int(absf(float(lt.v)) * 3.6)
	_hud_status.add_theme_color_override("font_color", bay.lightened(0.35))
	var tip: float = lt.tip
	_hud_warn.text = "TIPPING!" if tip > 0.04 and fmod(_beacon_t, 0.25) < 0.17 else ""

func _big_local(text: String, hex: String, hold: float) -> void:
	_hud_big.text = text
	_hud_big.add_theme_color_override("font_color", Color(hex))
	_hud_big.modulate.a = 1.0
	if hold > 0.0:
		var tw := create_tween()
		tw.tween_interval(hold)
		tw.tween_property(_hud_big, "modulate:a", 0.0, 0.4)

@rpc("authority", "call_local", "reliable")
func _rpc_big(text: String, hex: String, hold: float) -> void:
	_big_local(text, hex, hold)

@rpc("authority", "call_local", "reliable")
func _rpc_tick(left: float) -> void:
	_hud_time.text = "%d" % int(ceil(left))

@rpc("authority", "call_local", "reliable")
func _rpc_start() -> void:
	st = St.RUN
	clock = 0.0
	_big_local("GO!", "8fe36a", 0.7)
	Fx.sfx("buzzer", null, -6.0, 1.2)

@rpc("authority", "call_local", "reliable")
func _rpc_end() -> void:
	st = St.DONE
	for id in T:
		T[id].v = 0.0
	_big_local("SHIFT OVER", "e2c84b", 0.0)
	Fx.sfx("buzzer", null, -4.0, 0.8)


func _run() -> void:
	_rpc_tick.rpc(TIME_LIMIT)
	await get_tree().create_timer(0.6).timeout
	for s in ["3", "2", "1"]:
		_rpc_big.rpc(s, "e8e2c8", 0.0)
		Fx.sfx("click")
		await get_tree().create_timer(0.8).timeout
	_rpc_start.rpc()
	while clock < TIME_LIMIT:
		await get_tree().process_frame
		if T.keys().filter(func(id): return bool(T[id].alive)).is_empty():
			break
	_rpc_end.rpc()
	await get_tree().create_timer(2.5).timeout
	if not _ended:
		_ended = true
		finished.emit(_placement())

func _placement() -> Array:
	var living: Array = order.filter(func(id): return bool(T[id].alive))
	living.sort_custom(func(a, b):
		if int(deliveries[a]) != int(deliveries[b]):
			return int(deliveries[a]) > int(deliveries[b])
		return float(_last_deliver[a]) < float(_last_deliver[b]))
	var dead: Array = order.filter(func(id): return not bool(T[id].alive))
	dead.sort_custom(func(a, b):
		if int(deliveries[a]) != int(deliveries[b]):
			return int(deliveries[a]) > int(deliveries[b])
		return dead_order.find(a) > dead_order.find(b))
	return living + dead
