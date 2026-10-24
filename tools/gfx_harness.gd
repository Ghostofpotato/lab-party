extends Node
## Dev harness: spawns LabCharacters (every pattern / anim) under arena-like light and camera, saves screenshots and prints FPS.
## godot --path . res://tools/gfx_harness.tscn -- <shot_prefix> [level 0-2]

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(get_tree().quit)
	var a := OS.get_cmdline_user_args()
	var prefix: String = a[0] if a.size() > 0 else "user://gfxh"
	if a.size() > 1:
		Gfx.auto_adjust = false
		Gfx.set_level(int(a[1]))
	if a.size() > 2:
		get_viewport().mesh_lod_threshold = float(a[2])
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("05060a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.48, 0.62)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.25
	env.fog_enabled = true
	env.fog_density = 0.022
	env.ssao_enabled = true
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.62, 0.72, 1.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50.0, 160.0, 0.0)
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(4, 3, 2)
	lamp.light_energy = 3.0
	lamp.omni_range = 14.0
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.shadow_enabled = true
	add_child(lamp)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.32, 0.28)
	fm.roughness = 0.9
	floor_mi.material_override = fm
	add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	var hats := ["fedora", "hardhat", "cone", "tophat", "beanie", "bucket", "party", "propeller", "goggles", "shades"]
	var anims := ["Jog_Fwd", "Crouch_Idle", "Hit_Chest", "Idle"]
	var chars: Array[LabCharacter] = []
	for i in 20:
		var c := LabCharacter.new()
		c.owner_peer = -1
		c.sex = "male" if i % 2 == 0 else "female"
		c.hat = hats[i % 10]
		c.pattern = i % 10
		c.suit_color = Color.from_hsv((i % 10) / 10.0, 0.55, 0.8)
		c.position = Vector3((i % 5) * 1.7 - 3.4, 0, -(i / 5) * 5.0 + 2.0)
		add_child(c)
		chars.append(c)
	cam.position = Vector3(0, 4.4, 8.4)
	cam.look_at(Vector3(0, 0.9, -4.0))
	await get_tree().create_timer(0.5).timeout
	var n := 0
	for an in anims:
		for c in chars:
			c._dead = false
			c._action_busy = false
			c._locomotion = ""
			c.anim.play(an)
			c.anim.seek(0.4, true)
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, an])
		n += 1
	var t := 0.0
	var f := 0
	var fsum := 0.0
	while t < 4.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > 1.0:
			fsum += Engine.get_frames_per_second()
			f += 1
	print("HARNESS FPS level=", Gfx.level_name(), " avg=", fsum / maxf(f, 1))
	get_tree().quit()
