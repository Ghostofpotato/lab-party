extends ArenaMinigame3D
## Firearm Factory: gun parts (barrel, grip, slide, magazine) ride the conveyors and
## litter the factory floor. Walk over a part to grab it; with all four, hold SPACE at
## a workbench to assemble a pistol. It auto-aims at the nearest rival in front and
## holds one bullet: SPACE fires, a hit kills, a miss sends you back to collecting.
## Unarmed, SPACE punches a rival and knocks a part out of them.
## Most kills wins, then survivors, then whoever died last. Ends at one survivor or 50 s.

const TIME_LIMIT: float = 50.0
const START_DELAY: float = 1.2
const PART_NAMES: Array[String] = ["BARREL", "GRIP", "SLIDE", "MAG"]
const PART_COLORS: Array[Color] = [Color("ff8a2a"), Color("3ad7ff"), Color("ff4fc8"), Color("8dff4a")]
const FULL: int = 15
const PART_SCALE: float = 3.6
const BELT_Z: float = 5.0
const BELT_TOP: float = 0.52
const BELT_SPEED: float = 1.15
const BELTS: Array = [[-2.0, 6.7, 1.0], [9.3, 18.0, -1.0]]
const GAP_X: float = 8.0
const FLOOR_PARTS: int = 7
const PICK_R: float = 0.85
const BELT_PICK_R: float = 1.08
const BENCH_R: float = 0.95
const ASSEMBLE_T: float = 1.5
const PUNCH_R: float = 1.35
const PUNCH_CD: float = 0.9
const SHOT_RANGE: float = 13.0
const SHOT_CONE: float = 0.62
const AIM_CONE: float = 1.25

const SLOT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;
uniform vec4 owned = vec4(0.0);
uniform vec3 c0 : source_color;
uniform vec3 c1 : source_color;
uniform vec3 c2 : source_color;
uniform vec3 c3 : source_color;
uniform float alpha = 1.0;
float rect(vec2 p, vec2 b) { vec2 d = abs(p) - b; return max(d.x, d.y); }
float icon(int s, vec2 p) {
	if (s == 0) return min(rect(p, vec2(0.34, 0.07)), rect(p - vec2(0.3, 0.0), vec2(0.06, 0.12)));
	if (s == 1) return rect(vec2(p.x + p.y * 0.4, p.y), vec2(0.1, 0.3));
	if (s == 2) return min(rect(p - vec2(0.0, 0.06), vec2(0.36, 0.11)), rect(p - vec2(-0.16, -0.1), vec2(0.09, 0.06)));
	return rect(p, vec2(0.1, 0.32));
}
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float fx = UV.x * 4.0;
	int s = int(clamp(floor(fx), 0.0, 3.0));
	vec2 p = vec2(fract(fx) - 0.5, 0.5 - UV.y);
	vec3 col = s == 0 ? c0 : (s == 1 ? c1 : (s == 2 ? c2 : c3));
	float own = owned[s];
	float bx = rect(p, vec2(0.42));
	vec3 rgb = vec3(0.03);
	float a = step(bx, 0.0) * 0.75;
	if (icon(s, p) < 0.0) { rgb = own > 0.5 ? col * 1.5 : vec3(0.28); a = 1.0; }
	if (abs(bx + 0.03) < 0.03) { rgb = own > 0.5 ? col : vec3(0.3); a = 1.0; }
	ALBEDO = rgb;
	ALPHA = a * alpha;
}
"""

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;
uniform float progress = 0.0;
uniform vec3 col : source_color;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	float ang = atan(p.x, -p.y);
	float f = ang < 0.0 ? ang / 6.2832 + 1.0 : ang / 6.2832;
	float ring = step(abs(r - 0.38), 0.075);
	float fill = step(f, progress);
	ALBEDO = mix(vec3(0.1), col * 1.4, fill);
	ALPHA = ring * (0.55 + 0.45 * fill);
}
"""

class ArmPose extends SkeletonModifier3D:
	var poses: Dictionary = {}
	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for b in poses:
			sk.set_bone_pose_rotation(b, poses[b])

static var _pose_cache: Dictionary = {}

var benches: Array = []
var parts: Dictionary = {}
var inv: Dictionary = {}
var armed: Dictionary = {}
var kills: Dictionary = {}
var progress: Dictionary = {}
var holding: Dictionary = {}
var punch_cd: Dictionary = {}
var stun: Dictionary = {}
var aim_t: Dictionary = {}
var react: Dictionary = {}
var elim_order: Array = []
var guns: Dictionary = {}
var slot_mats: Dictionary = {}
var ring_nodes: Dictionary = {}
var _templates: Array = []
var _belt_mat: StandardMaterial3D
var _next_pid: int = 1
var _clock: float = 0.0
var _running: bool = false
var _done: bool = false
var _space_down: bool = false
var _belt_t: float = 0.0
var _floor_t: float = 0.0
var _hud_slots: Array[Panel] = []
var _hud_status: Label
var _hud_board: Label
var _hud_time: Label
var _hud_help: Label

func begin() -> void:
	setup_arena(false)
	build_chamber("concrete_floor_worn_001", "factory_brick", "rusty_metal")
	env.tonemap_exposure = 0.95
	env.ambient_light_energy = 0.5
	env.fog_density = 0.012
	camera.fov = 42.0
	camera.position = Vector3(W * 0.5, 8.6, D + 4.0)
	camera.look_at(Vector3(W * 0.5, 0.0, D * 0.5 - 0.6), Vector3.UP)
	_build_templates()
	_build_factory()
	spawn_players(_spawns())
	for id in players:
		players[id].bounds = AABB(Vector3(1.0, -5.0, 0.4), Vector3(W - 2.0, 20.0, D - 0.9))
		inv[id] = 0
		armed[id] = false
		kills[id] = 0
		progress[id] = 0.0
		holding[id] = false
		punch_cd[id] = 0.0
		stun[id] = 0.0
		aim_t[id] = 0.0
		react[id] = randf_range(0.5, 1.0)
		players[id].bot_brain = _bot_brain.bind(id)
		_add_overhead(id)
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _spawns() -> Array:
	var pts: Array = [Vector3(4.5, 0, 2.8), Vector3(11.5, 0, 7.3), Vector3(11.5, 0, 2.8), Vector3(4.5, 0, 7.3),
		Vector3(8.0, 0, 2.6), Vector3(8.0, 0, 7.6), Vector3(6.0, 0, 9.0), Vector3(10.0, 0, 9.0)]
	var a: Array = []
	for i in NetworkManager.players.size():
		a.append(pts[i % pts.size()])
	return a

