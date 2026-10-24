extends ArenaMinigame3D
## Stable Footing: a floor of stone slabs hangs over a black pit. Each cycle the
## terminal on the back wall announces the SAFE symbol (X, O, square, triangle);
## the painted symbols on the slabs flash and reshuffle, then lock. When the
## countdown runs out every slab not showing the safe symbol shakes and drops,
## taking anyone standing on it. Slabs return with new symbols; each cycle has
## less time and fewer safe slabs, and later the symbols switch off before the
## drop so you must remember where they were. SPACE shoves. Last one up wins.

const TIME_LIMIT: float = 45.0
const COLS: int = 8
const ROWS: int = 5
const P: float = 2.0
const TILE: float = 1.8
const TILE_H: float = 0.55
const SHUFFLE_T: float = 1.4
const SHAKE_T: float = 0.6
const DOWN_T: float = 1.6
const RISE_T: float = 0.7
const LOCK_TIMES: Array = [3.8, 3.3, 3.0, 2.7, 2.5, 2.3, 2.1, 2.0]
const SAFE_COUNTS: Array = [12, 9, 7, 5, 4, 3, 2, 2]
const HIDE_FROM: int = 2
const SHOVE_REACH: float = 1.9
const SHOVE_CD: float = 0.8
const LUNGE: float = 0.55
const KNOCK: float = 2.7
const SYM_NAMES: Array = ["X", "O", "SQUARE", "TRIANGLE"]
const GREEN: Color = Color(0.18, 1.0, 0.12)

enum St { COUNTDOWN, RUN, DONE }
enum Ph { IDLE, SHUFFLE, LOCK, SHAKE, DOWN }

var st: St = St.COUNTDOWN
var ph: Ph = Ph.IDLE
var clock: float = 0.0
var cycle: int = -1
var safe_sym: int = -1
var layout: Array[int] = []
var down: Array[bool] = []
var hidden_cycle: bool = false
var syms_on: bool = false
var lock_end: float = 0.0
var elim_order: Array = []
var shove_ready: Dictionary = {}
var lock_until: Dictionary = {}

var _tiles: Array[MeshInstance3D] = []
var _tile_base: Array[Vector3] = []
var _tile_tw: Array = []
var _sym: Array[MeshInstance3D] = []
var _sym_tex: Array[ImageTexture] = []
var _sym_mats: Array[StandardMaterial3D] = []
var _shaking: Array = []
var _shake_t0: float = 0.0
var _shuf_acc: float = 0.0
var _fans: Array[Node3D] = []
var _push_tw: Dictionary = {}
var _bot: Dictionary = {}
var _space_down: bool = false
var _ended: bool = false
var _sync_t: float = 0.0
var _soft: Texture2D
var _font: Font

var _scr_title: Label3D
var _scr_sym: MeshInstance3D
var _scr_count: Label3D
var _side_syms: Array[MeshInstance3D] = []
var _side_q: Array[Label3D] = []
var _scr_light: OmniLight3D

var _big: Label
var _hint: Label
var _timer_label: Label
var _alive_label: Label
var _safe_panel: Control
var _safe_icon: TextureRect
var _safe_count: Label

func begin() -> void:
	setup_arena(false)
	_font = load("res://assets/ui/VT323-Regular.ttf")
	_tune_light()
	_make_symbols()
	_build_room()
	_build_pit()
	_build_floor()
	_build_screens()
	_build_dressing()
	spawn_players(_spawns())
	for id in players:
		var p: LabPlayer3D = players[id]
		p.speed = 4.4
		p.input_enabled = false
		p.bot_brain = _bot_brain.bind(id)
		shove_ready[id] = 0.0
		lock_until[id] = 0.0
		if p.is_bot:
			_bot[id] = {"react": randf_range(0.35, 0.85), "err": randf_range(0.12, 0.35), "aggro": randf_range(0.25, 0.7),
				"think": 0.0, "tile": -1, "cycle": -1, "goal": p.position, "wander": 0.0}
	camera.fov = 52.0
	camera.position = Vector3(W * 0.5, 10.8, D + 6.2)
	camera.look_at(Vector3(W * 0.5, 0.0, D * 0.5 - 1.8), Vector3.UP)
	_build_hud()
	if NetworkManager.is_server():
		_run.call_deferred()

func _spawns() -> Array:
	var cells := [[1, 1], [6, 3], [3, 1], [4, 3], [5, 1], [2, 3], [0, 3], [7, 1]]
	var a: Array = []
	var i := 0
	for id in NetworkManager.players:
		var c: Array = cells[i % cells.size()]
		a.append(Vector3((c[0] + 0.5) * P, 0.0, (c[1] + 0.5) * P))
		i += 1
	return a

func _tune_light() -> void:
	for n in world.get_children():
		if n is DirectionalLight3D:
			n.light_energy = 0.38
			n.shadow_enabled = true
			n.light_color = Color(0.85, 0.92, 0.8)
	env.background_color = Color("030303")
	env.ambient_light_color = Color(0.62, 0.58, 0.5)
	env.ambient_light_energy = 0.34
	env.fog_light_color = Color(0.03, 0.012, 0.01)
	env.fog_density = 0.012
	env.fog_height = -0.6
	env.fog_height_density = 1.2
	env.tonemap_exposure = 1.1
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.15
	env.adjustment_saturation = 0.92

func _plain(col: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m

func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.4)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

func _cyl(r: float, h: float, m: Material, pos: Vector3, rot: Vector3, parent: Node, seg: int = 16) -> MeshInstance3D:
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

func _sdf(s: int, u: float, v: float) -> float:
	match s:
		0:
			var d := minf(absf(u - v), absf(u + v)) / sqrt(2.0)
			return maxf(d, maxf(absf(u), absf(v)) - 0.62)
		1:
			return absf(sqrt(u * u + v * v) - 0.56)
		2:
			return absf(maxf(absf(u), absf(v)) - 0.52)
	var r := 0.6
	var k := sqrt(3.0)
	var px := absf(u) - r
	var py := -v + 0.14 + r / k
	if px + k * py > 0.0:
		var nx := (px - k * py) * 0.5
		var ny := (-k * px - py) * 0.5
		px = nx
		py = ny
	px -= clampf(px, -2.0 * r, 0.0)
	return absf(Vector2(px, py).length() * signf(py))

