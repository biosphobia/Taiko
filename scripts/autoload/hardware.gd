extends Node
## Bridge between the native TaikoHW extension (PS Move + PS3 Eye) and the game.
## Emits unified drum hits from controllers and the keyboard.

signal drum_hit(hand: int, kind: int, t_usec: int, strength: float, source: String)
signal raw_hit(slot: int, t_usec: int, strength: float, kind: int, tracked: bool, pos: Vector2)
signal controllers_changed
signal move_button(slot: int, buttons: int, pressed: int, released: int)

enum Hand { LEFT = 0, RIGHT = 1 }
enum Kind { DON = 0, KA = 1 }

const BTN_TRIANGLE := 1 << 4
const BTN_CIRCLE := 1 << 5
const BTN_CROSS := 1 << 6
const BTN_SQUARE := 1 << 7
const BTN_SELECT := 1 << 8
const BTN_START := 1 << 11
const BTN_PS := 1 << 16
const BTN_MOVE := 1 << 19
const BTN_T := 1 << 20

var hw: Node = null ## TaikoHW instance (null when the extension is unavailable)
var available: bool = false
var slot_hand: Dictionary = {} ## slot -> Hand
var gameplay_mode: bool = false ## true while playing: LEDs fixed for tracking, no menu navigation
var menu_navigation: bool = true
var _flash_until: Dictionary = {}
var _rumble_until: Dictionary = {}
var _rainbow_phase := 0.0
var _last_led: Dictionary = {}
var _camera_wanted := false
var _camera_retry := 0.0


func _ready() -> void:
	process_priority = -100 # flush hardware events before gameplay nodes run
	if ClassDB.class_exists("TaikoHW"):
		hw = ClassDB.instantiate("TaikoHW")
		hw.name = "TaikoHW"
		add_child(hw)
		hw.hit.connect(_on_hit)
		hw.button.connect(_on_button)
		hw.controller_connected.connect(_on_connected)
		hw.controller_disconnected.connect(_on_disconnected)
		var cal_dir := ProjectSettings.globalize_path("user://calibration")
		DirAccess.make_dir_recursive_absolute(cal_dir)
		hw.set_calibration_dir(cal_dir)
		if DisplayServer.get_name() != "headless" or OS.has_environment("TAIKO_HW_HEADLESS"):
			hw.start()
			available = hw.is_started()
		apply_hit_config()
	else:
		push_warning("TaikoHW extension not available: running with keyboard input only.")
	Settings.changed.connect(_on_setting_changed)
	Profile.item_equipped.connect(func(_c, _i): update_leds())
	set_process(true)


func _on_setting_changed(key: String) -> void:
	if key.begins_with("threshold") or key in ["hit_mode", "trigger_point", "min_peak", "jerk_threshold", "refractory_ms", "rise_margin", "peak_confirm_ratio", "*"]:
		apply_hit_config()
	if key.begins_with("track_") or key.begins_with("camera_") or key == "*":
		apply_camera_config()
	if key in ["left_serial", "right_serial", "led_brightness", "*"]:
		refresh_hands()
		update_leds()


func ticks_usec() -> int:
	return Time.get_ticks_usec()


# ---------------------------------------------------------------- controllers
func apply_hit_config() -> void:
	if hw:
		hw.set_hit_config(Settings.hit_config())


func refresh_hands() -> void:
	slot_hand.clear()
	if hw == null:
		return
	var left_serial: String = str(Settings.get_value("left_serial"))
	var right_serial: String = str(Settings.get_value("right_serial"))
	var unassigned: Array = []
	for slot in hw.get_connected_slots():
		var info: Dictionary = hw.get_controller_info(slot)
		var serial: String = str(info.get("serial", ""))
		if serial != "" and serial == left_serial:
			slot_hand[slot] = Hand.LEFT
		elif serial != "" and serial == right_serial:
			slot_hand[slot] = Hand.RIGHT
		else:
			unassigned.append(slot)
	# Unassigned controllers fill whichever hand is free (first = left).
	var used := slot_hand.values()
	for slot in unassigned:
		if not used.has(Hand.LEFT):
			slot_hand[slot] = Hand.LEFT
			used.append(Hand.LEFT)
		elif not used.has(Hand.RIGHT):
			slot_hand[slot] = Hand.RIGHT
			used.append(Hand.RIGHT)
	apply_camera_targets()
	controllers_changed.emit()


func hand_for_slot(slot: int) -> int:
	return int(slot_hand.get(slot, -1))


