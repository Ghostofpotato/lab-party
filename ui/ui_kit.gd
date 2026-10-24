extends RefCounted
class_name UiKit
## Facility UI kit: warm near-black glass panels over the live 3D lab, Barlow
## Condensed display type, Barlow body text, one hazard-amber accent, soft
## radii, eased hover and entrance motion. Every screen builds from here.

const INK := Color("0d0c0b")
const SURFACE := Color(0.075, 0.068, 0.06, 0.74)
const SURFACE_HI := Color(1.0, 0.95, 0.88, 0.055)
const SURFACE_HOVER := Color(1.0, 0.95, 0.88, 0.1)
const LINE := Color(1.0, 0.94, 0.86, 0.11)
const LINE_STRONG := Color(1.0, 0.94, 0.86, 0.22)
const TEXT := Color("efe9df")
const MUTED := Color("a39b90")
const FAINT := Color("6d665d")
const ACCENT := Color("ffb02e")
const ACCENT_HI := Color("ffc457")
const ACCENT_INK := Color("1c1305")
const DANGER := Color("ff5d4d")
const OK := Color("8fd694")

const GREEN := TEXT
const GREEN_DIM := MUTED
const AMBER := ACCENT
const RED := DANGER
const PANEL := SURFACE

const R_PANEL: int = 14
const R_CTRL: int = 9
const EASE := Tween.EASE_OUT
const TRANS := Tween.TRANS_CUBIC

static var _theme: Theme
static var _hud_theme: Theme
static var _glass_mat: ShaderMaterial
static var display_font: Font = preload("res://assets/ui/BarlowCondensed-ExtraBold.ttf")
static var label_font: Font = _tracked(preload("res://assets/ui/BarlowCondensed-SemiBold.ttf"), 1)
static var body_font: Font = preload("res://assets/ui/Barlow-Regular.ttf")
static var strong_font: Font = preload("res://assets/ui/Barlow-SemiBold.ttf")
static var heading_font: Font = display_font

static func _tracked(f: Font, px: int) -> Font:
	var v := FontVariation.new()
	v.base_font = f
	v.set_spacing(TextServer.SPACING_GLYPH, px)
	return v

## Shared Theme for all menu screens.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)

	t.set_font("font", "Button", label_font)
	t.set_font_size("font_size", "Button", 18)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", FAINT)
	t.set_stylebox("normal", "Button", box(SURFACE_HI, LINE, 14))
	t.set_stylebox("hover", "Button", box(SURFACE_HOVER, LINE_STRONG, 14))
	t.set_stylebox("pressed", "Button", box(Color(ACCENT, 0.18), Color(ACCENT, 0.6), 14))
	t.set_stylebox("hover_pressed", "Button", box(Color(ACCENT, 0.22), Color(ACCENT, 0.7), 14))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.05), 14))
	t.set_stylebox("focus", "Button", focus_ring())

	t.set_font("font", "LineEdit", strong_font)
	t.set_font_size("font_size", "LineEdit", 19)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_color("font_placeholder_color", "LineEdit", FAINT)
	var le := box(Color(0, 0, 0, 0.38), LINE_STRONG, 14)
	le.content_margin_top = 8
	le.content_margin_bottom = 8
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate() as StyleBoxFlat
	lef.border_color = ACCENT
	lef.set_border_width_all(2)
	t.set_stylebox("focus", "LineEdit", lef)

	t.set_stylebox("panel", "PanelContainer", glass_box())
	t.set_stylebox("panel", "TooltipPanel", box(Color("1a1815"), LINE_STRONG, 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", body_font)
	t.set_font_size("font_size", "TooltipLabel", 15)

	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 0.95, 0.88, 0.22)
	grab.set_corner_radius_all(3)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = Color(ACCENT, 0.8)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.03)
	track.set_corner_radius_all(3)
	track.content_margin_left = 3
	track.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)

	t.set_stylebox("background", "ProgressBar", pill_box(Color(1, 1, 1, 0.07)))
	t.set_stylebox("fill", "ProgressBar", pill_box(ACCENT))
	_theme = t
	return t

