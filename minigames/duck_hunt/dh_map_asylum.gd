extends RefCounted
## Duck Hunt map: Blackwood Asylum. A moonlit, fog-choked courtyard of an
## abandoned asylum; dry fountain, toppled beds, hedges, flickering lamps.

static func layout() -> Dictionary:
	return {
		"name": "BLACKWOOD ASYLUM",
		"towers": [Vector3(17.4, 0.0, -1.6), Vector3(-1.6, 0.0, 11.2)],
		"lifts": [Vector3(15.2, 0.0, 0.8), Vector3(0.8, 0.0, 9.2)],
		"fusebox": Vector3(10.6, 0.0, 5.0),
		"skin": {"leg": ["rusty_metal_02", Color(0.55, 0.6, 0.55)], "wall": ["black_painted_planks", Color(0.7, 0.75, 0.7)], "floor": ["old_planks_02", Color(0.5, 0.5, 0.45)], "roof": ["corrugated_iron", Color(0.35, 0.4, 0.38)]},
	}

static func build(g) -> void:
	g.set_env({"bg": Color("030504"), "amb": Color(0.4, 0.5, 0.44), "amb_e": 0.78, "fog": Color(0.1, 0.14, 0.11), "fog_d": 0.045,
		"sat": 0.55, "exp": 1.3, "sun": Color(0.62, 0.85, 0.72), "sun_e": 0.3, "sun_rot": Vector3(-42.0, -150.0, 0.0)})
	g.box(Vector3(70.0, 0.2, 70.0), Vector3(8.0, -0.1, 5.0), g.mat("gravel_floor", 0.45, Color(0.6, 0.66, 0.6)))
	g.box(Vector3(17.5, 0.04, 11.5), Vector3(8.0, 0.0, 5.0), g.mat("damaged_concrete_floor", 0.3, Color(0.72, 0.78, 0.72)))
	g.box(Vector3(17.5, 0.05, 1.6), Vector3(8.0, 0.0, 5.0), g.mat("dirty_tiles", 0.5, Color(0.8, 0.85, 0.78)))
	g.box(Vector3(1.6, 0.05, 11.5), Vector3(5.0, 0.0, 5.0), g.mat("dirty_tiles", 0.5, Color(0.8, 0.85, 0.78)))
	_building(g)
	_fountain(g, Vector3(5.0, 0.0, 5.0))
	_bed(g, Vector3(2.4, 0.0, 2.4), 12.0)
	_bed(g, Vector3(12.4, 0.0, 8.3), -18.0)
	_hedge(g, Vector3(8.3, 0.0, 1.6), 0.0)
	_hedge(g, Vector3(2.2, 0.0, 6.9), 90.0)
	var brick: StandardMaterial3D = g.mat("dark_brick_wall", 0.5, Color(0.75, 0.75, 0.7))
	g.block(Vector3(3.2, 2.2, 0.5), Vector3(7.8, 0.0, 7.6), brick, 0.0)
	g.block(Vector3(0.5, 1.4, 1.4), Vector3(9.15, 0.0, 7.1), brick, 0.0)
	g.block(Vector3(2.6, 2.0, 0.5), Vector3(12.8, 0.0, 2.6), brick, 70.0)
	_cabinet(g, Vector3(14.4, 0.0, 5.0), -90.0)
	_cabinet(g, Vector3(4.6, 0.0, 8.8), 180.0)
	g.block(Vector3(1.6, 1.1, 0.9), Vector3(9.6, 0.0, 3.0), g.dull("rusty_metal", 1.0, Color(0.75, 0.78, 0.74)), 25.0)
	g.prop("trashbag", Vector3(9.4, 1.1, 3.0), 20.0, 0.9)
	g.prop("trashbag", Vector3(9.9, 1.1, 3.2), 140.0, 0.8)
	for b in [[Vector3(6.6, 0.0, 2.1), 0.0], [Vector3(9.4, 0.0, 9.0), 90.0], [Vector3(14.6, 0.0, 9.2), 0.0]]:
		g.block(Vector3(1.8, 0.5, 0.55), b[0], g.mat("concrete_wall_006", 0.6, Color(0.7, 0.72, 0.7)), b[1])
	g.fit("wheelchair_01", Vector3(3.9, 0.0, 8.0), 140.0, 0.95)
	g.fit("wheelchair_01", Vector3(11.8, 0.0, 1.3), 35.0, 0.95)
	g.fit("wheelchair_01", Vector3(15.0, 0.0, 6.9), -80.0, 0.95)
	g.fit("wheelchair_01", Vector3(7.0, 0.0, 6.3), 0.0, 0.8, false, null, Vector3(0, 0, 80))
	g.fit("vintage_crutches_01", Vector3(6.2, 0.05, 3.7), 30.0, 1.2)
	g.fit("vintage_crutches_01", Vector3(13.2, 0.05, 6.4), 110.0, 1.2)
	for t in [Vector3(-3.6, 0, 2.0), Vector3(19.6, 0, 6.0), Vector3(-4.2, 0, -4.0), Vector3(21.0, 0, -3.5), Vector3(3.0, 0, -5.0), Vector3(12.5, 0, -5.5), Vector3(-4.5, 0, 9.0), Vector3(20.5, 0, 12.0)]:
		g.dead_tree(t, t.x * 37.0, 4.5)
	for s in [Vector3(-2.5, 0, -2.5), Vector3(18.5, 0, 3.0), Vector3(-2.8, 0, 6.0), Vector3(18.8, 0, 10.0), Vector3(6.0, 0, -3.0), Vector3(10.0, 0, -3.2)]:
		g.prop("shrub_02", s, s.z * 51.0, 1.1)
	for n in [Vector3(0.6, 0, 4.2), Vector3(15.6, 0, 3.4), Vector3(10.6, 0, 0.5), Vector3(3.4, 0, 0.4), Vector3(7.4, 0, 9.6)]:
		g.prop("nettle_plant", n, n.x * 41.0, 1.5)
	var li := 0
	for lp in [Vector3(-0.9, 0, 4.0), Vector3(16.9, 0, 7.0), Vector3(6.2, 0, -1.0), Vector3(-0.9, 0, -0.6)]:
		g.box(Vector3(0.14, 4.0, 0.14), lp + Vector3(0, 2.0, 0), g.dull("rusty_metal_02", 1.0, Color(0.4, 0.42, 0.4)))
		g.fit("street_lamp_02", lp + Vector3(0, 3.0, 0.1), 0.0, 1.5)
		var l: OmniLight3D = g.omni(lp + Vector3(0, 4.1, 0), Color(0.75, 1.0, 0.8), 3.2, 8.0, li < 2)
		g.flicker(l, 3.2, 71 + li)
		li += 1
	g.omni(Vector3(8.0, 2.5, -6.0), Color(1.0, 0.2, 0.1), 2.0, 7.0)

