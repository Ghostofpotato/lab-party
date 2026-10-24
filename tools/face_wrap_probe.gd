extends Node

func _ready() -> void:
	var prefix: String = OS.get_cmdline_user_args()[0]
	get_tree().create_timer(100.0).timeout.connect(get_tree().quit)
	Globals.forced_minigame = "res://minigames/table_manners/table_manners.tscn"
	var main: Node = load("res://Main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	NetworkManager.local_name = "Tester"
	NetworkManager.host()
	NetworkManager.add_bots(2)
	NetworkManager.start_game()
	await get_tree().create_timer(0.3).timeout
	var rd: Node = main.get_node_or_null("RoundDirector")
	rd.get("minigame_pool").assign([Globals.forced_minigame])
	var mg: Node = null
	var t := 0.0
	while t < 20.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		mg = rd.get("current")
		if mg and mg.get("_boss") != null and is_instance_valid(mg.get("_boss")):
			break
	if mg == null:
		print("PROBE no minigame")
		get_tree().quit()
		return
	await get_tree().create_timer(2.0).timeout
	var boss: LabCharacter = mg.get("_boss")
	print("PROBE masked ", mg.get("_boss_masked"))
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		cl.visible = false
	var tw0 = mg.get("_boss_tw")
	if tw0:
		tw0.kill()
	boss.rotation.y = 0.0
	boss.anim.play("Pistol_Aim_Neutral", 0.0)
	await get_tree().create_timer(0.3).timeout
	boss.rotation.y = 0.0
	await RenderingServer.frame_post_draw
	var gimg := get_viewport().get_texture().get_image()
	gimg.save_png("%s_game.png" % prefix)
	gimg.get_region(Rect2i(gimg.get_width() / 2 - 160, int(gimg.get_height() * 0.12), 320, 200)).save_png("%s_gamezoom.png" % prefix)
	var cam := Camera3D.new()
	cam.fov = 30.0
	mg.add_child(cam)
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		cl.visible = false
	var views := {"front": Vector3(0, 0, 1), "q34": Vector3(0.75, 0.05, 0.66), "side": Vector3(1, 0.02, 0), "lowq": Vector3(-0.6, -0.25, 0.75)}
	for anim_name in ["Pistol_Idle", "Pistol_Aim_Neutral", "Pistol_Shoot"]:
		for vk in views:
			if anim_name != "Pistol_Idle" and vk == "lowq":
				continue
			var tw = mg.get("_boss_tw")
			if tw:
				tw.kill()
			boss.rotation.y = 0.0
			boss.anim.play(anim_name, 0.0)
			boss.anim.seek(0.25 if anim_name == "Pistol_Shoot" else 0.5, true)
			boss.anim.pause()
			await get_tree().process_frame
			var sk := boss.skeleton
			var hp := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))
			var face := hp * Vector3(0, 0.08, 0.06)
			var dir: Vector3 = (boss.global_basis * views[vk]).normalized()
			cam.global_position = face + dir * 0.6
			cam.look_at(face, Vector3.UP)
			cam.current = true
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var h := img.get_height()
			var crop := img.get_region(Rect2i((img.get_width() - h) / 2, 0, h, h))
			crop.resize(480, 480, Image.INTERPOLATE_BILINEAR)
			crop.save_png("%s_%s_%s.png" % [prefix, anim_name, vk])
	for mi in boss.skeleton.find_children("*", "MeshInstance3D", false, false):
		for si in mi.mesh.get_surface_count():
			var sm = mi.get_surface_override_material(si)
			if sm is ShaderMaterial and sm.shader.code.contains("face_mix"):
				sm.set_shader_parameter("face_mix", 0.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var ci := get_viewport().get_texture().get_image()
	ci.get_region(Rect2i((ci.get_width() - ci.get_height()) / 2, 0, ci.get_height(), ci.get_height())).save_png("%s_control.png" % prefix)
	boss.anim.play()
	print("PROBE DONE")
	get_tree().quit()
