extends RefCounted
## Duck Hunt map: Mall After Hours. A dead shopping-mall atrium at night;
## glowing shopfronts, a mezzanine, planters, kiosks and vending machines.

static func layout() -> Dictionary:
	return {
		"name": "MALL AFTER HOURS",
		"towers": [Vector3(3.0, 0.0, -2.2), Vector3(17.6, 0.0, 9.0)],
		"lifts": [Vector3(3.0, 0.0, 0.8), Vector3(15.2, 0.0, 8.0)],
		"fusebox": Vector3(9.6, 0.0, 4.2),
		"skin": {"leg": ["blue_metal_plate", Color(0.75, 0.78, 0.85)], "wall": ["grey_plaster_03", Color(0.55, 0.6, 0.75)], "floor": ["rubber_tiles", Color(0.5, 0.5, 0.55)], "roof": ["blue_metal_plate", Color(0.45, 0.5, 0.6)]},
	}

static func build(g) -> void:
	g.set_env({"bg": Color("030308"), "amb": Color(0.42, 0.44, 0.6), "amb_e": 0.55, "fog": Color(0.07, 0.07, 0.12), "fog_d": 0.022,
		"sat": 0.9, "exp": 1.25, "sun": Color(0.55, 0.6, 0.9), "sun_e": 0.12, "sun_rot": Vector3(-70.0, 20.0, 0.0)})
	g.box(Vector3(50.0, 0.2, 40.0), Vector3(8.0, -0.1, 4.0), g.mat("marble_tiles", 0.22, Color(0.7, 0.7, 0.72)))
	g.box(Vector3(12.0, 0.03, 7.0), Vector3(8.0, 0.0, 5.0), g.mat("dirty_tiles", 0.3, Color(0.6, 0.6, 0.62)))
	_shops(g)
	_planter(g, Vector3(6.4, 0.0, 2.2), 0.0)
	_planter(g, Vector3(12.4, 0.0, 6.6), 90.0)
	_planter(g, Vector3(2.0, 0.0, 7.2), 90.0)
	_kiosk(g, Vector3(12.8, 0.0, 2.4))
	_vending(g, Vector3(5.2, 0.0, 8.8), 0.0, Color(1.0, 0.25, 0.3))
	_vending(g, Vector3(6.3, 0.0, 8.8), 0.0, Color(0.25, 0.7, 1.0))
	_vending(g, Vector3(14.6, 0.0, 4.6), -90.0, Color(0.3, 1.0, 0.45))
	_directory(g, Vector3(9.6, 0.0, 8.6))
	g.block(Vector3(1.8, 1.4, 0.9), Vector3(3.6, 0.0, 4.0), g.mat("corrugated_iron", 0.8, Color(0.75, 0.6, 0.45)), 10.0)
	for k in 4:
		g.fit("cardboard_box_01", Vector3(3.0 + (k % 2) * 0.9, 1.4 if k < 2 else 0.0, 4.6 if k < 2 else 4.9), k * 37.0, 0.55)
	g.sign3d("DELIVERY", Vector3(3.62, 1.0, 4.47), Color(0.2, 0.15, 0.1), 40, 10.0)
	g.fit("plastic_monobloc_chair_01", Vector3(8.0, 0, 6.8), 200.0, 0.85)
	g.fit("plastic_monobloc_chair_01", Vector3(8.8, 0, 7.0), 150.0, 0.85)
	g.fit("plastic_monobloc_chair_01", Vector3(11.2, 0.0, 1.0), 60.0, 0.64, false, null, Vector3(85, 0, 0))
	g.prop("GreenChair_01", Vector3(1.0, 0, 3.2), 90.0)
	g.prop("WetFloorSign_01", Vector3(8.2, 0, 3.0), 20.0)
	g.prop("WetFloorSign_01", Vector3(13.6, 0, 8.6), 140.0)
	g.prop("metal_trash_can", Vector3(7.6, 0, 1.0), 0.0)
	g.prop("metal_trash_can", Vector3(1.0, 0, 9.4), 0.0)
	g.prop("trashbag", Vector3(1.6, 0, 9.6), 70.0)
	g.prop("Television_01", Vector3(10.8, 0, 6.2), -30.0, 1.0)

