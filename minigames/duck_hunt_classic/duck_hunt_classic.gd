extends ArenaMinigame3D
## Duck Hunt Classic: the original rules. One subject is the Hunter on a tower
## behind the exit gate, everyone else is a Duck at the far end of the yard.
## Ducks run for the gate, crouching behind cover; the hunter cycles a 3 level
## scope (laser only while scoped) and snipes. Body hit = injured and slower,
## second hit or a headshot kills. Every subject is the hunter once. Points per
## round: duck through the gate +1 (first one +2), hunter +1 per kill and +1 for
## a clean sweep. Highest total wins. Full spec in RULES.md.

const START_Z: float = 30.0
const FINISH_Z: float = 0.0
const TOWER := Vector3(8.0, 0.0, -4.5)
const PLATFORM_Y: float = 4.0
const SPEED: float = 4.0
const CROUCH_RATE: float = 4.0
const CROUCH_PENALTY: float = 0.25
const MAX_HP: int = 2
const INJURED_MULT: float = 0.75
const BUMP_STRENGTH: float = 2.0
const BUMP_MAX: float = 2.0
const BUMP_DECAY: float = 4.0
const ZOOM_FOVS: Array[float] = [75.0, 50.0, 25.0]
const ZOOM_LOOK: Array[float] = [1.0, 0.6, 0.3]
const ZOOM_TEXT: Array[String] = ["", "1.5x", "3x"]
const MAG_BY_DUCKS := {0: 7, 1: 7, 2: 8, 3: 10}
const CYCLE_BY_DUCKS := {0: 0.95, 1: 0.95, 2: 0.9, 3: 0.8}
const UNZOOM_MS: int = 500
const RELOAD_MS: int = 2850
const YAW_LIMIT: float = 0.873
const PITCH_MIN: float = -1.08
const PITCH_MAX: float = -0.035
const ROUND_CAP: float = 45.0
const END_WAIT: float = 3.0
const REVEAL_TIME: float = 4.0
const COUNTDOWN: int = 3
const STAND_H: float = 1.75
const CROUCH_H: float = 1.0
const RUN: int = 0
const DEAD: int = 1
const DONE: int = 2

static var _sens: float = 1.0

var hunter: int = 0
var _eye := Vector3.ZERO
var _round: int = 0
var _rounds: int = 0
var _pool: Array = []
var _score: Dictionary = {}
var _finishes: Dictionary = {}
var _state: Dictionary = {}
var _hp: Dictionary = {}
var _ducks: Array = []
var _first_done: bool = false
var _kills: int = 0
var _active: bool = false
var _can_aim: bool = false
var _over: bool = false
var _done: bool = false
var _play_t: float = 0.0
var _mag: int = 7
var _mag_cap: int = 7
var _cycle: float = 0.95
var _srv_ready_ms: int = 0
var _srv_unzoom_ms: int = 0
var _ready_ms: int = 0
var _reload_until_ms: int = 0
var _last_shot_ms: int = -100000
var _zoom: int = 0
var _laser_on: bool = false
var _yaw: float = 0.0
var _pitch: float = -0.3
var _aim := Vector3(0.0, -0.3, 1.0).normalized()
var _aim_send_t: float = 0.0
var _kick: float = 0.0
var _fire_was: bool = false
var _zoom_was: bool = false
var _sens_t: float = 0.0
var _crouch_p: Dictionary = {}
var _crouch_vis: Dictionary = {}
var _crouch_col: Dictionary = {}
var _crouch_anim: Dictionary = {}
var _bump: Dictionary = {}
var _bump_cd: Dictionary = {}
var _shapes: Dictionary = {}
var _step_t: float = 0.0
var _spec: int = 0
var _spectating: bool = false
var _spec_was: bool = false
var _spec_prev_was: bool = false
var _solids: Array = []
var _covers: Array = []
var _spots: Array = []
var _spots_ready: bool = false
var _bot: Dictionary = {}
var _bh_target: int = 0
var _bh_aim := Vector3(0.0, -0.3, 1.0).normalized()
var _bh_hold: float = 0.0
var _bh_need: float = 0.4
var _bh_react: float = 0.0
var _bh_head: bool = false
var _bh_check: float = 0.0
var _bh_sweep: float = 0.0
var _bh_vis: bool = false
var _bh_last := Vector3.INF
var _duck_lights: Array = []

var _laser: MeshInstance3D
var _laser_dot: MeshInstance3D
var _laser_light: OmniLight3D
var _viewmodel: Node3D
var _rifle: Node3D
var _muzzle: Marker3D
var _bolt_parts: Array = []
var _scope: ColorRect
var _black: ColorRect
var _reveal_label: Label
var _reveal_sub: Label
var _center: Label
var _info: Label
var _status: Label
var _ammo_label: Label
var _zoom_label: Label
var _sens_label: Label
var _hint: Label
var _spec_label: Label
var _board: Label
var _you: Label3D
var _fence_panel: Node3D
var _fence_post: Node3D
var _black_tw: Tween

func begin() -> void:
	setup_arena(false)
	_eye = TOWER + Vector3(0, PLATFORM_Y + 1.62, 1.15)
	_night()
	_build_yard()
	_build_tower()
	_build_laser()
	spawn_players(_spawn_points())
	for id in players:
		var p: LabPlayer3D = players[id]
		p.bot_brain = func(_d: float) -> Vector3: return Vector3.ZERO
		p.input_enabled = false
		p._label.no_depth_test = false
		_score[id] = 0
		_finishes[id] = 0
		for c in p.get_children():
			if c is CollisionShape3D:
				_shapes[id] = c
	hud_title("DUCK HUNT CLASSIC  ·  run for the gate")
	_build_hud()
	_you = Label3D.new()
	_you.text = "YOU\n▼"
	_you.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_you.no_depth_test = true
	_you.font_size = 44
	_you.pixel_size = 0.006
	_you.outline_size = 10
	_you.modulate = Color(1.0, 0.85, 0.3)
	_you.visible = false
	world.add_child(_you)
	_chase_cam(Vector3(W * 0.5, 0, START_Z), 1.0)
	if NetworkManager.is_server():
		_run.call_deferred()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _autopilot() -> bool:
	return OS.get_cmdline_user_args().has("--hunter-bot")

func _spawn_points() -> Array:
	return [Vector3(1.6, 0, 29.4), Vector3(3.6, 0, 30.4), Vector3(5.6, 0, 29.4), Vector3(7.4, 0, 30.4),
		Vector3(9.2, 0, 29.4), Vector3(11.0, 0, 30.4), Vector3(12.8, 0, 29.4), Vector3(14.6, 0, 30.4)]

func _night() -> void:
	env.background_color = Color("05060a")
	env.ambient_light_color = Color(0.42, 0.48, 0.62)
	env.ambient_light_energy = 0.62
	env.fog_light_color = Color(0.07, 0.08, 0.11)
	env.fog_density = 0.022
	env.adjustment_saturation = 0.7
	env.tonemap_exposure = 1.25
	for c in world.get_children():
		if c is DirectionalLight3D:
			var dl: DirectionalLight3D = c
			dl.light_color = Color(0.62, 0.72, 1.0)
			dl.light_energy = 0.34
			dl.rotation_degrees = Vector3(-50.0, 160.0, 0.0)
			dl.directional_shadow_max_distance = 60.0

func _solid(center: Vector3, size: Vector3, yaw_deg: float = 0.0, cover: bool = true) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	world.add_child(sb)
	sb.position = center
	sb.rotation_degrees.y = yaw_deg
	var sd := {"c": center, "s": size, "yaw": yaw_deg}
	_solids.append(sd)
	if cover:
		_covers.append(sd)