func _make_symbols() -> void:
	var n := 160
	for s in 4:
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var wob := FastNoiseLite.new()
		wob.seed = 11 + s
		wob.frequency = 0.03
		var fine := FastNoiseLite.new()
		fine.seed = 40 + s
		fine.frequency = 0.16
		for y in n:
			for x in n:
				var u := float(x) / float(n - 1) * 2.0 - 1.0
				var v := float(y) / float(n - 1) * 2.0 - 1.0
				var d := _sdf(s, u + wob.get_noise_2d(x, y + 400.0) * 0.05, v + wob.get_noise_2d(x + 400.0, y) * 0.05)
				var th := 0.15 + wob.get_noise_2d(x * 0.7, y * 0.7) * 0.05 + fine.get_noise_2d(x, y) * 0.02
				var a := clampf((th - d) * 45.0, 0.0, 1.0)
				if fine.get_noise_2d(x * 1.6 + 90.0, y * 1.6) > 0.5:
					a *= 0.2
				var drip := fine.get_noise_2d(x * 3.0, 7.0) > 0.55 and d < th + 0.04 + fine.get_noise_2d(x, y * 0.2) * 0.12 and v > 0.0
				if drip:
					a = maxf(a, 0.9)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		_sym_tex.append(tex)
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.albedo_color = GREEN
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
		m.emission_enabled = true
		m.emission = GREEN
		m.emission_energy_multiplier = 2.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_sym_mats.append(m)

func _build_room() -> void:
	var rm := Node3D.new()
	rm.name = "Room"
	world.add_child(rm)
	var wall := mat("concrete_wall_008", 0.3, Color(0.62, 0.62, 0.55))
	var dirty := mat("dirty_concrete", 0.32, Color(0.5, 0.5, 0.44))
	var ledge := mat("concrete_wall_006", 0.45, Color(0.55, 0.55, 0.5))
	var curb := mat("dirty_concrete", 0.6, Color(0.45, 0.45, 0.4))
	box(Vector3(W + 6.0, 13.0, 0.5), Vector3(W * 0.5, 6.2, -2.55), wall, rm)
	box(Vector3(0.5, 13.0, D + 8.0), Vector3(-2.55, 6.2, D * 0.5 + 1.0), wall, rm)
	box(Vector3(0.5, 13.0, D + 8.0), Vector3(W + 2.55, 6.2, D * 0.5 + 1.0), wall, rm)
	for c in [[Vector3(W + 6.0, 0.9, 0.9), Vector3(W * 0.5, 0.15, -2.3), Vector3(45, 0, 0)],
		[Vector3(0.9, 0.9, D + 8.0), Vector3(-2.3, 0.15, D * 0.5 + 1.0), Vector3(0, 0, 45)],
		[Vector3(0.9, 0.9, D + 8.0), Vector3(W + 2.3, 0.15, D * 0.5 + 1.0), Vector3(0, 0, 45)]]:
		var b := box(c[0], c[1], dirty, rm)
		b.rotation_degrees = c[2]
	box(Vector3(W + 6.0, 0.7, 0.3), Vector3(W * 0.5, 7.4, -2.25), dirty, rm)
	box(Vector3(0.3, 0.7, D + 8.0), Vector3(-2.25, 7.4, D * 0.5 + 1.0), dirty, rm)
	box(Vector3(0.3, 0.7, D + 8.0), Vector3(W + 2.25, 7.4, D * 0.5 + 1.0), dirty, rm)
	box(Vector3(W + 4.6, 0.6, 2.2), Vector3(W * 0.5, -0.15, -1.22), ledge, rm)
	box(Vector3(2.2, 0.6, D + 6.0), Vector3(-1.22, -0.15, D * 0.5 + 1.0), ledge, rm)
	box(Vector3(2.2, 0.6, D + 6.0), Vector3(W + 1.22, -0.15, D * 0.5 + 1.0), ledge, rm)
	box(Vector3(W + 4.6, 0.6, 3.6), Vector3(W * 0.5, -0.15, D + 1.92), ledge, rm)
	box(Vector3(W + 0.6, 0.22, 0.3), Vector3(W * 0.5, 0.26, -0.3), curb, rm)
	box(Vector3(W + 0.6, 0.22, 0.3), Vector3(W * 0.5, 0.26, D + 0.3), curb, rm)
	box(Vector3(0.3, 0.22, D + 0.3), Vector3(-0.3, 0.26, D * 0.5), curb, rm)
	box(Vector3(0.3, 0.22, D + 0.3), Vector3(W + 0.3, 0.26, D * 0.5), curb, rm)
	box(Vector3(W + 4.6, 0.9, 0.6), Vector3(W * 0.5, 0.45, D + 3.4), mat("concrete_wall_008", 0.5, Color(0.45, 0.45, 0.4)), rm)
	var pipe := mat("rusty_metal_02", 1.5, Color(0.6, 0.55, 0.5))
	for y in [5.3, 5.75]:
		_cyl(0.16, W + 6.0, pipe, Vector3(W * 0.5, y, -2.12), Vector3(0, 0, 90), rm, 12)
	for sx in [-1.0, 1.0]:
		_cyl(0.2, D + 8.0, pipe, Vector3(W * 0.5 + sx * (W * 0.5 + 2.12), 6.1, D * 0.5 + 1.0), Vector3(90, 0, 0), rm, 12)
	for px in [-1.6, W + 1.6]:
		_cyl(0.14, 13.0, pipe, Vector3(px, 6.0, -2.15), Vector3.ZERO, rm, 10)
	_vent(rm, Vector3(-0.2, 3.9, -2.28), 0.0, 1.85)
	_vent(rm, Vector3(W + 0.2, 3.9, -2.28), 0.0, 1.85)
	_vent(rm, Vector3(-2.28, 3.4, D * 0.5 + 1.2), 90.0, 1.7)
	_vent(rm, Vector3(W + 2.28, 3.4, D * 0.5 + 1.2), -90.0, 1.7)
	_grime_walls(rm)

