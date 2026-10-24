extends CharacterBody2D
class_name LabPlayer
## Grey-box player: a coloured disc. Humans own their own body (authority =
## their peer); bots are owned by the server (authority 1). Owner reads input /
## AI, moves, and broadcasts position; everyone else lerps to the last sync.

const SPEED: float = 230.0
const RADIUS: float = 16.0

var peer_id: int = 1
var is_bot: bool = false
var color: Color = Color.WHITE
var display_name: String = ""
var alive: bool = true

var _target: Vector2 = Vector2.ZERO
var _bot_dir: Vector2 = Vector2.ZERO
var _bot_t: float = 0.0

func _ready() -> void:
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = RADIUS
	cs.shape = sh
	add_child(cs)
	set_multiplayer_authority(1 if is_bot else peer_id)
	_target = position
	var label := Label.new()
	label.text = display_name
	label.position = Vector2(-26, -44)
	add_child(label)
	queue_redraw()

func set_alive(v: bool) -> void:
	alive = v
	modulate.a = 1.0 if v else 0.25
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 28, Color(0, 0, 0, 0.6), 2.0)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if is_multiplayer_authority():
		var dir := _bot_logic(delta) if is_bot else _input_dir()
		velocity = dir * SPEED
		move_and_slide()
		position = position.clamp(Vector2(RADIUS, RADIUS), ArenaMinigame.ARENA_SIZE - Vector2(RADIUS, RADIUS))
		_rpc_sync.rpc(position)
	else:
		position = position.lerp(_target, 0.3)

func _input_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): d.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): d.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): d.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): d.x += 1.0
	return d.normalized()

## Default bot wander. Minigames can set _bot_dir directly for smarter AI.
func _bot_logic(delta: float) -> Vector2:
	_bot_t -= delta
	if _bot_t <= 0.0:
		_bot_t = randf_range(0.4, 1.2)
		_bot_dir = Vector2.from_angle(randf() * TAU)
	return _bot_dir

@rpc("any_peer", "unreliable_ordered")
func _rpc_sync(p: Vector2) -> void:
	_target = p
