extends Node
## Dev harness: like client_test, but equips a non-default loadout first, joins
## 127.0.0.1, changes the loadout again in the lobby and prints the roster entry
## the server echoes back for this peer.
## godot --headless --path . res://tools/loadout_client_test.tscn -- <seconds>

func _ready() -> void:
	var secs: float = float(OS.get_cmdline_user_args()[0])
	for id in ["suit_void", "pattern_gold", "hat_tophat_gold", "title_eotm", "death_confetti", "hair_pink"]:
		Profile.unlocked_ids.append(id)
	for id in ["body_female", "suit_void", "pattern_gold", "hat_tophat_gold", "title_eotm", "death_confetti", "hair_pink"]:
		Profile.equip(id)
	var main: Node = load("res://Main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.5).timeout
	NetworkManager.local_name = "LoadoutBot"
	print("CLIENT join ", NetworkManager.join("127.0.0.1"))
	await get_tree().create_timer(0.8).timeout
	_dump("after join")
	Profile.equip("hat_beanie")
	await get_tree().create_timer(0.8).timeout
	_dump("after lobby change")
	var t := 6.0
	while t < secs:
		await get_tree().create_timer(10.0).timeout
		t += 10.0
	_dump("end")
	print("CLIENT DONE")
	get_tree().quit()

func _dump(tag: String) -> void:
	var me := multiplayer.get_unique_id()
	var p: Dictionary = NetworkManager.players.get(me, {})
	print("LOADOUT ", tag, " id=", me, " sex=", p.get("sex"), " suit=", p.get("suit"), " color=", p.get("color"), " pattern=", p.get("pattern"), " hat=", p.get("hat"), "/", p.get("hat_tint"), " title=", p.get("title"), " fx=", p.get("death_fx"), " roster=", NetworkManager.players.size())