func _dull(tex: String, tile: float, tint: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = mat(tex, tile, tint).duplicate()
	m.metallic = 0.2
	return m

func _glow_mat(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m

func _build_yard() -> void:
	var mid := (START_Z + FINISH_Z) * 0.5
	box(Vector3(90.0, 0.2, 90.0), Vector3(W * 0.5, -0.1, mid), mat("gravel_floor", 0.45))
	box(Vector3(W + 1.2, 0.04, START_Z + 3.0), Vector3(W * 0.5, 0.0, mid + 1.0), mat("damaged_concrete_floor", 0.3, Color(0.85, 0.85, 0.85)))
	box(Vector3(6.0, 0.05, 5.0), Vector3(3.5, 0.0, 19.0), mat("dirty_concrete", 0.4))
	box(Vector3(5.0, 0.05, 7.0), Vector3(12.5, 0.0, 9.0), mat("asphalt_02", 0.3))
	box(Vector3(W + 1.2, 0.06, 0.35), Vector3(W * 0.5, 0.0, FINISH_Z + 0.1), _glow_mat(Color(0.95, 0.75, 0.15), 0.8))
	for k in 8:
		box(Vector3(0.9, 0.065, 0.36), Vector3(1.0 + k * 2.0, 0.0, START_Z - 1.4), _dull("rusty_metal", 1.0, Color(0.9, 0.85, 0.7)))
	_cover_row()
	for b in [Vector3(-0.4, 0, 33.2), Vector3(0.4, 0, 33.6), Vector3(15.6, 0, 33.0), Vector3(16.3, 0, 32.4)]:
		prop("barrel_03", b, randf() * 360.0)
	prop("portable_generator", Vector3(13.2, 0, 33.4), 190.0, 1.3)
	prop("metal_jerrycan", Vector3(12.4, 0, 33.6), 20.0)
	prop("propane_tank", Vector3(2.0, 0, 33.6), 0.0)
	prop("cement_bag", Vector3(5.0, 0, 33.4), 40.0)
	prop("trashbag", Vector3(9.5, 0, 33.8), 0.0)
	prop("hand_truck", Vector3(7.0, 0, 33.5), 70.0)
	for n in [Vector3(0.4, 0, 24.2), Vector3(15.6, 0, 20.0), Vector3(0.5, 0, 11.0), Vector3(15.5, 0, 6.6), Vector3(7.0, 0, 28.2), Vector3(10.0, 0, 15.6)]:
		prop("nettle_plant", n, randf() * 360.0, 1.6)
	for o in [["can_rusted", 6.4, 24.0], ["plastic_crate_01", 10.8, 19.4], ["old_tyre", 5.0, 15.4], ["cardboard_box_01", 14.6, 11.0], ["wooden_crate_02", 1.0, 6.2], ["metal_trash_can", 15.2, 2.4], ["can_rusted", 9.0, 6.0]]:
		prop(o[0], Vector3(o[1], 0, o[2]), randf() * 360.0, 1.0)
	_fence_parts()
	_fence_line(Vector3(-1.4, 0, -9.0), Vector3(-1.4, 0, 35.0))
	_fence_line(Vector3(17.4, 0, -9.0), Vector3(17.4, 0, 35.0))
	_fence_line(Vector3(-1.4, 0, 35.0), Vector3(17.4, 0, 35.0))
	for gz in [-4.0, 4.0, 12.0, 20.0, 28.0]:
		prop("grass_medium_01", Vector3(-1.0, 0, gz), 90.0, 1.0)
		prop("grass_medium_01", Vector3(17.0, 0, gz + 2.0), -90.0, 1.0)
	for s in [Vector3(-6.0, 0, 30.0), Vector3(-5.0, 0, 16.0), Vector3(-6.5, 0, 2.0), Vector3(22.0, 0, 26.0), Vector3(22.5, 0, 10.0), Vector3(21.0, 0, -2.0), Vector3(4.0, 0, 39.0), Vector3(13.0, 0, 39.5)]:
		prop("shrub_02", s, randf() * 360.0, randf_range(1.0, 1.4))
	for o in [["barrel_03", -4.0, 25.0], ["old_tyre", -3.4, 25.6], ["wooden_crate_02", 20.0, 18.0], ["portable_generator", 20.5, 30.0], ["old_military_crate", -4.0, 8.0], ["propane_tank", 20.2, 4.0], ["trashbag", -3.0, 33.0], ["covered_car", 22.0, 14.0]]:
		prop(o[0], Vector3(o[1], 0, o[2]), randf() * 360.0, 1.1)
	_gate_wall()
	for z in [3.0, 11.0, 19.0, 27.0]:
		_security_light(Vector3(-1.0, 0, z), 1.0, z < 20.0)
		_security_light(Vector3(17.0, 0, z + 2.0), -1.0, false)
	for z in [6.0, 14.0, 22.0, 30.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(0.75, 0.82, 1.0)
		l.light_energy = 0.9
		l.omni_range = 9.0
		world.add_child(l)
		l.position = Vector3(W * 0.5, 4.0, z)
		_duck_lights.append(l)

func _cover_row() -> void:
	var defs := [["crates", 2.8, 26.5, 0.0], ["tyres", 8.0, 26.5, 0.0], ["crates", 13.2, 26.5, 8.0],
		["container", 4.2, 22.0, 0.0], ["car", 12.0, 22.0, 84.0],
		["tyres", 1.8, 17.5, 0.0], ["crates", 6.4, 17.5, -6.0], ["wall", 10.2, 17.5, 0.0], ["tyres", 14.4, 17.5, 0.0],
		["car", 3.6, 13.0, 96.0], ["crates", 8.4, 13.0, 4.0], ["container", 12.6, 13.0, 0.0],
		["crates", 2.2, 8.5, 0.0], ["wall", 6.2, 8.5, 0.0], ["tyres", 9.8, 8.5, 0.0], ["crates", 13.8, 8.5, -10.0],
		["tyres", 4.4, 4.5, 0.0], ["crates", 11.4, 4.5, 6.0]]
	var tints := [Color(0.95, 0.55, 0.4), Color(0.55, 0.72, 0.66), Color(0.75, 0.7, 0.55)]
	var ci := 0
	for d in defs:
		var at := Vector3(d[1], 0, d[2])
		var yaw: float = d[3]
		match d[0]:
			"crates":
				for i in 4:
					prop("old_military_crate", at + Vector3(randf_range(-0.05, 0.05), i * 0.3, 0), yaw + randf_range(-8.0, 8.0))
				prop("wooden_crate_01", at + Vector3(0.5, 1.2, 0.0), yaw + 25.0, 0.8)
				_solid(at + Vector3(0, 0.6, 0), Vector3(1.9, 1.2, 1.1), yaw)
			"tyres":
				for k in 8:
					var t := prop("old_tyre", at + Vector3(-0.35, 0.085 + k * 0.165, 0), k * 23.0)
					if t:
						t.rotation_degrees.x = 90.0
				for k in 6:
					var t2 := prop("old_tyre", at + Vector3(0.4, 0.085 + k * 0.165, 0.1), k * 41.0)
					if t2:
						t2.rotation_degrees.x = 90.0
				_solid(at + Vector3(0, 0.66, 0), Vector3(1.5, 1.32, 0.9), yaw)
			"container":
				var size := Vector3(4.6, 2.6, 2.4)
				var c := at + Vector3(0, size.y * 0.5, 0)
				var tint: Color = tints[ci % tints.size()]
				ci += 1
				box(size, c, _dull("corrugated_iron", 0.6, tint))
				box(Vector3(size.x + 0.06, 0.12, size.z + 0.06), at + Vector3(0, size.y - 0.04, 0), mat("rusty_metal", 0.8, tint.darkened(0.2)))
				box(Vector3(size.x + 0.06, 0.12, size.z + 0.06), at + Vector3(0, 0.06, 0), mat("rusty_metal", 0.8, tint.darkened(0.3)))
				_solid(c, size, 0.0)
			"car":
				prop("covered_car", at, yaw)
				_solid(at + Vector3(0, 0.7, 0), Vector3(1.8, 1.4, 4.4), yaw)
			"wall":
				var w := box(Vector3(3.0, 1.9, 0.3), at + Vector3(0, 0.95, 0), mat("dirty_concrete", 0.5, Color(0.8, 0.8, 0.78)))
				w.rotation_degrees.y = yaw
				box(Vector3(3.1, 0.12, 0.4), at + Vector3(0, 1.9, 0), mat("rusty_metal_02", 1.0))
				var rb := prop("concrete_road_barrier", at + Vector3(0.0, 0, 0.55), yaw)
				if rb:
					rb.scale = Vector3(0.9, 0.9, 0.9)
				_solid(at + Vector3(0, 0.95, 0), Vector3(3.0, 1.9, 0.3), yaw)

func _gate_wall() -> void:
	var wz := -7.5
	box(Vector3(60.0, 8.0, 0.6), Vector3(W * 0.5, 4.0, wz - 3.0), mat("factory_brick", 0.35, Color(0.8, 0.78, 0.74)))
	box(Vector3(60.0, 1.2, 0.8), Vector3(W * 0.5, 0.6, wz - 2.8), mat("concrete_wall_008", 0.5))
	prop("rollershutter_door", Vector3(1.5, 0, wz - 2.65), 0.0, 1.4)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.2, 0.18, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.78, 0.4)
	glow.emission_energy_multiplier = 1.6
	for wx in [-8.0, -4.0, 2.0, 14.0, 20.0, 24.0]:
		box(Vector3(1.6, 1.1, 0.1), Vector3(wx, 5.2, wz - 2.68), glow)
	for lx in [-3.0, 19.0]:
		_lamp_box(Vector3(lx, 3.7, wz - 2.55))
	var post_m := _dull("rusty_metal_02", 1.0, Color(0.85, 0.8, 0.75))
	for px in [-1.4, 17.4]:
		box(Vector3(0.4, 3.6, 0.4), Vector3(px, 1.8, FINISH_Z - 0.6), post_m)
	box(Vector3(19.2, 0.4, 0.4), Vector3(W * 0.5, 3.6, FINISH_Z - 0.6), post_m)
	var sign_m := _glow_mat(Color(0.2, 0.9, 0.3), 2.2)
	box(Vector3(2.4, 0.6, 0.08), Vector3(W * 0.5 - 4.0, 3.15, FINISH_Z - 0.4), sign_m)
	var lb := Label3D.new()
	lb.text = "EXIT"
	lb.font_size = 96
	lb.pixel_size = 0.006
	lb.outline_size = 12
	lb.modulate = Color(0.85, 1.0, 0.85)
	world.add_child(lb)
	lb.position = Vector3(W * 0.5 - 4.0, 3.15, FINISH_Z - 0.34)
	for gx in [0.6, 15.4]:
		var g := prop("large_iron_gate", Vector3(gx, 0, FINISH_Z - 1.4), 90.0 if gx < 8.0 else -90.0, 1.0)
		if g:
			g.rotation_degrees.y = 100.0 if gx < 8.0 else -100.0
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 1.0, 0.5)
	l.light_energy = 1.6
	l.omni_range = 6.0
	world.add_child(l)
	l.position = Vector3(W * 0.5 - 4.0, 2.6, FINISH_Z + 0.4)
	prop("security_camera_01", Vector3(16.8, 3.3, FINISH_Z - 0.4), 200.0, 1.6)

func _fence_parts() -> void:
	var src: Node3D = load(PH_MOD + "modular_chainlink_fence/modular_chainlink_fence.gltf").instantiate()
	_fence_panel = _extract(src, "modular_chainlink_fence_double")
	_fence_post = _extract(src, "modular_chainlink_fence_post")
	src.free()

func _extract(src: Node3D, child_name: String) -> Node3D:
	var holder := Node3D.new()
	var ch: Node3D = src.find_child(child_name, false, false)
	if not ch:
		return holder
	var bb := _bounds(ch, ch.transform)
	ch.owner = null
	src.remove_child(ch)
	holder.add_child(ch)
	ch.owner = holder
	for d in ch.find_children("*", "", true, false):
		d.owner = holder
	ch.position -= Vector3(bb.position.x, 0.0, bb.position.z + bb.size.z * 0.5)
	return holder

func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is MeshInstance3D:
		out = xf * (n as MeshInstance3D).get_aabb()
		first = false
	for c in n.get_children():
		if c is Node3D:
			var b := _bounds(c, xf * (c as Node3D).transform)
			if b.size != Vector3.ZERO:
				out = b if first else out.merge(b)
				first = false
	return out

func _fence_line(a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var count := int(ceil(dir.length() / 2.0))
	var step := dir / float(count)
	var yaw := atan2(-dir.z, dir.x)
	for i in count:
		var p: Node3D = _fence_panel.duplicate()
		world.add_child(p)
		p.position = a + step * i + step.normalized() * 0.05
		p.rotation.y = yaw
		p.scale = Vector3(step.length() / 1.92, 1.0, 1.0)
		var post: Node3D = _fence_post.duplicate()
		world.add_child(post)
		post.position = a + step * i - step.normalized() * 0.07
		post.rotation.y = yaw
	var last: Node3D = _fence_post.duplicate()
	world.add_child(last)
	last.position = b - dir.normalized() * 0.07

func _lamp_box(pos: Vector3) -> void:
	box(Vector3(0.42, 0.2, 0.34), pos, _dull("rusty_metal_02", 1.5, Color(0.6, 0.6, 0.6)))
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(1, 1, 1)
	lens.emission_enabled = true
	lens.emission = Color(1.0, 0.82, 0.55)
	lens.emission_energy_multiplier = 5.0
	box(Vector3(0.34, 0.04, 0.26), pos + Vector3(0, -0.11, 0), lens)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.78, 0.5)
	l.light_energy = 2.2
	l.omni_range = 6.0
	world.add_child(l)
	l.position = pos + Vector3(0, -0.3, 0.4)

func _security_light(base: Vector3, side: float, shadows: bool) -> void:
	var pole_m := mat("rusty_metal_02", 1.2)
	box(Vector3(0.16, 5.6, 0.16), base + Vector3(0, 2.8, 0), pole_m)
	box(Vector3(0.9, 0.1, 0.1), base + Vector3(side * 0.4, 5.4, 0), pole_m)
	var head := prop("security_light", base + Vector3(side * 0.8, 5.25, 0), 90.0 * side, 1.6)
	if head:
		head.rotation_degrees.x = -25.0
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(1, 1, 1)
	lens.emission_enabled = true
	lens.emission = Color(1.0, 0.95, 0.85)
	lens.emission_energy_multiplier = 6.0
	box(Vector3(0.12, 0.3, 0.42), base + Vector3(side * 0.95, 5.05, 0), lens)
	var sp := SpotLight3D.new()
	sp.light_color = Color(1.0, 0.92, 0.78)
	sp.light_energy = 14.0
	sp.spot_range = 15.0
	sp.spot_angle = 40.0
	sp.spot_attenuation = 0.9
	sp.shadow_enabled = shadows
	world.add_child(sp)
	sp.position = base + Vector3(side * 0.95, 5.0, 0)
	sp.look_at(base + Vector3(side * 6.0, 0.0, 0.5), Vector3.UP)

func _build_tower() -> void:
	var pivot := Node3D.new()
	world.add_child(pivot)
	pivot.position = TOWER
	var leg_m := _dull("rusty_metal_02", 1.0, Color(0.9, 0.85, 0.8))
	var h := PLATFORM_Y
	for cx in [-1.2, 1.2]:
		for cz in [-1.2, 1.2]:
			box(Vector3(0.18, h, 0.18), Vector3(cx, h * 0.5, cz), leg_m, pivot)
			box(Vector3(0.12, 2.6, 0.12), Vector3(cx, h + 1.3, cz), leg_m, pivot)
	for y in [1.4, 2.7, 3.9]:
		box(Vector3(2.5, 0.1, 0.1), Vector3(0, y, -1.2), leg_m, pivot)
		box(Vector3(2.5, 0.1, 0.1), Vector3(0, y, 1.2), leg_m, pivot)
		box(Vector3(0.1, 0.1, 2.5), Vector3(-1.2, y, 0), leg_m, pivot)
		box(Vector3(0.1, 0.1, 2.5), Vector3(1.2, y, 0), leg_m, pivot)
	for k in 2:
		var br := box(Vector3(0.08, 3.0, 0.08), Vector3(0, 2.0, -1.2 + k * 2.4), leg_m, pivot)
		br.rotation_degrees.z = 52.0 if k == 0 else -52.0
	box(Vector3(3.0, 0.16, 3.0), Vector3(0, h, 0), mat("black_painted_planks", 0.9, Color(0.6, 0.52, 0.42)), pivot)
	var wall_m := _dull("corrugated_iron", 0.7, Color(0.8, 0.78, 0.72))
	box(Vector3(3.0, 0.08, 0.08), Vector3(0, h + 0.95, 1.5), leg_m, pivot)
	box(Vector3(3.0, 0.08, 0.08), Vector3(0, h + 0.5, 1.5), leg_m, pivot)
	box(Vector3(3.0, 0.3, 0.04), Vector3(0, h + 0.15, 1.5), wall_m, pivot)
	box(Vector3(0.06, 1.0, 3.0), Vector3(-1.5, h + 0.55, 0), wall_m, pivot)
	box(Vector3(0.06, 1.0, 3.0), Vector3(1.5, h + 0.55, 0), wall_m, pivot)
	box(Vector3(3.0, 1.0, 0.06), Vector3(0, h + 0.55, -1.5), wall_m, pivot)
	var roof := box(Vector3(3.5, 0.06, 3.5), Vector3(0, h + 2.65, 0), mat("corrugated_iron", 0.8, Color(0.5, 0.45, 0.4)), pivot)
	roof.rotation_degrees.x = 6.0
	for k in 8:
		box(Vector3(0.6, 0.05, 0.05), Vector3(0, 0.4 + k * 0.5, -1.35), leg_m, pivot)
	prop("portable_searchlight", Vector3(-1.2, h + 1.12, 1.2), 20.0, 2.4, pivot)
	prop("ammo_box", Vector3(1.0, h + 0.08, -0.9), 30.0, 1.2, pivot)
	prop("caged_hanging_light", Vector3(0, h + 2.55, 0), 0.0, 1.2, pivot)
	var bulb := OmniLight3D.new()
	bulb.light_color = Color(1.0, 0.75, 0.45)
	bulb.light_energy = 1.6
	bulb.omni_range = 3.2
	world.add_child(bulb)
	bulb.position = TOWER + Vector3(0, h + 2.3, 0)

func _build_laser() -> void:
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.08, 0.05, 0.75)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_laser = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, 1.0)
	_laser.mesh = bm
	_laser.material_override = lm
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.visible = false
	world.add_child(_laser)
	_laser_dot = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	_laser_dot.mesh = sm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1.0, 0.15, 0.1)
	_laser_dot.material_override = dm
	_laser_dot.visible = false
	world.add_child(_laser_dot)
	_laser_light = OmniLight3D.new()
	_laser_light.light_color = Color(1.0, 0.1, 0.05)
	_laser_light.light_energy = 2.5
	_laser_light.omni_range = 1.1
	_laser_light.visible = false
	world.add_child(_laser_light)