func _build_templates() -> void:
	var src: Node3D = load(PH_MOD + "service_pistol/service_pistol.gltf").instantiate()
	world.add_child(src)
	var names := ["", "service_pistol_pistol_a", "service_pistol_slide_a", "service_pistol_magazine_loaded"]
	for t in 4:
		var mesh: Mesh
		var xf := Transform3D()
		if t == 0:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.019
			cm.bottom_radius = 0.019
			cm.height = 0.15
			cm.radial_segments = 12
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.3, 0.3, 0.32)
			m.metallic = 0.9
			m.roughness = 0.35
			cm.material = m
			mesh = cm
			xf = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO)
		else:
			var mi: MeshInstance3D = src.find_child(names[t], true, false)
			mesh = mi.mesh
			xf = mi.global_transform
		var center := (xf * mesh.get_aabb()).get_center()
		var final := Transform3D(Basis().scaled(Vector3.ONE * PART_SCALE), Vector3.ZERO) * Transform3D(Basis(), -center) * xf
		_templates.append([mesh, final])
	src.queue_free()

func _build_factory() -> void:
	var fac := Node3D.new()
	fac.name = "Factory"
	world.add_child(fac)
	var hz := _hazard_mat()
	var body := mat("green_metal_rust", 0.7, Color(0.7, 0.72, 0.66))
	var steel := mat("rusty_metal_02", 1.2)
	_belt_mat = mat("rubber_tiles", 1.6, Color(0.42, 0.4, 0.38)).duplicate()
	box(Vector3(W + 6.0, 0.02, D + 6.0), Vector3(W * 0.5, 0.005, D * 0.5), mat("concrete_floor_worn_001", 0.3, Color(0.52, 0.47, 0.4)), fac)
	box(Vector3(W + 1.0, 0.03, 2.6), Vector3(W * 0.5, 0.015, BELT_Z), mat("metal_grate_rusty", 0.7, Color(0.6, 0.58, 0.54)), fac)
	for b in BELTS:
		var x0: float = b[0]
		var x1: float = b[1]
		var dirx: float = b[2]
		var len := x1 - x0
		var cx := (x0 + x1) * 0.5
		box(Vector3(len, 0.45, 1.15), Vector3(cx, 0.225, BELT_Z), body, fac, true)
		box(Vector3(len - 0.1, 0.06, 0.9), Vector3(cx, 0.48, BELT_Z), _belt_mat, fac)
		for s in [-1.0, 1.0]:
			box(Vector3(len, 0.16, 0.1), Vector3(cx, 0.55, BELT_Z + s * 0.52), steel, fac)
			box(Vector3(len, 0.02, 0.24), Vector3(cx, 0.03, BELT_Z + s * 0.78), hz, fac)
			box(Vector3(len, 0.1, 0.06), Vector3(cx, 0.3, BELT_Z + s * 0.6), hz, fac)
		var x := x0 + 0.6
		while x < x1 - 0.3:
			_roller(Vector3(x, 0.47, BELT_Z), steel, fac)
			x += 0.9
		var start := x0 + 0.55 if dirx > 0.0 else x1 - 0.55
		var end := x1 - 0.25 if dirx > 0.0 else x0 + 0.25
		box(Vector3(1.1, 1.7, 1.4), Vector3(start, 0.85, BELT_Z), mat("green_metal_rust", 0.7, Color(0.45, 0.47, 0.42)), fac)
		box(Vector3(1.25, 0.2, 1.55), Vector3(start, 1.75, BELT_Z), steel, fac)
		box(Vector3(0.9, 0.5, 0.95), Vector3(start + dirx * 0.3, 0.75, BELT_Z), mat("rusty_metal", 1.0, Color(0.2, 0.19, 0.18)), fac)
		box(Vector3(0.5, 0.75, 1.2), Vector3(end, 0.375, BELT_Z), mat("rusty_metal", 0.8), fac)
		box(Vector3(0.42, 0.04, 1.1), Vector3(end, 0.76, BELT_Z), mat("rusty_metal", 0.8, Color(0.12, 0.1, 0.09)), fac)
		var warn := OmniLight3D.new()
		warn.light_color = Color(1.0, 0.45, 0.1)
		warn.light_energy = 1.2
		warn.omni_range = 2.6
		fac.add_child(warn)
		warn.position = Vector3(start + dirx * 1.2, 1.4, BELT_Z + 0.9)
	benches = [
		{"pos": Vector3(3.4, 0, -0.45), "yaw": 0.0, "zone": Vector3(3.4, 0, 0.85)},
		{"pos": Vector3(12.6, 0, -0.45), "yaw": 0.0, "zone": Vector3(12.6, 0, 0.85)},
		{"pos": Vector3(1.35, 0, 7.4), "yaw": 90.0, "zone": Vector3(2.6, 0, 7.4)},
		{"pos": Vector3(W - 1.35, 0, 7.4), "yaw": -90.0, "zone": Vector3(W - 2.6, 0, 7.4)},
	]
	for bn in benches:
		_bench(bn, fac, hz)
	var deco := [["drill_press_01", 1.0, -0.7, 10, 1.3], ["old_drill_press", 15.2, -0.8, -20, 1.3], ["tool_cart", 8.0, -0.6, 0, 1.2],
		["portable_welding_cart", 6.3, -0.8, 15, 1.2], ["steel_frame_shelves_03", 9.9, -1.4, 0, 1.0], ["old_military_compressor", -1.6, 3.6, 0, 1.15],
		["portable_generator", W + 1.5, 3.4, 90, 1.15], ["steel_frame_shelves_02", -1.8, 10.6, 90, 1.15], ["barrel_03", -0.9, 9.9, 0, 1.15],
		["barrel_03", -1.5, 9.2, 40, 1.15], ["barrel_03", W + 0.9, 10.1, 30, 1.15], ["wooden_crate_02", W + 1.0, 5.9, 10, 1.15],
		["wooden_crate_01", -1.0, 5.8, -15, 1.15], ["wooden_military_crate", -1.1, 1.8, 90, 1.2], ["wooden_military_crate", -1.1, 1.8, 80, 1.2],
		["wooden_military_crate", W + 1.1, 1.6, 90, 1.2], ["ammo_box", W + 1.0, 2.6, 30, 1.6], ["metal_toolbox", 4.6, -0.9, 10, 1.4],
		["cardboard_box_01", 6.6, D + 0.9, 20, 1.15], ["plastic_crate_01", 9.4, D + 1.0, -10, 1.6], ["metal_jerrycan", 4.2, D + 0.8, 70, 1.15],
		["can_rusted", 11.8, D + 0.7, 0, 1.4], ["propane_tank", 13.4, D + 1.0, 0, 1.15], ["sledgehammer_01", 2.0, D + 0.8, 0, 1.2]]
	var stack := 0.0
	for d in deco:
		var y := 0.0
		if d[0] == "wooden_military_crate" and d[1] < 0.0:
			y = stack
			stack += 0.56
		var n := prop(d[0], Vector3(d[1], y, d[2]), d[3], d[4], fac)
		if n and d[0] == "sledgehammer_01":
			n.rotation_degrees = Vector3(0, 30, 80)
			n.position.y = 0.12
	prop("modular_pipes", Vector3(W * 0.5, 1.6, -2.75), 0.0, 1.4, fac)
	prop("modular_pipes", Vector3(W * 0.5 + 6.0, 1.6, -2.75), 0.0, 1.4, fac)
	prop("large_iron_gate", Vector3(-2.75, 0.0, 5.0), 90.0, 1.3, fac)
	for lp in [Vector3(W * 0.5, 7.0, 2.0), Vector3(W * 0.5, 7.0, 8.0)]:
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.8, 0.55)
		sp.light_energy = 7.0
		sp.spot_range = 12.0
		sp.spot_angle = 50.0
		sp.shadow_enabled = true
		fac.add_child(sp)
		sp.position = lp
		sp.rotation_degrees.x = -90.0
	_grime(fac)

