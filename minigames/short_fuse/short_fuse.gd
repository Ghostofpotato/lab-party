extends ArenaMinigame3D
## Short Fuse: every subject wears an explosive collar with a blinking red LED and a
## countdown. Reach a wall terminal and hold SPACE for 0.8 s to reset your collar; each
## reset gives a shorter fuse than the last (12, 11, 10 ... min 5) and the terminal locks
## out for 4 s. SPACE next to a rival who is at a terminal shoves them off it.
## A collar at zero blows the head off. Last subject alive wins, otherwise the round
## ends after 50 s and survivors rank by remaining fuse, then by who blew up last.

const TIME_LIMIT: float = 50.0
const START_DELAY: float = 1.5
const FW: float = 20.0
const FD: float = 12.0
const FULL_T: float = 12.0
const MIN_T: float = 5.0
const T_STEP: float = 1.0
const HOLD_T: float = 0.8
const LOCK_T: float = 4.0
const AT_R: float = 0.95
const SHOVE_R: float = 1.5
const SHOVE_CD: float = 0.9
const STUN_T: float = 0.7
const BOT_SPEED: float = 4.6
const COL_READY := Color(0.25, 1.0, 0.4)
const COL_BUSY := Color(1.0, 0.75, 0.2)
const COL_LOCK := Color(1.0, 0.1, 0.08)

var terms: Array = []
var lock_left: Array[float] = []
var user_of: Array[int] = []
var term_state: Array[int] = []
var obst: Array[Rect2] = []
var obst_raw: Array[Rect2] = []

var timers: Dictionary = {}
var max_t: Dictionary = {}
var resets: Dictionary = {}
var holding: Dictionary = {}
var hold_p: Dictionary = {}
var hold_term: Dictionary = {}
var stun: Dictionary = {}
var shove_cd: Dictionary = {}
var immune: Dictionary = {}
var collars: Dictionary = {}
var beep_sec: Dictionary = {}
var go_at: Dictionary = {}
var aggro: Dictionary = {}
var bot_target: Dictionary = {}
var bot_retarget: Dictionary = {}
var bot_press_t: Dictionary = {}
var bot_wander: Dictionary = {}
var bot_wander_t: Dictionary = {}
var bot_last: Dictionary = {}
var bot_stuck: Dictionary = {}
var bot_nudge: Dictionary = {}
var bot_noise: Dictionary = {}
var elim_order: Array = []

var _clock: float = 0.0
var _running: bool = false
var _over: bool = false
var _done: bool = false
var _space_down: bool = false
var _sync_t: float = 0.0
var _hud_t: float = 0.0
var _hud_big: Label
var _hud_status: Label
var _hud_help: Label
var _hud_board: Label
var _hud_bar_bg: ColorRect
var _hud_bar: ColorRect

func begin() -> void:
	setup_arena(false)
	env.tonemap_exposure = 1.0
	env.ambient_light_energy = 0.55
	env.fog_density = 0.01
	camera.fov = 46.0
	camera.position = Vector3(FW * 0.5, 11.4, FD + 7.4)
	camera.look_at(Vector3(FW * 0.5, 0.0, FD * 0.5 + 0.3), Vector3.UP)
	_build_set()
	spawn_players(_spawns())
	var i := 0
	for id in players:
		var p: LabPlayer3D = players[id]
		p.bounds = AABB(Vector3(0.5, -5.0, 0.5), Vector3(FW - 1.0, 20.0, FD - 1.0))
		p.face(Vector3(FW * 0.5, 0.0, FD * 0.5) - p.position)
		timers[id] = FULL_T
		max_t[id] = FULL_T
		resets[id] = 0
		holding[id] = false
		hold_p[id] = 0.0
		hold_term[id] = -1
		stun[id] = 0.0
		shove_cd[id] = 0.0
		immune[id] = 0.0
		beep_sec[id] = 99
		go_at[id] = _roll_go()
		aggro[id] = randf() < 0.45
		bot_target[id] = -1
		bot_retarget[id] = 0.0
		bot_press_t[id] = 0.0
		bot_wander[id] = p.position
		bot_wander_t[id] = 0.0
		bot_last[id] = p.position
		bot_stuck[id] = 0.0
		bot_nudge[id] = 0.0
		var nz: Array[float] = []
		for k in terms.size():
			nz.append(randf_range(0.0, 2.5))
		bot_noise[id] = nz
		p.bot_brain = _bot_brain.bind(id)
		_add_collar(id, i)
		i += 1
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _spawns() -> Array:
	var pts: Array = [Vector3(6.5, 0, 2.2), Vector3(13.5, 0, 2.2), Vector3(10.0, 0, 6.0), Vector3(3.6, 0, 7.4),
		Vector3(16.5, 0, 6.0), Vector3(8.0, 0, 10.2), Vector3(12.5, 0, 8.9), Vector3(6.4, 0, 7.8)]
	var a: Array = []
	for k in NetworkManager.players.size():
		a.append(pts[k % pts.size()])
	return a

func _roll_go() -> float:
	if randf() < 0.2:
		return randf_range(2.4, 3.4)
	return randf_range(4.0, 6.2)

