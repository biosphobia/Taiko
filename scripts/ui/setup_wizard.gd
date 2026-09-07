extends Control
## Setup & calibration wizard: controllers, pairing, hit sensitivity, camera, drum zones and input offset.

const STEPS := ["Welcome", "Controllers", "Sensitivity", "Camera", "Drum zones", "Offset", "Done"]
const BEAT_MS := 500.0
const CAL_LEAD_IN := 2000.0
const CAL_BEATS := 32

var step := 0
var _header: Label
var _content: Control
var _b_back: Button
var _b_next: Button
var _b_skip: Button
var _t := {}
# step state
var _info_label: Label
var _assign_state := -1 ## -1 idle, 0 waiting left, 1 waiting right
var _assign_label: Label
var _pair_status: Label
var _pair_row: HBoxContainer
var _pair_active := false
var _meter: Control
var _calib_strengths: Array = []
var _calib_active := false
var _calib_label: Label
var _hit_counter := [0, 0]
var _threshold_slider: HSlider
var _min_peak_slider: HSlider
var _preview: TextureRect
var _preview_tex: ImageTexture
var _overlay: Control
var _cam_status: Label
var _auto_exposure := false
var _auto_iter := 0
var _exposure_slider: HSlider
var _gain_slider: HSlider
var _sample_hand := -1
var _drum_point := 0
var _drum_label: Label
var _drum_test_label: Label
var _zone_counts := [0, 0]
var _clock: AudioClock
var _offset_errors: Array = []
var _offset_label: Label
var _offset_running := false
var _offset_result := 0.0
var _beat_flash := 0.0
var _flash_rect: ColorRect
var _refresh_timer := 0.0


func _ready() -> void:
	UiTheme.fit_scene(self)
	Hardware.gameplay_mode = false
	Hardware.menu_navigation = false
	_t = UiTheme.theme()
	UiTheme.make_background(self)
	_header = UiTheme.make_title("")
	_header.position = Vector2(60, 24)
	add_child(_header)
	_content = Control.new()
	_content.position = Vector2(60, 100)
	_content.size = Vector2(1480, 690)
	add_child(_content)
	var hb := HBoxContainer.new()
	hb.position = Vector2(60, 810)
	hb.add_theme_constant_override("separation", 16)
	add_child(hb)
	_b_back = UiTheme.make_button("Back", 24)
	_b_back.custom_minimum_size = Vector2(200, 52)
	_b_back.pressed.connect(func(): _go(step - 1))
	hb.add_child(_b_back)
	_b_next = UiTheme.make_button("Next", 24)
	_b_next.custom_minimum_size = Vector2(200, 52)
	_b_next.pressed.connect(func():
		if step < STEPS.size() - 1:
			_go(step + 1))
	hb.add_child(_b_next)
	_b_skip = UiTheme.make_button("Exit wizard", 24)
	_b_skip.custom_minimum_size = Vector2(200, 52)
	_b_skip.pressed.connect(func():
		Settings.set_value("setup_done", true)
		Game.goto("menu"))
	hb.add_child(_b_skip)
	Hardware.move_button.connect(_on_move_button)
	Hardware.raw_hit.connect(_on_raw_hit)
	Hardware.drum_hit.connect(_on_drum_hit)
	_go(0)


func _exit_tree() -> void:
	Hardware.menu_navigation = true
	if Hardware.hw != null:
		Hardware.hw.camera_set_preview(false)


func _clear() -> void:
	for c in _content.get_children():
		c.queue_free()
	_assign_state = -1
	if _calib_active:
		_calib_active = false
		Hardware.apply_hit_config()
	_auto_exposure = false
	_sample_hand = -1
	_offset_running = false
	# references into the freed step
	_info_label = null
	_assign_label = null
	_pair_status = null
	_pair_row = null
	_meter = null
	_calib_label = null
	_threshold_slider = null
	_min_peak_slider = null
	_preview = null
	_preview_tex = null
	_overlay = null
	_cam_status = null
	_exposure_slider = null
	_gain_slider = null
	_drum_label = null
	_drum_test_label = null
	_offset_label = null
	_flash_rect = null
	if _clock != null:
		_clock.stop()
		_clock.queue_free()
		_clock = null
	if Hardware.hw != null:
		Hardware.hw.camera_set_preview(false)


func _go(s: int) -> void:
	_clear()
	step = clampi(s, 0, STEPS.size() - 1)
	_header.text = "Setup %d/%d: %s" % [step + 1, STEPS.size(), STEPS[step]]
	_b_back.disabled = step == 0
	_b_next.text = "Finish" if step == STEPS.size() - 1 else "Next"
	if _b_next.pressed.is_connected(_finish):
		_b_next.pressed.disconnect(_finish)
	match step:
		0: _build_welcome()
		1: _build_controllers()
		2: _build_sensitivity()
		3: _build_camera()
		4: _build_drum()
		5: _build_offset()
		6: _build_done()
	_b_next.grab_focus()