func _roller(pos: Vector3, m: Material, parent: Node) -> void:
	var r := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.07
	cm.height = 1.08
	r.mesh = cm
	r.material_override = m
	r.rotation_degrees.x = 90.0
	r.position = pos
	parent.add_child(r)

func _bench(bn: Dictionary, parent: Node, hz: Material) -> void:
	var p: Vector3 = bn.pos
	var yaw: float = bn.yaw
	var zone: Vector3 = bn.zone
	var fwd := (zone - p).normalized()
	var side := fwd.cross(Vector3.UP)
	var bench := Node3D.new()
	parent.add_child(bench)
	bench.position = p
	bench.rotation_degrees.y = yaw
	var solid := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.2, 1.0, 1.0)
	cs.shape = sh
	cs.position.y = 0.5
	solid.add_child(cs)
	bench.add_child(solid)
	var wood := mat("worn_planks", 1.2, Color(0.8, 0.7, 0.6))
	var steel := mat("rusty_metal_02", 1.5)
	box(Vector3(2.2, 0.09, 1.0), Vector3(0, 0.88, 0), wood, bench)
	box(Vector3(2.0, 0.05, 0.85), Vector3(0, 0.25, 0), mat("old_planks_02", 1.0, Color(0.6, 0.55, 0.5)), bench)
	for lx in [-1.0, 1.0]:
		for lz in [-0.42, 0.42]:
			box(Vector3(0.08, 0.84, 0.08), Vector3(lx, 0.42, lz), steel, bench)
	box(Vector3(2.1, 0.12, 0.06), Vector3(0, 0.78, 0.47), steel, bench)
	prop("bench_vice_01", p + Vector3(0, 0.93 + 0.14, 0) + side * 0.7 + fwd * 0.3, yaw + 90.0, 1.6, parent)
	prop("metal_toolbox", p + Vector3(0, 0.27, 0) - side * 0.5, yaw + 8.0, 1.5, parent)
	prop("pipe_wrench", p + Vector3(0, 0.93, 0) + side * 0.05 - fwd * 0.2, yaw + 60.0, 1.4, parent)
	var frame: Node3D = Node3D.new()
	parent.add_child(frame)
	frame.position = p + Vector3(0, 0.95, 0) - side * 0.5
	frame.rotation_degrees = Vector3(-90.0, yaw + 25.0, 0.0)
	var t: Array = _templates[1]
	var mi := MeshInstance3D.new()
	mi.mesh = t[0]
	mi.transform = Transform3D(Basis().scaled(Vector3.ONE * (1.0 / PART_SCALE) * 1.4), Vector3.ZERO) * t[1]
	frame.add_child(mi)
	var pad := box(Vector3(1.9, 0.02, 1.5), zone + Vector3(0, 0.02, 0) + fwd * 0.05, mat("blue_metal_plate", 0.8, Color(0.55, 0.55, 0.5)), parent)
	pad.rotation_degrees.y = yaw
	for s in [-1.0, 1.0]:
		var ln := box(Vector3(0.14, 0.03, 1.5), zone + Vector3(0, 0.03, 0) + fwd * 0.05 + side * s * 0.95, hz, parent)
		ln.rotation_degrees.y = yaw
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.6)
	l.light_energy = 2.2
	l.omni_range = 3.2
	parent.add_child(l)
	l.position = zone + Vector3(0, 2.2, 0) - fwd * 0.4

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
			img.set_pixel(x, y, Color(1, 1, 1, clampf((v - 0.25) * 2.0, 0.0, 0.85)))
	var tex := ImageTexture.create_from_image(img)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 16:
		var d := Decal.new()
		d.texture_albedo = tex
		var sz := rng.randf_range(1.2, 3.2)
		d.size = Vector3(sz, 1.0, sz * rng.randf_range(0.6, 1.0))
		d.modulate = Color(0.12, 0.1, 0.07) if i % 3 != 0 else Color(0.25, 0.17, 0.08)
		d.rotation.y = rng.randf() * TAU
		parent.add_child(d)
		d.position = Vector3(rng.randf_range(-1.0, W + 1.0), 0.1, rng.randf_range(-1.0, D + 1.5))

