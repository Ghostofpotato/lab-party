extends Node
## Dev harness: stages each facility bulletin joke with the game's own assets and
## saves a 480x270 JPG per card into ui/news/ and news/.
## godot --path . --windowed --audio-driver Dummy res://tools/news_thumbs.tscn -- [only_name]

const OUT := ["res://ui/news/", "res://news/"]
const SUITS := [Color("e2544b"), Color("3f7fd9"), Color("e8c23a"), Color("4fae5b"), Color("e07a2e"), Color("8a5bd1"), Color("37b5a8")]

var st: ArenaMinigame3D
var c := Vector3(8.0, 0.0, 5.0)

func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func(): print("THUMBS HARD TIMEOUT"); get_tree().quit(3))
	Profile.use_save_path("user://news_thumbs_profile.cfg")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(960, 540)
	var only: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	for n in ["roomba", "screamy", "survival", "hiring", "hr", "lost", "cafeteria", "safety"]:
		if only != "" and only != n:
			continue
		_new_stage(n != "cafeteria")
		await call("_stage_" + n)
		await _snap(n)
		st.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _new_stage(room: bool) -> void:
	st = ArenaMinigame3D.new()
	add_child(st)
	st.setup_arena(room)
	st.hud.get_parent().queue_free()

func _subject(pos: Vector3, yaw: float, i: int, hat: String = "", pose: String = "Idle", sex: String = "male") -> LabCharacter:
	var ch := LabCharacter.new()
	ch.owner_peer = -1
	ch.apply_look({"color": SUITS[i % SUITS.size()], "suit": SUITS[i % SUITS.size()], "hat": hat if hat != "" else Globals.HATS[i % Globals.HATS.size()], "sex": sex})
	st.world.add_child(ch)
	ch.position = pos
	ch.rotation_degrees.y = yaw
	ch.play_loop(pose)
	return ch

func _corpse(pos: Vector3, yaw: float, i: int, hat: String = "") -> LabCharacter:
	var ch := _subject(pos, yaw, i, hat)
	ch.die("Death01")
	Fx.blood(st.world, pos, 1)
	return ch

func _sign(text: String, pos: Vector3, yaw: float, w: float, h: float, size: int, col: Color = UiKit.TEXT, post: bool = true) -> void:
	var root := Node3D.new()
	st.world.add_child(root)
	root.position = pos
	root.rotation_degrees.y = yaw
	var board := StandardMaterial3D.new()
	board.albedo_color = Color(0.08, 0.075, 0.065)
	board.roughness = 0.8
	st.box(Vector3(w, h, 0.05), Vector3.ZERO, board, root)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = UiKit.ACCENT
	trim.emission_enabled = true
	trim.emission = UiKit.ACCENT
	trim.emission_energy_multiplier = 0.4
	st.box(Vector3(w, 0.05, 0.06), Vector3(0, h * 0.5 - 0.025, 0.002), trim, root)
	if post:
		st.box(Vector3(0.06, pos.y, 0.06), Vector3(0, -pos.y * 0.5 - h * 0.5 + 0.02, -0.04), board, root)
	var l := Label3D.new()
	l.text = text
	l.font = UiKit.display_font
	l.font_size = size
	l.pixel_size = 0.0035
	l.modulate = col
	l.outline_size = 0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.line_spacing = -size * 0.15
	l.position = Vector3(0, -0.02, 0.03)
	l.shaded = false
	root.add_child(l)

func _cam(pos: Vector3, look: Vector3, fov: float = 40.0) -> void:
	st.camera.fov = fov
	st.camera.position = pos
	st.camera.look_at(look, Vector3.UP)

func _key(pos: Vector3, energy: float = 6.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.84, 0.62)
	l.light_energy = energy * 0.35
	l.omni_range = 7.0
	l.shadow_enabled = true
	st.world.add_child(l)
	l.position = pos

