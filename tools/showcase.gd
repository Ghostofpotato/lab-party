extends Node3D
## Dev tool: lines up subjects with every hat, saves a screenshot, quits.
## godot --path . res://tools/showcase.tscn -- <out.png> [anim]

const HATS := ["fedora", "cone", "tophat", "hardhat", "shades", "party", "bucket", "beanie"]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://showcase.png"
	var pose: String = args[1] if args.size() > 1 else "Idle"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("1a1b1f")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	for i in HATS.size():
		var c := LabCharacter.new()
		c.sex = "male" if i % 2 == 0 else "female"
		c.hat = HATS[i]
		c.suit_color = Globals.SUIT_COLORS[i]
		c.position = Vector3((i - 3.5) * 0.9, 0, 0)
		add_child(c)
		c.play_loop(pose)
	var c0: LabCharacter = get_child(get_child_count() - 1)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.3, 6.2)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.fov = 45
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