func _vent(parent: Node3D, pos: Vector3, yaw: float, r: float) -> void:
	var v := Node3D.new()
	parent.add_child(v)
	v.position = pos
	v.rotation_degrees.y = yaw
	var rim := mat("rusty_metal_02", 1.4, Color(0.55, 0.5, 0.45))
	var slat := mat("rusty_metal", 1.6, Color(0.5, 0.46, 0.4))
	_cyl(r + 0.02, 0.08, _plain(Color(0.015, 0.014, 0.012), 1.0), Vector3(0, 0, 0.02), Vector3(90, 0, 0), v, 32)
	_cyl(r * 0.85, 0.03, _glow(Color(0.55, 0.35, 0.2), 0.35), Vector3(0, 0, 0.05), Vector3(90, 0, 0), v, 32)
	var tor := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.02
	tm.outer_radius = r + 0.26
	tm.rings = 40
	tm.ring_segments = 8
	tor.mesh = tm
	tor.material_override = rim
	v.add_child(tor)
	tor.position = Vector3(0, 0, 0.18)
	tor.rotation_degrees.x = 90.0
	tor.scale = Vector3(1.0, 1.6, 1.0)
	var fan := Node3D.new()
	v.add_child(fan)
	fan.position = Vector3(0, 0, 0.12)
	for k in 4:
		var bl := box(Vector3(0.42, r * 0.92, 0.04), Vector3.ZERO, _plain(Color(0.07, 0.065, 0.06), 0.7, 0.4), fan)
		bl.rotation.z = TAU * float(k) / 4.0
		bl.position = Vector3(sin(-bl.rotation.z), cos(bl.rotation.z), 0.0) * r * 0.46
		bl.rotation.y = 0.5
	_cyl(0.22, 0.2, rim, Vector3(0, 0, 0.12), Vector3(90, 0, 0), fan, 12)
	_fans.append(fan)
	var n := 11
	for i in n:
		var y := -r + (float(i) + 0.5) * 2.0 * r / float(n)
		var w := 2.0 * sqrt(maxf(r * r - y * y, 0.0)) * 0.98
		var s := box(Vector3(w, 0.07, 0.2), Vector3(0, y, 0.26), slat, v)
		s.rotation_degrees.x = 38.0
	box(Vector3(0.08, r * 2.0, 0.08), Vector3(0, 0, 0.34), rim, v)

func _grime_walls(parent: Node3D) -> void:
	var tex := _grime_tex()
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for i in 18:
		var d := Decal.new()
		d.texture_albedo = tex
		var sz := rng.randf_range(1.5, 3.5)
		d.size = Vector3(sz, 1.0, sz * rng.randf_range(1.2, 2.4))
		d.modulate = Color(0.12, 0.1, 0.07, 0.9) if i % 3 != 0 else Color(0.2, 0.13, 0.06, 0.8)
		parent.add_child(d)
		var side := i % 3
		if side == 0:
			d.position = Vector3(rng.randf_range(-1.5, W + 1.5), rng.randf_range(0.8, 6.0), -2.3)
			d.rotation_degrees = Vector3(90, 0, 0)
		elif side == 1:
			d.position = Vector3(-2.3, rng.randf_range(0.8, 6.0), rng.randf_range(-1.5, D + 2.0))
			d.rotation_degrees = Vector3(0, 0, -90)
		else:
			d.position = Vector3(rng.randf_range(-1.5, W + 1.5), 0.15, [rng.randf_range(-2.0, -0.4), rng.randf_range(D + 0.5, D + 3.0)][rng.randi() % 2])
	for i in 10:
		var d := Decal.new()
		d.texture_albedo = tex
		var sz := rng.randf_range(0.8, 1.6)
		d.size = Vector3(sz, 1.0, sz)
		d.modulate = Color(0.08, 0.07, 0.05, 0.85)
		parent.add_child(d)
		d.position = Vector3([rng.randf_range(-2.0, -0.4), rng.randf_range(W + 0.4, W + 2.0)][i % 2], 0.15, rng.randf_range(-1.0, D + 2.0))

func _grime_tex() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.seed = 17
	for y in n:
		for x in n:
			var dx := (x - n * 0.5) / (n * 0.5)
			var dy := (y - n * 0.5) / (n * 0.5)
			var v := 1.0 - sqrt(dx * dx + dy * dy) + noise.get_noise_2d(x, y) * 0.6
			img.set_pixel(x, y, Color(1, 1, 1, clampf((v - 0.25) * 2.0, 0.0, 0.85)))
	return ImageTexture.create_from_image(img)

func _build_pit() -> void:
	var pit := Node3D.new()
	pit.name = "Pit"
	world.add_child(pit)
	var shaft := mat("dirty_concrete", 0.3, Color(0.32, 0.31, 0.28))
	var depth := 24.0
	box(Vector3(0.4, depth, D + 0.8), Vector3(-0.32, 0.15 - depth * 0.5, D * 0.5), shaft, pit)
	box(Vector3(0.4, depth, D + 0.8), Vector3(W + 0.32, 0.15 - depth * 0.5, D * 0.5), shaft, pit)
	box(Vector3(W + 0.8, depth, 0.4), Vector3(W * 0.5, 0.15 - depth * 0.5, -0.32), shaft, pit)
	box(Vector3(W + 0.8, depth, 0.4), Vector3(W * 0.5, 0.15 - depth * 0.5, D + 0.32), shaft, pit)
	var rust := mat("rusty_metal_02", 1.0, Color(0.45, 0.42, 0.38))
	for y in [-3.0, -5.5]:
		_cyl(0.18, W, rust, Vector3(W * 0.5, y, 0.05), Vector3(0, 0, 90), pit, 10)
		_cyl(0.18, D, rust, Vector3(W - 0.05, y - 0.8, D * 0.5), Vector3(90, 0, 0), pit, 10)
	box(Vector3(W, 0.2, D), Vector3(W * 0.5, -22.0, D * 0.5), _glow(Color(0.5, 0.04, 0.02), 0.6), pit)
	for pl in [[W * 0.5, -9.0, D * 0.5, 3.0, 14.0], [W * 0.25, -5.0, D * 0.3, 1.0, 6.0], [W * 0.75, -5.0, D * 0.7, 1.0, 6.0]]:
		var o := OmniLight3D.new()
		o.position = Vector3(pl[0], pl[1], pl[2])
		o.light_color = Color(1.0, 0.12, 0.05)
		o.light_energy = pl[3]
		o.omni_range = pl[4]
		pit.add_child(o)