func _build_set() -> void:
	var set_root := Node3D.new()
	set_root.name = "MaintenanceFloor"
	world.add_child(set_root)
	var h := 6.6
	var brick := mat("dark_brick_wall", 0.4, Color(0.8, 0.76, 0.7))
	var band := mat("green_metal_rust", 0.6, Color(0.7, 0.72, 0.66))
	var steel := mat("rusty_metal_02", 1.2)
	box(Vector3(FW + 8.0, 0.2, FD + 8.0), Vector3(FW * 0.5, -0.1, FD * 0.5 + 0.5), mat("garage_floor", 0.3, Color(0.78, 0.74, 0.68)), set_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4412
	for k in 12:
		var tex: String = ["dirty_concrete", "damaged_concrete_floor", "hangar_concrete_floor"][k % 3]
		box(Vector3(rng.randf_range(1.5, 3.5), 0.02, rng.randf_range(1.2, 2.6)), Vector3(rng.randf_range(1.0, FW - 1.0), 0.011, rng.randf_range(1.0, FD - 1.0)), mat(tex, 0.3, Color(0.7, 0.66, 0.6)), set_root)
	box(Vector3(FW + 8.0, h, 0.4), Vector3(FW * 0.5, h * 0.5, -0.8), brick, set_root)
	box(Vector3(0.4, h, FD + 4.0), Vector3(-0.8, h * 0.5, FD * 0.5 + 1.0), brick, set_root)
	box(Vector3(0.4, h, FD + 4.0), Vector3(FW + 0.8, h * 0.5, FD * 0.5 + 1.0), brick, set_root)
	box(Vector3(FW + 8.0, 1.3, 0.5), Vector3(FW * 0.5, 0.65, -0.65), band, set_root)
	box(Vector3(0.5, 1.3, FD + 4.0), Vector3(-0.65, 0.65, FD * 0.5 + 1.0), band, set_root)
	box(Vector3(0.5, 1.3, FD + 4.0), Vector3(FW + 0.65, 0.65, FD * 0.5 + 1.0), band, set_root)
	box(Vector3(FW + 8.0, 0.6, 0.3), Vector3(FW * 0.5, 0.3, FD + 3.0), band, set_root)
	var pipe_mat := mat("rusty_metal_02", 1.5)
	for y in [4.3, 4.75]:
		var pipe := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.15
		cm.bottom_radius = 0.15
		cm.height = FW + 4.0
		pipe.mesh = cm
		pipe.material_override = pipe_mat
		pipe.rotation_degrees.z = 90.0
		pipe.position = Vector3(FW * 0.5, y, -0.4)
		set_root.add_child(pipe)
	for x in [3.0, 9.0, 16.5]:
		box(Vector3(0.12, 0.5, 0.5), Vector3(x, 4.5, -0.4), steel, set_root)
	prop("modular_pipes", Vector3(FW * 0.5 - 1.0, 3.2, -0.45), 0.0, 1.5, set_root)
	prop("fire_alarm", Vector3(11.8, 2.3, -0.5), 0.0, 1.6, set_root)
	prop("wall_clock", Vector3(9.9, 3.5, -0.55), 0.0, 2.2, set_root)
	prop("industrial_caged_sconce", Vector3(7.0, 2.9, -0.5), 0.0, 1.6, set_root)
	prop("industrial_caged_sconce", Vector3(13.0, 2.9, -0.5), 0.0, 1.6, set_root)
	prop("security_camera_01", Vector3(FW + 0.4, 4.6, 0.2), -135.0, 1.6, set_root)
	prop("large_iron_gate", Vector3(-0.55, 0.0, 5.6), 90.0, 1.2, set_root)
	var deco := [["wooden_crate_01", -1.4, 3.0, 10, 1.3], ["barrel_03", FW + 1.4, 9.0, 0, 1.2], ["cement_bag", FW + 1.6, 6.5, 40, 1.2],
		["trashbag", -1.5, 10.5, 0, 1.2], ["hand_truck", -1.6, FD + 0.6, 80, 1.2], ["cardboard_box_01", 4.0, FD + 1.5, 15, 1.2],
		["plastic_crate_01", 7.0, FD + 1.6, -10, 1.8], ["propane_tank", 11.0, FD + 1.5, 0, 1.2], ["old_tyre", 13.5, FD + 1.4, 0, 1.2],
		["metal_jerrycan", 16.0, FD + 1.5, 70, 1.2], ["WetFloorSign_01", 6.2, 5.2, 25, 1.2], ["pipe_wrench", 12.2, 3.6, 40, 1.4],
		["can_rusted", 8.4, 8.4, 0, 1.5], ["sledgehammer_01", 17.0, 1.4, 20, 1.2], ["bleach_bottle", FW + 1.5, 11.0, 0, 1.2]]
	for d in deco:
		var n := prop(d[0], Vector3(d[1], 0.0, d[2]), d[3], d[4], set_root)
		if n and d[0] == "sledgehammer_01":
			n.rotation_degrees = Vector3(0.0, 20.0, 80.0)
			n.position.y = 0.12
		if n and d[0] == "pipe_wrench":
			n.rotation_degrees = Vector3(80.0, 40.0, 0.0)
			n.position.y = 0.04
	_build_obstacles(set_root)
	_build_terminals(set_root)
	lamp(Vector3(5.0, 6.0, 4.2), 10.0, Color(1.0, 0.8, 0.55), set_root)
	lamp(Vector3(15.0, 6.0, 4.6), 10.0, Color(1.0, 0.8, 0.55), set_root)
	lamp(Vector3(10.0, 6.0, 9.4), 10.0, Color(1.0, 0.82, 0.6), set_root)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.55, 0.75, 0.6)
	fill.light_energy = 1.2
	fill.omni_range = 16.0
	set_root.add_child(fill)
	fill.position = Vector3(FW * 0.5, 3.4, 1.0)

