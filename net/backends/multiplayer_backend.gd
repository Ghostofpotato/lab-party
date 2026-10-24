extends RefCounted
class_name MultiplayerBackend
## Strategy base. A backend installs a MultiplayerPeer and nothing else — all
## roster/game logic lives in NetworkManager, so swapping transport is cheap.
## On success the backend sets `peer`; NetworkManager installs it on the
## SceneTree multiplayer (a RefCounted can't touch `multiplayer` itself).

var peer: MultiplayerPeer

func create_host(_port: int, _max_players: int) -> int:
	return ERR_UNAVAILABLE

func create_client(_address: String, _port: int) -> int:
	return ERR_UNAVAILABLE
