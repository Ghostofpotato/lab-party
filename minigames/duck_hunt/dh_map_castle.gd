extends RefCounted
## Duck Hunt map: Castle Bailey. The inner yard of a castle at dusk; curtain
## walls, torches, a hay cart, barrel stacks, a well and wooden siege towers.

static func layout() -> Dictionary:
	return {
		"name": "CASTLE BAILEY",
		"towers": [Vector3(8.0, 0.0, -2.0), Vector3(-1.6, 0.0, 9.0)],
		"lifts": [Vector3(8.0, 0.0, 0.8), Vector3(0.8, 0.0, 8.0)],
		"fusebox": Vector3(11.8, 0.0, 6.2),
		"skin": {"leg": ["old_planks_02", Color(0.75, 0.62, 0.48)], "wall": ["worn_planks", Color(0.8, 0.68, 0.55)], "floor": ["worn_planks", Color(0.7, 0.6, 0.5)], "roof": ["old_planks_02", Color(0.55, 0.45, 0.38)]},
	}

static func build(g) -> void:
	g.set_env({"bg": Color("1a1020"), "amb": Color(0.62, 0.48, 0.45), "amb_e": 0.55, "fog": Color(0.3, 0.22, 0.22), "fog_d": 0.008,
		"sat": 0.85, "exp": 1.1, "sun": Color(1.0, 0.58, 0.32), "sun_e": 0.9, "sun_rot": Vector3(-14.0, -62.0, 0.0),
		"sky": [Color(0.12, 0.1, 0.24), Color(0.9, 0.45, 0.28), Color(0.1, 0.08, 0.07)]})
	g.box(Vector3(70.0, 0.2, 70.0), Vector3(8.0, -0.1, 5.0), g.mat("gravel_floor", 0.45, Color(0.7, 0.62, 0.55)))
	g.box(Vector3(18.0, 0.04, 12.0), Vector3(8.0, 0.0, 5.0), g.mat("cobblestone_floor_01", 0.35, Color(0.85, 0.8, 0.75)))
	_walls(g)
	_hay_cart(g, Vector3(4.4, 0.0, 2.6), 15.0)
	_barrels(g, Vector3(12.2, 0.0, 2.2), -10.0)
	_barrels(g, Vector3(3.0, 0.0, 5.4), 80.0)
	_well(g, Vector3(7.8, 0.0, 5.2))
	var stone: StandardMaterial3D = g.mat("castle_brick_07", 0.45, Color(0.8, 0.75, 0.7))
	g.block(Vector3(3.0, 2.0, 0.8), Vector3(5.8, 0.0, 8.0), stone, -8.0)
	g.block(Vector3(0.8, 2.3, 2.4), Vector3(14.6, 0.0, 4.6), stone, 0.0)
	g.block(Vector3(2.0, 1.2, 0.7), Vector3(10.2, 0.0, 8.8), stone, 20.0)
	g.fit("cannon_01", Vector3(13.8, 0.0, 8.6), -150.0, 1.2, true)
	g.fit("cannon_01", Vector3(1.8, 0.0, 1.4), 30.0, 1.2, true)
	for c in [[Vector3(9.8, 0, 3.6), 3], [Vector3(15.0, 0, 1.0), 2], [Vector3(2.6, 0, 9.4), 2]]:
		for k in int(c[1]):
			g.prop("wooden_crate_01" if k % 2 == 0 else "wooden_crate_02", (c[0] as Vector3) + Vector3(0.03 * k, 0.62 * k, 0), k * 14.0)
		g.solid((c[0] as Vector3) + Vector3(0, 0.31 * int(c[1]), 0), Vector3(0.9, 0.62 * int(c[1]), 0.9))
	_dummy(g, Vector3(5.4, 0.0, 0.8))
	_dummy(g, Vector3(10.8, 0.0, 0.9))
	_fire(g, Vector3(7.2, 0.0, 9.5))
	g.prop("cardboard_box_01", Vector3(15.4, 0.0, 9.6), 30.0)
	g.fit("Barrel_01", Vector3(0.5, 0.0, 4.0), 0.0, 0.95)
	g.fit("Barrel_01", Vector3(15.6, 0.0, 6.6), 40.0, 0.95)

