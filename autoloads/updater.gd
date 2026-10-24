extends Node
## Over-the-air updates. On the main menu it reads the public manifest; when a newer
## build exists it offers UPDATE, downloads the new executable next to the running
## one from GitHub Releases, checks its SHA-256, swaps it in and restarts. Only active in exported builds
## (or with --updater-exe=<path> for testing). Publish with tools/push_update.sh.

const BUILD: int = 3
const MANIFEST_URL := "https://github.com/Ghostofpotato/lab-party/releases/latest/download/latest.json"

var exe_path: String = ""
var _manifest: Dictionary = {}
var _entry: Dictionary = {}
var _http: HTTPRequest
var _panel: PanelContainer
var _title: Label
var _info: Label
var _button: Button
var _state: String = "idle"
var _target: String = ""

func _ready() -> void:
	exe_path = OS.get_executable_path()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--updater-exe="):
			exe_path = a.trim_prefix("--updater-exe=")
	var forced := exe_path != OS.get_executable_path()
	if not forced and not OS.has_feature("template"):
		return
	_cleanup()
	_build_ui()
	GameManager.screen_changed.connect(func(_s): _refresh_visible())
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_manifest)
	_http.request(MANIFEST_URL)

func _platform() -> String:
	return "windows" if OS.has_feature("windows") or exe_path.ends_with(".exe") else "linux"

func _old_path() -> String:
	return exe_path.get_basename() + ".old" + ("." + exe_path.get_extension() if exe_path.get_extension() != "" else "")

func _cleanup() -> void:
	for p in [_old_path(), exe_path + ".new"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_panel = UiKit.panel()
	_panel.theme = UiKit.theme()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-380, 24)
	_panel.custom_minimum_size = Vector2(350, 0)
	_panel.visible = false
	layer.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	_title = UiKit.heading("UPDATE AVAILABLE", 30, UiKit.AMBER)
	v.add_child(_title)
	_info = UiKit.text("", 14)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(320, 0)
	v.add_child(_info)
	_button = UiKit.button("> UPDATE NOW", _on_button, 24)
	v.add_child(_button)

func _refresh_visible() -> void:
	if _panel:
		_panel.visible = _state != "idle" and GameManager.screen == GameManager.Screen.MENU

func _on_manifest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_http.request_completed.disconnect(_on_manifest)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[LP] UPDATE check failed ", result, " ", code)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return
	_manifest = data
	var build: int = int(_manifest.get("build", 0))
	print("[LP] UPDATE check build ", BUILD, " -> latest ", build)
	if build <= BUILD or not _manifest.get(_platform()) is Dictionary:
		return
	_entry = _manifest[_platform()]
	_state = "offer"
	_info.text = "v%s is out (you have build %d).\n%s\n%d MB download." % [
		_manifest.get("version", "?"), BUILD, _manifest.get("notes", ""), int(_entry.get("size", 0)) / 1048576]
	_refresh_visible()

func _on_button() -> void:
	match _state:
		"offer", "failed":
			_download()
		"ready":
			OS.create_process(exe_path, OS.get_cmdline_args())
			get_tree().quit()

func _download() -> void:
	_state = "downloading"
	_target = exe_path + ".new"
	_button.disabled = true
	_title.text = "DOWNLOADING"
	_http.timeout = 0.0
	_http.download_file = _target
	_http.download_chunk_size = 262144
	_http.body_size_limit = -1
	_http.request_completed.connect(_on_downloaded, CONNECT_ONE_SHOT)
	if _http.request(str(_entry.get("url", ""))) != OK:
		_fail("could not start the download")

func _process(_delta: float) -> void:
	if _state == "downloading":
		var total: int = maxi(int(_entry.get("size", 1)), 1)
		var got: int = _http.get_downloaded_bytes()
		_info.text = "%d / %d MB  ·  %d%%\nKeep the game open." % [got / 1048576, total / 1048576, got * 100 / total]

func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_http.download_file = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("download error %d / %d" % [result, code])
		return
	if FileAccess.get_sha256(_target) != str(_entry.get("sha256", "")):
		_fail("the file was damaged on the way")
		return
	var err := OK
	if _platform() == "windows":
		err = DirAccess.rename_absolute(exe_path, _old_path())
	else:
		FileAccess.set_unix_permissions(_target, 493)
	if err == OK:
		err = DirAccess.rename_absolute(_target, exe_path)
	if err != OK:
		_fail("could not replace the game file (error %d)" % err)
		return
	print("[LP] UPDATE installed build ", _manifest.get("build"))
	_state = "ready"
	_title.text = "UPDATE INSTALLED"
	_info.text = "v%s is ready. Restart to use it." % _manifest.get("version", "?")
	_button.text = "> RESTART NOW"
	_button.disabled = false

func _fail(why: String) -> void:
	print("[LP] UPDATE failed: ", why)
	if FileAccess.file_exists(_target):
		DirAccess.remove_absolute(_target)
	_state = "failed"
	_title.text = "UPDATE FAILED"
	_info.text = why + ".\nTry again, or download the new version from your link."
	_button.text = "> TRY AGAIN"
	_button.disabled = false
