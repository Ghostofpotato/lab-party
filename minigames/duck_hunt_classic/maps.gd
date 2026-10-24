extends RefCounted
## Duck Hunt Classic map set. Map 0 (the scrap yard) is built by the main script,
## maps 1..7 here. Every map keeps the same lane (X 0..16, ducks start at Z 30,
## exit line at Z 0, hunter tower behind the exit), six staggered cover rows of
## the same density, and brings its own sky, fog, light, props and tower skin.

const NAMES: Array[String] = ["SCRAP YARD", "HAUNTED ACRE", "DEAD MAN'S FUNFAIR", "WHITEOUT LODGE", "TEMPLE OF THE LOST", "SEWAGE CANAL", "BBQ GONE WRONG", "NEON NIGHT MARKET"]
const COUNT: int = 8
const W: float = 16.0

var g
var rng := RandomNumberGenerator.new()
var _glows: Dictionary = {}
var _soft: GradientTexture2D

func _init(game, seed_v: int) -> void:
	g = game
	rng.seed = seed_v

static func pick(seed_v: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			return posmod(int(a.substr(6)), COUNT)
	var e := OS.get_environment("LP_MAP")
	if e != "":
		return posmod(int(e), COUNT)
	return posmod(seed_v, COUNT)

func build(i: int) -> Dictionary:
	match i:
		1:
			return _haunted()
		2:
			return _funfair()
		3:
			return _lodge()
		4:
			return _temple()
		5:
			return _sewer()
		6:
			return _bbq()
		7:
			return _neon()
	return {}

func _env(bg: Color, amb: Color, amb_e: float, fog: Color, fog_d: float, exposure: float, sat: float) -> void:
	var env: Environment = g.env
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	env.fog_light_color = fog
	env.fog_density = fog_d
	env.tonemap_exposure = exposure
	env.adjustment_saturation = sat

func _sky(top: Color, hor: Color, bottom: Color, energy: float, fog_affect: float) -> void:
	var m := ProceduralSkyMaterial.new()
	m.sky_top_color = top
	m.sky_horizon_color = hor
	m.ground_horizon_color = hor
	m.ground_bottom_color = bottom
	m.energy_multiplier = energy
	var s := Sky.new()
	s.sky_material = m
	var env: Environment = g.env
	env.sky = s
	env.background_mode = Environment.BG_SKY
	env.fog_sky_affect = fog_affect

func _sun(col: Color, e: float, rot: Vector3) -> void:
	for c in g.world.get_children():
		if c is DirectionalLight3D:
			var dl: DirectionalLight3D = c
			dl.light_color = col
			dl.light_energy = e
			dl.rotation_degrees = rot
			dl.directional_shadow_max_distance = 60.0

func _ground(tex: String, tile: float, tint: Color) -> void:
	g.box(Vector3(130.0, 0.2, 130.0), Vector3(W * 0.5, -0.1, 15.0), g.mat(tex, tile, tint))

func _patch(tex: String, tile: float, tint: Color, size: Vector2, at: Vector2, y: float = 0.0) -> MeshInstance3D:
	return g.box(Vector3(size.x, 0.04, size.y), Vector3(at.x, y, at.y), g.mat(tex, tile, tint))

func _glow(c: Color, e: float) -> StandardMaterial3D:
	var k := c.to_html() + str(e)
	if not _glows.has(k):
		_glows[k] = g._glow_mat(c, e)
	return _glows[k]

func _piv(at: Vector3, yaw: float, parent: Node = null) -> Node3D:
	var p := Node3D.new()
	(parent if parent else g.world).add_child(p)
	p.position = at
	p.rotation_degrees.y = yaw
	return p

func _box(size: Vector3, pos: Vector3, m: Material, parent: Node = null) -> MeshInstance3D:
	return g.box(size, pos, m, parent)

func _cyl(rt: float, rb: float, h: float, pos: Vector3, m: Material, parent: Node = null, seg: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rt
	cm.bottom_radius = rb
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	(parent if parent else g.world).add_child(mi)
	return mi

func _ball(r: float, pos: Vector3, m: Material, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	(parent if parent else g.world).add_child(mi)
	return mi

func _limb(base: Vector3, rot: Vector3, length: float, r0: float, r1: float, m: Material, parent: Node = null) -> MeshInstance3D:
	var b := Basis.from_euler(rot)
	var mi := _cyl(r1, r0, length, base + b * Vector3(0, length * 0.5, 0), m, parent, 7)
	mi.basis = b
	return mi

func _prop(id: String, pos: Vector3, yaw: float = 0.0, s: float = 1.0, parent: Node = null) -> Node3D:
	return g.prop(id, pos, yaw, s, parent)

func _omni(pos: Vector3, col: Color, e: float, r: float, shadow: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = e
	l.omni_range = r
	l.shadow_enabled = shadow
	g.world.add_child(l)
	l.position = pos
	return l

func _spot(pos: Vector3, target: Vector3, col: Color, e: float, r: float, angle: float, shadow: bool) -> SpotLight3D:
	var sp := SpotLight3D.new()
	sp.light_color = col
	sp.light_energy = e
	sp.spot_range = r
	sp.spot_angle = angle
	sp.spot_attenuation = 0.9
	sp.shadow_enabled = shadow
	g.world.add_child(sp)
	sp.position = pos
	sp.look_at(target, Vector3.UP if absf((target - pos).normalized().y) < 0.98 else Vector3.RIGHT)
	return sp

func _duck_lights(col: Color, e: float) -> void:
	for z in [6.0, 14.0, 22.0, 30.0]:
		var l := _omni(Vector3(W * 0.5, 4.0, z), col, e, 9.0)
		g._duck_lights.append(l)

func _solid(c: Vector3, s: Vector3, yaw: float = 0.0, cover: bool = true) -> void:
	g._solid(c, s, yaw, cover)

func _label(text: String, pos: Vector3, size: int, col: Color, parent: Node = null, yaw: float = 0.0) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = size
	lb.pixel_size = 0.006
	lb.outline_size = 10
	lb.modulate = col
	(parent if parent else g.world).add_child(lb)
	lb.position = pos
	lb.rotation_degrees.y = yaw
	return lb

func _exit(col: Color, frame: Material, text: String = "EXIT") -> void:
	_box(Vector3(W + 1.2, 0.06, 0.35), Vector3(W * 0.5, 0.0, 0.1), _glow(col, 0.8))
	for px in [-1.4, 17.4]:
		_box(Vector3(0.45, 3.8, 0.45), Vector3(px, 1.9, -0.6), frame)
	_box(Vector3(19.3, 0.45, 0.45), Vector3(W * 0.5, 3.8, -0.6), frame)
	_box(Vector3(2.4, 0.6, 0.08), Vector3(W * 0.5 - 4.0, 3.2, -0.34), _glow(Color(0.2, 0.9, 0.3), 2.2))
	_label(text, Vector3(W * 0.5 - 4.0, 3.2, -0.28), 96, Color(0.85, 1.0, 0.85))
	_omni(Vector3(W * 0.5 - 4.0, 2.6, 0.4), Color(0.4, 1.0, 0.5), 1.6, 6.0)

func _soft_tex() -> GradientTexture2D:
	if _soft:
		return _soft
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	_soft = GradientTexture2D.new()
	_soft.gradient = gr
	_soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(0.5, 0.5)
	_soft.fill_to = Vector2(1.0, 0.5)
	_soft.width = 64
	_soft.height = 64
	return _soft

func _parts(at: Vector3, ext: Vector3, amount: int, life: float, vel: Vector3, spread: float, size: Vector2, col: Color, streak: bool = false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ext
	pm.gravity = Vector3.ZERO
	pm.direction = vel.normalized() if vel.length() > 0.001 else Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = vel.length() * 0.7
	pm.initial_velocity_max = vel.length() * 1.3
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if streak else BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.albedo_texture = _soft_tex()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.draw_pass_1 = q
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(-ext - Vector3.ONE * 20.0, ext * 2.0 + Vector3.ONE * 40.0)
	g.world.add_child(p)
	p.position = at
	return p

func _covers(rows: Array, fn: Callable) -> void:
	for d in rows:
		fn.call(String(d[0]), Vector3(float(d[1]), 0.0, float(d[2])), float(d[3]))

func _marks(m: Material) -> void:
	for k in 8:
		_box(Vector3(0.9, 0.065, 0.36), Vector3(1.0 + k * 2.0, 0.0, 28.6), m)

func _rail(a: Vector3, b: Vector3, post_m: Material, h: float, step: float, rails: Array) -> void:
	var dir := b - a
	var n := int(ceil(dir.length() / step))
	var yaw := rad_to_deg(atan2(dir.x, dir.z))
	for i in n + 1:
		var p := a + dir * (float(i) / float(n))
		_box(Vector3(0.12, h, 0.12), p + Vector3(0, h * 0.5, 0), post_m)
	for y in rails:
		var r := _box(Vector3(0.07, 0.07, dir.length()), (a + b) * 0.5 + Vector3(0, float(y), 0), post_m)
		r.rotation_degrees.y = yaw

func _stripes(size: Vector3, pos: Vector3, a: Material, b: Material, n: int, parent: Node) -> void:
	var w := size.x / float(n)
	for k in n:
		_box(Vector3(w, size.y, size.z), pos + Vector3(-size.x * 0.5 + w * (k + 0.5), 0, 0), a if k % 2 == 0 else b, parent)

## 1 · HAUNTED ACRE: moonlit graveyard, green fog, crooked tombs, crypts, angels.
func _haunted() -> Dictionary:
	_env(Color("05080a"), Color(0.36, 0.48, 0.5), 0.62, Color(0.1, 0.15, 0.14), 0.03, 1.35, 0.6)
	_sun(Color(0.55, 0.78, 0.85), 0.45, Vector3(-36.0, 195.0, 0.0))
	_ground("withered_grass", 0.3, Color(0.5, 0.56, 0.44))
	_patch("gravel_floor", 0.45, Color(0.62, 0.6, 0.55), Vector2(3.4, 36.0), Vector2(W * 0.5, 15.0))
	_patch("dirty_concrete", 0.4, Color(0.55, 0.58, 0.55), Vector2(W + 1.2, 3.0), Vector2(W * 0.5, 30.0), 0.012)
	_marks(g.mat("mossy_stone_wall", 1.0, Color(0.8, 0.8, 0.75)))
	var rows := [["grave", 2.6, 26.5, 4.0], ["stones", 8.0, 26.6, -3.0], ["grave", 13.4, 26.5, -6.0],
		["crypt", 3.6, 22.0, 0.0], ["angel", 8.2, 22.0, 0.0], ["grave", 12.8, 22.2, 8.0],
		["grave", 1.8, 17.5, -5.0], ["wall", 6.4, 17.5, 4.0], ["stones", 10.6, 17.6, 6.0], ["grave", 14.4, 17.4, -8.0],
		["angel", 2.8, 13.0, 0.0], ["crypt", 9.2, 13.0, 0.0], ["stones", 14.2, 13.1, -4.0],
		["stones", 2.0, 8.6, 5.0], ["grave", 5.9, 8.5, -7.0], ["grave", 10.2, 8.5, 6.0], ["wall", 13.8, 8.5, -6.0],
		["grave", 4.2, 4.5, 3.0], ["angel", 11.8, 4.5, 0.0]]
	_covers(rows, _haunted_cover)
	var iron: StandardMaterial3D = g.mat("rusty_metal_02", 1.2, Color(0.45, 0.45, 0.45))
	var stone: StandardMaterial3D = g.mat("mossy_stone_wall", 0.6, Color(0.6, 0.62, 0.58))
	for sx in [-1.4, 17.4]:
		_box(Vector3(0.5, 0.5, 36.0), Vector3(sx, 0.25, 17.0), stone)
		_rail(Vector3(sx, 0.5, -1.0), Vector3(sx, 0.5, 35.0), iron, 1.5, 0.5, [0.55, 1.35])
	_rail(Vector3(-1.4, 0.0, 35.0), Vector3(17.4, 0.0, 35.0), iron, 1.3, 0.5, [0.4, 1.15])
	_exit(Color(0.5, 0.95, 0.6), stone)
	for gx in [0.6, 15.4]:
		var gt := _prop("large_iron_gate", Vector3(gx, 0, -1.4), 0.0)
		if gt:
			gt.rotation_degrees.y = 100.0 if gx < 8.0 else -100.0
	var wall: StandardMaterial3D = g.mat("mossy_stone_wall", 0.35, Color(0.55, 0.56, 0.55))
	_box(Vector3(60.0, 9.0, 1.0), Vector3(W * 0.5, 4.5, -11.0), wall)
	_box(Vector3(6.0, 16.0, 6.0), Vector3(W * 0.5 + 9.0, 8.0, -13.5), wall)
	var spire := _cyl(0.0, 4.2, 7.0, Vector3(W * 0.5 + 9.0, 19.5, -13.5), g.mat("dark_rock", 0.5, Color(0.5, 0.5, 0.55)), null, 4)
	spire.rotation_degrees.y = 45.0
	for wx in [-10.0, -4.0, 2.0, 14.0, 20.0, 26.0]:
		_box(Vector3(1.4, 3.2, 0.1), Vector3(wx, 5.0, -10.45), _glow(Color(0.65, 0.12, 0.35) if int(wx) % 3 == 0 else Color(0.25, 0.3, 0.75), 1.4))
		_cyl(0.7, 0.7, 0.1, Vector3(wx, 6.6, -10.45), _glow(Color(0.85, 0.5, 0.2), 1.2), null, 10).rotation_degrees.x = 90.0
	_box(Vector3(1.6, 4.5, 0.1), Vector3(W * 0.5 + 9.0, 9.0, -10.45), _glow(Color(0.9, 0.7, 0.25), 1.6))
	var moon_m := _glow(Color(0.85, 0.97, 0.9), 3.0)
	moon_m.disable_fog = true
	_ball(5.0, Vector3(-22.0, 34.0, -70.0), moon_m)
	var bark: StandardMaterial3D = g.mat("bark_brown_02", 0.8, Color(0.35, 0.33, 0.32))
	for t in [Vector3(-4.0, 0, 4.0), Vector3(-5.5, 0, 15.0), Vector3(-3.8, 0, 26.0), Vector3(20.5, 0, 7.0), Vector3(21.5, 0, 19.0), Vector3(20.0, 0, 30.0), Vector3(-9.0, 0, 40.0), Vector3(6.0, 0, 46.0), Vector3(24.0, 0, 42.0), Vector3(-12.0, 0, 20.0), Vector3(28.0, 0, 14.0)]:
		_dead_tree(t, rng.randf_range(5.5, 8.5), bark)
	for o in [["dead_tree_trunk", -4.5, 10.0], ["dead_tree_trunk", 21.0, 24.0], ["gothic_statue", -3.2, 20.0], ["gothic_statue", 19.8, 12.0], ["tree_stump_01", -3.0, 32.0], ["tree_stump_01", 19.6, 2.0], ["rock_moss_set_01", -9.0, 30.0]]:
		_prop(o[0], Vector3(o[1], 0, o[2]), rng.randf() * 360.0, 0.6 if o[0] == "rock_moss_set_01" else 1.0)
	for o in [["grass_medium_01", -0.9, 6.0], ["grass_medium_01", 16.9, 14.0], ["grass_medium_01", -0.9, 24.0], ["nettle_plant", 16.9, 28.0], ["nettle_plant", -0.9, 2.0]]:
		_prop(o[0], Vector3(o[1], 0, o[2]), 90.0, 1.2)
	_box(Vector3(2.0, 0.08, 1.0), Vector3(-3.6, 0.02, 22.0), g.mat("dark_rock", 0.6, Color(0.35, 0.3, 0.25)))
	for z in [2.0, 10.0, 18.0, 26.0, 33.0]:
		for sx in [-1.4, 17.4]:
			_lantern(Vector3(sx, 0.5, z + (2.0 if sx > 8.0 else 0.0)))
	_parts(Vector3(W * 0.5, 0.4, 15.0), Vector3(14.0, 0.3, 20.0), 70, 9.0, Vector3(0.25, 0.0, 0.1), 40.0, Vector2(5.0, 2.2), Color(0.6, 0.75, 0.7, 0.07))
	_duck_lights(Color(0.6, 0.85, 0.8), 0.8)
	return {"leg": ["worn_planks", Color(0.55, 0.5, 0.45)], "deck": ["black_painted_planks", Color(0.5, 0.45, 0.4)], "wall": ["old_planks_02", Color(0.6, 0.55, 0.5)], "roof": ["dark_rock", Color(0.45, 0.45, 0.5)]}

func _lantern(base: Vector3) -> void:
	var iron: StandardMaterial3D = g.mat("rusty_metal_02", 1.2, Color(0.45, 0.45, 0.45))
	_box(Vector3(0.1, 1.9, 0.1), base + Vector3(0, 0.95, 0), iron)
	var ln := _prop("Lantern_01", base + Vector3(0, 1.9, 0), rng.randf() * 360.0, 2.4)
	if not ln:
		_box(Vector3(0.2, 0.3, 0.2), base + Vector3(0, 2.05, 0), _glow(Color(1.0, 0.6, 0.25), 3.0))
	_ball(0.07, base + Vector3(0, 2.2, 0), _glow(Color(1.0, 0.62, 0.25), 6.0))
	_omni(base + Vector3(0, 2.3, 0), Color(1.0, 0.6, 0.3), 1.6, 6.5)

func _dead_tree(at: Vector3, h: float, m: Material) -> void:
	var p := _piv(at, rng.randf() * 360.0)
	_limb(Vector3.ZERO, Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08)), h, 0.32, 0.1, m, p)
	for k in 6:
		var y := h * (0.4 + 0.1 * k)
		var rot := Vector3(rng.randf_range(0.7, 1.25), k * 1.9 + rng.randf(), 0.0)
		var l := h * rng.randf_range(0.22, 0.4)
		_limb(Vector3(0, y, 0), rot, l, 0.1, 0.02, m, p)
		var tip := Basis.from_euler(rot) * Vector3(0, l, 0) + Vector3(0, y, 0)
		_limb(tip - Basis.from_euler(rot) * Vector3(0, l * 0.3, 0), rot + Vector3(-0.6, 0.8, 0), l * 0.6, 0.04, 0.01, m, p)

func _haunted_cover(kind: String, at: Vector3, yaw: float) -> void:
	var stone: StandardMaterial3D = g.mat("mossy_stone_wall", 0.9, Color(0.72, 0.74, 0.7))
	var dark: StandardMaterial3D = g.mat("mossy_stone_wall", 0.9, Color(0.48, 0.5, 0.48))
	var p := _piv(at, yaw)
	match kind:
		"grave":
			_box(Vector3(1.8, 1.04, 0.95), Vector3(0, 0.52, 0.05), stone, p)
			_box(Vector3(1.95, 0.14, 1.08), Vector3(0, 1.1, 0.05), dark, p)
			var hs := _box(Vector3(0.95, 1.55, 0.2), Vector3(0, 0.75, -0.48), stone, p)
			hs.rotation_degrees = Vector3(rng.randf_range(-9.0, 5.0), 0, rng.randf_range(-8.0, 8.0))
			_box(Vector3(0.12, 0.6, 0.08), Vector3(0, 1.75, -0.48), dark, p)
			_box(Vector3(0.42, 0.1, 0.08), Vector3(0, 1.88, -0.48), dark, p)
			_solid(at + Vector3(0, 0.62, 0), Vector3(1.95, 1.24, 1.12), yaw)
		"stones":
			_box(Vector3(1.8, 0.4, 0.7), Vector3(0, 0.2, 0.0), dark, p)
			var a := _box(Vector3(0.8, 1.45, 0.28), Vector3(-0.42, 0.72, 0.0), stone, p)
			a.rotation_degrees.z = rng.randf_range(-7.0, -2.0)
			var b := _box(Vector3(0.8, 1.3, 0.28), Vector3(0.44, 0.65, 0.0), stone, p)
			b.rotation_degrees = Vector3(rng.randf_range(-6.0, 6.0), 0, rng.randf_range(3.0, 9.0))
			_cyl(0.4, 0.4, 0.28, Vector3(-0.42, 1.42, 0.0), stone, p, 12).rotation_degrees.x = 90.0
			_solid(at + Vector3(0, 0.7, 0), Vector3(1.8, 1.4, 0.4), yaw)
			_solid(at + Vector3(0, 0.2, 0), Vector3(1.8, 0.4, 0.7), yaw, false)
		"crypt":
			_box(Vector3(3.6, 2.6, 2.6), Vector3(0, 1.3, 0), stone, p)
			_box(Vector3(3.9, 0.25, 2.9), Vector3(0, 2.7, 0), dark, p)
			for s in [-1.0, 1.0]:
				var r := _box(Vector3(4.0, 0.18, 1.7), Vector3(0, 3.15, s * 0.7), dark, p)
				r.rotation_degrees.x = -s * 32.0
			_box(Vector3(1.1, 1.9, 0.08), Vector3(0, 0.95, 1.31), g.mat("rusty_metal_02", 1.0, Color(0.4, 0.38, 0.36)), p)
			_box(Vector3(0.14, 0.9, 0.14), Vector3(0, 3.9, 0), dark, p)
			_box(Vector3(0.5, 0.14, 0.14), Vector3(0, 4.05, 0), dark, p)
			_label("R.I.P.", Vector3(0, 2.25, 1.32), 64, Color(0.7, 0.75, 0.7), p)
			_omni(at + Vector3(0, 2.2, 1.9), Color(1.0, 0.6, 0.3), 1.2, 5.0)
			_ball(0.08, Vector3(1.0, 2.0, 1.35), _glow(Color(1.0, 0.6, 0.25), 6.0), p)
			_solid(at + Vector3(0, 1.4, 0), Vector3(3.9, 2.8, 2.9), yaw)
		"angel":
			_box(Vector3(1.1, 1.15, 1.1), Vector3(0, 0.575, 0), stone, p)
			_box(Vector3(1.25, 0.12, 1.25), Vector3(0, 1.2, 0), dark, p)
			_prop("gothic_statue", Vector3(0.05, 1.25, 0.35), 180.0, 0.82, p)
			_solid(at + Vector3(0, 1.3, 0), Vector3(1.15, 2.6, 1.15), yaw)
		"wall":
			_box(Vector3(3.0, 1.75, 0.45), Vector3(0, 0.875, 0), stone, p)
			_box(Vector3(1.2, 0.35, 0.45), Vector3(-0.8, 1.9, 0), stone, p)
			_box(Vector3(0.6, 0.2, 0.45), Vector3(0.9, 1.85, 0), dark, p)
			_prop("grass_medium_01", Vector3(0, 0, 0.35), 0.0, 0.5, p)
			_solid(at + Vector3(0, 0.875, 0), Vector3(3.0, 1.75, 0.45), yaw)

## 2 · DEAD MAN'S FUNFAIR: sunset carnival, bulb strings, stalls, ducks on sticks, carousel.
func _funfair() -> Dictionary:
	_env(Color("1a0d22"), Color(0.62, 0.48, 0.66), 0.62, Color(0.45, 0.26, 0.36), 0.012, 1.1, 1.05)
	_sky(Color(0.16, 0.08, 0.28), Color(0.95, 0.45, 0.24), Color(0.1, 0.06, 0.08), 1.0, 0.35)
	_sun(Color(1.0, 0.58, 0.32), 1.05, Vector3(-16.0, 185.0, 0.0))
	_ground("gravel_floor", 0.4, Color(0.75, 0.62, 0.5))
	_patch("asphalt_02", 0.3, Color(0.7, 0.62, 0.62), Vector2(W + 1.2, 36.0), Vector2(W * 0.5, 15.0))
	_patch("worn_planks", 0.5, Color(0.8, 0.65, 0.5), Vector2(4.0, 36.0), Vector2(W * 0.5, 15.0), 0.012)
	_marks(_glow(Color(1.0, 0.3, 0.25), 0.8))
	var rows := [["cart", 2.6, 26.5, 0.0], ["ducks", 8.0, 26.6, 0.0], ["cart", 13.4, 26.5, 0.0],
		["booth", 3.6, 22.0, 0.0], ["tent", 12.2, 21.8, 0.0],
		["ducks", 2.2, 17.5, 0.0], ["cart", 7.0, 17.5, 6.0], ["booth", 12.0, 17.4, 0.0],
		["cart", 2.4, 13.0, -5.0], ["carousel", 8.0, 12.8, 0.0], ["cart", 13.6, 13.0, 5.0],
		["booth", 3.2, 8.5, 0.0], ["ducks", 8.8, 8.6, 0.0], ["cart", 13.6, 8.5, -4.0],
		["cart", 5.0, 4.5, 0.0], ["cart", 11.0, 4.5, 0.0]]
	_covers(rows, _fair_cover)
	var pole: StandardMaterial3D = g.mat("rusty_metal_02", 1.0, Color(0.7, 0.6, 0.55))
	var cols := [Color(1.0, 0.25, 0.2), Color(1.0, 0.85, 0.25), Color(0.25, 0.8, 1.0), Color(0.4, 1.0, 0.45), Color(1.0, 0.4, 0.85)]
	for z in [3.0, 10.5, 15.5, 20.0, 25.0, 31.0]:
		for sx in [-1.2, 17.2]:
			_box(Vector3(0.14, 6.0, 0.14), Vector3(sx, 3.0, z), pole)
		_bulbs(Vector3(-1.2, 5.8, z), Vector3(17.2, 5.8, z), 26, cols, 0.9)
		_omni(Vector3(W * 0.5, 5.0, z), cols[int(z) % cols.size()], 0.9, 7.0)
	var picket_a: StandardMaterial3D = g.mat("distressed_painted_planks", 0.8, Color(0.95, 0.85, 0.75))
	for sx in [-1.4, 17.4]:
		for k in 36:
			_box(Vector3(0.08, 1.1, 0.16), Vector3(sx, 0.55, -1.0 + k), picket_a)
		_box(Vector3(0.06, 0.1, 36.0), Vector3(sx, 0.85, 17.0), picket_a)
	_exit(Color(1.0, 0.85, 0.3), g.mat("distressed_painted_planks", 0.8, Color(0.85, 0.3, 0.25)))
	_bulbs(Vector3(-1.4, 4.1, -0.4), Vector3(17.4, 4.1, -0.4), 30, cols, 0.0)
	_ferris(Vector3(W * 0.5 + 3.0, 0.0, -18.0), cols)
	var canvas_r: StandardMaterial3D = g.mat("grey_plaster_03", 0.5, Color(0.75, 0.15, 0.12))
	var canvas_w: StandardMaterial3D = g.mat("grey_plaster_03", 0.5, Color(0.9, 0.85, 0.75))
	for t in [Vector3(-7.0, 0, -8.0), Vector3(-6.0, 0, 8.0), Vector3(23.0, 0, -6.0), Vector3(23.5, 0, 12.0), Vector3(-6.5, 0, 24.0), Vector3(23.0, 0, 28.0)]:
		var tp := _piv(t, rng.randf() * 360.0)
		for k in 8:
			var seg := _box(Vector3(1.6, 3.4, 0.1), Vector3(0, 1.7, 0), canvas_r if k % 2 == 0 else canvas_w, tp)
			seg.rotation_degrees.y = k * 45.0
			seg.position = Vector3(sin(deg_to_rad(k * 45.0)) * 1.9, 1.7, cos(deg_to_rad(k * 45.0)) * 1.9)
		var roof := _cyl(0.05, 2.4, 2.2, Vector3(0, 4.5, 0), canvas_r, tp, 8)
		roof.rotation_degrees.y = 22.5
		_box(Vector3(0.6, 0.35, 0.02), Vector3(0.3, 5.8, 0), canvas_w, tp)
		_omni(t + Vector3(0, 2.0, 0), Color(1.0, 0.7, 0.4), 1.2, 5.0)
	for o in [["trashbag", -0.6, 32.6], ["cardboard_box_01", 1.6, 33.6], ["barrel_03", 15.4, 33.2], ["metal_trash_can", 13.2, 33.6], ["plastic_crate_01", 9.0, 33.6], ["cardboard_box_01", 5.4, 33.2], ["barrel_03", -3.0, 18.0], ["metal_trash_can", 19.4, 20.0], ["trashbag", 19.4, 6.0], ["plastic_monobloc_chair_01", -3.0, 6.0], ["plastic_monobloc_chair_01", 19.6, 26.0]]:
		_prop(o[0], Vector3(o[1], 0, o[2]), rng.randf() * 360.0)
	_strongman(Vector3(-3.6, 0, 14.0))
	_duck_lights(Color(1.0, 0.7, 0.85), 0.7)
	return {"leg": ["distressed_painted_planks", Color(0.85, 0.3, 0.25)], "deck": ["worn_planks", Color(0.7, 0.55, 0.45)], "wall": ["distressed_painted_planks", Color(0.95, 0.85, 0.7)], "roof": ["grey_plaster_03", Color(0.75, 0.15, 0.12)]}

func _bulbs(a: Vector3, b: Vector3, n: int, cols: Array, sag: float) -> void:
	var wire: StandardMaterial3D = g.mat("rusty_metal_02", 1.0, Color(0.2, 0.2, 0.2))
	var prev := a
	for i in n + 1:
		var t := float(i) / float(n)
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		if i > 0:
			var seg := _box(Vector3(0.025, 0.025, prev.distance_to(p)), (prev + p) * 0.5, wire)
			seg.look_at_from_position((prev + p) * 0.5, p, Vector3.UP)
		if i > 0 and i < n:
			_ball(0.075, p - Vector3(0, 0.1, 0), _glow(cols[i % cols.size()], 5.0))
		prev = p

func _ferris(c: Vector3, cols: Array) -> void:
	var steel: StandardMaterial3D = g.mat("rusty_metal_02", 1.0, Color(0.85, 0.85, 0.9))
	var hub := c + Vector3(0, 11.0, 0)
	var r := 9.0
	for k in 24:
		var a0 := TAU * k / 24.0
		var a1 := TAU * (k + 1) / 24.0
		var p0 := hub + Vector3(cos(a0) * r, sin(a0) * r, 0)
		var p1 := hub + Vector3(cos(a1) * r, sin(a1) * r, 0)
		var seg := _box(Vector3(0.25, 0.25, p0.distance_to(p1)), (p0 + p1) * 0.5, steel)
		seg.look_at_from_position((p0 + p1) * 0.5, p1, Vector3(0, 0, 1))
		var sp := _box(Vector3(0.12, 0.12, r), hub + Vector3(cos(a0) * r * 0.5, sin(a0) * r * 0.5, 0), steel)
		sp.look_at_from_position(sp.position, p0, Vector3(0, 0, 1))
		_ball(0.2, p0 + Vector3(0, 0, 0.2), _glow(cols[k % cols.size()], 4.0))
		if k % 3 == 0:
			_box(Vector3(1.2, 1.0, 1.2), p0 + Vector3(0, -1.0, 0), g.mat("distressed_painted_planks", 0.8, cols[(k / 3) % cols.size()].darkened(0.3)))
	for s in [-1.0, 1.0]:
		var leg := _box(Vector3(0.4, 12.5, 0.4), c + Vector3(s * 3.0, 5.6, 0), steel)
		leg.rotation_degrees.z = s * 15.0
	_omni(hub, Color(1.0, 0.6, 0.8), 3.0, 16.0)

func _strongman(at: Vector3) -> void:
	_box(Vector3(0.3, 7.0, 0.3), at + Vector3(0, 3.5, 0), g.mat("distressed_painted_planks", 0.8, Color(0.9, 0.85, 0.75)))
	for k in 7:
		_box(Vector3(0.36, 0.5, 0.02), at + Vector3(0, 0.8 + k * 0.9, 0.16), _glow([Color(0.3, 1.0, 0.4), Color(1.0, 0.9, 0.3), Color(1.0, 0.3, 0.2)][k / 3 if k < 7 else 2], 1.5))
	_ball(0.3, at + Vector3(0, 7.2, 0), g.mat("rusty_metal_02", 1.0, Color(1.0, 0.8, 0.4)))
	_box(Vector3(1.0, 0.4, 0.8), at + Vector3(0, 0.2, 0.3), g.mat("rusty_metal", 1.0))

func _fair_cover(kind: String, at: Vector3, yaw: float) -> void:
	var tints := [Color(0.85, 0.25, 0.2), Color(0.25, 0.45, 0.85), Color(0.95, 0.75, 0.2), Color(0.3, 0.7, 0.45)]
	var tint: Color = tints[rng.randi() % tints.size()]
	var paint: StandardMaterial3D = g.mat("distressed_painted_planks", 0.8, tint)
	var cream: StandardMaterial3D = g.mat("grey_plaster_03", 0.6, Color(0.95, 0.9, 0.8))
	var red: StandardMaterial3D = g.mat("grey_plaster_03", 0.6, Color(0.8, 0.15, 0.12))
	var p := _piv(at, yaw)
	match kind:
		"booth":
			_box(Vector3(3.0, 1.2, 0.6), Vector3(0, 0.6, 0.2), paint, p)
			_box(Vector3(3.0, 2.3, 0.14), Vector3(0, 1.15, -0.43), g.mat("worn_planks", 0.7, Color(0.8, 0.7, 0.6)), p)
			for s in [-1.45, 1.45]:
				_box(Vector3(0.1, 2.6, 0.1), Vector3(s, 1.3, 0.45), paint, p)
			_stripes(Vector3(3.2, 0.12, 1.1), Vector3(0, 2.6, 0.05), red, cream, 8, p)
			_box(Vector3(2.6, 0.06, 0.25), Vector3(0, 1.75, -0.3), g.mat("worn_planks", 0.7), p)
			for k in 6:
				_prop("rubber_duck_toy", Vector3(-1.1 + k * 0.44, 1.78, -0.3), 180.0, 1.4, p)
			_label(["HOOK-A-DUCK", "SHOOT 3 WIN 1", "LUCKY DIP"][rng.randi() % 3], Vector3(0, 2.0, -0.35), 52, Color(1.0, 0.9, 0.5), p)
			_omni(at + Vector3(0, 2.2, 0.6), Color(1.0, 0.75, 0.4), 1.0, 4.0)
			_solid(at + Vector3(0, 1.15, 0), Vector3(3.0, 2.3, 1.0), yaw)
		"cart":
			_box(Vector3(1.8, 1.0, 0.9), Vector3(0, 0.7, 0), paint, p)
			_box(Vector3(1.9, 0.08, 1.0), Vector3(0, 1.24, 0), g.mat("rusty_metal_02", 1.0), p)
			_box(Vector3(1.6, 0.06, 0.7), Vector3(0, 1.3, 0), cream, p)
			for wx in [-0.6, 0.6]:
				var t: Node3D = _prop("old_tyre", Vector3(wx, 0.2, 0.47), 0.0, 0.55, p)
				if t:
					t.rotation_degrees.x = 0.0
			for c in [Vector2(-0.85, -0.4), Vector2(0.85, -0.4), Vector2(-0.85, 0.4), Vector2(0.85, 0.4)]:
				_box(Vector3(0.05, 1.0, 0.05), Vector3(c.x, 1.75, c.y), g.mat("rusty_metal_02", 1.0), p)
			_stripes(Vector3(2.0, 0.08, 1.1), Vector3(0, 2.28, 0), red, cream, 6, p)
			_label(["POPCORN", "CANDY FLOSS", "HOT DOGS", "TOFFEE APPLES"][rng.randi() % 4], Vector3(0, 0.8, -0.47), 40, Color(1.0, 0.95, 0.8), p, 180.0)
			_solid(at + Vector3(0, 0.65, 0), Vector3(1.9, 1.3, 1.0), yaw)
		"ducks":
			_box(Vector3(3.0, 1.15, 0.5), Vector3(0, 0.575, 0), g.mat("distressed_painted_planks", 0.8, Color(0.25, 0.45, 0.85)), p)
			_stripes(Vector3(3.0, 0.55, 0.14), Vector3(0, 1.43, 0), red, cream, 10, p)
			for k in 7:
				var x := -1.3 + k * 0.43
				_box(Vector3(0.03, 0.45, 0.03), Vector3(x, 1.9, 0), g.mat("worn_planks", 1.0), p)
				_prop("rubber_duck_toy", Vector3(x, 2.1, 0), 180.0 if k % 2 == 0 else 0.0, 2.2, p)
			_label("SHOOT THE DUCKS", Vector3(0, 0.75, -0.26), 44, Color(1.0, 0.95, 0.7), p, 180.0)
			_solid(at + Vector3(0, 0.85, 0), Vector3(3.0, 1.7, 0.5), yaw)
		"tent":
			_stripes(Vector3(3.4, 2.4, 3.0), Vector3(0, 1.2, 0), red, cream, 6, p)
			var roof := _cyl(0.05, 2.5, 1.6, Vector3(0, 3.2, 0), red, p, 4)
			roof.rotation_degrees.y = 45.0
			_box(Vector3(1.0, 1.9, 0.04), Vector3(0, 0.95, 1.52), g.mat("black_painted_planks", 0.8, Color(0.3, 0.2, 0.2)), p)
			_label("MADAME ZORA\nSEES YOUR DEATH", Vector3(0, 2.1, 1.53), 40, Color(1.0, 0.85, 0.5), p)
			_box(Vector3(0.6, 0.35, 0.02), Vector3(0.3, 4.2, 0), g.mat("grey_plaster_03", 0.6, Color(0.95, 0.85, 0.3)), p)
			_box(Vector3(0.04, 0.9, 0.04), Vector3(0, 4.1, 0), g.mat("rusty_metal_02", 1.0), p)
			_omni(at + Vector3(0, 2.0, 1.9), Color(1.0, 0.5, 0.8), 1.0, 4.0)
			_solid(at + Vector3(0, 1.3, 0), Vector3(3.4, 2.6, 3.0), yaw)
		"carousel":
			var gold: StandardMaterial3D = g.mat("rusty_metal_02", 1.0, Color(1.0, 0.85, 0.5))
			_cyl(1.6, 1.6, 0.35, Vector3(0, 0.175, 0), g.mat("worn_planks", 0.6, Color(0.8, 0.5, 0.4)), p, 16)
			_cyl(0.75, 0.75, 2.6, Vector3(0, 1.3, 0), g.mat("distressed_painted_planks", 0.8, Color(0.9, 0.85, 0.7)), p, 12)
			_cyl(0.1, 2.0, 1.0, Vector3(0, 3.1, 0), red, p, 12)
			for k in 8:
				var a := TAU * k / 8.0
				var hp := Vector3(cos(a) * 1.2, 0, sin(a) * 1.2)
				_box(Vector3(0.05, 2.25, 0.05), hp + Vector3(0, 1.45, 0), gold, p)
				_prop("horse_statue_01", hp + Vector3(0, 0.6 + (k % 2) * 0.25, 0), rad_to_deg(-a) + 90.0, 4.0, p)
				_ball(0.07, Vector3(cos(a) * 1.95, 2.62, sin(a) * 1.95), _glow(Color(1.0, 0.85, 0.3), 5.0), p)
			_label("CAROUSEL OF\nCARNAGE", Vector3(0, 3.4, 1.0), 40, Color(1.0, 0.9, 0.5), p)
			_omni(at + Vector3(0, 2.4, 0), Color(1.0, 0.8, 0.5), 1.6, 6.0)
			_solid(at + Vector3(0, 1.3, 0), Vector3(3.0, 2.6, 3.0), yaw)

## 3 · WHITEOUT LODGE: overcast snow day, frozen lake in the middle, log piles, snowmen.
func _lodge() -> Dictionary:
	_env(Color("c8d0d8"), Color(0.72, 0.8, 0.95), 0.75, Color(0.8, 0.85, 0.9), 0.02, 0.85, 0.85)
	_sky(Color(0.5, 0.58, 0.7), Color(0.85, 0.88, 0.92), Color(0.8, 0.82, 0.86), 0.9, 0.7)
	_sun(Color(0.95, 0.95, 1.0), 0.85, Vector3(-40.0, 150.0, 0.0))
	_ground("snow_02", 0.25, Color(0.92, 0.95, 1.0))
	var ice: StandardMaterial3D = g.mat("snow_02", 0.2, Color(0.55, 0.72, 0.85)).duplicate()
	ice.roughness = 0.12
	ice.metallic = 0.15
	_box(Vector3(13.0, 0.04, 11.0), Vector3(W * 0.5, 0.0, 14.8), ice)
	_box(Vector3(1.2, 0.05, 0.9), Vector3(10.2, 0.005, 11.6), g.mat("dark_rock", 1.0, Color(0.05, 0.08, 0.1)))
	_patch("snow_02", 0.4, Color(0.85, 0.85, 0.88), Vector2(W + 1.2, 3.0), Vector2(W * 0.5, 30.0), 0.012)
	_marks(g.mat("worn_planks", 1.0, Color(0.6, 0.45, 0.35)))
	var rows := [["logs", 2.6, 26.5, 0.0], ["pine", 7.0, 26.4, 0.0], ["logs", 11.2, 26.5, 6.0], ["snowman", 14.6, 26.6, 0.0],
		["drift", 4.0, 22.0, 0.0], ["snowman", 8.2, 22.2, 0.0], ["hut", 12.2, 22.0, 0.0],
		["ice", 2.8, 17.5, 0.0], ["ice", 8.2, 17.6, 8.0], ["drift", 13.4, 17.5, -5.0],
		["hut", 5.0, 13.0, 0.0], ["ice", 11.0, 13.1, -6.0], ["ice", 14.6, 13.0, 4.0],
		["logs", 2.4, 8.5, -4.0], ["drift", 7.6, 8.5, 0.0], ["logs", 13.0, 8.5, 5.0],
		["snowman", 4.6, 4.5, 0.0], ["logs", 11.0, 4.5, 0.0]]
	_covers(rows, _lodge_cover)
	var snow: StandardMaterial3D = g.mat("snow_02", 0.4, Color(0.95, 0.97, 1.0))
	var wood: StandardMaterial3D = g.mat("worn_planks", 0.8, Color(0.55, 0.42, 0.32))
	for sx in [-1.6, 17.6]:
		for k in 9:
			var b := _ball(1.0, Vector3(sx + (-0.6 if sx < 8.0 else 0.6), 0.0, -1.0 + k * 4.4), snow)
			b.scale = Vector3(1.4, 0.9, 2.6)
		_rail(Vector3(sx, 0.0, -1.0), Vector3(sx, 0.0, 35.0), wood, 1.4, 2.4, [0.7, 1.25])
	_exit(Color(0.95, 0.4, 0.25), wood)
	var logm: StandardMaterial3D = g.mat("bark_brown_02", 0.6, Color(0.6, 0.5, 0.42))
	for k in 14:
		var lg := _cyl(0.32, 0.32, 30.0, Vector3(W * 0.5, 0.32 + k * 0.62, -11.5), logm, null, 10)
		lg.rotation_degrees.z = 90.0
	var roof := _box(Vector3(32.0, 0.5, 8.0), Vector3(W * 0.5, 10.4, -13.0), g.mat("snow_02", 0.3))
	roof.rotation_degrees.x = 22.0
	for wx in [-2.0, 2.5, 13.5, 18.0]:
		_box(Vector3(2.0, 1.6, 0.1), Vector3(wx, 3.6, -11.15), _glow(Color(1.0, 0.7, 0.35), 1.8))
		_box(Vector3(2.2, 0.12, 0.3), Vector3(wx, 2.75, -11.1), snow)
	_box(Vector3(1.4, 7.0, 1.4), Vector3(W * 0.5 + 10.0, 9.5, -12.5), g.mat("dark_rock", 0.6, Color(0.6, 0.58, 0.55)))
	_parts(Vector3(W * 0.5 + 10.0, 13.5, -12.5), Vector3(0.4, 0.2, 0.4), 40, 6.0, Vector3(0.4, 1.2, 0.3), 10.0, Vector2(1.6, 1.6), Color(0.7, 0.7, 0.72, 0.25))
	_label("LODGE", Vector3(W * 0.5, 7.0, -11.1), 220, Color(0.95, 0.85, 0.6))
	for t in [Vector3(-4.5, 0, 2.0), Vector3(-6.0, 0, 11.0), Vector3(-4.2, 0, 19.0), Vector3(-5.8, 0, 28.0), Vector3(20.5, 0, 4.0), Vector3(22.0, 0, 13.0), Vector3(20.4, 0, 22.0), Vector3(21.8, 0, 31.0),
			Vector3(-10.0, 0, 6.0), Vector3(-11.0, 0, 24.0), Vector3(26.0, 0, 9.0), Vector3(27.0, 0, 26.0), Vector3(-6.0, 0, 42.0), Vector3(4.0, 0, 47.0), Vector3(14.0, 0, 45.0), Vector3(23.0, 0, 41.0), Vector3(-14.0, 0, 36.0), Vector3(31.0, 0, 36.0)]:
		_pine(t, rng.randf_range(4.5, 8.0))
	var cm: Node3D = _prop("covered_car", Vector3(-4.0, 0, -5.0), 20.0)
	if cm:
		_box(Vector3(1.7, 0.25, 4.0), Vector3(-4.0, 1.45, -5.0), snow).rotation_degrees.y = 20.0
	for o in [["wooden_axe", 19.2, 16.0], ["tree_stump_01", 19.4, 16.2], ["wooden_crate_02", -3.0, 33.0], ["barrel_03", 15.6, 33.4], ["old_tyre", 1.0, 33.6], ["propane_tank", 12.0, 33.6]]:
		_prop(o[0], Vector3(o[1], 0.35 if o[0] == "wooden_axe" else 0.0, o[2]), rng.randf() * 360.0)
	for k in 4:
		var sk := _box(Vector3(0.1, 1.8, 0.03), Vector3(18.6 + k * 0.18, 0.85, 9.0), g.mat("distressed_painted_planks", 0.8, Color(0.85, 0.2, 0.15) if k % 2 == 0 else Color(0.2, 0.3, 0.8)))
		sk.rotation_degrees.x = -12.0
	_parts(Vector3(W * 0.5, 9.0, 16.0), Vector3(22.0, 1.0, 24.0), 900, 8.0, Vector3(0.35, -1.3, 0.2), 20.0, Vector2(0.07, 0.07), Color(1.0, 1.0, 1.0, 0.9))
	_duck_lights(Color(0.85, 0.9, 1.0), 0.5)
	return {"leg": ["bark_brown_02", Color(0.6, 0.5, 0.42)], "deck": ["worn_planks", Color(0.6, 0.5, 0.42)], "wall": ["worn_planks", Color(0.7, 0.55, 0.45)], "roof": ["snow_02", Color(0.95, 0.97, 1.0)]}

func _pine(at: Vector3, h: float) -> void:
	var p := _piv(at, rng.randf() * 360.0)
	var needles: StandardMaterial3D = g.mat("forest_leaves_02", 0.6, Color(0.22, 0.36, 0.28))
	var snow: StandardMaterial3D = g.mat("snow_02", 0.4, Color(0.95, 0.97, 1.0))
	_cyl(0.12, 0.22, h * 0.3, Vector3(0, h * 0.15, 0), g.mat("bark_brown_02", 0.8, Color(0.5, 0.42, 0.38)), p, 8)
	for k in 4:
		var r := h * (0.3 - k * 0.06)
		var y := h * (0.25 + k * 0.18)
		_cyl(0.0, r, h * 0.32, Vector3(0, y + h * 0.16, 0), needles, p, 9)
		_cyl(0.0, r * 0.75, h * 0.12, Vector3(0, y + h * 0.27, 0), snow, p, 9)

func _lodge_cover(kind: String, at: Vector3, yaw: float) -> void:
	var snow: StandardMaterial3D = g.mat("snow_02", 0.4, Color(0.95, 0.97, 1.0))
	var logm: StandardMaterial3D = g.mat("bark_brown_02", 0.7, Color(0.62, 0.52, 0.45))
	var p := _piv(at, yaw)
	match kind:
		"logs":
			var lay := [[-0.44, 0.22], [0.0, 0.22], [0.44, 0.22], [-0.22, 0.6], [0.22, 0.6], [0.0, 0.98]]
			for l in lay:
				var c := _cyl(0.22, 0.22, 2.2 + rng.randf_range(-0.15, 0.15), Vector3(rng.randf_range(-0.1, 0.1), l[1], l[0]), logm, p, 10)
				c.rotation_degrees.z = 90.0
			var cap := _ball(0.6, Vector3(0, 1.15, 0), snow, p)
			cap.scale = Vector3(1.9, 0.25, 0.8)
			_solid(at + Vector3(0, 0.62, 0), Vector3(2.2, 1.25, 1.3), yaw)
		"pine":
			_pine(at, 4.2)
			_solid(at + Vector3(0, 1.3, 0), Vector3(1.4, 2.6, 1.4), yaw)
		"snowman":
			_ball(0.55, Vector3(0, 0.45, 0), snow, p)
			_ball(0.4, Vector3(0, 1.2, 0), snow, p)
			_ball(0.28, Vector3(0, 1.75, 0), snow, p)
			var nose := _cyl(0.0, 0.05, 0.3, Vector3(0, 1.75, -0.36), g.mat("distressed_painted_planks", 1.0, Color(1.0, 0.45, 0.1)), p, 6)
			nose.rotation_degrees.x = -90.0
			for e in [-0.1, 0.1]:
				_ball(0.035, Vector3(e, 1.84, -0.25), g.mat("dark_rock", 1.0, Color(0.1, 0.1, 0.1)), p)
			for s in [-1.0, 1.0]:
				_limb(Vector3(s * 0.3, 1.3, 0), Vector3(0, 0, -s * 1.1), 0.7, 0.03, 0.015, logm, p)
			if rng.randf() < 0.6:
				var ax: Node3D = _prop("wooden_axe", Vector3(0.12, 1.95, -0.1), 0.0, 1.4, p)
				if ax:
					ax.rotation_degrees.z = 30.0
			_solid(at + Vector3(0, 0.95, 0), Vector3(1.1, 1.9, 1.1), yaw)
		"drift":
			for k in 3:
				var b := _ball(1.0, Vector3(-0.9 + k * 0.9, 0.3 + (k % 2) * 0.1, 0), snow, p)
				b.scale = Vector3(0.9, 1.0, 0.65)
			_solid(at + Vector3(0, 0.65, 0), Vector3(3.0, 1.3, 1.2), yaw)
		"hut":
			var red: StandardMaterial3D = g.mat("distressed_painted_planks", 0.7, Color(0.75, 0.22, 0.18))
			_box(Vector3(2.6, 2.3, 2.2), Vector3(0, 1.15, 0), red, p)
			var rf := _box(Vector3(3.0, 0.3, 2.6), Vector3(0, 2.45, 0), snow, p)
			rf.rotation_degrees.x = 8.0
			_box(Vector3(0.6, 0.45, 0.06), Vector3(0.6, 1.5, 1.11), _glow(Color(1.0, 0.75, 0.4), 1.5), p)
			_box(Vector3(0.8, 1.7, 0.06), Vector3(-0.6, 0.85, 1.11), g.mat("worn_planks", 0.8, Color(0.5, 0.4, 0.3)), p)
			_cyl(0.08, 0.08, 1.0, Vector3(0.9, 2.9, -0.5), g.mat("rusty_metal_02", 1.0), p, 8)
			_label("BAIT", Vector3(0, 1.9, -1.12), 60, Color(0.95, 0.9, 0.8), p, 180.0)
			_solid(at + Vector3(0, 1.2, 0), Vector3(2.6, 2.4, 2.2), yaw)
		"ice":
			var im := StandardMaterial3D.new()
			im.albedo_color = Color(0.7, 0.86, 0.95, 0.9)
			im.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			im.roughness = 0.08
			im.metallic = 0.1
			im.rim_enabled = true
			im.rim = 0.6
			_box(Vector3(1.7, 0.75, 1.0), Vector3(0, 0.375, 0), im, p)
			var t := _box(Vector3(1.1, 0.7, 0.9), Vector3(rng.randf_range(-0.25, 0.25), 1.1, 0.02), im, p)
			t.rotation_degrees.y = rng.randf_range(-10.0, 10.0)
			_box(Vector3(1.75, 0.08, 1.05), Vector3(0, 0.78, 0), snow, p)
			_solid(at + Vector3(0, 0.72, 0), Vector3(1.7, 1.45, 1.0), yaw)

## 4 · TEMPLE OF THE LOST: humid golden jungle ruins, broken pillars, idols, a step pyramid.
func _temple() -> Dictionary:
	_env(Color("4d5a3a"), Color(0.55, 0.64, 0.42), 0.75, Color(0.45, 0.52, 0.32), 0.02, 1.08, 1.05)
	_sky(Color(0.32, 0.48, 0.42), Color(0.88, 0.82, 0.52), Color(0.15, 0.2, 0.12), 1.0, 0.6)
	var env: Environment = g.env
	env.fog_sun_scatter = 0.35
	_sun(Color(1.0, 0.85, 0.55), 1.25, Vector3(-34.0, 205.0, 0.0))
	_ground("forest_leaves_02", 0.35, Color(0.7, 0.75, 0.55))
	for k in 18:
		var s := _patch("mossy_stone_wall", 0.5, Color(0.7, 0.72, 0.62), Vector2(rng.randf_range(1.4, 2.4), rng.randf_range(1.4, 2.2)), Vector2(W * 0.5 + rng.randf_range(-2.0, 2.0), -1.0 + k * 2.0), 0.005 * (k % 3))
		s.rotation_degrees.y = rng.randf_range(-12.0, 12.0)
	_marks(g.mat("mossy_stone_wall", 1.0, Color(0.85, 0.8, 0.6)))
	var rows := [["fallen", 3.0, 26.5, 22.0], ["block", 8.6, 26.5, 0.0], ["pillar", 13.6, 26.6, 0.0],
		["ruin", 5.0, 22.0, -12.0], ["pillar2", 10.0, 22.2, 0.0], ["fallen", 13.6, 21.8, -28.0],
		["pillar2", 2.0, 17.5, 0.0], ["idol", 7.6, 17.5, 0.0], ["block", 12.2, 17.5, 10.0],
		["block", 3.4, 13.0, -8.0], ["fallen", 8.8, 13.0, 32.0], ["ruin", 13.4, 13.0, 14.0],
		["ruin", 3.2, 8.5, 18.0], ["pillar", 8.0, 8.6, 0.0], ["block", 12.6, 8.5, -6.0],
		["fallen", 5.4, 4.5, -18.0], ["idol", 11.6, 4.5, 0.0]]
	_covers(rows, _temple_cover)
	var stone: StandardMaterial3D = g.mat("mossy_stone_wall", 0.5, Color(0.62, 0.66, 0.52))
	for sx in [-1.6, 17.6]:
		var z := -1.0
		while z < 35.0:
			var l := rng.randf_range(2.5, 4.5)
			var h := rng.randf_range(0.7, 1.6)
			_box(Vector3(0.7, h, l), Vector3(sx, h * 0.5, z + l * 0.5), stone)
			z += l + rng.randf_range(0.2, 1.2)
		for k in 7:
			_prop("fern_02", Vector3(sx + (-0.4 if sx < 8.0 else 0.4), 0, k * 5.0 + rng.randf()), rng.randf() * 360.0, 1.0)
	_exit(Color(1.0, 0.8, 0.35), stone)
	for tx in [-1.4, 17.4]:
		_brazier(Vector3(tx, 3.9, -0.6))
	var tiers := [[34.0, 3.0, 9.0], [27.0, 3.0, 7.0], [20.0, 3.0, 5.0], [13.0, 3.0, 3.0], [7.0, 3.2, 2.0]]
	var y := 0.0
	for t in tiers:
		_box(Vector3(t[0], t[1], t[2] + 4.0), Vector3(W * 0.5, y + t[1] * 0.5, -14.0 - (9.0 - t[2]) * 0.0), g.mat("mossy_stone_wall", 0.35, Color(0.6, 0.62, 0.5)))
		y += t[1]
	_box(Vector3(3.0, 3.8, 0.2), Vector3(W * 0.5, 13.9, -14.0 + 2.05), g.mat("dark_rock", 1.0, Color(0.05, 0.05, 0.04)))
	_box(Vector3(3.0, 5.0, 0.2), Vector3(W * 0.5, 2.5, -14.0 + 6.55), g.mat("dark_rock", 1.0, Color(0.04, 0.04, 0.03)))
	for bx in [-6.0, 22.0]:
		_prop("lion_head", Vector3(bx, 0.0, -8.0), 0.0, 9.0)
	_brazier(Vector3(W * 0.5 - 2.2, 15.4, -12.0))
	_brazier(Vector3(W * 0.5 + 2.2, 15.4, -12.0))
	var bark: StandardMaterial3D = g.mat("bark_brown_02", 0.6, Color(0.55, 0.5, 0.42))
	var leaf: StandardMaterial3D = g.mat("forest_leaves_02", 0.5, Color(0.35, 0.55, 0.22))
	for t in [Vector3(-4.8, 0, 3.0), Vector3(-5.5, 0, 14.0), Vector3(-4.5, 0, 25.0), Vector3(21.0, 0, 6.0), Vector3(20.5, 0, 17.0), Vector3(21.5, 0, 29.0), Vector3(-10.0, 0, 34.0), Vector3(4.0, 0, 44.0), Vector3(16.0, 0, 42.0), Vector3(27.0, 0, 38.0), Vector3(-12.0, 0, 10.0), Vector3(28.0, 0, 16.0)]:
		_jungle_tree(t, rng.randf_range(9.0, 13.0), bark, leaf)
	for o in [["rock_moss_set_01", -8.0, 20.0, 0.5], ["rock_moss_set_01", 25.0, 24.0, 0.5], ["marble_bust_01", -2.6, 9.0, 1.6], ["moss_01", 3.0, 30.0, 4.0], ["moss_01", 12.0, 2.0, 4.0], ["fern_02", 1.0, 33.0, 1.0], ["fern_02", 13.0, 33.0, 1.0], ["tree_stump_01", 19.0, 33.0, 1.0]]:
		_prop(o[0], Vector3(o[1], 0, o[2]), rng.randf() * 360.0, o[3])
	_parts(Vector3(W * 0.5, 1.8, 15.0), Vector3(12.0, 1.4, 18.0), 90, 6.0, Vector3(0.2, 0.15, 0.1), 180.0, Vector2(0.06, 0.06), Color(1.0, 1.0, 0.55, 0.95))
	_duck_lights(Color(1.0, 0.9, 0.6), 0.6)
	return {"leg": ["bark_brown_02", Color(0.6, 0.55, 0.45)], "deck": ["worn_planks", Color(0.6, 0.55, 0.42)], "wall": ["old_planks_02", Color(0.6, 0.6, 0.45)], "roof": ["forest_leaves_02", Color(0.35, 0.5, 0.25)]}

func _brazier(at: Vector3) -> void:
	_cyl(0.35, 0.22, 0.4, at + Vector3(0, 0.2, 0), g.mat("rusty_metal_02", 1.0, Color(0.6, 0.5, 0.4)), null, 10)
	_ball(0.28, at + Vector3(0, 0.5, 0), _glow(Color(1.0, 0.55, 0.15), 6.0))
	_parts(at + Vector3(0, 0.7, 0), Vector3(0.15, 0.05, 0.15), 24, 0.8, Vector3(0, 1.4, 0), 12.0, Vector2(0.3, 0.4), Color(1.0, 0.6, 0.2, 0.7))
	_omni(at + Vector3(0, 0.8, 0.3), Color(1.0, 0.6, 0.25), 2.4, 8.0)

func _jungle_tree(at: Vector3, h: float, bark: Material, leaf: Material) -> void:
	var p := _piv(at, rng.randf() * 360.0)
	_limb(Vector3.ZERO, Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)), h, 0.45, 0.22, bark, p)
	for k in 4:
		var rot := Vector3(rng.randf_range(0.2, 0.8), k * 1.6, 0)
		_limb(Vector3(-0.4 + k * 0.25, 0.0, 0.0), Vector3(-0.9, k * 1.6, 0), 1.2, 0.18, 0.08, bark, p)
		var top := Vector3(0, h * 0.85, 0) + Basis.from_euler(rot) * Vector3(0, 2.0, 0)
		_limb(Vector3(0, h * 0.85, 0), rot, 2.2, 0.16, 0.08, bark, p)
		for j in 3:
			var c := _ball(rng.randf_range(1.2, 1.8), top + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.4, 0.6), rng.randf_range(-0.9, 0.9)), leaf, p)
			c.scale = Vector3(1.2, 0.8, 1.2)
	for k in 5:
		var vl := rng.randf_range(2.5, 5.0)
		_box(Vector3(0.05, vl, 0.05), Vector3(rng.randf_range(-2.0, 2.0), h * 0.95 - vl * 0.5, rng.randf_range(-2.0, 2.0)), leaf, p)

