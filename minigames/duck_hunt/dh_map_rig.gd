extends RefCounted
## Duck Hunt map: Rig 9. An oil platform deck in a night storm; containers,
## pipe racks, a wellhead stack, a derrick overhead, rain and lightning.

static func layout() -> Dictionary:
	return {
		"name": "RIG 9  ·  STORM WARNING",
		"towers": [Vector3(-1.4, 0.0, -1.4), Vector3(17.4, 0.0, -1.4)],
		"lifts": [Vector3(0.8, 0.0, 0.8), Vector3(15.2, 0.0, 0.8)],
		"fusebox": Vector3(8.0, 0.0, 7.4),
		"skin": {"leg": ["rusty_metal_02", Color(1.0, 0.6, 0.25)], "wall": ["blue_metal_plate", Color(0.75, 0.8, 0.85)], "floor": ["metal_grate_rusty", Color(0.8, 0.8, 0.8)], "roof": ["corrugated_iron", Color(0.55, 0.6, 0.65)]},
	}

static func build(g) -> void:
	g.set_env({"bg": Color("04070b"), "amb": Color(0.42, 0.5, 0.62), "amb_e": 0.62, "fog": Color(0.08, 0.1, 0.13), "fog_d": 0.035,
		"sat": 0.62, "exp": 1.3, "sun": Color(0.6, 0.7, 0.9), "sun_e": 0.32, "sun_rot": Vector3(-55.0, 160.0, 0.0)})
	var sea := StandardMaterial3D.new()
	sea.albedo_color = Color(0.02, 0.04, 0.06)
	sea.roughness = 0.08
	sea.metallic = 0.4
	g.box(Vector3(260.0, 0.2, 260.0), Vector3(8.0, -16.0, 4.0), sea)
	var deck: StandardMaterial3D = g.mat("blue_metal_plate", 0.4, Color(0.55, 0.58, 0.6))
	g.box(Vector3(34.0, 0.6, 26.0), Vector3(8.0, -0.3, 3.0), deck)
	g.box(Vector3(17.4, 0.03, 11.4), Vector3(8.0, 0.0, 5.0), g.mat("metal_grate_rusty", 0.6, Color(0.85, 0.85, 0.85)))
	var hz: StandardMaterial3D = g.mat("grey_plaster_03", 0.6, Color(1.0, 0.75, 0.1))
	g.box(Vector3(17.6, 0.02, 0.2), Vector3(8.0, 0.02, 10.4), hz)
	g.box(Vector3(17.6, 0.02, 0.2), Vector3(8.0, 0.02, -0.4), hz)
	var leg: StandardMaterial3D = g.dull("rusty_metal_02", 0.8, Color(0.8, 0.55, 0.3))
	for lx in [-8.0, 24.0]:
		for lz in [-9.0, 15.0]:
			g.cyl(1.4, 16.0, Vector3(lx, -8.4, lz), leg)
	var rail: StandardMaterial3D = g.dull("rusty_metal_02", 1.5, Color(1.0, 0.75, 0.2))
	for e in [[Vector3(8.0, 0, 15.8), Vector3(34.0, 0, 0)], [Vector3(-8.8, 0, 3.0), Vector3(0, 0, 26.0)], [Vector3(24.8, 0, 3.0), Vector3(0, 0, 26.0)]]:
		var c: Vector3 = e[0]
		var span: Vector3 = e[1]
		for y in [0.55, 1.05]:
			g.box(Vector3(maxf(span.x, 0.06), 0.06, maxf(span.z, 0.06)), c + Vector3(0, y, 0), rail)
		var n := int(maxf(span.x, span.z) / 2.0)
		for i in n + 1:
			var t := -0.5 + float(i) / float(n)
			g.box(Vector3(0.06, 1.1, 0.06), c + span * t + Vector3(0, 0.55, 0), rail)
	for lb in [Vector3(-8.75, 0.7, 6.0), Vector3(24.75, 0.7, -2.0), Vector3(3.0, 0.7, 15.75)]:
		g.fit("lifebuoy", lb, 90.0 if absf(lb.x) > 8.0 else 0.0, 0.75)
	_derrick(g, Vector3(8.0, 0.0, -6.0))
	_quarters(g)
	g.container(Vector3(4.8, 0.0, 5.4), Vector3(3.4, 2.4, 2.2), Color(0.45, 0.6, 0.85))
	g.container(Vector3(12.4, 0.0, 5.4), Vector3(2.2, 2.4, 3.8), Color(0.95, 0.5, 0.25))
	_pipe_rack(g, Vector3(6.8, 0.0, 1.8), 0.0, 3.6)
	_pipe_rack(g, Vector3(11.4, 0.0, 9.0), 0.0, 3.0)
	_wellhead(g, Vector3(8.4, 0.0, 4.6))
	for b in [Vector3(1.6, 0, 7.6), Vector3(2.2, 0, 8.2), Vector3(1.4, 0, 8.6), Vector3(2.4, 0, 7.4)]:
		g.prop("barrel_03", b, b.x * 80.0)
	g.solid(Vector3(1.9, 0.47, 8.0), Vector3(1.6, 0.94, 1.7))
	g.fit("small_lpg_tank", Vector3(14.6, 0, 2.6), 20.0, 1.1, true)
	g.fit("small_lpg_tank", Vector3(15.3, 0, 3.0), 80.0, 1.1, true)
	g.prop("old_military_compressor", Vector3(2.0, 0, 4.4), 90.0, 1.2)
	g.solid(Vector3(2.0, 0.6, 4.4), Vector3(1.0, 1.2, 1.6), 90.0)
	for k in 3:
		g.prop("wooden_military_crate", Vector3(13.6, 0.0 + k * 0.5, 9.1), k * 9.0)
	g.solid(Vector3(13.6, 0.75, 9.1), Vector3(1.2, 1.5, 0.8))
	g.prop("propane_tank", Vector3(0.5, 0, 4.8), 0.0)
	g.prop("metal_toolbox", Vector3(10.0, 0, 3.2), 30.0)
	g.prop("metal_jerrycan", Vector3(5.8, 0, 9.4), 60.0)
	for sl in [[Vector3(-1.8, 0, 5.0), 1.0], [Vector3(17.8, 0, 5.0), -1.0]]:
		g.security_light(sl[0], sl[1])
	_rain(g)
	_lightning(g)