func _build_hud() -> void:
	_scope = ColorRect.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(uv);
	float a = smoothstep(0.405, 0.415, r);
	a = max(a, smoothstep(0.22, 0.41, r) * 0.65);
	float thin = (abs(uv.x) < 0.0011 || abs(uv.y) < 0.0011) ? 1.0 : 0.0;
	float post = ((abs(uv.x) < 0.0045 && abs(uv.y) > 0.13) || (abs(uv.y) < 0.0045 && abs(uv.x) > 0.13)) ? 1.0 : 0.0;
	a = max(a, max(thin * 0.85, post));
	float mil = (abs(uv.y) < 0.006 && abs(fract(uv.x * 25.0 + 0.5) - 0.5) < 0.03 && abs(uv.x) < 0.13) ? 0.8 : 0.0;
	a = max(a, mil);
	COLOR = vec4(0.0, 0.0, 0.0, a * strength);
}"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	_scope.material = smat
	_scope.visible = false
	hud.add_child(_scope)
	_black = ColorRect.new()
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.color = Color(0, 0, 0, 1)
	hud.add_child(_black)
	_info = _label(Vector2(16, 40), 18, Color("e8e0c8"))
	_status = _label(Vector2(16, 64), 20, Color("ff9a7a"))
	_board = _label(Vector2.ZERO, 18, Color("e8e0c8"))
	_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pin(_board, Vector2(1.0, 0.0), Rect2(-320, 12, 300, 260))
	_ammo_label = _label(Vector2.ZERO, 30, Color("f0d890"))
	_pin(_ammo_label, Vector2(0.0, 1.0), Rect2(24, -96, 640, 40))
	_zoom_label = _label(Vector2.ZERO, 26, Color("f0d890"))
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_zoom_label, Vector2(0.5, 0.5), Rect2(-100, 70, 200, 34))
	_sens_label = _label(Vector2.ZERO, 22, Color("b8f5c4"))
	_sens_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_sens_label, Vector2(0.5, 1.0), Rect2(-200, -96, 400, 30))
	_sens_label.visible = false
	_hint = _label(Vector2.ZERO, 20, Color("b8f5c4"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_hint, Vector2(0.5, 1.0), Rect2(-480, -52, 960, 30))
	_spec_label = _label(Vector2.ZERO, 22, Color("e8e0c8"))
	_spec_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_spec_label, Vector2(0.5, 1.0), Rect2(-400, -90, 800, 30))
	_spec_label.visible = false
	_center = _label(Vector2.ZERO, 44, Color("ffd060"))
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_center, Vector2(0.5, 0.5), Rect2(-500, -150, 1000, 60))
	_reveal_sub = _label(Vector2.ZERO, 24, Color("b8f5c4"))
	_reveal_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_reveal_sub, Vector2(0.5, 0.5), Rect2(-500, -70, 1000, 34))
	_reveal_label = _label(Vector2.ZERO, 54, Color("ff5a40"))
	_reveal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pin(_reveal_label, Vector2(0.5, 0.5), Rect2(-500, -30, 1000, 70))
	_reveal_label.modulate.a = 0.0
	_reveal_sub.modulate.a = 0.0

