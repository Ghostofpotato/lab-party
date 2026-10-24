extends Node
## Global config + version. Autoload singleton (see project.godot).

const GAME_VERSION: String = "labparty-0.5.0"

## Same random number on every peer for the current round (map variants etc.).
var round_seed: int = 0

## First player to reach this total wins the session.
var target_score: int = 10

## Suit colours assigned to players/bots in join order.
const SUIT_COLORS: Array[Color] = [
	Color("a33a2c"), Color("2f5684"), Color("5f7236"), Color("b8902a"),
	Color("b8642a"), Color("2c7470"), Color("74304a"), Color("6a6f7c"),
]

const HATS: Array[String] = ["fedora", "cone", "tophat", "hardhat", "shades", "party", "bucket", "beanie", "propeller", "goggles"]

## Every test (minigame). ready = built in 3D and QA'd; only ready tests can be enabled.
const MODES: Array[Dictionary] = [
	{"slug": "minefield3d", "name": "MINEFIELD", "rule": "Step off the amber plates before they blow.", "ready": true, "controls": "WASD move. Plates glow amber, then explode. Get off them in time."},
	{"slug": "duck_hunt", "name": "DUCK HUNT", "rule": "One sniper. Runners power the lift and go kill him.", "ready": true, "controls": "HUNTER: mouse aim, right click / SHIFT scope, left click / SPACE fire. Tower moves at 20 s and 35 s.  RUNNERS: WASD, SHIFT sprint. Bring 3 fuses to the fuse box (hold SPACE), then ride the lift (hold SPACE) and kill the sniper. Stay still 5 s and you are spotted."},
	{"slug": "firearm_factory", "name": "FIREARM FACTORY", "rule": "Build the gun first. Then use it.", "ready": true, "controls": "WASD move. Walk over the 4 gun parts, hold SPACE at your bench to build, SPACE to shoot. Unarmed SPACE punches."},
	{"slug": "table_manners", "name": "TABLE MANNERS", "rule": "Eat while the boss looks away. Caught chewing = shot.", "ready": true, "controls": "Mash SPACE to eat. Too fast and you choke. When the boss clicks his gun and turns (HE'S TURNING), stop. Take a bite while he's watching and he shoots you."},
	{"slug": "tunnel_hazard", "name": "TUNNEL HAZARD", "rule": "Reach the end of the tunnel. Trains do not stop.", "ready": true, "controls": "W run, A / D change lane, SPACE shove. A red lane means a train is coming."},
	{"slug": "inside_job", "name": "INSIDE JOB", "rule": "Someone has the syringe. Do not let them reach you.", "ready": true, "controls": "WASD move. Infected: SPACE stabs. Clean: hide in the dark and run."},
	{"slug": "smoke_break", "name": "SMOKE BREAK", "rule": "Smoke the most. Never inhale in a gust.", "ready": true, "controls": "Hold SPACE to inhale, release to exhale. Never inhale during a GUST. Drags over 1.4 s hurt. Stop for 6 s and you get shot."},
	{"slug": "chisel_gauntlet", "name": "CHISEL GAUNTLET", "rule": "Memorize the shape. Carve it. Submit.", "ready": true, "controls": "Memorize the green shape. Click blocks to chisel them off, A / D rotate, R reset, SPACE submit. Worst carver dies."},
	{"slug": "the_filter", "name": "THE FILTER", "rule": "Sort every item into the right bin.", "ready": true, "controls": "WASD move. SPACE grabs junk off the belt, SPACE at the right bin drops it. 3 wrong bins and you burn."},
	{"slug": "forklift_certified", "name": "FORKLIFT CERTIFIED", "rule": "Deliver the pallets. Mind the dock edge.", "ready": true, "controls": "W / S drive, A / D steer, E / Q forks up / down. Lift a pallet, bring it to your coloured bay. Mind the dock edge."},
	{"slug": "stable_footing", "name": "STABLE FOOTING", "rule": "Stand on the safe symbol. Everything else drops.", "ready": true, "controls": "WASD move. Stand on a tile with the SAFE symbol before the floor drops. SPACE shoves."},
	{"slug": "quick_draw", "name": "QUICK DRAW", "rule": "Wait for green. The slowest gets shot.", "ready": true, "controls": "Wait for GREEN, then press SPACE as fast as you can. Too early and the supervisor shoots you."},
	{"slug": "lethal_rebound", "name": "LETHAL REBOUND", "rule": "Push rivals into the saws.", "ready": true, "controls": "WASD move, SPACE dash and shove. Push rivals into the saws."},
	{"slug": "wrong_way", "name": "WRONG WAY", "rule": "Climb the escalator. It goes down.", "ready": true, "controls": "Tap A and D one after the other to climb. Same key twice = you stumble. SPACE shoves or hops lanes."},
	{"slug": "duck_hunt_classic", "name": "DUCK HUNT CLASSIC", "rule": "One sniper on the tower. Everyone else runs for the gate. Everyone hunts once.", "ready": true, "controls": "HUNTER: mouse aim, right click / SHIFT cycles 3 scope levels, left click / SPACE fire, wheel = sensitivity. DUCKS: WASD run to the EXIT, hold SPACE to crouch behind cover. 2 body hits or 1 headshot kills. Red laser = he is scoped in."},
	{"slug": "spine_breaker", "name": "SPINE BREAKER", "rule": "Something is loose in the cell block. Do not get caught.", "ready": true, "controls": "WASD move, hold SPACE to sprint (stamina). E or left click shoves a rival toward it. Watch for the roar before it lunges."},
	{"slug": "seat_assignment", "name": "SEAT ASSIGNMENT", "rule": "When the radio stops, sit. One chair short.", "ready": true, "controls": "WASD move around the chairs. When the music stops, walk into a free chair. SPACE shoves."},
	{"slug": "roomba_rampage", "name": "ROOMBA RAMPAGE", "rule": "The cleaners have blades now.", "ready": true, "controls": "WASD move, SPACE dive roll (short dodge). Watch for new hatches opening."},
	{"slug": "short_fuse", "name": "SHORT FUSE", "rule": "Your collar is counting down. Reset it at a terminal.", "ready": true, "controls": "WASD move. Hold SPACE at a green terminal to reset your collar. SPACE near someone at a terminal shoves them off."},
	{"slug": "live_wire", "name": "LIVE WIRE", "rule": "Do not be holding the battery when it blows.", "ready": true, "controls": "WASD move. Holding the battery: touch someone or press SPACE next to them to pass it."},
	{"slug": "gas_chamber", "name": "GAS CHAMBER", "rule": "Keep a mask on. There are never enough.", "ready": true, "controls": "WASD move. Walk over a mask to wear it. SPACE next to a masked rival rips it off (50% it is yours). Filters crack after 12 s."},
]

## Slugs the host enabled in the lobby (empty = all ready modes).
var enabled_modes: Array[String] = []

func mode_info(slug: String) -> Dictionary:
	for m in MODES:
		if m.slug == slug:
			return m
	return {"slug": slug, "name": slug.to_upper(), "rule": "", "ready": false}

func mode_path(slug: String) -> String:
	return "res://minigames/%s/%s.tscn" % [slug, slug]

func active_mode_paths() -> Array[String]:
	var out: Array[String] = []
	for m in MODES:
		if m.ready and (enabled_modes.is_empty() or enabled_modes.has(m.slug)):
			out.append(mode_path(m.slug))
	return out

## Dev/test: when set, the round director only plays this minigame scene.
var forced_minigame: String = ""