func _hazard_mat() -> StandardMaterial3D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.045
	noise.seed = 3
	for y in n:
		for x in n:
			var stripe := int(floor(float(x + y) / 16.0)) % 2
			var g := 0.72 + noise.get_noise_2d(x, y) * 0.4
			var c := Color(0.82, 0.6, 0.08) if stripe == 0 else Color(0.06, 0.06, 0.05)
			img.set_pixel(x, y, Color(c.r * g, c.g * g, c.b * g))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.9
	return m

func _add_overhead(id: int) -> void:
	var p: LabPlayer3D = players[id]
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SLOT_SHADER
	sm.shader = sh
	for i in 4:
		sm.set_shader_parameter("c%d" % i, PART_COLORS[i])
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.88, 0.22)
	q.mesh = qm
	q.material_override = sm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.position = Vector3(0, LabPlayer3D.HEIGHT + 0.3, 0)
	p.add_child(q)
	slot_mats[id] = sm
	var rm := ShaderMaterial.new()
	var rs := Shader.new()
	rs.code = RING_SHADER
	rm.shader = rs
	rm.set_shader_parameter("col", Color("ffd34a"))
	var r := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(1.1, 1.1)
	r.mesh = rq
	r.material_override = rm
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.position = Vector3(0, 0.9, 0)
	r.visible = false
	p.add_child(r)
	ring_nodes[id] = r

func _build_hud() -> void:
	hud_title("FIREARM FACTORY  ·  build a gun, shoot a rival")
	_hud_help = Label.new()
	_hud_help.text = "WASD move  ·  walk over parts  ·  hold SPACE at a bench to assemble  ·  SPACE shoot / punch"
	_hud_help.position = Vector2(16, 42)
	_style_label(_hud_help, 16, Color("e8e2c8"))
	hud.add_child(_hud_help)
	_hud_time = Label.new()
	_hud_time.position = Vector2(560, 10)
	_style_label(_hud_time, 26, Color("ffd34a"))
	hud.add_child(_hud_time)
	_hud_board = Label.new()
	_hud_board.position = Vector2(930, 12)
	_style_label(_hud_board, 16, Color("e8e2c8"))
	hud.add_child(_hud_board)
	var row := HBoxContainer.new()
	row.position = Vector2(396, 578)
	row.add_theme_constant_override("separation", 8)
	hud.add_child(row)
	for i in 4:
		var pnl := Panel.new()
		pnl.custom_minimum_size = Vector2(84, 30)
		var lb := Label.new()
		lb.text = PART_NAMES[i]
		lb.set_anchors_preset(Control.PRESET_FULL_RECT)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_style_label(lb, 15, Color.WHITE)
		pnl.add_child(lb)
		row.add_child(pnl)
		_hud_slots.append(pnl)
	_hud_status = Label.new()
	_hud_status.position = Vector2(396, 548)
	_style_label(_hud_status, 18, Color("ffd34a"))
	hud.add_child(_hud_status)
	_refresh_hud()

func _style_label(l: Label, size: int, c: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)

func _refresh_hud() -> void:
	var me := multiplayer.get_unique_id()
	var mask: int = inv.get(me, 0)
	for i in 4:
		var sb := StyleBoxFlat.new()
		var own := mask & (1 << i) != 0
		sb.bg_color = PART_COLORS[i].darkened(0.35) if own else Color(0.05, 0.05, 0.05, 0.75)
		sb.border_color = PART_COLORS[i] if own else Color(0.3, 0.3, 0.3)
		sb.set_border_width_all(2)
		_hud_slots[i].add_theme_stylebox_override("panel", sb)
	if armed.get(me, false):
		_hud_status.text = "ARMED  ·  face a rival, SPACE to fire (one bullet)"
	elif mask == FULL:
		_hud_status.text = "ALL PARTS  ·  stand on a bench pad, hold SPACE"
	else:
		_hud_status.text = "collect the parts  ·  SPACE punches"
	var ids: Array = players.keys()
	ids.sort_custom(func(a, b): return kills[a] > kills[b])
	var lines: Array = []
	for id in ids:
		var p: LabPlayer3D = players[id]
		lines.append("%s%s  %d" % ["" if p.alive else "† ", p.display_name, kills[id]])
	_hud_board.text = "KILLS\n" + "\n".join(lines)
	for id in slot_mats:
		var m: int = inv.get(id, 0)
		slot_mats[id].set_shader_parameter("owned", Vector4(m & 1, (m >> 1) & 1, (m >> 2) & 1, (m >> 3) & 1))
		slot_mats[id].set_shader_parameter("alpha", 0.0 if armed.get(id, false) or not players[id].alive else 1.0)

func _process(delta: float) -> void:
	_clock += delta
	if _belt_mat:
		_belt_mat.uv1_offset.x = fmod(_belt_mat.uv1_offset.x - delta * BELT_SPEED * 2.2, 1.0)
	for pid in parts:
		var pr: Dictionary = parts[pid]
		var n: Node3D = pr.node
		if pr.belt >= 0:
			n.position.x += float(BELTS[pr.belt][2]) * BELT_SPEED * delta
		var h: Node3D = pr.holder
		h.rotation = Vector3(-1.2, _clock * 1.6 + float(pid), 0.0)
		h.position.y = 0.22 + sin(_clock * 3.0 + float(pid)) * 0.05
	for id in guns:
		_update_gun(id)
	if _hud_time:
		var left := clampf(TIME_LIMIT - (_clock - START_DELAY), 0.0, TIME_LIMIT)
		_hud_time.text = "%d" % ceili(left)
		_hud_help.modulate.a = clampf(9.0 - _clock, 0.0, 1.0)
	var lp := local_player()
	if lp and lp.alive and _clock > START_DELAY:
		var down := Input.is_physical_key_pressed(KEY_SPACE)
		if down != _space_down:
			_space_down = down
			if multiplayer.is_server():
				_req_hold(down)
			else:
				_req_hold.rpc_id(1, down)

