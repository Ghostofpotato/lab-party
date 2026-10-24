extends Minigame
class_name ArenaMinigame3D
## Base for 3D minigames. Builds a grimy enclosed test chamber (photo-textured
## concrete, brick, rusted metal, pipes, hanging lamps, clutter), a close angled
## camera, and spawns a LabPlayer3D per roster entry. Play area is X 0..W, Z 0..D.
## Helpers: mat() for tiled photo materials, prop() for Poly Haven models,
## box() for textured blocks, eliminate() for deaths, survival placement.

const W: float = 16.0
const D: float = 10.0
const PH_TEX := "res://assets/ph/tex/"
const PH_MOD := "res://assets/ph/models/"

static var _mat_cache: Dictionary = {}

var world: Node3D
var hud: Control
var camera: Camera3D
var env: Environment
var players: Dictionary = {}

func setup_arena(build_room: bool = true) -> void:
	world = Node3D.new()
	world.name = "World3D"
	add_child(world)

	var env_node := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0c0d0b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.52)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.29, 0.24)
	env.fog_density = 0.006
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.78
	env.adjustment_contrast = 1.1
	env_node.environment = env
	world.add_child(env_node)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55.0, -28.0, 0.0)
	key.light_energy = 0.7
	key.light_color = Color(1.0, 0.93, 0.8)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 40.0
	world.add_child(key)

	camera = Camera3D.new()
	camera.fov = 48.0
	world.add_child(camera)
	camera.position = Vector3(W * 0.5, 8.6, D + 7.4)
	camera.look_at(Vector3(W * 0.5, 0.0, D * 0.5 + 0.8), Vector3.UP)
	camera.make_current()

	if build_room:
		build_chamber()
	hud = make_ui_layer()