func _text(text: String, size: int = 22, color: Color = Color(-1, 0, 0)) -> Label:
	var l := UiTheme.make_label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1400, 0)
	return l


func _vbox() -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.size = _content.size
	_content.add_child(vb)
	return vb


# ------------------------------------------------------------------ 0 welcome
func _build_welcome() -> void:
	var vb := _vbox()
	vb.add_child(_text("This wizard sets up your PS Move controllers, the PS3 Eye camera and the timing. You can re-run it any time from Settings.", 24))
	_info_label = _text("", 22, _t.accent)
	vb.add_child(_info_label)
	vb.add_child(_text("Requirements:\n  1. PS Move controllers (PS3 or PS4 model) connected over Bluetooth, or a PS4 Move plugged in with a USB cable.\n  2. A PS3 Eye camera with the WinUSB driver (install it once with Zadig: pick 'USB Camera-B4.09.24.1', driver WinUSB).\n  3. Place the camera above your screen, angled down toward the area where you will drum.\n\nWithout a camera the game still works: Don/Ka are then told apart by twisting the controller (or holding the trigger).", 20))
	vb.add_child(_text("Keyboard players: D F J K work everywhere, no setup needed.", 20, Color(1, 1, 1, 0.7)))


# ------------------------------------------------------------------ 1 controllers
func _build_controllers() -> void:
	var vb := _vbox()
	_info_label = _text("", 22)
	vb.add_child(_info_label)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	var b_left := UiTheme.make_button("Assign LEFT hand", 22)
	b_left.pressed.connect(func():
		_assign_state = 0
		_assign_label.text = "Press the MOVE button on the controller in your LEFT hand...")
	hb.add_child(b_left)
	var b_right := UiTheme.make_button("Assign RIGHT hand", 22)
	b_right.pressed.connect(func():
		_assign_state = 1
		_assign_label.text = "Press the MOVE button on the controller in your RIGHT hand...")
	hb.add_child(b_right)
	var b_swap := UiTheme.make_button("Swap hands", 22)
	b_swap.pressed.connect(func():
		var l = Settings.get_value("left_serial")
		Settings.set_value("left_serial", Settings.get_value("right_serial"), false)
		Settings.set_value("right_serial", l)
		Hardware.refresh_hands())
	hb.add_child(b_swap)
	_assign_label = _text("Assign which controller is which hand (needed for big notes). Unassigned controllers are used in the order they connect.", 20, Color(1, 1, 1, 0.75))
	vb.add_child(_assign_label)
	vb.add_child(_text("Tip: plug each controller in over USB once so its factory sensor calibration can be read and cached ('calibrated' above). It is reused over Bluetooth afterwards.", 19, Color(1, 1, 1, 0.75)))
	vb.add_child(_text("Pairing a controller over Bluetooth (Windows):", 24, _t.accent))
	vb.add_child(_text("Plug the controller in with a USB cable, then press 'Pair' next to it. Unplug it when asked and press its PS button until the light stays on. Registering with Windows needs TaikoMove to run as Administrator. PS4 Move controllers also work while they stay plugged in over USB.", 20))
	_pair_row = HBoxContainer.new()
	_pair_row.add_theme_constant_override("separation", 12)
	vb.add_child(_pair_row)
	_pair_status = _text("", 20, Color(1, 0.85, 0.5))
	vb.add_child(_pair_status)
	_refresh_controllers()


func _refresh_controllers() -> void:
	if not is_instance_valid(_info_label) or step != 1 or Hardware.hw == null:
		if is_instance_valid(_info_label) and Hardware.hw == null:
			_info_label.text = "Hardware extension not loaded: controllers unavailable."
		return
	var lines := []
	var slots: Array = Hardware.connected_slots()
	if slots.is_empty():
		lines.append("No controllers connected. Turn one on (PS button) or plug it in via USB.")
	for slot in slots:
		var info: Dictionary = Hardware.controller_info(slot)
		var hand := Hardware.hand_for_slot(slot)
		var hand_txt := "LEFT" if hand == 0 else ("RIGHT" if hand == 1 else "unassigned")
		var live: Dictionary = Hardware.controller_live(slot)
		var bat := "charging" if bool(info.get("charging", false)) else "%d/5" % int(info.get("battery", 0))
		var rate := 0.0
		if float(live.get("period_us", 0.0)) > 0.0:
			rate = 1e6 / float(live.get("period_us", 1.0))
		lines.append("Slot %d  %s  %s  via %s   battery %s   %s   %.0f reports/s   [%s]" % [slot, hand_txt, str(info.get("model", "")), "Bluetooth" if bool(info.get("bluetooth", false)) else "USB", bat, "calibrated" if bool(info.get("calibrated", false)) else "no calibration data (using auto-scale)", rate, str(info.get("serial", ""))])
	_info_label.text = "\n".join(lines)
	var row := _pair_row
	if is_instance_valid(row):
		for c in row.get_children():
			c.queue_free()
		for slot in slots:
			var info: Dictionary = Hardware.controller_info(slot)
			if not bool(info.get("bluetooth", false)) and not bool(info.get("virtual", false)):
				var b := UiTheme.make_button("Pair slot %d (USB)" % slot, 20)
				b.custom_minimum_size = Vector2(220, 44)
				b.pressed.connect(func():
					if Hardware.hw.pair_begin(slot):
						_pair_active = true
					_pair_status.text = str(Hardware.hw.pair_status().get("message", "")))
				row.add_child(b)
		if row.get_child_count() == 0:
			row.add_child(UiTheme.make_label("(no USB-connected controller found)", 18, Color(1, 1, 1, 0.5)))
		if not Hardware.hw.is_elevated():
			row.add_child(UiTheme.make_label("Not running as Administrator: pairing registration will fail.", 18, Color(1, 0.6, 0.5)))


