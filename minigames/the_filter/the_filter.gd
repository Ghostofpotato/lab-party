extends ArenaMinigame3D
## The Filter: junk tumbles out of the hopper onto the sort line. SPACE grabs the item
## in front of you, carry it to the matching bin (GLASS, METAL, ORGANIC, BIO-HAZARD)
## and SPACE drops it in. Right bin scores, wrong bin is a strike; three strikes and
## the floor chute under you opens into the incinerator. Whatever reaches the end of
## the belt burns, and so does anyone standing in the furnace mouth. Empty-handed
## SPACE shoves, and a shoved carrier drops their item. Best sorts minus strikes
## wins after 45 s; the dead place last.

const TIME_LIMIT: float = 45.0
const BRIEF_T: float = 2.6
const BELT_Z: float = 1.9
const BELT_TOP: float = 0.64
const BELT_X0: float = 0.3
const BELT_END: float = 14.25
const BELT_SPEED: float = 1.05
const ZONE_X: float = 14.45
const ZONE_Z: float = 3.75
const PICK_R: float = 1.45
const BIN_R: float = 1.35
const SHOVE_R: float = 1.45
const SHOVE_CD: float = 0.8
const KNOCK: float = 1.9
const MAX_STRIKES: int = 3
const CAT_NAMES: Array[String] = ["GLASS", "METAL", "ORGANIC", "BIO-HAZARD"]
const CAT_COLORS: Array[Color] = [Color("3fc4d6"), Color("f0b62c"), Color("74d23e"), Color("e5402c")]
const BIN_X: Array[float] = [3.0, 6.35, 9.65, 13.0]
const BIN_Z: float = 7.85
const DEPOSIT_Z: float = 6.75
const HELD_OFS: Vector3 = Vector3(0.0, 1.1, 0.42)
const VARIANTS: Array = [
	[["ph", "wine_bottles_01", 3, 0.68, 0.0], ["ph", "plastic_bottle_gallon", -1, 0.62, 0.0], ["ph", "bleach_bottle", -1, 0.65, 0.0], ["ph", "wine_bottles_01", 1, 0.68, 0.0]],
	[["ph", "can_rusted", -1, 0.52, 0.0], ["ph", "oil_tin", -1, 0.57, 0.0], ["ph", "metal_jerrycan", -1, 0.73, 0.0], ["ph", "long_life_food", 1, 0.49, 0.0]],
	[["ph", "food_apple_01", -1, 0.44, 0.0], ["ph", "hamburger_buns", -1, 0.65, 0.0], ["ph", "trashbag", -1, 0.68, 0.0]],
	[["ph", "medical_box", -1, 0.70, 0.0], ["ph", "old_gas_mask", -1, 0.60, 0.0], ["env", "Prop_Syringe", -1, 0.73, 90.0]],
]

const SHIMMER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	float m = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x) * smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.6, UV.y);
	vec2 o = vec2(sin(UV.y * 38.0 - TIME * 9.0) + sin(UV.y * 71.0 - TIME * 13.0) * 0.5, cos(UV.x * 31.0 + TIME * 7.0)) * 0.006 * m;
	ALBEDO = texture(scr, SCREEN_UV + o).rgb * (1.0 + 0.12 * m * vec3(1.0, 0.45, 0.1));
	ALPHA = m;
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