func _fwd(p: LabPlayer3D) -> Vector3:
	return Vector3(sin(p._target_yaw), 0.0, cos(p._target_yaw))

func _aim_target(id: int, cone: float) -> int:
	var p: LabPlayer3D = players[id]
	var f := _fwd(p)
	var best := -1
	var best_d := SHOT_RANGE
	for o in alive_ids():
		if o == id:
			continue
		var to: Vector3 = players[o].position - p.position
		to.y = 0.0
		var d := to.length()
		if d > best_d or d < 0.05:
			continue
		if acos(clampf(f.dot(to / d), -1.0, 1.0)) > cone:
			continue
		best_d = d
		best = o
	return best

func _update_gun(id: int) -> void:
	var g: Dictionary = guns[id]
	var p: LabPlayer3D = players[id]
	var laser: MeshInstance3D = g.laser
	if not p.alive or g.fired:
		laser.visible = false
		return
	if p.is_multiplayer_authority() and p.velocity.length() < 0.3:
		var ft := _aim_target(id, AIM_CONE)
		if ft != -1:
			p.face(players[ft].position - p.position)
	var t := _aim_target(id, SHOT_CONE)
	var mod: ArmPose = g.mod
	mod.poses = _arm_pose("Pistol_Aim_Neutral" if t != -1 else "Pistol_Idle", p.body.skeleton)
	var f := Vector3(sin(p.body.rotation.y), 0.0, cos(p.body.rotation.y))
	var att: BoneAttachment3D = g.att
	var a := att.global_position + f * 0.32 + Vector3(0, 0.07, 0)
	var b: Vector3 = players[t].position + Vector3(0, 1.1, 0) if t != -1 else a + f * 3.0
	laser.visible = true
	var len := a.distance_to(b)
	laser.position = (a + b) * 0.5
	if len > 0.05:
		laser.look_at(b, Vector3.UP)
	laser.scale = Vector3(1.0, 1.0, len)
	var lm: StandardMaterial3D = laser.material_override
	lm.albedo_color = Color(1.0, 0.1, 0.05, 0.85 if t != -1 else 0.35)

func _arm_pose(anim_name: String, sk: Skeleton3D) -> Dictionary:
	var key := "%s|%d" % [anim_name, sk.get_bone_count()]
	if _pose_cache.has(key):
		return _pose_cache[key]
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
	_pose_cache[key] = d
	return d

func _give_gun(id: int) -> void:
	var p: LabPlayer3D = players[id]
	var sk := p.body.skeleton
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	sk.add_child(att)
	var g: Node3D = load(PH_MOD + "service_pistol/service_pistol.gltf").instantiate()
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm.ends_with("_b") or nm.contains("magazine") or nm.contains("bullet"):
			mi.visible = false
	att.add_child(g)
	var gb := Basis(Vector3(0.03, 0.97, -0.24), Vector3(-0.03, 0.24, 0.97), Vector3(1.0, -0.02, 0.03)).orthonormalized()
	g.transform = Transform3D(gb * Basis.from_scale(Vector3.ONE * 1.9), Vector3(0.0, 0.068, 0.015))
	var mod := ArmPose.new()
	sk.add_child(mod)
	mod.poses = _arm_pose("Pistol_Idle", sk)
	var laser := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.018, 0.018, 1.0)
	laser.mesh = bm
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.albedo_color = Color(1.0, 0.1, 0.05, 0.6)
	laser.material_override = lm
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(laser)
	guns[id] = {"att": att, "mod": mod, "laser": laser, "fired": false}

func _remove_gun(id: int) -> void:
	if not guns.has(id):
		return
	var g: Dictionary = guns[id]
	for k in ["att", "mod", "laser"]:
		var n: Node = g[k]
		if is_instance_valid(n):
			n.queue_free()
	guns.erase(id)

func _spawn_part_local(pid: int, type: int, pos: Vector3, belt: int) -> void:
	var root := Node3D.new()
	world.add_child(root)
	root.position = pos
	var holder := Node3D.new()
	root.add_child(holder)
	var t: Array = _templates[type]
	var mi := MeshInstance3D.new()
	mi.mesh = t[0]
	mi.transform = t[1]
	holder.add_child(mi)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.37
	tm.rings = 24
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = PART_COLORS[type] * 1.6
	ring.material_override = rm
	ring.scale = Vector3(1.0, 0.25, 1.0)
	ring.position.y = 0.04
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var l := OmniLight3D.new()
	l.light_color = PART_COLORS[type]
	l.light_energy = 1.4
	l.omni_range = 1.4
	l.position.y = 0.45
	root.add_child(l)
	parts[pid] = {"type": type, "node": root, "holder": holder, "belt": belt, "born": _clock}

func _run() -> void:
	for i in FLOOR_PARTS:
		_server_spawn(_scarce_type(), _free_spot(), -1)
	for bi in 2:
		var b: Array = BELTS[bi]
		for k in 3:
			var x: float = lerpf(1.0, 6.0, k / 2.0) if bi == 0 else lerpf(10.0, 15.0, k / 2.0)
			_server_spawn(_scarce_type(), Vector3(x, BELT_TOP, BELT_Z), bi)
	await get_tree().create_timer(START_DELAY).timeout
	_running = true
	var t := 0.0
	while alive_ids().size() > 1 and t < TIME_LIMIT:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	_running = false
	await get_tree().create_timer(1.0).timeout
	if not _done:
		_done = true
		finished.emit(_placement())

func _placement() -> Array:
	var ids: Array = players.keys()
	ids.sort_custom(func(a, b): return _rank(a) > _rank(b))
	return ids

func _rank(id: int) -> float:
	var r: float = float(kills.get(id, 0)) * 1000.0
	if players[id].alive:
		return r + 500.0
	return r + float(elim_order.find(id))

