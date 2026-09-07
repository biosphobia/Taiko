class_name UiTheme
extends RefCounted
## Colors and small UI builders shared by every scene. Themes/skins come from Profile.equipped.

const THEMES := {
	"theme_festival": {"bg_top": Color(0.16, 0.05, 0.06), "bg_bottom": Color(0.42, 0.14, 0.06), "accent": Color(1.0, 0.55, 0.15), "panel": Color(0.08, 0.04, 0.05, 0.85), "text": Color(1, 0.96, 0.9), "lane": Color(0.13, 0.12, 0.14), "lane_edge": Color(0.95, 0.75, 0.35), "kiai": Color(1.0, 0.7, 0.2)},
	"theme_night": {"bg_top": Color(0.02, 0.03, 0.08), "bg_bottom": Color(0.06, 0.08, 0.2), "accent": Color(0.3, 0.9, 1.0), "panel": Color(0.02, 0.03, 0.08, 0.85), "text": Color(0.92, 0.96, 1), "lane": Color(0.06, 0.07, 0.12), "lane_edge": Color(0.4, 0.8, 1.0), "kiai": Color(0.4, 0.9, 1.0)},
	"theme_ocean": {"bg_top": Color(0.02, 0.15, 0.22), "bg_bottom": Color(0.03, 0.35, 0.45), "accent": Color(0.35, 1.0, 0.85), "panel": Color(0.01, 0.1, 0.15, 0.85), "text": Color(0.9, 1, 0.98), "lane": Color(0.04, 0.12, 0.16), "lane_edge": Color(0.5, 0.95, 0.9), "kiai": Color(0.5, 1.0, 0.9)},
	"theme_dojo": {"bg_top": Color(0.12, 0.12, 0.12), "bg_bottom": Color(0.22, 0.21, 0.2), "accent": Color(0.9, 0.85, 0.7), "panel": Color(0.05, 0.05, 0.05, 0.85), "text": Color(0.95, 0.95, 0.93), "lane": Color(0.09, 0.09, 0.09), "lane_edge": Color(0.8, 0.75, 0.6), "kiai": Color(0.95, 0.9, 0.7)},
}

const NOTE_SKINS := {
	"notes_classic": {"don": Color(0.95, 0.27, 0.22), "ka": Color(0.25, 0.7, 0.95), "roll": Color(1.0, 0.85, 0.2), "balloon": Color(1.0, 0.55, 0.15), "outline": Color(1, 1, 1), "outline_width": 4.0},
	"notes_pastel": {"don": Color(0.98, 0.6, 0.6), "ka": Color(0.62, 0.82, 0.98), "roll": Color(1.0, 0.92, 0.6), "balloon": Color(1.0, 0.75, 0.5), "outline": Color(1, 1, 1), "outline_width": 3.0},
	"notes_high_contrast": {"don": Color(1.0, 0.15, 0.0), "ka": Color(0.0, 0.8, 1.0), "roll": Color(1.0, 1.0, 0.0), "balloon": Color(1.0, 0.5, 0.0), "outline": Color(1, 1, 1), "outline_width": 6.0},
}

const DRUM_SKINS := {
	"drum_classic": {"body": Color(0.6, 0.35, 0.2), "face": Color(0.96, 0.92, 0.85), "rim": Color(0.25, 0.15, 0.1), "rope": Color(0.85, 0.2, 0.2)},
	"drum_sakura": {"body": Color(0.55, 0.3, 0.4), "face": Color(1.0, 0.9, 0.94), "rim": Color(0.75, 0.35, 0.5), "rope": Color(0.95, 0.5, 0.7)},
	"drum_neon": {"body": Color(0.08, 0.08, 0.12), "face": Color(0.15, 0.15, 0.2), "rim": Color(0.2, 1.0, 0.9), "rope": Color(1.0, 0.2, 0.8)},
	"drum_gold": {"body": Color(0.55, 0.42, 0.12), "face": Color(1.0, 0.95, 0.75), "rim": Color(0.85, 0.65, 0.2), "rope": Color(0.95, 0.85, 0.4)},
}


static func theme() -> Dictionary:
	return THEMES.get(Profile.equipped.get("theme", "theme_festival"), THEMES["theme_festival"])


static func note_skin() -> Dictionary:
	return NOTE_SKINS.get(Profile.equipped.get("notes", "notes_classic"), NOTE_SKINS["notes_classic"])


static func drum_skin() -> Dictionary:
	return DRUM_SKINS.get(Profile.equipped.get("drum", "drum_classic"), DRUM_SKINS["drum_classic"])


static func font() -> Font:
	return ThemeDB.fallback_font


static func make_background(parent: Control) -> ColorRect:
	var t := theme()
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = t.bg_top
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([t.bg_top, t.bg_bottom])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(grad)
	return bg


static func make_label(text: String, size: int = 24, color: Color = Color(-1, 0, 0), align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if color.r >= 0.0:
		l.add_theme_color_override("font_color", color)
	else:
		l.add_theme_color_override("font_color", theme().text)
	l.horizontal_alignment = align
	return l


static func make_title(text: String) -> Label:
	var l := make_label(text, 48, theme().accent)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	return l


static func make_button(text: String, size: int = 28) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(320, 56)
	b.focus_mode = Control.FOCUS_ALL
	var t := theme()
	var normal := StyleBoxFlat.new()
	normal.bg_color = t.panel
	normal.border_color = t.accent
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var hover := normal.duplicate()
	hover.bg_color = t.accent.darkened(0.55)
	var focus := normal.duplicate()
	focus.border_color = Color.WHITE
	focus.set_border_width_all(3)
	focus.bg_color = t.accent.darkened(0.5)
	var pressed := normal.duplicate()
	pressed.bg_color = t.accent.darkened(0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", t.text)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.focus_entered.connect(func(): Game.play_sfx("ui_move"))
	return b


static func make_panel(parent: Control, rect: Rect2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = theme().panel
	sb.border_color = theme().accent.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	return p


static func make_slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(320, 32)
	s.focus_mode = Control.FOCUS_ALL
	return s


static func make_option(items: Array, selected: int = 0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = clampi(selected, 0, maxi(0, items.size() - 1))
	o.custom_minimum_size = Vector2(320, 44)
	o.add_theme_font_size_override("font_size", 22)
	return o


static func fit_scene(root: Control) -> void:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