class Icon extends Control:
	var kind: int = 0
	func _draw() -> void:
		var c := Color.WHITE
		var w := 16.0
		match kind:
			0:
				var pts := PackedVector2Array([Vector2(112, 36), Vector2(144, 36), Vector2(144, 84), Vector2(170, 116), Vector2(170, 224), Vector2(86, 224), Vector2(86, 116), Vector2(112, 84), Vector2(112, 36)])
				draw_polyline(pts, c, w, true)
				draw_rect(Rect2(86, 146, 84, 40), c)
			1:
				draw_rect(Rect2(76, 70, 104, 150), c, false, w)
				draw_polyline(_ellipse(Vector2(128, 70), 52.0, 18.0), c, w, true)
				draw_line(Vector2(76, 120), Vector2(180, 120), c, 10.0)
				draw_line(Vector2(76, 170), Vector2(180, 170), c, 10.0)
			2:
				draw_arc(Vector2(108, 152), 52.0, 0.0, TAU, 48, c, w, true)
				draw_arc(Vector2(148, 152), 52.0, 0.0, TAU, 48, c, w, true)
				draw_line(Vector2(128, 104), Vector2(140, 58), c, 12.0)
				draw_colored_polygon(PackedVector2Array([Vector2(142, 72), Vector2(178, 48), Vector2(196, 62), Vector2(160, 84)]), c)
			3:
				var ctr := Vector2(128, 136)
				for i in 3:
					var a := -PI * 0.5 + TAU * float(i) / 3.0
					draw_arc(ctr + Vector2(cos(a), sin(a)) * 44.0, 40.0, 0.0, TAU, 40, c, w, true)
				draw_circle(ctr, 15.0, c)
				draw_arc(ctr, 74.0, 0.0, TAU, 56, c, 10.0, true)
			_:
				var ctr2 := Vector2(128, 140)
				var vs: Array[Vector2] = []
				for i in 3:
					var a2 := -PI * 0.5 + TAU * float(i) / 3.0
					vs.append(ctr2 + Vector2(cos(a2), sin(a2)) * 92.0)
				for i in 3:
					var a3: Vector2 = vs[i]
					var b3: Vector2 = vs[(i + 1) % 3]
					var s := a3.lerp(b3, 0.16)
					var e := a3.lerp(b3, 0.7)
					draw_line(s, e, c, 22.0)
					var d := (b3 - a3).normalized()
					var n := Vector2(-d.y, d.x)
					draw_colored_polygon(PackedVector2Array([e + d * 34.0, e + n * 28.0, e - n * 28.0]), c)
	func _ellipse(ctr: Vector2, rx: float, ry: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 41:
			var a := TAU * float(i) / 40.0
			pts.append(ctr + Vector2(cos(a) * rx, sin(a) * ry))
		return pts

static var _pose_cache: Dictionary = {}

var clock: float = 0.0
var running: bool = false
var _done: bool = false
var items: Dictionary = {}
var carry: Dictionary = {}
var score: Dictionary = {}
var strikes: Dictionary = {}
var act_cd: Dictionary = {}
var shove_cd: Dictionary = {}
var stun: Dictionary = {}
var anim_lock: Dictionary = {}
var dead_order: Array = []
var sorted_count: Array[int] = [0, 0, 0, 0]
var burned_count: int = 0
var _bot: Dictionary = {}
var _mods: Dictionary = {}
var _holders: Dictionary = {}
var _strike_tags: Dictionary = {}
var _templates: Array = []
var _icons: Array[ViewportTexture] = []
var _belt_mat: StandardMaterial3D
var _next_iid: int = 1
var _spawn_t: float = 0.0
var _space_down: bool = false
var _font: Font
var _soft: Texture2D
var _furnace_light: OmniLight3D
var _alarm_light: SpotLight3D
var _alarm_t: float = 0.0
var _bin_lights: Array[OmniLight3D] = []
var _push_tw: Dictionary = {}
var _ended_local: bool = false

var _scr_title: Label3D
var _scr_body: Label3D
var _scr_icon: Sprite3D
var _hud_time: Label
var _hud_board: Label
var _hud_status: Label
var _hud_help: Label
var _hud_brief: Control
var _hud_flash: ColorRect
var _big: Label

func begin() -> void:
	setup_arena(false)
	_font = load("res://assets/ui/VT323-Regular.ttf")
	build_chamber("concrete_floor_worn_001", "factory_brick", "rusty_metal")
	env.tonemap_exposure = 0.95
	env.ambient_light_energy = 0.48
	env.fog_density = 0.013
	env.fog_light_color = Color(0.32, 0.26, 0.2)
	camera.fov = 47.0
	camera.position = Vector3(W * 0.5, 9.0, 12.9)
	camera.look_at(Vector3(W * 0.5, 0.0, 3.6), Vector3.UP)
	_make_icons()
	_build_templates()
	_build_plant()
	spawn_players(_spawns())
	for id in players:
		var p: LabPlayer3D = players[id]
		p.bounds = AABB(Vector3(0.45, -5.0, 2.75), Vector3(15.7 - 0.45, 20.0, 8.7 - 2.75))
		p.input_enabled = false
		p.bot_brain = _bot_brain.bind(id)
		carry[id] = -1
		score[id] = 0
		strikes[id] = 0
		act_cd[id] = 0.0
		shove_cd[id] = 0.0
		stun[id] = 0.0
		anim_lock[id] = 0.0
		_add_tags(id)
		if p.is_bot:
			_bot[id] = {"err": randf_range(0.05, 0.24), "aggro": randf_range(0.08, 0.45), "react": randf_range(0.15, 0.45),
				"think": 0.0, "target": -1, "bin": 0, "victim": -1, "wait": 0.0, "home": p.position.x}
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _spawns() -> Array:
	var pts: Array = [Vector3(3.0, 0, 4.2), Vector3(13.0, 0, 4.2), Vector3(6.4, 0, 4.2), Vector3(9.6, 0, 4.2),
		Vector3(4.6, 0, 5.6), Vector3(11.4, 0, 5.6), Vector3(8.0, 0, 5.6), Vector3(1.6, 0, 5.6)]
	var a: Array = []
	for i in NetworkManager.players.size():
		a.append(pts[i % pts.size()])
	return a

func _make_icons() -> void:
	for k in 5:
		var vp := SubViewport.new()
		vp.size = Vector2i(256, 256)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var ic := Icon.new()
		ic.kind = k
		ic.size = Vector2(256, 256)
		vp.add_child(ic)
		add_child(vp)
		_icons.append(vp.get_texture())

func _aabb_of(n: Node, xf: Transform3D) -> AABB:
	var r := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		r = t * (n as MeshInstance3D).get_aabb()
		first = false
	for c in n.get_children():
		var a := _aabb_of(c, t)
		if a.size != Vector3.ZERO:
			r = a if first else r.merge(a)
			first = false
	return r

func _build_templates() -> void:
	for cat in VARIANTS.size():
		var arr: Array = []
		for v in VARIANTS[cat]:
			var path: String = (PH_MOD + v[1] + "/" + v[1] + ".gltf") if v[0] == "ph" else "res://assets/env/essentials/%s.gltf" % v[1]
			if not ResourceLoader.exists(path):
				continue
			var src: Node3D = load(path).instantiate()
			var keep: int = v[2]
			if keep >= 0:
				var meshes := src.find_children("*", "MeshInstance3D", true, false)
				for i in meshes.size():
					if i != keep:
						var m: Node = meshes[i]
						m.get_parent().remove_child(m)
						m.free()
			var tilt: float = v[4]
			var wrap := Node3D.new()
			wrap.add_child(src)
			src.rotation_degrees.x = tilt
			var bb := _aabb_of(wrap, Transform3D())
			var s: float = float(v[3]) / maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
			var piv := Node3D.new()
			piv.add_child(wrap)
			wrap.scale = Vector3.ONE * s
			wrap.position = -bb.get_center() * s
			for mi in piv.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			arr.append({"node": piv, "h": bb.size.y * s})
		_templates.append(arr)

func _exit_tree() -> void:
	for arr in _templates:
		for t in arr:
			var n: Node = t.node
			if is_instance_valid(n) and not n.is_inside_tree():
				n.free()

func _plain(col: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m

func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.3)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

func _cyl(r: float, h: float, m: Material, pos: Vector3, rot: Vector3, parent: Node, seg: int = 14) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = seg
	mi.mesh = cm
	mi.material_override = m
	mi.rotation_degrees = rot
	mi.position = pos
	parent.add_child(mi)
	return mi

func _hazard_mat() -> StandardMaterial3D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.045
	noise.seed = 9
	for y in n:
		for x in n:
			var stripe := int(floor(float(x + y) / 16.0)) % 2
			var g := 0.7 + noise.get_noise_2d(x, y) * 0.45
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

func _grime_tex(seed_v: int) -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.seed = seed_v
	for y in n:
		for x in n:
			var dx := (x - n * 0.5) / (n * 0.5)
			var dy := (y - n * 0.5) / (n * 0.5)
			var v := 1.0 - sqrt(dx * dx + dy * dy) + noise.get_noise_2d(x, y) * 0.6
			img.set_pixel(x, y, Color(1, 1, 1, clampf((v - 0.25) * 2.0, 0.0, 0.9)))
	return ImageTexture.create_from_image(img)

func _soft_tex() -> Texture2D:
	if _soft:
		return _soft
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	_soft = t
	return t

func _build_plant() -> void:
	var pl := Node3D.new()
	pl.name = "Plant"
	world.add_child(pl)
	var hz := _hazard_mat()
	_build_belt(pl, hz)
	_build_hopper(pl)
	_build_furnace(pl, hz)
	for i in 4:
		_build_bin(i, pl, hz)
	_build_terminal(pl)
	_build_dressing(pl)

func _build_belt(pl: Node3D, hz: Material) -> void:
	var body := mat("green_metal_rust", 0.7, Color(0.55, 0.57, 0.5))
	var steel := mat("rusty_metal_02", 1.2)
	_belt_mat = mat("rubber_tiles", 1.8, Color(0.3, 0.29, 0.27)).duplicate()
	var len := BELT_END - BELT_X0
	var cx := (BELT_X0 + BELT_END) * 0.5
	box(Vector3(len, 0.55, 1.2), Vector3(cx, 0.275, BELT_Z), body, pl, true)
	box(Vector3(len, 0.06, 0.96), Vector3(cx, 0.6, BELT_Z), _belt_mat, pl)
	for s in [-1.0, 1.0]:
		box(Vector3(len, 0.18, 0.1), Vector3(cx, 0.66, BELT_Z + s * 0.55), steel, pl)
		box(Vector3(len, 0.12, 0.05), Vector3(cx, 0.34, BELT_Z + s * 0.62), hz, pl)
	box(Vector3(len + 0.4, 0.02, 0.28), Vector3(cx, 0.012, BELT_Z + 0.82), hz, pl)
	var x := BELT_X0 + 0.5
	while x < BELT_END - 0.2:
		_cyl(0.075, 1.12, steel, Vector3(x, 0.52, BELT_Z + 0.0), Vector3(90, 0, 0), pl, 10)
		box(Vector3(0.1, 0.5, 0.06), Vector3(x, 0.25, BELT_Z + 0.63), steel, pl)
		x += 1.2
	box(Vector3(W + 1.0, 0.03, 1.2), Vector3(W * 0.5, 0.015, 3.35), mat("metal_grate_rusty", 0.7, Color(0.55, 0.52, 0.48)), pl)

func _build_hopper(pl: Node3D) -> void:
	var rust := mat("rusty_metal", 0.6, Color(0.75, 0.7, 0.65))
	var dark := mat("rusty_metal", 0.8, Color(0.2, 0.18, 0.16))
	var green := mat("green_metal_rust", 0.6, Color(0.55, 0.58, 0.5))
	box(Vector3(2.2, 1.6, 2.1), Vector3(-0.9, 0.8, BELT_Z), green, pl, true)
	var top := box(Vector3(3.0, 1.4, 2.8), Vector3(-0.9, 2.3, BELT_Z), rust, pl)
	top.rotation_degrees.z = -4.0
	box(Vector3(2.6, 0.06, 2.4), Vector3(-0.9, 3.02, BELT_Z), dark, pl)
	box(Vector3(0.1, 0.8, 1.1), Vector3(0.25, 1.05, BELT_Z), _plain(Color(0.02, 0.02, 0.02), 1.0), pl)
	for zz in [-0.5, 0.5]:
		box(Vector3(0.6, 0.06, 0.06), Vector3(0.3, 1.45, BELT_Z + zz), mat("rusty_metal_02", 2.0), pl)
	for t in [["trashbag", -1.4, 3.0, 1.0, 0.0, 0.9], ["trashbag", -0.4, 3.05, 2.6, 60.0, 0.8], ["cardboard_box_01", -1.2, 3.05, 2.3, 30.0, 1.0], ["metal_jerrycan", -0.3, 3.05, 1.4, 70.0, 1.1]]:
		prop(t[0], Vector3(t[1], t[2], t[3]), t[4], t[5], pl)
	var lbl := _label3d("HOPPER 2", 110, Vector3(-0.9, 1.0, BELT_Z + 1.07), pl)
	lbl.modulate = Color(0.85, 0.82, 0.7)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 1.0
	l.omni_range = 2.5
	pl.add_child(l)
	l.position = Vector3(0.8, 1.6, BELT_Z + 0.5)

func _build_furnace(pl: Node3D, hz: Material) -> void:
	var brick := mat("dark_brick_wall", 0.6, Color(0.6, 0.5, 0.45))
	var iron := mat("rusty_metal", 0.6, Color(0.55, 0.45, 0.4))
	var soot := _plain(Color(0.03, 0.025, 0.02), 1.0)
	box(Vector3(4.6, 4.6, 3.4), Vector3(16.7, 2.3, -1.1), brick, pl, true)
	box(Vector3(1.0, 4.6, 3.4), Vector3(14.6, 2.3, -1.1), brick, pl, true)
	box(Vector3(3.0, 2.2, 3.4), Vector3(15.6, 3.5, -1.1), brick, pl)
	box(Vector3(2.5, 0.25, 0.4), Vector3(15.6, 2.15, 0.62), iron, pl)
	for sx in [14.3, 16.9]:
		box(Vector3(0.25, 2.2, 0.4), Vector3(sx, 1.05, 0.62), iron, pl)
	box(Vector3(2.4, 2.0, 0.2), Vector3(15.6, 1.0, -0.3), _glow(Color(1.0, 0.38, 0.06), 3.5), pl)
	box(Vector3(2.4, 0.2, 1.0), Vector3(15.6, 0.0, 0.2), _glow(Color(1.0, 0.45, 0.08), 2.2), pl)
	box(Vector3(0.1, 2.0, 1.0), Vector3(14.42, 1.0, 0.2), soot, pl)
	box(Vector3(0.1, 2.0, 1.0), Vector3(16.78, 1.0, 0.2), soot, pl)
	_cyl(0.5, 4.0, iron, Vector3(17.6, 6.4, -1.8), Vector3.ZERO, pl, 16)
	var grate := Node3D.new()
	pl.add_child(grate)
	box(Vector3(2.4, 0.05, 3.1), Vector3(15.6, -0.02, 2.2), _glow(Color(1.0, 0.32, 0.05), 2.8), grate)
	var bar := mat("rusty_metal_02", 2.0, Color(0.25, 0.2, 0.18))
	var bx := ZONE_X + 0.1
	while bx < 16.8:
		box(Vector3(0.07, 0.08, 3.1), Vector3(bx, 0.04, 2.2), bar, grate)
		bx += 0.28
	for zz in [1.0, 2.0, 3.0]:
		box(Vector3(2.4, 0.08, 0.07), Vector3(15.6, 0.05, zz), bar, grate)
	box(Vector3(0.24, 0.04, 3.3), Vector3(ZONE_X - 0.1, 0.03, 2.15), hz, pl)
	box(Vector3(2.6, 0.04, 0.24), Vector3(15.6, 0.03, ZONE_Z + 0.08), hz, pl)
	var chute := box(Vector3(0.9, 0.05, 1.0), Vector3(14.7, 0.45, BELT_Z - 0.2), iron, pl)
	chute.rotation_degrees = Vector3(0, -50, -25)
	_fire(pl, Vector3(15.6, 0.3, 0.2), Vector3(1.0, 0.1, 0.35), 110, 1.2, 2.6, 1.1, false)
	_fire(pl, Vector3(15.6, 0.1, 2.2), Vector3(0.95, 0.02, 1.4), 40, 0.7, 1.4, 0.55, false)
	_smoke_column(pl, Vector3(15.6, 2.2, 0.6))
	var sh := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 3.2)
	sh.mesh = q
	var sm := ShaderMaterial.new()
	var s := Shader.new()
	s.code = SHIMMER_SHADER
	sm.shader = s
	sh.material_override = sm
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pl.add_child(sh)
	sh.position = Vector3(15.6, 1.9, 1.3)
	sh.rotation_degrees.x = -30.0
	_furnace_light = OmniLight3D.new()
	_furnace_light.light_color = Color(1.0, 0.42, 0.1)
	_furnace_light.light_energy = 5.0
	_furnace_light.omni_range = 7.5
	_furnace_light.shadow_enabled = true
	pl.add_child(_furnace_light)
	_furnace_light.position = Vector3(15.6, 1.2, 1.6)
	var sign := _label3d("INCINERATOR", 120, Vector3(15.6, 2.75, 0.84), pl)
	sign.modulate = Color(1.0, 0.62, 0.2)
	var warn := _label3d("DO NOT STAND", 70, Vector3(15.6, 0.06, ZONE_Z - 0.35), pl)
	warn.rotation_degrees.x = -90.0
	warn.modulate = Color(0.95, 0.75, 0.2)
	_alarm_light = SpotLight3D.new()
	_alarm_light.light_color = Color(1.0, 0.05, 0.02)
	_alarm_light.light_energy = 0.0
	_alarm_light.spot_range = 22.0
	_alarm_light.spot_angle = 30.0
	pl.add_child(_alarm_light)
	_alarm_light.position = Vector3(W * 0.5 + 3.2, 5.0, -2.5)
	box(Vector3(0.3, 0.3, 0.3), Vector3(W * 0.5 + 3.2, 5.0, -2.7), _glow(Color(1.0, 0.1, 0.05), 1.5), pl)

