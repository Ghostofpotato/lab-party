extends Node
## Transport-agnostic multiplayer brain. Holds the authoritative roster and the
## session start signal; a MultiplayerBackend installs the actual peer.
## Autoload singleton at /root/NetworkManager (stable path for RPC routing).

signal roster_changed()
signal server_created()
signal connected_to_server()
signal connection_failed()
signal disconnected()
signal game_should_start()

const DEFAULT_PORT: int = 7890
const MAX_PLAYERS: int = 8   # 4 was vanilla; 8 is the modded cap

enum Backend { ENET, STEAM }

var backend: MultiplayerBackend
var backend_type: Backend = Backend.ENET
var local_name: String = "Player"
## Joins as an AI subject: the host drives this player with the minigames' bot brains.
var autopilot: bool = false

## peer_id -> { name:String, is_bot:bool, score:int, color:Color, hat:String, sex:String,
##   suit:Color, pattern:int, hair:Color, hat_tint:String, title:String, title_rarity:int, death_fx:String }
## color stays a distinct per-player colour (name labels, swatches, HUDs); suit is what they wear.
var players: Dictionary = {}

var _next_bot_id: int = 1001
var lan: LanDiscovery

func _ready() -> void:
	lan = LanDiscovery.new()
	lan.name = "LanDiscovery"
	add_child(lan)
	game_should_start.connect(func(): lan.session_started = true)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Profile.loadout_changed.connect(_on_loadout_changed)

func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func _make_backend() -> void:
	match backend_type:
		Backend.STEAM:
			backend = SteamBackend.new()
		_:
			backend = ENetBackend.new()

# --- lifecycle ------------------------------------------------------------

func host(port: int = DEFAULT_PORT) -> int:
	_make_backend()
	var err := backend.create_host(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = backend.peer
	players.clear()
	_next_bot_id = 1001
	_add_player(1, local_name, false, Profile.local_look())
	server_created.emit()
	roster_changed.emit()
	return OK

func join(address: String, port: int = DEFAULT_PORT) -> int:
	_make_backend()
	var err := backend.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = backend.peer
	return OK

## Announce this lab on the LAN until close().
func advertise_lan() -> void:
	if is_server():
		lan.start_beacon(_beacon_info)

func _beacon_info() -> Dictionary:
	return {"host": local_name, "players": players.size(), "max": MAX_PLAYERS, "port": DEFAULT_PORT}

func close() -> void:
	lan.stop_beacon()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	roster_changed.emit()

# --- roster ---------------------------------------------------------------

func _add_player(peer_id: int, pname: String, is_bot: bool, look: Dictionary = {}) -> void:
	var idx := _free_slot()
	var col: Color = Globals.SUIT_COLORS[idx % Globals.SUIT_COLORS.size()]
	players[peer_id] = {
		"name": pname,
		"is_bot": is_bot,
		"score": 0,
		"slot": idx,
		"color": col,
		"suit": col,
		"pattern": 0,
		"hair": Color(0, 0, 0, 0),
		"hat": Globals.HATS[idx % Globals.HATS.size()],
		"hat_tint": "",
		"sex": "male" if idx % 3 != 1 else "female",
		"title": "",
		"title_rarity": 0,
		"death_fx": "blood",
	}
	_apply_look(peer_id, look)

func _free_slot() -> int:
	var used: Array = []
	for id in players:
		used.append(int(players[id].get("slot", -1)))
	var i := 0
	while used.has(i):
		i += 1
	return i

func _apply_look(peer_id: int, look: Dictionary) -> void:
	if not players.has(peer_id):
		return
	var clean := Profile.sanitize_look(look)
	for k in clean:
		players[peer_id][k] = clean[k]

func add_bots(count: int) -> void:
	if not is_server():
		return
	for i in count:
		if players.size() >= MAX_PLAYERS:
			break
		_add_player(_next_bot_id, "Bot %d" % (_next_bot_id - 1000), true)
		_next_bot_id += 1
	_broadcast_roster()

func human_peer_ids() -> Array:
	return players.keys().filter(func(id): return not players[id].is_bot)

func start_game() -> void:
	if not is_server():
		return
	_rpc_start_game.rpc()

func _broadcast_roster() -> void:
	if is_server():
		_rpc_set_roster.rpc(players)

# --- signal handlers ------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	print("[LP] PEER CONNECTED ", _id)
	pass   # client registers itself (see _on_connected)

func _on_peer_disconnected(id: int) -> void:
	print("[LP] PEER LEFT ", id)
	if is_server() and players.has(id):
		players.erase(id)
		_broadcast_roster()

func _on_connected() -> void:
	connected_to_server.emit()
	var look: Dictionary = Profile.local_look()
	if autopilot:
		look["autopilot"] = true
	_rpc_register_me.rpc_id(1, local_name, look)

func _on_loadout_changed() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if is_server():
		_apply_look(1, Profile.local_look())
		_broadcast_roster()
	else:
		_rpc_update_loadout.rpc_id(1, Profile.local_look())

func _on_connection_failed() -> void:
	connection_failed.emit()

func _on_server_disconnected() -> void:
	players.clear()
	roster_changed.emit()
	disconnected.emit()

# --- RPCs -----------------------------------------------------------------

@rpc("any_peer", "reliable")
func _rpc_register_me(pname: String, look: Dictionary = {}) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_add_player(id, pname.left(16), bool(look.get("autopilot", false)), look)
	_broadcast_roster()

@rpc("authority", "call_local", "reliable")
func _rpc_set_roster(new_roster: Dictionary) -> void:
	players = new_roster
	roster_changed.emit()

@rpc("authority", "call_local", "reliable")
func _rpc_start_game() -> void:
	game_should_start.emit()

@rpc("any_peer", "reliable")
func _rpc_update_loadout(look: Dictionary) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id) and GameManager.screen == GameManager.Screen.LOBBY:
		_apply_look(id, look)
		_broadcast_roster()