## Tiled photo material from assets/ph/tex/<name>/ (world-space triplanar, so any box tiles cleanly).
static func mat(tex_name: String, tile: float = 0.5, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [tex_name, tile, tint.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	var dir := PH_TEX + tex_name + "/"
	m.albedo_texture = load(dir + "diff.jpg") if ResourceLoader.exists(dir + "diff.jpg") else null
	m.albedo_color = tint
	if ResourceLoader.exists(dir + "nor.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(dir + "nor.jpg")
	if ResourceLoader.exists(dir + "arm.jpg"):
		var arm: Texture2D = load(dir + "arm.jpg")
		m.ao_enabled = true
		m.ao_texture = arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = arm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.metallic = 1.0
	elif ResourceLoader.exists(dir + "rough.jpg"):
		m.roughness_texture = load(dir + "rough.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[key] = m
	return m

func box(size: Vector3, pos: Vector3, material: Material, parent: Node = null, collide: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	(parent if parent else world).add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi

## Poly Haven model by id (assets/ph/models/<id>/<id>.gltf).
func prop(id: String, pos: Vector3, yaw_deg: float = 0.0, scale_f: float = 1.0, parent: Node = null) -> Node3D:
	var p := PH_MOD + id + "/" + id + ".gltf"
	if not ResourceLoader.exists(p):
		push_warning("prop missing: " + id)
		return null
	var n: Node3D = load(p).instantiate()
	(parent if parent else world).add_child(n)
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	n.scale = Vector3.ONE * scale_f
	return n

func lamp(pos: Vector3, energy: float = 9.0, color: Color = Color(1.0, 0.82, 0.58), parent: Node = null) -> SpotLight3D:
	var host: Node = parent if parent else world
	prop("hanging_industrial_lamp", pos, 0.0, 1.4, host)
	var sp := SpotLight3D.new()
	sp.light_color = color
	sp.light_energy = energy
	sp.spot_range = pos.y + 6.0
	sp.spot_angle = 62.0
	sp.spot_attenuation = 0.6
	sp.shadow_enabled = true
	host.add_child(sp)
	sp.position = pos + Vector3(0, -0.4, 0)
	sp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	return sp

## Enclosed test chamber around the play area. Override the materials per minigame for variety.
func build_chamber(floor_tex: String = "concrete_floor_worn_001", wall_tex: String = "factory_brick", band_tex: String = "green_metal_rust") -> void:
	var room := Node3D.new()
	room.name = "Chamber"
	world.add_child(room)
	var m := 3.0
	var h := 6.5
	box(Vector3(W + m * 2.0, 0.2, D + m * 2.0), Vector3(W * 0.5, -0.1, D * 0.5), mat(floor_tex, 0.35), room)
	box(Vector3(W + m * 2.0, h, 0.4), Vector3(W * 0.5, h * 0.5, -m), mat(wall_tex, 0.4), room)
	box(Vector3(0.4, h, D + m * 2.0), Vector3(-m, h * 0.5, D * 0.5), mat(wall_tex, 0.4), room)
	box(Vector3(0.4, h, D + m * 2.0), Vector3(W + m, h * 0.5, D * 0.5), mat(wall_tex, 0.4), room)
	box(Vector3(W + m * 2.0, 1.3, 0.5), Vector3(W * 0.5, 0.65, -m + 0.2), mat(band_tex, 0.6), room)
	box(Vector3(0.5, 1.3, D + m * 2.0), Vector3(-m + 0.2, 0.65, D * 0.5), mat(band_tex, 0.6), room)
	box(Vector3(0.5, 1.3, D + m * 2.0), Vector3(W + m - 0.2, 0.65, D * 0.5), mat(band_tex, 0.6), room)
	box(Vector3(W + m * 2.0, 0.6, 0.3), Vector3(W * 0.5, 0.3, D + m), mat(band_tex, 0.6), room)
	var pipe_mat := mat("rusty_metal_02", 1.5)
	for y in [4.2, 4.6]:
		var pipe := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.16
		cm.height = W + m * 2.0
		pipe.mesh = cm
		pipe.material_override = pipe_mat
		pipe.rotation_degrees.z = 90.0
		pipe.position = Vector3(W * 0.5, y, -m + 0.45)
		room.add_child(pipe)
	prop("power_box_01", Vector3(W * 0.25, 2.2, -m + 0.25), 0.0, 1.6, room)
	prop("fire_alarm", Vector3(W * 0.62, 2.4, -m + 0.22), 0.0, 1.6, room)
	prop("security_camera_01", Vector3(W + m - 0.4, 4.4, -m + 0.5), -135.0, 1.6, room)
	prop("industrial_caged_sconce", Vector3(W * 0.8, 2.8, -m + 0.22), 0.0, 1.6, room)
	var clutter := [["worn_metal_rack", -2.2, -2.0, 90], ["barrel_03", -2.2, 1.2, 0], ["barrel_03", -1.6, 2.0, 40],
		["wooden_crate_01", W + 1.9, -1.8, 15], ["wooden_crate_02", W + 2.2, -0.6, -10], ["metal_tool_chest", W * 0.15, -2.4, 0],
		["portable_generator", W * 0.82, -2.3, 180], ["cement_bag", -2.0, D * 0.75, 30], ["trashbag", W + 2.0, D * 0.7, 0],
		["metal_trash_can", W + 2.2, D * 0.45, 0], ["cardboard_box_01", W * 0.45, -2.5, 12], ["old_military_crate", -2.1, D * 0.5, 90],
		["propane_tank", W + 2.3, 1.5, 0], ["WetFloorSign_01", W * 0.95, D + 1.4, 30], ["old_tyre", -1.6, D + 1.2, 0],
		["wooden_crate_01", 1.2, D + 2.0, 20], ["barrel_03", W - 1.0, D + 2.2, 0], ["plastic_crate_01", W * 0.55, D + 2.3, -15], ["hand_truck", 3.4, D + 2.1, 60]]
	for c in clutter:
		prop(c[0], Vector3(c[1], 0.0, c[2]), c[3], 1.15, room)
	lamp(Vector3(W * 0.25, 6.0, D * 0.45), 11.0, Color(1.0, 0.82, 0.58), room)
	lamp(Vector3(W * 0.75, 6.0, D * 0.45), 11.0, Color(1.0, 0.82, 0.58), room)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.55, 0.78, 0.6)
	fill.light_energy = 1.4
	fill.omni_range = 14.0
	room.add_child(fill)
	fill.position = Vector3(W * 0.5, 3.0, -m + 1.0)

func spawn_players(points: Array = []) -> void:
	var scene := preload("res://player/player3d.tscn")
	var i := 0
	for id in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[id]
		var pl: LabPlayer3D = scene.instantiate()
		pl.name = "P_%d" % id
		pl.peer_id = id
		pl.is_bot = info.is_bot
		pl.color = info.color
		pl.hat = info.get("hat", "hardhat")
		pl.sex = info.get("sex", "male")
		pl.display_name = info.name
		pl.bounds = AABB(Vector3(0.3, -5.0, 0.3), Vector3(W - 0.6, 20.0, D - 0.6))
		pl.position = points[i] if i < points.size() else Vector3(2.0 + float(i) * 1.6, 0.0, 2.0)
		pl.position.y = 0.0
		world.add_child(pl)
		pl.face(Vector3(W * 0.5, 0.0, D * 0.5) - pl.position)
		players[id] = pl
		i += 1

func alive_ids() -> Array:
	return players.keys().filter(func(id): return is_instance_valid(players[id]) and players[id].alive)

## Local elimination (call it inside a call_local RPC): death animation, blood, corpse stays.
func eliminate(id: int, anim_name: String = "Death01") -> void:
	if players.has(id) and is_instance_valid(players[id]) and players[id].alive:
		var p: LabPlayer3D = players[id]
		p.set_alive(false)
		p.body.die(anim_name)
		Fx.blood(world, p.global_position + Vector3(0, 0.9, 0))
		Fx.shake(0.25)

func survival_placement(elim_order: Array) -> Array:
	var placement: Array = alive_ids()
	for i in range(elim_order.size() - 1, -1, -1):
		if not placement.has(elim_order[i]):
			placement.append(elim_order[i])
	return placement

func local_player() -> LabPlayer3D:
	return players.get(multiplayer.get_unique_id())

func hud_title(text: String) -> Label:
	var name_part := text
	var rule_part := ""
	for sep in ["  ·  ", " · ", " — ", " - "]:
		if text.contains(sep):
			name_part = text.get_slice(sep, 0)
			rule_part = text.substr(name_part.length() + sep.length())
			break
	var p := PanelContainer.new()
	var sb := UiKit.glass_box(0)
	sb.bg_color = Color(UiKit.INK, 0.66)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.material = UiKit.glass_material()
	p.position = Vector2(10, 6)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var mark := ColorRect.new()
	mark.color = UiKit.ACCENT
	mark.custom_minimum_size = Vector2(3, 16)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mark)
	var l := Label.new()
	l.text = name_part.to_upper()
	l.add_theme_font_override("font", UiKit.display_font)
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_color_override("font_color", UiKit.TEXT)
	h.add_child(l)
	if rule_part != "":
		var r := Label.new()
		r.text = rule_part
		r.add_theme_font_override("font", UiKit.strong_font)
		r.add_theme_font_size_override("font_size", 14)
		r.add_theme_color_override("font_color", UiKit.MUTED)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(r)
	hud.add_child(p)
	return l