func _temple_cover(kind: String, at: Vector3, yaw: float) -> void:
	var stone: StandardMaterial3D = g.mat("mossy_stone_wall", 0.8, Color(0.75, 0.75, 0.62))
	var moss: StandardMaterial3D = g.mat("forest_leaves_02", 0.8, Color(0.4, 0.55, 0.28))
	var p := _piv(at, yaw)
	match kind:
		"pillar", "pillar2":
			var h := 1.45 if kind == "pillar" else 3.0
			_box(Vector3(1.25, 0.3, 1.25), Vector3(0, 0.15, 0), stone, p)
			_cyl(0.52, 0.55, h - 0.3, Vector3(0, 0.3 + (h - 0.3) * 0.5, 0), stone, p, 12)
			var cap := _box(Vector3(1.1, 0.25, 1.1), Vector3(0.05, h + 0.1, 0), stone, p)
			cap.rotation_degrees.z = rng.randf_range(-8.0, 8.0)
			_prop("fern_02", Vector3(0.2, 0, 0.5), rng.randf() * 360.0, 0.6, p)
			var mm := _box(Vector3(1.0, 0.06, 1.0), Vector3(0, h + 0.25, 0), moss, p)
			mm.rotation_degrees.z = cap.rotation_degrees.z
			_solid(at + Vector3(0, (h + 0.2) * 0.5, 0), Vector3(1.2, h + 0.2, 1.2), yaw)
		"fallen":
			for s in [-0.8, 0.8]:
				var c := _cyl(0.6, 0.6, 1.55, Vector3(s, 0.6, 0), stone, p, 12)
				c.rotation_degrees.z = 90.0 + rng.randf_range(-3.0, 3.0)
			var m2 := _ball(0.5, Vector3(0.4, 1.1, 0), moss, p)
			m2.scale = Vector3(1.8, 0.25, 0.9)
			_prop("fern_02", Vector3(-1.2, 0, 0.6), 30.0, 0.5, p)
			_solid(at + Vector3(0, 0.6, 0), Vector3(3.2, 1.2, 1.2), yaw)
		"block":
			_box(Vector3(1.8, 0.65, 1.2), Vector3(0, 0.325, 0), stone, p)
			var b := _box(Vector3(1.0, 0.65, 1.0), Vector3(-0.35, 0.975, 0.05), stone, p)
			b.rotation_degrees.y = rng.randf_range(-15.0, 15.0)
			var b2 := _box(Vector3(0.7, 0.55, 0.8), Vector3(0.5, 0.92, -0.1), stone, p)
			b2.rotation_degrees = Vector3(0, rng.randf_range(-20.0, 20.0), 6.0)
			_box(Vector3(1.0, 0.05, 1.0), Vector3(-0.35, 1.32, 0.05), moss, p)
			_solid(at + Vector3(0, 0.65, 0), Vector3(1.8, 1.3, 1.2), yaw)
		"ruin":
			_box(Vector3(3.4, 1.8, 0.6), Vector3(0, 0.9, 0), stone, p)
			_box(Vector3(1.8, 0.7, 0.6), Vector3(-0.8, 2.15, 0), stone, p)
			_box(Vector3(0.7, 0.35, 0.6), Vector3(0.6, 1.97, 0), stone, p)
			_box(Vector3(3.5, 0.06, 0.7), Vector3(0, 1.82, 0), moss, p)
			for k in 3:
				_box(Vector3(0.05, 1.4, 0.05), Vector3(-1.5 + k * 1.2, 1.6, 0.33), moss, p)
			_solid(at + Vector3(0, 0.9, 0), Vector3(3.4, 1.8, 0.6), yaw)
			_solid(at + Vector3(-0.8, 0, 0).rotated(Vector3.UP, deg_to_rad(yaw)) + Vector3(0, 2.15, 0), Vector3(1.8, 0.7, 0.6), yaw)
		"idol":
			_box(Vector3(1.4, 0.9, 1.2), Vector3(0, 0.45, 0), stone, p)
			_prop("lion_head", Vector3(0, 0.9, 0), 180.0, 3.4, p)
			_box(Vector3(1.45, 0.05, 1.25), Vector3(0, 0.92, 0), moss, p)
			_solid(at + Vector3(0, 1.2, 0), Vector3(1.4, 2.4, 1.2), yaw)