static func _walls(g) -> void:
	var wall: StandardMaterial3D = g.mat("castle_brick_07", 0.3, Color(0.8, 0.74, 0.68))
	var cap: StandardMaterial3D = g.mat("castle_brick_07", 0.5, Color(0.7, 0.65, 0.6))
	g.box(Vector3(44.0, 7.0, 1.6), Vector3(8.0, 3.5, -7.5), wall)
	g.box(Vector3(1.6, 7.0, 22.0), Vector3(-7.0, 3.5, 3.5), wall)
	g.box(Vector3(1.6, 7.0, 22.0), Vector3(23.0, 3.5, 3.5), wall)
	var mx := -13.0
	while mx < 30.0:
		g.box(Vector3(0.9, 1.0, 0.6), Vector3(mx, 7.5, -6.9), cap)
		mx += 1.8
	var mz := -6.0
	while mz < 14.0:
		g.box(Vector3(0.6, 1.0, 0.9), Vector3(-6.4, 7.5, mz), cap)
		g.box(Vector3(0.6, 1.0, 0.9), Vector3(22.4, 7.5, mz), cap)
		mz += 1.8
	for tc in [Vector3(-7.0, 0, -7.5), Vector3(23.0, 0, -7.5)]:
		g.cyl(2.6, 11.0, tc + Vector3(0, 5.5, 0), wall)
		var roof := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 3.0
		cm.height = 4.0
		roof.mesh = cm
		roof.material_override = g.mat("old_planks_02", 0.5, Color(0.35, 0.25, 0.3))
		g.world.add_child(roof)
		roof.position = tc + Vector3(0, 13.0, 0)
	g.box(Vector3(14.0, 18.0, 9.0), Vector3(8.0, 9.0, -14.0), wall)
	var win: StandardMaterial3D = g.glow(Color(1.0, 0.6, 0.25), 2.0)
	for wx in [3.0, 6.0, 10.0, 13.0]:
		g.box(Vector3(0.8, 1.6, 0.1), Vector3(wx, 13.0, -9.45), win)
	g.box(Vector3(4.4, 5.0, 0.3), Vector3(8.0, 2.5, -6.7), g.mat("old_planks_02", 0.6, Color(0.45, 0.35, 0.28)))
	for y in [1.0, 2.6, 4.2]:
		g.box(Vector3(4.5, 0.18, 0.1), Vector3(8.0, y, -6.5), g.dull("rusty_metal_02", 1.0, Color(0.5, 0.5, 0.5)))
	var banner_cols := [Color(0.65, 0.08, 0.06), Color(0.12, 0.18, 0.5)]
	var i := 0
	for bx in [-3.0, 3.0, 13.0, 19.0]:
		g.box(Vector3(1.4, 3.6, 0.05), Vector3(bx, 4.4, -6.65), g.mat("dirty_carpet", 0.6, banner_cols[i % 2]))
		g.box(Vector3(1.6, 0.08, 0.08), Vector3(bx, 6.25, -6.6), g.dull("rusty_metal_02", 1.0, Color.WHITE))
		i += 1
	var tk := 0
	for t in [[Vector3(0.0, 2.6, -6.6), 0.0], [Vector3(16.0, 2.6, -6.6), 0.0], [Vector3(-6.15, 2.6, 2.0), 90.0], [Vector3(22.15, 2.6, 2.0), -90.0], [Vector3(-6.15, 2.6, 9.0), 90.0], [Vector3(22.15, 2.6, 9.0), -90.0]]:
		_torch(g, t[0], t[1], tk)
		tk += 1
	for s in [Vector3(-5.0, 0, 12.0), Vector3(21.0, 0, 12.5), Vector3(-5.5, 0, -5.0), Vector3(21.5, 0, -5.0)]:
		g.prop("shrub_02", s, s.x * 23.0, 0.9)

static func _torch(g, pos: Vector3, yaw: float, k: int) -> void:
	var fwd := Vector3(0, 0, 0.25).rotated(Vector3.UP, deg_to_rad(yaw))
	var stick: MeshInstance3D = g.box(Vector3(0.08, 0.6, 0.08), pos + fwd, g.mat("old_planks_02", 1.0, Color(0.5, 0.4, 0.3)))
	stick.rotation_degrees.x = 20.0
	g.flame(pos + fwd * 1.5 + Vector3(0, 0.3, 0), 0.22)
	var l: OmniLight3D = g.omni(pos + fwd * 2.5 + Vector3(0, 0.5, 0), Color(1.0, 0.55, 0.22), 2.8, 7.0, k < 2)
	var tw := l.create_tween().set_loops()
	tw.tween_property(l, "light_energy", 2.2, 0.13 + k * 0.02)
	tw.tween_property(l, "light_energy", 3.1, 0.11)
	tw.tween_property(l, "light_energy", 2.6, 0.17)