func _pin(c: Control, anchor: Vector2, r: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y

func _label(pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)
	hud.add_child(l)
	return l

func _fade_black(to: float, secs: float) -> void:
	if _black_tw:
		_black_tw.kill()
	_black_tw = _black.create_tween()
	_black_tw.tween_property(_black, "color:a", to, secs)

func _is_local_hunter() -> bool:
	return hunter != 0 and hunter == multiplayer.get_unique_id() and players.has(hunter) and not players[hunter].is_bot

func _bot_hunts() -> bool:
	return hunter != 0 and players.has(hunter) and (players[hunter].is_bot or _autopilot())

func _running() -> Array:
	return _ducks.filter(func(id): return int(_state.get(id, DEAD)) == RUN and players.has(id))

func _name(id: int) -> String:
	return str(NetworkManager.players.get(id, {}).get("name", "?"))

func _now() -> int:
	return Time.get_ticks_msec()

func _run() -> void:
	_pool = players.keys()
	_pool.shuffle()
	if _autopilot():
		var bots: Array = _pool.filter(func(id): return players[id].is_bot)
		if not bots.is_empty():
			_pool.erase(bots[0])
			_pool.push_front(bots[0])
	_rounds = _pool.size()
	if _rounds <= 1:
		_finish()
		return
	await get_tree().create_timer(1.0).timeout
	var r := 0
	while not _pool.is_empty():
		r += 1
		var h: int = _pool.pop_front()
		if not players.has(h):
			continue
		var ids: Array = players.keys().filter(func(id): return id != h)
		var pts := _spawn_points()
		pts.shuffle()
		var at: Array = []
		for i in ids.size():
			at.append(pts[i % pts.size()] + Vector3(0, 0, 0.6 * float(i / pts.size())))
		var n := ids.size()
		var cap: int = MAG_BY_DUCKS.get(mini(n, 3), 7)
		var cyc: float = CYCLE_BY_DUCKS.get(mini(n, 3), 0.95)
		_rpc_setup.rpc(r, _rounds, h, ids, at, cap, cyc)
		await get_tree().create_timer(1.0).timeout
		_rpc_reveal.rpc()
		await get_tree().create_timer(REVEAL_TIME).timeout
		_rpc_can_aim.rpc()
		for k in range(COUNTDOWN, 0, -1):
			_rpc_count.rpc(k)
			await get_tree().create_timer(1.0).timeout
		_rpc_go.rpc()
		var t := 0.0
		while t < ROUND_CAP:
			await get_tree().create_timer(0.1).timeout
			t += 0.1
			if _running().is_empty() or not players.has(hunter):
				break
		_rpc_round_over.rpc(_score)
		await get_tree().create_timer(END_WAIT).timeout
		if not _pool.is_empty():
			_rpc_black.rpc()
			await get_tree().create_timer(1.5).timeout
	_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	_rpc_final.rpc()
	var ids: Array = players.keys()
	ids.sort_custom(_rank)
	finished.emit(ids)

func _rank(a: int, b: int) -> bool:
	if int(_score.get(a, 0)) != int(_score.get(b, 0)):
		return int(_score.get(a, 0)) > int(_score.get(b, 0))
	return int(_finishes.get(a, 0)) > int(_finishes.get(b, 0))

@rpc("authority", "call_local", "reliable")
func _rpc_setup(r: int, total: int, h: int, ids: Array, at: Array, cap: int, cyc: float) -> void:
	_round = r
	_rounds = total
	hunter = h
	_ducks = ids.duplicate()
	_mag_cap = cap
	_mag = cap
	_cycle = cyc
	_active = false
	_can_aim = false
	_over = false
	_first_done = false
	_kills = 0
	_play_t = 0.0
	_zoom = 0
	_laser_on = false
	_ready_ms = 0
	_srv_ready_ms = 0
	_srv_unzoom_ms = 0
	_reload_until_ms = 0
	_spec = 0
	_spectating = false
	_bot.clear()
	_bh_target = 0
	_yaw = 0.0
	_pitch = -0.3
	_aim = Basis.from_euler(Vector3(_pitch, PI, 0.0)) * Vector3(0, 0, -1)
	_bh_aim = _aim
	_black.color.a = 1.0
	_spec_label.visible = false
	_center.text = ""
	for id in players:
		var p: LabPlayer3D = players[id]
		p.body._action_busy = false
		p.set_alive(true)
		p.body.revive()
		p._label.modulate.a = 1.0
		p._label.visible = id != multiplayer.get_unique_id()
		p.visible = true
		p.body.visible = true
		p.velocity = Vector3.ZERO
		_set_shape(id, false, false)
		_crouch_p[id] = 0.0
		_crouch_vis[id] = false
		_crouch_col[id] = false
		_crouch_anim[id] = ""
		_bump[id] = Vector3.ZERO
		_hp[id] = MAX_HP
		_state[id] = RUN if id != h else -1
	if players.has(h):
		var hp: LabPlayer3D = players[h]
		hp.bounds = AABB()
		hp.position = TOWER + Vector3(0, PLATFORM_Y + 0.08, 0.95)
		hp._target = hp.position
		hp.face(Vector3(0, 0, 1))
		hp._label.visible = false
	for i in ids.size():
		if not players.has(ids[i]):
			continue
		var p: LabPlayer3D = players[ids[i]]
		p.bounds = AABB(Vector3(0.3, -5.0, FINISH_Z - 0.8), Vector3(W - 0.6, 20.0, START_Z + 2.0 - FINISH_Z))
		p.position = at[i]
		p._target = at[i]
		p.face(Vector3(0, 0, -1))
	var me_hunter := _is_local_hunter()
	for l in _duck_lights:
		(l as OmniLight3D).visible = not me_hunter
	env.ambient_light_energy = 0.42 if me_hunter else 0.62
	if me_hunter:
		players[h].body.visible = false
		camera.near = 0.03
		camera.fov = ZOOM_FOVS[0]
		if not _viewmodel:
			_build_viewmodel()
		_viewmodel.visible = true
		_apply_hunter_cam()
		_status.text = "YOU ARE THE HUNTER"
		_hint.text = "MOUSE aim  ·  RMB / SHIFT scope (3 levels)  ·  LMB / SPACE fire  ·  WHEEL sensitivity"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		if _viewmodel:
			_viewmodel.visible = false
		camera.near = 0.05
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_status.text = "HUNTER: %s" % _name(h)
		_hint.text = "WASD run to the EXIT  ·  hold SPACE crouch behind cover  ·  red laser = he is scoped in"
		var me := local_player()
		if me and _state.get(me.peer_id, -1) == RUN:
			_chase_cam(me.position, 1.0)
	_scope.visible = false
	_hint.modulate.a = 1.0

func _set_shape(id: int, crouched: bool, off: bool) -> void:
	if not _shapes.has(id):
		return
	var cs: CollisionShape3D = _shapes[id]
	var cap: CapsuleShape3D = cs.shape
	var h := CROUCH_H if crouched else STAND_H
	cap.height = h
	cs.position.y = h * 0.5
	cs.set_deferred("disabled", off)

@rpc("authority", "call_local", "reliable")
func _rpc_reveal() -> void:
	_black.color.a = 1.0
	_reveal_sub.text = "ROUND %d / %d" % [_round, _rounds]
	_reveal_label.text = "HUNTER: %s" % _name(hunter).to_upper()
	if _is_local_hunter():
		_reveal_label.text = "YOU ARE THE HUNTER"
	_reveal_label.modulate.a = 0.0
	_reveal_sub.modulate.a = 0.0
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	var t := _reveal_label.create_tween()
	t.tween_property(_reveal_label, "modulate:a", 1.0, 1.0)
	t.parallel().tween_property(_reveal_sub, "modulate:a", 1.0, 1.0)
	t.tween_interval(1.0)
	t.tween_property(_reveal_label, "modulate:a", 0.0, 0.5)
	t.parallel().tween_property(_reveal_sub, "modulate:a", 0.0, 0.5)
	t.tween_interval(0.5)
	t.tween_callback(func() -> void: _fade_black(0.0, 0.5))

@rpc("authority", "call_local", "reliable")
func _rpc_can_aim() -> void:
	_can_aim = true

@rpc("authority", "call_local", "reliable")
func _rpc_count(k: int) -> void:
	_center.text = str(k)
	_center.modulate.a = 1.0
	Fx.sfx("beep", null, -6.0)
	var me := local_player()
	_you.visible = me != null and int(_state.get(me.peer_id, -1)) == RUN

@rpc("authority", "call_local", "reliable")
func _rpc_go() -> void:
	_active = true
	_play_t = 0.0
	_center.text = "GO"
	_center.modulate.a = 1.0
	Fx.sfx("buzzer", null, -6.0)

@rpc("authority", "call_local", "reliable")
func _rpc_round_over(scores: Dictionary) -> void:
	_active = false
	_over = true
	_laser_on = false
	_score = scores.duplicate()
	_you.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var through := _ducks.filter(func(id): return int(_state.get(id, 0)) == DONE).size()
	_center.text = "ROUND %d OVER  ·  %d shot  ·  %d escaped" % [_round, _kills, through]
	var me := multiplayer.get_unique_id()
	var shot := _ducks.filter(func(id): return int(_state.get(id, 0)) == DEAD).size()
	if hunter == me:
		Profile.bump("m.duck_hunt_classic.hunter_kills", shot)
		if through == 0 and shot > 0:
			Profile.bump("m.duck_hunt_classic.sweeps")
	elif int(_state.get(me, 0)) == DONE:
		Profile.bump("m.duck_hunt_classic.escapes")
	_center.modulate.a = 1.0
	Fx.sfx("buzzer", null, -4.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_black() -> void:
	_fade_black(1.0, 0.6)
	_spec_label.visible = false

@rpc("authority", "call_local", "reliable")
func _rpc_final() -> void:
	_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

@rpc("authority", "call_local", "reliable")
func _rpc_scores(scores: Dictionary) -> void:
	_score = scores.duplicate()

func _apply_hunter_cam() -> void:
	camera.position = _eye
	camera.basis = Basis.from_euler(Vector3(_pitch + _kick, PI + _yaw, 0.0))
	_aim = -camera.basis.z

func _chase_cam(at: Vector3, k: float) -> void:
	camera.fov = 55.0
	var want := at + Vector3(0.0, 4.4, 6.2)
	camera.position = camera.position.lerp(want, k)
	camera.look_at(camera.position + (at + Vector3(0, 0.9, -3.0) - want).normalized(), Vector3.UP)

func _build_viewmodel() -> void:
	_viewmodel = Node3D.new()
	camera.add_child(_viewmodel)
	_viewmodel.position = Vector3(0.2, -0.2, -0.5)
	_rifle = prop("bolt_action_rifle_7_62", Vector3.ZERO, 90.0, 1.0, _viewmodel)
	if not _rifle:
		return
	_rifle.rotation_degrees = Vector3(0.0, 93.0, 2.0)
	for mi in _rifle.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as MeshInstance3D).layers = 2
	for nm in ["bolt_action_rifle_7_62_bolt_a", "bolt_action_rifle_7_62_bolt_b"]:
		var bp: Node3D = _rifle.find_child(nm, true, false)
		if bp:
			_bolt_parts.append([bp, bp.position])
	_muzzle = Marker3D.new()
	_rifle.add_child(_muzzle)
	_muzzle.position = Vector3(0.6, 0.0, -0.02)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.8, 0.75)
	fill.light_energy = 0.9
	fill.omni_range = 1.4
	fill.light_cull_mask = 2
	camera.add_child(fill)
	fill.position = Vector3(0.1, 0.3, 0.1)