static func _building(g) -> void:
	var wallm: StandardMaterial3D = g.mat("peeling_painted_wall", 0.3, Color(0.72, 0.8, 0.72))
	var base: StandardMaterial3D = g.mat("dark_brick_wall", 0.4, Color(0.6, 0.62, 0.58))
	g.box(Vector3(52.0, 12.0, 0.8), Vector3(8.0, 6.0, -8.5), wallm)
	g.box(Vector3(52.0, 1.4, 1.0), Vector3(8.0, 0.7, -8.3), base)
	g.box(Vector3(0.8, 10.0, 24.0), Vector3(-7.5, 5.0, 3.5), wallm)
	g.box(Vector3(0.8, 10.0, 24.0), Vector3(23.5, 5.0, 3.5), wallm)
	g.box(Vector3(52.0, 0.6, 1.4), Vector3(8.0, 12.2, -8.3), g.mat("concrete_wall_008", 0.5, Color(0.55, 0.58, 0.55)))
	var bars: StandardMaterial3D = g.dull("rusty_metal_02", 1.5, Color(0.5, 0.5, 0.5))
	var lit: StandardMaterial3D = g.glow(Color(0.8, 0.9, 0.45), 1.4)
	var dark: StandardMaterial3D = g.mat("dirty_concrete", 0.6, Color(0.12, 0.13, 0.12))
	var k := 0
	for wy in [3.4, 7.6]:
		var wx := -14.0
		while wx < 31.0:
			var on := (k * 7) % 5 == 0
			g.box(Vector3(1.4, 1.9, 0.1), Vector3(wx, wy, -8.05), lit if on else dark)
			for bx in [-0.45, 0.0, 0.45]:
				g.box(Vector3(0.05, 1.9, 0.05), Vector3(wx + bx, wy, -7.98), bars)
			if on and wy < 5.0:
				var l: OmniLight3D = g.omni(Vector3(wx, wy, -7.0), Color(0.8, 0.95, 0.5), 1.4, 4.0)
				g.flicker(l, 1.4, k)
			wx += 3.5
			k += 1
	for side in [-7.05, 23.05]:
		for wz in [-4.0, 0.0, 4.0, 8.0]:
			g.box(Vector3(0.1, 1.9, 1.4), Vector3(side, 3.4, wz), dark)
			g.box(Vector3(0.1, 1.9, 1.4), Vector3(side, 7.6, wz), lit if int(wz) % 8 == 0 else dark)
	g.fit("large_iron_gate", Vector3(8.0, 0.0, -7.9), 0.0, 4.0)
	g.sign3d("BLACKWOOD ASYLUM", Vector3(8.0, 10.4, -8.0), Color(0.75, 0.82, 0.7), 140)
	g.sign3d("VISITING HOURS: NEVER", Vector3(2.0, 2.2, -7.85), Color(0.9, 0.85, 0.6), 40)

