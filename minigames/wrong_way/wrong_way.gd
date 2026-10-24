extends ArenaMinigame3D
## Wrong Way: subjects ride long rusted escalators that run DOWN into a scrap
## shredder. Tap LEFT and RIGHT in turn to climb a step; the same key twice
## stumbles you back. SPACE shoves a subject sharing your escalator, or hops you
## onto the next escalator toward your last tap. Barrels and crates roll down
## lanes whose handrails flash red, and the belts keep speeding up. First onto
## the top landing wins, then by height at the buzzer; the shredded place last.

const TIME_LIMIT: float = 45.0
const LANES: int = 4
const PITCH: float = 3.2
const TREAD_W: float = 1.5
const HALF_W: float = 6.4
const ANG: float = 30.0
const SN: float = 0.5
const CS: float = 0.8660254
const LEN: float = 14.0
const S_BOT: float = -1.0
const S_DEAD: float = -0.7
const STEP: float = 0.3
const START_S: float = 2.8
const STUMBLE_DS: float = 0.63
const STUMBLE_T: float = 0.45
const MIN_GAP: float = 0.08
const SHOVE_RANGE: float = 1.3
const SHOVE_DS: float = 1.26
const SHOVE_T: float = 0.6
const SHOVE_CD: float = 0.9
const HOP_CD: float = 0.7
const WARN: float = 1.3
const HAZ_START: float = LEN + 1.0
const HAZ_HIT: float = 0.55
const HAZ_DS: float = 2.25
const HAZ_T: float = 0.8
const X_SPLIT: float = 0.4
const ROLL_Z := [1.45, 2.5]
const ROLL_Y: float = -1.15
const ROLL_R: float = 0.5
const SIGN_TXT := ["►", "▼", "▲", "◄"]
const SIGN_COL := [Color(0.85, 1.0, 0.85), Color(0.4, 1.0, 0.45), Color(0.9, 1.0, 0.9), Color(0.4, 1.0, 0.45)]

enum St { COUNTDOWN, RUN, DONE }

var st: St = St.COUNTDOWN
var clock: float = 0.0
var phase: float = 0.0
var s_of: Dictionary = {}
var lane_of: Dictionary = {}
var xo_of: Dictionary = {}
var vis_s: Dictionary = {}
var vis_x: Dictionary = {}
var climb_v: Dictionary = {}
var last_k: Dictionary = {}
var last_t: Dictionary = {}
var stun_until: Dictionary = {}
var hop_ready: Dictionary = {}
var shove_ready: Dictionary = {}
var act_until: Dictionary = {}
var finish_order: Array = []
var dead_order: Array = []
var hazards: Dictionary = {}
var _next_haz_id: int = 1
var _next_haz: float = 2.2
var _bot: Dictionary = {}
var _sync_t: float = 0.0
var _ended: bool = false
var _focus_s: float = 0.0
var _now: float = 0.0
var _my_last: int = -1
var _key_flash: float = 0.0
var _spark_t: float = 0.5
var _corpses: Array = []

var _inc: Node3D
var _steps: Node3D
var _rollers: Array[Node3D] = []
var _rail_mats: Array[StandardMaterial3D] = []
var _signs: Array[Label3D] = []
var _warn_lights: Array[OmniLight3D] = []
var _sign_lights: Array[OmniLight3D] = []
var _fog: Array[MeshInstance3D] = []
var _fence_panel: Node3D
var _fence_post: Node3D
var _sconce: Node3D
var _big: Label
var _hint: Label
var _timer_label: Label
var _dist_label: Label
var _keys: RichTextLabel

func begin() -> void:
	setup_arena(false)
	_tune_light()
	_inc = Node3D.new()
	_inc.name = "Incline"
	world.add_child(_inc)
	_inc.rotation.x = deg_to_rad(ANG)
	_kit_parts()
	_build_escalators()
	_build_steps()
	_build_sides()
	_build_landing()
	_build_pit()
	_build_lights_and_cables()
	spawn_players()
	var order: Array = NetworkManager.players.keys()
	for i in order.size():
		var id: int = order[i]
		var p: LabPlayer3D = players[id]
		p.set_physics_process(false)
		p.input_enabled = false
		p.bounds = AABB()
		p.body.rotation.y = PI
		lane_of[id] = i % LANES
		xo_of[id] = 0.0
		s_of[id] = START_S - float(i / LANES) * 0.2
		vis_s[id] = s_of[id]
		climb_v[id] = 0.0
		last_k[id] = -1
		last_t[id] = -1.0
		stun_until[id] = -1.0
		hop_ready[id] = 0.0
		shove_ready[id] = 0.0
		act_until[id] = 0.0
		if p.is_bot:
			_bot[id] = {"rate": randf_range(4.2, 6.0), "fumble": randf_range(0.02, 0.06), "react": randf_range(0.3, 0.65),
				"aggro": randf_range(0.25, 0.7), "greed": randf_range(0.04, 0.14), "next": randf_range(0.1, 0.4), "think": 0.0, "ph": randf() * TAU}
	for l in LANES:
		_relayout(l)
	for id in players:
		vis_x[id] = _lane_x(lane_of[id]) + float(xo_of[id])
		players[id].position = _wpos(vis_s[id], vis_x[id], -0.06)
	camera.fov = 54.0
	_place_camera(1.0)
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.08
			n.rotation_degrees = Vector3(-62.0, 18.0, 0.0)
			n.directional_shadow_max_distance = 30.0
	env.background_color = Color(0.02, 0.02, 0.018)
	env.ambient_light_energy = 0.3
	env.ambient_light_color = Color(0.5, 0.5, 0.46)
	env.fog_density = 0.014
	env.fog_light_color = Color(0.09, 0.075, 0.065)
	env.glow_intensity = 0.85
	env.glow_bloom = 0.06

func _lane_x(l: int) -> float:
	return -HALF_W + PITCH * (float(l) + 0.5)

func _wpos(s: float, x: float, h: float = 0.0) -> Vector3:
	if s > LEN:
		return Vector3(x, LEN * SN + h, -LEN * CS - (s - LEN))
	return Vector3(x, s * SN + h * CS, -s * CS + h * SN)