func _on_move_button(slot: int, _buttons: int, pressed: int, _released: int) -> void:
	if pressed & Hardware.BTN_MOVE:
		if step == 1 and _assign_state >= 0:
			var serial: String = str(Hardware.controller_info(slot).get("serial", ""))
			var key := "left_serial" if _assign_state == 0 else "right_serial"
			var other := "right_serial" if _assign_state == 0 else "left_serial"
			if str(Settings.get_value(other)) == serial:
				Settings.set_value(other, "", false)
			Settings.set_value(key, serial)
			Hardware.refresh_hands()
			_assign_label.text = "%s hand assigned to %s." % ["LEFT" if _assign_state == 0 else "RIGHT", serial]
			_assign_state = -1
			Game.play_sfx("ui_select")
		elif step == 3 and _sample_hand >= 0:
			_sample_color_now()
		elif step == 4 and _drum_point < 5:
			_capture_drum_point(slot)


# ------------------------------------------------------------------ 2 sensitivity
func _build_sensitivity() -> void:
	var vb := _vbox()
	vb.add_child(_text("Hold the controllers like drumsticks with the glowing spheres pointing forward. Air drumming: strike downward and stop, the hit is registered at the fastest point of the swing. Surface mode registers the impact when you hit a pillow, pad or table.", 20))
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 20)
	vb.add_child(opts)
	opts.add_child(UiTheme.make_label("Hit mode", 22))
	var mode := UiTheme.make_option(["Air drumming", "Hitting a surface", "Hybrid"], int(Settings.get_value("hit_mode")))
	mode.item_selected.connect(func(i): Settings.set_value("hit_mode", i))
	opts.add_child(mode)
	opts.add_child(UiTheme.make_label("Trigger point", 22))
	var tp := UiTheme.make_option(["Peak (consistent)", "Early (lowest latency)"], int(Settings.get_value("trigger_point")))
	tp.item_selected.connect(func(i): Settings.set_value("trigger_point", i))
	opts.add_child(tp)
	opts.add_child(UiTheme.make_label("Ka without camera", 22))
	var ka := UiTheme.make_option(["Twist 90 degrees", "Hold trigger"], 0 if str(Settings.get_value("imu_ka_mode")) == "twist" else 1)
	ka.item_selected.connect(func(i): Settings.set_value("imu_ka_mode", "twist" if i == 0 else "trigger"))
	opts.add_child(ka)
	_meter = Control.new()
	_meter.custom_minimum_size = Vector2(1400, 220)
	_meter.draw.connect(_draw_meter)
	vb.add_child(_meter)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	var b_cal := UiTheme.make_button("Auto-calibrate: hit 8 times", 22)
	b_cal.custom_minimum_size = Vector2(360, 48)
	b_cal.pressed.connect(func():
		_calib_strengths.clear()
		_calib_active = true
		# Measure true stroke peaks: air mode, peak trigger (restored by apply_hit_config afterwards).
		if Hardware.hw != null:
			Hardware.hw.set_hit_config({"mode": 0, "trigger_point": 0})
		_calib_label.text = "Hit the drum 8 times at your normal strength... 0/8")
	row.add_child(b_cal)
	_calib_label = UiTheme.make_label("Auto-calibration sets the thresholds from your own strokes (recommended).", 20, Color(1, 1, 1, 0.75))
	row.add_child(_calib_label)
	var sl := HBoxContainer.new()
	sl.add_theme_constant_override("separation", 16)
	vb.add_child(sl)
	sl.add_child(UiTheme.make_label("Swing threshold", 20))
	_threshold_slider = UiTheme.make_slider(1.0, 15.0, 0.1, float(Settings.get_value("threshold")))
	_threshold_slider.value_changed.connect(func(v): Settings.set_value("threshold", v))
	sl.add_child(_threshold_slider)
	sl.add_child(UiTheme.make_label("Minimum peak", 20))
	_min_peak_slider = UiTheme.make_slider(1.0, 20.0, 0.1, float(Settings.get_value("min_peak")))
	_min_peak_slider.value_changed.connect(func(v): Settings.set_value("min_peak", v))
	sl.add_child(_min_peak_slider)
	_hit_counter = [0, 0]


