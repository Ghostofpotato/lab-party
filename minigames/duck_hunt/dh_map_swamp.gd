extends RefCounted
## Duck Hunt map: Flight 404. A crashed airliner broken in two in a misty
## swamp; fuselage halves, a wing in the mud, a burning engine, dead trees.

static func layout() -> Dictionary:
	return {
		"name": "FLIGHT 404  ·  SWAMP",
		"towers": [Vector3(-1.6, 0.0, 2.0), Vector3(17.6, 0.0, 2.0)],
		"lifts": [Vector3(0.8, 0.0, 2.0), Vector3(15.2, 0.0, 2.0)],
		"fusebox": Vector3(6.6, 0.0, 6.8),
		"skin": {"leg": ["old_planks_02", Color(0.5, 0.45, 0.36)], "wall": ["black_painted_planks", Color(0.65, 0.62, 0.5)], "floor": ["old_planks_02", Color(0.55, 0.5, 0.4)], "roof": ["corrugated_iron", Color(0.45, 0.42, 0.35)]},
	}

static func build(g) -> void:
	g.set_env({"bg": Color("060805"), "amb": Color(0.5, 0.58, 0.42), "amb_e": 0.8, "fog": Color(0.2, 0.25, 0.17), "fog_d": 0.04,
		"sat": 0.62, "exp": 1.45, "sun": Color(0.78, 0.85, 0.62), "sun_e": 0.38, "sun_rot": Vector3(-38.0, 120.0, 0.0)})
	g.box(Vector3(70.0, 0.2, 70.0), Vector3(8.0, -0.1, 5.0), g.mat("brown_mud_leaves_01", 0.3, Color(0.7, 0.72, 0.6)))
	var water: StandardMaterial3D = g.mat("brown_mud_leaves_01", 0.5, Color(0.32, 0.36, 0.26)).duplicate()
	water.roughness_texture = null
	water.roughness = 0.05
	water.metallic_texture = null
	water.metallic = 0.0
	water.metallic_specular = 0.9
	for pd in [[Vector3(-6.0, 0, 6.0), Vector3(9.0, 0, 7.0)], [Vector3(22.0, 0, 7.0), Vector3(9.0, 0, 10.0)], [Vector3(8.0, 0, -6.5), Vector3(30.0, 0, 6.0)], [Vector3(3.0, 0, 9.4), Vector3(3.0, 0, 1.4)], [Vector3(12.0, 0, 0.6), Vector3(2.6, 0, 1.2)], [Vector3(9.6, 0, 7.6), Vector3(2.0, 0, 1.6)]]:
		g.box(Vector3((pd[1] as Vector3).x, 0.02, (pd[1] as Vector3).z), (pd[0] as Vector3) + Vector3(0, 0.015, 0), water)
	_front(g, Vector3(4.6, 0.0, 4.2), 12.0)
	_rear(g, Vector3(11.8, 0.0, 6.0), -22.0)
	_wing(g, Vector3(9.6, 0.0, 1.2), 8.0)
	_engine(g, Vector3(13.0, 0.0, 9.4))
	_log(g, Vector3(2.6, 0.0, 8.0), 70.0)
	for st in [Vector3(14.4, 0, 3.6), Vector3(6.0, 0, 9.4), Vector3(9.4, 0, 3.6)]:
		_seats(g, st, st.x * 29.0)
	for s in [[Vector3(4.0, 0, 6.3), 30.0], [Vector3(8.6, 0, 9.2), -50.0], [Vector3(15.4, 0, 6.0), 80.0], [Vector3(1.6, 0, 0.6), 10.0], [Vector3(7.0, 0, 0.4), 100.0]]:
		g.fit("cardboard_box_01", s[0], s[1], 0.45)
	g.fit("lifebuoy", Vector3(10.8, 0.05, 8.4), 0.0, 0.12)
	g.prop("old_tyre", Vector3(12.8, 0.2, 2.8), 40.0)
	_fire(g, Vector3(8.6, 0.0, 3.0), 0)
	_fire(g, Vector3(15.4, 0.0, 8.6), 1)
	for t in [Vector3(-3.5, 0, -3.0), Vector3(-4.0, 0, 7.0), Vector3(19.8, 0, -2.0), Vector3(20.0, 0, 8.0), Vector3(2.0, 0, -5.0), Vector3(13.5, 0, -6.0), Vector3(-6.0, 0, 12.0), Vector3(23.0, 0, 13.0), Vector3(7.0, 0, -9.0)]:
		g.dead_tree(t, t.z * 47.0, 5.0)
	for k in 14:
		var a := float(k) * 2.4
		var p := Vector3(8.0 + cos(a) * (10.0 + (k % 3)), 0, 4.5 + sin(a) * (8.0 + (k % 2)))
		g.fit("fern_02", p, k * 37.0, 0.9)
		g.prop("grass_medium_01", p + Vector3(1.2, 0, 0.4), k * 51.0, 1.2)
	for n in [Vector3(0.5, 0, 4.6), Vector3(15.7, 0, 9.6), Vector3(10.6, 0, 9.7), Vector3(5.4, 0, 0.3), Vector3(16.4, 0, 0.6)]:
		g.prop("nettle_plant", n, n.x * 61.0, 1.4)
		g.fit("moss_01", n + Vector3(0.4, 0, 0.3), n.z * 20.0, 0.12)
	for r in [Vector3(-2.4, 0, 9.8), Vector3(18.4, 0, -1.0), Vector3(3.4, 0, -3.0), Vector3(16.6, 0, 11.6)]:
		g.fit("rock_moss_set_01", r, r.x * 15.0, 0.9)
	var fly := 0
	for fx in [Vector3(-2.0, 1.4, 6.0), Vector3(18.0, 1.6, 6.5), Vector3(5.0, 1.2, -2.5), Vector3(11.0, 1.5, 11.5)]:
		var l: OmniLight3D = g.omni(fx, Color(0.7, 1.0, 0.4), 0.9, 3.0)
		g.flicker(l, 0.9, 400 + fly)
		g.box(Vector3(0.04, 0.04, 0.04), fx, g.glow(Color(0.8, 1.0, 0.4), 8.0))
		fly += 1