func slot_for_hand(hand: int) -> int:
	for slot in slot_hand:
		if int(slot_hand[slot]) == hand:
			return int(slot)
	return -1


func connected_slots() -> Array:
	return hw.get_connected_slots() if hw else []


func controller_info(slot: int) -> Dictionary:
	return hw.get_controller_info(slot) if hw else {}


func controller_live(slot: int) -> Dictionary:
	return hw.get_controller_live(slot) if hw else {}


func hands_connected() -> Dictionary:
	return {"left": slot_for_hand(Hand.LEFT) >= 0, "right": slot_for_hand(Hand.RIGHT) >= 0}


func _on_connected(slot: int) -> void:
	refresh_hands()
	update_leds()


func _on_disconnected(slot: int) -> void:
	refresh_hands()


func _on_button(slot: int, buttons: int, pressed: int, released: int) -> void:
	move_button.emit(slot, buttons, pressed, released)
	if menu_navigation and not gameplay_mode and pressed != 0:
		var action := ""
		if pressed & (BTN_MOVE | BTN_T | BTN_START):
			action = "ui_accept"
		elif pressed & (BTN_SELECT | BTN_CIRCLE):
			action = "ui_cancel"
		elif pressed & BTN_TRIANGLE:
			action = "ui_up"
		elif pressed & BTN_CROSS:
			action = "ui_down"
		elif pressed & BTN_SQUARE:
			action = "ui_left"
		if action != "":
			var ev := InputEventAction.new()
			ev.action = action
			ev.pressed = true
			Input.parse_input_event(ev)
			var ev2 := InputEventAction.new()
			ev2.action = action
			ev2.pressed = false
			Input.parse_input_event(ev2)
			if action == "ui_cancel":
				var ev3 := InputEventAction.new()
				ev3.action = "ui_back"
				ev3.pressed = true
				Input.parse_input_event(ev3)


func _on_hit(slot: int, t_usec: int, strength: float, kind: int, tracked: bool, pos: Vector2) -> void:
	raw_hit.emit(slot, t_usec, strength, kind, tracked, pos)
	var hand := hand_for_slot(slot)
	if hand < 0:
		refresh_hands()
		hand = hand_for_slot(slot)
		if hand < 0:
			hand = slot % 2
	var drum_kind := classify_hit(slot, hand, tracked, pos)
	if drum_kind < 0:
		return
	_flash(slot)
	drum_hit.emit(hand, drum_kind, t_usec, strength, "move")


## Decides DON vs KA for a controller hit. Returns -1 to ignore the hit.
func classify_hit(slot: int, hand: int, tracked: bool, pos: Vector2) -> int:
	var mode: String = str(Settings.get_value("tracking_mode"))
	if mode == "camera" and bool(Settings.get_value("drum_calibrated")):
		if tracked:
			var uv: Vector2 = Settings.drum_uv(pos)
			var r := uv.length()
			if r <= float(Settings.get_value("drum_don_ratio")):
				return Kind.DON
			if r <= float(Settings.get_value("drum_ka_outer")):
				return Kind.KA
			return Kind.KA if str(Settings.get_value("outside_drum")) == "ka" else -1
		if str(Settings.get_value("untracked_fallback")) == "don":
			return Kind.DON
	return _imu_kind(slot)


func _imu_kind(slot: int) -> int:
	if hw == null:
		return Kind.DON
	var live: Dictionary = hw.get_controller_live(slot)
	if str(Settings.get_value("imu_ka_mode")) == "trigger":
		return Kind.KA if int(live.get("trigger", 0)) > 100 else Kind.DON
	# twist: the controller rolled ~90 degrees around the stick axis reads gravity along X
	var up: Vector3 = live.get("up", Vector3(0, 0, 1))
	return Kind.KA if absf(up.x) > 0.6 else Kind.DON


# ---------------------------------------------------------------- LEDs / rumble
func _flash(slot: int) -> void:
	if bool(Settings.get_value("led_flash")):
		_flash_until[slot] = Time.get_ticks_msec() + 60
	if bool(Settings.get_value("rumble")):
		_rumble_until[slot] = Time.get_ticks_msec() + 40
		if hw:
			hw.set_rumble(slot, 0.6)


func led_color_for_slot(slot: int) -> Color:
	var hand := hand_for_slot(slot)
	if hand < 0:
		hand = slot % 2
	var it: Dictionary = Profile.led_item(hand)
	var c: Color = it.get("color", Color.RED if hand == 0 else Color.BLUE)
	if it.get("id", "") == "led_rainbow":
		if gameplay_mode:
			c = Color.RED if hand == 0 else Color.BLUE
		else:
			c = Color.from_hsv(fmod(_rainbow_phase + 0.5 * hand, 1.0), 1.0, 1.0)
	return c * float(Settings.get_value("led_brightness"))