func _build_floor() -> void:
	var fl := Node3D.new()
	fl.name = "Floor"
	world.add_child(fl)
	var slabs: Array[StandardMaterial3D] = [mat("concrete_wall_008", 0.55, Color(0.42, 0.41, 0.37)),
		mat("dirty_concrete", 0.55, Color(0.4, 0.39, 0.35)), mat("concrete_wall_006", 0.55, Color(0.38, 0.37, 0.34))]
	var insets: Array[StandardMaterial3D] = [mat("damaged_concrete_floor", 0.7, Color(0.16, 0.16, 0.15)),
		mat("asphalt_02", 0.7, Color(0.2, 0.2, 0.19)), mat("dirty_concrete", 0.7, Color(0.13, 0.13, 0.12))]
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.3, 1.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for r in ROWS:
		for c in COLS:
			var i := r * COLS + c
			var pos := Vector3((c + 0.5) * P, -TILE_H * 0.5, (r + 0.5) * P)
			var k := rng.randi() % 3
			var mi := box(Vector3(TILE, TILE_H, TILE), pos, slabs[k], fl)
			var top := TILE_H * 0.5
			box(Vector3(TILE - 0.36, 0.02, TILE - 0.36), Vector3(0, top + 0.0, 0), insets[rng.randi() % 3], mi)
			var rimm: StandardMaterial3D = slabs[(k + 1) % 3]
			for sz in [-1.0, 1.0]:
				box(Vector3(TILE, 0.07, 0.18), Vector3(0, top + 0.035, sz * (TILE * 0.5 - 0.09)), rimm, mi)
				box(Vector3(0.18, 0.07, TILE - 0.36), Vector3(sz * (TILE * 0.5 - 0.09), top + 0.035, 0), rimm, mi)
			var s := MeshInstance3D.new()
			s.mesh = plane
			mi.add_child(s)
			s.position = Vector3(0, top + 0.03, 0)
			s.rotation.y = rng.randf_range(-0.12, 0.12)
			s.visible = false
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_tiles.append(mi)
			_tile_base.append(pos)
			_tile_tw.append(null)
			_sym.append(s)
			layout.append(0)
			down.append(false)

func _screen(parent: Node3D, pos: Vector3, size: Vector2) -> Node3D:
	var s := Node3D.new()
	parent.add_child(s)
	s.position = pos
	var frame := mat("rusty_metal_02", 1.2, Color(0.5, 0.47, 0.42))
	box(Vector3(size.x + 0.3, size.y + 0.3, 0.24), Vector3.ZERO, frame, s)
	box(Vector3(size.x, size.y, 0.04), Vector3(0, 0, 0.13), _glow(Color(0.02, 0.09, 0.035), 0.3), s)
	for sx in [-1.0, 1.0]:
		box(Vector3(0.06, 0.06, 0.06), Vector3(sx * (size.x * 0.5 + 0.06), size.y * 0.5 + 0.06, 0.14), mat("rusty_metal", 2.0), s)
	return s

func _build_screens() -> void:
	var sc := Node3D.new()
	sc.name = "Screens"
	world.add_child(sc)
	var center := _screen(sc, Vector3(W * 0.5, 3.6, -2.2), Vector2(4.2, 2.3))
	_scr_title = _label3d("STAND BY", 190, Vector3(-0.75, 0.35, 0.17), center)
	_scr_count = _label3d("", 170, Vector3(-0.75, -0.55, 0.17), center)
	var q := QuadMesh.new()
	q.size = Vector2(1.7, 1.7)
	_scr_sym = MeshInstance3D.new()
	_scr_sym.mesh = q
	center.add_child(_scr_sym)
	_scr_sym.position = Vector3(1.15, 0.0, 0.17)
	_scr_sym.visible = false
	for sx in [W * 0.5 - 4.4, W * 0.5 + 4.4]:
		var side := _screen(sc, Vector3(sx, 3.7, -2.2), Vector2(1.9, 1.9))
		var m := MeshInstance3D.new()
		var q2 := QuadMesh.new()
		q2.size = Vector2(1.6, 1.6)
		m.mesh = q2
		side.add_child(m)
		m.position = Vector3(0, 0, 0.17)
		m.visible = false
		_side_syms.append(m)
		_side_q.append(_label3d("?", 220, Vector3(0, 0.05, 0.17), side))
	_scr_light = OmniLight3D.new()
	_scr_light.light_color = Color(0.3, 1.0, 0.35)
	_scr_light.light_energy = 0.8
	_scr_light.omni_range = 5.0
	sc.add_child(_scr_light)
	_scr_light.position = Vector3(W * 0.5, 3.4, -1.0)

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

func _cable(a: Vector3, b: Vector3, sag: float, parent: Node3D) -> void:
	var m := _plain(Color(0.05, 0.05, 0.045), 0.6)
	var segs := 10
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		var mid := (prev + p) * 0.5
		var seg_len := prev.distance_to(p)
		var c := _cyl(0.035, seg_len, m, mid, Vector3.ZERO, parent, 6)
		c.look_at_from_position(mid, p, Vector3.UP if absf((p - prev).normalized().y) < 0.95 else Vector3.RIGHT)
		c.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		prev = p