func _build_bin(i: int, pl: Node3D, hz: Material) -> void:
	var col := CAT_COLORS[i]
	var b := Node3D.new()
	pl.add_child(b)
	b.position = Vector3(BIN_X[i], 0, BIN_Z)
	var paint := mat("painted_concrete", 0.9, col.lerp(Color(0.5, 0.48, 0.42), 0.15))
	var rim := mat("rusty_metal_02", 1.6, Color(0.6, 0.55, 0.5))
	var w := 2.0
	var d := 1.3
	var h := 0.95
	box(Vector3(w, h, 0.1), Vector3(0, h * 0.5, d * 0.5), paint, b)
	box(Vector3(w, h, 0.1), Vector3(0, h * 0.5, -d * 0.5), paint, b)
	box(Vector3(0.1, h, d), Vector3(w * 0.5, h * 0.5, 0), paint, b)
	box(Vector3(0.1, h, d), Vector3(-w * 0.5, h * 0.5, 0), paint, b)
	box(Vector3(w - 0.1, 0.05, d - 0.1), Vector3(0, 0.3, 0), _plain(Color(0.025, 0.022, 0.02), 1.0), b)
	for s in [-1.0, 1.0]:
		box(Vector3(w + 0.08, 0.08, 0.14), Vector3(0, h, s * d * 0.5), rim, b)
		box(Vector3(0.14, 0.08, d + 0.08), Vector3(s * w * 0.5, h, 0), rim, b)
	var solid := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(w, 1.2, d)
	cs.shape = shp
	cs.position.y = 0.6
	solid.add_child(cs)
	b.add_child(solid)
	var sign := Node3D.new()
	b.add_child(sign)
	sign.position = Vector3(0, h + 0.05, d * 0.5 + 0.02)
	sign.rotation_degrees.x = -52.0
	box(Vector3(w, 0.9, 0.08), Vector3(0, 0.45, 0), paint, sign)
	box(Vector3(w + 0.06, 0.07, 0.12), Vector3(0, 0.9, 0), rim, sign)
	for s in [-1.0, 1.0]:
		box(Vector3(0.05, 0.9, 0.12), Vector3(s * (w * 0.5 + 0.01), 0.45, 0), rim, sign)
	var ic := Sprite3D.new()
	ic.texture = _icons[i]
	ic.pixel_size = 0.0029
	ic.modulate = Color(0.07, 0.06, 0.05)
	ic.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	ic.shaded = true
	sign.add_child(ic)
	ic.position = Vector3(-0.62, 0.45, 0.05)
	var lb := _label3d(CAT_NAMES[i] if i < 3 else "BIO\nHAZARD", 92 if i < 3 else 74, Vector3(0.38, 0.45, 0.05), sign)
	lb.modulate = Color(0.07, 0.06, 0.05)
	lb.shaded = true
	var top_ic := Sprite3D.new()
	top_ic.texture = _icons[i]
	top_ic.pixel_size = 0.0034
	top_ic.modulate = col * 1.25
	top_ic.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	top_ic.rotation_degrees.x = -90.0
	b.add_child(top_ic)
	top_ic.position = Vector3(0, 0.34, -0.1)
	box(Vector3(w + 0.3, 0.02, 0.22), Vector3(0, 0.012, -d * 0.5 - 0.3), hz, b)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 0.9
	l.omni_range = 2.4
	b.add_child(l)
	l.position = Vector3(0, 1.7, -0.6)
	_bin_lights.append(l)