func update_leds() -> void:
	if hw == null:
		return
	for slot in hw.get_connected_slots():
		var c := led_color_for_slot(slot)
		if _flash_until.get(slot, 0) > Time.get_ticks_msec():
			c = c.lerp(Color.WHITE, 0.7)
		if _last_led.get(slot, Color(-1, 0, 0)) != c:
			hw.set_led(slot, c)
			_last_led[slot] = c


func _process(delta: float) -> void:
	if hw == null:
		return
	_rainbow_phase = fmod(_rainbow_phase + delta * 0.15, 1.0)
	update_leds()
	for slot in _rumble_until.keys():
		if _rumble_until[slot] <= Time.get_ticks_msec():
			hw.set_rumble(slot, 0.0)
			_rumble_until.erase(slot)
	if _camera_wanted and not hw.camera_running():
		_camera_retry -= delta
		if _camera_retry <= 0.0:
			_camera_retry = 3.0
			start_camera()


# ---------------------------------------------------------------- camera
func camera_available() -> bool:
	return hw != null and hw.camera_device_count() > 0


func start_camera() -> bool:
	if hw == null:
		return false
	_camera_wanted = true
	if hw.camera_running():
		return true
	var ok: bool = hw.camera_start(int(Settings.get_value("camera_fps")), int(Settings.get_value("camera_width")))
	if ok:
		apply_camera_config()
	return ok


func stop_camera() -> void:
	_camera_wanted = false
	if hw:
		hw.camera_stop()


func camera_running() -> bool:
	return hw != null and hw.camera_running()


func apply_camera_config() -> void:
	if hw == null or not hw.camera_running():
		return
	hw.camera_set_auto(false)
	hw.camera_set_exposure(int(Settings.get_value("camera_exposure")))
	hw.camera_set_gain(int(Settings.get_value("camera_gain")))
	hw.camera_set_flip(bool(Settings.get_value("camera_flip_h")), bool(Settings.get_value("camera_flip_v")))
	apply_camera_targets()


func apply_camera_targets() -> void:
	if hw == null:
		return
	var tol := float(Settings.get_value("track_tolerance"))
	var min_sat := float(Settings.get_value("track_min_sat"))
	var min_val := float(Settings.get_value("track_min_val"))
	for slot in range(hw.get_slot_count()):
		var hand := hand_for_slot(slot)
		var hue := -1.0
		if hand == Hand.LEFT:
			hue = float(Settings.get_value("track_hue_left"))
		elif hand == Hand.RIGHT:
			hue = float(Settings.get_value("track_hue_right"))
		hw.camera_set_target(slot, maxf(hue, 0.0), tol, min_sat, min_val, hue >= 0.0)


func tracking_for_hand(hand: int) -> Dictionary:
	var slot := slot_for_hand(hand)
	if slot < 0 or hw == null:
		return {"tracked": false}
	return hw.camera_get_result(slot)


# ---------------------------------------------------------------- keyboard
func _unhandled_input(event: InputEvent) -> void:
	if not bool(Settings.get_value("keyboard_enabled")):
		return
	if event.is_echo() or not event.is_pressed():
		return
	var t := Time.get_ticks_usec()
	if event.is_action_pressed("taiko_left_don"):
		drum_hit.emit(Hand.LEFT, Kind.DON, t, 1.0, "keyboard")
	elif event.is_action_pressed("taiko_right_don"):
		drum_hit.emit(Hand.RIGHT, Kind.DON, t, 1.0, "keyboard")
	elif event.is_action_pressed("taiko_left_ka"):
		drum_hit.emit(Hand.LEFT, Kind.KA, t, 1.0, "keyboard")
	elif event.is_action_pressed("taiko_right_ka"):
		drum_hit.emit(Hand.RIGHT, Kind.KA, t, 1.0, "keyboard")


## Status summary for menus.
func status_text() -> String:
	if hw == null:
		return "Hardware extension missing (keyboard only)"
	var hands := hands_connected()
	var parts := []
	parts.append("L: %s" % ("OK" if hands.left else "--"))
	parts.append("R: %s" % ("OK" if hands.right else "--"))
	parts.append("Camera: %s" % ("ON" if camera_running() else "off"))
	return "  ".join(parts)
