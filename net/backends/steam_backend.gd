extends MultiplayerBackend
class_name SteamBackend
## Placeholder for the shipping transport.
##
## The real build would, like the game studied, use the `steam-multiplayer-peer`
## GDExtension + GodotSteam:
##   - host:  Steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, max_players)
##            then SteamMultiplayerPeer.create_host(0)
##   - join:  SteamMultiplayerPeer.create_client(lobby_owner_steam_id, 0)
##   - lobby owner == SceneMultiplayer server/relay authority.
## Inactive until those addons are added under res://addons/. See README.

func create_host(_port: int, _max_players: int) -> int:
	push_warning("Steam backend not installed — use ENet. See README §Steam.")
	return ERR_UNAVAILABLE

func create_client(_address: String, _port: int) -> int:
	push_warning("Steam backend not installed — use ENet. See README §Steam.")
	return ERR_UNAVAILABLE