func _draw_meter() -> void:
	var w := _meter.size.x
	var f := UiTheme.font()
	for hand in range(2):
		var y := 20.0 + hand * 100.0
		var slot := Hardware.slot_for_hand(hand)
		_meter.draw_rect(Rect2(0, y, w, 80), Color(0, 0, 0, 0.45))
		var name := "LEFT" if hand == 0 else "RIGHT"
		if slot < 0:
			_meter.draw_string(f, Vector2(12, y + 48), name + ": no controller", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.5))
			continue
		var live: Dictionary = Hardware.controller_live(slot)
		var speed := float(live.get("down_speed", 0.0))
		var peak := float(live.get("last_peak", 0.0))
		var maxv := 20.0
		var bar_w := w - 320.0
		var x0 := 300.0
		var col := Color(0.3, 0.9, 0.5) if speed > 0 else Color(0.5, 0.6, 0.9)
		_meter.draw_rect(Rect2(x0, y + 20, clampf(absf(speed) / maxv, 0.0, 1.0) * bar_w, 40), col)
		var thr := float(Settings.get_value("threshold")) / maxv * bar_w
		var mp := float(Settings.get_value("min_peak")) / maxv * bar_w
		_meter.draw_line(Vector2(x0 + thr, y + 10), Vector2(x0 + thr, y + 70), Color(1, 0.8, 0.2), 3.0)
		_meter.draw_line(Vector2(x0 + mp, y + 10), Vector2(x0 + mp, y + 70), Color(1, 0.3, 0.3), 3.0)
		var px := x0 + clampf(peak / maxv, 0.0, 1.0) * bar_w
		_meter.draw_line(Vector2(px, y + 20), Vector2(px, y + 60), Color.WHITE, 2.0)
		_meter.draw_string(f, Vector2(12, y + 34), "%s  hits: %d" % [name, _hit_counter[hand]], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
		_meter.draw_string(f, Vector2(12, y + 62), "speed %.1f  last peak %.1f rad/s" % [speed, peak], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.7))
	_meter.draw_string(f, Vector2(300, 215), "yellow = swing threshold, red = minimum peak, white = last peak", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))


func _on_raw_hit(slot: int, _t: int, strength: float, kind: int, _tracked: bool, _pos: Vector2) -> void:
	if step == 2:
		var hand := Hardware.hand_for_slot(slot)
		if hand >= 0:
			_hit_counter[hand] += 1
		if _calib_active and kind == 0 and is_instance_valid(_calib_label):
			_calib_strengths.append(strength)
			_calib_label.text = "Hit the drum 8 times at your normal strength... %d/8" % _calib_strengths.size()
			if _calib_strengths.size() >= 8:
				_calib_active = false
				var s: Array = _calib_strengths.duplicate()
				s.sort()
				var median: float = s[s.size() / 2]
				var thr := clampf(median * 0.35, 1.5, 12.0)
				var mp := clampf(median * 0.5, 2.0, 15.0)
				Settings.set_value("threshold", snappedf(thr, 0.1), false)
				Settings.set_value("min_peak", snappedf(mp, 0.1))
				_threshold_slider.set_value_no_signal(thr)
				_min_peak_slider.set_value_no_signal(mp)
				Hardware.apply_hit_config()
				_calib_label.text = "Done. Median stroke %.1f rad/s -> threshold %.1f, minimum peak %.1f" % [median, thr, mp]
				Game.play_sfx("unlock")


func _on_drum_hit(hand: int, kind: int, _t: int, _s: float, source: String) -> void:
	if source != "move":
		return
	Game.play_sfx("don" if kind == 0 else "ka")
	if step == 4 and is_instance_valid(_drum_test_label):
		_zone_counts[kind] += 1
		_drum_test_label.text = "%s hand: %s      (Don %d / Ka %d)" % ["LEFT" if hand == 0 else "RIGHT", "DON" if kind == 0 else "KA", _zone_counts[0], _zone_counts[1]]
	if step == 5 and _offset_running and _clock != null:
		var t := _clock.song_time_at(_t)
		var beat := roundf((t - CAL_LEAD_IN) / BEAT_MS)
		if beat >= 0 and beat < CAL_BEATS:
			var err := t - (CAL_LEAD_IN + beat * BEAT_MS)
			if absf(err) < 200.0:
				_offset_errors.append(err)
				_update_offset_label()


