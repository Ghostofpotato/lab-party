extends Node3D
class_name LabCharacter
## Visual body for a test subject: rigged subject model, per-player suit colour,
## a hat on the head bone, and the shared animation library (UAL1 + UAL2).
## Gameplay code drives it with set_motion() and play_action(); it never moves itself.

const BODY_SCENES := {
	"male": preload("res://assets/characters/subject_male.glb"),
	"female": preload("res://assets/characters/subject_female.glb"),
}
const SUIT_MASKS := {
	"male": preload("res://assets/characters/T_Suit_Male_Mask.png"),
	"female": preload("res://assets/characters/T_Suit_Female_Mask.png"),
}
const ANIM_SOURCES := [
	preload("res://assets/anims/UAL1_Standard.glb"),
	preload("res://assets/anims/UAL2_Standard.glb"),
]
const SUIT_SHADER := preload("res://assets/shaders/suit.gdshader")
const HAIR_COLORS: Array[Color] = [Color("2b1d14"), Color("120d0a"), Color("5a3a22"), Color("6e2c18"), Color("8a6a3a"), Color("3a2c22")]
const PATTERN_COLORS := {1: Color(0.95, 0.74, 0.06), 2: Color(0.2, 0.22, 0.12), 9: Color(0.86, 0.84, 0.76)}
const HAT_TINTS := {"gold": Color(1.0, 0.74, 0.22), "chrome": Color(0.82, 0.85, 0.9), "blood": Color(0.38, 0.02, 0.02), "neon": Color(0.3, 1.0, 0.35), "rust": Color(0.5, 0.24, 0.08)}
const HAT_HEIGHT := {"male": 1.79, "female": 1.75}
const LOOPS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd",
	"Dance", "Driving", "Push", "Sitting_Idle", "Pistol_Idle", "Swim_Fwd",
	"Swim_Idle", "Walk_Carry", "Zombie_Walk_Fwd", "Zombie_Idle", "Idle_FoldArms",
	"Slide", "Jump", "Idle_Talking", "Sitting_Talking", "Idle_TalkingPhone"]

static var _library: AnimationLibrary

@export var sex: String = "male"
@export var hat: String = "hardhat"
@export var suit_color: Color = Color("e2544b")
@export var pattern: int = 0
@export var hair_color: Color = Color(0, 0, 0, 0)
@export var hat_tint: String = ""
@export var death_fx: String = ""
var owner_peer: int = 0

var anim: AnimationPlayer
var skeleton: Skeleton3D
var _body: Node3D
var _suit_mats: Array[ShaderMaterial] = []
var _locomotion: String = ""
var _action_busy: bool = false
var _dead: bool = false

func _ready() -> void:
	if owner_peer == 0:
		_match_roster()
	if not BODY_SCENES.has(sex):
		sex = "male"
	_body = BODY_SCENES[sex].instantiate()
	add_child(_body)
	skeleton = _body.find_child("Skeleton3D", true, false)
	_apply_suit()
	_attach_hat()
	_setup_anims()
	set_motion(0.0)

func apply_look(d: Dictionary, with_hat: bool = true) -> void:
	if d.get("sex", "") is String and BODY_SCENES.has(d.get("sex", "")):
		sex = d.sex
	if d.get("suit") is Color:
		suit_color = d.suit
	elif d.get("color") is Color:
		suit_color = d.color
	if d.get("pattern") is int:
		pattern = d.pattern
	if d.get("hair") is Color:
		hair_color = d.hair
	if with_hat and d.get("hat") is String:
		hat = d.hat
	if d.get("hat_tint") is String:
		hat_tint = d.hat_tint
	if d.get("death_fx") is String:
		death_fx = d.death_fx

func _match_roster() -> void:
	owner_peer = -1
	for id in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[id]
		if info.get("color") is Color and (info.color as Color).is_equal_approx(suit_color):
			owner_peer = id
			var keep_hat := hat
			apply_look(info, false)
			if keep_hat != str(info.get("hat", "")):
				hat_tint = ""
			return