func _muzzle_world() -> Vector3:
	if _is_local_hunter() and _muzzle and _viewmodel.visible:
		return _muzzle.global_position
	var fwd := _aim.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	return _eye + fwd * 0.9 + right * 0.2 + Vector3(0, -0.16, 0)

func _excl() -> Array:
	var out: Array = []
	for id in players:
		if id == hunter or int(_state.get(id, DEAD)) != RUN:
			out.append((players[id] as LabPlayer3D).get_rid())
	return out

func _cast(from: Vector3, dir: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * 120.0)
	q.exclude = _excl()
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		var d := dir.normalized()
		var t := 100.0
		if d.y < -0.01:
			t = -from.y / d.y
		return {"position": from + d * t, "collider": null}
	return hit

func _seen(id: int) -> bool:
	var p: LabPlayer3D = players[id]
	var hs: Array = [0.55, 0.85] if _crouch_col.get(id, false) else [1.1, 1.5]
	for h in hs:
		var hit := _cast(_eye, p.global_position + Vector3(0, h, 0) - _eye)
		if hit.collider == p:
			return true
	return false

func _process(delta: float) -> void:
	if not world:
		return
	if _active:
		_play_t += delta
	_duck_visuals()
	if hunter != 0 and players.has(hunter):
		_hunter_pose()
		if _is_local_hunter():
			_hunter_input(delta)
		if NetworkManager.is_server():
			_server_weapon_tick()
			if _bot_hunts():
				_bot_hunter_think(delta)
		_update_laser()
	_update_camera(delta)
	_kick = move_toward(_kick, 0.0, delta * 0.2)
	if _center.modulate.a > 0.0 and not _over and _active and _play_t > 0.8:
		_center.modulate.a = maxf(_center.modulate.a - delta * 1.5, 0.0)
	if _hint.modulate.a > 0.0 and _active and _play_t > 6.0:
		_hint.modulate.a = maxf(_hint.modulate.a - delta, 0.0)
	if _you.visible:
		var me := local_player()
		if me:
			_you.position = me.position + Vector3(0, 2.6, 0)
		if _active and _play_t > 2.0:
			_you.visible = false
	_sens_t -= delta
	_sens_label.visible = _sens_t > 0.0 and _is_local_hunter()
	_update_hud()

func _physics_process(delta: float) -> void:
	if not world or hunter == 0:
		return
	for id in _ducks:
		if not players.has(id):
			continue
		var p: LabPlayer3D = players[id]
		if p.is_multiplayer_authority() and int(_state.get(id, DEAD)) == RUN:
			_move_duck(id, p, delta)
	if NetworkManager.is_server() and _active:
		for id in _running():
			if (players[id] as LabPlayer3D).position.z <= FINISH_Z:
				_srv_finish(id)

func _move_duck(id: int, p: LabPlayer3D, delta: float) -> void:
	var dir := Vector3.ZERO
	var held := false
	if _active:
		if p.is_bot or _autopilot():
			var r: Array = _duck_ai(id, p, delta)
			dir = r[0]
			held = r[1]
		elif p.is_local_human():
			dir = p._input_dir()
			held = Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_CTRL)
	var cp: float = _crouch_p.get(id, 0.0)
	if _active:
		cp = minf(cp + delta * CROUCH_RATE, 1.0) if held else maxf(cp - delta * CROUCH_RATE, 0.0)
	_crouch_p[id] = cp
	var vis: bool = _crouch_vis.get(id, false)
	var col: bool = _crouch_col.get(id, false)
	var nvis := cp > 0.5
	var ncol := col
	if not col and cp >= 1.0:
		ncol = true
	elif col and cp <= 0.0:
		ncol = false
	if nvis != vis or ncol != col:
		_rpc_crouch.rpc(id, nvis, ncol)
	var spd := SPEED * (1.0 - cp * CROUCH_PENALTY)
	if int(_hp.get(id, MAX_HP)) < MAX_HP:
		spd *= INJURED_MULT
	var bump: Vector3 = _bump.get(id, Vector3.ZERO)
	var extra := Vector3.ZERO
	if bump.length() > 0.001:
		extra = bump
		_bump[id] = bump.move_toward(Vector3.ZERO, delta * BUMP_DECAY)
	p.velocity = dir.normalized() * spd + extra
	p.move_and_slide()
	if p.bounds.size != Vector3.ZERO:
		p.position.x = clampf(p.position.x, p.bounds.position.x, p.bounds.end.x)
		p.position.z = clampf(p.position.z, p.bounds.position.z, p.bounds.end.z)
	p.position.y = 0.0
	if dir.length() > 0.1:
		p.face(dir)
	if (_bump.get(id, Vector3.ZERO) as Vector3).length() <= 0.001:
		for i in p.get_slide_collision_count():
			var other: Object = p.get_slide_collision(i).get_collider()
			if other is LabPlayer3D:
				var o: LabPlayer3D = other
				if _ducks.has(o.peer_id) and int(_state.get(o.peer_id, DEAD)) == RUN and _now() >= int(_bump_cd.get(o.peer_id, 0)):
					var d := o.global_position - p.global_position
					d.y = 0.0
					_bump_cd[o.peer_id] = _now() + 250
					_rpc_bump.rpc(o.peer_id, d.normalized())
	if p.is_local_human() and dir.length() > 0.1:
		_step_t += delta
		if _step_t > 0.38:
			_step_t = 0.0
			Fx.sfx("step", null, -22.0 if col else -12.0, randf_range(0.95, 1.05))

@rpc("any_peer", "call_local", "reliable")
func _rpc_bump(id: int, dir: Vector3) -> void:
	if not players.has(id) or not (players[id] as LabPlayer3D).is_multiplayer_authority():
		return
	var b: Vector3 = _bump.get(id, Vector3.ZERO)
	if b.length() > 0.001:
		return
	b += dir * BUMP_STRENGTH
	if b.length() > BUMP_MAX:
		b = b.normalized() * BUMP_MAX
	_bump[id] = b

@rpc("any_peer", "call_local", "reliable")
func _rpc_crouch(id: int, vis: bool, col: bool) -> void:
	var s := multiplayer.get_remote_sender_id()
	if s != 0 and s != id and s != 1:
		return
	_crouch_vis[id] = vis
	if _crouch_col.get(id, false) != col:
		_crouch_col[id] = col
		_set_shape(id, col, int(_state.get(id, DEAD)) != RUN)