# ------------------------------------------------------------------ 3 camera
func _build_camera() -> void:
	var vb := _vbox()
	if Hardware.hw == null or Hardware.hw.camera_device_count() == 0 and not Hardware.camera_running():
		vb.add_child(_text("No PS3 Eye camera found.", 28, Color(1, 0.6, 0.5)))
		vb.add_child(_text("Windows needs the WinUSB driver for the camera: download Zadig (zadig.akeo.ie), select 'USB Camera-B4.09.24.1' (VID 1415, PID 2000), choose WinUSB and click Install. Then plug the camera into a USB 2.0 port and press Retry.", 22))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		vb.add_child(hb)
		var b_retry := UiTheme.make_button("Retry", 22)
		b_retry.pressed.connect(func(): _go(3))
		hb.add_child(b_retry)
		var b_skip := UiTheme.make_button("Continue without camera (IMU mode)", 22)
		b_skip.custom_minimum_size = Vector2(460, 52)
		b_skip.pressed.connect(func():
			Settings.set_value("tracking_mode", "imu")
			_go(5))
		hb.add_child(b_skip)
		return
	if not Hardware.camera_running():
		if not Hardware.start_camera():
			vb.add_child(_text("The camera was found but could not be started (is another program using it?).", 24, Color(1, 0.6, 0.5)))
			var b_retry := UiTheme.make_button("Retry", 22)
			b_retry.pressed.connect(func(): _go(3))
			vb.add_child(b_retry)
			return
	Settings.set_value("tracking_mode", "camera", false)
	Hardware.hw.camera_set_preview(true)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(640, 480)
	hb.add_child(frame)
	_preview = TextureRect.new()
	_preview.size = Vector2(640, 480)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_SCALE
	frame.add_child(_preview)
	_overlay = Control.new()
	_overlay.size = Vector2(640, 480)
	_overlay.draw.connect(_draw_overlay)
	frame.add_child(_overlay)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	hb.add_child(right)
	right.add_child(_text("1. Lower the exposure until only the glowing spheres are bright (press Auto).\n2. Hold the LEFT controller's sphere inside the circle and press 'Sample left color' (or its Move button). Repeat for the right one.\n3. Both spheres should then show a white ring in the preview.", 19))
	var er := HBoxContainer.new()
	er.add_child(UiTheme.make_label("Exposure", 20))
	_exposure_slider = UiTheme.make_slider(0, 255, 1, float(Settings.get_value("camera_exposure")))
	_exposure_slider.value_changed.connect(func(v): Settings.set_value("camera_exposure", int(v)))
	er.add_child(_exposure_slider)
	right.add_child(er)
	var gr := HBoxContainer.new()
	gr.add_child(UiTheme.make_label("Gain", 20))
	_gain_slider = UiTheme.make_slider(0, 63, 1, float(Settings.get_value("camera_gain")))
	_gain_slider.value_changed.connect(func(v): Settings.set_value("camera_gain", int(v)))
	gr.add_child(_gain_slider)
	right.add_child(gr)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 12)
	right.add_child(br)
	var b_auto := UiTheme.make_button("Auto exposure", 20)
	b_auto.custom_minimum_size = Vector2(200, 44)
	b_auto.pressed.connect(func():
		_auto_exposure = true
		_auto_iter = 0
		_exposure_slider.set_value_no_signal(120)
		Settings.set_value("camera_exposure", 120))
	br.add_child(b_auto)
	var flip := CheckButton.new()
	flip.text = "Mirror"
	flip.button_pressed = bool(Settings.get_value("camera_flip_h"))
	flip.toggled.connect(func(on): Settings.set_value("camera_flip_h", on))
	br.add_child(flip)
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 12)
	right.add_child(sr)
	for hand in range(2):
		var b := UiTheme.make_button("Sample %s color" % ("left" if hand == 0 else "right"), 20)
		b.custom_minimum_size = Vector2(220, 44)
		b.pressed.connect(func():
			_sample_hand = hand
			_sample_color_now())
		sr.add_child(b)
	var b_arm := UiTheme.make_button("Arm: sample with Move button", 18)
	b_arm.custom_minimum_size = Vector2(220, 44)
	b_arm.pressed.connect(func():
		_sample_hand = 0 if _sample_hand != 0 else 1
		_cam_status.text = "Armed for %s: press the Move button while the sphere is in the circle." % ("LEFT" if _sample_hand == 0 else "RIGHT"))
	sr.add_child(b_arm)
	_cam_status = _text("", 19, Color(1, 0.9, 0.6))
	right.add_child(_cam_status)
	var b_nocam := UiTheme.make_button("Use IMU mode instead (no camera)", 18)
	b_nocam.custom_minimum_size = Vector2(320, 40)
	b_nocam.pressed.connect(func():
		Settings.set_value("tracking_mode", "imu")
		_go(5))
	right.add_child(b_nocam)