func _build_terminal(pl: Node3D) -> void:
	var s := Node3D.new()
	pl.add_child(s)
	s.position = Vector3(7.0, 1.95, -2.72)
	box(Vector3(4.2, 2.3, 0.26), Vector3.ZERO, mat("rusty_metal_02", 1.2, Color(0.5, 0.47, 0.42)), s)
	box(Vector3(3.9, 2.0, 0.04), Vector3(0, 0, 0.14), _glow(Color(0.02, 0.09, 0.035), 0.3), s)
	_scr_title = _label3d("SORT LINE 3", 100, Vector3(-0.35, 0.72, 0.17), s)
	_scr_body = _label3d("", 74, Vector3(-0.35, -0.2, 0.17), s)
	_scr_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_scr_icon = Sprite3D.new()
	_scr_icon.texture = _icons[4]
	_scr_icon.pixel_size = 0.0058
	_scr_icon.modulate = Color(0.45, 1.0, 0.42)
	s.add_child(_scr_icon)
	_scr_icon.position = Vector3(1.25, 0.0, 0.17)
	var gl := OmniLight3D.new()
	gl.light_color = Color(0.3, 1.0, 0.35)
	gl.light_energy = 0.8
	gl.omni_range = 4.0
	s.add_child(gl)
	gl.position = Vector3(0, 0, 1.0)
	_refresh_terminal()

func _label3d(text: String, size: int, pos: Vector3, parent: Node3D) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = Color(0.45, 1.0, 0.42)
	l.outline_size = 0
	l.position = pos
	parent.add_child(l)
	return l

func _build_dressing(pl: Node3D) -> void:
	var d := [["steel_frame_shelves_02", 10.6, -2.3, 0, 1.1], ["steel_frame_shelves_03", 2.2, -2.3, 0, 1.0], ["trashbag", 3.4, -0.4, 20, 1.2],
		["trashbag", 4.2, 0.2, 80, 1.0], ["trashbag", 12.4, -0.2, 140, 1.1], ["cardboard_box_01", 9.8, -0.4, 25, 1.2], ["cardboard_box_01", 9.6, 0.4, -10, 1.0],
		["barrel_03", 12.0, -1.6, 0, 1.15], ["barrel_03", 12.8, -0.9, 40, 1.15], ["metal_trash_can", 4.6, -0.3, 0, 1.1], ["plastic_crate_01", 10.0, -1.2, 15, 1.3],
		["wine_bottles_01", 10.8, 0.5, 30, 1.2], ["can_rusted", 3.0, 0.6, 0, 1.6], ["oil_tin", 11.2, 0.5, 40, 1.6], ["bananas", 3.9, 0.7, 30, 1.4],
		["medical_box", 10.2, 0.4, 70, 1.3], ["plastic_bottle_gallon", 9.6, 0.6, 0, 1.5], ["old_tyre", 13.6, 0.4, 0, 1.0],
		["WetFloorSign_01", 0.6, 9.2, 30, 1.0], ["metal_trash_can", 15.4, 9.0, 0, 1.1], ["trashbag", 4.4, 9.0, 40, 1.0], ["trashbag", 8.0, 9.1, 100, 1.1],
		["trashbag", 11.6, 9.0, 10, 0.9], ["food_apple_01", 7.4, 9.3, 0, 1.6], ["hamburger_buns", 11.0, 9.3, 20, 1.3], ["barrel_stove", 18.2, 3.6, 0, 1.1]]
	for it in d:
		prop(it[0], Vector3(it[1], 0.0, it[2]), it[3], it[4], pl)
	var gr := _grime_tex(11)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in 20:
		var dc := Decal.new()
		dc.texture_albedo = gr
		var sz := rng.randf_range(1.2, 3.4)
		dc.size = Vector3(sz, 1.0, sz * rng.randf_range(0.6, 1.0))
		dc.modulate = Color(0.12, 0.1, 0.06) if i % 3 != 0 else Color(0.22, 0.2, 0.08)
		dc.rotation.y = rng.randf() * TAU
		pl.add_child(dc)
		dc.position = Vector3(rng.randf_range(-1.0, W + 0.5), 0.1, rng.randf_range(-1.5, D + 1.5))
	var pud := StandardMaterial3D.new()
	pud.albedo_texture = _grime_tex(41)
	pud.albedo_color = Color(0.05, 0.06, 0.04, 0.85)
	pud.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pud.roughness = 0.04
	pud.metallic_specular = 1.0
	for pp in [Vector3(4.8, 0.03, 6.2), Vector3(10.8, 0.03, 4.4), Vector3(7.6, 0.03, 8.0), Vector3(1.4, 0.03, 4.0), Vector3(13.0, 0.03, 7.0)]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(rng.randf_range(1.4, 2.4), rng.randf_range(1.0, 1.8))
		mi.mesh = pm
		mi.material_override = pud
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.y = rng.randf() * TAU
		pl.add_child(mi)
		mi.position = pp
	for fp in [Vector3(BIN_X[2], 1.4, BIN_Z), Vector3(3.8, 0.8, -0.1), Vector3(12.4, 0.8, -0.2), Vector3(8.0, 0.7, 9.2), Vector3(-0.6, 3.4, BELT_Z)]:
		_flies(pl, fp)
	for lx in [4.4, 11.6]:
		var sp := lamp(Vector3(lx, 6.8, 3.6), 9.0, Color(1.0, 0.82, 0.6), pl)
		sp.spot_angle = 64.0
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 5.5
	key.spot_range = 16.0
	key.spot_angle = 52.0
	key.shadow_enabled = true
	pl.add_child(key)
	key.position = Vector3(W * 0.5, 9.0, 7.6)
	key.rotation_degrees.x = -90.0
	prop("modular_pipes", Vector3(W * 0.5 - 4.0, 1.6, -2.75), 0.0, 1.4, pl)

func _flies(parent: Node, pos: Vector3) -> void:
	var gp := GPUParticles3D.new()
	gp.amount = 14
	gp.lifetime = 2.6
	gp.preprocess = 2.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.45
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 6.0
	pm.turbulence_noise_scale = 1.2
	pm.turbulence_influence_min = 0.4
	pm.turbulence_influence_max = 0.8
	gp.process_material = pm
	var m := SphereMesh.new()
	m.radius = 0.028
	m.height = 0.04
	m.radial_segments = 4
	m.rings = 2
	m.material = _plain(Color(0.02, 0.02, 0.02), 0.4)
	gp.draw_pass_1 = m
	parent.add_child(gp)
	gp.position = pos

