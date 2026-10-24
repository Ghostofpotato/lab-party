extends Node
## Dev harness: host + 3 bots play only Inside Job while a joined client auto-stabs
## (teleports beside the nearest clean subject and taps SPACE whenever infected).
## Both sides log every round so you can check the client sees each reset and the
## server accepts its stabs. godot --headless ... res://tools/inside_job_net_test.tscn -- host|client <seconds>

const PATH := "res://minigames/inside_job/inside_job.tscn"

var role: String = ""
var _seen_round: int = 0
var _press_t: float = 0.0
var _down: bool = false
var _near_t: float = 0.0
var _presses: int = 0
var _srv_hits: Dictionary = {}

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	var secs: float = float(a[1])
	get_tree().create_timer(secs).timeout.connect(_quit)
	var main: Node = load("res://Main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	if role == "host":
		NetworkManager.local_name = "Host"
		Globals.forced_minigame = PATH
		NetworkManager.host()
		GameManager.go(GameManager.Screen.LOBBY)
		NetworkManager.add_bots(3)
		await get_tree().create_timer(6.0).timeout
		print("[IJNET] host starting with ", NetworkManager.players.size(), " players")
		NetworkManager.start_game()
	else:
		NetworkManager.local_name = "Client"
		NetworkManager.join("127.0.0.1")

func _quit() -> void:
	print("[IJNET] %s quit presses=%d" % [role, _presses])
	get_tree().quit()

func _mg() -> Node:
	var rd: Node = get_tree().root.find_child("RoundDirector", true, false)
	if rd == null:
		return null
	var c: Variant = rd.get("current")
	if c is Node and is_instance_valid(c) and String((c as Node).scene_file_path) == PATH:
		return c
	return null

func _client_id() -> int:
	for id in NetworkManager.players:
		if id != 1 and not NetworkManager.players[id].get("is_bot", false):
			return id
	return 0

func _physics_process(delta: float) -> void:
	var mg := _mg()
	if mg == null:
		return
	var r: int = mg.get("_round")
	if r != _seen_round:
		if role == "host" and _seen_round > 0:
			print("[IJNET] host round %d done: client hits=%d tally=%s" % [_seen_round, int(_srv_hits.get(_seen_round, 0)), str(mg.get("_tally"))])
		_seen_round = r
		print("[IJNET] %s sees ROUND %d/%d zero=%d me=%d" % [role, r, int(mg.get("_rounds")), int(mg.get("zero_id")), multiplayer.get_unique_id()])
	if role == "host":
		var cid := _client_id()
		var ib: Dictionary = mg.get("infected_by")
		if cid != 0 and ib.has(cid):
			_srv_hits[r] = maxi(int(_srv_hits.get(r, 0)), int(ib[cid]))
		return
	var live: bool = mg.get("_live")
	var lp: LabPlayer3D = mg.local_player()
	var inf: Array = mg.get("infected")
	if not live or lp == null or not lp.alive or not inf.has(lp.peer_id) or float(mg.get("stun").get(lp.peer_id, 0.0)) > 0.0:
		_near_t = 0.0
		_key(false)
		return
	var best: LabPlayer3D = null
	var bd := INF
	var ps: Dictionary = mg.get("players")
	for id in ps:
		var p: LabPlayer3D = ps[id]
		if p == lp or not p.alive or inf.has(id):
			continue
		var d := p.position.distance_to(lp.position)
		if d < bd:
			bd = d
			best = p
	if best == null:
		_key(false)
		return
	var dir := best.position - lp.position
	dir.y = 0.0
	if dir.length() > 0.55:
		lp.position = best.position - dir.normalized() * 0.5
		lp._target = lp.position
	lp.face(dir)
	_near_t += delta
	_press_t -= delta
	if _near_t > 0.2 and _press_t <= 0.0:
		_press_t = 0.45
		_key(not _down)
		if _down:
			_presses += 1
			print("[IJNET] client SPACE round %d target=%s" % [_seen_round, best.display_name])

func _key(v: bool) -> void:
	if v == _down:
		return
	_down = v
	var e := InputEventKey.new()
	e.physical_keycode = KEY_SPACE
	e.keycode = KEY_SPACE
	e.pressed = v
	Input.parse_input_event(e)
