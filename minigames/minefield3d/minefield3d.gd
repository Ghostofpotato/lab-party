extends ArenaMinigame3D
## Minefield: the floor is a grid of pressure plates. Plates arm (amber light,
## rising beep) then blow (explosion). Anyone standing on a blowing plate dies.
## More plates arm each wave. Last subject standing wins.

const COLS: int = 12
const ROWS: int = 7
const TIME_LIMIT: float = 50.0

var cell_w: float = W / float(COLS)
var cell_d: float = D / float(ROWS)
var plates: Array[MeshInstance3D] = []
var lamps: Array[OmniLight3D] = []
var elim_order: Array = []
var _alive_label: Label
var _mat_idle: StandardMaterial3D
var _mat_armed: StandardMaterial3D

func begin() -> void:
	setup_arena()
	_build_grid()
	spawn_players(_spawns())
	for id in players:
		players[id].bot_brain = _bot_brain.bind(id)
	hud_title("MINEFIELD  ·  step off the amber plates")
	_alive_label = Label.new()
	_alive_label.position = Vector2(16, 40)
	_alive_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_alive_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_alive_label)
	_update_alive_label()
	if NetworkManager.is_server():
		_run.call_deferred()

func _spawns() -> Array:
	var a: Array = []
	var i := 0
	for id in NetworkManager.players:
		var c := 2 + (i % 4) * 2
		var r := 1 + (i / 4) * 4
		a.append(Vector3((c + 0.5) * cell_w, 0.0, (r + 0.5) * cell_d))
		i += 1
	return a

func _build_grid() -> void:
	_mat_idle = mat("blue_metal_plate", 0.9).duplicate()
	_mat_idle.albedo_color = Color(0.42, 0.44, 0.42)
	_mat_armed = _mat_idle.duplicate()
	_mat_armed.albedo_color = Color(1.0, 0.7, 0.3)
	_mat_armed.emission_enabled = true
	_mat_armed.emission = Color("ff7a10")
	_mat_armed.emission_energy_multiplier = 0.7
	box(Vector3(W + 0.5, 0.14, D + 0.5), Vector3(W * 0.5, 0.0, D * 0.5), mat("metal_grate_rusty", 1.2))
	for r in ROWS:
		for c in COLS:
			var mi := box(Vector3(cell_w * 0.9, 0.1, cell_d * 0.9), Vector3((c + 0.5) * cell_w, 0.1, (r + 0.5) * cell_d), _mat_idle)
			plates.append(mi)
			var l := OmniLight3D.new()
			l.light_color = Color("ff8a20")
			l.light_energy = 0.0
			l.omni_range = 1.8
			l.position = mi.position + Vector3(0, 0.35, 0)
			world.add_child(l)
			lamps.append(l)

func _cell_of(pos: Vector3) -> int:
	var c := clampi(int(pos.x / cell_w), 0, COLS - 1)
	var r := clampi(int(pos.z / cell_d), 0, ROWS - 1)
	return r * COLS + c

func _cell_center(i: int) -> Vector3:
	return plates[i].position

var _armed_now: Array = []

func _bot_brain(delta: float, id: int) -> Vector3:
	var p: LabPlayer3D = players[id]
	var here := _cell_of(p.position)
	if _armed_now.has(here):
		var best := Vector3.ZERO
		var best_d := INF
		for dc in [-1, 0, 1]:
			for dr in [-1, 0, 1]:
				var c: int = (here % COLS) + dc
				var r: int = (here / COLS) + dr
				if c < 0 or c >= COLS or r < 0 or r >= ROWS:
					continue
				var idx: int = r * COLS + c
				if _armed_now.has(idx):
					continue
				var d := _cell_center(idx).distance_to(p.position)
				if d < best_d:
					best_d = d
					best = _cell_center(idx)
		if best_d < INF and randf() > 0.08:
			return (best - p.position).normalized()
	p._bot_t -= delta
	if p._bot_t <= 0.0:
		p._bot_t = randf_range(0.5, 1.4)
		var a := randf() * TAU
		p.bot_dir = Vector3(cos(a), 0.0, sin(a)) * randf_range(0.3, 1.0)
	return p.bot_dir

func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	var t := 0.0
	var danger := 8
	var warn := 1.1
	while alive_ids().size() > 1 and t < TIME_LIMIT:
		var armed: Array = []
		while armed.size() < danger:
			var k := randi() % plates.size()
			if not armed.has(k):
				armed.append(k)
		_rpc_plates.rpc(armed, 1)
		await get_tree().create_timer(warn).timeout
		_rpc_plates.rpc(armed, 2)
		_check_deaths(armed)
		await get_tree().create_timer(0.6).timeout
		_rpc_plates.rpc(armed, 0)
		await get_tree().create_timer(0.35).timeout
		t += warn + 0.95
		danger = mini(danger + 2, 40)
		warn = maxf(warn - 0.04, 0.7)
	finished.emit(survival_placement(elim_order))

func _check_deaths(armed: Array) -> void:
	for id in alive_ids():
		if armed.has(_cell_of(players[id].position)):
			elim_order.append(id)
			_rpc_eliminate.rpc(id)

func _update_alive_label() -> void:
	if _alive_label:
		_alive_label.text = "subjects alive: %d" % alive_ids().size()

@rpc("authority", "call_local", "reliable")
func _rpc_plates(indices: Array, s: int) -> void:
	_armed_now = indices if s == 1 else []
	for i in indices:
		if i < 0 or i >= plates.size():
			continue
		match s:
			1:
				plates[i].material_override = _mat_armed
				lamps[i].light_energy = 2.5
			2:
				plates[i].material_override = _mat_idle
				lamps[i].light_energy = 0.0
			_:
				plates[i].material_override = _mat_idle
				lamps[i].light_energy = 0.0
	if s == 1:
		Fx.sfx("arm", null, -8.0)
	elif s == 2:
		var shown := 0
		for i in indices:
			if shown < 10:
				Fx.explosion(world, _cell_center(i), 0.55)
				shown += 1
		Fx.shake(0.7)

@rpc("authority", "call_local", "reliable")
func _rpc_eliminate(id: int) -> void:
	eliminate(id, "Death01")
	_update_alive_label()