static func _derrick(g, c: Vector3) -> void:
	var m: StandardMaterial3D = g.dull("rusty_metal_02", 0.9, Color(0.95, 0.4, 0.25))
	var h := 24.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg: MeshInstance3D = g.box(Vector3(0.35, h, 0.35), c + Vector3(sx * 2.0, h * 0.5, sz * 2.0), m)
			leg.rotation_degrees = Vector3(-sz * 3.5, 0, sx * 3.5)
	var y := 2.0
	while y < h:
		var w := 4.2 - y * 0.12
		g.box(Vector3(w, 0.18, 0.18), c + Vector3(0, y, w * 0.5), m)
		g.box(Vector3(w, 0.18, 0.18), c + Vector3(0, y, -w * 0.5), m)
		g.box(Vector3(0.18, 0.18, w), c + Vector3(w * 0.5, y, 0), m)
		g.box(Vector3(0.18, 0.18, w), c + Vector3(-w * 0.5, y, 0), m)
		y += 3.0
	g.box(Vector3(9.0, 3.0, 7.0), c + Vector3(0, 1.5, -3.0), g.dull("blue_metal_plate", 0.5, Color(0.6, 0.65, 0.7)))
	var red: StandardMaterial3D = g.glow(Color(1.0, 0.1, 0.05), 6.0)
	var top: MeshInstance3D = g.box(Vector3(0.4, 0.4, 0.4), c + Vector3(0, h + 0.3, 0), red)
	var l: OmniLight3D = g.omni(c + Vector3(0, h, 0), Color(1.0, 0.1, 0.05), 3.0, 10.0)
	var tw := top.create_tween().set_loops()
	tw.tween_property(l, "light_energy", 0.0, 0.6)
	tw.tween_property(l, "light_energy", 3.0, 0.1)
	tw.tween_interval(0.6)
	g.sign3d("RIG 9", c + Vector3(0, 4.0, 0.6), Color(1.0, 0.85, 0.5), 160)