func _duck_visuals() -> void:
	for id in _ducks:
		if not players.has(id):
			continue
		var p: LabPlayer3D = players[id]
		if not p.alive or int(_state.get(id, DEAD)) != RUN:
			continue
		var want := ""
		if _crouch_vis.get(id, false):
			want = "Crouch_Fwd" if p._move_speed > 0.3 else "Crouch_Idle"
		var cur: String = _crouch_anim.get(id, "")
		if want == cur:
			continue
		_crouch_anim[id] = want
		if want != "":
			p.body.play_action(want, 0.15)
		else:
			p.body._action_busy = false
			p.body._locomotion = ""
			p.body.set_motion(p._move_speed)

func _hunter_pose() -> void:
	var hp: LabPlayer3D = players[hunter]
	if not hp.alive:
		return
	hp.face(Vector3(_aim.x, 0.0, _aim.z))
	var b: LabCharacter = hp.body
	if b.anim and b.anim.current_animation != "Pistol_Aim_Down":
		b.play_action("Pistol_Aim_Down", 0.25)

func _hunter_input(delta: float) -> void:
	var target_fov: float = ZOOM_FOVS[_zoom]
	camera.fov = move_toward(camera.fov, target_fov, delta * 50.0 / 0.09)
	var scoped := _zoom > 0
	_scope.visible = scoped
	(_scope.material as ShaderMaterial).set_shader_parameter("strength", 1.0 if scoped else 0.0)
	if _viewmodel:
		_viewmodel.visible = not scoped
		var cyc := clampf(1.0 - float(_now() - _last_shot_ms) / 260.0, 0.0, 1.0)
		_viewmodel.position = Vector3(0.2, -0.2, -0.5 + cyc * 0.09)
		_viewmodel.rotation.x = cyc * 0.16
		_bolt_cycle()
	if _autopilot():
		camera.position = _eye
		camera.look_at(_eye + _aim, Vector3.UP)
		return
	_apply_hunter_cam()
	var ready := _active and _now() >= _ready_ms
	var zoom_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_physical_key_pressed(KEY_SHIFT)
	if zoom_down and not _zoom_was and ready:
		var nz := wrapi(_zoom + 1, 0, ZOOM_FOVS.size())
		_local_zoom(nz)
		_rpc_zoom_req.rpc_id(1, nz)
	_zoom_was = zoom_down
	var fire_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_SPACE)
	if fire_down and not _fire_was and ready:
		_last_shot_ms = _now()
		_laser_on = false
		var reload := _mag <= 1
		_ready_ms = _now() + UNZOOM_MS + (RELOAD_MS if reload else 0) + int(_cycle * 1000.0)
		_rpc_fire_request.rpc_id(1, _aim)
	_fire_was = fire_down
	_aim_send_t -= delta
	if _aim_send_t <= 0.0 and not _over:
		_aim_send_t = 0.05
		_rpc_aim.rpc(_aim)

func _local_zoom(z: int) -> void:
	if z != _zoom:
		Fx.sfx("click", null, -4.0, randf_range(0.95, 1.05) * (1.3 if z > 0 else 1.0))
	_zoom = z
	_laser_on = z > 0