static func shared_library() -> AnimationLibrary:
	if _library:
		return _library
	_library = AnimationLibrary.new()
	for src in ANIM_SOURCES:
		var inst: Node = src.instantiate()
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		for lib_name in ap.get_animation_library_list():
			var lib := ap.get_animation_library(lib_name)
			for a in lib.get_animation_list():
				if _library.has_animation(a):
					continue
				var copy: Animation = lib.get_animation(a).duplicate()
				copy.loop_mode = Animation.LOOP_LINEAR if a in LOOPS else Animation.LOOP_NONE
				_strip_root_motion(copy)
				_library.add_animation(a, copy)
		inst.free()
	return _library

static func _strip_root_motion(a: Animation) -> void:
	for t in range(a.get_track_count() - 1, -1, -1):
		var p := String(a.track_get_path(t))
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D and (p.ends_with(":root")):
			a.remove_track(t)

func _setup_anims() -> void:
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	_body.add_child(anim)
	anim.root_node = anim.get_path_to(_body)
	anim.add_animation_library("", shared_library())
	anim.animation_finished.connect(_on_anim_finished)

func _apply_suit() -> void:
	for mi in _body.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		m.layers = 2
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			if src is StandardMaterial3D and String(src.resource_name).begins_with("MI_Peasant"):
				var sm := ShaderMaterial.new()
				sm.shader = SUIT_SHADER
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("normal_tex", src.normal_texture)
				sm.set_shader_parameter("orm_tex", src.roughness_texture)
				sm.set_shader_parameter("suit_mask", SUIT_MASKS[sex])
				sm.set_shader_parameter("suit_color", suit_color)
				sm.set_shader_parameter("pattern", pattern)
				sm.set_shader_parameter("pattern_color", PATTERN_COLORS.get(pattern, Color(0.9, 0.72, 0.08)))
				m.set_surface_override_material(s, sm)
				_suit_mats.append(sm)
			elif src is StandardMaterial3D and String(src.resource_name).begins_with("MI_Hair"):
				var hm: StandardMaterial3D = src.duplicate()
				hm.albedo_color = hair_color if hair_color.a > 0.5 else HAIR_COLORS[absi(hash(suit_color.to_html())) % HAIR_COLORS.size()]
				m.set_surface_override_material(s, hm)

func set_suit_color(c: Color) -> void:
	suit_color = c
	pattern = 0
	for sm in _suit_mats:
		sm.set_shader_parameter("suit_color", c)
		sm.set_shader_parameter("pattern", 0)

func _attach_hat() -> void:
	if hat == "" or not skeleton:
		return
	var path := "res://assets/hats/hat_%s.glb" % hat
	if not ResourceLoader.exists(path):
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	skeleton.add_child(att)
	var h: Node3D = load(path).instantiate()
	att.add_child(h)
	var head_rest := skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone("Head"))
	var want := Transform3D(Basis(), global_transform * Vector3(0.0, HAT_HEIGHT[sex] - 0.005, 0.0))
	want.basis = global_transform.basis * Basis(Vector3.UP, PI)
	h.transform = head_rest.affine_inverse() * want
	if HAT_TINTS.has(hat_tint):
		_tint_hat(h, HAT_TINTS[hat_tint])

func _tint_hat(h: Node, c: Color) -> void:
	for mi in h.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			var nm := StandardMaterial3D.new()
			if src is StandardMaterial3D:
				nm = src.duplicate()
			nm.albedo_color = c
			match hat_tint:
				"gold", "chrome":
					nm.metallic = 0.85
					nm.roughness = 0.22
					nm.emission_enabled = true
					nm.emission = c * 0.22
				"neon":
					nm.emission_enabled = true
					nm.emission = c
					nm.emission_energy_multiplier = 1.6
				"blood":
					nm.roughness = 0.25
			m.set_surface_override_material(s, nm)

## speed in m/s on the ground plane; picks idle / walk / jog / sprint.
func set_motion(speed: float, crouch: bool = false) -> void:
	if _dead or _action_busy:
		return
	var want := "Idle"
	if crouch:
		want = "Crouch_Fwd" if speed > 0.3 else "Crouch_Idle"
	elif speed > 6.5:
		want = "Sprint"
	elif speed > 2.6:
		want = "Jog_Fwd"
	elif speed > 0.3:
		want = "Walk"
	play_loop(want)