func _build_dressing() -> void:
	var d := Node3D.new()
	d.name = "Dressing"
	world.add_child(d)
	for it in [["barrel_03", -1.3, -1.2, 0, 1.1], ["cement_bag", -1.1, 0.8, 30, 1.1], ["can_rusted", -1.0, 4.2, 0, 1.5],
		["metal_jerrycan", -1.2, 6.6, 70, 1.1], ["trashbag", W + 1.2, -1.1, 0, 1.1], ["wooden_crate_02", W + 1.3, 1.6, 12, 1.0],
		["metal_trash_can", W + 1.1, 7.4, 0, 1.0], ["old_tyre", W + 1.0, 9.6, 0, 1.0], ["plastic_crate_01", W * 0.3, -1.4, 10, 1.0],
		["old_military_crate", W * 0.72, -1.5, 0, 1.0], ["cardboard_box_01", -1.1, D + 1.6, 25, 1.0], ["propane_tank", W + 1.3, D + 1.8, 0, 1.0]]:
		prop(it[0], Vector3(it[1], 0.15, it[2]), it[3], it[4], d)
	prop("power_box_01", Vector3(W * 0.5 + 2.6, 1.4, -2.28), 0.0, 1.5, d)
	prop("fire_alarm", Vector3(W * 0.5 - 2.6, 1.7, -2.28), 0.0, 1.5, d)
	prop("security_camera_01", Vector3(W + 2.0, 6.4, -2.0), -135.0, 1.6, d)
	prop("security_camera_01", Vector3(-2.0, 6.4, -2.0), -45.0, 1.6, d)
	for sc in [[Vector3(-2.28, 2.2, 1.0), 90.0], [Vector3(W + 2.28, 2.2, 1.0), -90.0], [Vector3(-2.28, 2.2, D + 0.5), 90.0], [Vector3(W + 2.28, 2.2, D + 0.5), -90.0]]:
		var pos: Vector3 = sc[0]
		box(Vector3(0.3, 0.42, 0.3), pos, mat("rusty_metal_02", 2.0, Color(0.5, 0.46, 0.4)), d)
		box(Vector3(0.18, 0.26, 0.18), pos + Vector3(0.18 * signf(W * 0.5 - pos.x), 0, 0), _glow(Color(1.0, 0.7, 0.4), 2.5), d)
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.72, 0.42)
		o.light_energy = 1.6
		o.omni_range = 5.0
		d.add_child(o)
		o.position = pos + Vector3(0.5 * signf(W * 0.5 - pos.x), 0.1, 0)
	_cable(Vector3(-2.2, 7.0, 2.0), Vector3(W * 0.3, 9.5, 3.5), 1.6, d)
	_cable(Vector3(W + 2.2, 7.0, 1.0), Vector3(W * 0.7, 9.5, 3.5), 1.8, d)
	_cable(Vector3(-2.2, 6.8, -1.0), Vector3(W * 0.5 - 2.4, 5.0, -2.2), 0.8, d)
	_cable(Vector3(W + 2.2, 6.8, -1.0), Vector3(W * 0.5 + 2.4, 5.0, -2.2), 0.8, d)
	_cable(Vector3(W * 0.5 - 4.4, 4.75, -2.15), Vector3(W * 0.5 - 2.4, 4.85, -2.15), 0.5, d)
	_cable(Vector3(W * 0.5 + 4.4, 4.75, -2.15), Vector3(W * 0.5 + 2.4, 4.85, -2.15), 0.5, d)
	for lx in [W * 0.25, W * 0.75]:
		var sp := lamp(Vector3(lx, 8.2, D * 0.35), 7.0, Color(1.0, 0.86, 0.66), d)
		sp.spot_angle = 60.0
		sp.shadow_enabled = false
		_cable(Vector3(lx, 8.6, D * 0.35), Vector3(lx, 12.0, D * 0.35), 0.0, d)
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.76)
	key.light_energy = 9.0
	key.spot_range = 26.0
	key.spot_angle = 38.0
	key.spot_attenuation = 0.6
	key.shadow_enabled = true
	d.add_child(key)
	key.position = Vector3(W * 0.5, 15.0, D * 0.5)
	key.rotation_degrees.x = -90.0

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

func _dust(pos: Vector3) -> void:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.amount = 7
	gp.lifetime = 1.4
	gp.explosiveness = 0.85
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.05, 0.9)
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -0.4, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 1.0
	pm.scale_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.3, 0.28, 0.25, 0.32))
	ramp.set_color(1, Color(0.2, 0.2, 0.18, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex()
	q.material = m
	gp.draw_pass_1 = q
	world.add_child(gp)
	gp.global_position = pos
	gp.emitting = true
	var ch := GPUParticles3D.new()
	ch.one_shot = true
	ch.amount = 10
	ch.lifetime = 1.2
	ch.explosiveness = 0.9
	var cm := ParticleProcessMaterial.new()
	cm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	cm.emission_box_extents = Vector3(0.9, 0.05, 0.9)
	cm.direction = Vector3.UP
	cm.spread = 50.0
	cm.initial_velocity_min = 1.0
	cm.initial_velocity_max = 2.6
	cm.gravity = Vector3(0, -12.0, 0)
	cm.angular_velocity_min = -300.0
	cm.angular_velocity_max = 300.0
	ch.process_material = cm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.07, 0.08)
	bm.material = mat("dirty_concrete", 2.0, Color(0.5, 0.5, 0.45))
	ch.draw_pass_1 = bm
	world.add_child(ch)
	ch.global_position = pos
	ch.emitting = true
	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		gp.queue_free()
		ch.queue_free())

func _style(l: Label, size: int, c: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)

func _center_label(size: int, y: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.anchor_top = y - 0.1
	l.anchor_bottom = y + 0.1
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 12)
	hud.add_child(l)
	return l

func _build_hud() -> void:
	hud_title("STABLE FOOTING  ·  stand on the safe symbol")
	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-120, 10)
	_timer_label.size = Vector2(100, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(_timer_label, 26, Color("ffd34a"))
	hud.add_child(_timer_label)
	_alive_label = Label.new()
	_alive_label.position = Vector2(16, 40)
	_style(_alive_label, 18, Color("e8e2c8"))
	hud.add_child(_alive_label)
	_safe_panel = Control.new()
	_safe_panel.anchor_left = 1.0
	_safe_panel.anchor_right = 1.0
	_safe_panel.offset_left = -250.0
	_safe_panel.offset_right = -10.0
	_safe_panel.offset_top = 40.0
	_safe_panel.offset_bottom = 124.0
	hud.add_child(_safe_panel)
	var sl := Label.new()
	sl.text = "SAFE"
	sl.position = Vector2(0, 14)
	sl.size = Vector2(120, 50)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(sl, 40, Color(0.5, 1.0, 0.45))
	_safe_panel.add_child(sl)
	_safe_icon = TextureRect.new()
	_safe_icon.position = Vector2(132, 4)
	_safe_icon.size = Vector2(72, 72)
	_safe_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_safe_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_safe_icon.modulate = Color(0.45, 1.0, 0.4)
	_safe_panel.add_child(_safe_icon)
	_safe_count = Label.new()
	_safe_count.position = Vector2(0, 62)
	_safe_count.size = Vector2(240, 30)
	_safe_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_safe_count, 22, Color("ffd34a"))
	_safe_panel.add_child(_safe_count)
	_safe_panel.visible = false
	_big = _center_label(84, 0.42)
	_hint = _center_label(24, 0.88)
	_hint.text = "WASD  MOVE   ·   SPACE  SHOVE\nstand on the SAFE symbol · everything else drops · remember where they were"
	_hint.add_theme_color_override("font_color", Color("e8e2c8"))
	_update_alive_label()

func _update_alive_label() -> void:
	if _alive_label:
		_alive_label.text = "subjects standing: %d" % alive_ids().size()

func _big_local(text: String, hex: String, hold: float, size: int = 84) -> void:
	_big.text = text
	_big.add_theme_font_size_override("font_size", size)
	_big.add_theme_color_override("font_color", Color(hex))
	_big.modulate.a = 1.0
	if hold > 0.0:
		var tw := create_tween()
		tw.tween_interval(hold)
		tw.tween_property(_big, "modulate:a", 0.0, 0.4)

func _cell_of(pos: Vector3) -> int:
	var c := clampi(int(floor(pos.x / P)), 0, COLS - 1)
	var r := clampi(int(floor(pos.z / P)), 0, ROWS - 1)
	return r * COLS + c