static func _shops(g) -> void:
	var wall: StandardMaterial3D = g.mat("grey_plaster_03", 0.4, Color(0.55, 0.55, 0.6))
	g.box(Vector3(52.0, 14.0, 0.8), Vector3(8.0, 7.0, -7.0), wall)
	g.box(Vector3(0.8, 14.0, 26.0), Vector3(-8.0, 7.0, 5.0), wall)
	g.box(Vector3(0.8, 14.0, 26.0), Vector3(24.0, 7.0, 5.0), wall)
	var shops := [["BURGER BARN", Color(1.0, 0.55, 0.15)], ["TOYZ", Color(1.0, 0.3, 0.7)], ["PET WORLD", Color(0.3, 1.0, 0.5)], ["SALE 90%", Color(1.0, 0.15, 0.1)], ["PHONE FIX", Color(0.3, 0.7, 1.0)], ["WIG PALACE", Color(0.85, 0.5, 1.0)], ["CINEMA", Color(1.0, 0.85, 0.3)]]
	var i := 0
	for row in [0.0, 5.4]:
		var sx := -12.0
		while sx < 29.0:
			var sh: Array = shops[(i * 3) % shops.size()]
			var col: Color = sh[1]
			var lit := (i % 4) != 3
			g.box(Vector3(4.6, 3.0, 0.1), Vector3(sx, row + 1.6, -6.55), g.glow(col.darkened(0.55), 1.2) if lit else g.mat("dirty_concrete", 0.6, Color(0.12, 0.12, 0.14)))
			g.box(Vector3(5.0, 0.12, 0.3), Vector3(sx, row + 3.15, -6.5), g.dull("blue_metal_plate", 0.8, Color(0.6, 0.6, 0.65)))
			var lb: Label3D = g.sign3d(sh[0], Vector3(sx, row + 3.75, -6.5), col if lit else col.darkened(0.7), 72)
			lb.outline_modulate = Color(0, 0, 0)
			if not lit:
				g.fit("rollershutter_door", Vector3(sx, row, -6.45), 0.0, 3.0)
			elif i % 3 == 0:
				g.omni(Vector3(sx, row + 1.6, -5.4), col, 1.6, 6.0)
			sx += 5.6
			i += 1
	var slab: StandardMaterial3D = g.mat("concrete_wall_006", 0.5, Color(0.6, 0.6, 0.62))
	g.box(Vector3(52.0, 0.5, 3.0), Vector3(8.0, 5.15, -5.5), slab)
	var rail: StandardMaterial3D = g.dull("blue_metal_plate", 1.2, Color(0.8, 0.82, 0.85))
	g.box(Vector3(52.0, 0.08, 0.08), Vector3(8.0, 6.4, -4.05), rail)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.8, 0.9, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	g.box(Vector3(52.0, 1.0, 0.04), Vector3(8.0, 5.9, -4.05), glass)
	var esc: MeshInstance3D = g.box(Vector3(1.6, 0.4, 8.0), Vector3(-4.5, 2.6, -1.5), g.dull("blue_metal_plate", 0.6, Color(0.7, 0.7, 0.75)))
	esc.rotation_degrees.x = 37.0
	var hand: MeshInstance3D = g.box(Vector3(1.8, 0.9, 0.08), Vector3(-4.5, 3.4, -1.5), rail)
	hand.rotation_degrees.x = 37.0
	g.sign3d("OPEN 24/7*", Vector3(8.0, 11.0, -6.5), Color(1.0, 0.95, 0.8), 150)
	g.sign3d("*closed", Vector3(12.6, 10.2, -6.5), Color(0.8, 0.8, 0.8), 50)
	var sky: StandardMaterial3D = g.glow(Color(0.12, 0.16, 0.3), 0.6)
	g.box(Vector3(40.0, 0.3, 22.0), Vector3(8.0, 14.0, 3.0), g.mat("corrugated_iron", 0.5, Color(0.25, 0.25, 0.3)))
	g.box(Vector3(14.0, 0.1, 8.0), Vector3(8.0, 13.8, 2.0), sky)
	var k := 0
	for lx in [0.0, 8.0, 16.0]:
		for lz in [0.5, 7.5]:
			g.fit("mounted_fluorescent_lights", Vector3(lx, 9.0, lz), 90.0, 0.08)
			var l: OmniLight3D = g.omni(Vector3(lx, 8.6, lz), Color(0.85, 0.92, 1.0), 4.0, 12.0, k < 3)
			if k == 4:
				g.flicker(l, 4.0, 77)
			k += 1
	for pp in [Vector3(-6.5, 0, 2.0), Vector3(-6.5, 0, 8.0), Vector3(22.5, 0, 2.0), Vector3(22.5, 0, -2.0)]:
		g.prop("potted_plant_02", pp, pp.z * 30.0, 1.4)
	for p in [Vector3(-5.5, 0, 11.0), Vector3(21.0, 0, 12.0)]:
		g.fit("CoffeeCart_01", p, 30.0, 1.6)