func _scarce_type() -> int:
	var count := [0, 0, 0, 0]
	for pid in parts:
		count[parts[pid].type] += 1
	var best: Array = []
	var lo: int = count.min()
	for i in 4:
		if count[i] == lo:
			best.append(i)
	return best[randi() % best.size()]

func _free_spot() -> Vector3:
	for i in 40:
		var p := Vector3(randf_range(1.6, W - 1.6), 0.0, randf_range(1.6, D - 0.8))
		if absf(p.z - BELT_Z) < 1.3:
			continue
		var ok := true
		for bn in benches:
			var zp: Vector3 = bn.zone
			var bp: Vector3 = bn.pos
			if Vector2(p.x - zp.x, p.z - zp.z).length() < 1.4 or Vector2(p.x - bp.x, p.z - bp.z).length() < 1.6:
				ok = false
		for id in alive_ids():
			if players[id].position.distance_to(p) < 1.6:
				ok = false
		for pid in parts:
			if parts[pid].node.position.distance_to(p) < 1.2:
				ok = false
		if ok:
			return p
	return Vector3(GAP_X, 0.0, 2.6)

func _server_spawn(type: int, pos: Vector3, belt: int) -> int:
	var pid := _next_pid
	_next_pid += 1
	_rpc_spawn_part.rpc(pid, type, pos, belt)
	return pid

func _physics_process(delta: float) -> void:
	if not NetworkManager.is_server() or not _running:
		return
	for id in players:
		punch_cd[id] = maxf(punch_cd[id] - delta, 0.0)
		stun[id] = maxf(stun[id] - delta, 0.0)
	_server_parts(delta)
	for id in alive_ids():
		_server_pickups(id)
		_server_assembly(id, delta)
		if players[id].is_bot:
			_bot_fire(id, delta)

func _server_parts(delta: float) -> void:
	for pid in parts.keys():
		var pr: Dictionary = parts[pid]
		if pr.belt < 0:
			continue
		var b: Array = BELTS[pr.belt]
		var x: float = pr.node.position.x
		if (b[2] > 0.0 and x >= b[1] - 0.3) or (b[2] < 0.0 and x <= b[0] + 0.3):
			_rpc_take.rpc(-1, pid)
	_belt_t -= delta
	if _belt_t <= 0.0:
		_belt_t = randf_range(1.0, 1.7)
		var bi := randi() % 2
		var b: Array = BELTS[bi]
		var sx: float = b[0] + 0.9 if b[2] > 0.0 else b[1] - 0.9
		_server_spawn(_scarce_type(), Vector3(sx, BELT_TOP, BELT_Z), bi)
	var on_floor := 0
	for pid in parts:
		if parts[pid].belt < 0:
			on_floor += 1
	if on_floor < FLOOR_PARTS:
		_floor_t -= delta
		if _floor_t <= 0.0:
			_floor_t = 0.7
			_server_spawn(_scarce_type(), _free_spot(), -1)

func _server_pickups(id: int) -> void:
	if armed[id]:
		return
	var pos: Vector3 = players[id].position
	for pid in parts.keys():
		var pr: Dictionary = parts[pid]
		var bit: int = 1 << int(pr.type)
		if inv[id] & bit or _clock - float(pr.born) < 0.45:
			continue
		var pp: Vector3 = pr.node.position
		var r := BELT_PICK_R if pr.belt >= 0 else PICK_R
		if Vector2(pp.x - pos.x, pp.z - pos.z).length() <= r:
			inv[id] = inv[id] | bit
			_rpc_take.rpc(id, pid)
			return

func _bench_near(pos: Vector3) -> int:
	for i in benches.size():
		var zp: Vector3 = benches[i].zone
		if Vector2(pos.x - zp.x, pos.z - zp.z).length() <= BENCH_R:
			return i
	return -1

func _server_assembly(id: int, delta: float) -> void:
	var pos: Vector3 = players[id].position
	var can: bool = holding[id] and inv[id] == FULL and not armed[id] and stun[id] <= 0.0 and _bench_near(pos) >= 0
	if can:
		if progress[id] <= 0.0:
			_rpc_assembling.rpc(id, true)
		progress[id] += delta
		_rpc_progress.rpc(id, progress[id] / ASSEMBLE_T)
		if progress[id] >= ASSEMBLE_T:
			progress[id] = 0.0
			holding[id] = false
			inv[id] = 0
			armed[id] = true
			aim_t[id] = 0.0
			_rpc_armed.rpc(id)
	elif progress[id] > 0.0:
		progress[id] = 0.0
		if players[id].is_bot:
			holding[id] = false
		_rpc_assembling.rpc(id, false)

func _bot_fire(id: int, delta: float) -> void:
	if not armed[id]:
		return
	var t := _aim_target(id, SHOT_CONE)
	if t != -1 and players[t].position.distance_to(players[id].position) < 7.5:
		aim_t[id] += delta
		if aim_t[id] >= react[id]:
			_shoot(id, randf() < 0.22)
	else:
		aim_t[id] = maxf(aim_t[id] - delta, 0.0)

@rpc("any_peer", "call_local", "reliable")
func _req_hold(on: bool) -> void:
	if not multiplayer.is_server() or not _running:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	if not players.has(id) or not players[id].alive:
		return
	if not on:
		holding[id] = false
		return
	if armed[id]:
		_shoot(id, false)
	elif inv[id] == FULL and _bench_near(players[id].position) >= 0:
		holding[id] = true
	else:
		_punch(id)

func _shoot(id: int, force_miss: bool) -> void:
	if not armed[id]:
		return
	armed[id] = false
	var p: LabPlayer3D = players[id]
	var victim := -1 if force_miss else _aim_target(id, SHOT_CONE)
	var f := _fwd(p)
	if force_miss:
		f = f.rotated(Vector3.UP, randf_range(0.35, 0.6) * (1.0 if randf() < 0.5 else -1.0))
	var end := p.position + f * 16.0
	end.x = clampf(end.x, -2.8, W + 2.8)
	end.z = clampf(end.z, -2.8, D + 2.8)
	end.y = 1.2
	if victim != -1:
		end = players[victim].position + Vector3(0, 1.2, 0)
		elim_order.append(victim)
	_rpc_shot.rpc(id, victim, end)
	if victim != -1:
		var lost: int = inv[victim]
		inv[victim] = 0
		armed[victim] = false
		holding[victim] = false
		var vp: Vector3 = players[victim].position
		for i in 4:
			if lost & (1 << i):
				var off := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf_range(0.7, 1.3)
				_server_spawn(i, _clamp_floor(vp + off), -1)