## Minimal theme for in-minigame HUD layers: modern default font, sizes unchanged.
static func hud_theme() -> Theme:
	if _hud_theme:
		return _hud_theme
	var t := Theme.new()
	t.default_font = strong_font
	_hud_theme = t
	return t

static func box(bg: Color, border: Color, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(R_CTRL)
	s.corner_detail = 6
	s.anti_aliasing = true
	s.set_content_margin_all(pad)
	s.content_margin_top = roundi(pad * 0.55)
	s.content_margin_bottom = roundi(pad * 0.55)
	return s

static func pill_box(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(99)
	s.corner_detail = 6
	return s

static func focus_ring() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = ACCENT
	s.set_border_width_all(2)
	s.set_corner_radius_all(R_CTRL + 2)
	s.expand_margin_left = 3
	s.expand_margin_right = 3
	s.expand_margin_top = 3
	s.expand_margin_bottom = 3
	return s

static func glass_box(pad: int = 20) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SURFACE
	s.border_color = LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(R_PANEL)
	s.corner_detail = 8
	s.set_content_margin_all(pad)
	return s

## Material that blurs and darkens whatever is behind the control it is set on.
static func glass_material() -> ShaderMaterial:
	if _glass_mat:
		return _glass_mat
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 6.0;
	vec3 b = textureLod(screen_tex, SCREEN_UV, 3.2).rgb * 0.4;
	b += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), 3.2).rgb * 0.15;
	b += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0), 3.2).rgb * 0.15;
	b += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), 3.2).rgb * 0.15;
	b += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y), 3.2).rgb * 0.15;
	float a = COLOR.a;
	COLOR = vec4(mix(b * 0.85, COLOR.rgb, a), clamp(a * 5.0, 0.0, 1.0));
}"""
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = sh
	return _glass_mat

static func heading(text: String, size: int = 64, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", display_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", -int(size * 0.18))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(1, size / 28))
	l.add_theme_constant_override("shadow_outline_size", 0)
	return l

static func text(t: String, size: int = 17, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func strong(t: String, size: int = 17, color: Color = TEXT) -> Label:
	var l := text(t, size, color)
	l.add_theme_font_override("font", strong_font)
	return l

## Small uppercase tracked label for section names and metadata.
static func label(t: String, size: int = 14, color: Color = MUTED) -> Label:
	var l := text(t.to_upper(), size, color)
	l.add_theme_font_override("font", label_font)
	return l

static func pill(t: String, color: Color = ACCENT, filled: bool = false, size: int = 13) -> PanelContainer:
	var p := PanelContainer.new()
	var s := pill_box(color if filled else Color(color, 0.14))
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	if not filled:
		s.border_color = Color(color, 0.4)
		s.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.add_child(label(t, size, ACCENT_INK if filled else color.lightened(0.15)))
	return p

static func chip(color: Color, w: float = 12.0, h: float = 12.0) -> Panel:
	var p := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(int(minf(w, h) * 0.35))
	s.border_color = Color(1, 1, 1, 0.18)
	s.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(w, h)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func bar(value: float, max_value: float, color: Color = ACCENT, w: float = 150.0, h: float = 6.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.max_value = maxf(max_value, 0.001)
	b.value = value
	b.custom_minimum_size = Vector2(w, h)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("background", pill_box(Color(1, 1, 1, 0.08)))
	b.add_theme_stylebox_override("fill", pill_box(color))
	return b

static func spacer(h: float = 12.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func flex() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func _sounds(b: BaseButton, cb: Callable) -> void:
	b.pressed.connect(func(): Fx.sfx("click", null, -6.0); cb.call())
	b.mouse_entered.connect(func(): Fx.sfx("click", null, -20.0, 1.6))

static func _clean(t: String) -> String:
	return t.trim_prefix("> ").trim_prefix(">").strip_edges()

## Secondary button. Size is the font size; height follows it.
static func button(t: String, cb: Callable, size: int = 18) -> Button:
	var b := Button.new()
	b.text = _clean(t).to_upper()
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, maxi(40, size + 22))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_sounds(b, cb)
	press_fx(b)
	return b

## The single loud call to action on a screen.
static func primary(t: String, cb: Callable, size: int = 22) -> Button:
	var b := button(t, cb, size)
	var n := box(ACCENT, ACCENT, 18)
	var h := box(ACCENT_HI, ACCENT_HI, 18)
	var p := box(ACCENT.darkened(0.12), ACCENT.darkened(0.12), 18)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	b.add_theme_stylebox_override("disabled", box(Color(ACCENT, 0.25), Color(ACCENT, 0.25), 18))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, ACCENT_INK)
	b.add_theme_color_override("font_disabled_color", Color(ACCENT_INK, 0.6))
	b.custom_minimum_size.y = maxi(48, size + 26)
	return b

## Quiet list-style menu item: transparent until hovered or focused, then an
## amber edge slides in and the label eases right.
static func menu_item(t: String, cb: Callable, size: int = 20, danger: bool = false) -> Button:
	var b := Button.new()
	b.text = _clean(t).to_upper()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, maxi(40, size + 20))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var edge := DANGER if danger else ACCENT
	var s := box(Color(1, 0.95, 0.88, 0.0), Color(edge, 0.0), 14)
	s.set_border_width_all(0)
	s.border_width_left = 3
	s.corner_radius_top_left = 3
	s.corner_radius_bottom_left = 3
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fg := DANGER.lightened(0.25) if danger else TEXT
	b.add_theme_color_override("font_color", Color(fg, 0.86))
	for k in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, DANGER.lightened(0.35) if danger else Color.WHITE)
	var state := {"in": false}
	var go := func(on: bool) -> void:
		if state["in"] == on:
			return
		state["in"] = on
		var tw := b.create_tween().set_parallel().set_ease(EASE).set_trans(TRANS)
		tw.tween_property(s, "bg_color", Color(1, 0.95, 0.88, 0.08 if on else 0.0), 0.16)
		tw.tween_property(s, "border_color", Color(edge, 1.0 if on else 0.0), 0.16)
		tw.tween_property(s, "content_margin_left", 22.0 if on else 14.0, 0.18)
	b.mouse_entered.connect(func(): go.call(true))
	b.mouse_exited.connect(func(): go.call(b.has_focus()))
	b.focus_entered.connect(func(): go.call(true))
	b.focus_exited.connect(func(): go.call(b.is_hovered()))
	_sounds(b, cb)
	press_fx(b)
	return b

## Square icon button drawing a glyph (play, plus, minus, check, close).
static func icon_button(kind: String, cb: Callable, side: float = 36.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(side, side)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var g := Glyph.new()
	g.kind = kind
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(g)
	b.mouse_entered.connect(func(): g.color = ACCENT; g.queue_redraw())
	b.mouse_exited.connect(func(): g.color = TEXT; g.queue_redraw())
	_sounds(b, cb)
	press_fx(b)
	return b

## Subtle scale push on press, eased back on release.
static func press_fx(c: Control) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size * 0.5)
	c.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			var tw := c.create_tween().set_ease(EASE).set_trans(Tween.TRANS_BACK)
			tw.tween_property(c, "scale", Vector2(0.97, 0.97) if e.pressed else Vector2.ONE, 0.09 if e.pressed else 0.18))

## Hover lift for cards: gentle scale and draw on top of neighbours.
static func hover_lift(c: Control, amount: float = 1.025) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size * 0.5)
	var lift := func(on: bool) -> void:
		c.z_index = 1 if on else 0
		var tw := c.create_tween().set_ease(EASE).set_trans(TRANS)
		tw.tween_property(c, "scale", Vector2.ONE * (amount if on else 1.0), 0.16)
	c.mouse_entered.connect(func(): lift.call(true))
	c.mouse_exited.connect(func(): lift.call(false))
	c.focus_entered.connect(func(): lift.call(true))
	c.focus_exited.connect(func(): lift.call(false))

## Glass panel: blurs and darkens what is behind it.
static func panel(pad: int = 20) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", glass_box(pad))
	p.material = glass_material()
	return p

static func hairline() -> ColorRect:
	var r := ColorRect.new()
	r.color = LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Fades children in one after another; each also rises a few pixels if it sits
## outside a container.
static func stagger(parent: Control, delay: float = 0.0, step: float = 0.045) -> void:
	var i := 0
	for c in parent.get_children():
		if c is Control:
			fade_in(c, delay + step * i)
			i += 1

static func fade_in(c: CanvasItem, delay: float = 0.0, dur: float = 0.32) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween().set_ease(EASE).set_trans(TRANS)
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, dur)

## Slides a control in from an offset by moving its anchor offsets, so anchored
## layouts keep their size (not for container children).
static func slide_in(c: Control, from: Vector2 = Vector2(-28, 0), delay: float = 0.0, dur: float = 0.45) -> void:
	var ol := c.offset_left
	var orr := c.offset_right
	var ot := c.offset_top
	var ob := c.offset_bottom
	var move := func(k: float) -> void:
		c.offset_left = ol + from.x * k
		c.offset_right = orr + from.x * k
		c.offset_top = ot + from.y * k
		c.offset_bottom = ob + from.y * k
	move.call(1.0)
	var tw := c.create_tween().set_ease(EASE).set_trans(Tween.TRANS_QUART)
	tw.tween_interval(delay)
	tw.tween_method(move, 1.0, 0.0, dur)

## Warm grain plus vignette over the whole screen (replaces the old CRT lines).
static func scanlines() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float n = h(floor(FRAGCOORD.xy * 0.5) + floor(TIME * 18.0)) - 0.5;
	vec2 d = UV - 0.5;
	float v = smoothstep(0.35, 0.95, length(d * vec2(1.0, 1.25)));
	COLOR = vec4(vec3(0.02, 0.015, 0.01) + n * 0.3, v * 0.55 + abs(n) * 0.022);
}"""
	m.shader = sh
	r.material = m
	return r

