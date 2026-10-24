extends Node
class_name Minigame
## Base for every minigame. The round director instances one, renames it
## "Minigame" (stable RPC path), adds it under GameArea, calls begin().
## Server resolves the round and emits finished(placement) (peer_ids best->worst).

signal finished(placement)

## Full-rect Control layer for HUD/overlay text. Use for UI-only minigames too.
func make_ui_layer() -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.theme = UiKit.hud_theme()
	layer.add_child(c)
	return c

func begin() -> void:
	pass
