extends RefCounted
## Duck Hunt map: Medina Rooftops. A flat roof terrace above an old medina at
## dusk; stair huts, water tanks, butane bottles, rugs, lanterns, a minaret.

static func layout() -> Dictionary:
	return {
		"name": "MEDINA ROOFTOPS",
		"towers": [Vector3(-1.6, 0.0, 6.0), Vector3(17.6, 0.0, 1.0)],
		"lifts": [Vector3(0.8, 0.0, 6.0), Vector3(15.2, 0.0, 1.4)],
		"fusebox": Vector3(7.4, 0.0, 3.0),
		"skin": {"leg": ["old_planks_02", Color(0.7, 0.55, 0.42)], "wall": ["clay_plaster", Color(0.95, 0.75, 0.6)], "floor": ["worn_planks", Color(0.7, 0.55, 0.45)], "roof": ["dirty_carpet", Color(0.7, 0.2, 0.15)]},
	}

static func build(g) -> void:
	g.set_env({"bg": Color("2a1820"), "amb": Color(0.62, 0.58, 0.62), "amb_e": 0.7, "fog": Color(0.42, 0.34, 0.4), "fog_d": 0.008,
		"sat": 0.88, "exp": 1.05, "sun": Color(1.0, 0.72, 0.5), "sun_e": 1.2, "sun_rot": Vector3(-13.0, -118.0, 0.0),
		"sky": [Color(0.22, 0.18, 0.42), Color(1.0, 0.56, 0.36), Color(0.25, 0.16, 0.14)]})
	var plaster: StandardMaterial3D = g.mat("clay_plaster", 0.35, Color(0.95, 0.78, 0.62))
	g.box(Vector3(80.0, 0.2, 80.0), Vector3(8.0, -9.0, 5.0), g.mat("dirty_concrete", 0.3, Color(0.4, 0.32, 0.28)))
	g.box(Vector3(21.0, 9.0, 15.0), Vector3(8.0, -4.5, 5.0), plaster)
	g.box(Vector3(16.6, 0.03, 10.6), Vector3(8.0, 0.0, 5.0), g.mat("patterned_terracotta_tiling", 0.4, Color(0.95, 0.85, 0.78)))
	var par: StandardMaterial3D = g.mat("clay_plaster", 0.6, Color(1.0, 0.82, 0.66))
	g.box(Vector3(16.9, 0.9, 0.25), Vector3(8.0, 0.45, -0.25), par)
	g.box(Vector3(16.9, 0.7, 0.25), Vector3(8.0, 0.35, 10.25), par)
	g.box(Vector3(0.25, 0.9, 10.7), Vector3(-0.25, 0.45, 5.0), par)
	g.box(Vector3(0.25, 0.9, 10.7), Vector3(16.25, 0.45, 5.0), par)
	_skyline(g)
	_stair_hut(g, Vector3(4.0, 0.0, 7.8))
	_tank_stand(g, Vector3(11.6, 0.0, 6.2))
	_coop(g, Vector3(1.3, 0.0, 9.2))
	g.block(Vector3(2.2, 2.3, 1.8), Vector3(12.4, 0.0, 1.0), g.mat("clay_plaster", 0.5, Color(0.92, 0.74, 0.62)), 0.0)
	g.box(Vector3(2.4, 0.12, 2.0), Vector3(12.4, 2.36, 1.0), g.mat("clay_plaster", 0.6, Color(0.8, 0.6, 0.48)))
	g.box(Vector3(0.8, 1.7, 0.05), Vector3(12.0, 0.85, 1.93), g.mat("worn_planks", 0.8, Color(0.7, 0.35, 0.25)))
	g.block(Vector3(3.0, 1.5, 0.35), Vector3(9.0, 0.0, 8.5), par, 0.0)
	g.block(Vector3(0.35, 1.5, 2.8), Vector3(13.6, 0.0, 4.6), par, 0.0)
	_rug_frame(g, Vector3(2.8, 0.0, 2.4), 20.0, Color(0.7, 0.12, 0.1))
	_rug_frame(g, Vector3(10.2, 0.0, 3.6), -70.0, Color(0.15, 0.3, 0.6))
	for k in 3:
		g.fit("small_lpg_tank", Vector3(9.4 + k * 0.45, 0.0, 0.9 + (k % 2) * 0.3), k * 50.0, 0.6)
	g.solid(Vector3(9.85, 0.3, 1.05), Vector3(1.5, 0.6, 0.8))
	for k in 2:
		g.prop("wooden_crate_01" if k == 0 else "wooden_crate_02", Vector3(5.4, 0.62 * k, 1.0), k * 18.0)
	g.solid(Vector3(5.4, 0.62, 1.0), Vector3(0.9, 1.24, 0.9))
	g.fit("outdoor_table_chair_set_01", Vector3(6.8, 0.0, 9.3), 10.0, 0.95)
	g.fit("plastic_monobloc_chair_01", Vector3(14.6, 0.0, 7.6), -120.0, 0.85)
	g.fit("plastic_monobloc_chair_01", Vector3(8.0, 0.0, 5.6), 40.0, 0.85)
	_dish(g, Vector3(14.9, 0.0, 9.0), -140.0)
	for pp in [Vector3(0.5, 0, 0.5), Vector3(15.5, 0, 9.5), Vector3(5.8, 0, 9.6), Vector3(6.6, 0, 0.4)]:
		g.fit("planter_pot_clay", pp, pp.x * 20.0, 0.55)
		g.prop("shrub_02", pp + Vector3(0, 0.45, 0), pp.z * 33.0, 0.45)
	for cp in [Vector3(6.2, 0, 6.4), Vector3(10.6, 0, 9.6), Vector3(1.4, 0, 4.0)]:
		g.fit("ceramic_pot", cp, cp.x * 31.0, 0.6)
	_lights(g)

