extends Control

var _status: Label
var _first_button: Button
var _drum: DrumWidget


func _ready() -> void:
	UiTheme.fit_scene(self)
	Hardware.gameplay_mode = false
	Hardware.menu_navigation = true
	var t := UiTheme.theme()
	UiTheme.make_background(self)
	var title := UiTheme.make_title("TaikoMove")
	title.add_theme_font_size_override("font_size", 84)
	title.position = Vector2(120, 110)
	add_child(title)
	var sub := UiTheme.make_label("Taiko drumming with PS Move controllers", 26, Color(1, 1, 1, 0.8))
	sub.position = Vector2(126, 210)
	add_child(sub)
	var player := UiTheme.make_label("%s   |   %d coins" % [Profile.title_name(), Profile.coins], 22, t.accent)
	player.position = Vector2(126, 250)
	add_child(player)

	var vb := VBoxContainer.new()
	vb.position = Vector2(120, 330)
	vb.add_theme_constant_override("separation", 14)
	add_child(vb)
	var entries := [
		["Play", func(): Game.goto("songs")],
		["Setup & Calibration", func(): Game.goto("setup")],
		["Unlockables", func(): Game.goto("shop")],
		["Settings", func(): Game.goto("settings")],
		["Quit", func(): get_tree().quit()],
	]
	for e in entries:
		var b := UiTheme.make_button(e[0])
		b.custom_minimum_size = Vector2(420, 62)
		b.pressed.connect(func():
			Game.play_sfx("ui_select")
			e[1].call())
		vb.add_child(b)
		if _first_button == null:
			_first_button = b
	_first_button.grab_focus()

	_status = UiTheme.make_label("", 20, Color(1, 1, 1, 0.75))
	_status.position = Vector2(120, 820)
	_status.size = Vector2(1300, 30)
	add_child(_status)
	var hint := UiTheme.make_label("Keyboard: D F J K = ka don don ka   |   Move button = select, Select/Circle = back", 18, Color(1, 1, 1, 0.5))
	hint.position = Vector2(120, 850)
	add_child(hint)
	var version := UiTheme.make_label("v" + ProjectSettings.get_setting("application/config/version", "1.0"), 16, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_RIGHT)
	version.position = Vector2(1300, 860)
	version.size = Vector2(280, 24)
	add_child(version)

	# decorative drum
	_drum = DrumWidget.new()
	_drum.position = Vector2(1000, 260)
	_drum.size = Vector2(420, 420)
	add_child(_drum)
	Hardware.drum_hit.connect(_on_drum_hit)


func _exit_tree() -> void:
	if Hardware.drum_hit.is_connected(_on_drum_hit):
		Hardware.drum_hit.disconnect(_on_drum_hit)


func _on_drum_hit(hand: int, kind: int, _t: int, _s: float, _src: String) -> void:
	_drum.flash(hand, kind)
	Game.play_sfx("don" if kind == 0 else "ka")


func _process(_d: float) -> void:
	var s := Hardware.status_text()
	if Hardware.hw != null and not bool(Settings.get_value("setup_done")):
		s += "   -  run Setup & Calibration first"
	_status.text = s