func _fire(parent: Node, pos: Vector3, ext: Vector3, amount: int, life: float, vel: float, size: float, one_shot: bool) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = amount
	gp.lifetime = life
	gp.one_shot = one_shot
	if one_shot:
		gp.explosiveness = 0.8
	else:
		gp.preprocess = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ext
	pm.direction = Vector3.UP
	pm.spread = 20.0 if not one_shot else 45.0
	pm.initial_velocity_min = vel * 0.5
	pm.initial_velocity_max = vel
	pm.gravity = Vector3(0, 1.5, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1.0, 0.2))
	var ct := CurveTexture.new()
	ct.curve = sc
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.85, 0.45, 1.0), Color(1.0, 0.45, 0.08, 0.9), Color(0.6, 0.12, 0.02, 0.5), Color(0.1, 0.05, 0.03, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex()
	q.material = m
	gp.draw_pass_1 = q
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(gp)
	gp.global_position = pos
	gp.emitting = true
	if one_shot:
		get_tree().create_timer(life + 0.6).timeout.connect(gp.queue_free)
	return gp

func _smoke_column(parent: Node, pos: Vector3) -> void:
	var gp := GPUParticles3D.new()
	gp.amount = 18
	gp.lifetime = 3.0
	gp.preprocess = 2.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.1, 0.2)
	pm.direction = Vector3(0, 1, 0.3)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.3, 0)
	pm.scale_min = 1.0
	pm.scale_max = 2.0
	var g := Gradient.new()
	g.set_color(0, Color(0.15, 0.12, 0.1, 0.45))
	g.set_color(1, Color(0.1, 0.1, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex()
	q.material = m
	gp.draw_pass_1 = q
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(gp)
	gp.global_position = pos

func _add_tags(id: int) -> void:
	var p: LabPlayer3D = players[id]
	var l := Label3D.new()
	l.text = ""
	l.font = _font
	l.font_size = 46
	l.pixel_size = 0.0011
	l.fixed_size = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 10
	l.modulate = Color(1.0, 0.2, 0.15)
	l.position = Vector3(0, LabPlayer3D.HEIGHT + 0.85, 0)
	p.add_child(l)
	_strike_tags[id] = l
	var h := Node3D.new()
	p.body.add_child(h)
	h.position = HELD_OFS
	_holders[id] = h

func _style(l: Label, size: int, c: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)

func _build_hud() -> void:
	hud_title("THE FILTER  ·  sort it right")
	_hud_flash = ColorRect.new()
	_hud_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_flash.color = Color(0.9, 0.05, 0.02, 0.0)
	_hud_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hud_flash)
	_hud_time = Label.new()
	_hud_time.position = Vector2(860, 10)
	_style(_hud_time, 26, Color("ffd34a"))
	hud.add_child(_hud_time)
	_hud_board = Label.new()
	_hud_board.position = Vector2(930, 12)
	_style(_hud_board, 16, Color("e8e2c8"))
	hud.add_child(_hud_board)
	_hud_help = Label.new()
	_hud_help.text = "WASD move  ·  SPACE grab from the belt / drop in a bin  ·  empty hands: SPACE shoves"
	_hud_help.position = Vector2(16, 42)
	_style(_hud_help, 16, Color("e8e2c8"))
	hud.add_child(_hud_help)
	_hud_status = Label.new()
	_hud_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hud_status.position = Vector2(-300, -64)
	_hud_status.size = Vector2(600, 40)
	_hud_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_hud_status, 22, Color("ffd34a"))
	hud.add_child(_hud_status)
	_hud_brief = Control.new()
	_hud_brief.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_brief.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hud_brief)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.04, 0.015, 0.82)
	bg.set_anchors_preset(Control.PRESET_CENTER)
	bg.position = Vector2(-230, -200)
	bg.size = Vector2(460, 360)
	_hud_brief.add_child(bg)
	var tr := TextureRect.new()
	tr.texture = _icons[4]
	tr.set_anchors_preset(Control.PRESET_CENTER)
	tr.position = Vector2(-110, -190)
	tr.size = Vector2(220, 220)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.modulate = Color(0.45, 1.0, 0.42)
	_hud_brief.add_child(tr)
	var bl := Label.new()
	bl.text = "SORT WITH 100% ACCURACY\n3 STRIKES = FILTERED"
	bl.set_anchors_preset(Control.PRESET_CENTER)
	bl.position = Vector2(-230, 40)
	bl.size = Vector2(460, 100)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.add_theme_font_override("font", _font)
	_style(bl, 40, Color(0.5, 1.0, 0.45))
	_hud_brief.add_child(bl)
	_big = Label.new()
	_big.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big.anchor_top = 0.3
	_big.anchor_bottom = 0.5
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big.add_theme_font_size_override("font_size", 64)
	_big.add_theme_color_override("font_outline_color", Color.BLACK)
	_big.add_theme_constant_override("outline_size", 12)
	hud.add_child(_big)
	_refresh_hud()

func _big_local(text: String, c: Color, hold: float) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", c)
	_big.modulate.a = 1.0
	if hold > 0.0:
		var tw := create_tween()
		tw.tween_interval(hold)
		tw.tween_property(_big, "modulate:a", 0.0, 0.4)

func _net(id: int) -> int:
	return int(score[id]) - int(strikes[id])

func _refresh_hud() -> void:
	var ids: Array = players.keys()
	ids.sort_custom(func(a, b): return _net(a) > _net(b))
	var lines: Array = []
	for id in ids:
		var p: LabPlayer3D = players[id]
		lines.append("%s%s  %d  %s" % ["" if p.alive else "† ", p.display_name, int(score[id]), "x".repeat(int(strikes[id]))])
	_hud_board.text = "SORTED / STRIKES\n" + "\n".join(lines)
	for id in _strike_tags:
		var n: int = strikes[id]
		_strike_tags[id].text = "X ".repeat(n).strip_edges()
		_strike_tags[id].visible = players[id].alive
	var me := multiplayer.get_unique_id()
	if not players.has(me):
		_hud_status.text = ""
		return
	var mp: LabPlayer3D = players[me]
	if not mp.alive:
		_hud_status.text = "FILTERED" if int(strikes[me]) >= MAX_STRIKES else "INCINERATED"
		_hud_status.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		return
	var iid: int = carry.get(me, -1)
	if iid >= 0 and items.has(iid):
		_hud_status.text = "CARRYING  ·  SPACE at the right bin  ·  strikes %d/%d" % [int(strikes[me]), MAX_STRIKES]
		_hud_status.add_theme_color_override("font_color", Color("ffd34a"))
	else:
		_hud_status.text = "grab junk off the belt  ·  strikes %d/%d" % [int(strikes[me]), MAX_STRIKES]
		_hud_status.add_theme_color_override("font_color", Color("e8e2c8"))

func _refresh_terminal() -> void:
	if not _scr_body:
		return
	var lines: Array = []
	for i in 4:
		lines.append("%-11s %02d" % [CAT_NAMES[i], sorted_count[i]])
	lines.append("%-11s %02d" % ["BURNED", burned_count])
	_scr_body.text = "\n".join(lines)

func _process(delta: float) -> void:
	if not world:
		return
	clock += delta
	if _belt_mat:
		_belt_mat.uv1_offset.x = fmod(_belt_mat.uv1_offset.x - delta * BELT_SPEED * 1.8, 1.0)
	if _furnace_light:
		_furnace_light.light_energy = 4.4 + sin(clock * 13.0) * 0.6 + sin(clock * 31.0) * 0.4 + randf() * 0.5
	if _alarm_light:
		_alarm_t = maxf(_alarm_t - delta, 0.0)
		_alarm_light.light_energy = 14.0 if _alarm_t > 0.0 else 0.0
		_alarm_light.rotation = Vector3(-0.5, clock * 9.0, 0.0)
	for iid in items:
		var it: Dictionary = items[iid]
		if it.state == "belt":
			var n: Node3D = it.node
			n.position.x += BELT_SPEED * delta
	for id in carry:
		if int(carry[id]) >= 0:
			_drive_carry(id)
	if _hud_time:
		var left := clampf(TIME_LIMIT - clock, 0.0, TIME_LIMIT) if running or _ended_local else TIME_LIMIT
		_hud_time.text = "%d" % ceili(left)
		_hud_flash.color.a = maxf(_hud_flash.color.a - delta * 1.2, 0.0)
	var lp := local_player()
	if lp and lp.alive and running:
		var down := Input.is_physical_key_pressed(KEY_SPACE)
		if down and not _space_down:
			if multiplayer.is_server():
				_try_action(multiplayer.get_unique_id())
			else:
				_req_action.rpc_id(1)
		_space_down = down

func _drive_carry(id: int) -> void:
	var p: LabPlayer3D = players[id]
	var b: LabCharacter = p.body
	if not p.alive or b.is_dead() or clock < float(anim_lock[id]):
		return
	if not _mods.has(id):
		var mod := ArmPose.new()
		mod.poses = _arm_pose(b.skeleton)
		b.skeleton.add_child(mod)
		_mods[id] = mod
	var want := "Walk_Carry" if p._move_speed > 0.3 else "Idle"
	b._action_busy = true
	b._locomotion = ""
	if b.anim.current_animation != want:
		b.anim.play(want, 0.18)

func _arm_pose(sk: Skeleton3D) -> Dictionary:
	var key := "carry|%d" % sk.get_bone_count()
	if _pose_cache.has(key):
		return _pose_cache[key]
	var a := LabCharacter.shared_library().get_animation("Walk_Carry")
	var d: Dictionary = {}
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(a.track_get_path(t)).get_slice(":", 1)
		if not (bone.ends_with("_r") or bone.ends_with("_l")):
			continue
		if bone.begins_with("thigh") or bone.begins_with("calf") or bone.begins_with("foot") or bone.begins_with("ball"):
			continue
		var bi := sk.find_bone(bone)
		if bi >= 0:
			d[bi] = a.rotation_track_interpolate(t, 0.25)
	_pose_cache[key] = d
	return d

func _release_pose(id: int) -> void:
	if _mods.has(id):
		var m: Node = _mods[id]
		if is_instance_valid(m):
			m.queue_free()
		_mods.erase(id)

func _fwd(p: LabPlayer3D) -> Vector3:
	return Vector3(sin(p._target_yaw), 0.0, cos(p._target_yaw))

func _item_pos(iid: int) -> Vector3:
	var n: Node3D = items[iid].node
	return n.global_position

func _in_zone(pos: Vector3) -> bool:
	return pos.x > ZONE_X and pos.z < ZONE_Z

@rpc("any_peer", "reliable")
func _req_action() -> void:
	if multiplayer.is_server():
		_try_action(multiplayer.get_remote_sender_id())

