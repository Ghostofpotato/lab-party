extends Node
class_name LanDiscovery
## LAN lab discovery over UDP. A host sends a small JSON beacon every second to
## the broadcast addresses on DISCOVERY_PORT; the main menu listens there and
## keeps a list of labs, dropping any not heard from for EXPIRY_MS.

signal labs_changed()

const GAME_ID := "labparty"
const DISCOVERY_PORT: int = 7891
const INTERVAL: float = 1.0
const EXPIRY_MS: int = 4000

var beacon_info: Callable
var session_started: bool = false

var _sender: PacketPeerUDP
var _listener: PacketPeerUDP
var _timer: Timer
var _targets: PackedStringArray = []
var _sid: String = ""
var _labs: Dictionary = {}
var _signature: String = ""

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = INTERVAL
	_timer.timeout.connect(_send_beacon)
	add_child(_timer)
	set_process(false)

## --- host side ---------------------------------------------------------------

func start_beacon(info: Callable) -> void:
	stop_beacon()
	beacon_info = info
	session_started = false
	_sid = "%08x%08x" % [randi(), Time.get_ticks_usec() & 0x7fffffff]
	_sender = PacketPeerUDP.new()
	_sender.set_broadcast_enabled(true)
	if _sender.bind(0, "0.0.0.0") != OK:
		push_warning("LAN beacon could not open a socket")
		_sender = null
		return
	_targets = broadcast_targets()
	print("[LP] LAN beacon on ", DISCOVERY_PORT, " -> ", _targets)
	_send_beacon()
	_timer.start()

func stop_beacon() -> void:
	_timer.stop()
	if _sender:
		_sender.close()
	_sender = null

func is_beaconing() -> bool:
	return _sender != null

func _send_beacon() -> void:
	if _sender == null:
		return
	var info: Dictionary = beacon_info.call() if beacon_info.is_valid() else {}
	info["game"] = GAME_ID
	info["build"] = Updater.BUILD
	info["sid"] = _sid
	info["started"] = session_started
	var pkt := JSON.stringify(info).to_utf8_buffer()
	for addr in _targets:
		_sender.set_dest_address(addr, DISCOVERY_PORT)
		_sender.put_packet(pkt)

## Limited broadcast, a /24 broadcast per IPv4 interface (Windows sends limited
## broadcast out of one NIC only), and loopback for a second copy on this PC.
static func broadcast_targets() -> PackedStringArray:
	var out: PackedStringArray = ["255.255.255.255"]
	for iface in IP.get_local_interfaces():
		for a: String in iface.get("addresses", []):
			if a.contains(":") or a.begins_with("127."):
				continue
			var p := a.split(".")
			if p.size() == 4:
				var b := "%s.%s.%s.255" % [p[0], p[1], p[2]]
				if not out.has(b):
					out.append(b)
	if not OS.has_feature("windows"):
		out.append("127.255.255.255")
	out.append("127.0.0.1")
	return out

## --- menu side ---------------------------------------------------------------

func start_listening() -> bool:
	if _listener:
		return true
	_labs.clear()
	_signature = ""
	var l := PacketPeerUDP.new()
	var err := l.bind(DISCOVERY_PORT, "0.0.0.0")
	if err != OK:
		print("[LP] LAN listen failed on ", DISCOVERY_PORT, " err ", err)
		return false
	_listener = l
	set_process(true)
	return true

func stop_listening() -> void:
	set_process(false)
	if _listener:
		_listener.close()
	_listener = null
	if not _labs.is_empty():
		_labs.clear()
		_signature = ""
		labs_changed.emit()

func is_listening() -> bool:
	return _listener != null

## Discovered labs, oldest first: {sid, ip, port, host, players, max, build, started}.
func labs() -> Array:
	var out: Array = _labs.values()
	out.sort_custom(func(a, b): return a.first < b.first)
	return out

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	while _listener and _listener.get_available_packet_count() > 0:
		var pkt := _listener.get_packet()
		var ip := _listener.get_packet_ip()
		if pkt.size() > 1024:
			continue
		var d: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if not d is Dictionary or d.get("game", "") != GAME_ID:
			continue
		var sid := str(d.get("sid", "")).left(32)
		if sid == "":
			continue
		var prev: Dictionary = _labs.get(sid, {})
		if not prev.is_empty() and not str(prev.ip).begins_with("127.") and ip.begins_with("127."):
			ip = prev.ip
		_labs[sid] = {
			"sid": sid,
			"ip": ip,
			"port": clampi(int(d.get("port", NetworkManager.DEFAULT_PORT)), 1, 65535),
			"host": str(d.get("host", "Unknown")).strip_edges().left(16),
			"players": maxi(int(d.get("players", 0)), 0),
			"max": maxi(int(d.get("max", NetworkManager.MAX_PLAYERS)), 1),
			"build": int(d.get("build", 0)),
			"started": bool(d.get("started", false)),
			"seen": now,
			"first": prev.get("first", now),
		}
	for sid in _labs.keys():
		if now - int(_labs[sid].seen) > EXPIRY_MS:
			_labs.erase(sid)
	var sig := ""
	for l in labs():
		sig += "%s|%s|%s|%d|%d|%d|%s;" % [l.sid, l.ip, l.host, l.players, l.max, l.build, l.started]
	if sig != _signature:
		_signature = sig
		labs_changed.emit()
