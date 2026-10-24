extends RefCounted
class_name UiKit
## Lab terminal look for every screen: phosphor green on black, VT323 headings,
## Share Tech Mono body, hard 1px borders, no rounded corners.

const GREEN := Color("8dfca4")
const GREEN_DIM := Color("3f7a4c")
const AMBER := Color("ffb23f")
const RED := Color("ff5a4a")
const INK := Color("050806")
const PANEL := Color(0.02, 0.05, 0.03, 0.86)

static var _theme: Theme
static var heading_font: Font = preload("res://assets/ui/VT323-Regular.ttf")
static var body_font: Font = preload("res://assets/ui/ShareTechMono-Regular.ttf")

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font
	t.default_font_size = 18
	t.set_color("font_color", "Label", GREEN)
	t.set_color("font_color", "Button", GREEN)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", GREEN)
	t.set_color("font_disabled_color", "Button", GREEN_DIM)
	t.set_stylebox("normal", "Button", box(Color(0, 0, 0, 0.55), GREEN_DIM))
	t.set_stylebox("hover", "Button", box(GREEN, GREEN))
	t.set_stylebox("pressed", "Button", box(AMBER, AMBER))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GREEN))
	t.set_stylebox("disabled", "Button", box(Color(0, 0, 0, 0.4), Color(0.15, 0.25, 0.17)))
	t.set_color("font_color", "LineEdit", GREEN)
	t.set_color("caret_color", "LineEdit", AMBER)
	t.set_color("font_placeholder_color", "LineEdit", GREEN_DIM)
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.6), GREEN_DIM))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.6), GREEN))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, GREEN_DIM, 18))
	_theme = t
	return t

static func box(bg: Color, border: Color, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_content_margin_all(pad)
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s

static func heading(text: String, size: int = 64, color: Color = GREEN) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", heading_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(color, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", 10)
	return l

static func text(t: String, size: int = 18, color: Color = GREEN) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(t: String, cb: Callable, size: int = 22) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_override("font", heading_font)
	b.add_theme_font_size_override("font_size", size)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, size + 14)
	b.pressed.connect(func(): Fx.sfx("click", null, -6.0); cb.call())
	b.mouse_entered.connect(func(): Fx.sfx("click", null, -18.0, 1.6))
	return b

static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	return p

static func scanlines() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ float l = step(0.5, fract(FRAGCOORD.y * 0.5)); COLOR = vec4(0.0, 0.0, 0.0, 0.10 * l); }"
	m.shader = sh
	r.material = m
	return r