func _obstacle(id: String, x: float, z: float, yaw: float, sc: float, foot: Vector2, y: float = 0.0, solid: bool = true) -> void:
	var holder := world.get_node("MaintenanceFloor")
	prop(id, Vector3(x, y, z), yaw, sc, holder)
	if not solid:
		return
	var turned := absf(sin(deg_to_rad(yaw))) > 0.7
	var sx: float = (foot.y if turned else foot.x) * sc
	var sz: float = (foot.x if turned else foot.y) * sc
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(sx, 1.6, sz)
	cs.shape = sh
	sb.add_child(cs)
	sb.position = Vector3(x, 0.8, z)
	holder.add_child(sb)
	var r := Rect2(x - sx * 0.5, z - sz * 0.5, sx, sz)
	obst_raw.append(r)
	obst.append(r.grow(0.55))

func _build_obstacles(_set_root: Node3D) -> void:
	_obstacle("concrete_road_barrier", 10.0, 3.2, 0.0, 1.3, Vector2(1.55, 0.64))
	_obstacle("concrete_road_barrier", 10.0, 9.0, 0.0, 1.3, Vector2(1.55, 0.64))
	_obstacle("drawer_cabinet", 7.0, 6.0, 90.0, 1.3, Vector2(1.14, 0.49))
	_obstacle("worn_metal_rack", 13.0, 6.0, 90.0, 1.3, Vector2(0.92, 0.6))
	_obstacle("portable_generator", 3.5, 4.5, 0.0, 1.4, Vector2(0.82, 0.56))
	_obstacle("portable_welding_cart", 16.5, 8.2, 0.0, 1.4, Vector2(0.84, 0.65))
	_obstacle("tool_cart", 5.5, 9.6, 0.0, 1.3, Vector2(1.27, 0.75))
	_obstacle("vintage_cabinet_01", 14.5, 10.9, 0.0, 1.0, Vector2(2.02, 0.65))
	_obstacle("steel_frame_shelves_03", 10.0, 0.0, 0.0, 1.0, Vector2(2.35, 0.98))
	_obstacle("wooden_military_crate", 1.8, 6.5, 90.0, 1.3, Vector2(1.24, 0.73))
	_obstacle("wooden_military_crate", 1.8, 6.5, 80.0, 1.3, Vector2(1.24, 0.73), 0.55, false)
	_obstacle("barrel_03", 17.8, 10.6, 0.0, 1.2, Vector2(0.64, 0.64))
	_obstacle("barrel_03", 18.6, 10.0, 40.0, 1.2, Vector2(0.64, 0.64))
	_obstacle("barrel_03", 18.4, 11.0, 0.0, 1.2, Vector2(0.64, 0.64))
	_obstacle("metal_trash_can", 1.4, 2.4, 0.0, 1.3, Vector2(0.61, 0.56))
	_obstacle("old_military_crate", 12.0, 10.0, 0.0, 1.3, Vector2(0.93, 0.68))
	_obstacle("cardboard_box_01", 12.0, 10.0, 15.0, 1.2, Vector2(0.39, 0.52), 0.47, false)
	_obstacle("metal_tool_chest", 18.4, 1.6, 90.0, 1.3, Vector2(0.69, 0.32))

func _build_terminals(set_root: Node3D) -> void:
	var defs: Array = [
		{"root": Vector3(4.5, 0.0, -0.6), "yaw": 0.0},
		{"root": Vector3(15.5, 0.0, -0.6), "yaw": 0.0},
		{"root": Vector3(-0.6, 0.0, 8.5), "yaw": 90.0},
		{"root": Vector3(FW + 0.6, 0.0, 4.0), "yaw": -90.0},
	]
	var body_mat := mat("green_metal_rust", 0.8, Color(0.62, 0.66, 0.6))
	var dark := mat("rusty_metal", 1.0, Color(0.22, 0.21, 0.2))
	for d in defs:
		var root := Node3D.new()
		root.position = d.root
		root.rotation_degrees.y = d.yaw
		set_root.add_child(root)
		var yaw_r: float = deg_to_rad(d.yaw)
		var out := Vector3(sin(yaw_r), 0.0, cos(yaw_r))
		box(Vector3(1.6, 1.9, 0.5), Vector3(0.0, 0.95, 0.25), body_mat, root)
		box(Vector3(1.75, 0.12, 0.62), Vector3(0.0, 1.94, 0.28), dark, root)
		box(Vector3(1.24, 0.9, 0.05), Vector3(0.0, 1.4, 0.52), dark, root)
		var screen_mat := StandardMaterial3D.new()
		screen_mat.albedo_color = Color(0.03, 0.06, 0.04)
		screen_mat.emission_enabled = true
		screen_mat.emission = COL_READY
		screen_mat.emission_energy_multiplier = 0.9
		var screen := box(Vector3(1.1, 0.74, 0.05), Vector3(0.0, 1.4, 0.54), screen_mat, root)
		screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		box(Vector3(1.14, 0.12, 0.04), Vector3(0.0, 0.88, 0.53), dark, root)
		var bar_pivot := Node3D.new()
		bar_pivot.position = Vector3(-0.5, 0.88, 0.56)
		root.add_child(bar_pivot)
		var bar_mat := StandardMaterial3D.new()
		bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bar_mat.albedo_color = Color(1.0, 0.9, 0.3)
		var bar := box(Vector3(1.0, 0.07, 0.02), Vector3(0.5, 0.0, 0.0), bar_mat, bar_pivot)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar_pivot.scale.x = 0.001
		var lbl := Label3D.new()
		lbl.text = "RESET"
		lbl.font_size = 64
		lbl.pixel_size = 0.0045
		lbl.outline_size = 10
		lbl.position = Vector3(0.0, 1.62, 0.58)
		lbl.modulate = COL_READY
		root.add_child(lbl)
		var sub := Label3D.new()
		sub.text = "HOLD SPACE"
		sub.font_size = 44
		sub.pixel_size = 0.0038
		sub.outline_size = 8
		sub.position = Vector3(0.0, 1.22, 0.58)
		sub.modulate = COL_READY
		root.add_child(sub)
		for kx in [-0.62, 0.62]:
			box(Vector3(0.1, 1.7, 0.1), Vector3(kx, 0.85, 0.55), dark, root)
		prop("power_box_01", Vector3(1.25, 1.5, 0.07), 0.0, 1.5, root)
		prop("utility_box_01", Vector3(-1.4, 0.0, 0.3), 0.0, 1.3, root)
		var pad_mat := mat("rubber_tiles", 1.6, Color(0.9, 0.78, 0.3)).duplicate()
		pad_mat.emission_enabled = true
		pad_mat.emission = COL_READY
		pad_mat.emission_energy_multiplier = 0.45
		box(Vector3(1.5, 0.03, 1.3), Vector3(0.0, 0.015, 1.3), pad_mat, root)
		var glow := OmniLight3D.new()
		glow.light_color = COL_READY
		glow.light_energy = 1.4
		glow.omni_range = 3.4
		root.add_child(glow)
		glow.position = Vector3(0.0, 1.6, 1.0)
		var spot: Vector3 = d.root + out * 1.3
		terms.append({"root": root, "out": out, "spot": spot, "screen_mat": screen_mat, "pad_mat": pad_mat,
			"light": glow, "lbl": lbl, "sub": sub, "bar": bar_pivot})
		lock_left.append(0.0)
		user_of.append(-1)
		term_state.append(-1)

