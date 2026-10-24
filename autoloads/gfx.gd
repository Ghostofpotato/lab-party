extends Node
## Graphics quality: LOW / MEDIUM / HIGH, saved per machine. Applies to every
## light, environment and the 3D render scale as nodes enter the tree, and steps
## down automatically when a match runs below 35 FPS. F3 toggles an FPS counter.

enum Q { LOW, MEDIUM, HIGH }

const SETTINGS := "user://settings.cfg"
const NAMES := ["LOW", "MEDIUM", "HIGH"]

var level: int = Q.HIGH
var auto_adjust: bool = true
var _fps_label: Label
var _low_t: float = 0.0
var _cooldown: float = 8.0

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		level = int(cfg.get_value("gfx", "level", Q.HIGH))
		auto_adjust = bool(cfg.get_value("gfx", "auto", true))
	elif _looks_weak():
		level = Q.LOW
	get_tree().node_added.connect(_on_node_added)
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_fps_label = Label.new()
	_fps_label.position = Vector2(8, 620)
	_fps_label.visible = false
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(_fps_label)
	_apply_viewport()

func _looks_weak() -> bool:
	var name := RenderingServer.get_video_adapter_name().to_lower()
	var vendor := RenderingServer.get_video_adapter_vendor().to_lower()
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return true
	return "intel" in vendor or "intel" in name or "llvmpipe" in name or "microsoft basic" in name

func set_level(l: int) -> void:
	level = clampi(l, Q.LOW, Q.HIGH)
	_save()
	_apply_viewport()
	_apply_tree(get_tree().root)

func cycle() -> void:
	set_level((level + 2) % 3)

func level_name() -> String:
	return NAMES[level]

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("gfx", "level", level)
	cfg.set_value("gfx", "auto", auto_adjust)
	cfg.save(SETTINGS)

func _apply_viewport() -> void:
	var vp := get_viewport()
	vp.use_debanding = level != Q.LOW
	vp.mesh_lod_threshold = 0.0 if level == Q.HIGH else 0.6
	match level:
		Q.LOW:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = 0.67
			vp.fsr_sharpness = 0.12
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			RenderingServer.directional_shadow_atlas_set_size(1024, false)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		Q.MEDIUM:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = 0.85
			vp.fsr_sharpness = 0.18
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		_:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)

func _apply_tree(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_apply_tree(c)

func _on_node_added(n: Node) -> void:
	if n is Light3D:
		_tune_light.call_deferred(n)
	elif n is WorldEnvironment:
		_tune_env.call_deferred(n)
	elif n is GPUParticles3D and level == Q.LOW:
		var p: GPUParticles3D = n
		p.amount = maxi(4, p.amount / 2)

func _tune_light(l: Light3D) -> void:
	if not is_instance_valid(l):
		return
	if not l.has_meta("gfx_shadow"):
		l.set_meta("gfx_shadow", l.shadow_enabled)
		l.set_meta("gfx_ang", l.light_angular_distance)
	var want: bool = l.get_meta("gfx_shadow")
	if level == Q.LOW:
		want = false
	elif level == Q.MEDIUM and not (l is DirectionalLight3D):
		want = false
	l.shadow_enabled = want
	l.shadow_normal_bias = maxf(l.shadow_normal_bias, 1.6)
	l.shadow_blur = 1.4 if level == Q.HIGH else 1.0
	if l is DirectionalLight3D and level == Q.HIGH:
		l.light_angular_distance = maxf(l.light_angular_distance, 0.35)
	elif l is DirectionalLight3D:
		l.light_angular_distance = float(l.get_meta("gfx_ang"))

func _tune_env(w: WorldEnvironment) -> void:
	if not is_instance_valid(w) or w.environment == null:
		return
	var e := w.environment
	if not e.has_meta("gfx_orig"):
		e.set_meta("gfx_orig", [e.ssao_enabled, e.ssil_enabled, e.glow_enabled, e.volumetric_fog_enabled, e.sdfgi_enabled, e.ssr_enabled])
	var o: Array = e.get_meta("gfx_orig")
	var hi := level == Q.HIGH
	e.ssao_enabled = hi
	if hi and not bool(o[0]):
		e.ssao_radius = 0.9
		e.ssao_intensity = 2.2
		e.ssao_power = 1.6
		e.ssao_detail = 0.6
		e.ssao_light_affect = 0.25
	e.ssil_enabled = o[1] and hi
	e.glow_enabled = o[2] and level != Q.LOW
	e.volumetric_fog_enabled = o[3] and hi
	e.sdfgi_enabled = o[4] and hi
	e.ssr_enabled = o[5] and hi

func _process(delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	if _fps_label.visible:
		_fps_label.text = "%d FPS  ·  %s" % [fps, NAMES[level]]
	_cooldown -= delta
	if not auto_adjust or level == Q.LOW or _cooldown > 0.0 or GameManager.screen != GameManager.Screen.SESSION:
		_low_t = 0.0
		return
	_low_t = _low_t + delta if fps < 35.0 else maxf(_low_t - delta, 0.0)
	if _low_t > 4.0:
		_low_t = 0.0
		_cooldown = 10.0
		set_level(level - 1)
		print("[LP] GFX auto -> ", NAMES[level], " fps=", fps)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_fps_label.visible = not _fps_label.visible