static func _skyline(g) -> void:
	var tints := [Color(0.98, 0.8, 0.64), Color(0.95, 0.68, 0.55), Color(0.9, 0.86, 0.78), Color(0.92, 0.6, 0.48), Color(0.85, 0.75, 0.62)]
	var houses := [[-8.0, -8.0, 7.0, 6.0, 1.5], [0.0, -8.5, 7.0, 6.0, -1.5], [8.0, -9.0, 8.0, 7.0, 3.5], [16.0, -8.5, 7.0, 6.0, 0.5], [24.0, -8.0, 8.0, 6.0, 2.0],
		[-8.0, 0.0, 6.0, 7.0, -0.8], [-9.0, 7.0, 6.0, 7.0, 1.0], [-8.5, 14.0, 7.0, 6.0, -3.5], [24.5, 0.0, 7.0, 7.0, 1.8], [25.0, 7.5, 7.0, 6.0, -0.5],
		[24.0, 14.0, 7.0, 6.0, -3.0], [4.0, 17.0, 10.0, 6.0, -4.0], [14.0, 17.0, 10.0, 6.0, -4.5], [-2.0, -16.0, 9.0, 8.0, 4.5], [12.0, -17.0, 10.0, 8.0, 2.5], [-14.0, -2.0, 6.0, 8.0, 3.0], [31.0, -3.0, 6.0, 8.0, 4.0]]
	var i := 0
	var dark: StandardMaterial3D = g.mat("dirty_concrete", 0.8, Color(0.12, 0.1, 0.1))
	var lit: StandardMaterial3D = g.glow(Color(1.0, 0.72, 0.4), 1.4)
	for h in houses:
		var top: float = h[4]
		var size := Vector3(h[2], top + 9.0, h[3])
		var c := Vector3(h[0], -9.0 + size.y * 0.5, h[1])
		g.box(size, c, g.mat("clay_plaster", 0.4, tints[i % tints.size()]))
		g.box(Vector3(size.x + 0.2, 0.5, size.z + 0.2), Vector3(c.x, top + 0.25, c.z), g.mat("clay_plaster", 0.6, tints[(i + 2) % tints.size()].darkened(0.1)))
		for w in 3:
			var face := Vector3(0, 0, size.z * 0.5 + 0.03) if c.z < 5.0 else Vector3(0, 0, -size.z * 0.5 - 0.03)
			if absf(c.x - 8.0) > 12.0:
				face = Vector3(size.x * 0.5 + 0.03, 0, 0) if c.x < 8.0 else Vector3(-size.x * 0.5 - 0.03, 0, 0)
			var along := Vector3(1.6 * (w - 1), 0, 0) if face.x == 0.0 else Vector3(0, 0, 1.6 * (w - 1))
			var wsize := Vector3(0.8, 1.1, 0.04) if face.x == 0.0 else Vector3(0.04, 1.1, 0.8)
			g.box(wsize, Vector3(c.x, top - 1.6, c.z) + face + along, lit if (i + w) % 3 == 0 else dark)
		if i % 3 == 0:
			_dish(g, Vector3(c.x + 1.0, top + 0.5, c.z), i * 40.0)
		if i % 4 == 1:
			g.fit("barrel_03", Vector3(c.x - 1.4, top + 0.5, c.z + 0.6), 0.0, 1.0)
		if i % 2 == 0 and top > -1.0:
			_laundry(g, Vector3(c.x - 2.0, top + 0.5, c.z - 1.0), Vector3(c.x + 2.0, top + 0.5, c.z - 1.0), i)
		i += 1
	var mc := Vector3(27.0, 0, -18.0)
	g.box(Vector3(3.6, 30.0, 3.6), mc + Vector3(0, 6.0, 0), g.mat("clay_plaster", 0.3, Color(0.92, 0.72, 0.55)))
	g.box(Vector3(3.8, 1.6, 3.8), mc + Vector3(0, 19.0, 0), g.mat("patterned_terracotta_tiling", 0.4, Color(0.4, 0.75, 0.6)))
	g.box(Vector3(4.2, 0.4, 4.2), mc + Vector3(0, 21.2, 0), g.mat("clay_plaster", 0.5, Color(0.9, 0.7, 0.55)))
	g.box(Vector3(1.8, 3.0, 1.8), mc + Vector3(0, 22.9, 0), g.mat("clay_plaster", 0.5, Color(0.95, 0.75, 0.6)))
	g.cyl(0.08, 2.0, mc + Vector3(0, 25.4, 0), g.dull("rusty_metal", 1.0, Color(1.0, 0.85, 0.4)))
	g.box(Vector3(0.6, 0.8, 0.6), mc + Vector3(0, 23.0, 0.92), g.glow(Color(0.4, 1.0, 0.5), 3.0))
	g.omni(mc + Vector3(0, 23.0, 2.0), Color(0.4, 1.0, 0.5), 3.0, 10.0)