## 5 · SEWAGE CANAL: flooded brick canal at night, sodium lamps, toxic sludge, rats.
func _sewer() -> Dictionary:
	_env(Color("030503"), Color(0.45, 0.48, 0.34), 0.85, Color(0.12, 0.15, 0.08), 0.024, 1.5, 0.8)
	var env: Environment = g.env
	env.ssr_enabled = true
	_sun(Color(0.5, 0.62, 0.4), 0.18, Vector3(-62.0, 170.0, 0.0))
	_ground("damaged_concrete_floor", 0.35, Color(0.35, 0.38, 0.3))
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.17, 0.21, 0.09, 0.8)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.04
	water.metallic = 0.2
	water.normal_enabled = true
	water.normal_texture = load("res://assets/ph/tex/dirty_concrete/nor.jpg") if ResourceLoader.exists("res://assets/ph/tex/dirty_concrete/nor.jpg") else null
	water.normal_scale = 0.25
	water.uv1_triplanar = true
	water.uv1_world_triplanar = true
	water.uv1_scale = Vector3.ONE * 0.15
	_box(Vector3(W + 2.6, 0.04, 40.0), Vector3(W * 0.5, 0.12, 15.0), water)
	_marks(_glow(Color(0.9, 0.55, 0.15), 0.6))
	var rows := [["drums", 2.4, 26.5, 0.0], ["pipe", 8.0, 26.5, 0.0], ["drums", 13.6, 26.5, 0.0],
		["pillar", 3.8, 22.0, 0.0], ["dumpster", 9.4, 22.0, 4.0], ["pillar", 13.4, 22.0, 0.0],
		["sluice", 2.2, 17.5, 0.0], ["wreck", 7.6, 17.5, 82.0], ["sluice", 13.4, 17.5, 0.0],
		["pipe", 3.8, 13.0, 10.0], ["pillar", 9.2, 13.0, 0.0], ["drums", 13.8, 13.0, 0.0],
		["dumpster", 3.0, 8.5, -4.0], ["sluice", 8.4, 8.5, 0.0], ["pipe", 13.2, 8.5, -10.0],
		["drums", 5.6, 4.5, 0.0], ["drums", 11.0, 4.5, 0.0]]
	_covers(rows, _sewer_cover)
	var brick: StandardMaterial3D = g.mat("mossy_brick", 0.35, Color(0.55, 0.52, 0.45))
	var conc: StandardMaterial3D = g.mat("dirty_concrete", 0.4, Color(0.5, 0.5, 0.45))
	var iron: StandardMaterial3D = g.mat("rusty_metal_02", 1.2, Color(0.6, 0.55, 0.5))
	for sx in [-1.0, 17.0]:
		var side := -1.0 if sx < 8.0 else 1.0
		_box(Vector3(1.6, 0.5, 40.0), Vector3(sx + side * 0.5, 0.25, 15.0), conc)
		_rail(Vector3(sx - side * 0.25, 0.5, -1.0), Vector3(sx - side * 0.25, 0.5, 35.0), iron, 1.0, 3.0, [0.95])
		_box(Vector3(0.8, 9.0, 40.0), Vector3(sx + side * 1.7, 4.5, 15.0), brick)
		for z in [3.0, 11.0, 19.0, 27.0]:
			var pp := _cyl(0.55, 0.55, 1.6, Vector3(sx + side * 1.0, 1.2, z), iron, null, 14)
			pp.rotation_degrees.z = 90.0
			_box(Vector3(0.08, 0.9, 0.9), Vector3(sx + side * 0.2, 1.2, z), _glow(Color(0.35, 0.9, 0.2), 0.6))
			if z == 11.0 or z == 27.0:
				_parts(Vector3(sx + side * 0.1, 1.0, z), Vector3(0.05, 0.05, 0.3), 60, 0.7, Vector3(-side * 1.0, -2.5, 0), 6.0, Vector2(0.25, 0.25), Color(0.45, 0.85, 0.2, 0.75))
		for z in [-1.0, 7.0, 15.0, 23.0, 31.0]:
			_box(Vector3(0.3, 0.25, 0.5), Vector3(sx + side * 1.2, 4.8, z), iron)
			_box(Vector3(0.22, 0.05, 0.35), Vector3(sx + side * 1.05, 4.66, z), _glow(Color(1.0, 0.62, 0.22), 5.0))
			_spot(Vector3(sx + side * 1.0, 4.6, z), Vector3(W * 0.5, 0.0, z + 1.0), Color(1.0, 0.6, 0.25), 9.0, 14.0, 50.0, z == 15.0 or z == 23.0)
		for k in 3:
			_prop("street_rat", Vector3(sx + side * 0.4, 0.5, 5.0 + k * 11.0), rng.randf() * 360.0, 2.0)
		var pl := _cyl(0.18, 0.18, 40.0, Vector3(sx + side * 1.2, 6.5, 15.0), iron, null, 8)
		pl.rotation_degrees.x = 90.0
	for z in [5.0, 15.0, 25.0]:
		_box(Vector3(22.0, 1.4, 1.2), Vector3(W * 0.5, 7.2, z), brick)
		_box(Vector3(22.0, 0.3, 1.3), Vector3(W * 0.5, 6.45, z), conc)
		for lx in [4.0, 12.0]:
			g.lamp(Vector3(lx, 6.3, z + 0.9), 7.0, Color(1.0, 0.7, 0.35))
	_exit(Color(0.4, 1.0, 0.3), g.mat("rusty_metal_02", 1.0, Color(0.5, 0.48, 0.42)), "EXIT")
	_box(Vector3(40.0, 14.0, 1.0), Vector3(W * 0.5, 7.0, -11.0), brick)
	var mouth := _cyl(5.0, 5.0, 0.3, Vector3(W * 0.5, 3.5, -10.4), g.mat("dark_rock", 1.0, Color(0.02, 0.02, 0.02)), null, 24)
	mouth.rotation_degrees.x = 90.0
	var ring := _cyl(5.6, 5.6, 0.2, Vector3(W * 0.5, 3.5, -10.48), conc, null, 24)
	ring.rotation_degrees.x = 90.0
	for k in 9:
		_box(Vector3(0.18, 8.0, 0.18), Vector3(W * 0.5 - 4.0 + k * 1.0, 3.5, -10.1), iron)
	_omni(Vector3(W * 0.5, 2.0, -9.0), Color(0.4, 0.9, 0.3), 2.0, 10.0)
	for o in [["trashbag", 6.0, 30.6], ["plastic_bottle_gallon", 4.2, 24.0], ["bleach_bottle", 11.6, 19.6], ["rubber_duck_toy", 9.8, 15.4], ["trashbag", 1.2, 11.2], ["plastic_bottle_gallon", 15.0, 6.6], ["rubber_duck_toy", 6.6, 2.6], ["can_rusted", 12.4, 28.6], ["water_manhole_cover", -1.2, 20.0], ["industrial_pastic_container", 17.2, 9.0], ["barrel_03", -1.2, 33.0], ["metal_jerrycan", 17.4, 31.0]]:
		var y := 0.5 if absf(float(o[1]) - 8.0) > 8.5 else 0.06
		_prop(o[0], Vector3(o[1], y, o[2]), rng.randf() * 360.0, 1.4 if o[0] == "rubber_duck_toy" else 1.0)
	_parts(Vector3(W * 0.5, 0.6, 15.0), Vector3(10.0, 0.3, 18.0), 50, 8.0, Vector3(0.1, 0.05, 0.1), 60.0, Vector2(4.0, 1.4), Color(0.45, 0.6, 0.3, 0.06))
	_duck_lights(Color(0.6, 0.95, 0.5), 0.8)
	return {"leg": ["rusty_metal_02", Color(0.7, 0.65, 0.55)], "deck": ["metal_grate_rusty", Color(0.7, 0.65, 0.55)], "wall": ["green_metal_rust", Color(0.8, 0.85, 0.75)], "roof": ["corrugated_iron", Color(0.45, 0.48, 0.4)]}