func _cyl(r: float, h: float, m: Material, pos: Vector3, rot: Vector3, parent: Node, segs: int = 10, top: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r if top < 0.0 else top
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
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

func _local_mat(tex: String, tile: float, tint: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = mat(tex, tile, tint).duplicate()
	m.uv1_world_triplanar = false
	return m

func _omni(pos: Vector3, col: Color, energy: float, rng: float, parent: Node, shadow: bool = false) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = col
	o.light_energy = energy
	o.omni_range = rng
	o.omni_attenuation = 1.2
	o.shadow_enabled = shadow
	parent.add_child(o)
	o.position = pos
	return o

func _kit_parts() -> void:
	var src: Node3D = load(PH_MOD + "modular_chainlink_fence/modular_chainlink_fence.gltf").instantiate()
	_fence_panel = _extract(src, "modular_chainlink_fence_double")
	_fence_post = _extract(src, "modular_chainlink_fence_post")
	src.free()
	for part in [_fence_panel, _fence_post]:
		for mi in part.find_children("*", "MeshInstance3D", true, false):
			var m3: MeshInstance3D = mi
			for si in m3.mesh.get_surface_count():
				var src_m := m3.mesh.surface_get_material(si)
				if src_m is StandardMaterial3D:
					var dm: StandardMaterial3D = src_m.duplicate()
					dm.albedo_color = dm.albedo_color * Color(0.45, 0.43, 0.4)
					m3.set_surface_override_material(si, dm)
	var sc: Node3D = load(PH_MOD + "industrial_caged_sconce/industrial_caged_sconce.gltf").instantiate()
	_sconce = _extract(sc, "industrial_caged_sconce_a")
	sc.free()

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

func _build_escalators() -> void:
	var s0 := S_BOT - 0.2
	var s1 := LEN + 0.3
	var ln := s1 - s0
	var mz := -(s0 + s1) * 0.5
	var truss := mat("rusty_metal", 0.9, Color(0.32, 0.3, 0.28))
	var skirt := mat("rusty_metal_02", 1.2, Color(0.45, 0.42, 0.38))
	var balus := mat("rusty_metal_02", 0.9, Color(0.3, 0.29, 0.28))
	var steel_dark := mat("rusty_metal", 1.2, Color(0.25, 0.24, 0.22))
	var deck := mat("corrugated_iron", 1.1, Color(0.4, 0.38, 0.35))
	var fill := mat("rusty_metal", 0.7, Color(0.22, 0.21, 0.2))
	var amber := _glow(Color(1.0, 0.6, 0.18), 0.8)
	var stop := _glow(Color(1.0, 0.06, 0.04), 2.4)
	for l in LANES:
		var x := _lane_x(l)
		box(Vector3(TREAD_W + 0.3, 0.7, ln), Vector3(x, -0.6, mz), truss, _inc)
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.035, 0.03, 0.03)
		rm.roughness = 0.55
		rm.emission_enabled = true
		rm.emission = Color(1.0, 0.08, 0.04)
		rm.emission_energy_multiplier = 0.0
		_rail_mats.append(rm)
		for sx in [-1.0, 1.0]:
			var side: float = sx
			var cx := x + side * (TREAD_W * 0.5 + 0.1)
			box(Vector3(0.06, 0.36, ln), Vector3(x + side * (TREAD_W * 0.5 + 0.03), 0.06, mz), skirt, _inc)
			var pan := box(Vector3(0.07, 1.12, ln), Vector3(cx + side * 0.06, 0.6, mz), balus, _inc)
			pan.rotation.z = -side * 0.2
			var tx := cx + side * 0.17
			box(Vector3(0.1, 0.1, ln), Vector3(tx, 1.14, mz), steel_dark, _inc)
			_cyl(0.07, ln, rm, Vector3(tx, 1.22, mz), Vector3(90, 0, 0), _inc, 10)
			for e in 2:
				var ez: float = -(s0 if e == 0 else s1)
				var tor := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.48
				tm.outer_radius = 0.62
				tm.rings = 20
				tm.ring_segments = 8
				tor.mesh = tm
				tor.material_override = rm
				_inc.add_child(tor)
				tor.position = Vector3(tx, 0.67, ez)
				tor.rotation_degrees = Vector3(0, 0, 90)
				_cyl(0.52, 0.08, balus, Vector3(cx + side * 0.1, 0.62, ez), Vector3(0, 0, 90), _inc, 18)
	for k in LANES + 1:
		var bx := -HALF_W + PITCH * float(k)
		var wdt: float = PITCH - TREAD_W - 0.36 + 0.06
		if k == 0 or k == LANES:
			wdt = 0.5
			bx += -0.08 if k == 0 else 0.08
		box(Vector3(wdt + 0.1, 0.07, ln), Vector3(bx, 0.75, mz), deck, _inc)
		box(Vector3(wdt - 0.04, 1.0, ln), Vector3(bx, 0.22, mz), fill, _inc)
		var s := 2.0
		while s < LEN - 0.5:
			box(Vector3(0.07, 0.03, 0.07), Vector3(bx, 0.8, -s), amber, _inc)
			s += 3.0
		if k > 0 and k < LANES:
			for bs in [0.5, LEN - 0.8]:
				_cyl(0.11, 0.06, stop, Vector3(bx, 0.81, -float(bs)), Vector3.ZERO, _inc, 12)
				_cyl(0.16, 0.03, _plain(Color(0.08, 0.08, 0.08), 0.5, 0.4), Vector3(bx, 0.79, -float(bs)), Vector3.ZERO, _inc, 12)
	for l in LANES:
		var x := _lane_x(l)
		box(Vector3(TREAD_W + 0.06, 0.08, 0.7), Vector3(x, 0.03, -(LEN + 0.05)), mat("rusty_metal", 1.4, Color(0.6, 0.56, 0.5)), _inc)
		box(Vector3(TREAD_W + 0.06, 0.02, 0.08), Vector3(x, 0.08, -(LEN - 0.27)), _glow(Color(0.95, 0.75, 0.1), 0.5), _inc)

func _build_steps() -> void:
	_steps = Node3D.new()
	_steps.name = "Steps"
	_inc.add_child(_steps)
	var d := STEP * CS
	var h := STEP * SN
	var st_body := SurfaceTool.new()
	st_body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tread := BoxMesh.new()
	tread.size = Vector3(TREAD_W, 0.05, d)
	st_body.append_from(tread, 0, Transform3D(Basis(), Vector3(0, -0.025, -d * 0.5)))
	var under := BoxMesh.new()
	under.size = Vector3(TREAD_W - 0.04, 0.24, d * 0.9)
	st_body.append_from(under, 0, Transform3D(Basis(), Vector3(0, -0.17, -d * 0.5)))
	var riser := BoxMesh.new()
	riser.size = Vector3(TREAD_W, h, 0.03)
	st_body.append_from(riser, 0, Transform3D(Basis(), Vector3(0, h * 0.5 - 0.02, -d + 0.015)))
	var body_mesh := st_body.commit()
	body_mesh.surface_set_material(0, _local_mat("corrugated_iron", 2.2, Color(0.36, 0.36, 0.35)))
	var st_line := SurfaceTool.new()
	st_line.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nose := BoxMesh.new()
	nose.size = Vector3(TREAD_W - 0.06, 0.01, 0.025)
	st_line.append_from(nose, 0, Transform3D(Basis(), Vector3(0, 0.004, -0.03)))
	var side := BoxMesh.new()
	side.size = Vector3(0.02, 0.01, d - 0.06)
	for sx in [-1.0, 1.0]:
		st_line.append_from(side, 0, Transform3D(Basis(), Vector3(float(sx) * (TREAD_W * 0.5 - 0.05), 0.004, -d * 0.5)))
	var line_mesh := st_line.commit()
	var paint := _plain(Color(0.42, 0.34, 0.1), 0.85)
	paint.emission_enabled = true
	paint.emission = Color(0.6, 0.45, 0.12)
	paint.emission_energy_multiplier = 0.06
	line_mesh.surface_set_material(0, paint)
	var per := int((LEN - S_BOT) / STEP) + 1
	var b := Basis(Vector3.RIGHT, -deg_to_rad(ANG))
	for m in [body_mesh, line_mesh]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = per * LANES
		for l in LANES:
			for i in per:
				mm.set_instance_transform(l * per + i, Transform3D(b, Vector3(_lane_x(l), 0.0, -(S_BOT + float(i) * STEP))))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		_steps.add_child(mmi)

func _build_sides() -> void:
	var slab := mat("damaged_concrete_floor", 0.35, Color(0.32, 0.3, 0.27))
	var rocks := [mat("dark_rock", 0.3, Color(0.5, 0.47, 0.43)), mat("cliff_side", 0.25, Color(0.45, 0.42, 0.38)), mat("damaged_concrete_floor", 0.3, Color(0.36, 0.34, 0.3))]
	var pipe_m := mat("rusty_metal_02", 1.5)
	var cable_m := _plain(Color(0.04, 0.04, 0.04), 0.6)
	var junk := ["barrel_03", "old_tyre", "trashbag", "cement_bag", "metal_jerrycan", "cardboard_box_01", "plastic_crate_01", "metal_trash_can", "propane_tank", "can_rusted"]
	for sx in [-1.0, 1.0]:
		var side: float = sx
		box(Vector3(4.4, 0.4, LEN + 14.0), Vector3(side * (HALF_W + 2.4), -0.5, -(LEN * 0.5 + 1.0)), slab, _inc)
		box(Vector3(1.0, 34.0, 50.0), Vector3(side * (HALF_W + 9.5), 6.0, -12.0), rocks[0], world)
		for c in [[0.2, 0.13, pipe_m], [0.42, 0.08, pipe_m], [0.12, 0.05, cable_m]]:
			_cyl(float(c[1]), LEN + 12.0, c[2], Vector3(side * (HALF_W + 1.25 + float(c[0]) * 0.6), float(c[0]), -(LEN * 0.5 + 1.0)), Vector3(90, 0, 0), _inc, 8)
		var rs := -6.0
		while rs < LEN + 8.0:
			for layer in 3:
				var lx: float = [HALF_W + 3.0, HALF_W + 5.4, HALF_W + 7.6][layer]
				var ly: float = [1.0, 3.3, 6.2][layer]
				var tilt: float = [0.75, 1.0, 1.2][layer]
				var r := box(Vector3(randf_range(3.2, 4.4), randf_range(0.9, 1.6), randf_range(2.6, 4.2)), Vector3(side * (lx + randf_range(-0.4, 0.4)), ly + randf_range(-0.3, 0.3), -rs - randf_range(-0.6, 0.6)), rocks[randi() % rocks.size()], _inc)
				r.rotation = Vector3(randf_range(-0.25, 0.25), randf_range(-0.3, 0.3), side * (tilt + randf_range(-0.2, 0.2)))
			if randf() < 0.6:
				var bo := box(Vector3(randf_range(0.6, 1.5), randf_range(0.5, 1.1), randf_range(0.6, 1.4)), Vector3(side * randf_range(HALF_W + 1.9, HALF_W + 2.6), 0.3, -rs), rocks[randi() % rocks.size()], _inc)
				bo.rotation = Vector3(randf() * 0.8, randf() * TAU, randf() * 0.8)
			rs += randf_range(2.2, 3.0)
		var s := -0.5
		while s < LEN + 1.0:
			var p: Node3D = _fence_panel.duplicate()
			_inc.add_child(p)
			p.position = Vector3(side * (HALF_W + 0.22), 0.0, -s)
			p.rotation.y = deg_to_rad(90.0)
			p.scale = Vector3(1.04, 0.8, 1.0)
			var post: Node3D = _fence_post.duplicate()
			_inc.add_child(post)
			post.position = Vector3(side * (HALF_W + 0.22), 0.0, -s)
			post.scale = Vector3(1.0, 0.8, 1.0)
			s += 2.0
		var ws := -3.0
		while ws < LEN + 3.0:
			var lean := Node3D.new()
			_inc.add_child(lean)
			lean.position = Vector3(side * (HALF_W + 1.75), -0.2, -ws)
			lean.rotation.z = -side * 0.42
			var wp: Node3D = _fence_panel.duplicate()
			lean.add_child(wp)
			wp.rotation.y = deg_to_rad(90.0)
			wp.scale = Vector3(1.04, 1.9, 1.0)
			var wpost: Node3D = _fence_post.duplicate()
			lean.add_child(wpost)
			wpost.scale = Vector3(1.0, 1.9, 1.0)
			ws += 2.0
		var js := 0.5
		while js < LEN:
			if randf() < 0.8:
				var id: String = junk[randi() % junk.size()]
				var pr := prop(id, _wpos(js, side * randf_range(HALF_W + 0.75, HALF_W + 1.45), 0.0) + Vector3(0, -0.12, 0), randf() * 360.0, randf_range(1.0, 1.2), world)
				if pr and id == "old_tyre":
					pr.rotation_degrees.x = 80.0
			js += randf_range(1.4, 2.8)
		var ps := 1.5 + (0.0 if side < 0.0 else 3.0)
		while ps < LEN + 2.0:
			var lp := _wpos(ps, side * (HALF_W + 3.4), 0.0) + Vector3(0, 4.6, 0)
			prop("security_light", lp, -90.0 * side, 1.6, world)
			var sp := SpotLight3D.new()
			sp.light_color = Color(1.0, 0.86, 0.66)
			sp.light_energy = 8.0
			sp.spot_range = 10.0
			sp.spot_angle = 38.0
			sp.spot_attenuation = 0.8
			world.add_child(sp)
			sp.position = lp + Vector3(-side * 0.3, -0.2, 0)
			sp.look_at(_wpos(ps, side * (HALF_W + 2.6), 0.0), Vector3.UP)
			ps += 4.0

func _build_landing() -> void:
	var top := LEN * SN
	var z0 := -LEN * CS
	var lf := Node3D.new()
	lf.name = "Landing"
	world.add_child(lf)
	box(Vector3(2.0 * HALF_W + 9.0, 0.5, 8.0), Vector3(0, top - 0.25, z0 - 4.0), mat("hangar_concrete_floor", 0.35, Color(0.5, 0.48, 0.44)), lf)
	box(Vector3(2.0 * HALF_W + 0.2, 0.04, 2.0), Vector3(0, top + 0.01, z0 - 1.3), mat("metal_grate_rusty", 0.8, Color(0.6, 0.56, 0.5)), lf)
	box(Vector3(2.0 * HALF_W + 9.0, 1.0, 0.4), Vector3(0, top - 0.5, z0 + 0.15), mat("dirty_concrete", 0.4, Color(0.35, 0.33, 0.3)), lf)
	box(Vector3(2.0 * HALF_W + 9.0, 12.0, 0.6), Vector3(0, top + 6.0, z0 - 8.0), mat("factory_brick", 0.35, Color(0.5, 0.45, 0.4)), lf)
	box(Vector3(2.0 * HALF_W + 9.0, 1.4, 0.7), Vector3(0, top + 0.7, z0 - 7.8), mat("green_metal_rust", 0.6, Color(0.5, 0.52, 0.46)), lf)
	var gate := prop("large_iron_gate", Vector3(0, top, z0 - 7.6), 0.0, 1.3, lf)
	if gate:
		gate.scale = Vector3(1.3, 1.3, 1.3)
	for gx in [-4.6, 4.6]:
		prop("rollershutter_door", Vector3(float(gx) - 1.0, top, z0 - 7.65), 0.0, 1.1, lf)
	var ex := Label3D.new()
	ex.text = "EXIT"
	ex.font_size = 200
	ex.pixel_size = 0.006
	ex.modulate = Color(0.45, 1.0, 0.5)
	ex.outline_size = 0
	lf.add_child(ex)
	ex.position = Vector3(0, top + 4.6, z0 - 7.65)
	box(Vector3(2.6, 0.9, 0.1), Vector3(0, top + 4.6, z0 - 7.72), _plain(Color(0.03, 0.04, 0.03), 0.6), lf)
	_omni(Vector3(0, top + 3.5, z0 - 6.5), Color(0.4, 1.0, 0.5), 4.0, 10.0, lf)
	_omni(Vector3(0, top + 2.5, z0 - 2.5), Color(1.0, 0.85, 0.6), 2.5, 9.0, lf)
	var gz := z0 + 0.6
	var gy := top + 3.2
	var steel := mat("rusty_metal", 1.0, Color(0.5, 0.46, 0.42))
	box(Vector3(2.0 * HALF_W + 1.6, 0.5, 0.5), Vector3(0, gy, gz), steel, lf)
	for gx in [-HALF_W - 0.6, HALF_W + 0.6]:
		box(Vector3(0.4, 4.6, 0.4), Vector3(float(gx), top + 1.4, gz), steel, lf)
	for l in LANES:
		var x := _lane_x(l)
		box(Vector3(2.0, 1.6, 0.16), Vector3(x, gy - 1.0, gz + 0.12), _plain(Color(0.02, 0.022, 0.02), 0.5, 0.3), lf)
		box(Vector3(2.2, 1.8, 0.14), Vector3(x, gy - 1.0, gz + 0.04), mat("rusty_metal_02", 1.2, Color(0.35, 0.33, 0.32)), lf)
		for ly in [-0.55, 0.0, 0.55]:
			box(Vector3(1.85, 0.015, 0.02), Vector3(x, gy - 1.0 + float(ly), gz + 0.21), _plain(Color(0.06, 0.07, 0.06), 0.6), lf)
		var sg := Label3D.new()
		sg.text = SIGN_TXT[l]
		sg.font_size = 260
		sg.pixel_size = 0.0055
		sg.modulate = SIGN_COL[l]
		sg.outline_size = 0
		lf.add_child(sg)
		sg.position = Vector3(x, gy - 1.0, gz + 0.22)
		_signs.append(sg)
		var so := _omni(Vector3(x, gy - 1.0, gz + 1.1), SIGN_COL[l], 1.2, 3.5, lf)
		_sign_lights.append(so)
		var wl := _omni(_wpos(LEN - 1.5, x, 1.6), Color(1.0, 0.1, 0.05), 0.0, 6.5, world)
		_warn_lights.append(wl)
		box(Vector3(1.2, 0.5, 0.9), Vector3(x, top + 2.75, z0 - 1.0), mat("rusty_metal", 1.0, Color(0.3, 0.28, 0.26)), lf)
		box(Vector3(1.0, 0.05, 0.7), Vector3(x, top + 2.49, z0 - 1.0), _plain(Color(0.01, 0.01, 0.01), 0.9), lf)
	var cl := [["barrel_03", -HALF_W - 3.0, -2.0], ["barrel_03", -HALF_W - 2.3, -2.6], ["wooden_crate_02", HALF_W + 2.8, -2.2], ["old_military_crate", HALF_W + 2.2, -5.5],
		["metal_trash_can", -HALF_W - 2.8, -5.8], ["hand_truck", HALF_W + 3.4, -6.4], ["steel_frame_shelves_01", -HALF_W - 3.4, -6.8], ["wooden_crate_01", 2.5, -6.8], ["cement_bag", -2.6, -6.6]]
	for c in cl:
		prop(c[0], Vector3(float(c[1]), top, z0 + float(c[2])), randf() * 360.0 if c[0] != "steel_frame_shelves_01" else 0.0, 1.2, lf)

func _build_pit() -> void:
	var pit := Node3D.new()
	pit.name = "Pit"
	world.add_child(pit)
	var wid := 2.0 * HALF_W + 9.0
	box(Vector3(wid, 0.5, 14.0), Vector3(0, -5.5, 6.5), mat("gravel_floor", 0.4, Color(0.3, 0.27, 0.24)), pit)
	box(Vector3(wid, 4.4, 0.5), Vector3(0, -3.0, 0.5), mat("dirty_concrete", 0.4, Color(0.3, 0.28, 0.25)), pit)
	box(Vector3(wid, 8.0, 0.6), Vector3(0, -2.0, 13.0), mat("concrete_wall_006", 0.3, Color(0.3, 0.28, 0.26)), pit)
	var steel := mat("rusty_metal_02", 1.0, Color(0.42, 0.4, 0.37))
	var dark := mat("rusty_metal", 1.2, Color(0.25, 0.23, 0.21))
	var teeth := BoxMesh.new()
	teeth.size = Vector3(0.12, 0.26, 0.16)
	teeth.material = mat("rusty_metal", 2.0, Color(0.55, 0.5, 0.45))
	var rl := 2.0 * HALF_W + 0.6
	for ri in 2:
		var rn := Node3D.new()
		pit.add_child(rn)
		rn.position = Vector3(0, ROLL_Y, ROLL_Z[ri])
		_cyl(ROLL_R - 0.08, rl, dark, Vector3.ZERO, Vector3(0, 0, 90), rn, 14)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = teeth
		var rings := int(rl / 0.32)
		mm.instance_count = rings * 9
		for r in rings:
			for a in 9:
				var ang := TAU * float(a) / 9.0 + float(r % 2) * 0.35
				var dirv := Vector3(0, cos(ang), sin(ang))
				var bas := Basis(Vector3.RIGHT, ang)
				mm.set_instance_transform(r * 9 + a, Transform3D(bas, Vector3(-rl * 0.5 + 0.16 + float(r) * 0.32, 0, 0) + dirv * (ROLL_R - 0.04)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		rn.add_child(mmi)
		_rollers.append(rn)
	for sx in [-1.0, 1.0]:
		var side: float = sx
		box(Vector3(0.7, 2.2, 2.9), Vector3(side * (HALF_W + 0.65), ROLL_Y - 0.1, 1.95), steel, pit)
		_cyl(0.55, 0.2, mat("rusty_metal", 1.5), Vector3(side * (HALF_W + 1.05), ROLL_Y, 1.45), Vector3(0, 0, 90), pit, 16)
		_cyl(0.55, 0.2, mat("rusty_metal", 1.5), Vector3(side * (HALF_W + 1.05), ROLL_Y, 2.5), Vector3(0, 0, 90), pit, 16)
		box(Vector3(3.0, 0.3, 3.0), Vector3(side * (HALF_W + 2.6), -0.75, 1.8), mat("metal_grate_rusty", 0.8), pit)
	box(Vector3(rl, 0.12, 1.4), Vector3(0, ROLL_Y - 0.9, 1.95), _glow(Color(1.0, 0.14, 0.04), 1.6), pit)
	_omni(Vector3(-3.0, -2.2, 2.0), Color(1.0, 0.2, 0.07), 2.4, 5.5, pit)
	_omni(Vector3(3.0, -2.2, 2.0), Color(1.0, 0.2, 0.07), 2.4, 5.5, pit)
	_omni(Vector3(0.0, 1.8, 1.4), Color(1.0, 0.82, 0.6), 2.2, 7.0, pit, true)
	_omni(Vector3(0.0, -1.2, 6.0), Color(1.0, 0.3, 0.12), 2.2, 9.0, pit)
	var scrap := [mat("rusty_metal", 1.0, Color(0.5, 0.45, 0.4)), mat("rusty_metal_02", 1.2), mat("corrugated_iron", 1.0, Color(0.45, 0.42, 0.4)), mat("green_metal_rust", 1.0), mat("blue_metal_plate", 1.0, Color(0.5, 0.5, 0.5)), mat("worn_planks", 0.8, Color(0.4, 0.35, 0.3))]
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.75, 0.75, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.04
	glass.metallic = 0.6
	for i in 10:
		var lump := box(Vector3(randf_range(3.0, 5.5), 2.0, randf_range(2.5, 4.0)), Vector3(randf_range(-HALF_W - 2.0, HALF_W + 2.0), -4.6, randf_range(4.0, 10.5)), scrap[randi() % 3], pit)
		lump.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
	for i in 170:
		var x := randf_range(-HALF_W - 3.6, HALF_W + 3.6)
		var z := 3.0 + pow(randf(), 1.6) * 8.5
		var y := _pile_y(x, z) + randf_range(-0.2, 0.15)
		var kind := randi() % 10
		if kind < 5:
			var b := box(Vector3(randf_range(0.2, 1.4), randf_range(0.04, 0.35), randf_range(0.2, 1.1)), Vector3(x, y, z), scrap[randi() % scrap.size()], pit)
			b.rotation = Vector3(randf_range(-1.0, 1.0), randf() * TAU, randf_range(-1.0, 1.0))
		elif kind < 8:
			var sh := _cyl(randf_range(0.12, 0.34), randf_range(0.5, 1.6), scrap[randi() % 3], Vector3(x, y + 0.3, z), Vector3(randf_range(-40, 40), randf() * 360.0, randf_range(-40, 40)), pit, 3 + randi() % 2, 0.0)
			sh.scale = Vector3(1.0, 1.0, randf_range(0.3, 1.0))
		else:
			var g := box(Vector3(randf_range(0.25, 0.7), 0.012, randf_range(0.25, 0.6)), Vector3(x, y + 0.1, z), glass, pit)
			g.rotation = Vector3(randf_range(-1.2, 1.2), randf() * TAU, randf_range(-1.2, 1.2))
	for i in 70:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var x := side * randf_range(HALF_W + 0.6, HALF_W + 4.5)
		var z := randf_range(-0.4, 4.5)
		var y := randf_range(-1.6, -0.2) + (absf(x) - HALF_W) * 0.12
		if i % 3 == 0:
			var sh := _cyl(randf_range(0.15, 0.4), randf_range(0.7, 1.8), scrap[randi() % 3], Vector3(x, y + 0.3, z), Vector3(randf_range(-35, 35), randf() * 360.0, randf_range(-35, 35)), pit, 3 + randi() % 2, 0.0)
			sh.scale = Vector3(1.0, 1.0, randf_range(0.3, 1.0))
		else:
			var b := box(Vector3(randf_range(0.4, 1.8), randf_range(0.05, 0.5), randf_range(0.3, 1.4)), Vector3(x, y, z), scrap[randi() % scrap.size()], pit)
			b.rotation = Vector3(randf_range(-1.0, 1.0), randf() * TAU, randf_range(-1.0, 1.0))
	var pj := ["old_tyre", "barrel_03", "metal_jerrycan", "can_rusted", "trashbag", "propane_tank", "cardboard_box_01", "metal_toolbox", "old_gas_mask", "sledgehammer_01", "pipe_wrench"]
	for i in 26:
		var x := randf_range(-HALF_W - 3.0, HALF_W + 3.0)
		var z := 3.2 + pow(randf(), 1.5) * 7.0
		var pr := prop(pj[randi() % pj.size()], Vector3(x, _pile_y(x, z) - 0.05, z), randf() * 360.0, randf_range(1.0, 1.3), pit)
		if pr:
			pr.rotation = Vector3(randf_range(-0.8, 0.8), randf() * TAU, randf_range(-0.8, 0.8))
	var soft := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = gr
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	for i in 9:
		var q := QuadMesh.new()
		q.size = Vector2(1, 1) * randf_range(4.0, 7.0)
		var fm := StandardMaterial3D.new()
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fm.albedo_texture = soft
		fm.albedo_color = Color(0.45, 0.14, 0.1, 0.22)
		fm.disable_receive_shadows = true
		q.material = fm
		var fmi := MeshInstance3D.new()
		fmi.mesh = q
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pit.add_child(fmi)
		fmi.position = Vector3(randf_range(-HALF_W - 1.0, HALF_W + 1.0), randf_range(-3.2, -1.6), randf_range(2.5, 10.0))
		fmi.set_meta("base", fmi.position)
		fmi.set_meta("ph", randf() * TAU)
		_fog.append(fmi)

func _pile_y(x: float, z: float) -> float:
	var t := clampf((z - 3.0) / 8.0, 0.0, 1.0)
	var y := lerpf(-1.5, -4.4, sqrt(t))
	y += sin(x * 0.9 + z * 0.4) * 0.35 + cos(x * 0.37 - z * 1.1) * 0.25
	if absf(x) > HALF_W + 1.5:
		y -= 0.4
	return y

func _build_lights_and_cables() -> void:
	var cable := _plain(Color(0.035, 0.035, 0.035), 0.6)
	var k := 0
	var s := 2.5
	while s < LEN:
		var x: float = [-2.6, 1.4, -0.6, 2.8][k % 4]
		var lp := _wpos(s, x, 0.0) + Vector3(0, 7.5, 0)
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.8, 0.52)
		sp.light_energy = 16.0
		sp.spot_range = 12.0
		sp.spot_angle = 30.0
		sp.spot_attenuation = 0.9
		sp.shadow_enabled = k % 2 == 0
		world.add_child(sp)
		sp.position = lp
		sp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		s += 4.5
		k += 1
	for sx in [-1.0, 1.0]:
		var side: float = sx
		var ss := 1.5 + (0.0 if side < 0.0 else 2.0)
		while ss < LEN:
			var p := _wpos(ss, side * (HALF_W + 0.22), 0.0) + Vector3(0, 2.25, 0)
			var sc: Node3D = _sconce.duplicate()
			world.add_child(sc)
			sc.position = p
			sc.rotation.y = -PI * 0.5 * side
			sc.scale = Vector3.ONE * 1.6
			_omni(p + Vector3(-side * 1.0, 0.4, 0), Color(1.0, 0.72, 0.42), 1.3, 5.5, world)
			box(Vector3(0.08, 0.08, 0.08), p + Vector3(-side * 0.22, 0.18, 0), _glow(Color(1.0, 0.62, 0.3), 1.2), world)
			ss += 4.0
	for sx in [-1.0, 1.0]:
		var side: float = sx
		var cs := -1.0
		while cs < LEN + 2.0:
			var span := randf_range(3.0, 4.5)
			for j in 2:
				var a := _wpos(cs, side * (HALF_W + 2.6 + j * 0.3), 0.0) + Vector3(0, 2.6 + j * 0.3, 0)
				var b := _wpos(cs + span, side * (HALF_W + 2.6 + j * 0.3), 0.0) + Vector3(0, 2.6 + j * 0.3, 0)
				_catenary(a, b, randf_range(0.4, 0.9), cable)
			cs += span

func _catenary(a: Vector3, b: Vector3, sag: float, m: Material) -> void:
	var segs := 14
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var p := a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0)
		var mid := (prev + p) * 0.5
		var dvec := p - prev
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.022
		cm.bottom_radius = 0.022
		cm.height = dvec.length()
		cm.radial_segments = 4
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = m
		world.add_child(mi)
		mi.position = mid
		var up := dvec.normalized()
		var side := up.cross(Vector3.FORWARD)
		if side.length() < 0.01:
			side = up.cross(Vector3.RIGHT)
		side = side.normalized()
		mi.basis = Basis(side, up, side.cross(up).normalized())
		prev = p

func _build_hud() -> void:
	hud_title("WRONG WAY  ·  climb the down escalator, stay out of the shredder")
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
	_hint = _center_label(20, 0.73)
	_hint.text = "tap  A / D  (◄ / ►)  in turn to climb  ·  same key twice = stumble\nSPACE  shove a subject on your escalator, or hop toward your last tap\nred handrails = something is rolling down"
	_hint.add_theme_color_override("font_color", Color("e8e2c8"))
	_keys = RichTextLabel.new()
	_keys.bbcode_enabled = true
	_keys.set_anchors_preset(Control.PRESET_FULL_RECT)
	_keys.anchor_top = 0.86
	_keys.anchor_bottom = 0.98
	_keys.scroll_active = false
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys.add_theme_font_size_override("normal_font_size", 46)
	_keys.add_theme_color_override("font_outline_color", Color.BLACK)
	_keys.add_theme_constant_override("outline_size", 10)
	hud.add_child(_keys)

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

func _belt() -> float:
	if st == St.COUNTDOWN:
		return 0.0
	return 0.42 + 0.77 * pow(clampf(clock / TIME_LIMIT, 0.0, 1.0), 1.3)

func _relayout(l: int) -> void:
	var on: Array = _runners().filter(func(id): return int(lane_of[id]) == l)
	on.sort_custom(func(a, b): return float(xo_of[a]) < float(xo_of[b]))
	var n := on.size()
	for i in n:
		xo_of[on[i]] = 0.0 if n == 1 else lerpf(-X_SPLIT, X_SPLIT, float(i) / float(n - 1)) * (1.0 if n == 2 else 1.25)

func _place_camera(k: float) -> void:
	var r := _runners()
	if not r.is_empty():
		var lo := INF
		var hi := -INF
		for id in r:
			var v: float = vis_s[id]
			lo = minf(lo, v)
			hi = maxf(hi, v)
		if not finish_order.is_empty():
			hi = LEN
		var want := clampf((lo + hi) * 0.5 - 6.0, 0.0, 1.5)
		_focus_s = lerpf(_focus_s, want, k)
	camera.position = Vector3(0.0, 12.8, 13.8) + Vector3(0.0, SN, -CS) * _focus_s
	camera.rotation = Vector3(deg_to_rad(-31.0), 0.0, 0.0)

func _process(delta: float) -> void:
	if not world:
		return
	_now += delta
	if st == St.RUN:
		clock += delta
	var bv := _belt()
	phase += bv * delta
	if _steps:
		_steps.position.z = fmod(phase, STEP)
	for ri in _rollers.size():
		_rollers[ri].rotation.x += delta * (2.6 + bv) * (1.0 if ri == 0 else -1.0)
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = randf_range(0.15, 0.55)
		Fx.sparks(world, Vector3(randf_range(-HALF_W, HALF_W), ROLL_Y + 0.2, (ROLL_Z[0] + ROLL_Z[1]) * 0.5))
	for fm in _fog:
		var b: Vector3 = fm.get_meta("base")
		var ph: float = fm.get_meta("ph")
		fm.position = b + Vector3(sin(_now * 0.21 + ph) * 1.2, sin(_now * 0.33 + ph * 2.0) * 0.3, cos(_now * 0.17 + ph) * 0.8)
	for c in _corpses:
		var cp: LabPlayer3D = c
		cp.body.position = Vector3(randf_range(-0.03, 0.03), randf_range(-0.04, 0.02), randf_range(-0.03, 0.03))
	_animate_players(delta, bv)
	_move_hazards(delta, bv)
	_update_lanes()
	_place_camera(1.0 - exp(-2.2 * delta))
	_update_hud(delta)
	if st == St.RUN and NetworkManager.is_server():
		_server_tick(delta, bv)

func _animate_players(delta: float, bv: float) -> void:
	for id in players:
		var p: LabPlayer3D = players[id]
		if not p.alive or not vis_s.has(id):
			continue
		var done := finish_order.has(id)
		var prev: float = vis_s[id]
		var ns := lerpf(prev, float(s_of[id]), 1.0 - exp(-(6.0 if done else 14.0) * delta))
		vis_s[id] = ns
		var tx := _lane_x(lane_of[id]) + float(xo_of[id])
		if done:
			tx = float(xo_of[id])
		vis_x[id] = lerpf(float(vis_x[id]), tx, 1.0 - exp(-(4.0 if done else 10.0) * delta))
		p.position = _wpos(ns, float(vis_x[id]), -0.06)
		var cv: float = (ns - prev) / maxf(delta, 0.0001) + (0.0 if done else bv)
		climb_v[id] = lerpf(float(climb_v[id]), cv, 0.12)
		var yaw := PI
		if done:
			yaw = 0.0 if absf(float(s_of[id]) - ns) < 0.3 and absf(tx - float(vis_x[id])) < 0.3 else atan2(tx - float(vis_x[id]), -(float(s_of[id]) - ns))
		p.body.rotation.y = lerp_angle(p.body.rotation.y, yaw, 1.0 - exp(-10.0 * delta))
		if _now < float(act_until[id]):
			continue
		var a := p.body.anim
		if done:
			var moving := absf(float(s_of[id]) - ns) > 0.25 or absf(tx - float(vis_x[id])) > 0.25
			a.speed_scale = 1.0
			p.body.play_loop("Walk" if moving else "Dance")
			continue
		var v: float = climb_v[id]
		if v > 1.2:
			p.body.play_loop("Jog_Fwd")
			a.speed_scale = clampf(v / 1.7, 0.7, 1.5)
		elif v > 0.25:
			p.body.play_loop("Walk")
			a.speed_scale = clampf(v / 0.8, 0.7, 1.6)
		else:
			p.body.play_loop("Idle")
			a.speed_scale = 1.0

func _act(id: int, anim_name: String, dur: float, spd: float = 1.0) -> void:
	var p: LabPlayer3D = players[id]
	if not p.alive:
		return
	p.body.anim.speed_scale = 1.0
	p.body.play_action(anim_name, 0.06, spd)
	act_until[id] = _now + dur

func _update_lanes() -> void:
	var blink := fmod(_now, 0.3) < 0.15
	for l in LANES:
		var warn := false
		var rolling := false
		for hid in hazards:
			if int(hazards[hid].lane) == l:
				warn = true
				if clock - float(hazards[hid].t0) >= WARN:
					rolling = true
		var rm: StandardMaterial3D = _rail_mats[l]
		if rolling:
			blink = true
		rm.emission_energy_multiplier = (1.6 if blink else 0.35) if warn else 0.0
		if rolling:
			rm.emission_energy_multiplier = 0.45
		_signs[l].text = "!" if warn else SIGN_TXT[l]
		_signs[l].modulate = (Color(1.0, 0.15, 0.08) if blink else Color(0.6, 0.05, 0.03)) if warn else SIGN_COL[l]
		_sign_lights[l].light_color = Color(1.0, 0.12, 0.06) if warn else SIGN_COL[l]
		_warn_lights[l].light_energy = (3.5 if blink else 1.5) if warn else 0.0

func _update_hud(delta: float) -> void:
	_key_flash = maxf(0.0, _key_flash - delta)
	var me := local_player()
	if not me:
		return
	var id := me.peer_id
	if finish_order.has(id):
		_dist_label.text = "OUT  ·  #%d to the top" % (finish_order.find(id) + 1)
		_keys.text = ""
	elif me.alive:
		_dist_label.text = "%d m to the top" % int(ceil(maxf(0.0, LEN - float(vis_s.get(id, 0.0)))))
		var on := "8fe36a"
		var off := "4a4a40"
		var lc := on if _my_last != 0 else off
		var rc := on if _my_last != 1 else off
		if _key_flash > 0.0:
			lc = "ff3a28"
			rc = "ff3a28"
		_keys.text = "[center][color=#%s]◄ A[/color]      [color=#%s]D ►[/color][/center]" % [lc, rc] if st != St.DONE else ""
	else:
		_dist_label.text = "shredded"
		_keys.text = ""

func _input(event: InputEvent) -> void:
	if st != St.RUN or not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	var k := -1
	match ke.physical_keycode:
		KEY_A, KEY_LEFT:
			k = 0
		KEY_D, KEY_RIGHT:
			k = 1
		KEY_SPACE:
			k = 2
	if k < 0:
		return
	if k < 2:
		_my_last = -1 if k == _my_last else k
	if NetworkManager.is_server():
		_press(multiplayer.get_unique_id(), k)
	else:
		_rpc_press.rpc_id(1, k)

@rpc("any_peer", "reliable")
func _rpc_press(k: int) -> void:
	if NetworkManager.is_server():
		_press(multiplayer.get_remote_sender_id(), k)

func _press(id: int, k: int) -> void:
	if st != St.RUN or not players.has(id) or not players[id].alive or finish_order.has(id):
		return
	if k == 2:
		_space(id)
		return
	if clock < float(stun_until[id]) or clock - float(last_t[id]) < MIN_GAP:
		return
	last_t[id] = clock
	if int(last_k[id]) == k:
		last_k[id] = -1
		s_of[id] = float(s_of[id]) - STUMBLE_DS
		stun_until[id] = clock + STUMBLE_T
		_rpc_stumble.rpc(id)
		return
	last_k[id] = k
	s_of[id] = float(s_of[id]) + STEP

func _space(id: int) -> void:
	if clock < float(stun_until[id]):
		return
	if _shove(id):
		return
	var lk: int = last_k[id]
	var l: int = lane_of[id]
	var dir := -1 if lk == 0 else 1
	if lk < 0:
		dir = 1 if l < LANES / 2 else -1
	if l + dir < 0 or l + dir >= LANES:
		dir = -dir
	_hop(id, dir)

func _hop(id: int, dir: int) -> bool:
	var l: int = lane_of[id]
	var nl := l + dir
	if nl < 0 or nl >= LANES or clock < float(hop_ready[id]) or clock < float(stun_until[id]):
		return false
	hop_ready[id] = clock + HOP_CD
	lane_of[id] = nl
	xo_of[id] = -float(dir) * 2.0
	_relayout(nl)
	_relayout(l)
	_rpc_hop.rpc(id, nl, dir)
	return true

func _shove(id: int) -> bool:
	if clock < float(shove_ready[id]):
		return false
	var best := -1
	var best_d := SHOVE_RANGE
	for o in _runners():
		if o == id or int(lane_of[o]) != int(lane_of[id]):
			continue
		var d: float = absf(float(s_of[o]) - float(s_of[id]))
		if d < best_d:
			best_d = d
			best = o
	if best < 0:
		return false
	shove_ready[id] = clock + SHOVE_CD
	s_of[best] = float(s_of[best]) - SHOVE_DS
	stun_until[best] = clock + SHOVE_T
	last_k[best] = -1
	_rpc_shove.rpc(id, best)
	return true

@rpc("authority", "call_local", "reliable")
func _rpc_stumble(id: int) -> void:
	if not players.has(id):
		return
	_act(id, "Hit_Knockback", 0.5, 1.5)
	Fx.sfx("step", players[id].position, -2.0, 0.55)
	Fx.sfx("hit", players[id].position, -10.0, 1.4)
	if players[id].is_local_human():
		_key_flash = 0.4
		_my_last = -1

@rpc("authority", "call_local", "reliable")
func _rpc_hop(id: int, nl: int, dir: int) -> void:
	if not players.has(id):
		return
	lane_of[id] = nl
	_act(id, "Jump", 0.35, 1.6)
	Fx.sfx("whoosh", players[id].position, -6.0, 1.2)

@rpc("authority", "call_local", "reliable")
func _rpc_shove(a: int, v: int) -> void:
	if not players.has(a) or not players.has(v):
		return
	_act(a, "Punch_Cross", 0.45, 1.6)
	_act(v, "Hit_Knockback", 0.65, 1.2)
	Fx.sfx("hit", players[v].position, -2.0)
	Fx.shake(0.12)
	if players[v].is_local_human():
		_key_flash = 0.4
		_my_last = -1

@rpc("authority", "call_local", "reliable")
func _rpc_knock(id: int, kind: int) -> void:
	if not players.has(id):
		return
	var p: LabPlayer3D = players[id]
	_act(id, "Hit_Knockback", 0.85, 1.0)
	Fx.sfx("hit", p.position, 3.0, 0.7 if kind == 0 else 0.9)
	Fx.sparks(world, p.position + Vector3(0, 1.0, 0))
	Fx.shake(0.35)
	if p.is_local_human():
		_key_flash = 0.6
		_my_last = -1

func _server_tick(delta: float, bv: float) -> void:
	for id in _runners():
		s_of[id] = float(s_of[id]) - bv * delta
		if float(s_of[id]) < S_DEAD:
			_rpc_shred.rpc(id)
		elif float(s_of[id]) >= LEN:
			finish_order.append(id)
			_rpc_finish.rpc(id, finish_order.size())
	for id in _bot:
		if players[id].alive and not finish_order.has(id):
			_bot_tick(id, delta)
	_next_haz -= delta
	if _next_haz <= 0.0 and clock < TIME_LIMIT - 3.0:
		_spawn_hazard()
		_next_haz = lerpf(3.4, 1.7, clock / TIME_LIMIT) * randf_range(0.8, 1.2)
	for hid in hazards:
		var h: Dictionary = hazards[hid]
		if clock - float(h.t0) < WARN:
			continue
		for id in _runners():
			if int(lane_of[id]) == int(h.lane) and absf(float(s_of[id]) - float(h.s)) < HAZ_HIT and not (h.hit as Array).has(id):
				(h.hit as Array).append(id)
				s_of[id] = float(s_of[id]) - HAZ_DS
				stun_until[id] = clock + HAZ_T
				last_k[id] = -1
				_rpc_knock.rpc(id, int(h.kind))
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.05
		var ids := PackedInt32Array()
		var ss := PackedFloat32Array()
		var ls := PackedInt32Array()
		var xs := PackedFloat32Array()
		for id in players:
			ids.append(id)
			ss.append(float(s_of[id]))
			ls.append(int(lane_of[id]))
			xs.append(float(xo_of[id]))
		_rpc_state.rpc(ids, ss, ls, xs, maxf(0.0, TIME_LIMIT - clock))

@rpc("authority", "call_local", "unreliable_ordered")
func _rpc_state(ids: PackedInt32Array, ss: PackedFloat32Array, ls: PackedInt32Array, xs: PackedFloat32Array, left: float) -> void:
	if _timer_label:
		_timer_label.text = "%d s" % int(ceil(left))
	if NetworkManager.is_server():
		return
	for i in ids.size():
		var id: int = ids[i]
		if not players.has(id):
			continue
		s_of[id] = ss[i]
		lane_of[id] = ls[i]
		xo_of[id] = xs[i]

func _spawn_hazard() -> void:
	if hazards.size() >= 2:
		return
	var busy: Array = []
	for hid in hazards:
		if clock - float(hazards[hid].t0) < WARN + 1.5:
			busy.append(int(hazards[hid].lane))
	var free: Array = []
	for l in LANES:
		if not busy.has(l):
			free.append(l)
	if free.size() < 2:
		return
	var lane: int = free[randi() % free.size()]
	var r := _runners()
	if not r.is_empty() and randf() < 0.65:
		var tl: int = lane_of[r[randi() % r.size()]]
		if free.has(tl):
			lane = tl
	var kind := 0 if randf() < 0.6 else 1
	var v: float = randf_range(3.4, 4.5) if kind == 0 else randf_range(2.5, 3.4)
	_rpc_hazard.rpc(_next_haz_id, lane, kind, v)
	_next_haz_id += 1

@rpc("authority", "call_local", "reliable")
func _rpc_hazard(hid: int, lane: int, kind: int, v: float) -> void:
	hazards[hid] = {"lane": lane, "kind": kind, "v": v, "t0": clock, "s": HAZ_START, "node": null, "spin": null, "hit": []}
	Fx.sfx("buzzer", _wpos(LEN, _lane_x(lane), 2.0), -4.0, 0.8)
	Fx.sfx("beep", null, -12.0, 0.7)

func _make_hazard(kind: int) -> Array:
	var holder := Node3D.new()
	world.add_child(holder)
	var spin := Node3D.new()
	holder.add_child(spin)
	if kind == 0:
		var m := prop("barrel_03", Vector3.ZERO, 0.0, 1.0, spin)
		if m:
			m.rotation_degrees = Vector3(0, 0, 90)
			m.position = Vector3(0.465, 0, 0)
	else:
		var m := prop("old_military_crate", Vector3.ZERO, 0.0, 1.0, spin)
		if m:
			m.scale = Vector3(0.7, 1.6, 1.4)
			m.position = Vector3(0, -0.24, 0)
	return [holder, spin]

func _move_hazards(delta: float, bv: float) -> void:
	for hid in hazards.keys():
		var h: Dictionary = hazards[hid]
		var age := clock - float(h.t0)
		if age < WARN:
			continue
		if h.node == null:
			var made := _make_hazard(int(h.kind))
			h.node = made[0]
			h.spin = made[1]
			Fx.sfx("hit", _wpos(HAZ_START, _lane_x(int(h.lane)), 1.0), -4.0, 0.5)
		h.s = float(h.s) - (float(h.v) + bv) * delta
		var s: float = h.s
		var node: Node3D = h.node
		var spin: Node3D = h.spin
		var drop := maxf(0.0, 1.0 - (age - WARN) / 0.3)
		var r := 0.33 if int(h.kind) == 0 else 0.35
		var bounce := 0.0 if int(h.kind) == 0 else absf(sin(age * 7.0)) * 0.45
		node.position = _wpos(s, _lane_x(int(h.lane)), r + bounce + drop * drop * 2.5)
		node.rotation.x = deg_to_rad(ANG) if s < LEN else 0.0
		spin.rotation.x += (float(h.v) + bv) / r * delta * (1.0 if int(h.kind) == 0 else 0.45)
		if s < S_BOT - 0.4:
			var at := Vector3(_lane_x(int(h.lane)), ROLL_Y + 0.4, (ROLL_Z[0] + ROLL_Z[1]) * 0.5)
			Fx.sparks(world, at)
			Fx.sparks(world, at + Vector3(0.4, 0, 0))
			Fx.sfx("hit", at, 0.0, 0.45)
			Fx.sfx("explosion", at, -14.0, 1.8)
			Fx.shake(0.15)
			node.queue_free()
			hazards.erase(hid)

func _gore_decal(pos: Vector3, size: float) -> void:
	var d := Decal.new()
	d.texture_albedo = Fx._splat_tex
	d.size = Vector3(size, 3.0, size)
	d.modulate = Color(0.5, 0.02, 0.03)
	d.rotation.y = randf() * TAU
	world.add_child(d)
	d.global_position = pos

@rpc("authority", "call_local", "reliable")
func _rpc_shred(id: int) -> void:
	if not dead_order.has(id):
		dead_order.append(id)
	var p: LabPlayer3D = players[id]
	if not p.alive:
		return
	var x: float = p.position.x
	eliminate(id, "Death01")
	var l: int = lane_of[id]
	_relayout(l)
	Fx.sfx("buzzer", null, -8.0, 0.6)
	var nip := Vector3(x, ROLL_Y + 0.3, (ROLL_Z[0] + ROLL_Z[1]) * 0.5)
	var lx := clampf(x + randf_range(-0.5, 0.5), -HALF_W + 0.4, HALF_W - 0.4)
	var land := Vector3(lx, ROLL_Y + 0.42, nip.z + randf_range(-0.15, 0.15))
	var tw := create_tween()
	tw.tween_property(p, "position", nip, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		Fx.blood(world, nip + Vector3(0, 0.4, 0), 140)
		Fx.blood(world, nip + Vector3(0.3, 0.6, 0.3), 80)
		Fx.sparks(world, nip)
		Fx.sparks(world, nip + Vector3(-0.4, 0.1, 0))
		Fx.sfx("splat", nip, 4.0, 0.8)
		Fx.sfx("hit", nip, 2.0, 0.5)
		Fx.shake(0.95)
		_gore_decal(Vector3(x, 0.5, 0.2), 1.8)
		_bloody_rollers(x)
		_chunks(nip))
	tw.tween_property(p, "position", nip + Vector3(0, -0.5, 0.1), 0.25)
	tw.tween_property(p, "position", land + Vector3(0, 0.9, 0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "position", land, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		Fx.sfx("splat", land, 0.0, 0.7)
		Fx.blood(world, land + Vector3(0, 0.3, 0), 60)
		_gore_decal(land + Vector3(0, 1.0, 0.6), randf_range(2.0, 2.8))
		_corpses.append(p))
	var rt := create_tween()
	rt.tween_interval(0.5)
	rt.tween_property(p.body, "rotation:x", randf_range(-0.25, 0.25), 0.5)
	rt.parallel().tween_property(p.body, "rotation:y", PI * 0.5 + randf_range(-0.6, 0.6), 0.5)

func _bloody_rollers(x: float) -> void:
	var red := _plain(Color(0.35, 0.01, 0.02), 0.25, 0.1)
	for rn in _rollers:
		for i in 5:
			var ang := randf() * TAU
			var bx := box(Vector3(randf_range(0.15, 0.4), 0.05, 0.18), Vector3(x + randf_range(-0.5, 0.5), cos(ang) * ROLL_R, sin(ang) * ROLL_R), red, rn)
			bx.rotation.x = ang

func _chunks(at: Vector3) -> void:
	var meat := _plain(Color(0.4, 0.03, 0.03), 0.35)
	for i in 9:
		var c := box(Vector3(randf_range(0.08, 0.22), randf_range(0.06, 0.16), randf_range(0.08, 0.2)), at, meat, world)
		var cz := randf_range(3.2, 6.0)
		var cx := at.x + randf_range(-2.0, 2.0)
		var end := Vector3(cx, _pile_y(cx, cz) + 0.1, cz)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(c, "position:x", end.x, 0.7)
		tw.tween_property(c, "position:z", end.z, 0.7)
		tw.tween_property(c, "rotation", Vector3(randf() * 8.0, randf() * 8.0, 0), 0.7)
		var up := create_tween()
		up.tween_property(c, "position:y", at.y + randf_range(1.5, 3.0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		up.tween_property(c, "position:y", end.y, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

@rpc("authority", "call_local", "reliable")
func _rpc_finish(id: int, place: int) -> void:
	if not finish_order.has(id):
		finish_order.append(id)
	var side := -1.0 if place % 2 == 1 else 1.0
	s_of[id] = LEN + 1.6 + float((place - 1) / 2) * 1.1
	xo_of[id] = side * (HALF_W + 1.4)
	_relayout(int(lane_of[id]))
	var p: LabPlayer3D = players[id]
	Fx.sfx("win", p.position, -6.0)
	if p.is_local_human():
		_big_local("TOP #%d" % place, "8fe36a", 1.4)

func _big_local(text: String, hex: String, hold: float) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", Color(hex))
	_big.modulate.a = 1.0
	if hold > 0.0:
		var tw := create_tween()
		tw.tween_interval(hold)
		tw.tween_property(_big, "modulate:a", 0.0, 0.4)

@rpc("authority", "call_local", "reliable")
func _rpc_big(text: String, hex: String, hold: float) -> void:
	_big_local(text, hex, hold)

@rpc("authority", "call_local", "reliable")
func _rpc_start() -> void:
	st = St.RUN
	clock = 0.0
	_big_local("CLIMB!", "8fe36a", 0.7)
	Fx.sfx("beep", null, -4.0, 1.4)
	Fx.sfx("hum", null, -8.0, 0.5)
	var th := create_tween()
	th.tween_interval(6.0)
	th.tween_property(_hint, "modulate:a", 0.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_end(timeout: bool) -> void:
	st = St.DONE
	_big_local("TIME!" if timeout else "SHAFT CLEAR", "e2c84b", 0.0)
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
	living.sort_custom(func(a, b): return float(s_of[a]) > float(s_of[b]))
	out.append_array(living)
	for i in range(dead_order.size() - 1, -1, -1):
		if not out.has(dead_order[i]):
			out.append(dead_order[i])
	return out

func _lane_eta(l: int, s: float, known_after: float) -> float:
	var best := INF
	var bv := _belt()
	for hid in hazards:
		var h: Dictionary = hazards[hid]
		var age := clock - float(h.t0)
		if int(h.lane) != l or age < known_after:
			continue
		var hs: float = h.s
		if hs < s - 0.5:
			continue
		best = minf(best, maxf(0.0, hs - s) / (float(h.v) + bv) + maxf(0.0, WARN - age))
	return best

func _bot_tick(id: int, delta: float) -> void:
	var b: Dictionary = _bot[id]
	var s: float = s_of[id]
	var cur: int = lane_of[id]
	if clock < float(stun_until[id]):
		b.next = maxf(float(b.next), float(stun_until[id]) - clock + randf_range(0.08, 0.3))
	b.think = float(b.think) - delta
	if float(b.think) <= 0.0:
		b.think = randf_range(0.1, 0.2)
		var react: float = b.react
		var eta := _lane_eta(cur, s, react)
		if eta < 1.7 and randf() > float(b.greed):
			var best := cur
			var best_eta := eta
			for dl in [-1, 1]:
				var nl: int = cur + dl
				if nl < 0 or nl >= LANES:
					continue
				var e := _lane_eta(nl, s, react)
				if e > best_eta + 0.4:
					best_eta = e
					best = nl
			if best != cur:
				_hop(id, best - cur)
		elif clock > 2.5 and randf() < float(b.aggro) * 0.07:
			for o in _runners():
				if o != id and int(lane_of[o]) == cur and float(s_of[o]) - s > -0.3 and float(s_of[o]) - s < SHOVE_RANGE * 0.9:
					_shove(id)
					break
		elif randf() < float(b.aggro) * 0.04:
			for o in _runners():
				if o == id:
					continue
				var ol: int = lane_of[o]
				var ds: float = float(s_of[o]) - s
				if absf(ol - cur) == 1 and ds > 0.0 and ds < 1.0 and _lane_eta(ol, s, 0.0) > 3.0:
					_hop(id, ol - cur)
					break
	b.next = float(b.next) - delta
	if float(b.next) <= 0.0:
		var rate: float = float(b.rate) * (1.0 + 0.12 * sin(clock * 1.3 + float(b.ph)))
		b.next = (1.0 / rate) * randf_range(0.8, 1.2)
		var lk: int = last_k[id]
		var k: int = randi() % 2 if lk < 0 else 1 - lk
		if lk >= 0 and randf() < float(b.fumble):
			k = lk
		_press(id, k)
