extends RefCounted
## Duck Hunt map: Wondertoy Factory. A grimy toy plant floor after the night
## shift; giant letter blocks, giant rubber ducks, conveyor lines, box stacks.

static func layout() -> Dictionary:
	return {
		"name": "WONDERTOY FACTORY",
		"towers": [Vector3(-1.6, 0.0, 3.0), Vector3(17.6, 0.0, 7.0)],
		"lifts": [Vector3(0.8, 0.0, 3.0), Vector3(15.2, 0.0, 7.0)],
		"fusebox": Vector3(8.0, 0.0, 7.4),
		"skin": {"leg": ["green_metal_rust", Color(1.0, 0.85, 0.35)], "wall": ["blue_metal_plate", Color(0.9, 0.5, 0.5)], "floor": ["rubber_tiles", Color(0.6, 0.6, 0.6)], "roof": ["blue_metal_plate", Color(0.5, 0.7, 1.0)]},
	}

static func build(g) -> void:
	g.set_env({"bg": Color("0a0806"), "amb": Color(0.78, 0.66, 0.52), "amb_e": 0.75, "fog": Color(0.24, 0.19, 0.14), "fog_d": 0.014,
		"sat": 1.05, "exp": 1.15, "sun": Color(1.0, 0.9, 0.75), "sun_e": 0.25, "sun_rot": Vector3(-65.0, -30.0, 0.0)})
	g.box(Vector3(50.0, 0.2, 40.0), Vector3(8.0, -0.1, 4.0), g.mat("garage_floor", 0.35, Color(0.7, 0.66, 0.6)))
	g.box(Vector3(17.6, 0.03, 11.6), Vector3(8.0, 0.0, 5.0), g.mat("concrete_floor_worn_001", 0.3, Color(0.85, 0.82, 0.75)))
	var stripe: StandardMaterial3D = g.mat("grey_plaster_03", 0.6, Color(1.0, 0.78, 0.1))
	for e in [[Vector3(8.0, 0.02, -0.6), Vector3(17.6, 0.02, 0.18)], [Vector3(8.0, 0.02, 10.6), Vector3(17.6, 0.02, 0.18)], [Vector3(-0.6, 0.02, 5.0), Vector3(0.18, 0.02, 11.4)], [Vector3(16.6, 0.02, 5.0), Vector3(0.18, 0.02, 11.4)]]:
		g.box(e[1], e[0], stripe)
	_hall(g)
	var cols := [Color(0.95, 0.3, 0.25), Color(0.3, 0.5, 1.0), Color(1.0, 0.82, 0.2), Color(0.35, 0.85, 0.4)]
	_toy_block(g, Vector3(3.6, 0.0, 1.6), 0.0, cols[0], "A")
	_toy_block(g, Vector3(5.1, 0.0, 1.6), 0.0, cols[1], "B")
	_toy_block(g, Vector3(4.35, 1.5, 1.6), 8.0, cols[2], "C")
	g.solid(Vector3(4.35, 1.5, 1.6), Vector3(3.0, 3.0, 1.5))
	_toy_block(g, Vector3(11.8, 0.0, 4.6), 20.0, cols[3], "D")
	g.solid(Vector3(11.8, 0.75, 4.6), Vector3(1.5, 1.5, 1.5), 20.0)
	_toy_block(g, Vector3(4.6, 0.0, 8.2), -15.0, cols[1], "U")
	g.solid(Vector3(4.6, 0.75, 8.2), Vector3(1.5, 1.5, 1.5), -15.0)
	_toy_block(g, Vector3(13.0, 0.0, 9.3), 5.0, cols[0], "K")
	g.solid(Vector3(13.0, 0.75, 9.3), Vector3(1.5, 1.5, 1.5), 5.0)
	g.fit("rubber_duck_toy", Vector3(8.8, 0.0, 2.2), 200.0, 2.3, true)
	g.fit("rubber_duck_toy", Vector3(13.6, 0.0, 1.6), 150.0, 1.6, true)
	g.fit("rubber_duck_toy", Vector3(2.6, 0.0, 5.6), 120.0, 1.9, true)
	var rej: Label3D = g.sign3d("QC: REJECTED", Vector3(8.8, 2.8, 2.2), Color(1.0, 0.25, 0.2), 48)
	rej.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var ball: Node3D = g.fit("american_football", Vector3(10.6, 0.0, 8.6), 70.0, 1.1, true)
	if ball:
		ball.rotation_degrees.z = 8.0
	_conveyor(g, Vector3(7.4, 0.0, 4.9), 4.2)
	for st in [[Vector3(1.6, 0, 0.8), 3], [Vector3(14.4, 0, 9.1), 2], [Vector3(15.0, 0, 3.8), 3]]:
		for k in int(st[1]):
			g.fit("cardboard_box_01", (st[0] as Vector3) + Vector3(0.05 * k, 0.7 * k, 0), k * 17.0, 0.7)
		g.solid((st[0] as Vector3) + Vector3(0, 0.35 * int(st[1]), 0), Vector3(0.9, 0.7 * int(st[1]), 0.9))
	g.prop("plastic_crate_01", Vector3(6.4, 0, 9.5), 15.0, 1.2)
	g.prop("plastic_crate_01", Vector3(10.0, 0, 0.5), -25.0, 1.2)
	g.prop("hand_truck", Vector3(6.2, 0, 3.0), 60.0)
	g.prop("WetFloorSign_01", Vector3(9.6, 0, 6.2), 30.0)
	g.fit("rubber_duck_toy", Vector3(6.8, 0.0, 9.0), 40.0, 0.35)
	g.fit("rubber_duck_toy", Vector3(7.2, 0.0, 9.3), 160.0, 0.35)
	g.fit("rubber_duck_toy", Vector3(12.2, 0.0, 6.9), 280.0, 0.35)