func _clamp_floor(p: Vector3) -> Vector3:
	var q := Vector3(clampf(p.x, 1.3, W - 1.3), 0.0, clampf(p.z, 0.7, D - 0.7))
	if absf(q.z - BELT_Z) < 1.0 and absf(q.x - GAP_X) > 1.1:
		q.z = BELT_Z + (1.0 if q.z >= BELT_Z else -1.0)
	return q

func _punch(id: int) -> void:
	if punch_cd[id] > 0.0:
		return
	punch_cd[id] = PUNCH_CD
	var p: LabPlayer3D = players[id]
	var f := _fwd(p)
	var victim := -1
	var best := PUNCH_R
	for o in alive_ids():
		if o == id:
			continue
		var to: Vector3 = players[o].position - p.position
		to.y = 0.0
		var d := to.length()
		if d > best or d < 0.01:
			continue
		if d > 0.9 and f.dot(to / d) < 0.3:
			continue
		best = d
		victim = o
	var dir := Vector3.ZERO
	var drop := -1
	var pid := -1
	var dpos := Vector3.ZERO
	if victim != -1:
		dir = players[victim].position - p.position
		dir.y = 0.0
		dir = dir.normalized()
		p.face(dir)
		stun[victim] = 0.6
		holding[victim] = false
		var owned: Array = []
		for i in 4:
			if inv[victim] & (1 << i):
				owned.append(i)
		if not owned.is_empty():
			drop = owned[randi() % owned.size()]
			inv[victim] = inv[victim] & ~(1 << drop)
			pid = _next_pid
			_next_pid += 1
			dpos = _clamp_floor(players[victim].position + dir.cross(Vector3.UP) * randf_range(-0.6, 0.6) - dir * 0.2)
	_rpc_punch.rpc(id, victim, dir, drop, pid, dpos)

func _bot_brain(_delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	if not _running or stun[id] > 0.0 or holding[id]:
		return Vector3.ZERO
	if armed[id]:
		var t := _nearest_rival(id)
		if t == -1:
			return Vector3.ZERO
		var to: Vector3 = players[t].position - p.position
		to.y = 0.0
		if to.length() < 5.5:
			p.face(to)
			return Vector3.ZERO
		return _steer(p.position, players[t].position)
	if inv[id] == FULL:
		var bi := _nearest_bench(p.position)
		var zp: Vector3 = benches[bi].zone
		if Vector2(p.position.x - zp.x, p.position.z - zp.z).length() < 0.45:
			holding[id] = true
			p.face(benches[bi].pos - p.position)
			return Vector3.ZERO
		return _steer(p.position, zp)
	if punch_cd[id] <= 0.0:
		for o in alive_ids():
			if o == id or _bits(inv[o]) < 2:
				continue
			var to: Vector3 = players[o].position - p.position
			to.y = 0.0
			if to.length() < 1.1:
				p.face(to)
				_punch(id)
				return Vector3.ZERO
			if to.length() < 2.2 and _bits(inv[o]) >= _bits(inv[id]):
				return _steer(p.position, players[o].position)
	var goal := _part_goal(id)
	if goal.x < INF:
		return _steer(p.position, goal)
	p._bot_t -= _delta
	if p._bot_t <= 0.0:
		p._bot_t = randf_range(0.6, 1.4)
		p.bot_dir = (Vector3(randf_range(2.0, W - 2.0), 0, randf_range(1.5, 3.5) if p.position.z < BELT_Z else randf_range(6.5, 8.5)) - p.position).normalized()
	return p.bot_dir

func _bits(m: int) -> int:
	return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1) + ((m >> 3) & 1)

func _nearest_rival(id: int) -> int:
	var best := -1
	var best_d := INF
	for o in alive_ids():
		if o == id:
			continue
		var d: float = players[o].position.distance_to(players[id].position)
		if d < best_d:
			best_d = d
			best = o
	return best

