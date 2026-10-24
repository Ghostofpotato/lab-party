extends ArenaMinigame
## Minefield — reference arena minigame. A grid floor; cells arm (yellow) then
## detonate (red). Stand on a detonating cell and you're out. Last disc standing
## wins. Proves movement + networked hazards + elimination + placement.

const COLS: int = 12
const ROWS: int = 7
const CELL: Vector2 = Vector2(96, 90)
const ORIGIN: Vector2 = Vector2(0, 18)
const TIME_LIMIT: float = 45.0

var cells: Array[ColorRect] = []
var elim_order: Array = []
var _alive_label: Label

func begin() -> void:
	setup_arena()
	_build_grid()
	spawn_players(_spawns())
	hud_title("MINEFIELD — don't stand on red")
	_alive_label = Label.new()
	_alive_label.position = Vector2(16, 40)
	hud.add_child(_alive_label)
	_update_alive_label()
	if NetworkManager.is_server():
		_run.call_deferred()

func _spawns() -> Array:
	var a: Array = []
	var i := 0
	for id in NetworkManager.players:
		var c := 2 + (i % 4) * 2
		var r := 1 + (i / 4) * 2
		a.append(ORIGIN + Vector2(c + 0.5, r + 0.5) * CELL)
		i += 1
	return a

func _build_grid() -> void:
	for r in ROWS:
		for c in COLS:
			var cr := ColorRect.new()
			cr.position = ORIGIN + Vector2(c, r) * CELL
			cr.size = CELL - Vector2(5, 5)
			cr.color = _state_color(0)
			world.add_child(cr)
			cells.append(cr)

func _state_color(s: int) -> Color:
	match s:
		1: return Color("e2c84b")   # armed
		2: return Color("e2544b")   # boom
		_: return Color("1a2030")   # safe

func _cell_of(pos: Vector2) -> int:
	var c := clampi(int((pos.x - ORIGIN.x) / CELL.x), 0, COLS - 1)
	var r := clampi(int((pos.y - ORIGIN.y) / CELL.y), 0, ROWS - 1)
	return r * COLS + c

# --- server loop ----------------------------------------------------------

func _run() -> void:
	var t := 0.0
	var danger := 7
	while alive_ids().size() > 1 and t < TIME_LIMIT:
		var armed: Array = []
		for i in danger:
			armed.append(randi() % cells.size())
		_rpc_cells.rpc(armed, 1)
		await get_tree().create_timer(0.9).timeout
		_rpc_cells.rpc(armed, 2)
		_check_deaths(armed)
		await get_tree().create_timer(0.7).timeout
		_rpc_cells.rpc(armed, 0)
		await get_tree().create_timer(0.3).timeout
		t += 1.9
		danger = min(danger + 1, 16)
	_finish()

func _check_deaths(armed: Array) -> void:
	for id in alive_ids():
		if armed.has(_cell_of(players[id].position)):
			elim_order.append(id)
			_rpc_eliminate.rpc(id)

func _finish() -> void:
	finished.emit(survival_placement(elim_order))

func _update_alive_label() -> void:
	if _alive_label:
		_alive_label.text = "alive: %d" % alive_ids().size()

# --- display RPCs ---------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _rpc_cells(indices: Array, s: int) -> void:
	for i in indices:
		if i >= 0 and i < cells.size():
			cells[i].color = _state_color(s)

@rpc("authority", "call_local", "reliable")
func _rpc_eliminate(id: int) -> void:
	eliminate(id)
	_update_alive_label()
