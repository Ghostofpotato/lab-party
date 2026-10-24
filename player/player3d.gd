extends CharacterBody3D
class_name LabPlayer3D
## Networked test subject. Humans own their body (authority = peer), bots are
## server-owned; the owner moves and broadcasts position + facing, everyone else
## lerps. The visible body is a LabCharacter driven from velocity.
## Minigames steer bots by setting bot_dir (or bot_brain), change speed with
## speed, and trigger synced animations with act() / kill().

const RADIUS: float = 0.35
const HEIGHT: float = 1.75

var peer_id: int = 1
var is_bot: bool = false
var color: Color = Color.WHITE
var display_name: String = ""
var hat: String = "hardhat"
var sex: String = "male"
var alive: bool = true

var speed: float = 4.6
var input_enabled: bool = true
var gravity_enabled: bool = false
var bounds: AABB = AABB()
## Bots: set bot_dir directly, or bot_brain = func(delta) -> Vector3 for full control.
var bot_dir: Vector3 = Vector3.ZERO
var bot_brain: Callable
var _bot_t: float = 0.0

var body: LabCharacter
var _label: Label3D
var _title: Label3D
var _target: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _move_speed: float = 0.0

func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	cs.shape = cap
	cs.position.y = HEIGHT * 0.5
	add_child(cs)

	body = LabCharacter.new()
	body.sex = sex
	body.hat = hat
	body.suit_color = color
	body.owner_peer = peer_id
	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	if info.get("color") is Color and (info.color as Color).is_equal_approx(color):
		body.apply_look(info, hat == str(info.get("hat", hat)))
	add_child(body)

	_label = Label3D.new()
	_label.text = display_name
	_label.position = Vector3(0.0, HEIGHT + 0.55, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 26
	_label.outline_size = 10
	_label.modulate = color.lightened(0.35)
	add_child(_label)
	var title: String = str(info.get("title", ""))
	if title != "":
		_title = Label3D.new()
		_title.text = "«%s»" % title
		_title.position = Vector3(0.0, -0.19, 0.0)
		_title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_title.no_depth_test = true
		_title.fixed_size = true
		_title.pixel_size = 0.0011
		_title.font_size = 17
		_title.outline_size = 8
		_title.modulate = Profile.rarity_color(int(info.get("title_rarity", 0))).lightened(0.15)
		_label.add_child(_title)

	set_multiplayer_authority(1 if is_bot else peer_id)
	_target = position
	_last_pos = position

func is_local_human() -> bool:
	return not is_bot and peer_id == multiplayer.get_unique_id()

func set_alive(v: bool) -> void:
	alive = v
	if not v:
		velocity = Vector3.ZERO
		_label.modulate.a = 0.35
		if _title:
			_title.modulate.a = 0.3

func _physics_process(delta: float) -> void:
	if alive and is_multiplayer_authority():
		var dir := _bot_dir(delta) if is_bot else (_input_dir() if input_enabled else Vector3.ZERO)
		var vy := velocity.y
		velocity = Vector3(dir.x, 0.0, dir.z) * speed
		if gravity_enabled:
			velocity.y = vy - 18.0 * delta
		move_and_slide()
		if bounds.size != Vector3.ZERO:
			position.x = clampf(position.x, bounds.position.x, bounds.end.x)
			position.z = clampf(position.z, bounds.position.z, bounds.end.z)
		if dir.length() > 0.1:
			_target_yaw = atan2(dir.x, dir.z)
		_rpc_sync.rpc(position, _target_yaw)
	elif not is_multiplayer_authority():
		position = position.lerp(_target, 0.3)
	body.rotation.y = lerp_angle(body.rotation.y, _target_yaw, 1.0 - exp(-14.0 * delta))
	var flat := Vector3(position.x - _last_pos.x, 0.0, position.z - _last_pos.z)
	_move_speed = lerpf(_move_speed, flat.length() / maxf(delta, 0.0001), 0.25)
	_last_pos = position
	if alive:
		body.set_motion(_move_speed)

func face(dir: Vector3) -> void:
	if dir.length() > 0.01:
		_target_yaw = atan2(dir.x, dir.z)

func _input_dir() -> Vector3:
	var d := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): d.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): d.z += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): d.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): d.x += 1.0
	return d.normalized()

func _bot_dir(delta: float) -> Vector3:
	if bot_brain.is_valid():
		return bot_brain.call(delta)
	_bot_t -= delta
	if _bot_t <= 0.0:
		_bot_t = randf_range(0.4, 1.2)
		var a := randf() * TAU
		bot_dir = Vector3(cos(a), 0.0, sin(a))
	return bot_dir

## Synced one-shot animation on every peer (call from the authority or server).
func act(anim_name: String) -> void:
	_rpc_act.rpc(anim_name)

## Synced death: plays the death animation and leaves the body as a corpse.
func kill(anim_name: String = "Death01") -> void:
	_rpc_kill.rpc(anim_name)

@rpc("any_peer", "call_local", "reliable")
func _rpc_act(anim_name: String) -> void:
	body.play_action(anim_name)

@rpc("any_peer", "call_local", "reliable")
func _rpc_kill(anim_name: String) -> void:
	set_alive(false)
	body.die(anim_name)
	Fx.blood(get_parent(), global_position + Vector3(0, 0.9, 0))

@rpc("any_peer", "unreliable_ordered")
func _rpc_sync(p: Vector3, yaw: float) -> void:
	_target = p
	_target_yaw = yaw