static func _quarters(g) -> void:
	var m: StandardMaterial3D = g.dull("blue_metal_plate", 0.4, Color(0.9, 0.9, 0.85))
	g.box(Vector3(10.0, 8.0, 6.0), Vector3(-4.0, 4.0, -8.0), m)
	g.box(Vector3(9.0, 6.0, 6.0), Vector3(20.0, 3.0, -8.0), m)
	var win: StandardMaterial3D = g.glow(Color(1.0, 0.85, 0.55), 1.6)
	for wx in [-7.0, -5.0, -3.0, -1.0]:
		g.box(Vector3(1.2, 0.8, 0.05), Vector3(wx, 5.8, -4.95), win)
	for wx in [17.0, 19.5, 22.0]:
		g.box(Vector3(1.2, 0.8, 0.05), Vector3(wx, 3.8, -4.95), win)
	g.omni(Vector3(-4.0, 5.0, -4.2), Color(1.0, 0.8, 0.5), 2.0, 6.0)
	var crane: MeshInstance3D = g.box(Vector3(0.6, 0.6, 16.0), Vector3(-3.0, 11.0, -1.0), g.dull("rusty_metal_02", 0.8, Color(1.0, 0.75, 0.2)))
	crane.rotation_degrees = Vector3(-18.0, 35.0, 0.0)
	g.box(Vector3(1.2, 4.0, 1.2), Vector3(-3.0, 10.0, -6.0), g.dull("rusty_metal_02", 0.8, Color(1.0, 0.75, 0.2)))

static func _pipe_rack(g, base: Vector3, yaw: float, length: float) -> void:
	var pipe: StandardMaterial3D = g.dull("rusty_metal", 0.8, Color(0.85, 0.7, 0.55))
	var holder := Node3D.new()
	g.world.add_child(holder)
	holder.position = base
	holder.rotation_degrees.y = yaw
	for k in 3:
		for j in 2:
			var p: MeshInstance3D = g.cyl(0.19, length, Vector3(0, 0.3 + k * 0.4, -0.22 + j * 0.44), pipe, holder)
			p.rotation_degrees.z = 90.0
	var frame: StandardMaterial3D = g.dull("rusty_metal_02", 1.0, Color(1.0, 0.7, 0.2))
	for x in [-length * 0.4, length * 0.4]:
		g.box(Vector3(0.12, 1.4, 1.0), Vector3(x, 0.7, 0), frame, holder)
	g.solid(base + Vector3(0, 0.7, 0), Vector3(length, 1.4, 1.0), yaw)

static func _wellhead(g, base: Vector3) -> void:
	var red: StandardMaterial3D = g.dull("rusty_metal", 0.8, Color(0.95, 0.3, 0.2))
	g.cyl(0.7, 1.0, base + Vector3(0, 0.5, 0), red)
	g.cyl(0.55, 0.9, base + Vector3(0, 1.45, 0), g.dull("rusty_metal_02", 0.8, Color(0.9, 0.85, 0.8)))
	g.cyl(0.65, 0.7, base + Vector3(0, 2.25, 0), red)
	g.cyl(0.2, 1.4, base + Vector3(0, 3.3, 0), red)
	for a in 4:
		var v: MeshInstance3D = g.cyl(0.14, 0.9, base + Vector3(0, 1.2, 0) + Vector3(0.75, 0, 0).rotated(Vector3.UP, a * PI * 0.5), red)
		v.rotation_degrees.z = 90.0
		v.rotation_degrees.y = a * 90.0
	g.solid(base + Vector3(0, 1.3, 0), Vector3(1.4, 2.6, 1.4))
	g.sign3d("DANGER  H2S", base + Vector3(0, 1.0, 0.72), Color(1.0, 0.85, 0.2), 36)

static func _rain(g) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = 2400
	ps.lifetime = 0.9
	ps.preprocess = 1.0
	ps.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18.0, 0.5, 14.0)
	pm.direction = Vector3(0.25, -1.0, 0.1)
	pm.spread = 3.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 22.0
	pm.gravity = Vector3(0, -10, 0)
	ps.process_material = pm
	var qm := BoxMesh.new()
	qm.size = Vector3(0.012, 0.55, 0.012)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.7, 0.8, 0.95, 0.35)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.material = rm
	ps.draw_pass_1 = qm
	ps.transform = Transform3D(Basis(), Vector3(8.0, 13.0, 4.0))
	ps.local_coords = false
	g.world.add_child(ps)

static func _lightning(g) -> void:
	var flash := DirectionalLight3D.new()
	flash.light_color = Color(0.75, 0.85, 1.0)
	flash.light_energy = 0.0
	flash.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	g.world.add_child(flash)
	var r := RandomNumberGenerator.new()
	r.seed = 909
	var tw := flash.create_tween().set_loops()
	for k in 4:
		tw.tween_interval(r.randf_range(4.0, 9.0))
		tw.tween_property(flash, "light_energy", 2.6, 0.03)
		tw.tween_property(flash, "light_energy", 0.2, 0.08)
		tw.tween_property(flash, "light_energy", 1.8, 0.04)
		tw.tween_property(flash, "light_energy", 0.0, 0.25)
		tw.tween_callback(func() -> void: Fx.sfx("explosion", null, -22.0, 0.35))
