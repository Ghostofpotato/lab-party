extends Node
## Dev harness: opens the wardrobe on a temp profile with a mix of unlocks, cycles
## every tab, equips items, scrolls, plays a death FX, shows unlock toasts and the
## menu, saving a screenshot at every step.
## godot --path . --windowed res://tools/wardrobe_test.tscn -- <shot_prefix>

var prefix: String = "user://wardrobe"
var n: int = 0

func shot(tag: String) -> void:
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var p := "%s_%02d_%s.png" % [prefix, n, tag]
	get_viewport().get_texture().get_image().save_png(p)
	print("SHOT ", p)
	n += 1

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		prefix = a[0]
	var path := "user://wardrobe_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.use_save_path(path)
	for i in 12:
		Profile.apply_round("duck_hunt", {"place": 1 if i < 4 else 3, "count": 6, "died": false, "role": "sniper" if i < 4 else "runner"})
	Profile.apply_match(true, 1)
	for id in ["pattern_gold", "pattern_chrome", "pattern_blood", "hat_tophat_gold", "death_confetti", "death_gold", "hair_pink", "title_eotm", "pattern_hazard", "pattern_camo", "pattern_inmate", "pattern_rust", "pattern_bio", "pattern_filth", "hat_goggles_neon", "hat_hardhat_chrome"]:
		Profile.unlocked_ids.append(id)
	NetworkManager.local_name = "Issam"
	var w := Wardrobe.new()
	get_tree().root.add_child.call_deferred(w)
	await get_tree().create_timer(2.5).timeout
	await shot("body")
	for t in ["suit", "pattern", "hair", "hat", "title", "death_fx", "challenges"]:
		w.select_tab(t)
		await shot(t)
	w._scroll.scroll_vertical = 2000
	await shot("challenges_scrolled")
	w.select_tab("title")
	w._scroll.scroll_vertical = 2000
	await shot("title_scrolled")
	var steps := [["suit", "suit_hazmat"], ["pattern", "pattern_camo"], ["pattern", "pattern_hazard"], ["pattern", "pattern_blood"], ["pattern", "pattern_chrome"], ["pattern", "pattern_gold"], ["pattern", "pattern_inmate"], ["pattern", "pattern_bio"], ["pattern", "pattern_rust"], ["hair", "hair_pink"], ["hat", "hat_tophat_gold"], ["hat", "hat_goggles_neon"], ["body", "body_female"], ["title", "title_eotm"]]
	for s in steps:
		w.select_tab(s[0])
		w.equip(s[1])
		await get_tree().create_timer(1.6).timeout
		await shot("equip_" + s[1])
	w.select_tab("pattern")
	w.equip("pattern_hazard")
	w.select_tab("death_fx")
	w._on_card("hat_cone_blood")
	w.equip("death_confetti")
	await get_tree().create_timer(0.85).timeout
	await shot("death_confetti")
	await get_tree().create_timer(3.2).timeout
	w.equip("death_gold")
	await get_tree().create_timer(0.8).timeout
	await shot("death_gold")
	await get_tree().create_timer(3.2).timeout
	var rd := RoundDirector.new()
	get_tree().root.add_child(rd)
	rd.show_unlocks(["hat_tophat_gold", "pattern_blood", "hair_grey", "title_labrat"])
	await get_tree().create_timer(1.6).timeout
	await shot("toasts")
	print("ON DISK ", FileAccess.get_file_as_string(path).length() > 0, " loadout ", Profile.loadout)
	w.queue_free()
	rd.queue_free()
	var main: Node = load("res://Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().create_timer(2.5).timeout
	await shot("menu")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("WARDROBE TEST DONE")
	get_tree().quit()