static func _hall(g) -> void:
	var brick: StandardMaterial3D = g.mat("factory_brick", 0.35, Color(0.85, 0.75, 0.68))
	g.box(Vector3(50.0, 14.0, 0.8), Vector3(8.0, 7.0, -8.0), brick)
	g.box(Vector3(0.8, 14.0, 26.0), Vector3(-8.0, 7.0, 4.5), brick)
	g.box(Vector3(0.8, 14.0, 26.0), Vector3(24.0, 7.0, 4.5), brick)
	g.box(Vector3(50.0, 0.4, 24.0), Vector3(8.0, 13.2, 3.0), g.mat("corrugated_iron", 0.5, Color(0.35, 0.33, 0.3)))
	var beam: StandardMaterial3D = g.dull("rusty_metal_02", 1.0, Color(0.9, 0.5, 0.3))
	for bx in [-4.0, 2.0, 8.0, 14.0, 20.0]:
		g.box(Vector3(0.3, 0.6, 24.0), Vector3(bx, 12.7, 3.0), beam)
	g.box(Vector3(50.0, 1.4, 0.9), Vector3(8.0, 0.7, -7.7), g.mat("grey_plaster_03", 0.5, Color(0.9, 0.75, 0.2)))
	g.sign3d("WONDERTOY Co.", Vector3(8.0, 10.0, -7.55), Color(1.0, 0.45, 0.3), 220)
	g.sign3d("FUN IS MANDATORY", Vector3(8.0, 7.9, -7.55), Color(1.0, 0.9, 0.5), 90)
	var cols := [Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.3, 0.85, 0.4)]
	for i in 6:
		var px := -5.0 + i * 5.0
		g.box(Vector3(2.0, 2.8, 0.06), Vector3(px if i != 2 else px + 1.5, 4.6, -7.55), g.mat("grey_plaster_03", 0.7, cols[i % 4]))
	var glass: StandardMaterial3D = g.glow(Color(0.55, 0.65, 0.8), 0.9)
	for wx in [-6.0, 0.0, 16.0, 22.0]:
		g.box(Vector3(3.0, 2.0, 0.1), Vector3(wx, 9.8, -7.55), glass)
	_belt(g, Vector3(8.0, 0.0, -4.6), 26.0)
	for i in 9:
		g.fit("cardboard_box_01", Vector3(-4.0 + i * 3.0, 0.95, -4.6), i * 23.0, 0.55)
		g.fit("rubber_duck_toy", Vector3(-2.6 + i * 3.0, 0.95, -4.6), i * 40.0, 0.4)
	for sx in [-6.6, 22.6]:
		for sz in [-2.0, 2.0, 6.0]:
			g.prop("steel_frame_shelves_02", Vector3(sx, 0, sz), 90.0 if sx < 0 else -90.0, 1.3)
	for p in [Vector3(-4.0, 0, 11.0), Vector3(20.5, 0, 11.5), Vector3(-5.0, 0, -6.0), Vector3(21.0, 0, -6.0)]:
		g.prop("wooden_crate_01", p, p.x * 13.0, 1.2)
		g.prop("cardboard_box_01", p + Vector3(0.9, 0, 0.4), p.z * 31.0, 1.4)
	g.prop("tool_cart", Vector3(19.5, 0, 1.0), -70.0)
	g.prop("drill_press_01", Vector3(-4.5, 0, 3.0), 90.0)
	g.prop("portable_welding_cart", Vector3(-4.2, 0, 7.0), 80.0)
	for lx in [2.0, 8.0, 14.0]:
		for lz in [1.0, 7.0]:
			g.lamp(Vector3(lx, 7.5, lz), 10.0, Color(1.0, 0.86, 0.62))
	g.omni(Vector3(8.0, 8.0, -5.5), Color(1.0, 0.75, 0.5), 3.0, 14.0)

