extends Node
## Shared effects: blood, explosions, sparks, screen shake and sound.
## All calls are local and cosmetic; trigger them from synced RPCs so every peer sees them.

var _sfx: Dictionary = {}
var _shake: float = 0.0
var _splat_tex: Texture2D
var post: ColorRect
var _music: AudioStreamPlayer
var _music_name: String = ""

func _ready() -> void:
	for n in ["explosion", "hit", "splat", "beep", "arm", "buzzer", "win", "gunshot", "step", "whoosh", "click", "hum"]:
		_sfx[n] = load("res://assets/sfx/%s.wav" % n)
	_splat_tex = _make_splat()
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/post.gdshader")
	post.material = m
	layer.add_child(post)

var _slow_t: float = 0.0
var _fps_log_t: float = 0.0

func _process(delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	_slow_t = _slow_t + delta if fps < 30.0 else 0.0
	_fps_log_t -= delta
	if _slow_t > 2.0 and _fps_log_t <= 0.0:
		print("[LP] LOW FPS ", fps, " mem=", int(OS.get_static_memory_usage() / 1048576), "MB")
		_fps_log_t = 10.0
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	if _shake > 0.001:
		cam.h_offset = randf_range(-1.0, 1.0) * _shake * 0.35
		cam.v_offset = randf_range(-1.0, 1.0) * _shake * 0.35
		_shake = maxf(_shake - delta * 1.8, 0.0)
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0

func shake(amount: float = 0.5) -> void:
	_shake = maxf(_shake, amount)

func sfx(sound: String, at: Variant = null, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _sfx.has(sound):
		return
	var p: Node
	if at is Vector3 and get_viewport().get_camera_3d():
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 8.0
		p3.max_db = 6.0
		get_tree().current_scene.add_child(p3)
		p3.global_position = at
		p3.stream = _sfx[sound]
		p3.volume_db = volume_db
		p3.pitch_scale = pitch * randf_range(0.93, 1.07)
		p3.play()
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		p2.stream = _sfx[sound]
		p2.volume_db = volume_db
		p2.pitch_scale = pitch
		p2.play()
		p = p2
	p.finished.connect(p.queue_free)

func _burst(parent: Node, pos: Vector3, color: Color, amount: int, spd: float, size: float, life: float, grav: float) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.amount = amount
	gp.lifetime = life
	gp.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = spd * 0.4
	pm.initial_velocity_max = spd
	pm.gravity = Vector3(0, -grav, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color = color
	gp.process_material = pm
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.3
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	gp.draw_pass_1 = m
	parent.add_child(gp)
	gp.global_position = pos
	gp.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(gp.queue_free)
	return gp

func blood(parent: Node, pos: Vector3, amount: int = 60) -> void:
	_burst(parent, pos, Color(0.3, 0.0, 0.015), amount, 4.5, 0.045, 1.1, 14.0)
	var d := Decal.new()
	d.texture_albedo = _splat_tex
	var s := randf_range(1.2, 2.0)
	d.size = Vector3(s, 1.5, s)
	d.modulate = Color(0.3, 0.0, 0.01)
	d.cull_mask = 1
	d.rotation.y = randf() * TAU
	parent.add_child(d)
	d.global_position = Vector3(pos.x, 0.2, pos.z)
	sfx("splat", pos, -2.0)

func explosion(parent: Node, pos: Vector3, power: float = 1.0) -> void:
	_burst(parent, pos, Color(1.0, 0.55, 0.15), int(50 * power), 9.0 * power, 0.07, 0.6, 6.0)
	_smoke(parent, pos, power)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 12.0 * power
	l.omni_range = 7.0 * power
	parent.add_child(l)
	l.global_position = pos + Vector3(0, 0.8, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.45)
	tw.tween_callback(l.queue_free)
	var d := Decal.new()
	d.texture_albedo = _splat_tex
	d.size = Vector3(2.4 * power, 1.5, 2.4 * power)
	d.modulate = Color(0.05, 0.04, 0.035)
	d.cull_mask = 1
	parent.add_child(d)
	d.global_position = Vector3(pos.x, 0.2, pos.z)
	shake(0.6 * power)
	sfx("explosion", pos)

func _smoke(parent: Node, pos: Vector3, power: float) -> void:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.amount = int(14 * power) + 4
	gp.lifetime = 1.8
	gp.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.4 * power
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.scale_min = 1.0
	pm.scale_max = 2.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.25, 0.23, 0.2, 0.55))
	ramp.set_color(1, Color(0.18, 0.18, 0.18, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2) * power
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_tex()
	q.material = mat
	gp.draw_pass_1 = q
	parent.add_child(gp)
	gp.global_position = pos + Vector3(0, 0.4, 0)
	gp.emitting = true
	get_tree().create_timer(2.4).timeout.connect(gp.queue_free)

var _soft: Texture2D
func _soft_tex() -> Texture2D:
	if _soft:
		return _soft
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	_soft = t
	return t

func sparks(parent: Node, pos: Vector3) -> void:
	_burst(parent, pos, Color(1.0, 0.8, 0.35), 24, 6.0, 0.02, 0.5, 12.0)

func _make_splat() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.06
	noise.seed = 7
	for y in n:
		for x in n:
			var dx := (x - n * 0.5) / (n * 0.5)
			var dy := (y - n * 0.5) / (n * 0.5)
			var r := sqrt(dx * dx + dy * dy)
			var v := 1.0 - r + noise.get_noise_2d(x, y) * 0.55
			var drop := noise.get_noise_2d(x * 3.0 + 99.0, y * 3.0) > 0.55 and r < 0.95
			var a := 1.0 if v > 0.45 or drop else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

## Looping background track from assets/music/<name>.ogg|wav with a short crossfade.
func music(track: String, volume_db: float = -10.0) -> void:
	if track == _music_name:
		return
	_music_name = track
	var path := ""
	for ext in ["ogg", "wav"]:
		if ResourceLoader.exists("res://assets/music/%s.%s" % [track, ext]):
			path = "res://assets/music/%s.%s" % [track, ext]
			break
	var old := _music
	if old:
		var tw := old.create_tween()
		tw.tween_property(old, "volume_db", -40.0, 0.8)
		tw.tween_callback(old.queue_free)
	_music = null
	if path == "":
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.volume_db = -40.0
	add_child(_music)
	_music.play()
	_music.create_tween().tween_property(_music, "volume_db", volume_db, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