func _sewer_cover(kind: String, at: Vector3, yaw: float) -> void:
	var conc: StandardMaterial3D = g.mat("dirty_concrete", 0.5, Color(0.55, 0.55, 0.5))
	var iron: StandardMaterial3D = g.mat("rusty_metal_02", 1.0, Color(0.7, 0.62, 0.55))
	var p := _piv(at, yaw)
	match kind:
		"drums":
			_box(Vector3(1.9, 0.14, 0.9), Vector3(0, 0.07, 0), g.mat("worn_planks", 0.8, Color(0.5, 0.45, 0.4)), p)
			for k in 3:
				var b: Node3D = _prop("barrel_03", Vector3(-0.62 + k * 0.62, 0.14, rng.randf_range(-0.08, 0.08)), rng.randf() * 360.0, 1.05, p)
				if b:
					b.rotation_degrees.z = rng.randf_range(-3.0, 3.0)
			_box(Vector3(0.5, 0.02, 0.3), Vector3(0, 0.8, -0.33), _glow(Color(0.95, 0.85, 0.1), 0.5), p)
			_label("TOXIC", Vector3(0, 0.6, -0.34), 50, Color(0.95, 0.85, 0.1), p, 180.0)
			_ball(0.4, Vector3(0.3, 0.14, 0.5), _glow(Color(0.35, 0.95, 0.15), 1.4), p).scale = Vector3(1.6, 0.06, 1.0)
			_solid(at + Vector3(0, 0.6, 0), Vector3(1.9, 1.2, 0.8), yaw)
		"pipe":
			var c := _cyl(0.8, 0.8, 3.2, Vector3(0, 0.8, 0), conc, p, 16)
			c.rotation_degrees.z = 90.0
			for s in [-1.0, 1.0]:
				var r := _cyl(0.86, 0.86, 0.2, Vector3(s * 1.5, 0.8, 0), iron, p, 16)
				r.rotation_degrees.z = 90.0
			var hole := _cyl(0.62, 0.62, 0.02, Vector3(1.61, 0.8, 0), g.mat("dark_rock", 1.0, Color(0.02, 0.02, 0.02)), p, 16)
			hole.rotation_degrees.z = 90.0
			_solid(at + Vector3(0, 0.8, 0), Vector3(3.2, 1.6, 1.5), yaw)
		"pillar":
			_box(Vector3(1.2, 6.5, 1.2), Vector3(0, 3.25, 0), g.mat("mossy_brick", 0.5, Color(0.55, 0.52, 0.45)), p)
			_box(Vector3(1.3, 0.6, 1.3), Vector3(0, 0.3, 0), conc, p)
			_box(Vector3(1.25, 0.6, 1.25), Vector3(0, 0.35, 0), _glow(Color(0.3, 0.6, 0.15), 0.15), p)
			_solid(at + Vector3(0, 3.0, 0), Vector3(1.3, 6.0, 1.3), yaw)
		"dumpster":
			var green: StandardMaterial3D = g.mat("green_metal_rust", 0.7, Color(0.7, 0.8, 0.65))
			_box(Vector3(2.4, 1.5, 1.4), Vector3(0, 0.75, 0), green, p)
			var lid := _box(Vector3(2.45, 0.08, 1.45), Vector3(0, 1.62, -0.1), green, p)
			lid.rotation_degrees.x = -14.0
			_prop("trashbag", Vector3(0.6, 1.45, 0.2), 30.0, 1.0, p)
			_solid(at + Vector3(0, 0.8, 0), Vector3(2.4, 1.6, 1.4), yaw)
		"sluice":
			_box(Vector3(2.4, 1.3, 0.8), Vector3(0, 0.65, 0), conc, p)
			for s in [-1.0, 1.0]:
				_box(Vector3(0.2, 2.4, 0.2), Vector3(s * 0.9, 1.2, -0.45), iron, p)
			_box(Vector3(2.0, 0.2, 0.2), Vector3(0, 2.4, -0.45), iron, p)
			var wheel := _cyl(0.35, 0.35, 0.06, Vector3(0, 2.62, -0.45), iron, p, 12)
			wheel.rotation_degrees.x = 90.0
			_box(Vector3(1.6, 0.5, 0.06), Vector3(0, 1.55, -0.45), iron, p)
			_solid(at + Vector3(0, 0.7, 0), Vector3(2.4, 1.4, 0.8), yaw)
		"wreck":
			_prop("covered_car", Vector3(0, -0.15, 0), 0.0, 1.0, p)
			_box(Vector3(1.9, 0.3, 4.5), Vector3(0, 0.15, 0), _glow(Color(0.25, 0.5, 0.1), 0.1), p)
			_solid(at + Vector3(0, 0.7, 0), Vector3(1.8, 1.4, 4.4), yaw)