func _add_collar(id: int, idx: int) -> void:
	var p: LabPlayer3D = players[id]
	var sk: Skeleton3D = p.body.skeleton
	var bone: int = sk.find_bone("neck_01")
	if bone < 0:
		bone = sk.find_bone("Head")
	var att := BoneAttachment3D.new()
	att.bone_name = sk.get_bone_name(bone)
	sk.add_child(att)
	var rig := Node3D.new()
	att.add_child(rig)
	var rest: Transform3D = sk.global_transform * sk.get_bone_global_rest(bone)
	var want := Transform3D(p.body.global_transform.basis, rest.origin + Vector3(0.0, 0.03, 0.0))
	rig.transform = rest.affine_inverse() * want
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.16, 0.17)
	metal.metallic = 0.7
	metal.roughness = 0.45
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.075
	tm.outer_radius = 0.125
	tm.rings = 24
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = metal
	rig.add_child(ring)
	var charge_mat := StandardMaterial3D.new()
	charge_mat.albedo_color = Color(0.5, 0.1, 0.07)
	charge_mat.roughness = 0.8
	var parts: Array[MeshInstance3D] = []
	for spec in [[Vector3(0.14, 0.1, 0.07), Vector3(0.0, 0.0, 0.135)], [Vector3(0.07, 0.07, 0.07), Vector3(0.125, 0.0, 0.02)], [Vector3(0.07, 0.07, 0.07), Vector3(-0.125, 0.0, 0.02)]]:
		var pack := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		pack.mesh = bm
		pack.material_override = charge_mat
		pack.position = spec[1]
		rig.add_child(pack)
		parts.append(pack)
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.2, 0.0, 0.0)
	led_mat.emission_enabled = true
	led_mat.emission = Color(1.0, 0.05, 0.03)
	led_mat.emission_energy_multiplier = 4.0
	var led := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.024
	sm.height = 0.048
	led.mesh = sm
	led.material_override = led_mat
	led.position = Vector3(0.0, 0.0, 0.175)
	led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(led)
	var lbl := Label3D.new()
	lbl.text = "12.0"
	lbl.font_size = 64
	lbl.pixel_size = 0.0045
	lbl.outline_size = 14
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.shaded = false
	lbl.position = Vector3(0.0, 0.5, 0.0)
	rig.add_child(lbl)
	collars[id] = {"rig": rig, "led": led_mat, "label": lbl, "phase": float(idx) * 0.37, "flash": 0.0, "att": att}

func _build_hud() -> void:
	hud_title("SHORT FUSE  ·  reset your collar before it blows")
	_hud_help = Label.new()
	_hud_help.text = "WASD move  ·  hold SPACE at a green terminal to reset  ·  SPACE beside a rival at a terminal shoves them off"
	_hud_help.position = Vector2(16, 42)
	_style_label(_hud_help, 16, Color("e8e2c8"))
	hud.add_child(_hud_help)
	_hud_big = Label.new()
	_hud_big.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_big.offset_top = 56.0
	_hud_big.offset_bottom = 170.0
	_hud_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_hud_big, 92, Color.WHITE)
	_hud_big.add_theme_constant_override("outline_size", 14)
	hud.add_child(_hud_big)
	_hud_status = Label.new()
	_hud_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_status.offset_top = 172.0
	_hud_status.offset_bottom = 204.0
	_hud_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_hud_status, 20, Color("ffd34a"))
	hud.add_child(_hud_status)
	_hud_bar_bg = ColorRect.new()
	_hud_bar_bg.color = Color(0.0, 0.0, 0.0, 0.6)
	_hud_bar_bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hud_bar_bg.offset_left = -150.0
	_hud_bar_bg.offset_right = 150.0
	_hud_bar_bg.offset_top = 210.0
	_hud_bar_bg.offset_bottom = 226.0
	_hud_bar_bg.visible = false
	hud.add_child(_hud_bar_bg)
	_hud_bar = ColorRect.new()
	_hud_bar.color = Color(1.0, 0.9, 0.3)
	_hud_bar.position = Vector2(2, 2)
	_hud_bar.size = Vector2(0, 12)
	_hud_bar_bg.add_child(_hud_bar)
	_hud_board = Label.new()
	_hud_board.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud_board.offset_left = -240.0
	_hud_board.offset_right = -14.0
	_hud_board.offset_top = 10.0
	_hud_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_label(_hud_board, 16, Color("e8e2c8"))
	hud.add_child(_hud_board)