func _snap(n: String) -> void:
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(480, 270, Image.INTERPOLATE_LANCZOS)
	for d in OUT:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
		img.save_jpg(ProjectSettings.globalize_path(d + n + ".jpg"), 0.8)
	print("THUMB ", n, " ", FileAccess.get_file_as_bytes(OUT[0] + n + ".jpg").size(), " bytes")

func _stage_roomba() -> void:
	var rr: Node = load("res://minigames/roomba_rampage/roomba_rampage.gd").new()
	rr.world = st.world
	rr._steel = rr._blade_material()
	rr._dark = rr._plain(Color(0.09, 0.09, 0.1), 0.45, 0.5)
	rr._rubber = rr._plain(Color(0.06, 0.06, 0.06), 0.9)
	var r: Variant = rr._build_roomba(Color(0.85, 0.83, 0.8), false)
	r.node.position = c + Vector3(-0.5, 0, 0.6)
	r.node.rotation_degrees.y = 35.0
	rr.free()
	_corpse(c + Vector3(0.7, 0, 0.1), -70.0, 1, "hardhat")
	var bubble := Label3D.new()
	bubble.text = "sorry."
	bubble.font = UiKit.strong_font
	bubble.font_size = 64
	bubble.pixel_size = 0.004
	bubble.modulate = UiKit.TEXT
	bubble.outline_size = 14
	bubble.outline_modulate = Color(0, 0, 0, 0.85)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.position = c + Vector3(-0.5, 0.95, 0.6)
	st.world.add_child(bubble)
	_key(c + Vector3(0, 3.4, 1.2), 7.0)
	_cam(c + Vector3(0.3, 0.75, 2.6), c + Vector3(0.0, 0.35, 0.3), 46.0)

func _mask(ch: LabCharacter) -> void:
	var scn: Node3D = load(ArenaMinigame3D.PH_MOD + "old_gas_mask/old_gas_mask.gltf").instantiate()
	var sk := ch.skeleton
	var hb := sk.find_bone("Head")
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	sk.add_child(att)
	var face := Node3D.new()
	att.add_child(face)
	var head_rest: Transform3D = sk.global_transform * sk.get_bone_global_rest(hb)
	face.transform = head_rest.affine_inverse() * Transform3D(ch.global_transform.basis.orthonormalized(), head_rest.origin)
	var wp := Node3D.new()
	wp.position = Vector3(0.0, 0.075, 0.065)
	wp.scale = Vector3.ONE * 1.1
	face.add_child(wp)
	wp.add_child(scn)

func _stage_screamy() -> void:
	for i in 3:
		var ch := _subject(c + Vector3((i - 1) * 0.85, 0, absf(i - 1) * -0.15), (1 - i) * 8.0, i + 2, "beanie" if i != 1 else "hardhat", "Idle_FoldArms" if i != 1 else "Idle")
		_mask(ch)
	_sign("QUIET\nPLEASE", c + Vector3(1.9, 1.5, -0.6), -12.0, 0.9, 0.62, 96, UiKit.TEXT)
	_key(c + Vector3(0, 3.6, 1.6), 7.0)
	_cam(c + Vector3(0.4, 1.55, 3.6), c + Vector3(0.35, 1.25, 0.0), 40.0)

func _stage_survival() -> void:
	_subject(c, 0.0, 2, "party", "Dance")
	_corpse(c + Vector3(-1.2, 0, -0.4), 40.0, 0)
	_corpse(c + Vector3(1.25, 0, -0.2), -60.0, 1)
	_corpse(c + Vector3(-0.6, 0, 0.9), 120.0, 3)
	_corpse(c + Vector3(0.9, 0, 0.9), -150.0, 5)
	_key(c + Vector3(0, 3.6, 0.6), 9.0)
	_cam(c + Vector3(0, 1.9, 3.4), c + Vector3(0, 0.75, 0), 46.0)