## 6 · BBQ GONE WRONG: sunny suburban backyard, hedges, flipped tables, smoking grills.
func _bbq() -> Dictionary:
	_env(Color("8fb4dc"), Color(0.75, 0.72, 0.62), 0.75, Color(0.7, 0.76, 0.82), 0.006, 0.95, 1.05)
	_sky(Color(0.22, 0.42, 0.8), Color(0.78, 0.84, 0.92), Color(0.3, 0.35, 0.25), 1.0, 0.2)
	_sun(Color(1.0, 0.88, 0.7), 1.5, Vector3(-38.0, 145.0, 0.0))
	_ground("leafy_grass", 0.3, Color(0.62, 0.86, 0.48))
	_patch("painted_concrete", 0.4, Color(0.85, 0.82, 0.78), Vector2(W + 1.2, 4.0), Vector2(W * 0.5, 30.6))
	_patch("worn_planks", 0.6, Color(0.75, 0.6, 0.45), Vector2(W + 4.0, 5.0), Vector2(W * 0.5, -3.5))
	_marks(g.mat("distressed_painted_planks", 1.0, Color(0.95, 0.95, 0.9)))
	var rows := [["hedge", 2.8, 26.5, 0.0], ["grill", 8.0, 26.5, 0.0], ["hedge", 13.4, 26.5, 0.0],
		["shed", 3.6, 22.0, 0.0], ["table", 9.0, 22.0, 8.0], ["planters", 13.6, 22.0, 0.0],
		["table", 2.0, 17.5, -6.0], ["hedge", 6.6, 17.5, 0.0], ["grill", 11.0, 17.5, 0.0], ["table", 14.6, 17.5, 10.0],
		["car", 3.4, 13.0, 90.0], ["planters", 8.6, 13.0, 0.0], ["shed", 12.8, 13.0, 0.0],
		["grill", 2.4, 8.5, 0.0], ["table", 6.4, 8.5, -8.0], ["hedge", 10.6, 8.5, 0.0], ["planters", 14.2, 8.5, 0.0],
		["hedge", 4.6, 4.5, 0.0], ["table", 11.2, 4.5, 4.0]]
	_covers(rows, _bbq_cover)
	var fence: StandardMaterial3D = g.mat("old_planks_02", 0.8, Color(0.85, 0.72, 0.58))
	for sx in [-1.4, 17.4]:
		for k in 72:
			_box(Vector3(0.06, 1.8 + (k % 2) * 0.1, 0.48), Vector3(sx, 0.9, -1.0 + k * 0.5), fence)
		_box(Vector3(0.1, 0.1, 36.0), Vector3(sx + (-0.08 if sx < 8.0 else 0.08), 1.4, 17.0), fence)
	for k in 37:
		_box(Vector3(0.48, 1.0, 0.06), Vector3(-1.4 + k * 0.5, 0.5, 35.0), fence)
	_exit(Color(1.0, 0.9, 0.4), fence)
	var brick: StandardMaterial3D = g.mat("factory_brick", 0.4, Color(0.9, 0.75, 0.65))
	_box(Vector3(40.0, 6.0, 1.0), Vector3(W * 0.5, 3.0, -11.0), brick)
	var roof := _box(Vector3(42.0, 0.4, 7.0), Vector3(W * 0.5, 7.4, -12.6), g.mat("corrugated_iron", 0.6, Color(0.55, 0.3, 0.25)))
	roof.rotation_degrees.x = 28.0
	for wx in [-4.0, 1.0, 15.0, 20.0]:
		_box(Vector3(2.2, 1.6, 0.1), Vector3(wx, 3.6, -10.45), _glow(Color(0.6, 0.75, 0.9), 0.5))
		_box(Vector3(2.4, 0.15, 0.25), Vector3(wx, 2.75, -10.4), g.mat("painted_concrete", 1.0))
	_box(Vector3(4.0, 2.6, 0.1), Vector3(W * 0.5, 1.4, -10.45), _glow(Color(0.7, 0.85, 1.0), 0.35))
	_bulbs(Vector3(-4.0, 5.2, -10.3), Vector3(20.0, 5.2, -10.3), 30, [Color(1.0, 0.85, 0.5)], 0.6)
	for o in [["garden_gnome", -0.6, 3.0, 1.6], ["garden_gnome", 16.6, 11.0, 1.6], ["garden_gnome", -0.6, 20.0, 1.6], ["plastic_monobloc_chair_01", 1.0, 33.4, 1.0], ["plastic_monobloc_chair_01", 3.0, 33.0, 1.0], ["outdoor_table_chair_set_01", 14.4, 33.2, 1.0], ["hamburger_buns", 10.0, 33.6, 1.5], ["barrel_stove", 12.2, 33.4, 1.0], ["potted_plant_02", -0.4, 31.0, 1.4], ["potted_plant_02", 16.4, 31.0, 1.4], ["wooden_picnic_table", -5.0, 25.0, 1.0], ["planter_box_01", 19.0, 5.0, 1.0]]:
		_prop(o[0], Vector3(o[1], 0, o[2]), rng.randf() * 360.0, o[3])
	var pool := _cyl(1.0, 1.0, 0.4, Vector3(8.0, 0.2, 33.4), g.mat("rubber_tiles", 0.8, Color(0.3, 0.55, 0.95)), null, 20)
	pool.scale = Vector3(1.6, 1.0, 1.0)
	var wat := StandardMaterial3D.new()
	wat.albedo_color = Color(0.4, 0.75, 0.9, 0.85)
	wat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wat.roughness = 0.05
	var wtop := _cyl(0.92, 0.92, 0.02, Vector3(8.0, 0.36, 33.4), wat, null, 20)
	wtop.scale = Vector3(1.6, 1.0, 1.0)
	_prop("rubber_duck_toy", Vector3(8.4, 0.36, 33.2), 40.0, 1.5)
	for t in [Vector3(-5.0, 0, 6.0), Vector3(-6.0, 0, 18.0), Vector3(22.0, 0, 3.0), Vector3(21.0, 0, 20.0), Vector3(-3.0, 0, 42.0), Vector3(12.0, 0, 44.0), Vector3(26.0, 0, 36.0)]:
		_jungle_tree(t, rng.randf_range(7.0, 10.0), g.mat("bark_brown_02", 0.7, Color(0.7, 0.62, 0.55)), g.mat("forest_leaves_02", 0.5, Color(0.45, 0.65, 0.3)))
	for k in 3:
		var nb := _box(Vector3(8.0, 5.0, 7.0), Vector3(-14.0 + k * 22.0 if k < 2 else 30.0, 2.5, 48.0), g.mat("grey_plaster_03", 0.4, [Color(0.95, 0.88, 0.75), Color(0.75, 0.82, 0.9), Color(0.9, 0.75, 0.7)][k]))
		nb.rotation_degrees.y = rng.randf_range(-6.0, 6.0)
	_duck_lights(Color(1.0, 0.95, 0.85), 0.35)
	return {"leg": ["worn_planks", Color(0.8, 0.65, 0.5)], "deck": ["worn_planks", Color(0.8, 0.65, 0.5)], "wall": ["old_planks_02", Color(0.9, 0.78, 0.62)], "roof": ["corrugated_iron", Color(0.3, 0.5, 0.3)]}