func _style_label(l: Label, size: int, c: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)

func _fd(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _fuse_color(t: float) -> Color:
	if t > 6.0:
		return Color(0.95, 0.95, 0.9)
	if t > 3.0:
		return Color(1.0, 0.8, 0.2)
	return Color(1.0, 0.22, 0.12)

func _process(delta: float) -> void:
	_clock += delta
	var live := _clock > START_DELAY and not _over
	for id in players:
		var p: LabPlayer3D = players[id]
		if live and p.alive:
			timers[id] = maxf(float(timers[id]) - delta, 0.0)
		_update_collar(id, delta)
	for i in terms.size():
		if lock_left[i] > 0.0:
			lock_left[i] = maxf(lock_left[i] - delta, 0.0)
		_update_terminal(i)
	if NetworkManager.is_server():
		_sync_t -= delta
		if _sync_t <= 0.0 and live:
			_sync_t = 0.25
			_rpc_sync.rpc(timers.keys(), timers.values())
	_update_hud(delta)
	var lp := local_player()
	if lp and lp.alive and _clock > START_DELAY and not _over:
		var down := Input.is_physical_key_pressed(KEY_SPACE)
		if down != _space_down:
			_space_down = down
			if multiplayer.is_server():
				_req_hold(down)
			else:
				_req_hold.rpc_id(1, down)

func _update_collar(id: int, delta: float) -> void:
	var c: Dictionary = collars[id]
	var p: LabPlayer3D = players[id]
	var lbl: Label3D = c.label
	var led: StandardMaterial3D = c.led
	if not p.alive:
		return
	var t: float = timers[id]
	lbl.text = "%.1f" % t
	lbl.modulate = _fuse_color(t)
	var flash: float = c.flash
	if flash > 0.0:
		c.flash = flash - delta
		led.emission = Color(0.1, 1.0, 0.3)
		led.emission_energy_multiplier = 5.0
		return
	var freq: float = 1.4 + (FULL_T - minf(t, FULL_T)) * 0.5
	if t < 2.0:
		freq = 9.0
	c.phase = float(c.phase) + delta * freq
	var on: bool = fmod(float(c.phase), 1.0) < 0.5
	led.emission = Color(1.0, 0.05, 0.03)
	led.emission_energy_multiplier = 5.0 if on else 0.15
	if _clock > START_DELAY and t <= 3.0 and t > 0.0:
		var sec: int = ceili(t)
		if sec != int(beep_sec[id]):
			beep_sec[id] = sec
			Fx.sfx("beep", p.position, -8.0, 1.0 + (3.0 - t) * 0.12)

func _update_terminal(i: int) -> void:
	var tm: Dictionary = terms[i]
	var st := 0
	if lock_left[i] > 0.0:
		st = 2
	elif user_of[i] != -1:
		st = 1
	var lbl: Label3D = tm.lbl
	var sub: Label3D = tm.sub
	if st == 2:
		sub.text = "LOCKED %.1f" % lock_left[i]
	if st == term_state[i]:
		return
	term_state[i] = st
	var col := COL_READY
	match st:
		1:
			col = COL_BUSY
			sub.text = "RESETTING"
			lbl.text = "BUSY"
		2:
			col = COL_LOCK
			lbl.text = "OFFLINE"
		_:
			sub.text = "HOLD SPACE"
			lbl.text = "RESET"
	lbl.modulate = col
	sub.modulate = col
	var sm: StandardMaterial3D = tm.screen_mat
	sm.emission = col
	var pm: StandardMaterial3D = tm.pad_mat
	pm.emission = col
	var light: OmniLight3D = tm.light
	light.light_color = col

func _update_hud(_delta: float) -> void:
	_hud_help.modulate.a = clampf(10.0 - _clock, 0.0, 1.0)
	var me := multiplayer.get_unique_id()
	if not players.has(me):
		return
	var p: LabPlayer3D = players[me]
	var t: float = timers[me]
	if p.alive:
		_hud_big.text = "%.1f" % t
		var pulse := 1.0
		if t < 3.0:
			pulse = 0.7 + 0.3 * absf(sin(_clock * 10.0))
		_hud_big.add_theme_color_override("font_color", _fuse_color(t) * pulse)
		var nxt: float = maxf(MIN_T, float(max_t[me]) - T_STEP)
		if holding[me]:
			_hud_status.text = "RESETTING"
		elif t < 5.0:
			_hud_status.text = "RUN TO A GREEN TERMINAL"
		else:
			_hud_status.text = "next reset gives %d s" % int(nxt)
		_hud_bar_bg.visible = holding[me]
		_hud_bar.size.x = 296.0 * clampf(float(hold_p[me]) / HOLD_T, 0.0, 1.0)
	else:
		_hud_big.text = "BOOM"
		_hud_big.add_theme_color_override("font_color", COL_LOCK)
		_hud_status.text = "your head is somewhere else"
		_hud_bar_bg.visible = false
	_hud_t -= _delta
	if _hud_t > 0.0:
		return
	_hud_t = 0.2
	var ids: Array = players.keys()
	ids.sort_custom(func(a, b): return float(timers[a]) > float(timers[b]) if players[a].alive == players[b].alive else players[a].alive)
	var lines: Array = []
	for id in ids:
		var q: LabPlayer3D = players[id]
		if q.alive:
			lines.append("%s  %.1f" % [q.display_name, float(timers[id])])
		else:
			lines.append("† %s" % q.display_name)
	_hud_board.text = "FUSES\n" + "\n".join(lines)

func _run() -> void:
	await get_tree().create_timer(START_DELAY).timeout
	_running = true
	var t := 0.0
	while alive_ids().size() > 1 and t < TIME_LIMIT:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	_running = false
	_over = true
	_rpc_over.rpc()
	await get_tree().create_timer(1.3).timeout
	if not _done:
		_done = true
		finished.emit(_placement())

func _placement() -> Array:
	var alive: Array = alive_ids()
	alive.sort_custom(func(a, b): return float(timers[a]) > float(timers[b]))
	var out: Array = alive.duplicate()
	for i in range(elim_order.size() - 1, -1, -1):
		if not out.has(elim_order[i]):
			out.append(elim_order[i])
	for id in players:
		if not out.has(id):
			out.append(id)
	return out

func _physics_process(delta: float) -> void:
	if not NetworkManager.is_server() or not _running:
		return
	for id in players:
		stun[id] = maxf(float(stun[id]) - delta, 0.0)
		shove_cd[id] = maxf(float(shove_cd[id]) - delta, 0.0)
		immune[id] = maxf(float(immune[id]) - delta, 0.0)
	for id in alive_ids():
		if float(timers[id]) <= 0.0:
			_detonate(id)
			continue
		if holding[id]:
			_tick_hold(id, delta)

func _detonate(id: int) -> void:
	if holding[id]:
		holding[id] = false
		user_of[hold_term[id]] = -1
	elim_order.append(id)
	_rpc_explode.rpc(id)

func _term_near(pos: Vector3) -> int:
	var best := -1
	var bd := AT_R
	for i in terms.size():
		var d := _fd(pos, terms[i].spot)
		if d < bd:
			bd = d
			best = i
	return best

func _shove_target(id: int, holders_only: bool) -> int:
	var p: LabPlayer3D = players[id]
	var best := -1
	var bd := SHOVE_R
	for vid in alive_ids():
		if vid == id or float(immune[vid]) > 0.0:
			continue
		var v: LabPlayer3D = players[vid]
		var d := _fd(p.position, v.position)
		if d >= bd:
			continue
		var at_term := bool(holding[vid])
		if not at_term and not holders_only:
			var ti := _term_near(v.position)
			at_term = ti >= 0 and lock_left[ti] <= 0.0
		if at_term:
			bd = d
			best = vid
	return best

func _press(id: int, holders_only: bool) -> void:
	if not _running or not players.has(id):
		return
	var p: LabPlayer3D = players[id]
	if not p.alive or float(stun[id]) > 0.0 or holding[id]:
		return
	var ti := _term_near(p.position)
	if ti >= 0 and lock_left[ti] <= 0.0 and user_of[ti] == -1:
		holding[id] = true
		hold_term[id] = ti
		hold_p[id] = 0.0
		user_of[ti] = id
		_rpc_hold.rpc(id, ti, true)
		return
	if float(shove_cd[id]) > 0.0:
		return
	var victim := _shove_target(id, holders_only)
	if victim >= 0:
		_shove(id, victim)

func _stop_hold(id: int) -> void:
	if not holding[id]:
		return
	holding[id] = false
	var ti: int = hold_term[id]
	if user_of[ti] == id:
		user_of[ti] = -1
	hold_p[id] = 0.0
	_rpc_hold.rpc(id, ti, false)

func _tick_hold(id: int, delta: float) -> void:
	var p: LabPlayer3D = players[id]
	var ti: int = hold_term[id]
	if _fd(p.position, terms[ti].spot) > AT_R + 0.4 or lock_left[ti] > 0.0:
		_stop_hold(id)
		return
	hold_p[id] = float(hold_p[id]) + delta
	_rpc_progress.rpc(ti, float(hold_p[id]) / HOLD_T)
	if float(hold_p[id]) >= HOLD_T:
		holding[id] = false
		hold_p[id] = 0.0
		resets[id] = int(resets[id]) + 1
		max_t[id] = maxf(MIN_T, float(max_t[id]) - T_STEP)
		timers[id] = max_t[id]
		user_of[ti] = -1
		lock_left[ti] = LOCK_T
		go_at[id] = _roll_go()
		_rpc_reset.rpc(id, ti, float(timers[id]), float(max_t[id]))

func _shove(id: int, victim: int) -> void:
	var p: LabPlayer3D = players[id]
	var v: LabPlayer3D = players[victim]
	shove_cd[id] = SHOVE_CD
	var out := Vector3.ZERO
	if holding[victim]:
		out = terms[hold_term[victim]].out
	else:
		var ti := _term_near(v.position)
		if ti >= 0:
			out = terms[ti].out
	_stop_hold(victim)
	stun[victim] = STUN_T
	immune[victim] = 1.6
	if out != Vector3.ZERO:
		var vt := _term_near(v.position)
		if vt >= 0:
			var nz: Array = bot_noise[victim]
			nz[vt] = float(nz[vt]) + 7.0
	bot_target[victim] = -1
	var dir := Vector3(v.position.x - p.position.x, 0.0, v.position.z - p.position.z)
	if dir.length() < 0.05:
		dir = out
	dir = (dir.normalized() * 0.6 + out).normalized()
	_rpc_shove.rpc(id, victim, dir)

@rpc("any_peer", "call_local", "reliable")
func _req_hold(on: bool) -> void:
	if not multiplayer.is_server() or not _running:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	if not players.has(id):
		return
	if on:
		_press(id, false)
	else:
		_stop_hold(id)

func _bot_brain(delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	if not _running or float(stun[id]) > 0.0 or holding[id]:
		return Vector3.ZERO
	bot_press_t[id] = maxf(float(bot_press_t[id]) - delta, 0.0)
	bot_retarget[id] = float(bot_retarget[id]) - delta
	var moved := _fd(p.position, bot_last[id])
	bot_last[id] = p.position
	if moved < 0.4 * delta * BOT_SPEED:
		bot_stuck[id] = float(bot_stuck[id]) + delta
	else:
		bot_stuck[id] = 0.0
	if float(bot_stuck[id]) > 0.45:
		bot_stuck[id] = 0.0
		bot_nudge[id] = 0.5
		var a := randf() * TAU
		p.bot_dir = Vector3(cos(a), 0.0, sin(a))
	if float(bot_nudge[id]) > 0.0:
		bot_nudge[id] = float(bot_nudge[id]) - delta
		return p.bot_dir
	var t: float = timers[id]
	if t < float(go_at[id]):
		return _bot_reset_run(p, id)
	if aggro[id]:
		var occ := _occupant_other(id)
		if occ >= 0:
			return _bot_chase(p, id, players[occ])
	return _bot_wander(p, id, delta)

func _occupant_other(id: int) -> int:
	var best := -1
	var bd := INF
	var p: LabPlayer3D = players[id]
	for i in terms.size():
		var u: int = user_of[i]
		if u != -1 and u != id and players[u].alive:
			var d := _fd(p.position, players[u].position)
			if d < bd:
				bd = d
				best = u
	return best

func _bot_reset_run(p: LabPlayer3D, id: int) -> Vector3:
	if float(bot_retarget[id]) <= 0.0 or int(bot_target[id]) < 0:
		bot_retarget[id] = 0.5
		bot_target[id] = _pick_terminal(p, id)
	var ti: int = bot_target[id]
	if ti < 0:
		return Vector3.ZERO
	var occ: int = user_of[ti]
	if occ != -1 and occ != id and players[occ].alive:
		return _bot_chase(p, id, players[occ])
	var spot: Vector3 = terms[ti].spot
	if _fd(p.position, spot) < AT_R - 0.2:
		if float(bot_press_t[id]) <= 0.0:
			bot_press_t[id] = 0.3
			_press(id, true)
		return Vector3.ZERO
	return _steer(p.position, spot)

func _bot_chase(p: LabPlayer3D, id: int, target: LabPlayer3D) -> Vector3:
	var d := _fd(p.position, target.position)
	if d < SHOVE_R - 0.35:
		if float(bot_press_t[id]) <= 0.0:
			bot_press_t[id] = 0.3
			_press(id, true)
		p.face(target.position - p.position)
		return Vector3.ZERO
	return _steer(p.position, target.position)

func _bot_wander(p: LabPlayer3D, id: int, delta: float) -> Vector3:
	bot_wander_t[id] = float(bot_wander_t[id]) - delta
	var goal: Vector3 = bot_wander[id]
	if float(bot_wander_t[id]) <= 0.0 or _fd(p.position, goal) < 0.7:
		bot_wander_t[id] = randf_range(1.5, 3.2)
		for k in 8:
			goal = Vector3(randf_range(2.0, FW - 2.0), 0.0, randf_range(2.0, FD - 1.5))
			if not _in_obstacle(goal):
				break
		bot_wander[id] = goal
	return _steer(p.position, goal) * 0.55

func _in_obstacle(pos: Vector3) -> bool:
	for r in obst:
		if r.has_point(Vector2(pos.x, pos.z)):
			return true
	return false

func _pick_terminal(p: LabPlayer3D, id: int) -> int:
	var best := -1
	var bc := INF
	var noise: Array = bot_noise[id]
	for i in terms.size():
		var d := _fd(p.position, terms[i].spot)
		var eta := d / BOT_SPEED
		if lock_left[i] > eta + 0.3 and lock_left[i] > 0.0:
			continue
		var cost := d + float(noise[i])
		if user_of[i] != -1 and user_of[i] != id:
			cost += 5.0
		if cost < bc:
			bc = cost
			best = i
	if best < 0:
		var wd := INF
		for i in terms.size():
			var w := _fd(p.position, terms[i].spot) + lock_left[i] * BOT_SPEED
			if w < wd:
				wd = w
				best = i
	return best

func _seg_hits(a: Vector3, b: Vector3, r: Rect2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := Vector2(b.x - a.x, b.z - a.z)
	var o := Vector2(a.x, a.z)
	for ax in 2:
		var lo: float = r.position[ax]
		var hi: float = r.end[ax]
		if absf(d[ax]) < 0.0001:
			if o[ax] < lo or o[ax] > hi:
				return false
		else:
			var ta: float = (lo - o[ax]) / d[ax]
			var tb: float = (hi - o[ax]) / d[ax]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
	return true

func _steer(from: Vector3, goal: Vector3) -> Vector3:
	var target := goal
	for hop in 2:
		var blocker := -1
		var bd := INF
		for i in obst.size():
			if _seg_hits(from, target, obst[i]):
				var d := _fd(from, Vector3(obst[i].get_center().x, 0.0, obst[i].get_center().y))
				if d < bd:
					bd = d
					blocker = i
		if blocker < 0:
			break
		var rr: Rect2 = obst[blocker].grow(0.3)
		var best_c := target
		var best_cost := INF
		for c in [rr.position, rr.end, Vector2(rr.position.x, rr.end.y), Vector2(rr.end.x, rr.position.y)]:
			var cv: Vector2 = c
			if cv.x < 0.5 or cv.x > FW - 0.5 or cv.y < 0.5 or cv.y > FD - 0.5:
				continue
			var cp := Vector3(cv.x, 0.0, cv.y)
			var cost := _fd(from, cp) + _fd(cp, target)
			if cost < best_cost:
				best_cost = cost
				best_c = cp
		target = best_c
	var dir := Vector3(target.x - from.x, 0.0, target.z - from.z)
	if dir.length() < 0.05:
		return Vector3.ZERO
	return dir.normalized()

@rpc("authority", "unreliable")
func _rpc_sync(ids: Array, vals: Array) -> void:
	for k in ids.size():
		if timers.has(ids[k]):
			timers[ids[k]] = vals[k]

@rpc("authority", "call_local", "reliable")
func _rpc_over() -> void:
	_over = true

@rpc("authority", "call_local", "unreliable")
func _rpc_progress(ti: int, f: float) -> void:
	var bar: Node3D = terms[ti].bar
	bar.scale.x = clampf(f, 0.001, 1.0)
	var u: int = user_of[ti]
	if u != -1 and players.has(u):
		hold_p[u] = clampf(f, 0.0, 1.0) * HOLD_T

@rpc("authority", "call_local", "reliable")
func _rpc_hold(id: int, ti: int, on: bool) -> void:
	var p: LabPlayer3D = players[id]
	var bar: Node3D = terms[ti].bar
	holding[id] = on
	hold_term[id] = ti
	if on:
		user_of[ti] = id
		hold_p[id] = 0.0
		p.face(-terms[ti].out)
		p.body.play_action("Interact", 0.1)
		Fx.sfx("click", p.position, -6.0)
	else:
		if user_of[ti] == id:
			user_of[ti] = -1
		hold_p[id] = 0.0
		bar.scale.x = 0.001
		if p.alive:
			p.body.play_loop("Idle")
	if p.is_local_human():
		p.input_enabled = not on

@rpc("authority", "call_local", "reliable")
func _rpc_reset(id: int, ti: int, t: float, mt: float) -> void:
	var p: LabPlayer3D = players[id]
	var tm: Dictionary = terms[ti]
	holding[id] = false
	hold_p[id] = 0.0
	user_of[ti] = -1
	lock_left[ti] = LOCK_T
	timers[id] = t
	max_t[id] = mt
	beep_sec[id] = 99
	var bar: Node3D = tm.bar
	bar.scale.x = 0.001
	collars[id].flash = 0.7
	if p.alive:
		p.body.play_loop("Idle")
	if p.is_local_human():
		p.input_enabled = true
	Fx.sparks(world, tm.spot + Vector3(0.0, 1.3, 0.0) - tm.out * 0.9)
	Fx.sfx("arm", p.position, -4.0, 1.4)

@rpc("authority", "call_local", "reliable")
func _rpc_shove(id: int, victim: int, dir: Vector3) -> void:
	var p: LabPlayer3D = players[id]
	var v: LabPlayer3D = players[victim]
	holding[victim] = false
	p.body.play_action("Punch_Jab", 0.06, 1.3)
	p.face(v.position - p.position)
	v.body.play_action("Hit_Knockback", 0.06)
	Fx.sfx("whoosh", p.position, -4.0)
	Fx.sfx("hit", v.position, 0.0)
	Fx.shake(0.2)
	if v.is_multiplayer_authority():
		var to := v.position + dir * 1.7
		to.x = clampf(to.x, 0.5, FW - 0.5)
		to.z = clampf(to.z, 0.5, FD - 0.5)
		for r in obst_raw:
			if _seg_hits(v.position, to, r.grow(0.35)):
				to = v.position
				break
		var tw := v.create_tween()
		tw.tween_property(v, "position", Vector3(to.x, v.position.y, to.z), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if v.is_local_human():
		v.input_enabled = false
		get_tree().create_timer(0.5).timeout.connect(_unlock.bind(v))

func _unlock(v: LabPlayer3D) -> void:
	if is_instance_valid(v) and v.alive:
		v.input_enabled = true

@rpc("authority", "call_local", "reliable")
func _rpc_explode(id: int) -> void:
	var p: LabPlayer3D = players[id]
	var neck := p.global_position + Vector3(0.0, 1.5, 0.0)
	holding[id] = false
	for i in terms.size():
		if user_of[i] == id:
			user_of[i] = -1
			var bar: Node3D = terms[i].bar
			bar.scale.x = 0.001
	timers[id] = 0.0
	var c: Dictionary = collars[id]
	var rig: Node3D = c.rig
	rig.visible = false
	Fx.explosion(world, neck, 0.45)
	Fx.blood(world, neck, 140)
	eliminate(id, "Death01")
	Fx.shake(0.5)
	if p.is_local_human():
		p.input_enabled = false
