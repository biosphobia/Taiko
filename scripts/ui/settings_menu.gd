extends Control

var _rows: VBoxContainer
var _first: Control


func _ready() -> void:
	UiTheme.fit_scene(self)
	Hardware.gameplay_mode = false
	Hardware.menu_navigation = true
	var t := UiTheme.theme()
	UiTheme.make_background(self)
	var title := UiTheme.make_title("Settings")
	title.position = Vector2(60, 30)
	add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60, 110)
	scroll.size = Vector2(1480, 660)
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	_rows.custom_minimum_size = Vector2(1440, 0)
	scroll.add_child(_rows)

	_section("Timing")
	_slider("Input offset (ms)  [negative if you hit late]", "input_offset_ms", -150, 150, 1)
	_slider("Scroll speed", "scroll_speed", 0.5, 3.0, 0.1)
	_option("Judgement windows", "judge_preset", ["od", "arcade", "strict", "lenient"], ["osu! (by OD)", "Arcade (25/75/108 ms)", "Strict (20/50/70 ms)", "Lenient (50/120/135 ms)"])
	_section("Hit detection (PS Move)")
	_option("Hit mode", "hit_mode", [0, 1, 2], ["Air drumming", "Hitting a surface", "Hybrid"])
	_option("Trigger point", "trigger_point", [0, 1], ["Peak of the swing (most consistent)", "Early (lowest latency)"])
	_slider("Swing threshold (rad/s)", "threshold", 1.0, 15.0, 0.1)
	_slider("Minimum peak (rad/s)", "min_peak", 1.0, 20.0, 0.1)
	_slider("Surface impact threshold (g)", "jerk_threshold", 0.5, 8.0, 0.1)
	_slider("Minimum time between hits (ms)", "refractory_ms", 20, 150, 1)
	_section("Don / Ka detection")
	_option("Tracking", "tracking_mode", ["camera", "imu"], ["Camera (PS3 Eye) drum zones", "IMU only (no camera)"])
	_option("Ka without camera", "imu_ka_mode", ["twist", "trigger"], ["Twist the controller 90 degrees", "Hold the trigger"])
	_option("Hit outside the drum", "outside_drum", ["ka", "ignore"], ["Counts as Ka", "Ignored"])
	_option("Controller not visible", "untracked_fallback", ["imu", "don"], ["Use IMU rule", "Always Don"])
	_section("Controllers")
	_slider("LED brightness", "led_brightness", 0.1, 1.0, 0.05)
	_toggle("Flash LED on hit", "led_flash")
	_toggle("Rumble on hit", "rumble")
	_toggle("Keyboard input (D F J K)", "keyboard_enabled")
	_section("Camera")
	_option("Camera frame rate", "camera_fps", [60, 75, 100, 125, 150, 187], ["60", "75", "100", "125 (default)", "150", "187"])
	_toggle("Mirror camera horizontally", "camera_flip_h")
	_section("Audio")
	_slider("Master volume", "volume_master", 0.0, 1.0, 0.05)
	_slider("Music volume", "volume_music", 0.0, 1.0, 0.05)
	_slider("Effects volume", "volume_sfx", 0.0, 1.0, 0.05)
	_section("Display")
	_toggle("Fullscreen", "fullscreen")
	_toggle("V-Sync (off = lowest latency)", "vsync")
	_option("FPS limit", "max_fps", [0, 60, 120, 144, 240], ["Unlimited", "60", "120", "144", "240"])
	_toggle("Show hit error bar", "show_error_bar")
	_toggle("Show camera drum monitor", "show_drum_monitor")
	_toggle("Show FPS", "show_fps")

	var hb := HBoxContainer.new()
	hb.position = Vector2(60, 800)
	hb.add_theme_constant_override("separation", 16)
	add_child(hb)
	var b_back := UiTheme.make_button("Back")
	b_back.pressed.connect(func(): Game.goto("menu"))
	hb.add_child(b_back)
	var b_setup := UiTheme.make_button("Calibration wizard")
	b_setup.pressed.connect(func(): Game.goto("setup"))
	hb.add_child(b_setup)
	var b_reset := UiTheme.make_button("Reset to defaults")
	b_reset.pressed.connect(func():
		Settings.reset_to_defaults()
		Game.goto("settings"))
	hb.add_child(b_reset)
	var note := UiTheme.make_label("Settings are saved immediately. Sensitivity values are best set with the calibration wizard.", 18, Color(1, 1, 1, 0.6))
	note.position = Vector2(60, 860)
	add_child(note)
	if _first:
		_first.grab_focus()


func _section(text: String) -> void:
	var l := UiTheme.make_label(text, 28, UiTheme.theme().accent)
	_rows.add_child(l)


func _row(label: String, control: Control) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	var l := UiTheme.make_label(label, 22)
	l.custom_minimum_size = Vector2(700, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l)
	hb.add_child(control)
	_rows.add_child(hb)
	if _first == null:
		_first = control if control.focus_mode != Control.FOCUS_NONE else control.get_child(0)


func _slider(label: String, key: String, min_v: float, max_v: float, step: float) -> void:
	var s := UiTheme.make_slider(min_v, max_v, step, float(Settings.get_value(key)))
	var v := UiTheme.make_label(_fmt(s.value, step), 22)
	v.custom_minimum_size = Vector2(120, 0)
	s.value_changed.connect(func(val):
		v.text = _fmt(val, step)
		Settings.set_value(key, val))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.add_child(s)
	hb.add_child(v)
	_row(label, hb)


static func _fmt(v: float, step: float) -> String:
	return str(int(round(v))) if step >= 1.0 else "%.2f" % v


func _option(label: String, key: String, values: Array, names: Array) -> void:
	var o := UiTheme.make_option(names, maxi(0, values.find(Settings.get_value(key))))
	o.item_selected.connect(func(i): Settings.set_value(key, values[i]))
	_row(label, o)


func _toggle(label: String, key: String) -> void:
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(key))
	c.add_theme_font_size_override("font_size", 22)
	c.toggled.connect(func(on):
		Settings.set_value(key, on)
		if key in ["fullscreen", "vsync", "max_fps"]:
			Settings.apply_display()
		if key.begins_with("volume"):
			Settings.apply_audio())
	_row(label, c)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		Game.goto("menu")
