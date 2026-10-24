extends ArenaMinigame3D
## Inside Job: a dark, run-down office floor. One random subject starts infected,
## holding a giant syringe. Infected stab clean subjects (SPACE) to turn them; the
## turned convulse, go sick green, shamble faster and join the hunt. Patient zero
## must infect someone within 20 s or overdoses. Everyone only sees a small circle
## around themselves (the infected see further). 45 s or until nobody is clean.
## Clean survivors rank first, then the infected in reverse order of infection;
## patient zero climbs one place per subject they infected.

const TIME_LIMIT: float = 45.0
const OVERDOSE_T: float = 20.0
const START_DELAY: float = 1.6
const BASE_SPEED: float = 4.6
const INF_SPEED: float = 4.6 * 1.15
const STAB_R: float = 1.35
const STAB_CD: float = 0.75
const STUN_T: float = 1.0
const SEE_CLEAN: float = 3.4
const SEE_INF: float = 5.6
const BOT_SIGHT_CLEAN: float = 9.0
const BOT_SIGHT_INF: float = 8.0
const CELL: float = 0.5
const GW: int = 32
const GH: int = 20
const SICK: Color = Color(0.4, 0.52, 0.2)

const FOG_SHADER := """
shader_type canvas_item;
uniform vec2 center = vec2(0.5);
uniform vec2 radius = vec2(0.2);
uniform float darkness = 0.9;
uniform float on = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
void fragment() {
	vec2 d = (SCREEN_UV - center) / radius;
	float r = length(d);
	float wob = sin(atan(d.y, d.x) * 7.0 + TIME * 1.7) * 0.03 + (hash(floor(SCREEN_UV * 180.0) + floor(TIME * 12.0)) - 0.5) * 0.06;
	float a = smoothstep(0.62, 1.12, r + wob) * darkness;
	COLOR = vec4(0.0, 0.006, 0.004, a * on);
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

static var _zombie_lib: AnimationLibrary
static var _aim_pose: Dictionary = {}

var infected: Array = []
var zero_id: int = -1
var infected_by: Dictionary = {}
var overdosed: bool = false
var stun: Dictionary = {}
var stab_cd: Dictionary = {}
var bots: Dictionary = {}
var syringes: Dictionary = {}
var blocked := PackedByteArray()
var walls: Array[Rect2] = []
var lights_flicker: Array = []
var _clock: float = 0.0
var _running: bool = false
var _done: bool = false
var _space_down: bool = false
var _fog_mat: ShaderMaterial
var _fog_r: float = SEE_CLEAN
var _halo: OmniLight3D
var _cam_t: Vector3 = Vector3(W * 0.5, 0.0, D * 0.5 - 1.4)
var _cam_o: Vector3 = Vector3(0.0, 10.6, 9.6)
var _hud_time: Label
var _hud_status: Label
var _hud_board: Label
var _hud_help: Label
var _hud_big: Label

func begin() -> void:
	setup_arena(false)
	_tune_light()
	blocked.resize(GW * GH)
	_build_office()
	camera.fov = 42.0
	camera.position = Vector3(W * 0.5, 10.6, D + 4.2)
	camera.look_at(Vector3(W * 0.5, 0.0, D * 0.5 - 1.4), Vector3.UP)
	spawn_players(_spawns())
	for id in players:
		infected_by[id] = 0
		stun[id] = 0.0
		stab_cd[id] = 0.0
		bots[id] = {"t": randf_range(0.0, 0.3), "path": [], "goal": Vector3.INF, "react": randf_range(0.3, 0.55), "seen": {}, "sniff": Vector3.INF, "sniff_t": 0.0}
		players[id].speed = BASE_SPEED
		players[id].bot_brain = _bot_brain.bind(id)
	_build_fog()
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.16
			n.light_color = Color(0.7, 0.8, 0.9)
			n.shadow_enabled = false
	env.ambient_light_energy = 0.38
	env.ambient_light_color = Color(0.55, 0.62, 0.56)
	env.tonemap_exposure = 1.05
	env.fog_density = 0.02
	env.fog_light_color = Color(0.16, 0.18, 0.15)
	env.adjustment_saturation = 0.7

func _spawns() -> Array:
	var pts: Array = [Vector3(8.0, 0, 5.4), Vector3(1.0, 0, 0.9), Vector3(15.0, 0, 0.9), Vector3(1.0, 0, 9.2),
		Vector3(15.0, 0, 9.2), Vector3(8.0, 0, 9.3), Vector3(4.4, 0, 5.4), Vector3(11.6, 0, 5.4)]
	var a: Array = []
	for i in NetworkManager.players.size():
		a.append(pts[i % pts.size()])
	return a

func _solid(r: Rect2, h: float, opaque: bool, visual: Material = null, parent: Node = null) -> void:
	var c := Vector3(r.get_center().x, h * 0.5, r.get_center().y)
	var size := Vector3(r.size.x, h, r.size.y)
	if visual:
		box(size, c, visual, parent, true)
	else:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		(parent if parent else world).add_child(sb)
		sb.position = c
	var g := r.grow(0.22)
	for i in GW * GH:
		var p := _center(i)
		if g.has_point(Vector2(p.x, p.z)):
			blocked[i] = 1
	if opaque:
		walls.append(r)

func _partition(a: Vector2, b: Vector2, parent: Node, fabric: Material, trim: Material, h: float = 1.4) -> void:
	var r := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(b.x - a.x), absf(b.y - a.y))).grow(0.04)
	_solid(r, h, true, fabric, parent)
	box(Vector3(r.size.x + 0.02, 0.05, r.size.y + 0.02), Vector3(r.get_center().x, h + 0.02, r.get_center().y), trim, parent)

func _build_office() -> void:
	var off := Node3D.new()
	off.name = "Office"
	world.add_child(off)
	var wall := mat("concrete_wall_008", 0.4, Color(0.62, 0.63, 0.58))
	var paper := mat("decrepit_wallpaper", 0.5, Color(0.62, 0.62, 0.5))
	var fabric := mat("dirty_carpet", 1.1, Color(0.42, 0.47, 0.5))
	var trim := mat("rusty_metal_02", 1.5, Color(0.55, 0.55, 0.52))
	box(Vector3(W + 6.0, 0.2, D + 6.0), Vector3(W * 0.5, -0.1, D * 0.5 + 1.0), mat("dirty_carpet", 0.32, Color(0.62, 0.6, 0.52)), off)
	box(Vector3(W + 1.2, 0.02, 3.6), Vector3(W * 0.5, 0.005, D - 0.9), mat("old_linoleum_flooring_01", 0.45, Color(0.7, 0.68, 0.6)), off)
	box(Vector3(W + 2.0, 4.6, 0.4), Vector3(W * 0.5, 2.3, -0.8), wall, off)
	box(Vector3(0.4, 4.6, D + 5.0), Vector3(-0.8, 2.3, D * 0.5 + 1.5), wall, off)
	box(Vector3(0.4, 4.6, D + 5.0), Vector3(W + 0.8, 2.3, D * 0.5 + 1.5), wall, off)
	box(Vector3(W + 1.4, 1.1, 0.06), Vector3(W * 0.5, 0.55, -0.58), paper, off)
	box(Vector3(0.06, 1.1, D + 5.0), Vector3(-0.58, 0.55, D * 0.5 + 1.5), paper, off)
	box(Vector3(0.06, 1.1, D + 5.0), Vector3(W + 0.58, 0.55, D * 0.5 + 1.5), paper, off)
	box(Vector3(W + 1.4, 0.06, 0.05), Vector3(W * 0.5, 1.12, -0.56), trim, off)
	box(Vector3(0.05, 0.06, D + 5.0), Vector3(-0.56, 1.12, D * 0.5 + 1.5), trim, off)
	box(Vector3(0.05, 0.06, D + 5.0), Vector3(W + 0.56, 1.12, D * 0.5 + 1.5), trim, off)
	box(Vector3(0.12, 2.3, 1.3), Vector3(-0.6, 1.15, 6.6), mat("black_painted_planks", 1.0, Color(0.1, 0.09, 0.08)), off)
	_hide_sign(off)
	_cubicles(Vector2(1.8, 1.4), off, fabric, trim)
	_cubicles(Vector2(9.0, 1.4), off, fabric, trim)
	_desk_island(Vector3(3.2, 0, 7.9), off, true)
	_desk_island(Vector3(12.8, 0, 7.9), off, true)
	_desk_island(Vector3(8.0, 0, 8.0), off, false)
	_partition(Vector2(6.9, 8.85), Vector2(9.1, 8.85), off, fabric, trim, 1.15)
	_wall_furniture(off)
	_lights(off)
	_papers(off)
	_stains(off)

func _cubicles(o: Vector2, parent: Node, fabric: Material, trim: Material) -> void:
	var w := 5.2
	var d := 3.2
	var mid := o.y + d * 0.5
	_partition(Vector2(o.x, mid), Vector2(o.x + w, mid), parent, fabric, trim)
	_partition(Vector2(o.x + w * 0.5, o.y), Vector2(o.x + w * 0.5, o.y + d), parent, fabric, trim)
	_partition(Vector2(o.x, o.y + 0.5), Vector2(o.x, o.y + d - 0.5), parent, fabric, trim)
	_partition(Vector2(o.x + w, o.y + 0.5), Vector2(o.x + w, o.y + d - 0.5), parent, fabric, trim)
	var items := ["Television_01", "classic_laptop", "Television_01", "office_notepads"]
	var k := 0
	for side in [-1.0, 1.0]:
		for half in [0, 1]:
			var cx: float = o.x + w * (0.27 if half == 0 else 0.73) + (0.18 if half == 0 else -0.18)
			var dz: float = mid + side * 0.48
			var desk := prop("metal_office_desk", Vector3(cx, 0, dz), 0.0 if side < 0.0 else 180.0, 0.8, parent)
			if desk:
				desk.scale = Vector3(0.82, 1.0, 0.8)
				_tint(desk, Color(0.42, 0.44, 0.4))
			_solid(Rect2(Vector2(cx - 0.82, dz - 0.4), Vector2(1.64, 0.8)), 0.79, false)
			var top: Vector3 = Vector3(cx + randf_range(-0.3, 0.3), 0.79, dz + side * 0.08)
			var it: String = items[(k + int(o.x)) % items.size()]
			prop(it, top, (180.0 if side < 0.0 else 0.0) + randf_range(-20.0, 20.0), 0.9 if it == "Television_01" else 1.0, parent)
			if it == "Television_01":
				var glow := OmniLight3D.new()
				glow.light_color = Color(0.45, 0.7, 1.0)
				glow.light_energy = 0.8
				glow.omni_range = 2.0
				parent.add_child(glow)
				glow.position = top + Vector3(0, 0.3, side * 0.45)
				lights_flicker.append({"l": glow, "base": 0.8, "t": 0.0, "kind": 2})
			prop("binder_notebook", Vector3(cx - side * 0.55, 0.795, dz), randf() * 360.0, 1.0, parent)
			var ch := prop("GreenChair_01" if k % 2 == 0 else "SchoolChair_01", Vector3(cx + randf_range(-0.4, 0.4), 0, dz + side * 0.72), (0.0 if side < 0.0 else 180.0) + randf_range(-40.0, 40.0), 1.0, parent)
			if ch and k == 2:
				ch.rotation_degrees = Vector3(0.0, 30.0, 90.0)
				ch.position.y = 0.3
			k += 1
	prop("cardboard_box_01", Vector3(o.x + 0.45, 0, mid - 0.3), 20.0, 1.2, parent)
	prop("trashbag", Vector3(o.x + w - 0.4, 0, mid + 0.35), 0.0, 1.0, parent)

func _desk_island(c: Vector3, parent: Node, pair: bool) -> void:
	_tint(prop("metal_office_desk", c + Vector3(0, 0, -0.46 if pair else 0.0), 180.0, 1.0, parent), Color(0.42, 0.44, 0.4))
	if pair:
		_tint(prop("metal_office_desk", c + Vector3(0, 0, 0.46), 0.0, 1.0, parent), Color(0.42, 0.44, 0.4))
		_solid(Rect2(Vector2(c.x - 1.0, c.z - 0.95), Vector2(2.0, 1.9)), 0.79, false)
		prop("Television_01", c + Vector3(-0.5, 0.79, -0.5), 180.0, 1.0, parent)
		prop("classic_laptop", c + Vector3(0.45, 0.79, 0.45), 10.0, 1.0, parent)
		prop("desk_lamp_arm_01", c + Vector3(0.75, 0.79, -0.6), 200.0, 1.0, parent)
		prop("office_notepads", c + Vector3(-0.3, 0.79, 0.55), 15.0, 0.8, parent)
		prop("SchoolChair_01", c + Vector3(-0.4, 0, -1.25), 170.0, 1.0, parent)
		prop("GreenChair_01", c + Vector3(0.5, 0, 1.3), -20.0, 1.0, parent)
		var lp := SpotLight3D.new()
		lp.light_color = Color(1.0, 0.72, 0.4)
		lp.light_energy = 3.0
		lp.spot_range = 2.4
		lp.spot_angle = 50.0
		parent.add_child(lp)
		lp.position = c + Vector3(0.7, 1.55, -0.45)
		lp.rotation_degrees.x = -90.0
	else:
		_solid(Rect2(Vector2(c.x - 1.0, c.z - 0.48), Vector2(2.0, 0.96)), 0.79, false)
		prop("Television_01", c + Vector3(0.3, 0.79, 0.05), 160.0, 1.0, parent)
		prop("wall_clock", c + Vector3(-0.4, 0.8, -0.1), 0.0, 1.0, parent).rotation_degrees = Vector3(-90.0, 30.0, 0.0)
		prop("GreenChair_01", c + Vector3(0.2, 0, -0.85), 200.0, 1.0, parent)

func _tint(n: Node, c: Color) -> void:
	if n == null:
		return
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			if src is StandardMaterial3D:
				var d: StandardMaterial3D = src.duplicate()
				d.albedo_color = d.albedo_color * c
				m.set_surface_override_material(i, d)

func _wall_furniture(parent: Node) -> void:
	for x in [0.9, 2.1]:
		prop("drawer_cabinet", Vector3(x, 0, -0.32), 0.0, 1.0, parent)
	prop("vintage_cabinet_01", Vector3(14.2, 0, -0.25), 0.0, 1.0, parent)
	prop("drawer_cabinet", Vector3(15.6, 0, 3.0), -90.0, 1.0, parent)
	prop("drawer_cabinet", Vector3(15.6, 0, 4.2), -90.0, 1.0, parent)
	prop("drawer_cabinet", Vector3(0.4, 0, 3.6), 90.0, 1.0, parent)
	_solid(Rect2(Vector2(15.3, 2.4), Vector2(0.7, 2.4)), 1.9, true)
	_solid(Rect2(Vector2(0.0, 3.0), Vector2(0.7, 1.2)), 1.9, true)
	prop("potted_plant_02", Vector3(7.9, 0, -0.2), 0.0, 1.2, parent)
	prop("wall_clock", Vector3(11.0, 3.4, -0.58), 0.0, 1.4, parent)
	var deco := [["cardboard_box_01", 4.4, -0.25, 15.0, 1.3], ["cardboard_box_01", 4.9, -0.2, -10.0, 1.1], ["metal_trash_can", 10.2, -0.3, 0.0, 0.8],
		["WetFloorSign_01", 0.4, 5.6, 40.0, 1.3], ["trashbag", 15.5, 6.0, 0.0, 1.1], ["trashbag", 15.2, 9.6, 30.0, 1.2], ["cardboard_box_01", 0.4, 9.5, 70.0, 1.3],
		["cardboard_box_01", 0.45, 8.9, 10.0, 1.1], ["SchoolDesk_01", 15.5, 7.6, 90.0, 1.0], ["potted_plant_02", 0.4, 1.0, 40.0, 1.0],
		["cardboard_box_01", 6.0, D + 0.6, 30.0, 1.3], ["SchoolChair_01", 10.5, D + 0.7, 120.0, 1.0], ["trashbag", 2.2, D + 0.7, 0.0, 1.1], ["metal_trash_can", 14.0, D + 0.8, 90.0, 0.9]]
	for d in deco:
		prop(d[0], Vector3(d[1], 0.0, d[2]), d[3], d[4], parent)
	var tipped := prop("SchoolChair_01", Vector3(6.2, 0.28, 5.3), 0.0, 1.0, parent)
	if tipped:
		tipped.rotation_degrees = Vector3(80.0, 40.0, 0.0)
	_solid(Rect2(Vector2(15.25, 7.2), Vector2(0.75, 0.8)), 0.88, false)
	var board := box(Vector3(1.6, 1.0, 0.05), Vector3(12.1, 1.6, -0.56), mat("worn_planks", 1.4, Color(0.55, 0.4, 0.25)), parent)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var note := mat("grey_plaster_03", 2.0, Color(0.95, 0.92, 0.8))
	for i in 7:
		var n := box(Vector3(0.21, 0.28, 0.01), board.position + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.3, 0.3), 0.035), note, parent)
		n.rotation.z = rng.randf_range(-0.25, 0.25)

func _hide_sign(parent: Node) -> void:
	var u := 30
	var iw := 18 * u
	var ih := 12 * u
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	var rects: Array = [[0, 0, 1, 6], [3, 0, 1, 6], [0, 2.5, 4, 1], [5.2, 0, 1, 6],
		[7.4, 0, 1, 6], [7.4, 0, 3, 1], [7.4, 5, 3, 1], [10.4, 0.7, 1, 4.6], [9.9, 0.3, 0.9, 0.9], [9.9, 4.8, 0.9, 0.9],
		[12.6, 0, 1, 6], [12.6, 0, 4, 1], [12.6, 2.5, 3.2, 1], [12.6, 5, 4, 1]]
	var noise := FastNoiseLite.new()
	noise.frequency = 0.035
	noise.seed = 21
	var ox := 0.5 * u
	var oy := 0.6 * u
	for r in rects:
		var x0 := int(ox + float(r[0]) * u)
		var y0 := int(oy + float(r[1]) * u)
		var x1 := int(ox + (float(r[0]) + float(r[2])) * u)
		var y1 := int(oy + (float(r[1]) + float(r[3])) * u)
		for y in range(y0, mini(y1, ih)):
			for x in range(x0, mini(x1, iw)):
				var n := noise.get_noise_2d(x, y) + noise.get_noise_2d(x * 4.0, y * 4.0) * 0.5
				if n > -0.5:
					img.set_pixel(x, y, Color(1, 1, 1, clampf(0.9 + n * 0.6, 0.55, 1.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 26:
		var r: Array = rects[rng.randi() % rects.size()]
		var x := int(ox + (float(r[0]) + rng.randf() * float(r[2])) * u)
		var y := int(oy + (float(r[1]) + float(r[3])) * u) - 2
		var len := rng.randi_range(u, u * 5)
		var wd := rng.randi_range(2, 5)
		for k in len:
			var yy := y + k
			if yy >= ih:
				break
			var fade := 1.0 - float(k) / float(len)
			for dx in wd:
				var xx := x + dx
				if xx < iw:
					var c := img.get_pixel(xx, yy)
					img.set_pixel(xx, yy, Color(1, 1, 1, maxf(c.a, 0.8 * fade)))
	img.generate_mipmaps()
	var dec := Decal.new()
	dec.texture_albedo = ImageTexture.create_from_image(img)
	dec.modulate = Color(0.035, 0.035, 0.03)
	dec.albedo_mix = 1.0
	dec.size = Vector3(6.0, 0.3, 4.0)
	dec.cull_mask = 1
	parent.add_child(dec)
	dec.position = Vector3(W * 0.5 - 0.1, 0.75, -0.6)
	dec.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var sp := SpotLight3D.new()
	sp.light_color = Color(0.95, 0.9, 0.75)
	sp.light_energy = 14.0
	sp.spot_range = 7.5
	sp.spot_angle = 58.0
	sp.spot_attenuation = 0.7
	sp.shadow_enabled = true
	parent.add_child(sp)
	sp.position = Vector3(W * 0.5 - 0.4, 0.25, 1.1)
	sp.look_at(Vector3(W * 0.5 - 0.2, 2.2, -0.6), Vector3.UP)
	for x in [3.0, 13.0]:
		prop("industrial_caged_sconce", Vector3(x, 3.3, -0.55), 0.0, 1.5, parent)
		var wl := OmniLight3D.new()
		wl.light_color = Color(1.0, 0.8, 0.55)
		wl.light_energy = 2.2
		wl.omni_range = 4.5
		parent.add_child(wl)
		wl.position = Vector3(x, 3.1, -0.2)

func _lights(parent: Node) -> void:
	var spots := [Vector3(4.4, 3.4, 3.0), Vector3(11.6, 3.4, 3.0), Vector3(3.6, 3.4, 7.8), Vector3(12.4, 3.4, 7.8), Vector3(8.0, 3.6, 0.9)]
	var tube := StandardMaterial3D.new()
	tube.albedo_color = Color(0.9, 1.0, 0.92)
	tube.emission_enabled = true
	tube.emission = Color(0.8, 1.0, 0.85)
	tube.emission_energy_multiplier = 2.2
	for i in spots.size():
		var p: Vector3 = spots[i]
		var fx := prop("mounted_fluorescent_lights", p, 90.0, 1.0, parent)
		var tm: StandardMaterial3D = tube.duplicate() if i == 4 or i == 1 else tube
		var tb := box(Vector3(0.08, 0.04, 0.85), p + Vector3(0, -0.05, 0), tm, parent)
		tb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in [-0.3, 0.3]:
			var wire := box(Vector3(0.012, 3.0, 0.012), p + Vector3(0, 1.5, s), mat("rusty_metal_02", 1.0), parent)
			wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if fx:
			fx.position.y = p.y
		var sp := SpotLight3D.new()
		sp.light_color = Color(0.82, 0.96, 0.86)
		sp.light_energy = 5.5 if i != 4 else 4.0
		sp.spot_range = 6.0
		sp.spot_angle = 64.0
		sp.spot_attenuation = 0.85
		sp.shadow_enabled = i < 4
		parent.add_child(sp)
		sp.position = p + Vector3(0, -0.15, 0)
		sp.rotation_degrees.x = -90.0
		if i == 4 or i == 1:
			lights_flicker.append({"l": sp, "base": sp.light_energy, "t": 0.0, "kind": 0 if i == 4 else 1, "m": tm})

func _papers(parent: Node) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.21, 0.004, 0.3)
	bm.material = mat("grey_plaster_03", 2.5, Color(0.9, 0.88, 0.78))
	mm.mesh = bm
	mm.instance_count = 90
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for i in 90:
		var p := Vector3(rng.randf_range(-0.4, W + 0.4), 0.012 + float(i % 3) * 0.003, rng.randf_range(-0.3, D + 1.4))
		if i < 30:
			p = Vector3(rng.randf_range(6.6, 9.4), p.y, rng.randf_range(4.6, 6.4))
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08))
		mm.set_instance_transform(i, Transform3D(b, p))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _stains(parent: Node) -> void:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.045
	noise.seed = 13
	for y in n:
		for x in n:
			var dx := (x - n * 0.5) / (n * 0.5)
			var dy := (y - n * 0.5) / (n * 0.5)
			var v := 1.0 - sqrt(dx * dx + dy * dy) + noise.get_noise_2d(x, y) * 0.7
			var ring := 1.0 - absf(v - 0.3) * 6.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(maxf((v - 0.25) * 1.6, ring * 0.9), 0.0, 0.9)))
	var tex := ImageTexture.create_from_image(img)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 18:
		var d := Decal.new()
		d.texture_albedo = tex
		var sz := rng.randf_range(1.0, 3.4)
		d.size = Vector3(sz, 1.0, sz * rng.randf_range(0.55, 1.0))
		d.modulate = Color(0.2, 0.15, 0.08) if i % 3 != 0 else Color(0.1, 0.11, 0.07)
		d.rotation.y = rng.randf() * TAU
		parent.add_child(d)
		d.position = Vector3(rng.randf_range(-0.4, W + 0.4), 0.1, rng.randf_range(-0.4, D + 1.4))
	for i in 7:
		var d := Decal.new()
		d.texture_albedo = tex
		d.size = Vector3(rng.randf_range(0.8, 2.0), 0.6, rng.randf_range(1.5, 3.5))
		d.modulate = Color(0.25, 0.2, 0.1)
		parent.add_child(d)
		d.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		d.position = Vector3(rng.randf_range(0.0, W), rng.randf_range(2.6, 4.0), -0.55)

func _build_fog() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -2
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FOG_SHADER
	_fog_mat.shader = sh
	rect.material = _fog_mat
	layer.add_child(rect)
	_halo = OmniLight3D.new()
	_halo.light_color = Color(1.0, 0.86, 0.66)
	_halo.light_energy = 1.3
	_halo.omni_range = 4.0
	_halo.omni_attenuation = 1.6
	world.add_child(_halo)

func _build_hud() -> void:
	hud_title("INSIDE JOB  ·  don't get stuck")
	_hud_help = Label.new()
	_hud_help.text = "WASD move  ·  hide in the dark  ·  infected: SPACE stab"
	_hud_help.position = Vector2(16, 42)
	_style(_hud_help, 16, Color("e8e2c8"))
	hud.add_child(_hud_help)
	_hud_time = Label.new()
	_hud_time.position = Vector2(560, 10)
	_style(_hud_time, 26, Color("b8f5c4"))
	hud.add_child(_hud_time)
	_hud_board = Label.new()
	_hud_board.position = Vector2(930, 12)
	_style(_hud_board, 16, Color("e8e2c8"))
	hud.add_child(_hud_board)
	_hud_status = Label.new()
	_hud_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hud_status.position = Vector2(-300, -64)
	_hud_status.size = Vector2(600, 30)
	_hud_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_hud_status, 20, Color("e8e2c8"))
	hud.add_child(_hud_status)
	_hud_big = Label.new()
	_hud_big.set_anchors_preset(Control.PRESET_CENTER)
	_hud_big.position = Vector2(-400, -120)
	_hud_big.size = Vector2(800, 60)
	_hud_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_hud_big, 34, Color("9dff6a"))
	hud.add_child(_hud_big)
	_refresh_hud()

func _style(l: Label, size: int, c: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)

func _clean_ids() -> Array:
	return alive_ids().filter(func(id): return not infected.has(id))

func _inf_alive() -> Array:
	return alive_ids().filter(func(id): return infected.has(id))

func _refresh_hud() -> void:
	var me := multiplayer.get_unique_id()
	var lp := local_player()
	if lp == null:
		_hud_status.text = ""
	elif not lp.alive:
		_hud_status.text = "OVERDOSED"
		_hud_status.add_theme_color_override("font_color", Color("ff6a5a"))
	elif infected.has(me):
		var t := "INFECTED  ·  SPACE to stab the clean"
		if me == zero_id and infected_by.get(me, 0) == 0 and not overdosed:
			t = "PATIENT ZERO  ·  stab someone before you overdose"
		_hud_status.text = t
		_hud_status.add_theme_color_override("font_color", Color("9dff6a"))
	else:
		_hud_status.text = "CLEAN  ·  stay away from the syringe"
		_hud_status.add_theme_color_override("font_color", Color("e8e2c8"))
	_hud_board.text = "CLEAN     %d\nINFECTED  %d" % [_clean_ids().size(), _inf_alive().size()]

func _process(delta: float) -> void:
	_clock += delta
	if _hud_time:
		var left := clampf(TIME_LIMIT - (_clock - START_DELAY), 0.0, TIME_LIMIT)
		_hud_time.text = "%d" % ceili(left)
		_hud_help.modulate.a = clampf(9.0 - _clock, 0.0, 1.0)
		_hud_big.modulate.a = clampf(4.5 - _clock, 0.0, 1.0) if _clock < 6.0 else _hud_big.modulate.a
		var me := multiplayer.get_unique_id()
		if me == zero_id and infected.has(me) and infected_by.get(me, 0) == 0 and not overdosed and _clock > START_DELAY:
			var od := OVERDOSE_T - (_clock - START_DELAY)
			_hud_big.text = "OVERDOSE IN %d" % ceili(maxf(od, 0.0))
			_hud_big.modulate.a = 1.0 if od < 8.0 else _hud_big.modulate.a
	_flicker(delta)
	_update_cam(delta)
	_update_fog(delta)
	for id in syringes:
		var s: Dictionary = syringes[id]
		var m: ArmPose = s.mod
		m.active = _clock > float(s.get("hold", 0.0))
	var lp := local_player()
	if lp and lp.alive and _clock > START_DELAY:
		var down := Input.is_physical_key_pressed(KEY_SPACE)
		if down != _space_down:
			_space_down = down
			if down and infected.has(lp.peer_id):
				if multiplayer.is_server():
					_req_stab()
				else:
					_req_stab.rpc_id(1)

func _flicker(delta: float) -> void:
	for f in lights_flicker:
		var l: Light3D = f.l
		f.t -= delta
		if f.t > 0.0:
			continue
		var on := true
		match int(f.kind):
			0:
				on = randf() > 0.45
				f.t = randf_range(0.03, 0.12) if randf() < 0.7 else randf_range(0.5, 1.6)
			1:
				on = randf() > 0.12
				f.t = randf_range(0.05, 0.1) if not on else randf_range(1.0, 3.0)
			_:
				l.light_energy = float(f.base) * randf_range(0.6, 1.1)
				f.t = randf_range(0.04, 0.1)
				continue
		l.light_energy = float(f.base) * (1.0 if on else 0.04)
		if f.has("m"):
			var m: StandardMaterial3D = f.m
			m.emission_energy_multiplier = 2.2 if on else 0.05
		if on and f.kind == 0 and randf() < 0.2:
			Fx.sfx("hum", l.global_position, -22.0, 1.6)

func _update_cam(delta: float) -> void:
	var lp := local_player()
	var tgt := Vector3(W * 0.5, 0.0, D * 0.5 - 1.4)
	var off := Vector3(0.0, 10.6, 9.6)
	if lp and lp.alive:
		tgt = Vector3(lerpf(W * 0.5, lp.position.x, 0.5), 0.0, lerpf(D * 0.5 - 1.0, lp.position.z, 0.62) - 1.2)
		off = Vector3(0.0, 7.4, 8.8)
	_cam_t = _cam_t.lerp(tgt, 1.0 - exp(-3.0 * delta))
	_cam_o = _cam_o.lerp(off, 1.0 - exp(-2.0 * delta))
	camera.position = _cam_t + _cam_o
	camera.look_at(_cam_t + Vector3(0.0, 1.1, 0.0), Vector3.UP)

func _update_fog(delta: float) -> void:
	var lp := local_player()
	if lp == null or not lp.alive:
		_fog_mat.set_shader_parameter("on", 0.0)
		_halo.visible = false
		for id in players:
			players[id]._label.visible = true
		return
	var want := SEE_INF if infected.has(lp.peer_id) else SEE_CLEAN
	_fog_r = lerpf(_fog_r, want, 1.0 - exp(-2.5 * delta))
	var c := lp.global_position + Vector3(0, 0.7, 0)
	var sc := camera.unproject_position(c)
	var rx := absf(camera.unproject_position(c + Vector3(_fog_r, 0, 0)).x - sc.x)
	var ry := (absf(camera.unproject_position(c + Vector3(0, 0, _fog_r)).y - sc.y) + absf(camera.unproject_position(c - Vector3(0, 0, _fog_r)).y - sc.y)) * 0.5
	var vs := get_viewport().get_visible_rect().size
	_fog_mat.set_shader_parameter("on", 1.0)
	_fog_mat.set_shader_parameter("center", sc / vs)
	_fog_mat.set_shader_parameter("radius", Vector2(rx, ry * 1.25) / vs)
	_halo.visible = true
	_halo.global_position = c + Vector3(0, 1.1, 0)
	_halo.omni_range = _fog_r * 1.3
	_halo.light_color = Color(0.7, 1.0, 0.6) if infected.has(lp.peer_id) else Color(1.0, 0.86, 0.66)
	for id in players:
		var p: LabPlayer3D = players[id]
		var near := p == lp or (p.position.distance_to(lp.position) < _fog_r * 1.05 and _los(lp.position, p.position))
		p._label.visible = near

func _run() -> void:
	var ids: Array = players.keys()
	if ids.is_empty():
		_finish()
		return
	zero_id = ids[randi() % ids.size()]
	stun[zero_id] = START_DELAY + 0.4
	_rpc_start.rpc(zero_id)
	await get_tree().create_timer(START_DELAY).timeout
	_running = true
	var t := 0.0
	while t < TIME_LIMIT and not _clean_ids().is_empty() and not _inf_alive().is_empty():
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		if t >= OVERDOSE_T and not overdosed and infected_by[zero_id] == 0 and players[zero_id].alive:
			overdosed = true
			_rpc_overdose.rpc(zero_id)
	_running = false
	await get_tree().create_timer(1.2).timeout
	_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit(_placement())

func _placement() -> Array:
	var out: Array = _clean_ids()
	var victims: Array = []
	for i in range(infected.size() - 1, -1, -1):
		if infected[i] != zero_id:
			victims.append(infected[i])
	if zero_id != -1 and players.has(zero_id):
		if players[zero_id].alive:
			victims.insert(clampi(victims.size() - int(infected_by.get(zero_id, 0)), 0, victims.size()), zero_id)
	out.append_array(victims)
	for id in players.keys():
		if not out.has(id):
			out.append(id)
	return out

func _physics_process(delta: float) -> void:
	for id in stun:
		stun[id] = maxf(stun[id] - delta, 0.0)
		stab_cd[id] = maxf(stab_cd[id] - delta, 0.0)
	if not NetworkManager.is_server() or not _running:
		return
	for id in _inf_alive():
		if not players[id].is_bot or stun[id] > 0.0 or stab_cd[id] > 0.0:
			continue
		var v := _stab_victim(id)
		if v != -1 and players[v].position.distance_to(players[id].position) < 1.0:
			bots[id].react -= delta
			if bots[id].react <= 0.0:
				bots[id].react = randf_range(0.18, 0.42)
				_do_stab(id)

@rpc("any_peer", "call_local", "reliable")
func _req_stab() -> void:
	if not multiplayer.is_server() or not _running:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	if not players.has(id) or not players[id].alive or not infected.has(id):
		return
	if stab_cd[id] > 0.0 or stun[id] > 0.0:
		return
	_do_stab(id)

func _stab_victim(id: int) -> int:
	var p: LabPlayer3D = players[id]
	var f := Vector3(sin(p._target_yaw), 0.0, cos(p._target_yaw))
	var best := -1
	var best_d := STAB_R
	for o in _clean_ids():
		var to: Vector3 = players[o].position - p.position
		to.y = 0.0
		var d := to.length()
		if d > best_d:
			continue
		if d > 0.8 and f.dot(to / maxf(d, 0.01)) < -0.1:
			continue
		best_d = d
		best = o
	return best

func _do_stab(id: int) -> void:
	stab_cd[id] = STAB_CD
	var v := _stab_victim(id)
	if v != -1:
		infected_by[id] = int(infected_by[id]) + 1
		stun[v] = STUN_T
		stab_cd[v] = STUN_T + 0.3
		bots[v].path = []
	var order: Array = infected.duplicate()
	if v != -1:
		order.append(v)
	_rpc_stab.rpc(id, v, order, infected_by[id])

@rpc("authority", "call_local", "reliable")
func _rpc_start(zid: int) -> void:
	zero_id = zid
	infected = [zid]
	stun[zid] = START_DELAY + 0.4
	var z: LabPlayer3D = players[zid]
	_hud_big.text = "PATIENT ZERO: %s" % z.display_name
	_turn(zid, 2.1)
	Fx.sfx("buzzer", null, -6.0)
	_refresh_hud()

@rpc("authority", "call_local", "reliable")
func _rpc_stab(id: int, victim: int, order: Array, count: int) -> void:
	var p: LabPlayer3D = players[id]
	infected_by[id] = count
	if syringes.has(id):
		syringes[id].hold = _clock + 0.5
	p.body.play_action("Melee_Hook", 0.06, 1.2)
	Fx.sfx("whoosh", p.position, -3.0, 0.8)
	if victim == -1:
		return
	infected = order
	var v: LabPlayer3D = players[victim]
	if is_instance_valid(v):
		var dir := v.position - p.position
		dir.y = 0.0
		p.face(dir)
		v.face(-dir)
		v.body.play_action("Hit_Chest", 0.05, 0.7)
		Fx.sfx("hit", v.position, 0.0, 0.7)
		Fx.sfx("splat", v.position, -6.0, 1.4)
		Fx._burst(world, v.position + Vector3(0, 1.2, 0), Color(0.45, 0.9, 0.2), 40, 3.5, 0.035, 0.9, 9.0)
		Fx.shake(0.25)
		if v.is_local_human():
			v.input_enabled = false
		get_tree().create_timer(0.36).timeout.connect(_convulse.bind(victim))
		get_tree().create_timer(STUN_T).timeout.connect(_turn.bind(victim, 1.55))
	_refresh_hud()

func _convulse(id: int) -> void:
	var v: LabPlayer3D = players[id]
	if is_instance_valid(v) and v.alive:
		v.body.play_action("Hit_Chest", 0.04, 0.9)
		Fx.sfx("hit", v.position, -6.0, 0.6)

func _turn(id: int, syringe_scale: float) -> void:
	var p: LabPlayer3D = players[id]
	if not is_instance_valid(p) or not p.alive:
		return
	var c := p.color
	var g := c.get_luminance()
	var sick := SICK.lerp(Color(g, g, g), 0.22)
	p.body.set_suit_color(sick)
	p._label.modulate = Color("9dff6a")
	p.speed = INF_SPEED
	_zombify(p.body)
	_attach_syringe(id, syringe_scale)
	if p.is_local_human():
		p.input_enabled = true
	Fx.sfx("arm", p.position, -6.0, 0.6)
	_refresh_hud()

func _zombify(b: LabCharacter) -> void:
	if _zombie_lib == null:
		var base := LabCharacter.shared_library()
		_zombie_lib = AnimationLibrary.new()
		for n in base.get_animation_list():
			_zombie_lib.add_animation(n, base.get_animation(n))
		for pair in [["Idle", "Zombie_Idle"], ["Walk", "Zombie_Walk_Fwd"], ["Jog_Fwd", "Zombie_Walk_Fwd"], ["Sprint", "Zombie_Walk_Fwd"]]:
			_zombie_lib.remove_animation(pair[0])
			_zombie_lib.add_animation(pair[0], base.get_animation(pair[1]).duplicate())
	b.anim.stop()
	b.anim.remove_animation_library("")
	b.anim.add_animation_library("", _zombie_lib)
	b.anim.speed_scale = 1.45
	b._action_busy = false
	b._locomotion = ""
	b.set_motion(0.0)

func _attach_syringe(id: int, s: float) -> void:
	if syringes.has(id):
		return
	var p: LabPlayer3D = players[id]
	var sk := p.body.skeleton
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	sk.add_child(att)
	var syr: Node3D = load("res://assets/env/essentials/Prop_Syringe.gltf").instantiate()
	att.add_child(syr)
	var hr := sk.get_bone_global_rest(sk.find_bone("hand_r"))
	var mid := sk.get_bone_global_rest(sk.find_bone("middle_01_r")).origin
	var idx := sk.get_bone_global_rest(sk.find_bone("index_01_r")).origin
	var pk := sk.get_bone_global_rest(sk.find_bone("pinky_01_r")).origin
	var inv := hr.basis.inverse()
	var y := -(inv * (mid - hr.origin)).normalized()
	var t := (inv * (idx - pk)).normalized()
	var x := (t - y * t.dot(y)).normalized()
	var palm := inv * ((mid - hr.origin) * 0.6)
	syr.transform = Transform3D(Basis(x, y, x.cross(y)).scaled(Vector3.ONE * s), palm - y * 0.4 * s)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 1.0, 0.3)
	glow.light_energy = 1.1
	glow.omni_range = 1.8
	syr.add_child(glow)
	glow.position = Vector3(0, 0.1, 0)
	var mod := ArmPose.new()
	sk.add_child(mod)
	mod.poses = _aim(sk)
	syringes[id] = {"att": att, "mod": mod, "hold": 0.0}

func _aim(sk: Skeleton3D) -> Dictionary:
	if not _aim_pose.is_empty():
		return _aim_pose
	var a := LabCharacter.shared_library().get_animation("OverhandThrow")
	for tr in a.get_track_count():
		if a.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(a.track_get_path(tr)).get_slice(":", 1)
		if bone.ends_with("_r") and (bone.begins_with("clavicle") or bone.begins_with("upperarm") or bone.begins_with("lowerarm") or bone.begins_with("hand")):
			var bi := sk.find_bone(bone)
			if bi >= 0:
				_aim_pose[bi] = a.rotation_track_interpolate(tr, 0.3)
	return _aim_pose

@rpc("authority", "call_local", "reliable")
func _rpc_overdose(id: int) -> void:
	overdosed = true
	var p: LabPlayer3D = players[id]
	Fx._burst(world, p.position + Vector3(0, 1.5, 0), Color(0.75, 0.95, 0.6), 50, 2.5, 0.03, 1.2, 6.0)
	eliminate(id, "Death01")
	if syringes.has(id):
		syringes[id].mod.active = false
		syringes[id].hold = 99999.0
	Fx.sfx("buzzer", null, -4.0)
	_hud_big.text = "%s OVERDOSED" % p.display_name
	_hud_big.modulate.a = 1.0
	_hud_big.create_tween().tween_property(_hud_big, "modulate:a", 0.0, 0.6).set_delay(2.5)
	_refresh_hud()

func _center(i: int) -> Vector3:
	return Vector3((float(i % GW) + 0.5) * CELL, 0.0, (float(i / GW) + 0.5) * CELL)

func _cell(p: Vector3) -> int:
	return clampi(int(p.z / CELL), 0, GH - 1) * GW + clampi(int(p.x / CELL), 0, GW - 1)

func _seg_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for ax in 2:
		var lo: float = r.position[ax]
		var hi: float = r.end[ax]
		if absf(d[ax]) < 0.00001:
			if a[ax] < lo or a[ax] > hi:
				return false
			continue
		var ta := (lo - a[ax]) / d[ax]
		var tb := (hi - a[ax]) / d[ax]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true

func _los(a: Vector3, b: Vector3) -> bool:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	for r in walls:
		if _seg_hits(a2, b2, r):
			return false
	return true

func _free(i: int) -> bool:
	return i >= 0 and i < GW * GH and blocked[i] == 0

func _bfs(sources: Array) -> Array:
	var dist := PackedInt32Array()
	dist.resize(GW * GH)
	dist.fill(-1)
	var par := PackedInt32Array()
	par.resize(GW * GH)
	par.fill(-1)
	var q: Array[int] = []
	for s in sources:
		var si: int = s
		if dist[si] == -1:
			dist[si] = 0
			q.append(si)
	var h := 0
	while h < q.size():
		var c: int = q[h]
		h += 1
		var cx := c % GW
		var cy := c / GW
		for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + o[0]
			var ny: int = cy + o[1]
			if nx < 0 or ny < 0 or nx >= GW or ny >= GH:
				continue
			var n := ny * GW + nx
			if dist[n] != -1 or blocked[n] == 1:
				continue
			dist[n] = dist[c] + 1
			par[n] = c
			q.append(n)
	return [dist, par]

func _nearest_free(i: int) -> int:
	if _free(i):
		return i
	var best := i
	var bd := INF
	var c := _center(i)
	for j in GW * GH:
		if blocked[j] == 0:
			var d := _center(j).distance_squared_to(c)
			if d < bd:
				bd = d
				best = j
	return best

func _path_to(from: Vector3, goal: Vector3) -> Array:
	var gi := _nearest_free(_cell(goal))
	var res := _bfs([gi])
	var dist: PackedInt32Array = res[0]
	var par: PackedInt32Array = res[1]
	var c := _nearest_free(_cell(from))
	var path: Array = []
	var guard := 0
	while c != -1 and c != gi and guard < 200:
		c = par[c]
		if c != -1:
			path.append(_center(c))
		guard += 1
	if dist[_nearest_free(_cell(from))] == -1:
		return [goal]
	path.append(goal)
	return path

func _follow(id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	var b: Dictionary = bots[id]
	var path: Array = b.path
	while path.size() > 1:
		var w: Vector3 = path[0]
		if Vector2(w.x - p.position.x, w.z - p.position.z).length() < 0.35:
			path.pop_front()
		else:
			break
	if path.size() > 1:
		var ahead: Vector3 = path[1]
		if _walk_clear(p.position, ahead):
			path.pop_front()
	if path.is_empty():
		return Vector3.ZERO
	var w2: Vector3 = path[0]
	var v := Vector3(w2.x - p.position.x, 0.0, w2.z - p.position.z)
	if v.length() < 0.12:
		return Vector3.ZERO
	return v.normalized()

func _walk_clear(a: Vector3, b: Vector3) -> bool:
	var n := int(a.distance_to(b) / 0.2) + 1
	for k in n + 1:
		var q := a.lerp(b, float(k) / float(n))
		if blocked[_cell(q)] == 1:
			return false
	return true

func _bot_brain(delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	if not _running or stun[id] > 0.0:
		return Vector3.ZERO
	var b: Dictionary = bots[id]
	b.t -= delta
	if infected.has(id):
		return _hunt(id, p, b)
	return _flee(id, p, b)

func _hunt(id: int, p: LabPlayer3D, b: Dictionary) -> Vector3:
	var best := -1
	var best_d := BOT_SIGHT_INF
	for o in _clean_ids():
		var d: float = players[o].position.distance_to(p.position)
		if d < best_d and _los(p.position, players[o].position):
			best_d = d
			best = o
	if best != -1 and best_d < 1.6:
		var to: Vector3 = players[best].position - p.position
		to.y = 0.0
		if _walk_clear(p.position, players[best].position):
			p.face(to)
			return to.normalized()
	if b.t <= 0.0:
		b.t = randf_range(0.45, 0.8)
		var goal := Vector3.INF
		if best != -1:
			goal = players[best].position
			b.sniff = goal
		elif b.sniff != Vector3.INF and b.sniff.distance_to(p.position) > 0.8:
			goal = b.sniff
		else:
			b.sniff_t -= 0.4
			if b.sniff_t <= 0.0:
				b.sniff_t = randf_range(1.2, 2.2)
				var near := -1
				var nd := INF
				for o in _clean_ids():
					var d: float = players[o].position.distance_to(p.position)
					if d < nd:
						nd = d
						near = o
				b.sniff = players[near].position if near != -1 else Vector3.INF
			goal = b.sniff
		if goal != Vector3.INF:
			b.path = _path_to(p.position, goal)
	return _follow(id)

func _flee(id: int, p: LabPlayer3D, b: Dictionary) -> Vector3:
	var threats: Array = []
	var seen: Dictionary = b.seen
	for o in _inf_alive():
		var op: Vector3 = players[o].position
		var d := op.distance_to(p.position)
		if d < 4.2 or (d < BOT_SIGHT_CLEAN and _los(p.position, op)):
			seen[o] = [op, _clock]
	for o in seen.keys():
		if _clock - float(seen[o][1]) > 2.5 or not infected.has(o) or not players[o].alive:
			seen.erase(o)
		else:
			threats.append(seen[o][0])
	var closest := INF
	var cpos := Vector3.ZERO
	for t in threats:
		var tv: Vector3 = t
		var d := tv.distance_to(p.position)
		if d < closest:
			closest = d
			cpos = tv
	if closest < 1.7:
		var away := (p.position - cpos)
		away.y = 0.0
		var bestv := Vector3.ZERO
		var bs := -INF
		for k in 12:
			var dv := away.normalized().rotated(Vector3.UP, (float(k) - 5.5) * 0.45)
			var probe := p.position + dv * 1.0
			if probe.x < 0.4 or probe.x > W - 0.4 or probe.z < 0.4 or probe.z > D - 0.4 or blocked[_cell(probe)] == 1:
				continue
			var s := dv.dot(away.normalized())
			if s > bs:
				bs = s
				bestv = dv
		if bestv != Vector3.ZERO:
			b.t = minf(b.t, 0.15)
			return bestv
	if b.t <= 0.0:
		b.t = randf_range(0.3, 0.5)
		if threats.is_empty():
			if b.goal == Vector3.INF or randf() < 0.05:
				b.goal = _hide_spot(p.position, [])
				b.path = _path_to(p.position, b.goal)
		else:
			var src: Array = []
			for t in threats:
				src.append(_nearest_free(_cell(t)))
			var danger: PackedInt32Array = _bfs(src)[0]
			var mine: PackedInt32Array = _bfs([_nearest_free(_cell(p.position))])[0]
			var best := -1
			var bs := -INF
			for i in range(0, GW * GH):
				if mine[i] < 0 or danger[i] < 0:
					continue
				if mine[i] > 0 and mine[i] * 1.0 >= danger[i] * 0.9:
					continue
				var c := _center(i)
				var s := float(danger[i]) - float(mine[i]) * 0.35 + _corner(i) * 0.5
				var hidden := true
				for t in threats:
					if _los(t, c):
						hidden = false
						break
				if hidden:
					s += 4.0
				if s > bs:
					bs = s
					best = i
			if best != -1:
				b.goal = _center(best)
				b.path = _path_to(p.position, b.goal)
	return _follow(id)

func _corner(i: int) -> float:
	var cx := i % GW
	var cy := i / GW
	var n := 0.0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var x: int = cx + dx
			var y: int = cy + dy
			if x < 0 or y < 0 or x >= GW or y >= GH or blocked[y * GW + x] == 1:
				n += 1.0
	return n

func _hide_spot(from: Vector3, _avoid: Array) -> Vector3:
	var mine: PackedInt32Array = _bfs([_nearest_free(_cell(from))])[0]
	var best := -1
	var bs := -INF
	for k in 60:
		var i := randi() % (GW * GH)
		if mine[i] < 0:
			continue
		var s := _corner(i) * 1.0 - float(mine[i]) * 0.12 + randf() * 2.0
		for o in _inf_alive():
			s += minf(players[o].position.distance_to(_center(i)), 8.0) * 0.4
		if s > bs:
			bs = s
			best = i
	return _center(best) if best != -1 else from