func _center(i: int) -> Vector3:
	return Vector3((i % COLS + 0.5) * P, 0.0, (i / COLS + 0.5) * P)

func _process(delta: float) -> void:
	if not world:
		return
	clock += delta
	if st == St.RUN:
		_handle_input()
	for f in _fans:
		f.rotation.z += delta * 5.0
	_animate_tiles(delta)
	_update_screen()
	if st == St.RUN and NetworkManager.is_server():
		_server_tick(delta)

func _animate_tiles(delta: float) -> void:
	if ph == Ph.SHUFFLE:
		_shuf_acc -= delta
		if _shuf_acc <= 0.0:
			_shuf_acc = 0.09
			for i in _sym.size():
				if not down[i]:
					_sym[i].material_override = _sym_mats[randi() % 4]
					_sym[i].visible = randf() > 0.15
		for m in _sym_mats:
			m.emission_energy_multiplier = 0.6 + absf(sin(clock * 16.0)) * 3.2
	else:
		for m in _sym_mats:
			m.emission_energy_multiplier = 2.4
	if not _shaking.is_empty():
		var t := clock - _shake_t0
		var amp := 0.015 + clampf(t / SHAKE_T, 0.0, 1.0) * 0.05
		for i in _shaking:
			var mi := _tiles[i]
			mi.position = _tile_base[i] + Vector3(randf_range(-amp, amp), randf_range(-amp, amp) * 0.6, randf_range(-amp, amp))
			mi.rotation = Vector3(randf_range(-amp, amp), 0.0, randf_range(-amp, amp)) * 0.7

func _update_screen() -> void:
	if not _scr_title:
		return
	if ph == Ph.LOCK or ph == Ph.SHAKE:
		var left := maxf(0.0, lock_end - clock)
		var txt := "%.1f" % left if ph == Ph.LOCK else "DROP"
		_scr_count.text = txt
		_safe_count.text = txt if ph == Ph.SHAKE else "%d" % int(ceil(left))
		var blink := ph == Ph.SHAKE or (left < 1.0 and fmod(clock, 0.25) < 0.12)
		_scr_count.modulate = Color(1.0, 0.35, 0.25) if blink else Color(0.45, 1.0, 0.42)
		_scr_light.light_energy = 1.4 if blink else 0.8
	elif ph == Ph.SHUFFLE:
		_scr_count.text = "SCANNING"
		_scr_count.modulate = Color(0.45, 1.0, 0.42)
		_safe_count.text = "..."
		_scr_light.light_energy = 0.6 + absf(sin(clock * 16.0)) * 0.8
	else:
		_scr_light.light_energy = 0.6

func _handle_input() -> void:
	var me := local_player()
	if not me or not me.alive:
		return
	var press := Input.is_physical_key_pressed(KEY_SPACE)
	if press and not _space_down:
		if NetworkManager.is_server():
			_try_shove(multiplayer.get_unique_id())
		else:
			_rpc_press.rpc_id(1)
	_space_down = press

@rpc("any_peer", "reliable")
func _rpc_press() -> void:
	if NetworkManager.is_server():
		_try_shove(multiplayer.get_remote_sender_id())

func _fwd(p: LabPlayer3D) -> Vector3:
	return Vector3(sin(p._target_yaw), 0.0, cos(p._target_yaw))

func _try_shove(id: int) -> void:
	if st != St.RUN or not players.has(id) or not players[id].alive:
		return
	if clock < float(shove_ready[id]) or clock < float(lock_until[id]):
		return
	shove_ready[id] = clock + SHOVE_CD
	lock_until[id] = clock + 0.2
	var p: LabPlayer3D = players[id]
	var f := _fwd(p)
	var best := -1
	var best_d := SHOVE_REACH
	for o in alive_ids():
		if o == id:
			continue
		var to: Vector3 = players[o].position - p.position
		to.y = 0.0
		var d := to.length()
		if d > best_d:
			continue
		if d > 0.6 and f.dot(to / d) < 0.0:
			continue
		best = o
		best_d = d
	if best < 0:
		_rpc_shove.rpc(id, -1, p.position + f * LUNGE, Vector3.ZERO)
		return
	var v: LabPlayer3D = players[best]
	var to_v: Vector3 = v.position - p.position
	to_v.y = 0.0
	var dir: Vector3 = to_v.normalized() if to_v.length() > 0.05 else f
	if not p.is_bot:
		dir = (dir * 0.6 + f * 0.4).normalized()
	lock_until[best] = clock + 0.55
	_rpc_shove.rpc(id, best, p.position + dir * maxf(best_d - 0.6, 0.0), v.position + dir * KNOCK)

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
		if is_instance_valid(p) and p.alive and st == St.RUN:
			p.input_enabled = true)

@rpc("authority", "call_local", "reliable")
func _rpc_shove(a: int, v: int, lunge_to: Vector3, push_to: Vector3) -> void:
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
	pv.face(pa.position - pv.position)
	pv.body.play_action("Hit_Knockback", 0.05, 1.2)
	Fx.sfx("hit", pv.position, -1.0, 1.0)
	Fx.shake(0.18)
	if pv.is_multiplayer_authority():
		_tween_move(v, push_to, 0.38)
	_lock_input(pv, 0.55)

func _server_tick(delta: float) -> void:
	for id in alive_ids():
		var c := _cell_of(players[id].position)
		if down[c]:
			elim_order.append(id)
			_rpc_fall.rpc(id)
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.25
		_rpc_sync.rpc(maxf(0.0, TIME_LIMIT - clock))

@rpc("authority", "call_local", "reliable")
func _rpc_sync(time_left: float) -> void:
	_timer_label.text = "%d s" % int(ceil(time_left))