static func _toy_block(g, base: Vector3, yaw: float, col: Color, letter: String) -> void:
	var b: MeshInstance3D = g.box(Vector3(1.5, 1.5, 1.5), base + Vector3(0, 0.75, 0), g.mat("grey_plaster_03", 0.55, col), null, true)
	b.rotation_degrees.y = yaw
	for f in 4:
		var lb := Label3D.new()
		lb.text = letter
		lb.font_size = 110
		lb.pixel_size = 0.01
		lb.outline_size = 16
		lb.modulate = col.lightened(0.6)
		lb.outline_modulate = col.darkened(0.6)
		b.add_child(lb)
		lb.rotation_degrees.y = f * 90.0
		lb.position = Vector3(0, 0, 0.77).rotated(Vector3.UP, deg_to_rad(f * 90.0))

static func _belt(g, c: Vector3, length: float) -> void:
	g.box(Vector3(length, 0.12, 1.0), c + Vector3(0, 0.88, 0), g.mat("rubber_tiles", 0.8, Color(0.4, 0.4, 0.4)))
	var frame: StandardMaterial3D = g.dull("rusty_metal_02", 1.2, Color(0.9, 0.65, 0.3))
	g.box(Vector3(length, 0.2, 0.08), c + Vector3(0, 0.84, 0.54), frame)
	g.box(Vector3(length, 0.2, 0.08), c + Vector3(0, 0.84, -0.54), frame)
	var n := int(length / 1.6)
	for i in n + 1:
		var lx := -length * 0.5 + i * (length / float(n))
		for z in [-0.5, 0.5]:
			g.box(Vector3(0.1, 0.84, 0.1), c + Vector3(lx, 0.42, z), frame)

static func _conveyor(g, c: Vector3, length: float) -> void:
	_belt(g, c, length)
	g.solid(c + Vector3(0, 0.6, 0), Vector3(length, 1.2, 1.1))
	for i in 4:
		g.fit("cardboard_box_01", c + Vector3(-1.5 + i * 1.0, 0.94, 0.0), i * 33.0, 0.5)
	g.fit("rubber_duck_toy", c + Vector3(1.9, 0.94, 0.1), 90.0, 0.45)