func _bbq_cover(kind: String, at: Vector3, yaw: float) -> void:
	var leaf: StandardMaterial3D = g.mat("forest_leaves_02", 0.9, Color(0.32, 0.52, 0.22))
	var p := _piv(at, yaw)
	match kind:
		"hedge":
			_box(Vector3(3.0, 1.8, 0.9), Vector3(0, 0.9, 0), leaf, p)
			for k in 4:
				var b := _ball(0.55, Vector3(-1.1 + k * 0.73, 1.75, rng.randf_range(-0.1, 0.1)), leaf, p)
				b.scale = Vector3(1.0, 0.5, 0.85)
			_prop("nettle_plant", Vector3(-1.2, 0, 0.5), 0.0, 1.0, p)
			_solid(at + Vector3(0, 0.95, 0), Vector3(3.0, 1.9, 0.9), yaw)
		"grill":
			var brick: StandardMaterial3D = g.mat("factory_brick", 0.8, Color(0.85, 0.6, 0.5))
			_box(Vector3(1.8, 0.95, 0.9), Vector3(0, 0.475, 0), brick, p)
			_box(Vector3(1.4, 0.06, 0.6), Vector3(0, 1.0, 0), g.mat("metal_grate_rusty", 1.5, Color(0.4, 0.38, 0.36)), p)
			_box(Vector3(0.5, 0.6, 0.5), Vector3(0.65, 1.25, -0.2), brick, p)
			_box(Vector3(1.0, 0.04, 0.5), Vector3(-0.2, 0.99, 0), _glow(Color(1.0, 0.35, 0.08), 3.0), p)
			for k in 4:
				var s := _cyl(0.04, 0.04, 0.35, Vector3(-0.5 + k * 0.2, 1.06, 0.05), g.mat("dark_rock", 1.0, Color(0.3, 0.12, 0.08)), p, 6)
				s.rotation_degrees.x = 90.0
			_parts(at + Vector3(0, 1.3, 0), Vector3(0.4, 0.05, 0.2), 40, 3.0, Vector3(0.3, 1.2, 0.1), 15.0, Vector2(0.9, 0.9), Color(0.55, 0.55, 0.55, 0.22))
			_omni(at + Vector3(0, 1.3, 0.3), Color(1.0, 0.45, 0.15), 1.4, 3.5)
			_solid(at + Vector3(0, 0.78, 0), Vector3(1.8, 1.55, 0.9), yaw)
		"table":
			var t: Node3D = _prop("dining_table", Vector3(0, 0.68, 0.435), 0.0, 1.0, p)
			if t:
				t.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			_prop("plastic_monobloc_chair_01", Vector3(0.6, 0, 0.9), rng.randf() * 360.0, 1.0, p)
			_prop("hamburger_buns", Vector3(-0.8, 0, -0.9), 0.0, 1.0, p)
			_solid(at + Vector3(0, 0.7, 0), Vector3(2.25, 1.4, 0.9), yaw)
		"shed":
			var wood: StandardMaterial3D = g.mat("old_planks_02", 0.7, Color(0.55, 0.62, 0.5))
			_box(Vector3(3.0, 2.3, 2.2), Vector3(0, 1.15, 0), wood, p)
			var rf := _box(Vector3(3.3, 0.12, 2.6), Vector3(0, 2.5, 0), g.mat("corrugated_iron", 0.8, Color(0.45, 0.4, 0.35)), p)
			rf.rotation_degrees.x = -10.0
			_box(Vector3(0.9, 1.9, 0.05), Vector3(0.6, 0.95, 1.11), g.mat("worn_planks", 0.8, Color(0.6, 0.5, 0.4)), p)
			_label("KEEP OUT", Vector3(0, 1.8, -1.12), 50, Color(0.95, 0.3, 0.2), p, 180.0)
			_prop("garden_gnome", Vector3(-1.0, 0, 1.3), 0.0, 1.6, p)
			_solid(at + Vector3(0, 1.2, 0), Vector3(3.0, 2.4, 2.2), yaw)
		"planters":
			for r in 2:
				for c in 2:
					_prop("planter_box_01", Vector3(-0.47 + c * 0.94, r * 0.42, 0), 0.0, 1.0, p)
			_box(Vector3(1.86, 0.5, 0.42), Vector3(0, 0.25, 0.0), g.mat("old_planks_02", 0.8, Color(0.6, 0.45, 0.35)), p)
			_box(Vector3(1.86, 0.4, 0.45), Vector3(0, 0.95, 0), g.mat("old_planks_02", 0.8, Color(0.6, 0.45, 0.35)), p)
			_prop("fern_02", Vector3(-0.6, 1.15, 0), 0.0, 0.4, p)
			_prop("garden_gnome", Vector3(0.6, 1.15, 0), 180.0, 1.0, p)
			_solid(at + Vector3(0, 0.65, 0), Vector3(1.9, 1.3, 0.5), yaw)
		"car":
			_prop("covered_car", Vector3.ZERO, 0.0, 1.0, p)
			_solid(at + Vector3(0, 0.7, 0), Vector3(1.8, 1.4, 4.4), yaw)