func play_loop(name: String, blend: float = 0.18) -> void:
	if _dead or _locomotion == name or not anim.has_animation(name):
		return
	_locomotion = name
	_action_busy = false
	anim.play(name, blend)

## One-shot action (Punch_Jab, Pistol_Shoot, Hit_Chest, Interact, ...). Returns to locomotion after.
func play_action(name: String, blend: float = 0.1, speed: float = 1.0) -> void:
	if _dead or not anim.has_animation(name):
		return
	_action_busy = true
	_locomotion = ""
	anim.play(name, blend, speed)

func die(anim_name: String = "Death01") -> void:
	if _dead:
		return
	_action_busy = false
	anim.play(anim_name, 0.08)
	_dead = true
	if owner_peer > 0:
		Profile.note_death(owner_peer)
	_death_effect()

func _death_effect() -> void:
	var host: Node = get_parent()
	if death_fx == "" or death_fx == "blood" or not is_inside_tree() or host == null:
		return
	var pos := global_position + Vector3(0, 0.9, 0)
	match death_fx:
		"gore":
			Fx.blood(host, pos, 140)
			Fx.blood(host, pos + Vector3(0.4, 0, 0.3), 80)
		"sparks":
			Fx.sparks(host, pos)
			Fx.sparks(host, pos + Vector3(0, 0.4, 0))
			_burst(host, pos, Color(0.5, 0.8, 1.0), 40, 7.0, 0.02, 0.6, 10.0, -1.0)
			Fx.sfx("buzzer", pos, -10.0, 1.6)
		"ash":
			_burst(host, pos, Color(0.12, 0.11, 0.1), 70, 2.2, 0.09, 2.2, -1.2, -1.0)
			_burst(host, pos, Color(1.0, 0.45, 0.1), 30, 3.5, 0.025, 0.9, 2.0, -1.0)
		"boom":
			Fx.explosion(host, pos, 0.45)
			Fx.blood(host, pos, 120)
		"confetti":
			_burst(host, pos + Vector3(0, 0.5, 0), Color(1.0, 0.2, 0.2), 140, 7.5, 0.05, 2.4, 5.0, 1.0)
			Fx.sfx("win", pos, -10.0, 1.4)
		"gold":
			_burst(host, pos, Color(1.0, 0.78, 0.25), 90, 8.0, 0.03, 1.2, 9.0, 0.0)
			Fx.blood(host, pos, 150)
			Fx.sfx("win", pos, -12.0, 0.8)

func _burst(host: Node, pos: Vector3, color: Color, amount: int, spd: float, size: float, life: float, grav: float, hue: float) -> void:
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.amount = amount
	gp.lifetime = life
	gp.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = spd * 0.4
	pm.initial_velocity_max = spd
	pm.gravity = Vector3(0, -grav, 0)
	pm.damping_min = 0.5
	pm.damping_max = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color = color
	if hue > 0.0:
		pm.hue_variation_min = -hue
		pm.hue_variation_max = hue
		pm.angular_velocity_min = -400.0
		pm.angular_velocity_max = 400.0
	gp.process_material = pm
	var mesh: PrimitiveMesh
	if hue > 0.0:
		var q := QuadMesh.new()
		q.size = Vector2(size * 2.0, size * 1.2)
		mesh = q
	else:
		var sp := SphereMesh.new()
		sp.radius = size
		sp.height = size * 2.0
		sp.radial_segments = 6
		sp.rings = 3
		mesh = sp
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if hue >= 0.0:
		mat.emission_enabled = true
		mat.emission = color * 0.6
	(mesh as PrimitiveMesh).material = mat
	gp.draw_pass_1 = mesh
	host.add_child(gp)
	gp.global_position = pos
	gp.emitting = true
	get_tree().create_timer(life + 0.6).timeout.connect(gp.queue_free)

func revive() -> void:
	_dead = false
	_locomotion = ""
	set_motion(0.0)

func is_dead() -> bool:
	return _dead

func _on_anim_finished(_n: StringName) -> void:
	if _action_busy:
		_action_busy = false
		set_motion(0.0)
