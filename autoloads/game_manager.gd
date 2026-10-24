extends Node
## Owns high-level screen/session state. Autoload singleton.

signal screen_changed(screen)

enum Screen { MENU, LOBBY, SESSION }

var screen: Screen = Screen.MENU

func go(new_screen: Screen) -> void:
	screen = new_screen
	screen_changed.emit(new_screen)