static func _laundry(g, a: Vector3, b: Vector3, seed_i: int) -> void:
	var pole: StandardMaterial3D = g.dull("rusty_metal_02", 1.2, Color(0.7, 0.7, 0.7))
	g.box(Vector3(0.06, 2.0, 0.06), a + Vector3(0, 1.0, 0), pole)
	g.box(Vector3(0.06, 2.0, 0.06), b + Vector3(0, 1.0, 0), pole)
	g.box(Vector3(a.distance_to(b), 0.02, 0.02), (a + b) * 0.5 + Vector3(0, 1.95, 0), pole)
	var cols := [Color(0.9, 0.2, 0.2), Color(0.95, 0.95, 0.9), Color(0.2, 0.5, 0.9), Color(1.0, 0.75, 0.2), Color(0.3, 0.7, 0.4)]
	for k in 4:
		var t := 0.15 + k * 0.23
		var p := a.lerp(b, t) + Vector3(0, 1.55, 0)
		g.box(Vector3(0.6, 0.75, 0.02), p, g.mat("dirty_carpet", 1.0, cols[(seed_i + k) % cols.size()]))

static func _dish(g, base: Vector3, yaw: float) -> void:
	var metal: StandardMaterial3D = g.dull("rusty_metal_02", 1.2, Color(0.85, 0.85, 0.85))
	g.box(Vector3(0.06, 1.0, 0.06), base + Vector3(0, 0.5, 0), metal)
	var dish := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.1
	cm.height = 0.18
	dish.mesh = cm
	dish.material_override = g.dull("blue_metal_plate", 1.0, Color(0.9, 0.9, 0.88))
	g.world.add_child(dish)
	dish.position = base + Vector3(0, 1.05, 0)
	dish.rotation_degrees = Vector3(-60.0, yaw, 0.0)

static func _stair_hut(g, base: Vector3) -> void:
	g.block(Vector3(2.4, 2.5, 2.2), base, g.mat("clay_plaster", 0.5, Color(0.98, 0.84, 0.7)), 0.0)
	g.box(Vector3(2.6, 0.15, 2.4), base + Vector3(0, 2.57, 0), g.mat("clay_plaster", 0.6, Color(0.85, 0.65, 0.5)))
	g.box(Vector3(0.9, 1.9, 0.06), base + Vector3(0.5, 0.95, -1.12), g.mat("worn_planks", 0.8, Color(0.25, 0.45, 0.6)))
	g.fit("brass_diya_lantern", base + Vector3(-0.4, 1.8, -1.2), 0.0, 0.35)
	g.omni(base + Vector3(-0.4, 1.8, -1.6), Color(1.0, 0.7, 0.35), 1.8, 4.0)
	g.fit("ceramic_pot", base + Vector3(1.4, 0.0, 0.6), 30.0, 0.5)