static func _fountain(g, c: Vector3) -> void:
	var stone: StandardMaterial3D = g.mat("concrete_wall_006", 0.5, Color(0.65, 0.68, 0.64))
	for e in [[Vector3(0, 0, -1.3), Vector3(2.8, 0.85, 0.3)], [Vector3(0, 0, 1.3), Vector3(2.8, 0.85, 0.3)], [Vector3(-1.3, 0, 0), Vector3(0.3, 0.85, 2.3)], [Vector3(1.3, 0, 0), Vector3(0.3, 0.85, 2.3)]]:
		g.box(e[1], c + e[0] + Vector3(0, 0.425, 0), stone)
	g.box(Vector3(2.4, 0.3, 2.4), c + Vector3(0, 0.15, 0), g.mat("dark_rock", 0.6, Color(0.25, 0.3, 0.25)))
	g.solid(c + Vector3(0, 0.45, 0), Vector3(2.9, 0.9, 2.9))
	g.block(Vector3(0.7, 2.6, 0.7), c, stone)
	g.box(Vector3(1.3, 0.2, 1.3), c + Vector3(0, 2.7, 0), stone)
	g.fit("old_gas_mask", c + Vector3(0, 2.8, 0), 180.0, 0.35)

static func _bed(g, base: Vector3, yaw: float) -> void:
	var holder := Node3D.new()
	g.world.add_child(holder)
	holder.position = base
	holder.rotation_degrees.y = yaw
	var frame: StandardMaterial3D = g.dull("rusty_metal", 1.2, Color(0.8, 0.82, 0.78))
	g.box(Vector3(2.1, 1.0, 0.22), Vector3(0, 0.6, 0.0), g.mat("dirty_carpet", 0.8, Color(0.85, 0.8, 0.6)), holder)
	for x in [-1.05, 1.05]:
		g.box(Vector3(0.06, 1.25, 0.06), Vector3(x, 0.62, -0.15), frame, holder)
		g.box(Vector3(0.06, 0.06, 0.9), Vector3(x, 1.2, 0.3), frame, holder)
	g.box(Vector3(2.16, 0.06, 0.06), Vector3(0, 1.22, -0.15), frame, holder)
	g.box(Vector3(2.16, 0.06, 0.06), Vector3(0, 0.05, -0.15), frame, holder)
	g.solid(base + Vector3(0, 0.6, 0), Vector3(2.2, 1.2, 0.6), yaw)

static func _hedge(g, base: Vector3, yaw: float) -> void:
	g.block(Vector3(2.6, 1.3, 0.9), base, g.mat("dark_rock", 0.8, Color(0.36, 0.5, 0.3)), yaw)
	var d := Vector3(1.0, 0, 0).rotated(Vector3.UP, deg_to_rad(yaw))
	for k in [-0.9, 0.0, 0.9]:
		g.prop("shrub_02", base + d * k + Vector3(0, 0.5, 0), k * 90.0 + yaw, 1.0)

static func _cabinet(g, base: Vector3, yaw: float) -> void:
	g.block(Vector3(1.4, 1.9, 0.6), base, g.dull("green_metal_rust", 0.9, Color(0.85, 0.92, 0.85)), yaw)
	var fwd := Vector3(0, 0, 0.32).rotated(Vector3.UP, deg_to_rad(yaw))
	var m: Node3D = g.prop("medical_box", base + fwd + Vector3(0, 1.9, 0) - fwd, yaw, 1.0)
	if m:
		m.position.y = 1.9