func _try_action(id: int) -> void:
	if not running or not players.has(id) or not players[id].alive:
		return
	if clock < float(act_cd[id]) or float(stun[id]) > 0.0:
		return
	act_cd[id] = clock + 0.3
	var p: LabPlayer3D = players[id]
	var iid: int = carry[id]
	if iid >= 0:
		var bi := _bin_near(p.position)
		if bi >= 0:
			_deposit(id, iid, bi)
		else:
			var dp := _clamp_floor(p.position + _fwd(p) * 0.7)
			carry[id] = -1
			_rpc_drop.rpc(id, iid, dp, false)
			if _in_zone(dp):
				_burn_item_later(iid)
		return
	var v := _shove_target(id, true)
	if v >= 0:
		_shove(id, v)
		return
	var it := _item_near(id)
	if it >= 0:
		carry[id] = it
		items[it].state = "held"
		_rpc_pick.rpc(id, it)
		if _bot.has(id):
			var cat: int = items[it].cat
			var b: Dictionary = _bot[id]
			b.bin = cat if randf() > float(b.err) else (cat + 1 + randi() % 3) % 4
		return
	_shove(id, _shove_target(id, false))

func _bin_near(pos: Vector3) -> int:
	var best := -1
	var best_d := BIN_R
	for i in 4:
		var d := Vector2(pos.x - BIN_X[i], pos.z - DEPOSIT_Z).length()
		if d < best_d:
			best_d = d
			best = i
	return best

func _item_near(id: int) -> int:
	var p: LabPlayer3D = players[id]
	var f := _fwd(p)
	var best := -1
	var best_s := INF
	for iid in items:
		var it: Dictionary = items[iid]
		if it.state != "belt" and it.state != "floor":
			continue
		var ip := _item_pos(iid)
		var to := Vector3(ip.x - p.position.x, 0.0, ip.z - p.position.z)
		var d := to.length()
		if d > PICK_R:
			continue
		var dot := f.dot(to / maxf(d, 0.01))
		if d > 0.8 and dot < 0.2:
			continue
		var s := d - dot * 0.6
		if s < best_s:
			best_s = s
			best = iid
	return best

func _shove_target(id: int, carriers_only: bool) -> int:
	var p: LabPlayer3D = players[id]
	var f := _fwd(p)
	var best := -1
	var best_d := SHOVE_R
	for o in alive_ids():
		if o == id or (carriers_only and int(carry[o]) < 0):
			continue
		var to: Vector3 = players[o].position - p.position
		to.y = 0.0
		var d := to.length()
		if d > best_d:
			continue
		if d > 0.7 and f.dot(to / d) < 0.35:
			continue
		best = o
		best_d = d
	return best

func _clamp_floor(q: Vector3) -> Vector3:
	return Vector3(clampf(q.x, 0.6, 15.6), 0.0, clampf(q.z, 2.9, 6.6))

func _shove(id: int, v: int) -> void:
	if clock < float(shove_cd[id]):
		return
	shove_cd[id] = clock + SHOVE_CD
	var p: LabPlayer3D = players[id]
	var f := _fwd(p)
	if v < 0:
		_rpc_shove.rpc(id, -1, p.position + f * 0.5, Vector3.ZERO, -1, Vector3.ZERO)
		return
	var pv: LabPlayer3D = players[v]
	var to := pv.position - p.position
	to.y = 0.0
	var dir: Vector3 = to.normalized() if to.length() > 0.05 else f
	if not p.is_bot:
		dir = (dir * 0.6 + f * 0.4).normalized()
	stun[v] = 0.55
	var dropped: int = carry[v]
	var dpos := Vector3.ZERO
	if dropped >= 0:
		carry[v] = -1
		items[dropped].state = "floor"
		dpos = _clamp_floor(pv.position + dir * 1.2 + dir.cross(Vector3.UP) * randf_range(-0.5, 0.5))
	var push_to := pv.position + dir * KNOCK
	_rpc_shove.rpc(id, v, p.position + dir * maxf(to.length() - 0.65, 0.0), push_to, dropped, dpos)
	if dropped >= 0 and _in_zone(dpos):
		_burn_item_later(dropped)

func _deposit(id: int, iid: int, bi: int) -> void:
	var cat: int = items[iid].cat
	var ok := cat == bi
	carry[id] = -1
	if ok:
		score[id] = int(score[id]) + 1
	else:
		strikes[id] = int(strikes[id]) + 1
	_rpc_deposit.rpc(id, iid, bi, ok, int(score[id]), int(strikes[id]))
	if not ok and int(strikes[id]) >= MAX_STRIKES:
		get_tree().create_timer(0.75).timeout.connect(func() -> void:
			if players[id].alive and not _done:
				dead_order.append(id)
				_rpc_filter.rpc(id))

func _burn_item_later(iid: int) -> void:
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if items.has(iid) and items[iid].state == "floor":
			burned_count += 1
			_rpc_burn_item.rpc(iid, burned_count))

func _run() -> void:
	var xs := 1.0
	while xs < 11.5:
		_server_spawn(xs)
		xs += randf_range(1.3, 1.9)
	_rpc_brief.rpc()
	await get_tree().create_timer(BRIEF_T).timeout
	_rpc_start.rpc()
	while clock < TIME_LIMIT and not _over():
		await get_tree().create_timer(0.2).timeout
	_rpc_end.rpc()
	await get_tree().create_timer(2.2).timeout
	if not _done:
		_done = true
		finished.emit(_placement())

func _over() -> bool:
	var a := alive_ids().size()
	return a == 0 or (a <= 1 and players.size() > 1)

func _placement() -> Array:
	var alive: Array = alive_ids()
	alive.sort_custom(func(a, b): return _net(a) > _net(b) or (_net(a) == _net(b) and int(score[a]) > int(score[b])))
	var res: Array = alive.duplicate()
	for i in range(dead_order.size() - 1, -1, -1):
		if not res.has(dead_order[i]):
			res.append(dead_order[i])
	for id in players:
		if not res.has(id):
			res.append(id)
	return res

func _server_spawn(x: float) -> void:
	var cat := randi() % 4
	var v := randi() % (_templates[cat] as Array).size()
	var iid := _next_iid
	_next_iid += 1
	_rpc_spawn.rpc(iid, cat, v, x, randf() * TAU)

func _physics_process(delta: float) -> void:
	if not NetworkManager.is_server() or not running:
		return
	for id in players:
		stun[id] = maxf(float(stun[id]) - delta, 0.0)
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = randf_range(0.9, 1.35)
		_server_spawn(BELT_X0 + 0.35)
	for iid in items.keys():
		var it: Dictionary = items[iid]
		if it.state == "belt" and (it.node as Node3D).position.x >= BELT_END:
			it.state = "gone"
			burned_count += 1
			_rpc_burn_item.rpc(iid, burned_count)
	for id in alive_ids():
		if _in_zone(players[id].position):
			dead_order.append(id)
			_rpc_burn_player.rpc(id)

@rpc("authority", "call_local", "reliable")
func _rpc_spawn(iid: int, cat: int, v: int, x: float, yaw: float) -> void:
	var t: Dictionary = _templates[cat][v]
	var root := Node3D.new()
	world.add_child(root)
	var model: Node3D = (t.node as Node3D).duplicate()
	root.add_child(model)
	var h: float = t.h
	root.position = Vector3(x, BELT_TOP + h * 0.5, BELT_Z + randf_range(-0.2, 0.2))
	model.rotation.y = yaw
	items[iid] = {"cat": cat, "node": root, "model": model, "h": h, "state": "belt"}
	if x < 1.0:
		root.position.y += 0.8
		var tw := root.create_tween()
		tw.tween_property(root, "position:y", BELT_TOP + h * 0.5, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

@rpc("authority", "call_local", "reliable")
func _rpc_pick(id: int, iid: int) -> void:
	if not items.has(iid):
		return
	var it: Dictionary = items[iid]
	it.state = "held"
	carry[id] = iid
	var p: LabPlayer3D = players[id]
	var n: Node3D = it.node
	p.face(n.global_position - p.position)
	p.body.play_action("PickUp_Table", 0.08, 1.5)
	anim_lock[id] = clock + 0.4
	var h: Node3D = _holders[id]
	var gt := n.global_transform
	n.get_parent().remove_child(n)
	h.add_child(n)
	n.global_transform = gt
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "position", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "rotation", Vector3(0.0, 0.0, 0.0), 0.28)
	Fx.sfx("click", p.position, -2.0, 1.2)
	if p.is_local_human():
		p.speed = 4.2
	elif p.is_bot:
		p.speed = 4.0
	_refresh_hud()