static func _coop(g, base: Vector3) -> void:
	var wood: StandardMaterial3D = g.mat("old_planks_02", 0.8, Color(0.6, 0.48, 0.38))
	g.block(Vector3(1.8, 1.6, 1.4), base, wood, 0.0)
	var mesh: StandardMaterial3D = g.dull("rusty_metal_02", 2.0, Color(0.5, 0.5, 0.5))
	g.box(Vector3(1.6, 0.8, 0.04), base + Vector3(0, 1.0, -0.72), mesh)
	g.box(Vector3(2.0, 0.08, 1.6), base + Vector3(0, 1.64, 0), g.mat("corrugated_iron", 0.8, Color(0.6, 0.5, 0.4)))
	for k in 3:
		g.fit("ceramic_pot", base + Vector3(-0.5 + k * 0.5, 1.68, 0.2), k * 60.0, 0.3)

static func _tank_stand(g, base: Vector3) -> void:
	var metal: StandardMaterial3D = g.dull("rusty_metal_02", 1.0, Color(0.85, 0.8, 0.75))
	for x in [-0.75, 0.75]:
		for z in [-0.75, 0.75]:
			g.box(Vector3(0.1, 1.2, 0.1), base + Vector3(x, 0.6, z), metal)
	g.box(Vector3(1.7, 0.1, 1.7), base + Vector3(0, 1.2, 0), metal)
	g.cyl(0.7, 1.1, base + Vector3(-0.0, 1.8, 0), g.dull("blue_metal_plate", 0.8, Color(0.95, 0.95, 0.9)))
	g.box(Vector3(1.7, 1.0, 0.08), base + Vector3(0, 0.55, -0.8), g.mat("corrugated_iron", 0.8, Color(0.8, 0.7, 0.6)))
	g.solid(base + Vector3(0, 1.15, 0), Vector3(1.8, 2.3, 1.8))

static func _rug_frame(g, base: Vector3, yaw: float, col: Color) -> void:
	var holder := Node3D.new()
	g.world.add_child(holder)
	holder.position = base
	holder.rotation_degrees.y = yaw
	var wood: StandardMaterial3D = g.mat("old_planks_02", 1.0, Color(0.55, 0.42, 0.32))
	for x in [-1.05, 1.05]:
		g.box(Vector3(0.08, 1.8, 0.08), Vector3(x, 0.9, 0), wood, holder)
	g.box(Vector3(2.2, 0.08, 0.08), Vector3(0, 1.78, 0), wood, holder)
	g.box(Vector3(1.9, 1.5, 0.04), Vector3(0, 1.0, 0.05), g.mat("dirty_carpet", 0.5, col), holder)
	g.box(Vector3(1.9, 1.5, 0.04), Vector3(0, 1.0, -0.05), g.mat("dirty_carpet", 0.7, col.lightened(0.15)), holder)
	g.solid(base + Vector3(0, 0.9, 0), Vector3(2.0, 1.8, 0.25), yaw)

static func _lights(g) -> void:
	var cord: StandardMaterial3D = g.dull("rusty_metal_02", 1.0, Color(0.2, 0.2, 0.2))
	var bulb: StandardMaterial3D = g.glow(Color(1.0, 0.75, 0.4), 1.6)
	var lines := [[Vector3(-0.2, 3.4, -0.2), Vector3(16.2, 3.4, 10.2)], [Vector3(16.2, 3.4, -0.2), Vector3(-0.2, 3.4, 10.2)]]
	for e in lines:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		for p in [a, b]:
			g.box(Vector3(0.08, 3.4, 0.08), Vector3(p.x, 1.7, p.z), cord)
		for k in 18:
			var t := float(k + 1) / 19.0
			var p2 := a.lerp(b, t) - Vector3(0, sin(t * PI) * 0.6, 0)
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.04
			sm.height = 0.08
			s.mesh = sm
			s.material_override = bulb
			g.world.add_child(s)
			s.position = p2
	g.omni(Vector3(4.0, 2.9, 2.5), Color(1.0, 0.75, 0.42), 2.0, 6.0, true)
	g.omni(Vector3(12.0, 2.9, 7.5), Color(1.0, 0.75, 0.42), 2.0, 6.0)
	g.omni(Vector3(8.0, 2.8, 5.0), Color(1.0, 0.72, 0.4), 1.6, 6.0)