@rpc("authority", "call_local", "reliable")
func _rpc_fall(id: int) -> void:
	var p: LabPlayer3D = players[id]
	if not p.alive:
		return
	if not elim_order.has(id):
		elim_order.append(id)
	if _push_tw.has(id):
		var old: Tween = _push_tw[id]
		if old and old.is_valid():
			old.kill()
	if p.is_local_human():
		p.input_enabled = false
	p.set_alive(false)
	p.collision_layer = 0
	p.collision_mask = 0
	p._label.visible = false
	var b: LabCharacter = p.body
	b.play_loop("Jump", 0.05)
	Fx.sfx("whoosh", p.position, 2.0, 0.55)
	Fx.sfx("buzzer", p.position, -10.0, 1.8)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(b, "position:y", -15.0, 1.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(b, "rotation:x", randf_range(-1.8, 1.8), 1.25)
	tw.tween_property(b, "rotation:z", randf_range(-0.8, 0.8), 1.25)
	tw.chain().tween_callback(func() -> void:
		b.die("Death01")
		var bottom := p.position + Vector3(0, -6.0, 0)
		Fx.sfx("splat", bottom, 4.0, 0.7)
		Fx.sfx("hit", bottom, 0.0, 0.45)
		Fx.shake(0.35)
		get_tree().create_timer(0.32).timeout.connect(func() -> void: Fx.sfx("splat", bottom, -8.0, 0.62))
		get_tree().create_timer(0.7).timeout.connect(func() -> void: Fx.sfx("splat", bottom, -16.0, 0.55)))
	_update_alive_label()
	var me := local_player()
	if me and me.peer_id == id:
		_big_local("YOU FELL", "ff4040", 1.4, 72)

@rpc("authority", "call_local", "reliable")
func _rpc_announce(k: int, safe: int, lay: Array, hide: bool) -> void:
	cycle = k
	safe_sym = safe
	layout.assign(lay)
	hidden_cycle = hide
	ph = Ph.SHUFFLE
	syms_on = true
	_scr_title.text = "SAFE:"
	_scr_sym.material_override = _sym_mats[safe]
	_scr_sym.visible = true
	for i in _side_syms.size():
		_side_syms[i].material_override = _sym_mats[safe]
		_side_syms[i].visible = true
		_side_q[i].visible = false
	_safe_icon.texture = _sym_tex[safe]
	_safe_panel.visible = true
	Fx.sfx("beep", null, -4.0, 0.9)
	Fx.sfx("arm", null, -12.0, 1.4)
	if hide and k == HIDE_FROM:
		_big_local("LIGHTS GO OUT BEFORE THE DROP\nREMEMBER THEM", "ffd34a", 1.8, 40)

@rpc("authority", "call_local", "reliable")
func _rpc_lock(dur: float) -> void:
	ph = Ph.LOCK
	lock_end = clock + dur
	for i in _sym.size():
		_sym[i].material_override = _sym_mats[layout[i]]
		_sym[i].visible = not down[i]
	Fx.sfx("click", null, 0.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_hide() -> void:
	syms_on = false
	for s in _sym:
		s.visible = false
	Fx.sfx("buzzer", null, -8.0, 0.5)
	Fx.sfx("click", null, 0.0, 0.5)

@rpc("authority", "call_local", "reliable")
func _rpc_shake(drop: Array) -> void:
	ph = Ph.SHAKE
	_shaking = drop
	_shake_t0 = clock
	Fx.sfx("hum", null, 0.0, 0.45)
	Fx.sfx("arm", null, -6.0, 0.6)
	Fx.shake(0.15)

@rpc("authority", "call_local", "reliable")
func _rpc_drop(drop: Array) -> void:
	ph = Ph.DOWN
	_shaking = []
	var n := 0
	for i in drop:
		down[i] = true
		_sym[i].visible = false
		var mi := _tiles[i]
		mi.position = _tile_base[i]
		mi.rotation = Vector3.ZERO
		if _tile_tw[i]:
			var old: Tween = _tile_tw[i]
			if old.is_valid():
				old.kill()
		var tw := create_tween().set_parallel(true)
		var delay := randf_range(0.0, 0.12)
		tw.tween_property(mi, "position:y", -20.0, 1.7).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(mi, "rotation", Vector3(randf_range(-0.7, 0.7), randf_range(-0.4, 0.4), randf_range(-0.7, 0.7)), 1.7).set_delay(delay)
		tw.chain().tween_callback(mi.hide)
		_tile_tw[i] = tw
		if n % 3 == 0:
			_dust(_center(i) + Vector3(0, 0.05, 0))
		n += 1
	Fx.sfx("explosion", null, -8.0, 0.45)
	Fx.sfx("hit", null, 0.0, 0.4)
	Fx.sfx("hum", null, -2.0, 0.35)
	Fx.shake(0.55)

@rpc("authority", "call_local", "reliable")
func _rpc_rise() -> void:
	ph = Ph.IDLE
	syms_on = false
	for s in _sym:
		s.visible = false
	for i in _tiles.size():
		if not down[i]:
			continue
		down[i] = false
		var mi := _tiles[i]
		if _tile_tw[i]:
			var old: Tween = _tile_tw[i]
			if old.is_valid():
				old.kill()
		mi.show()
		mi.rotation = Vector3.ZERO
		mi.position = _tile_base[i] + Vector3(0, -7.0, 0)
		var tw := create_tween()
		tw.tween_property(mi, "position", _tile_base[i], RISE_T).set_delay(randf_range(0.0, 0.1)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tile_tw[i] = tw
	_scr_title.text = "STAND BY"
	_scr_count.text = ""
	_scr_sym.visible = false
	for i in _side_syms.size():
		_side_syms[i].visible = false
		_side_q[i].visible = true
	_safe_panel.visible = false
	Fx.sfx("hum", null, -4.0, 0.7)
	Fx.sfx("click", null, -2.0, 0.6)

@rpc("authority", "call_local", "reliable")
func _rpc_big(text: String, hex: String, hold: float) -> void:
	_big_local(text, hex, hold)

@rpc("authority", "call_local", "reliable")
func _rpc_start() -> void:
	st = St.RUN
	clock = 0.0
	for id in players:
		var p: LabPlayer3D = players[id]
		if p.is_local_human():
			p.input_enabled = true
	_big_local("GO", "8fe36a", 0.6)
	Fx.sfx("beep", null, -4.0, 1.4)
	var th := create_tween()
	th.tween_interval(7.0)
	th.tween_property(_hint, "modulate:a", 0.0, 0.8)

@rpc("authority", "call_local", "reliable")
func _rpc_end(timeout: bool) -> void:
	st = St.DONE
	_shaking = []
	if ph == Ph.SHUFFLE:
		ph = Ph.IDLE
		for i in _sym.size():
			_sym[i].material_override = _sym_mats[layout[i]]
			_sym[i].visible = not down[i]
	for id in players:
		players[id].input_enabled = false
	var alive := alive_ids()
	var txt := "TIME!" if timeout else "NOBODY LEFT"
	if alive.size() == 1:
		txt = "%s STANDS" % players[alive[0]].display_name
	elif timeout:
		txt = "TIME!  %d STILL STANDING" % alive.size()
	_big_local(txt, "e2c84b", 0.0, 56)
	Fx.sfx("buzzer", null, -6.0, 1.3)

func _over() -> bool:
	return alive_ids().size() <= 1 or clock >= TIME_LIMIT

func _wait(t: float) -> bool:
	var end := clock + t
	while clock < end:
		if _over():
			return false
		await get_tree().process_frame
	return true

func _make_layout(safe: int, n_safe: int) -> Array:
	var n := COLS * ROWS
	var idx: Array = range(n)
	idx.shuffle()
	var lay: Array = []
	lay.resize(n)
	for i in n:
		lay[i] = (safe + 1 + randi() % 3) % 4
	for j in mini(n_safe, n):
		lay[idx[j]] = safe
	return lay

func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	for n in ["3", "2", "1"]:
		_rpc_big.rpc(n, "e8e2c8", 0.0)
		Fx.sfx("click")
		await get_tree().create_timer(0.8).timeout
	_rpc_start.rpc()
	var k := 0
	var prev := -1
	while not _over():
		var safe := randi() % 4
		if safe == prev:
			safe = (safe + 1 + randi() % 3) % 4
		prev = safe
		var n_safe: int = SAFE_COUNTS[mini(k, SAFE_COUNTS.size() - 1)]
		var lock_t: float = LOCK_TIMES[mini(k, LOCK_TIMES.size() - 1)]
		var hide := k >= HIDE_FROM
		var lay := _make_layout(safe, n_safe)
		_rpc_announce.rpc(k, safe, lay, hide)
		if not await _wait(SHUFFLE_T):
			break
		_rpc_lock.rpc(lock_t)
		if hide:
			var lead := minf(lock_t - 0.6, 1.0 + 0.2 * float(k - HIDE_FROM))
			if not await _wait(lock_t - lead):
				break
			_rpc_hide.rpc()
			if not await _wait(lead):
				break
		elif not await _wait(lock_t):
			break
		var drop: Array = []
		for i in lay.size():
			if int(lay[i]) != safe:
				drop.append(i)
		_rpc_shake.rpc(drop)
		if not await _wait(SHAKE_T):
			break
		_rpc_drop.rpc(drop)
		await get_tree().process_frame
		if not await _wait(DOWN_T):
			break
		_rpc_rise.rpc()
		if not await _wait(RISE_T + 0.25):
			break
		k += 1
	_rpc_end.rpc(clock >= TIME_LIMIT)
	await get_tree().create_timer(2.4).timeout
	if not _ended:
		_ended = true
		finished.emit(survival_placement(elim_order))

func _occupancy(tile: int, me: int) -> int:
	var n := 0
	for o in alive_ids():
		if o == me:
			continue
		if _cell_of(players[o].position) == tile or (_bot.has(o) and int(_bot[o].tile) == tile):
			n += 1
	return n

func _pick_tile(id: int, b: Dictionary) -> int:
	var p: LabPlayer3D = players[id]
	var best := -1
	var best_s := INF
	for i in layout.size():
		if layout[i] != safe_sym:
			continue
		var s: float = _center(i).distance_to(p.position) + float(_occupancy(i, id)) * 2.2 + randf() * 0.8
		if s < best_s:
			best_s = s
			best = i
	if best >= 0 and hidden_cycle:
		var err: float = float(b.err) * (1.8 if not syms_on else 1.0)
		if randf() < err:
			var c := best % COLS
			var r := best / COLS
			var wrong: Array = []
			for dc in [-1, 0, 1]:
				for dr in [-1, 0, 1]:
					var cc: int = c + dc
					var rr: int = r + dr
					if cc < 0 or cc >= COLS or rr < 0 or rr >= ROWS:
						continue
					var j: int = rr * COLS + cc
					if layout[j] != safe_sym:
						wrong.append(j)
			if not wrong.is_empty():
				best = wrong[randi() % wrong.size()]
	return best

func _bot_brain(delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	if st != St.RUN or clock < float(lock_until[id]):
		return Vector3.ZERO
	var b: Dictionary = _bot[id]
	b.think = float(b.think) - delta
	if float(b.think) <= 0.0:
		b.think = randf_range(0.15, 0.3)
		var here := _cell_of(p.position)
		if ph == Ph.LOCK or ph == Ph.SHAKE:
			if int(b.cycle) != cycle and clock >= lock_end - LOCK_TIMES[mini(cycle, LOCK_TIMES.size() - 1)] + float(b.react):
				b.cycle = cycle
				b.tile = _pick_tile(id, b)
			if int(b.tile) >= 0:
				var t: int = b.tile
				if syms_on and layout[t] == safe_sym and _occupancy(t, id) >= 2 and randf() < 0.25:
					b.tile = _pick_tile(id, b)
					t = b.tile
				b.goal = _center(t) + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
			for o in alive_ids():
				if o == id:
					continue
				var to: Vector3 = players[o].position - p.position
				to.y = 0.0
				if to.length() > 1.3 or clock < float(shove_ready[id]):
					continue
				var contest: bool = _cell_of(players[o].position) == here or _cell_of(players[o].position) == int(b.tile)
				var chance: float = float(b.aggro) * (0.55 if contest else 0.06)
				if ph == Ph.SHAKE and contest:
					chance *= 1.5
				if randf() < chance:
					p.face(to)
					_try_shove(id)
					return Vector3.ZERO
				break
		elif ph == Ph.DOWN:
			b.goal = _center(here)
		else:
			b.wander = float(b.wander) - 0.2
			if float(b.wander) <= 0.0:
				b.wander = randf_range(1.0, 2.5)
				var c := clampi(here % COLS + randi_range(-1, 1), 1, COLS - 2)
				var r := clampi(here / COLS + randi_range(-1, 1), 1, ROWS - 2)
				b.goal = _center(r * COLS + c) + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
			if ph == Ph.SHUFFLE:
				for o in alive_ids():
					if o != id and players[o].position.distance_to(p.position) < 1.1 and randf() < float(b.aggro) * 0.03 and clock >= float(shove_ready[id]):
						p.face(players[o].position - p.position)
						_try_shove(id)
						return Vector3.ZERO
	var goal: Vector3 = b.goal
	var v := goal - p.position
	v.y = 0.0
	if v.length() < 0.2:
		return Vector3.ZERO
	if ph == Ph.DOWN:
		return Vector3.ZERO
	return v.normalized() * clampf(v.length() * 1.8, 0.3, 1.0)