func _input(event: InputEvent) -> void:
	if not _is_local_hunter() or _autopilot():
		return
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_sens(0.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_sens(-0.1)
	if not _can_aim or _over:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m: InputEventMouseMotion = event
		var k: float = _sens / 1000.0 * ZOOM_LOOK[_zoom]
		_yaw = clampf(_yaw - m.screen_relative.x * k, -YAW_LIMIT, YAW_LIMIT)
		_pitch = clampf(_pitch - m.screen_relative.y * k, PITCH_MIN, PITCH_MAX)

func _change_sens(v: float) -> void:
	_sens = clampf(snappedf(_sens + v, 0.1), 0.1, 20.0)
	_sens_t = 1.0
	_sens_label.text = "SENSITIVITY  %.1f" % _sens
	Fx.sfx("click", null, -10.0, 1.5 if v > 0.0 else 1.2)

func _bolt_cycle() -> void:
	var t := float(_now() - _last_shot_ms) / 1000.0
	var k := 0.0
	var span := 0.5 + _cycle
	if _now() < _reload_until_ms:
		k = 1.0
	elif t > 0.5 and t < span:
		k = sin(clampf((t - 0.5) / (span - 0.5), 0.0, 1.0) * PI)
	for bp in _bolt_parts:
		(bp[0] as Node3D).position = (bp[1] as Vector3) + Vector3(-0.08 * k, 0.015 * k, 0)
	if _rifle:
		_rifle.rotation_degrees.x = -18.0 * k
	if _viewmodel and _now() < _reload_until_ms:
		_viewmodel.position.y = -0.34
		_viewmodel.rotation.z = 0.5

@rpc("any_peer", "unreliable_ordered")
func _rpc_aim(dir: Vector3) -> void:
	var s := multiplayer.get_remote_sender_id()
	if s == hunter or s == 1:
		_aim = dir.normalized()

@rpc("any_peer", "call_local", "reliable")
func _rpc_zoom_req(z: int) -> void:
	if not NetworkManager.is_server():
		return
	var s := multiplayer.get_remote_sender_id()
	if s == 0:
		s = multiplayer.get_unique_id()
	if s != hunter or not _active or _now() < _srv_ready_ms - 150:
		return
	_rpc_zoom.rpc(clampi(z, 0, ZOOM_FOVS.size() - 1))

@rpc("authority", "call_local", "reliable")
func _rpc_zoom(z: int) -> void:
	if _is_local_hunter():
		_local_zoom(z)
	else:
		_zoom = z
		_laser_on = z > 0

func _server_weapon_tick() -> void:
	if _srv_unzoom_ms > 0 and _now() >= _srv_unzoom_ms:
		_srv_unzoom_ms = 0
		_rpc_zoom.rpc(0)

func _update_laser() -> void:
	var hp: LabPlayer3D = players[hunter]
	var on := _active and hp.alive and _laser_on and _zoom > 0 and not _is_local_hunter()
	_laser.visible = on
	_laser_dot.visible = on
	_laser_light.visible = on
	if not on:
		return
	var a := _muzzle_world()
	var hit := _cast(_eye, _aim)
	var b: Vector3 = hit.position
	var len := a.distance_to(b)
	if len < 0.1:
		return
	_laser.global_position = (a + b) * 0.5
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.98 else Vector3.RIGHT
	_laser.look_at(b, up)
	_laser.scale = Vector3(1.0, 1.0, len)
	_laser_dot.global_position = b - _aim.normalized() * 0.03
	_laser_light.global_position = b - _aim.normalized() * 0.25

func _update_camera(delta: float) -> void:
	if _is_local_hunter():
		return
	var me := local_player()
	var follow: LabPlayer3D = null
	if me and int(_state.get(me.peer_id, -1)) == RUN:
		follow = me
	elif me and _ducks.has(me.peer_id):
		if not _spectating and not _over:
			_start_spectate()
		if _spectating:
			_spectate_input()
			if _spec != 0 and players.has(_spec) and int(_state.get(_spec, DEAD)) == RUN:
				follow = players[_spec]
			elif _spec != 0:
				_cycle_spec(1)
				if _spec == 0:
					_fade_black(1.0, 1.0)
	elif me and me.peer_id != hunter:
		var run := _running()
		if not run.is_empty():
			follow = players[run[0]]
	if follow:
		_chase_cam(follow.position, 1.0 - exp(-6.0 * delta))

func _start_spectate() -> void:
	_spectating = true
	_spec = 0
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree() or _over:
		return
	_fade_black(1.0, 1.0)
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree() or _over:
		return
	_cycle_spec(1)
	if _spec != 0:
		_chase_cam(players[_spec].position, 1.0)
		_fade_black(0.0, 1.0)

func _cycle_spec(step: int) -> void:
	var run := _running()
	if run.is_empty():
		_spec = 0
		_spec_label.visible = false
		return
	var i := run.find(_spec)
	i = wrapi(i + step, 0, run.size()) if i >= 0 else 0
	_spec = run[i]
	_spec_label.visible = true
	_spec_label.text = "SPECTATING %s  ·  SPACE next  ·  SHIFT previous" % _name(_spec)

func _spectate_input() -> void:
	var nxt := Input.is_physical_key_pressed(KEY_SPACE)
	var prv := Input.is_physical_key_pressed(KEY_SHIFT)
	if _spec != 0:
		if nxt and not _spec_was:
			_cycle_spec(1)
			Fx.sfx("click", null, -8.0, 1.4)
		if prv and not _spec_prev_was:
			_cycle_spec(-1)
			Fx.sfx("click", null, -8.0, 1.1)
	_spec_was = nxt
	_spec_prev_was = prv

func _update_hud() -> void:
	if not _info:
		return
	if hunter == 0:
		_info.text = ""
		return
	_info.text = "ROUND %d/%d  ·  ducks running: %d  ·  %ds" % [_round, _rounds, _running().size(), int(maxf(ROUND_CAP - _play_t, 0.0))]
	var lines: Array = []
	var ids: Array = players.keys()
	ids.sort_custom(func(a, b): return int(_score.get(a, 0)) > int(_score.get(b, 0)))
	for id in ids:
		var tag := ""
		if id == hunter:
			tag = "  [HUNTER]"
		elif int(_state.get(id, 0)) == DEAD:
			tag = "  [SHOT]"
		elif int(_state.get(id, 0)) == DONE:
			tag = "  [OUT]"
		lines.append("%s%s  %d" % [_name(id), tag, int(_score.get(id, 0))])
	_board.text = "\n".join(lines)
	if _is_local_hunter():
		var shells := ""
		for i in _mag_cap:
			shells += "|" if i < _mag else "."
		var st := ""
		if _now() < _reload_until_ms:
			st = "   RELOADING"
		elif _now() < _ready_ms:
			st = "   BOLT"
		elif not _active:
			st = "   SAFETY ON"
		_ammo_label.text = "%s  %d/%d%s" % [shells, _mag, _mag_cap, st]
		_zoom_label.text = ZOOM_TEXT[_zoom]
	else:
		_ammo_label.text = ""
		_zoom_label.text = ""
		var me := local_player()
		if me and _ducks.has(me.peer_id):
			match int(_state.get(me.peer_id, 0)):
				DEAD:
					_status.text = "YOU GOT SHOT"
				DONE:
					_status.text = "YOU GOT OUT"
				_:
					_status.text = ("INJURED  ·  slower, one more hit and you're done" if int(_hp.get(me.peer_id, MAX_HP)) < MAX_HP else "HUNTER: %s" % _name(hunter)) + ("   ·   CROUCHED" if _crouch_col.get(me.peer_id, false) else "")

@rpc("any_peer", "call_local", "reliable")
func _rpc_fire_request(dir: Vector3) -> void:
	if not NetworkManager.is_server():
		return
	var s := multiplayer.get_remote_sender_id()
	if s == 0:
		s = multiplayer.get_unique_id()
	if s != hunter:
		return
	_server_fire(_eye, dir, 150)

func _server_fire(origin: Vector3, dir: Vector3, slack: int) -> void:
	if not _active or _over or _now() < _srv_ready_ms - slack:
		return
	_mag -= 1
	var reload := _mag <= 0
	if reload:
		_mag = _mag_cap
	var wait := UNZOOM_MS + (RELOAD_MS if reload else 0) + int(_cycle * 1000.0)
	_srv_ready_ms = _now() + wait
	_srv_unzoom_ms = _now() + UNZOOM_MS
	var hit := _cast(origin, dir)
	var pt: Vector3 = hit.position
	var kind := 0
	var victim := 0
	var head := false
	if hit.collider is LabPlayer3D:
		var p: LabPlayer3D = hit.collider
		if _ducks.has(p.peer_id) and int(_state.get(p.peer_id, DEAD)) == RUN:
			victim = p.peer_id
			head = _is_headshot(p, pt)
			_hp[victim] = int(_hp.get(victim, MAX_HP)) - (2 if head else 1)
			kind = 3 if int(_hp[victim]) <= 0 else 2
	elif hit.collider != null:
		kind = 1
	if kind == 3:
		_state[victim] = DEAD
		_kills += 1
		_score[hunter] = int(_score.get(hunter, 0)) + 1
		if _kills == _ducks.size():
			_score[hunter] = int(_score.get(hunter, 0)) + 1
	_rpc_shot.rpc(pt, kind, victim, head, _mag, reload, wait, int(_hp.get(victim, MAX_HP)))
	if kind == 3:
		_rpc_scores.rpc(_score)

func _srv_finish(id: int) -> void:
	var first := not _first_done
	_first_done = true
	_state[id] = DONE
	_score[id] = int(_score.get(id, 0)) + (2 if first else 1)
	_finishes[id] = int(_finishes.get(id, 0)) + 1
	_rpc_finish.rpc(id, first)
	_rpc_scores.rpc(_score)

@rpc("authority", "call_local", "reliable")
func _rpc_finish(id: int, first: bool) -> void:
	_state[id] = DONE
	if first:
		_first_done = true
	if not players.has(id):
		return
	var p: LabPlayer3D = players[id]
	p.visible = false
	p.velocity = Vector3.ZERO
	_set_shape(id, false, true)
	Fx.sfx("whoosh", Vector3(p.position.x, 1.0, FINISH_Z), 0.0, 1.1)
	if id == multiplayer.get_unique_id():
		Fx.sfx("win", null, -6.0)
		_center.text = "YOU GOT OUT  +%d" % (2 if first else 1)
		_center.modulate.a = 1.0
	elif _is_local_hunter():
		_center.text = "%s ESCAPED" % _name(id).to_upper()
		_center.modulate.a = 1.0

func _is_headshot(p: LabPlayer3D, pt: Vector3) -> bool:
	var sk: Skeleton3D = p.body.skeleton
	if sk:
		var bi := sk.find_bone("Head")
		if bi >= 0:
			var hp: Vector3 = sk.global_transform * sk.get_bone_global_pose(bi).origin
			if pt.distance_to(hp + Vector3(0, 0.08, 0)) < 0.24:
				return true
	return not _crouch_col.get(p.peer_id, false) and pt.y > p.global_position.y + 1.52

@rpc("authority", "call_local", "reliable")
func _rpc_shot(pt: Vector3, kind: int, victim: int, head: bool, mag_left: int, reload: bool, wait_ms: int, hp_left: int) -> void:
	_mag = mag_left
	_last_shot_ms = _now()
	_laser_on = false
	_ready_ms = _now() + wait_ms
	if reload:
		_reload_until_ms = _now() + UNZOOM_MS + RELOAD_MS
	var from := _muzzle_world()
	_muzzle_flash(from)
	_tracer(from, pt)
	if _is_local_hunter():
		Fx.sfx("gunshot", null, 2.0, 0.85)
		Fx.shake(0.4)
		_kick = 0.04
	else:
		Fx.sfx("gunshot", _eye, 4.0, 0.8)
		Fx.shake(0.1)
	_bolt_sounds(reload)
	match kind:
		0:
			Fx.sparks(world, pt + Vector3(0, 0.05, 0))
		1:
			Fx.sparks(world, pt)
			Fx.sfx("hit", pt, -6.0, 1.4)
		2:
			_hp[victim] = hp_left
			if players.has(victim):
				var p: LabPlayer3D = players[victim]
				p.body.play_action("Hit_Chest")
				if _crouch_vis.get(victim, false):
					_crouch_anim[victim] = "-"
				Fx.blood(world, pt, 28)
				Fx.sfx("hit", pt, 0.0)
			_flash("HIT" if _is_local_hunter() else "")
		3:
			_hp[victim] = hp_left
			_state[victim] = DEAD
			if players.has(victim):
				var vp: LabPlayer3D = players[victim]
				vp._label.visible = false
				Fx.blood(world, pt, 90 if head else 40)
				Fx.sfx("splat", pt, 0.0)
			eliminate(victim, "Death01")
			_set_shape(victim, false, true)
			if _is_local_hunter():
				_flash("HEADSHOT" if head else "KILL")
			elif victim == multiplayer.get_unique_id():
				_flash("SHOT" if not head else "HEADSHOT")
	if victim != 0 and victim == multiplayer.get_unique_id():
		Fx.shake(0.7)

func _bolt_sounds(reload: bool) -> void:
	await get_tree().create_timer(0.55).timeout
	if not is_inside_tree():
		return
	if reload:
		Fx.sfx("arm", _eye, -4.0, 0.7)
		await get_tree().create_timer(1.6).timeout
		if is_inside_tree():
			Fx.sfx("click", _eye, -2.0, 0.8)
	else:
		Fx.sfx("click", _eye, -2.0, 0.75)

func _flash(text: String) -> void:
	if text == "":
		return
	_center.text = text
	_center.modulate.a = 1.0

func _muzzle_flash(at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 9.0
	l.omni_range = 6.0
	world.add_child(l)
	l.global_position = at
	var f := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	f.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.5)
	f.material_override = m
	f.layers = 2
	f.visible = not (_is_local_hunter() and _zoom > 0)
	world.add_child(f)
	f.global_position = at
	f.scale = Vector3(1.0, 1.0, 2.2)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.09)
	tw.tween_callback(l.queue_free)
	tw.tween_callback(f.queue_free)

func _tracer(a: Vector3, b: Vector3) -> void:
	if a.distance_to(b) < 0.1:
		return
	var t := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 1.0)
	t.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	t.material_override = m
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(t)
	t.global_position = (a + b) * 0.5
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.98 else Vector3.RIGHT
	t.look_at(b, up)
	t.scale = Vector3(1.0, 1.0, a.distance_to(b))
	var tw := t.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(t.queue_free)

func _hunter_ready() -> bool:
	return _now() >= _srv_ready_ms

func _aim_ground() -> Vector3:
	return _cast(_eye, _aim).position

func _half(sd: Dictionary) -> Vector2:
	var yaw := deg_to_rad(float(sd.yaw))
	var sx: float = sd.s.x * 0.5
	var sz: float = sd.s.z * 0.5
	return Vector2(absf(cos(yaw)) * sx + absf(sin(yaw)) * sz, absf(sin(yaw)) * sx + absf(cos(yaw)) * sz)

func _make_spots() -> void:
	_spots_ready = true
	var space := world.get_world_3d().direct_space_state
	var ex: Array = []
	for id in players:
		ex.append((players[id] as LabPlayer3D).get_rid())
	for sd in _covers:
		var hh := _half(sd)
		var c: Vector3 = sd.c
		var n := maxi(1, int(hh.x / 0.8))
		for k in n:
			var fx := 0.0 if n == 1 else lerpf(-hh.x + 0.5, hh.x - 0.5, float(k) / float(n - 1))
			var sp := Vector3(c.x + fx, 0.0, c.z + hh.y + 0.5)
			if sp.x < 0.5 or sp.x > W - 0.5:
				continue
			var q := PhysicsRayQueryParameters3D.create(_eye, sp + Vector3(0, 0.8, 0))
			q.exclude = ex
			var hit := space.intersect_ray(q)
			var hidden := not hit.is_empty() and (hit.position as Vector3).distance_to(sp + Vector3(0, 0.8, 0)) > 0.25
			if hidden:
				_spots.append({"p": sp, "tall": float(sd.s.y) > 1.7})