## 7 · NEON NIGHT MARKET: rainy night street, magenta and cyan neon, stalls, AC stacks.
func _neon() -> Dictionary:
	_env(Color("07040f"), Color(0.5, 0.42, 0.66), 0.75, Color(0.16, 0.07, 0.2), 0.022, 1.25, 1.1)
	var env: Environment = g.env
	env.ssr_enabled = true
	env.glow_intensity = 0.85
	_sun(Color(0.45, 0.5, 0.95), 0.22, Vector3(-55.0, 160.0, 0.0))
	var wet: StandardMaterial3D = g.mat("asphalt_02", 0.3, Color(0.55, 0.52, 0.6)).duplicate()
	wet.roughness = 0.3
	g.box(Vector3(130.0, 0.2, 130.0), Vector3(W * 0.5, -0.1, 15.0), wet)
	var puddle: StandardMaterial3D = g.mat("dark_rock", 1.0, Color(0.05, 0.04, 0.07)).duplicate()
	puddle.roughness = 0.0
	for k in 9:
		var pd := _cyl(1.0, 1.0, 0.02, Vector3(rng.randf_range(0.5, 15.5), 0.01, rng.randf_range(1.0, 32.0)), puddle, null, 14)
		pd.scale = Vector3(rng.randf_range(0.6, 1.6), 1.0, rng.randf_range(0.5, 1.2))
	for k in 8:
		_box(Vector3(0.45, 0.03, 3.0), Vector3(1.2 + k * 0.6, 0.0, 29.6), g.mat("painted_concrete", 1.0, Color(0.95, 0.95, 0.95)))
	_marks(_glow(Color(0.2, 0.95, 1.0), 1.0))
	var rows := [["crates", 2.4, 26.5, 0.0], ["stall", 7.6, 26.5, 0.0], ["ac", 13.2, 26.5, 0.0],
		["kiosk", 4.0, 22.0, 0.0], ["crates", 9.6, 22.0, 8.0], ["stall", 13.4, 22.0, 0.0],
		["stall", 2.6, 17.5, 0.0], ["ac", 7.4, 17.5, 0.0], ["van", 12.4, 17.5, 90.0],
		["ac", 2.0, 13.0, 0.0], ["kiosk", 8.0, 13.0, 0.0], ["crates", 13.8, 13.0, -6.0],
		["van", 3.8, 8.5, 86.0], ["stall", 9.8, 8.5, 0.0], ["crates", 14.2, 8.5, 0.0],
		["stall", 4.8, 4.5, 0.0], ["ac", 11.0, 4.5, 0.0]]
	_covers(rows, _neon_cover)
	var neon := [Color(1.0, 0.15, 0.7), Color(0.15, 0.9, 1.0), Color(1.0, 0.75, 0.15), Color(0.6, 0.3, 1.0), Color(0.3, 1.0, 0.5)]
	var words := ["NOODLES", "KARAOKE", "HOTEL", "DUCK 24H", "PAWN", "LUCKY", "RAMEN", "BAR", "MASSAGE", "OPEN"]
	for sx in [-2.0, 18.0]:
		var side := -1.0 if sx < 8.0 else 1.0
		var z := -2.0
		var bi := 0
		while z < 38.0:
			var depth := rng.randf_range(5.0, 8.0)
			var h := rng.randf_range(9.0, 18.0)
			_box(Vector3(4.0, h, depth - 0.2), Vector3(sx + side * 2.0, h * 0.5, z + depth * 0.5), g.mat(["concrete_wall_006", "dark_brick_wall", "concrete_wall_008"][bi % 3], 0.4, Color(0.45, 0.42, 0.5)))
			for wy in range(3, int(h) - 1, 2):
				for wz in range(1, int(depth) - 1, 2):
					if rng.randf() < 0.45:
						_box(Vector3(0.05, 1.0, 0.9), Vector3(sx + side * 0.0 - side * 0.03, float(wy), z + float(wz)), _glow([Color(1.0, 0.8, 0.5), Color(0.5, 0.8, 1.0), Color(1.0, 0.4, 0.7)][rng.randi() % 3], rng.randf_range(0.6, 1.6)))
			var c: Color = neon[(bi + (0 if sx < 8.0 else 2)) % neon.size()]
			var sign_y := rng.randf_range(3.2, 6.5)
			_box(Vector3(0.12, 0.9, 3.4), Vector3(sx - side * 0.1, sign_y, z + depth * 0.5), _glow(c, 3.5))
			_label(words[rng.randi() % words.size()], Vector3(sx - side * 0.2, sign_y, z + depth * 0.5), 110, Color(1, 1, 1), null, -90.0 * side)
			_omni(Vector3(sx - side * 1.0, sign_y, z + depth * 0.5), c, 2.4, 8.0)
			_prop("exterior_aircon_unit", Vector3(sx - side * 0.25, rng.randf_range(7.0, 9.0), z + 1.2), 90.0 * side, 1.0)
			z += depth
			bi += 1
		for k in 4:
			_prop(["utility_box_02", "korean_public_payphone_01", "metal_trash_can", "trashbag"][k], Vector3(sx + side * 0.4 - side * 1.0, 0, 3.0 + k * 8.0), 90.0 * side, 1.0 if k != 1 else 2.2)
	for z in [3.0, 11.0, 19.0, 27.0, 34.0]:
		_bulbs(Vector3(-2.0, 7.4, z), Vector3(18.0, 7.4, z + 2.0), 14, [Color(1.0, 0.2, 0.15)], 0.8)
	var gantry: StandardMaterial3D = g.mat("rusty_metal_02", 1.0, Color(0.4, 0.4, 0.45))
	_exit(Color(1.0, 0.15, 0.7), gantry)
	_box(Vector3(40.0, 22.0, 1.0), Vector3(W * 0.5, 11.0, -12.0), g.mat("concrete_wall_006", 0.3, Color(0.35, 0.33, 0.4)))
	_box(Vector3(14.0, 5.0, 0.2), Vector3(W * 0.5, 12.0, -11.4), _glow(Color(0.1, 0.6, 0.9), 1.6))
	_label("DUCK SOUP\nOPEN ALL NIGHT", Vector3(W * 0.5, 12.0, -11.25), 300, Color(1.0, 0.95, 1.0))
	for k in 30:
		_box(Vector3(0.9, 1.0, 0.05), Vector3(rng.randf_range(-10.0, 26.0), rng.randf_range(2.0, 20.0), -11.45), _glow([Color(1.0, 0.8, 0.5), Color(0.5, 0.8, 1.0), Color(1.0, 0.4, 0.7)][k % 3], 1.2))
	_omni(Vector3(W * 0.5, 9.0, -8.0), Color(0.2, 0.7, 1.0), 4.0, 18.0)
	_parts(Vector3(W * 0.5, 10.0, 15.0), Vector3(14.0, 1.0, 22.0), 700, 1.0, Vector3(0.6, -14.0, 0.0), 2.0, Vector2(0.02, 0.6), Color(0.75, 0.8, 1.0, 0.35), true)
	for z in [7.0, 17.0, 27.0]:
		_omni(Vector3(W * 0.5, 6.0, z), Color(0.85, 0.8, 1.0), 1.3, 11.0)
	_duck_lights(Color(0.95, 0.45, 1.0), 0.8)
	return {"leg": ["rusty_metal_02", Color(0.55, 0.55, 0.62)], "deck": ["metal_grate_rusty", Color(0.6, 0.6, 0.65)], "wall": ["blue_metal_plate", Color(0.7, 0.75, 0.9)], "roof": ["corrugated_iron", Color(0.4, 0.4, 0.5)]}

