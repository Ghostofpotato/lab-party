extends Node
## Dev tool: runs the studio intro, saves a screenshot every 0.5 s, prints INTRO FINISHED.
## godot --path . res://tools/intro_test.tscn -- <prefix> [skip]

var _prefix: String = ""
var _skip: bool = false
var _t: float = 0.0
var _next_shot: float = 0.5
var _n: int = 0
var _ended: bool = false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_prefix = args[0] if args.size() > 0 else "user://intro"
	_skip = args.has("skip")
	var intro: Node = load("res://intro/studio_intro.tscn").instantiate()
	intro.finished.connect(_on_finished.bind(intro))
	add_child(intro)
	if _skip:
		get_tree().create_timer(2.0).timeout.connect(_press)

func _press() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	print("INTRO SKIP SENT t=%.2f" % _t)

func _process(delta: float) -> void:
	_t += delta
	if _t > 25.0:
		print("INTRO TIMEOUT")
		get_tree().quit(1)
	if _ended or DisplayServer.get_name() == "headless" or _t < _next_shot:
		return
	_next_shot += 0.5
	_n += 1
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [_prefix, _n])

func _on_finished(intro: Node) -> void:
	_ended = true
	print("INTRO FINISHED t=%.2f" % _t)
	intro.queue_free()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