func _sample_color_now() -> void:
	if Hardware.hw == null or _sample_hand < 0:
		return
	var cw := float(Settings.get_value("camera_width"))
	var r: Dictionary = Hardware.hw.camera_sample_color(cw * 0.5, cw * 0.375, cw * 0.11)
	if not bool(r.get("ok", false)):
		_cam_status.text = "No bright colored pixels inside the circle. Move the sphere into the circle (and lower the exposure if it looks white)."
		return
	var hue := float(r.hue)
	var key := "track_hue_left" if _sample_hand == 0 else "track_hue_right"
	Settings.set_value(key, hue)
	var other := float(Settings.get_value("track_hue_right" if _sample_hand == 0 else "track_hue_left"))
	var msg := "%s color sampled: hue %.0f, saturation %.2f (%d px)." % ["LEFT" if _sample_hand == 0 else "RIGHT", hue, float(r.sat), int(r.count)]
	if float(r.sat) < 0.4:
		msg += " Saturation is low: lower the exposure so the sphere is not washed out."
	if other >= 0.0:
		var d := absf(hue - other)
		d = minf(d, 360.0 - d)
		if d < 2.0 * float(Settings.get_value("track_tolerance")):
			msg += " WARNING: both hands have similar colors, choose different LED colors in Unlockables."
	_cam_status.text = msg
	Hardware.apply_camera_targets()
	Game.play_sfx("ui_select")
	_sample_hand = -1