func _duck_ai(id: int, p: LabPlayer3D, delta: float) -> Array:
	if not _spots_ready:
		_make_spots()
	if not _bot.has(id):
		_bot[id] = {"goal": null, "hide": false, "wait": 0.0, "patience": 0.0, "zig": randf() * TAU, "stuck": 0.0, "last": p.position, "side": Vector3.ZERO, "side_t": 0.0, "via": null, "delay": randf_range(0.0, 0.5)}
	var s: Dictionary = _bot[id]
	if s.delay > 0.0:
		s.delay -= delta
		return [Vector3.ZERO, false]
	if s.goal == null:
		_next_goal(id, p, s)
	var goal: Vector3 = s.goal
	var to := goal - p.position
	to.y = 0.0
	var injured := int(_hp.get(id, MAX_HP)) < MAX_HP
	if s.hide and to.length() < 0.3:
		s.wait -= delta
		s.patience -= delta
		var aim_d := Vector2(_aim_ground().x - p.position.x, _aim_ground().z - p.position.z).length()
		var safe := not _hunter_ready() or _zoom == 0 or aim_d > 5.0
		if (s.wait <= 0.0 and safe) or s.patience <= 0.0:
			_next_goal(id, p, s)
		return [Vector3.ZERO, true]
	if not s.hide and to.length() < 0.3:
		_next_goal(id, p, s)
	s.stuck += delta
	if s.stuck > 0.5:
		if (p.position - (s.last as Vector3)).length() < 0.25 and s.side_t <= 0.0:
			s.side = Vector3(-to.z, 0, to.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
			s.side_t = 0.6
		s.stuck = 0.0
		s.last = p.position
	var way := _route(p.position, s)
	var dir := Vector3(way.x - p.position.x, 0.0, way.z - p.position.z).normalized()
	if s.side_t > 0.0:
		s.side_t -= delta
		dir = (dir * 0.3 + (s.side as Vector3)).normalized()
	elif _zoom > 0 and to.length() > 2.0:
		var ag := _aim_ground()
		if Vector2(ag.x - p.position.x, ag.z - p.position.z).length() < 4.0:
			s.zig += delta * (5.0 if not injured else 3.5)
			var lat := Vector3(1, 0, 0) * sin(s.zig) * 0.9
			dir = (dir + lat).normalized()
	return [dir, false]

func _next_goal(id: int, p: LabPlayer3D, s: Dictionary) -> void:
	var taken: Array = []
	for k in _bot:
		if k != id and _bot[k].goal != null:
			taken.append(_bot[k].goal)
	var best: Variant = null
	var best_s := -INF
	var injured := int(_hp.get(id, MAX_HP)) < MAX_HP
	for sp in _spots:
		var v: Vector3 = sp.p
		if v.z > p.position.z - 2.0 or v.z < p.position.z - 10.5:
			continue
		var score := -absf(v.x - p.position.x) * 0.45 + randf() * 2.5 + (1.0 if sp.tall else 0.0)
		for t in taken:
			if (t as Vector3).distance_to(v) < 1.2:
				score -= 3.0
		if score > best_s:
			best_s = score
			best = v
	s.via = null
	if best != null and p.position.z > 3.0:
		s.goal = best
		s.hide = true
		s.wait = randf_range(0.2, 1.1) * (1.6 if injured else 1.0)
		s.patience = randf_range(1.8, 3.6)
	else:
		s.goal = Vector3(clampf(p.position.x, 1.0, W - 1.0), 0.0, FINISH_Z - 0.7)
		s.hide = false

func _route(from: Vector3, s: Dictionary) -> Vector3:
	var goal: Vector3 = s.goal
	if s.via != null:
		if Vector2(from.x - s.via.x, from.z - s.via.z).length() > 0.45 and _blocker(from, s.via, 0.25) < 0:
			return s.via
		s.via = null
	var bi := _blocker(from, goal, 0.35)
	if bi < 0:
		return goal
	var sd: Dictionary = _solids[bi]
	var hs: Vector3 = sd.s * 0.5 + Vector3(0.75, 0, 0.75)
	var best := goal
	var best_d := INF
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var corner: Vector3 = sd.c + Vector3(hs.x * cx, 0, hs.z * cz).rotated(Vector3.UP, deg_to_rad(float(sd.yaw)))
			corner.y = 0.0
			corner.x = clampf(corner.x, 0.35, W - 0.35)
			var d := from.distance_to(corner) + corner.distance_to(goal)
			if Vector2(corner.x - from.x, corner.z - from.z).length() < 0.6:
				d += 60.0
			if _blocker(from, corner, 0.2) >= 0:
				d += 30.0
			if d < best_d:
				best_d = d
				best = corner
	s.via = best
	return best

func _blocker(a: Vector3, b: Vector3, pad: float) -> int:
	for i in _solids.size():
		var sd: Dictionary = _solids[i]
		var c: Vector3 = sd.c
		var yaw := deg_to_rad(float(sd.yaw))
		var la := (a - c).rotated(Vector3.UP, -yaw)
		var lb := (b - c).rotated(Vector3.UP, -yaw)
		var hx: float = sd.s.x * 0.5 + pad
		var hz: float = sd.s.z * 0.5 + pad
		var t0 := 0.0
		var t1 := 1.0
		var ok := true
		for axis in 2:
			var p0: float = la.x if axis == 0 else la.z
			var d: float = (lb.x - la.x) if axis == 0 else (lb.z - la.z)
			var h: float = hx if axis == 0 else hz
			if absf(d) < 0.00001:
				if absf(p0) > h:
					ok = false
			else:
				var e0 := (-h - p0) / d
				var e1 := (h - p0) / d
				t0 = maxf(t0, minf(e0, e1))
				t1 = minf(t1, maxf(e0, e1))
		if ok and t0 <= t1:
			return i
	return -1

func _bot_hunter_think(delta: float) -> void:
	if not _can_aim or _over:
		return
	_bh_check -= delta
	if _bh_check <= 0.0:
		_bh_check = 0.2
		var keep: bool = _bh_target != 0 and int(_state.get(_bh_target, DEAD)) == RUN and _seen(_bh_target)
		var pick: int = _bh_target if keep else 0
		if not keep:
			var best_s := -INF
			for id in _running():
				if not _seen(id):
					continue
				var d: Vector3 = players[id].global_position + Vector3(0, 1.0, 0) - _eye
				var score := -(players[id] as LabPlayer3D).position.z * 0.25 - rad_to_deg(_bh_aim.angle_to(d)) * 0.15 + randf() * 2.0
				if score > best_s:
					best_s = score
					pick = id
		if pick != _bh_target:
			_bh_target = pick
			_bh_last = Vector3.INF
			if pick != 0:
				_bh_react = randf_range(0.2, 0.45)
				_bh_hold = 0.0
				_bh_need = randf_range(0.1, 0.35)
				_bh_head = randf() < 0.25
		_bh_vis = _bh_target != 0 and _seen(_bh_target)
	var want := _bh_aim
	var dist := 20.0
	if _bh_target != 0:
		var tp: LabPlayer3D = players[_bh_target]
		var crouched: bool = _crouch_col.get(_bh_target, false)
		var h := (0.95 if _bh_head else 0.6) if crouched else (1.58 if _bh_head else 1.12)
		var vel: Vector3 = (tp.global_position - _bh_last) / maxf(delta, 0.001) if _bh_last != Vector3.INF else Vector3.ZERO
		_bh_last = tp.global_position
		vel.y = 0.0
		var tgt := tp.global_position + vel.limit_length(5.0) * 0.18 + Vector3(0, h, 0)
		dist = _eye.distance_to(tgt)
		want = (tgt - _eye).normalized()
	else:
		_bh_sweep += delta * 0.5
		want = (Vector3(W * 0.5 + sin(_bh_sweep) * 6.0, 0.8, 16.0 + cos(_bh_sweep * 0.7) * 9.0) - _eye).normalized()
	if _bh_react > 0.0:
		_bh_react -= delta
	else:
		var rate := 9.0 if _zoom == 0 else (7.0 if _zoom == 1 else 5.5)
		_bh_aim = _bh_aim.slerp(want, clampf(delta * rate, 0.0, 1.0)).normalized()
	_aim = _bh_aim
	_aim_send_t -= delta
	if _aim_send_t <= 0.0:
		_aim_send_t = 0.05
		_rpc_aim.rpc(_aim)
	if not _active or not _hunter_ready():
		return
	var want_zoom := 0
	if _bh_target != 0:
		want_zoom = 2 if dist > 19.0 else (1 if dist > 8.0 else 0)
	if want_zoom != _zoom:
		_rpc_zoom.rpc(want_zoom)
		_bh_hold = 0.0
		return
	if _bh_target != 0 and _bh_aim.angle_to(want) < deg_to_rad(1.0 + 0.6 * float(2 - _zoom)):
		_bh_hold += delta
	if _bh_target != 0 and _bh_vis and _bh_hold >= _bh_need:
		var spread_k: float = [0.018, 0.011, 0.0065][_zoom]
		var spread := Vector3(randfn(0.0, 1.0), randfn(0.0, 0.7), randfn(0.0, 1.0)) * spread_k
		_bh_hold = 0.0
		_bh_need = randf_range(0.12, 0.4)
		_bh_head = randf() < 0.25
		_server_fire(_eye, (_bh_aim + spread).normalized(), 0)