func _detach(id: int, iid: int) -> Node3D:
	var n: Node3D = items[iid].node
	var gt := n.global_transform
	n.get_parent().remove_child(n)
	world.add_child(n)
	n.global_transform = gt
	if carry.get(id, -1) == iid:
		carry[id] = -1
	_release_pose(id)
	var p: LabPlayer3D = players[id]
	p.speed = 4.6
	return n

func _unbusy(id: int) -> void:
	var b: LabCharacter = players[id].body
	if not b.is_dead():
		b._action_busy = false
		b._locomotion = ""
		b.set_motion(0.0)

@rpc("authority", "call_local", "reliable")
func _rpc_drop(id: int, iid: int, pos: Vector3, _thrown: bool) -> void:
	if not items.has(iid):
		return
	var it: Dictionary = items[iid]
	var n := _detach(id, iid)
	it.state = "floor"
	_unbusy(id)
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "position", pos + Vector3(0, float(it.h) * 0.5, 0), 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "rotation", Vector3(0.0, randf() * TAU, 0.0), 0.35)
	Fx.sfx("hit", pos, -8.0, 1.4)
	_refresh_hud()

@rpc("authority", "call_local", "reliable")
func _rpc_deposit(id: int, iid: int, bi: int, ok: bool, sc: int, st: int) -> void:
	score[id] = sc
	strikes[id] = st
	if ok:
		sorted_count[bi] += 1
	var p: LabPlayer3D = players[id]
	p.face(Vector3(BIN_X[bi], 0, BIN_Z) - p.position)
	if items.has(iid):
		var n := _detach(id, iid)
		items[iid].state = "gone"
		var target := Vector3(BIN_X[bi] + randf_range(-0.4, 0.4), 0.45, BIN_Z + randf_range(-0.2, 0.2))
		var mid := (n.global_position + target) * 0.5 + Vector3(0, 1.1, 0)
		var tw := n.create_tween()
		tw.tween_property(n, "global_position", mid, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "global_position", target, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(n.queue_free)
		items.erase(iid)
	p.body.play_action("OverhandThrow", 0.08, 1.6)
	var bl: OmniLight3D = _bin_lights[bi]
	var base_c := CAT_COLORS[bi]
	if ok:
		Fx.sfx("win", Vector3(BIN_X[bi], 1.0, BIN_Z), -6.0, 1.3)
		Fx.sparks(world, Vector3(BIN_X[bi], 1.2, BIN_Z))
		bl.light_color = Color(0.5, 1.0, 0.4)
	else:
		Fx.sfx("buzzer", Vector3(BIN_X[bi], 1.0, BIN_Z), 0.0, 1.0)
		Fx.shake(0.2)
		bl.light_color = Color(1.0, 0.05, 0.02)
		_alarm_t = 1.4
		if p.is_local_human():
			_hud_flash.color.a = 0.35
			_big_local("STRIKE %d" % st if st < MAX_STRIKES else "FILTERED", Color(1.0, 0.25, 0.2), 0.8)
	bl.light_energy = 4.0
	var tw2 := bl.create_tween()
	tw2.tween_property(bl, "light_energy", 0.9, 0.7)
	tw2.tween_callback(func() -> void: bl.light_color = base_c)
	_refresh_terminal()
	_refresh_hud()

@rpc("authority", "call_local", "reliable")
func _rpc_burn_item(iid: int, total: int) -> void:
	burned_count = total
	if not items.has(iid):
		return
	var n: Node3D = items[iid].node
	items.erase(iid)
	var mouth := Vector3(15.6, 0.5, 0.0)
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "global_position", mouth, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(n, "rotation", Vector3(randf_range(-2.0, 2.0), randf(), randf_range(-2.0, 2.0)), 0.5)
	tw.chain().tween_callback(func() -> void:
		_fire(world, mouth + Vector3(0, 0.3, 0.3), Vector3(0.3, 0.1, 0.2), 18, 0.7, 2.6, 0.6, true)
		Fx.sfx("hum", mouth, -10.0, 0.6)
		n.queue_free())
	_refresh_terminal()

func _tween_move(id: int, to: Vector3, t: float) -> void:
	var p: LabPlayer3D = players[id]
	var dest := Vector3(clampf(to.x, p.bounds.position.x, p.bounds.end.x), p.position.y, clampf(to.z, p.bounds.position.z, p.bounds.end.z))
	if _push_tw.has(id):
		var old: Tween = _push_tw[id]
		if old and old.is_valid():
			old.kill()
	var tw := create_tween()
	tw.tween_property(p, "position", dest, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_push_tw[id] = tw

func _lock_input(p: LabPlayer3D, t: float) -> void:
	if not p.is_local_human():
		return
	p.input_enabled = false
	get_tree().create_timer(t).timeout.connect(func() -> void:
		if is_instance_valid(p) and p.alive and running:
			p.input_enabled = true)

@rpc("authority", "call_local", "reliable")
func _rpc_shove(a: int, v: int, lunge_to: Vector3, push_to: Vector3, dropped: int, dpos: Vector3) -> void:
	var pa: LabPlayer3D = players[a]
	if not pa.alive:
		return
	pa.face(lunge_to - pa.position)
	pa.body.play_action("Shield_Dash", 0.05, 1.6)
	Fx.sfx("whoosh", pa.position, -4.0, 1.1)
	if pa.is_multiplayer_authority():
		_tween_move(a, lunge_to, 0.16)
	_lock_input(pa, 0.2)
	if v < 0 or not players[v].alive:
		return
	var pv: LabPlayer3D = players[v]
	if dropped >= 0 and items.has(dropped):
		var n := _detach(v, dropped)
		items[dropped].state = "floor"
		var tw2 := n.create_tween().set_parallel(true)
		tw2.tween_property(n, "position", dpos + Vector3(0, float(items[dropped].h) * 0.5, 0), 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw2.tween_property(n, "rotation", Vector3(0.0, randf() * TAU, PI * 0.5 * float(randi() % 2)), 0.4)
	pv.face(pa.position - pv.position)
	pv.body.play_action("Hit_Knockback", 0.05, 1.2)
	anim_lock[v] = clock + 0.7
	Fx.sfx("hit", pv.position, -1.0, 1.0)
	Fx.shake(0.18)
	if pv.is_multiplayer_authority():
		_tween_move(v, push_to, 0.38)
	_lock_input(pv, 0.55)
	_refresh_hud()

func _char(p: LabPlayer3D) -> void:
	var over := StandardMaterial3D.new()
	over.albedo_color = Color(0.04, 0.025, 0.015, 0.82)
	over.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	over.roughness = 1.0
	for mi in p.body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = over
	p.body.set_suit_color(Color(0.07, 0.05, 0.04))

func _kill_common(id: int) -> LabPlayer3D:
	var p: LabPlayer3D = players[id]
	if _push_tw.has(id):
		var old: Tween = _push_tw[id]
		if old and old.is_valid():
			old.kill()
	if int(carry.get(id, -1)) >= 0 and items.has(int(carry[id])):
		var iid: int = carry[id]
		var n := _detach(id, iid)
		items[iid].state = "floor"
		n.position.y = float(items[iid].h) * 0.5
	carry[id] = -1
	_release_pose(id)
	if p.is_local_human():
		p.input_enabled = false
	p.set_alive(false)
	p.body._action_busy = false
	if not dead_order.has(id):
		dead_order.append(id)
	return p

@rpc("authority", "call_local", "reliable")
func _rpc_burn_player(id: int) -> void:
	var p: LabPlayer3D = players[id]
	if not p.alive:
		return
	_kill_common(id)
	p.body.die("Death01")
	_char(p)
	_fire(world, p.position + Vector3(0, 0.6, 0), Vector3(0.35, 0.6, 0.35), 60, 1.0, 3.5, 0.8, true)
	var lingering := _fire(world, p.position + Vector3(0, 0.25, 0), Vector3(0.5, 0.15, 0.3), 24, 0.8, 1.6, 0.5, false)
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if is_instance_valid(lingering):
			lingering.emitting = false)
	Fx.sfx("explosion", p.position, -6.0, 0.6)
	Fx.sfx("hum", p.position, 0.0, 0.5)
	Fx.shake(0.4)
	_refresh_hud()
	if p.is_local_human():
		_big_local("INCINERATED", Color(1.0, 0.5, 0.15), 1.6)

@rpc("authority", "call_local", "reliable")
func _rpc_filter(id: int) -> void:
	var p: LabPlayer3D = players[id]
	if not p.alive:
		return
	_kill_common(id)
	p.collision_layer = 0
	p.collision_mask = 0
	p._label.visible = false
	var pos := p.position
	var hatch := Node3D.new()
	world.add_child(hatch)
	hatch.position = Vector3(pos.x, 0.0, pos.z)
	box(Vector3(1.3, 0.02, 1.3), Vector3(0, 0.02, 0), _plain(Color(0.0, 0.0, 0.0), 1.0), hatch)
	box(Vector3(1.1, 0.02, 1.1), Vector3(0, -0.6, 0), _glow(Color(1.0, 0.35, 0.05), 4.0), hatch)
	var hz := _hazard_mat()
	for s in [-1.0, 1.0]:
		box(Vector3(1.6, 0.03, 0.14), Vector3(0, 0.025, s * 0.72), hz, hatch)
		box(Vector3(0.14, 0.03, 1.6), Vector3(s * 0.72, 0.025, 0), hz, hatch)
		var hinge := Node3D.new()
		hatch.add_child(hinge)
		hinge.position = Vector3(s * 0.65, 0.03, 0)
		var door := box(Vector3(0.64, 0.05, 1.26), Vector3(-s * 0.32, 0, 0), mat("blue_metal_plate", 1.0, Color(0.5, 0.5, 0.45)), hinge)
		door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var tw := hinge.create_tween()
		tw.tween_property(hinge, "rotation:z", s * 1.75, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var gl := OmniLight3D.new()
	gl.light_color = Color(1.0, 0.4, 0.08)
	gl.light_energy = 3.0
	gl.omni_range = 3.0
	hatch.add_child(gl)
	gl.position = Vector3(0, 0.3, 0)
	_fire(hatch, hatch.position + Vector3(0, -0.2, 0), Vector3(0.4, 0.05, 0.4), 22, 0.9, 1.4, 0.5, false)
	var b: LabCharacter = p.body
	b.play_loop("Jump", 0.05)
	Fx.sfx("buzzer", pos, -4.0, 0.7)
	Fx.sfx("whoosh", pos, 2.0, 0.55)
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(b, "position:y", -5.0, 0.8).set_delay(0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw2.tween_property(b, "rotation:x", randf_range(-1.2, 1.2), 0.8).set_delay(0.15)
	tw2.chain().tween_callback(func() -> void:
		b.die("Death01")
		b.visible = false
		var top := Vector3(pos.x, 0.3, pos.z)
		_fire(world, top, Vector3(0.45, 0.1, 0.45), 70, 1.1, 5.5, 0.9, true)
		Fx.blood(world, top + Vector3(0, 0.4, 0), 110)
		Fx.sfx("explosion", top, -4.0, 0.5)
		Fx.sfx("splat", top, 2.0, 0.7)
		Fx.shake(0.45))
	_refresh_hud()
	if p.is_local_human():
		_big_local("FILTERED", Color(1.0, 0.25, 0.2), 1.6)

@rpc("authority", "call_local", "reliable")
func _rpc_brief() -> void:
	_hud_brief.visible = true
	_scr_title.text = "BRIEFING"
	Fx.sfx("beep", null, -4.0, 0.9)

@rpc("authority", "call_local", "reliable")
func _rpc_start() -> void:
	running = true
	clock = 0.0
	for id in players:
		var p: LabPlayer3D = players[id]
		if p.is_local_human():
			p.input_enabled = true
	var tw := create_tween()
	tw.tween_property(_hud_brief, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: _hud_brief.visible = false)
	_scr_title.text = "SORT LINE 3"
	_big_local("SORT", Color("8fe36a"), 0.6)
	Fx.sfx("beep", null, -4.0, 1.4)
	Fx.sfx("hum", null, -8.0, 0.8)
	var th := create_tween()
	th.tween_interval(8.0)
	th.tween_property(_hud_help, "modulate:a", 0.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_end() -> void:
	running = false
	_ended_local = true
	for id in players:
		players[id].input_enabled = false
	var alive := alive_ids()
	alive.sort_custom(func(a, b): return _net(a) > _net(b))
	var txt := "SHIFT OVER"
	if not alive.is_empty():
		txt = "SHIFT OVER  ·  %s TOPS THE LINE" % players[alive[0]].display_name
	_big_local(txt, Color("e2c84b"), 0.0)
	Fx.sfx("buzzer", null, -6.0, 1.3)

func _steer(from: Vector3, goal: Vector3) -> Vector3:
	var g := goal
	if g.x > ZONE_X - 0.6 and g.z < ZONE_Z + 0.6:
		g.x = ZONE_X - 0.6
	var v := Vector3(g.x - from.x, 0.0, g.z - from.z)
	if from.x > ZONE_X - 0.9 and from.z < ZONE_Z + 0.9:
		v += Vector3(-1.2, 0.0, 0.8)
	if v.length() < 0.1:
		return Vector3.ZERO
	return v.normalized() * clampf(v.length() * 2.0, 0.35, 1.0)

func _claimed(iid: int, me: int) -> bool:
	for o in _bot:
		if o != me and int(_bot[o].target) == iid and players[o].alive:
			return true
	return false

func _bot_brain(delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	if not running or float(stun[id]) > 0.0:
		return Vector3.ZERO
	var b: Dictionary = _bot[id]
	if float(b.wait) > 0.0:
		b.wait = float(b.wait) - delta
		return Vector3.ZERO
	if int(carry[id]) >= 0:
		var bi: int = b.bin
		var goal := Vector3(BIN_X[bi], 0.0, DEPOSIT_Z + 0.05)
		if Vector2(p.position.x - goal.x, p.position.z - goal.z).length() < BIN_R - 0.35:
			p.face(Vector3(BIN_X[bi], 0, BIN_Z) - p.position)
			b.wait = float(b.react) * 0.5
			_try_action(id)
			return Vector3.ZERO
		return _steer(p.position, goal)
	b.think = float(b.think) - delta
	if float(b.think) <= 0.0:
		b.think = randf_range(0.25, 0.45)
		b.victim = -1
		if clock >= float(shove_cd[id]) and randf() < float(b.aggro):
			var best := 3.0
			for o in alive_ids():
				if o == id or int(carry[o]) < 0:
					continue
				var dd: float = players[o].position.distance_to(p.position)
				if dd < best:
					best = dd
					b.victim = o
		b.target = _bot_pick_target(id)
	var vic: int = b.victim
	if vic >= 0 and players[vic].alive and int(carry[vic]) >= 0:
		var to: Vector3 = players[vic].position - p.position
		to.y = 0.0
		if to.length() < 1.1:
			p.face(to)
			_try_action(id)
			b.victim = -1
			b.wait = 0.2
			return Vector3.ZERO
		return _steer(p.position, players[vic].position)
	var t: int = b.target
	if t < 0 or not items.has(t) or (items[t].state != "belt" and items[t].state != "floor"):
		b.think = 0.0
		return _steer(p.position, Vector3(clampf(p.position.x, 2.0, 12.0), 0.0, 3.4))
	var ip := _item_pos(t)
	var reach := Vector2(ip.x - p.position.x, ip.z - p.position.z).length()
	if reach < PICK_R - 0.25:
		p.face(Vector3(ip.x - p.position.x, 0.0, ip.z - p.position.z))
		b.wait = float(b.react) * 0.4
		_try_action(id)
		return Vector3.ZERO
	var goal2: Vector3
	if items[t].state == "belt":
		var lead := clampf(absf(ip.x - p.position.x) / 4.6 * BELT_SPEED + 0.25, 0.25, 1.6)
		goal2 = Vector3(minf(ip.x + lead, ZONE_X - 0.8), 0.0, 2.95)
	else:
		goal2 = Vector3(ip.x, 0.0, ip.z)
	return _steer(p.position, goal2)

func _bot_pick_target(id: int) -> int:
	var p: LabPlayer3D = players[id]
	var best := -1
	var best_s := INF
	for iid in items:
		var it: Dictionary = items[iid]
		if it.state != "belt" and it.state != "floor":
			continue
		var ip := _item_pos(iid)
		if it.state == "belt" and ip.x > ZONE_X - 2.4:
			continue
		if _in_zone(ip):
			continue
		var s := Vector2(ip.x - p.position.x, ip.z - p.position.z).length()
		s += absf(ip.x - float(_bot[id].home)) * 0.35
		if _claimed(iid, id):
			s += 4.0
		if it.state == "belt":
			s -= ip.x * 0.08
		if s < best_s:
			best_s = s
			best = iid
	return best