func _draw_overlay() -> void:
	if Hardware.hw == null:
		return
	var cw := float(Settings.get_value("camera_width"))
	var scale := 640.0 / cw
	var f := UiTheme.font()
	if step == 3:
		_overlay.draw_arc(Vector2(320, 240), cw * 0.11 * scale, 0.0, TAU, 40, Color(1, 1, 1, 0.8), 2.0)
	for hand in range(2):
		var tr := Hardware.tracking_for_hand(hand)
		if bool(tr.get("tracked", false)):
			var p: Vector2 = tr.get("pos", Vector2.ZERO) * scale
			var r := maxf(6.0, float(tr.get("radius", 5.0)) * scale)
			_overlay.draw_arc(p, r + 4.0, 0.0, TAU, 32, Color.WHITE, 3.0)
			_overlay.draw_string(f, p + Vector2(r + 8, 6), "L" if hand == 0 else "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	if step == 4 and bool(Settings.get_value("drum_calibrated")):
		var pts := PackedVector2Array()
		var inner := PackedVector2Array()
		var outer := PackedVector2Array()
		for i in range(49):
			var a := TAU * i / 48.0
			var uv := Vector2(cos(a), sin(a))
			pts.append(Settings.drum_xy(uv) * scale)
			inner.append(Settings.drum_xy(uv * float(Settings.get_value("drum_don_ratio"))) * scale)
			outer.append(Settings.drum_xy(uv * float(Settings.get_value("drum_ka_outer"))) * scale)
		_overlay.draw_polyline(outer, Color(0.25, 0.7, 0.95, 0.6), 2.0)
		_overlay.draw_polyline(pts, Color.WHITE, 2.0)
		_overlay.draw_polyline(inner, Color(0.95, 0.27, 0.22), 2.0)
	if step == 4:
		var names := ["center", "left", "right", "near", "far"]
		for i in range(mini(_drum_point, 5)):
			var p: Vector2 = Settings.get_value("drum_" + names[i]) * scale
			_overlay.draw_circle(p, 5.0, Color(1, 0.8, 0.2))
	var stats: Dictionary = Hardware.hw.camera_get_stats()
	_overlay.draw_string(f, Vector2(8, 470), "%.0f fps  exp %d  gain %d  stray bright %d  proc %.1f ms" % [float(stats.get("fps", 0.0)), int(stats.get("exposure", 0)), int(stats.get("gain", 0)), int(stats.get("stray_bright", 0)), float(stats.get("process_ms", 0.0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))


func _update_preview() -> void:
	if not is_instance_valid(_preview) or not is_instance_valid(_overlay) or Hardware.hw == null or not Hardware.camera_running():
		return
	var img: Image = Hardware.hw.camera_get_preview()
	if img == null:
		return
	if _preview_tex == null or Vector2i(_preview_tex.get_size()) != img.get_size():
		_preview_tex = ImageTexture.create_from_image(img)
		_preview.texture = _preview_tex
	else:
		_preview_tex.update(img)
	_overlay.queue_redraw()


func _auto_exposure_step() -> void:
	if not _auto_exposure or Hardware.hw == null or not is_instance_valid(_exposure_slider):
		_auto_exposure = false
		return
	_auto_iter += 1
	if _auto_iter % 8 != 0:
		return
	var stats: Dictionary = Hardware.hw.camera_get_stats()
	var exp := int(Settings.get_value("camera_exposure"))
	var stray := int(stats.get("stray_bright", 0))
	if stray > 40 and exp > 3:
		exp = maxi(3, exp - maxi(2, int(exp * 0.15)))
		Settings.set_value("camera_exposure", exp)
		_exposure_slider.set_value_no_signal(exp)
		_cam_status.text = "Auto exposure: %d (stray bright pixels %d)" % [exp, stray]
	else:
		_auto_exposure = false
		_cam_status.text = "Auto exposure done: %d. Now sample each controller's color." % exp
	if _auto_iter > 400:
		_auto_exposure = false


# ------------------------------------------------------------------ 4 drum zones
func _build_drum() -> void:
	var vb := _vbox()
	if str(Settings.get_value("tracking_mode")) != "camera" or not Hardware.camera_running():
		vb.add_child(_text("Camera tracking is not active, so drum zones are not used. Don/Ka come from the controller (twist or trigger).", 24))
		return
	Hardware.hw.camera_set_preview(true)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(640, 480)
	hb.add_child(frame)
	_preview = TextureRect.new()
	_preview.size = Vector2(640, 480)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_SCALE
	frame.add_child(_preview)
	_overlay = Control.new()
	_overlay.size = Vector2(640, 480)
	_overlay.draw.connect(_draw_overlay)
	frame.add_child(_overlay)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	hb.add_child(right)
	right.add_child(_text("Define where your virtual drum is. Imagine a drum in front of you (a real pad or pillow works great). For each point, hold a sphere exactly there and press the Move button (or Capture).", 19))
	_drum_point = 0
	_drum_label = _text("", 24, _t.accent)
	right.add_child(_drum_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	right.add_child(row)
	var b_cap := UiTheme.make_button("Capture", 20)
	b_cap.custom_minimum_size = Vector2(160, 44)
	b_cap.pressed.connect(func(): _capture_drum_point(-1))
	row.add_child(b_cap)
	var b_restart := UiTheme.make_button("Restart", 20)
	b_restart.custom_minimum_size = Vector2(160, 44)
	b_restart.pressed.connect(func():
		_drum_point = 0
		_update_drum_label())
	row.add_child(b_restart)
	var sr := HBoxContainer.new()
	sr.add_child(UiTheme.make_label("Don area size", 20))
	var don := UiTheme.make_slider(0.3, 0.9, 0.01, float(Settings.get_value("drum_don_ratio")))
	don.value_changed.connect(func(v): Settings.set_value("drum_don_ratio", v))
	sr.add_child(don)
	right.add_child(sr)
	var kr := HBoxContainer.new()
	kr.add_child(UiTheme.make_label("Ka outer limit", 20))
	var ka := UiTheme.make_slider(1.05, 2.2, 0.01, float(Settings.get_value("drum_ka_outer")))
	ka.value_changed.connect(func(v): Settings.set_value("drum_ka_outer", v))
	kr.add_child(ka)
	right.add_child(kr)
	_drum_test_label = _text("Test: drum away, hits show as DON or KA here.", 22, Color(1, 1, 1, 0.8))
	right.add_child(_drum_test_label)
	_zone_counts = [0, 0]
	_update_drum_label()


func _update_drum_label() -> void:
	var names := ["the CENTER of the drum", "the LEFT edge of the drum (left hand)", "the RIGHT edge of the drum (right hand)", "the edge NEAREST to you", "the edge FARTHEST from you"]
	if _drum_point < 5:
		_drum_label.text = "Point %d/5: hold a sphere at %s and press Move / Capture." % [_drum_point + 1, names[_drum_point]]
	else:
		_drum_label.text = "Drum calibrated. Red = Don area, white = rim, blue = Ka limit. Adjust with the sliders and test below."


func _capture_drum_point(slot: int) -> void:
	if _drum_point >= 5 or Hardware.hw == null or not is_instance_valid(_drum_label):
		return
	var hand := Hardware.hand_for_slot(slot) if slot >= 0 else -1
	var preferred := hand
	if _drum_point == 1:
		preferred = 0
	elif _drum_point == 2:
		preferred = 1
	var pos := Vector2(-1, -1)
	var order := [preferred, 0, 1] if preferred >= 0 else [0, 1]
	for h in order:
		var tr := Hardware.tracking_for_hand(h)
		if bool(tr.get("tracked", false)):
			pos = tr.get("pos", Vector2(-1, -1))
			break
	if pos.x < 0:
		_drum_label.text = "No sphere is visible right now. Make sure the colors are sampled and the sphere is in view."
		return
	var keys := ["drum_center", "drum_left", "drum_right", "drum_near", "drum_far"]
	Settings.set_value(keys[_drum_point], pos, false)
	_drum_point += 1
	Game.play_sfx("ui_select")
	if _drum_point >= 5:
		# sanity: the rims must span a reasonable area
		var a: Vector2 = Settings.get_value("drum_right") - Settings.get_value("drum_left")
		var b: Vector2 = Settings.get_value("drum_near") - Settings.get_value("drum_far")
		if a.length() < 10.0 or b.length() < 6.0:
			_drum_point = 0
			Settings.set_value("drum_calibrated", false)
			_drum_label.text = "The captured points are too close together; try again with a bigger drum."
			return
		Settings.set_value("drum_calibrated", true)
		Game.play_sfx("unlock")
	else:
		Settings.save()
	_update_drum_label()


# ------------------------------------------------------------------ 5 offset
func _build_offset() -> void:
	var vb := _vbox()
	vb.add_child(_text("A metronome plays for 16 seconds. Drum along on the beat with your controllers (Don or Ka, either hand). The average error becomes your input offset, so that hits you feel are 'on time' are judged as on time.", 21))
	_flash_rect = ColorRect.new()
	_flash_rect.custom_minimum_size = Vector2(1400, 120)
	_flash_rect.color = Color(1, 1, 1, 0.05)
	vb.add_child(_flash_rect)
	_offset_label = _text("Current input offset: %+.0f ms" % float(Settings.get_value("input_offset_ms")), 24, _t.accent)
	vb.add_child(_offset_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	var b_start := UiTheme.make_button("Start metronome", 22)
	b_start.pressed.connect(_start_offset_test)
	row.add_child(b_start)
	var b_apply := UiTheme.make_button("Apply suggested offset", 22)
	b_apply.custom_minimum_size = Vector2(340, 52)
	b_apply.pressed.connect(func():
		if _offset_errors.size() >= 4:
			Settings.set_value("input_offset_ms", snappedf(_offset_result, 1.0))
			_offset_label.text = "Input offset set to %+.0f ms." % _offset_result
			Game.play_sfx("unlock"))
	row.add_child(b_apply)
	vb.add_child(_text("Tip: the results screen after every song also shows your average timing error and can apply an offset.", 18, Color(1, 1, 1, 0.6)))


func _start_offset_test() -> void:
	if _clock != null:
		_clock.stop()
		_clock.queue_free()
	_clock = AudioClock.new()
	add_child(_clock)
	var stream := SongLibrary.load_audio("res://songs/calibration/audio.ogg")
	_clock.setup(stream, 1000.0)
	_clock.start()
	_offset_errors.clear()
	_offset_running = true
	_offset_label.text = "Listen... drum on every tick."


func _update_offset_label() -> void:
	var n := _offset_errors.size()
	var s := 0.0
	for e in _offset_errors:
		s += float(e)
	var mean := s / n
	var v := 0.0
	for e in _offset_errors:
		v += (float(e) - mean) * (float(e) - mean)
	var std := sqrt(v / n)
	_offset_result = -mean
	_offset_label.text = "%d hits   average %+.1f ms (%s)   consistency +/-%.1f ms   ->  suggested offset %+.0f ms" % [n, mean, "late" if mean > 0 else "early", std, _offset_result]


# ------------------------------------------------------------------ 6 done
func _build_done() -> void:
	var vb := _vbox()
	var hands := Hardware.hands_connected()
	var lines := []
	lines.append("Controllers: left %s, right %s" % ["connected" if hands.left else "not connected", "connected" if hands.right else "not connected"])
	lines.append("Hit mode: %s, threshold %.1f rad/s, minimum peak %.1f rad/s" % [["air", "surface", "hybrid"][int(Settings.get_value("hit_mode"))], float(Settings.get_value("threshold")), float(Settings.get_value("min_peak"))])
	lines.append("Don/Ka: %s" % ("camera drum zones (%s)" % ("calibrated" if bool(Settings.get_value("drum_calibrated")) else "NOT calibrated") if str(Settings.get_value("tracking_mode")) == "camera" else "IMU (%s)" % str(Settings.get_value("imu_ka_mode"))))
	lines.append("Input offset: %+.0f ms" % float(Settings.get_value("input_offset_ms")))
	vb.add_child(_text("\n".join(lines), 24))
	vb.add_child(_text("Press Finish to save. You can change everything later in Settings or by running this wizard again.", 20, Color(1, 1, 1, 0.7)))
	if not _b_next.pressed.is_connected(_finish):
		_b_next.pressed.connect(_finish)


func _finish() -> void:
	Settings.set_value("setup_done", true)
	Game.goto("menu")


# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	_refresh_timer -= delta
	if step == 1:
		if _refresh_timer <= 0.0:
			_refresh_timer = 0.5
			_refresh_controllers()
		if _pair_active and Hardware.hw != null:
			var st: Dictionary = Hardware.hw.pair_status()
			_pair_status.text = str(st.get("message", ""))
			if bool(st.get("done", false)):
				_pair_active = false
	elif step == 2 and _meter != null:
		_meter.queue_redraw()
	elif step == 3 or step == 4:
		_update_preview()
		_auto_exposure_step()
	elif step == 5 and _clock != null and _offset_running and is_instance_valid(_flash_rect):
		var t := _clock.now_ms()
		var phase := fposmod(t - CAL_LEAD_IN, BEAT_MS)
		_flash_rect.color = Color(1, 1, 1, 0.05 + 0.5 * maxf(0.0, 1.0 - phase / 120.0)) if t >= CAL_LEAD_IN - 1.0 else Color(1, 1, 1, 0.05)
		if t > CAL_LEAD_IN + CAL_BEATS * BEAT_MS + 500.0 or _clock.audio_finished():
			_offset_running = false
			_clock.stop()
			if _offset_errors.size() < 4:
				_offset_label.text = "Not enough hits registered. Try again."


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		Game.goto("menu")