static func _hay_cart(g, base: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	g.world.add_child(holder)
	holder.position = base
	holder.rotation_degrees.y = yaw
	var wood: StandardMaterial3D = g.mat("worn_planks", 0.8, Color(0.75, 0.6, 0.45))
	g.box(Vector3(2.6, 0.12, 1.4), Vector3(0, 0.75, 0), wood, holder)
	g.box(Vector3(2.6, 0.5, 0.06), Vector3(0, 1.05, 0.68), wood, holder)
	g.box(Vector3(2.6, 0.5, 0.06), Vector3(0, 1.05, -0.68), wood, holder)
	g.box(Vector3(2.3, 0.8, 1.25), Vector3(0, 1.2, 0), g.mat("gravel_floor", 1.2, Color(0.95, 0.78, 0.38)), holder)
	for wx in [-0.8, 0.8]:
		for wz in [-0.75, 0.75]:
			var w: MeshInstance3D = g.cyl(0.42, 0.1, Vector3(wx, 0.42, wz), wood, holder)
			w.rotation_degrees.x = 90.0
	var shaft: MeshInstance3D = g.box(Vector3(1.6, 0.08, 0.08), Vector3(2.0, 0.55, 0.3), wood, holder)
	shaft.rotation_degrees.z = 14.0
	g.solid(base + Vector3(0, 0.8, 0), Vector3(2.6, 1.6, 1.4), yaw)

static func _barrels(g, base: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	g.world.add_child(holder)
	holder.position = base
	holder.rotation_degrees.y = yaw
	for k in 3:
		g.fit("wine_barrel_01", Vector3(-0.8 + k * 0.8, 0.0, 0), 0.0, 0.76, false, holder, Vector3(90, 0, 0))
	for k in 2:
		g.fit("wine_barrel_01", Vector3(-0.4 + k * 0.8, 0.7, 0), 0.0, 0.76, false, holder, Vector3(90, 0, 0))
	g.solid(base + Vector3(0, 0.75, 0), Vector3(2.4, 1.5, 1.0), yaw)

static func _well(g, c: Vector3) -> void:
	var stone: StandardMaterial3D = g.mat("cobblestone_floor_01", 0.6, Color(0.7, 0.68, 0.65))
	for e in [[Vector3(0, 0, -0.8), Vector3(1.9, 0.9, 0.3)], [Vector3(0, 0, 0.8), Vector3(1.9, 0.9, 0.3)], [Vector3(-0.8, 0, 0), Vector3(0.3, 0.9, 1.3)], [Vector3(0.8, 0, 0), Vector3(0.3, 0.9, 1.3)]]:
		g.box(e[1], c + e[0] + Vector3(0, 0.45, 0), stone)
	g.box(Vector3(1.3, 0.05, 1.3), c + Vector3(0, 0.7, 0), g.mat("dark_rock", 0.6, Color(0.05, 0.06, 0.07)))
	var wood: StandardMaterial3D = g.mat("old_planks_02", 0.8, Color(0.6, 0.5, 0.4))
	for x in [-0.85, 0.85]:
		g.box(Vector3(0.12, 2.2, 0.12), c + Vector3(x, 1.1, 0), wood)
	var r1: MeshInstance3D = g.box(Vector3(2.2, 0.06, 1.0), c + Vector3(0, 2.35, 0.35), wood)
	r1.rotation_degrees.x = 30.0
	var r2: MeshInstance3D = g.box(Vector3(2.2, 0.06, 1.0), c + Vector3(0, 2.35, -0.35), wood)
	r2.rotation_degrees.x = -30.0
	g.prop("wooden_crate_02", c + Vector3(1.4, 0, 0.6), 20.0, 0.7)
	g.solid(c + Vector3(0, 0.5, 0), Vector3(2.0, 1.0, 2.0))
	g.solid(c + Vector3(0, 1.2, 0), Vector3(1.9, 2.4, 0.3))

static func _dummy(g, base: Vector3) -> void:
	var wood: StandardMaterial3D = g.mat("old_planks_02", 1.0, Color(0.6, 0.48, 0.38))
	g.box(Vector3(0.12, 1.8, 0.12), base + Vector3(0, 0.9, 0), wood)
	g.box(Vector3(1.1, 0.1, 0.1), base + Vector3(0, 1.4, 0), wood)
	g.box(Vector3(0.5, 0.7, 0.3), base + Vector3(0, 1.25, 0), g.mat("gravel_floor", 1.2, Color(0.9, 0.75, 0.4)))
	g.cyl(0.18, 0.3, base + Vector3(0, 1.8, 0), g.mat("dirty_carpet", 1.0, Color(0.85, 0.75, 0.55)))

static func _fire(g, pos: Vector3) -> void:
	g.fit("stone_fire_pit", pos, 0.0, 0.45)
	g.flame(pos + Vector3(0, 0.15, 0), 0.45)
	g.flame(pos + Vector3(0.15, 0.15, 0.1), 0.3)
	g.flame(pos + Vector3(-0.12, 0.15, -0.08), 0.32)
	var l: OmniLight3D = g.omni(pos + Vector3(0, 0.9, 0), Color(1.0, 0.5, 0.18), 4.0, 6.0, true)
	var tw := l.create_tween().set_loops()
	tw.tween_property(l, "light_energy", 3.0, 0.12)
	tw.tween_property(l, "light_energy", 4.6, 0.09)
	tw.tween_property(l, "light_energy", 3.6, 0.15)
