extends Node
## Dev harness (headless): feeds fake round / match results into Profile, prints
## stat progress and unlocks, checks catalog integrity and the save/load round trip.
## godot --headless --path . res://tools/profile_test.tscn

var fails: int = 0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func _ready() -> void:
	var path := "user://profile_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.use_save_path(path)
	check(Profile.stats.is_empty() and Profile.unlocked_ids.is_empty(), "fresh profile is empty")

	var per := [0, 0, 0, 0]
	var free := 0
	for it in Profile.ITEMS:
		per[it.r] += 1
		if it.get("free", false):
			free += 1
		elif Profile.challenge_for(it.id).is_empty():
			check(false, "item without challenge: " + it.id)
	print("ITEMS total=%d common=%d rare=%d epic=%d legendary=%d starters=%d" % [Profile.ITEMS.size(), per[0], per[1], per[2], per[3], free])
	print("CHALLENGES ", Profile.CHALLENGES.size())
	var rewards := {}
	for c in Profile.CHALLENGES:
		if Profile.item(c.reward).is_empty():
			check(false, "missing reward " + c.reward)
		if rewards.has(c.reward):
			check(false, "reward used twice " + c.reward)
		rewards[c.reward] = true
		if c.stat.begins_with("m."):
			var slug: String = c.stat.split(".")[1]
			if Globals.mode_info(slug).get("ready", false) == false:
				check(false, "challenge for unknown mode " + c.stat)
	var modes_with := {}
	for c in Profile.CHALLENGES:
		if c.stat.begins_with("m."):
			modes_with[c.stat.split(".")[1]] = true
	check(modes_with.size() == Globals.MODES.size(), "every mode has challenges (%d/%d)" % [modes_with.size(), Globals.MODES.size()])

	var got: Array[String] = []
	got.append_array(Profile.apply_round("duck_hunt", {"place": 2, "count": 6, "died": false, "role": "runner"}))
	print("round1 unlocked ", got)
	check(got.has("title_expendable"), "first round unlocks Expendable")
	check(Profile.stat("m.duck_hunt.runner_survived") == 1, "runner survival counted")
	for i in 9:
		got.append_array(Profile.apply_round("duck_hunt", {"place": 3, "count": 6, "died": false, "role": "runner"}))
	check(got.has("pattern_camo"), "10 runner survivals unlock Camo")
	check(got.has("suit_khaki"), "10 rounds unlock Khaki")
	check(got.has("suit_mud"), "10 top-3 unlock Mud Brown")
	print("after 10 duck hunt: ", Profile.requirement_text("hat_goggles_neon"))
	for i in 3:
		got.append_array(Profile.apply_round("duck_hunt", {"place": 1, "count": 6, "died": false, "role": "sniper"}))
	check(got.has("hat_goggles_neon"), "3 sniper wins unlock Night Vision")
	check(got.has("hat_fedora") and got.has("hat_shades"), "first win + flawless win")
	check(Profile.stat("win_streak_best") == 3 and got.has("death_boom"), "3 win streak")
	Profile.apply_round("minefield3d", {"place": 6, "count": 6, "died": true})
	check(Profile.stat("win_streak") == 0 and Profile.stat("deaths") == 1 and Profile.stat("last_places") == 1, "loss resets streak, counts death + last place")
	for i in 5:
		Profile.apply_round("firearm_factory", {"place": 2, "count": 4, "died": false, "extra": {"kills": 2}})
	check(Profile.is_unlocked("suit_arterial"), "10 Firearm Factory kills unlock Arterial Red")
	got = Profile.apply_round("inside_job", {"place": 3, "count": 5, "died": false, "role": "zero"})
	check(got.has("title_zero"), "patient zero top 3")
	got = Profile.apply_match(true, 1)
	check(got.has("suit_hazmat") and got.has("title_labrat"), "match win unlocks Hazmat + Lab Rat")
	for slug in Globals.MODES.map(func(m): return m.slug):
		Profile.apply_round(slug, {"place": 1, "count": 3, "died": false})
	check(Profile.stat("modes_played") == 21 and Profile.is_unlocked("death_confetti"), "win every mode unlocks Confetti")

	check(Profile.equip("hat_goggles_neon"), "equip unlocked item")
	check(not Profile.equip("hat_tophat_gold"), "cannot equip locked item")
	var look := Profile.local_look()
	check(look.hat == "goggles" and look.hat_tint == "neon", "look resolves hat tint")
	var clean := Profile.sanitize_look({"sex": "robot", "hat": "../../x", "pattern": 99, "title": "x".repeat(80), "death_fx": "nuke", "suit": Color.RED})
	check(not clean.has("sex") and not clean.has("hat") and clean.pattern == 9 and clean.title.length() == 28 and not clean.has("death_fx"), "sanitize rejects junk")

	var snap_stats := Profile.stats.duplicate()
	var snap_unl := Profile.unlocked_ids.duplicate()
	var snap_lo := Profile.loadout.duplicate()
	Profile.reset()
	Profile.load_profile()
	check(Profile.stats == snap_stats, "stats round trip")
	check(Profile.unlocked_ids == snap_unl, "unlocks round trip")
	check(Profile.loadout == snap_lo, "loadout round trip")

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[profile]\nstats=garbage{{{\nloadout=\"nope\"\n")
	f.close()
	Profile.load_profile()
	check(Profile.loadout == Profile.DEFAULT_LOADOUT and Profile.equipped("hat") == "hat_hardhat", "corrupt file falls back to defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.load_profile()
	check(Profile.stats.is_empty(), "missing file = fresh profile")

	print("PROFILE TEST DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