## Horizontal darkening from one edge so text reads over the 3D backdrop.
static func scrim(from_left: bool = true, reach: float = 0.62, strength: float = 0.88) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(INK, strength))
	g.set_color(1, Color(INK, 0.0))
	g.add_point(0.45, Color(INK, strength * 0.7))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0 if from_left else 1.0, 0.5)
	gt.fill_to = Vector2(reach if from_left else 1.0 - reach, 0.5)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## Tiny vector glyphs so icons never depend on font coverage.
class Glyph extends Control:
	var kind: String = "play"
	var color: Color = UiKit.TEXT
	var fill: Color = Color(0, 0, 0, 0)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.22
		match kind:
			"play":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.75, -r), c + Vector2(r * 1.05, 0), c + Vector2(-r * 0.75, r)]), color)
			"plus":
				draw_line(c - Vector2(r, 0), c + Vector2(r, 0), color, 2.0, true)
				draw_line(c - Vector2(0, r), c + Vector2(0, r), color, 2.0, true)
			"minus":
				draw_line(c - Vector2(r, 0), c + Vector2(r, 0), color, 2.0, true)
			"check":
				draw_polyline(PackedVector2Array([c + Vector2(-r, 0), c + Vector2(-r * 0.25, r * 0.75), c + Vector2(r, -r * 0.7)]), color, 2.0, true)
			"box":
				var s := StyleBoxFlat.new()
				s.bg_color = fill
				s.border_color = color
				s.set_border_width_all(2 if fill.a == 0.0 else 0)
				s.set_corner_radius_all(4)
				s.anti_aliasing = true
				var side := minf(size.x, size.y)
				draw_style_box(s, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)))
				if fill.a > 0.0:
					var q := side * 0.26
					draw_polyline(PackedVector2Array([c + Vector2(-q, 0), c + Vector2(-q * 0.25, q * 0.75), c + Vector2(q, -q * 0.7)]), UiKit.ACCENT_INK, 2.0, true)