func _nearest_bench(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in benches.size():
		var d := _path_len(pos, benches[i].zone)
		if d < best_d:
			best_d = d
			best = i
	return best

func _crosses(a: Vector3, b: Vector3) -> bool:
	return (a.z < BELT_Z) != (b.z < BELT_Z) and absf(a.x - GAP_X) > 0.9

func _path_len(a: Vector3, b: Vector3) -> float:
	var d := Vector2(a.x - b.x, a.z - b.z).length()
	if _crosses(a, b):
		d += absf(a.x - GAP_X) + absf(b.x - GAP_X) - absf(a.x - b.x)
	return d

func _steer(from: Vector3, goal: Vector3) -> Vector3:
	var g := goal
	if _crosses(from, goal):
		g = Vector3(GAP_X, 0.0, BELT_Z + (-0.9 if from.z < BELT_Z else 0.9))
		if absf(from.x - GAP_X) < 1.2:
			g.z = BELT_Z + (1.0 if from.z < BELT_Z else -1.0)
	var v := Vector3(g.x - from.x, 0.0, g.z - from.z)
	if v.length() < 0.08:
		return Vector3.ZERO
	return v.normalized() * clampf(v.length() * 2.0, 0.35, 1.0)

func _part_goal(id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	var best := INF
	var goal := Vector3(INF, 0, 0)
	for pid in parts:
		var pr: Dictionary = parts[pid]
		if inv[id] & (1 << int(pr.type)):
			continue
		var pp: Vector3 = pr.node.position
		var g: Vector3
		if pr.belt >= 0:
			var b: Array = BELTS[pr.belt]
			var side := -1.0 if p.position.z < BELT_Z else 1.0
			var lead: float = float(b[2]) * clampf(absf(pp.x - p.position.x) * 0.25, 0.2, 1.2)
			var gx := clampf(pp.x + lead, 1.1, W - 1.1)
			if (b[2] > 0.0 and gx > b[1] - 0.6) or (b[2] < 0.0 and gx < b[0] + 0.6):
				continue
			g = Vector3(gx, 0.0, BELT_Z + side * 0.9)
		else:
			g = Vector3(pp.x, 0.0, pp.z)
		var d := _path_len(p.position, g)
		if d < best:
			best = d
			goal = g
	return goal

@rpc("authority", "call_local", "reliable")
func _rpc_spawn_part(pid: int, type: int, pos: Vector3, belt: int) -> void:
	_spawn_part_local(pid, type, pos, belt)

@rpc("authority", "call_local", "reliable")
func _rpc_take(id: int, pid: int) -> void:
	if not parts.has(pid):
		return
	var pr: Dictionary = parts[pid]
	var n: Node3D = pr.node
	if id >= 0:
		inv[id] = int(inv.get(id, 0)) | (1 << int(pr.type))
		Fx.sfx("click", n.position, -2.0, 1.3)
		Fx.sparks(world, n.position + Vector3(0, 0.3, 0))
		_refresh_hud()
	n.queue_free()
	parts.erase(pid)

@rpc("authority", "call_local", "unreliable")
func _rpc_progress(id: int, f: float) -> void:
	if ring_nodes.has(id):
		ring_nodes[id].material_override.set_shader_parameter("progress", f)

@rpc("authority", "call_local", "reliable")
func _rpc_assembling(id: int, on: bool) -> void:
	var p: LabPlayer3D = players[id]
	ring_nodes[id].visible = on
	ring_nodes[id].material_override.set_shader_parameter("progress", 0.0)
	if p.is_local_human():
		p.input_enabled = not on
	if not p.alive:
		return
	if on:
		p.body.play_action("Fixing_Kneeling", 0.15)
		Fx.sfx("hum", p.position, -4.0)
	else:
		p.body.play_loop("Idle")

@rpc("authority", "call_local", "reliable")
func _rpc_armed(id: int) -> void:
	var p: LabPlayer3D = players[id]
	inv[id] = 0
	armed[id] = true
	ring_nodes[id].visible = false
	if p.is_local_human():
		p.input_enabled = true
	p.body.play_loop("Idle")
	_give_gun(id)
	Fx.sfx("arm", p.position, 0.0)
	Fx.sparks(world, p.position + Vector3(0, 1.0, 0))
	_refresh_hud()

@rpc("authority", "call_local", "reliable")
func _rpc_shot(id: int, victim: int, end: Vector3) -> void:
	var p: LabPlayer3D = players[id]
	armed[id] = false
	if guns.has(id):
		guns[id].fired = true
		guns[id].laser.visible = false
	p.body.play_action("Pistol_Shoot", 0.05)
	var f := (end - p.position)
	f.y = 0.0
	f = f.normalized()
	var muzzle := p.position + Vector3(0, 1.38, 0) + f * 0.6
	Fx.sfx("gunshot", muzzle, 2.0)
	Fx.sparks(world, muzzle)
	Fx.shake(0.45)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.75, 0.35)
	fl.light_energy = 14.0
	fl.omni_range = 5.0
	world.add_child(fl)
	fl.global_position = muzzle
	var ftw := fl.create_tween()
	ftw.tween_property(fl, "light_energy", 0.0, 0.12)
	ftw.tween_callback(fl.queue_free)
	var tr := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, 0.035, 1.0)
	tr.mesh = bm
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_color = Color(1.0, 0.85, 0.4, 0.9)
	tr.material_override = tm
	world.add_child(tr)
	var len := muzzle.distance_to(end)
	tr.global_position = (muzzle + end) * 0.5
	if len > 0.05:
		tr.look_at(end, Vector3.UP)
	tr.scale = Vector3(1.0, 1.0, len)
	var ttw := tr.create_tween()
	ttw.tween_property(tm, "albedo_color:a", 0.0, 0.18)
	ttw.tween_callback(tr.queue_free)
	if victim != -1:
		kills[id] = int(kills.get(id, 0)) + 1
		inv[victim] = 0
		armed[victim] = false
		_remove_gun(victim)
		if ring_nodes.has(victim):
			ring_nodes[victim].visible = false
		eliminate(victim, "Death01")
		Fx.blood(world, players[victim].global_position + Vector3(0, 1.2, 0), 90)
		Fx.shake(0.6)
	else:
		Fx.sparks(world, end)
		Fx.sfx("hit", end, -6.0, 1.6)
	get_tree().create_timer(0.6).timeout.connect(_remove_gun.bind(id))
	_refresh_hud()

@rpc("authority", "call_local", "reliable")
func _rpc_punch(id: int, victim: int, dir: Vector3, drop: int, pid: int, dpos: Vector3) -> void:
	var p: LabPlayer3D = players[id]
	p.body.play_action("Punch_Jab", 0.06, 1.3)
	Fx.sfx("whoosh", p.position, -4.0)
	if victim == -1:
		return
	var v: LabPlayer3D = players[victim]
	v.body.play_action("Hit_Knockback", 0.06)
	Fx.sfx("hit", v.position, 0.0)
	Fx.shake(0.2)
	ring_nodes[victim].visible = false
	if v.is_multiplayer_authority():
		var to := _clamp_floor(v.position + dir * 1.3)
		if _crosses(v.position, to):
			to = v.position
		var tw := v.create_tween()
		tw.tween_property(v, "position", Vector3(to.x, v.position.y, to.z), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if v.is_local_human():
		v.input_enabled = false
		get_tree().create_timer(0.5).timeout.connect(_unlock.bind(v))
	if drop >= 0:
		inv[victim] = int(inv.get(victim, 0)) & ~(1 << drop)
		_spawn_part_local(pid, drop, v.position, -1)
		var n: Node3D = parts[pid].node
		var tw2 := n.create_tween()
		tw2.tween_property(n, "position", dpos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		Fx.sparks(world, v.position + Vector3(0, 1.0, 0))
	_refresh_hud()

func _unlock(v: LabPlayer3D) -> void:
	if is_instance_valid(v) and v.alive:
		v.input_enabled = true
