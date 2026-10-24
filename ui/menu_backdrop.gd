extends ArenaMinigame3D
class_name MenuBackdrop
## Live 3D scene behind the menu and lobby: the current subjects lined up in a
## test chamber under the lamps, idling, with a slow camera drift. showcase()
## switches to one close-up subject on a slow turntable (wardrobe preview).

const POSES := ["Idle", "Idle_FoldArms", "Dance", "Idle_TalkingPhone", "Idle", "Zombie_Idle", "Idle_Rail", "Yes"]

var subjects: Array = []
var showcase_mode: bool = false
var spin: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	setup_arena()
	hud.get_parent().queue_free()
	if subjects.is_empty():
		refresh([])

## lineup: Array of roster-style looks {color, suit, hat, sex, pattern, hair, hat_tint, death_fx}; empty = a demo lineup.
func refresh(lineup: Array) -> void:
	showcase_mode = false
	_clear_subjects()
	if lineup.is_empty():
		for i in 6:
			lineup.append({"color": Globals.SUIT_COLORS[i], "hat": Globals.HATS[i], "sex": "male" if i % 3 != 1 else "female"})
	var n := lineup.size()
	for i in n:
		var c := LabCharacter.new()
		c.owner_peer = -1
		c.apply_look(lineup[i])
		world.add_child(c)
		c.position = Vector3(W * 0.62 + (i - (n - 1) * 0.5) * 1.15, 0.0, D * 0.55 + absf(i - (n - 1) * 0.5) * 0.25)
		c.rotation.y = deg_to_rad(randf_range(-15.0, 15.0))
		c.play_loop(POSES[i % POSES.size()])
		subjects.append(c)

func showcase(look: Dictionary, pose: String = "Idle") -> LabCharacter:
	showcase_mode = true
	_clear_subjects()
	var c := LabCharacter.new()
	c.owner_peer = -1
	c.apply_look(look)
	world.add_child(c)
	c.position = Vector3(W * 0.5, 0.0, D * 0.55)
	c.rotation.y = spin
	c.play_loop(pose)
	subjects.append(c)
	return c

func _clear_subjects() -> void:
	for s in subjects:
		if is_instance_valid(s):
			s.queue_free()
	subjects.clear()

func _process(delta: float) -> void:
	_t += delta
	if showcase_mode:
		spin += delta * 0.55
		for s in subjects:
			if is_instance_valid(s):
				s.rotation.y = spin
		camera.position = Vector3(W * 0.5 - 1.05, 1.35, D * 0.55 + 3.5)
		camera.look_at(Vector3(W * 0.5 - 1.05, 0.95, D * 0.55), Vector3.UP)
		return
	camera.position = Vector3(W * 0.5 + sin(_t * 0.12) * 0.6, 3.1, D * 0.55 + 6.6)
	camera.look_at(Vector3(W * 0.5 + 0.2, 1.25, D * 0.55), Vector3.UP)
