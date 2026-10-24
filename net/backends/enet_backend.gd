extends MultiplayerBackend
class_name ENetBackend
## Direct ENet/UDP transport — works on LAN and 127.0.0.1 with no extra deps.
## This is the active backend for development and local play.

func create_host(port: int, max_players: int) -> int:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, max_players)
	if err != OK:
		return err
	peer = p
	return OK

func create_client(address: String, port: int) -> int:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(address, port)
	if err != OK:
		return err
	peer = p
	return OK
