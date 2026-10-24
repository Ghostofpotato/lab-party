extends Node
## Dev harness: drives the Updater against a fake executable and prints each state.
## godot --headless --path . res://tools/updater_test.tscn -- --updater-exe=<fake path>

func _ready() -> void:
	var t := 0.0
	var last := ""
	while t < 90.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		var s: String = Updater._state
		if s != last:
			print("UPDTEST state ", s, " at ", t)
			last = s
		if s == "offer":
			Updater._on_button()
		elif s == "ready" or s == "failed":
			break
	print("UPDTEST DONE ", Updater._state, " ", Updater._info.text.replace("\n", " | ") if Updater._info else "")
	get_tree().quit()