static func _skin(g, tint: Color) -> StandardMaterial3D:
	return g.mat("grey_plaster_03", 0.45, tint)

static func _windows(g, holder: Node3D, length: float, z: float) -> void:
	var dark: StandardMaterial3D = g.mat("dirty_concrete", 0.8, Color(0.1, 0.1, 0.1))
	var lit: StandardMaterial3D = g.glow(Color(0.9, 0.8, 0.5), 0.8)
	var n := int(length / 0.7)
	for i in n:
		g.box(Vector3(0.3, 0.38, 0.04), Vector3(-length * 0.5 + 0.4 + i * 0.7, 1.75, z), lit if i % 5 == 2 else dark, holder)

static func _front(g, base: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	g.world.add_child(holder)
	holder.position = base
	holder.rotation_degrees = Vector3(0, yaw, 6.0)
	var body := _skin(g, Color(0.85, 0.85, 0.82))
	g.box(Vector3(4.6, 2.3, 2.3), Vector3(0, 1.15, 0), body, holder)
	var nose: MeshInstance3D = g.box(Vector3(1.4, 1.7, 2.0), Vector3(-2.9, 1.0, 0), body, holder)
	nose.rotation_degrees.z = 12.0
	g.box(Vector3(0.5, 0.5, 1.6), Vector3(-3.3, 1.6, 0), g.glow(Color(0.25, 0.35, 0.4), 0.5), holder)
	var stripe: StandardMaterial3D = g.mat("grey_plaster_03", 0.6, Color(0.75, 0.12, 0.08))
	for z in [1.17, -1.17]:
		g.box(Vector3(4.6, 0.22, 0.03), Vector3(0, 1.25, z), stripe, holder)
		_windows(g, holder, 4.4, z * 1.01)
	var lb: Label3D = g.sign3d("LABAIR", Vector3.ZERO, Color(0.2, 0.25, 0.5), 110)
	lb.reparent(holder, false)
	lb.position = Vector3(0.6, 0.55, 1.19)
	g.box(Vector3(0.1, 2.3, 2.3), Vector3(2.32, 1.15, 0), g.mat("rusty_metal", 0.8, Color(0.3, 0.28, 0.25)), holder)
	g.solid(base + Vector3(0, 1.15, 0), Vector3(5.8, 2.3, 2.3), yaw)

static func _rear(g, base: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	g.world.add_child(holder)
	holder.position = base
	holder.rotation_degrees = Vector3(0, yaw, -4.0)
	var body := _skin(g, Color(0.82, 0.82, 0.78))
	g.box(Vector3(4.0, 2.2, 2.2), Vector3(0, 1.1, 0), body, holder)
	var cone: MeshInstance3D = g.box(Vector3(1.8, 1.5, 1.6), Vector3(2.7, 1.4, 0), body, holder)
	cone.rotation_degrees.z = 10.0
	var fin: MeshInstance3D = g.box(Vector3(1.8, 2.6, 0.18), Vector3(2.6, 3.2, 0), _skin(g, Color(0.75, 0.15, 0.1)), holder)
	fin.rotation_degrees.z = -22.0
	var stab: MeshInstance3D = g.box(Vector3(1.2, 0.12, 3.6), Vector3(3.0, 1.9, 0), body, holder)
	stab.rotation_degrees.x = 8.0
	for z in [1.12, -1.12]:
		g.box(Vector3(4.0, 0.22, 0.03), Vector3(0, 1.2, z), g.mat("grey_plaster_03", 0.6, Color(0.75, 0.12, 0.08)), holder)
		_windows(g, holder, 3.8, z * 1.01)
	g.box(Vector3(0.1, 2.2, 2.2), Vector3(-2.02, 1.1, 0), g.mat("rusty_metal", 0.8, Color(0.3, 0.28, 0.25)), holder)
	g.solid(base + Vector3(0.5, 1.1, 0).rotated(Vector3.UP, deg_to_rad(yaw)), Vector3(5.2, 2.2, 2.2), yaw)

static func _wing(g, base: Vector3, yaw: float) -> void:
	var w: MeshInstance3D = g.box(Vector3(5.4, 0.22, 1.7), base + Vector3(0, 0.75, 0), _skin(g, Color(0.7, 0.72, 0.7)), null)
	w.rotation_degrees = Vector3(62.0, yaw, 6.0)
	g.box(Vector3(5.4, 0.1, 0.3), base + Vector3(0, 0.05, 0.4).rotated(Vector3.UP, deg_to_rad(yaw)), g.mat("dark_rock", 0.6, Color(0.2, 0.18, 0.14)))
	g.solid(base + Vector3(0, 0.75, 0), Vector3(5.2, 1.5, 0.9), yaw)

static func _engine(g, base: Vector3) -> void:
	var e: MeshInstance3D = g.cyl(0.75, 2.2, base + Vector3(0, 0.75, 0), _skin(g, Color(0.6, 0.6, 0.6)))
	e.rotation_degrees = Vector3(0, 20.0, 90.0)
	var inner: MeshInstance3D = g.cyl(0.6, 2.25, base + Vector3(0, 0.75, 0), g.mat("rusty_metal", 0.8, Color(0.15, 0.13, 0.12)))
	inner.rotation_degrees = Vector3(0, 20.0, 90.0)
	g.solid(base + Vector3(0, 0.75, 0), Vector3(2.2, 1.5, 1.5), -20.0)

static func _log(g, base: Vector3, yaw: float) -> void:
	var lg: MeshInstance3D = g.cyl(0.4, 3.4, base + Vector3(0, 0.38, 0), g.mat("old_planks_02", 0.6, Color(0.35, 0.3, 0.22)))
	lg.rotation_degrees = Vector3(0, yaw, 90.0)
	g.fit("moss_01", base + Vector3(0, 0.7, 0), yaw, 0.2)
	g.solid(base + Vector3(0, 0.4, 0), Vector3(3.4, 0.8, 0.8), yaw)

static func _seats(g, base: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	g.world.add_child(holder)
	holder.position = base
	holder.rotation_degrees = Vector3(0, yaw, 0)
	var fab: StandardMaterial3D = g.mat("dirty_carpet", 0.8, Color(0.35, 0.42, 0.65))
	for k in 3:
		g.box(Vector3(0.5, 0.12, 0.5), Vector3(-0.55 + k * 0.55, 0.45, 0), fab, holder)
		g.box(Vector3(0.5, 0.7, 0.12), Vector3(-0.55 + k * 0.55, 0.85, -0.22), fab, holder)
	g.box(Vector3(1.7, 0.08, 0.5), Vector3(0, 0.36, 0), g.dull("rusty_metal_02", 1.0, Color(0.7, 0.7, 0.7)), holder)
	g.solid(base + Vector3(0, 0.6, 0), Vector3(1.7, 1.2, 0.6), yaw)

static func _fire(g, pos: Vector3, k: int) -> void:
	g.box(Vector3(0.6, 0.12, 0.5), pos + Vector3(0, 0.06, 0), g.mat("rusty_metal", 1.0, Color(0.2, 0.18, 0.15)))
	g.flame(pos + Vector3(0, 0.1, 0), 0.55)
	g.flame(pos + Vector3(0.2, 0.1, 0.12), 0.35)
	var l: OmniLight3D = g.omni(pos + Vector3(0, 0.9, 0), Color(1.0, 0.5, 0.18), 3.6, 6.5, k == 0)
	var tw := l.create_tween().set_loops()
	tw.tween_property(l, "light_energy", 2.6, 0.1 + k * 0.03)
	tw.tween_property(l, "light_energy", 4.2, 0.08)
	tw.tween_property(l, "light_energy", 3.2, 0.14)