func _stage_hiring() -> void:
	_corpse(c + Vector3(-0.3, 0, 0.4), 80.0, 4, "hardhat")
	_sign("NOW\nHIRING", c + Vector3(0.75, 1.15, 0.1), -14.0, 0.95, 0.66, 110, UiKit.ACCENT)
	st.prop("WetFloorSign_01", c + Vector3(-1.3, 0, -0.2), 30.0, 1.1)
	_key(c + Vector3(0.2, 3.4, 1.4), 8.0)
	_cam(c + Vector3(0.1, 1.45, 3.4), c + Vector3(0.1, 0.6, 0.2), 42.0)

func _stage_hr() -> void:
	_subject(c + Vector3(-1.1, 0, 0.1), 15.0, 0, "party", "Dance")
	_subject(c + Vector3(0.0, 0, 0.3), 0.0, 3, "party", "Dance", "female")
	_subject(c + Vector3(1.1, 0, 0.1), -15.0, 6, "beanie", "Idle_FoldArms")
	_sign("FUN IS\nMANDATORY", c + Vector3(0, 2.3, -0.8), 0.0, 1.5, 0.7, 92, UiKit.ACCENT, false)
	_key(c + Vector3(0, 3.6, 1.4), 8.0)
	_cam(c + Vector3(0, 1.75, 4.3), c + Vector3(0, 1.4, 0), 42.0)

func _stage_lost() -> void:
	var crate := st.prop("wooden_crate_01", c + Vector3(0.0, 0, 0.0), 12.0, 1.0)
	var hat: Node3D = load("res://assets/hats/hat_tophat.glb").instantiate()
	st.world.add_child(hat)
	var top := 0.62
	var aabb := _bounds(crate)
	if aabb.size != Vector3.ZERO:
		top = aabb.end.y
	hat.position = c + Vector3(0.0, top, 0.05)
	hat.rotation_degrees = Vector3(0, 30, 8)
	hat.scale = Vector3.ONE * 1.5
	_steam(c + Vector3(0, top + 0.25, 0.05))
	_sign("LOST AND FOUND", c + Vector3(0, 1.75, -0.7), 0.0, 1.6, 0.36, 72, UiKit.TEXT, false)
	_key(c + Vector3(0.3, 3.2, 1.2), 8.0)
	_cam(c + Vector3(0.2, 1.4, 2.7), c + Vector3(0, 0.95, 0), 42.0)

func _steam(at: Vector3) -> void:
	for i in 3:
		var q := QuadMesh.new()
		q.size = Vector2(0.35, 0.5)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = Fx._soft_tex()
		m.albedo_color = Color(0.85, 0.82, 0.78, 0.32 - i * 0.07)
		q.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = q
		st.world.add_child(mi)
		mi.position = at + Vector3(sin(i * 2.1) * 0.08, i * 0.28, 0)
		mi.scale = Vector3.ONE * (1.0 + i * 0.5)

func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

func _stage_cafeteria() -> void:
	var tm: Node = load("res://minigames/table_manners/table_manners.gd").new()
	tm.world = st.world
	tm.env = st.env
	tm.camera = st.camera
	tm._tune_light()
	tm._lib = tm._make_lib()
	tm._build_room()
	tm._build_table()
	tm._build_boss()
	tm._boss.play_loop("Pistol_Idle")
	await get_tree().process_frame
	tm.free()
	_cam(Vector3(0.0, 1.55, 1.2), Vector3(0.0, 1.15, -1.75), 38.0)

func _stage_safety() -> void:
	_sign("DAYS WITHOUT\nINCIDENT", c + Vector3(-0.35, 1.6, -0.8), 0.0, 1.5, 0.62, 80, UiKit.TEXT, false)
	_sign("0", c + Vector3(0.75, 1.6, -0.8), 0.0, 0.62, 0.62, 200, UiKit.DANGER, false)
	_corpse(c + Vector3(0.1, 0, 0.2), 95.0, 5, "hardhat")
	st.prop("korean_fire_extinguisher_01", c + Vector3(-1.0, 0, -0.5), 20.0, 1.0)
	_key(c + Vector3(0, 3.6, 1.2), 8.0)
	_cam(c + Vector3(0, 1.45, 3.4), c + Vector3(0.1, 0.85, 0), 44.0)