static func _planter(g, base: Vector3, yaw: float) -> void:
	g.block(Vector3(2.6, 1.1, 1.2), base, g.mat("concrete_wall_006", 0.5, Color(0.85, 0.8, 0.75)), yaw)
	g.box(Vector3(2.4, 0.05, 1.0), base + Vector3(0, 1.1, 0), g.mat("brown_mud_leaves_01", 0.8, Color(0.6, 0.5, 0.4)))
	var d := Vector3(0.8, 0, 0).rotated(Vector3.UP, deg_to_rad(yaw))
	g.prop("potted_plant_02", base + d + Vector3(0, 1.0, 0), yaw, 1.2)
	g.prop("shrub_02", base - d + Vector3(0, 1.05, 0), yaw * 2.0, 0.6)

static func _kiosk(g, base: Vector3) -> void:
	g.block(Vector3(2.0, 1.15, 1.0), base, g.dull("blue_metal_plate", 0.6, Color(0.9, 0.55, 0.35)), 0.0)
	g.box(Vector3(2.2, 0.06, 1.2), base + Vector3(0, 1.18, 0), g.mat("marble_tiles", 0.8, Color(0.85, 0.85, 0.85)))
	g.fit("CashRegister_01", base + Vector3(-0.4, 1.21, 0.0), 180.0, 0.32)
	g.fit("CoffeeCart_01", base + Vector3(0.0, 0.0, -1.3), 0.0, 1.5, true)
	g.sign3d("COFFEE", base + Vector3(0, 0.7, 0.52), Color(1.0, 0.85, 0.6), 50)

static func _vending(g, base: Vector3, yaw: float, col: Color) -> void:
	g.block(Vector3(1.0, 2.0, 0.8), base, g.dull("blue_metal_plate", 0.6, col.darkened(0.3)), yaw)
	var fwd := Vector3(0, 0, 0.41).rotated(Vector3.UP, deg_to_rad(yaw))
	var front: MeshInstance3D = g.box(Vector3(0.7, 1.3, 0.02), base + fwd + Vector3(0, 1.2, 0), g.glow(col, 0.9))
	front.rotation_degrees.y = yaw
	g.omni(base + fwd * 2.5 + Vector3(0, 1.2, 0), col, 0.8, 2.5)

static func _directory(g, base: Vector3) -> void:
	g.block(Vector3(1.4, 2.1, 0.3), base, g.dull("blue_metal_plate", 0.6, Color(0.4, 0.42, 0.48)), 0.0)
	g.box(Vector3(1.2, 1.4, 0.02), base + Vector3(0, 1.3, 0.16), g.glow(Color(0.7, 0.85, 1.0), 0.6))
	var lb: Label3D = g.sign3d("YOU ARE HERE\n(sadly)", base + Vector3(0, 1.35, 0.18), Color(0.1, 0.12, 0.2), 18)
	lb.outline_size = 0