func _neon_cover(kind: String, at: Vector3, yaw: float) -> void:
	var neon := [Color(1.0, 0.15, 0.7), Color(0.15, 0.9, 1.0), Color(1.0, 0.75, 0.15), Color(0.3, 1.0, 0.5)]
	var c: Color = neon[rng.randi() % neon.size()]
	var p := _piv(at, yaw)
	match kind:
		"stall":
			_box(Vector3(2.6, 1.15, 0.8), Vector3(0, 0.575, 0.2), g.mat("blue_metal_plate", 0.8, Color(0.55, 0.6, 0.75)), p)
			_box(Vector3(2.6, 2.0, 0.15), Vector3(0, 1.0, -0.42), g.mat("corrugated_iron", 0.7, Color(0.5, 0.45, 0.5)), p)
			var tarp := _box(Vector3(3.0, 0.06, 1.6), Vector3(0, 2.35, 0.2), g.mat("grey_plaster_03", 0.6, c.darkened(0.35)), p)
			tarp.rotation_degrees.x = 10.0
			_box(Vector3(2.6, 0.06, 0.06), Vector3(0, 2.22, 0.95), _glow(c, 4.0), p)
			for k in 4:
				_box(Vector3(0.35, 0.3, 0.3), Vector3(-0.9 + k * 0.6, 1.3, 0.2), g.mat("rubber_tiles", 1.0, neon[k % neon.size()].darkened(0.4)), p)
			_ball(0.22, Vector3(-1.2, 2.0, 0.9), _glow(Color(1.0, 0.25, 0.15), 3.0), p)
			_label(["DUMPLINGS", "SKEWERS", "PHONE FIX", "FAKE WATCH", "FRIED DUCK"][rng.randi() % 5], Vector3(0, 1.75, -0.51), 50, c.lightened(0.4), p, 180.0)
			_omni(at + Vector3(0, 2.0, 1.0), c, 1.4, 4.5)
			_solid(at + Vector3(0, 1.0, 0), Vector3(2.6, 2.0, 1.0), yaw)
		"crates":
			for r in 3:
				for k in 3:
					var b := _box(Vector3(0.5, 0.4, 0.9), Vector3(-0.55 + k * 0.55, 0.2 + r * 0.42, rng.randf_range(-0.05, 0.05)), g.mat("rubber_tiles", 1.0, neon[(r + k) % neon.size()].darkened(0.45)), p)
					b.rotation_degrees.y = rng.randf_range(-6.0, 6.0)
			_prop("cardboard_box_01", Vector3(0.3, 1.26, 0), 20.0, 1.0, p)
			_solid(at + Vector3(0, 0.65, 0), Vector3(1.7, 1.3, 1.0), yaw)
		"ac":
			var fr: StandardMaterial3D = g.mat("rusty_metal_02", 1.0, Color(0.5, 0.5, 0.55))
			for s in [-0.95, 0.95]:
				_box(Vector3(0.08, 1.9, 0.5), Vector3(s, 0.95, 0), fr, p)
			_prop("exterior_aircon_unit", Vector3(0, 0.33, 0), 180.0, 1.0, p)
			_prop("exterior_aircon_unit", Vector3(0, 1.26, 0), 180.0, 1.0, p)
			_box(Vector3(1.9, 0.06, 0.06), Vector3(0, 1.9, -0.25), _glow(c, 3.0), p)
			_solid(at + Vector3(0, 0.95, 0), Vector3(1.95, 1.9, 0.55), yaw)
		"kiosk":
			_box(Vector3(3.0, 2.5, 2.0), Vector3(0, 1.25, 0), g.mat("corrugated_iron", 0.6, Color(0.55, 0.5, 0.6)), p)
			_box(Vector3(2.0, 0.9, 0.05), Vector3(0, 1.4, 1.01), _glow(Color(1.0, 0.85, 0.6), 1.2), p)
			_box(Vector3(3.2, 0.7, 0.2), Vector3(0, 2.85, 0.9), _glow(c, 3.0), p)
			_label(["LOTTO", "CIGS", "24/7", "PACHINKO"][rng.randi() % 4], Vector3(0, 2.85, 1.02), 90, Color(1, 1, 1), p)
			_omni(at + Vector3(0, 2.6, 1.6), c, 1.8, 6.0)
			_solid(at + Vector3(0, 1.25, 0), Vector3(3.0, 2.5, 2.0), yaw)
		"van":
			_prop("covered_car", Vector3.ZERO, 0.0, 1.0, p)
			_box(Vector3(1.9, 0.04, 4.5), Vector3(0, 0.02, 0), _glow(c, 1.2), p)
			_solid(at + Vector3(0, 0.7, 0), Vector3(1.8, 1.4, 4.4), yaw)
