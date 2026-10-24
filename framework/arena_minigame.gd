extends Minigame
class_name ArenaMinigame
## Base for movement-based minigames. Builds a 2D world sized to the viewport,
## spawns a LabPlayer per roster entry (humans self-owned, bots server-owned),
## and offers alive/eliminate helpers. Subclasses implement the rules in begin()
## and resolve with finished.emit(placement).

const ARENA_SIZE: Vector2 = Vector2(1152, 648)

var world: Node2D
var hud: Control
var players: Dictionary = {}   # peer_id -> LabPlayer

func setup_arena() -> void:
	var bg := ColorRect.new()
	bg.color = Color("10131a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	hud = make_ui_layer()

func spawn_players(points: Array = []) -> void:
	var scene := preload("res://player/player2d.tscn")
	var i := 0
	for id in NetworkManager.players:
		var pl: LabPlayer = scene.instantiate()
		pl.name = "P_%d" % id
		pl.peer_id = id
		pl.is_bot = NetworkManager.players[id].is_bot
		pl.color = NetworkManager.players[id].color
		pl.display_name = NetworkManager.players[id].name
		pl.position = points[i] if i < points.size() else Vector2(140 + i * 150, 120)
		world.add_child(pl)
		players[id] = pl
		i += 1

func alive_ids() -> Array:
	return players.keys().filter(func(id): return is_instance_valid(players[id]) and players[id].alive)

func eliminate(id: int) -> void:
	if players.has(id) and is_instance_valid(players[id]):
		players[id].set_alive(false)

## Standard "survival" placement: current survivors first, then the eliminated
## in reverse order (last out ranks higher). Pass the elimination order you kept.
func survival_placement(elim_order: Array) -> Array:
	var placement: Array = alive_ids()
	for i in range(elim_order.size() - 1, -1, -1):
		if not placement.has(elim_order[i]):
			placement.append(elim_order[i])
	return placement

func hud_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(16, 10)
	l.add_theme_font_size_override("font_size", 22)
	hud.add_child(l)
	return l
