extends Node
## Persistent user settings (user://settings.cfg).

signal changed(key: String)

const PATH := "user://settings.cfg"

const DEFAULTS := {
	# timing / gameplay
	"input_offset_ms": 0.0,
	"scroll_speed": 1.0,
	"judge_preset": "od", # od | arcade | strict | lenient
	"outside_drum": "ka", # ka | ignore : what a hit outside the drum ellipse counts as
	"untracked_fallback": "imu", # imu | don : what to do when the camera cannot see the controller
	# hit detection
	"hit_mode": 0, # 0 air, 1 surface, 2 hybrid
	"trigger_point": 0, # 0 peak, 1 early
	"threshold": 4.0,
	"min_peak": 5.0,
	"jerk_threshold": 2.0,
	"refractory_ms": 50.0,
	"rise_margin": 2.0,
	"peak_confirm_ratio": 0.92,
	# tracking
	"tracking_mode": "camera", # camera | imu
	"imu_ka_mode": "twist", # twist | trigger
	"camera_fps": 125,
	"camera_width": 320,
	"camera_exposure": 40,
	"camera_gain": 8,
	"camera_flip_h": false,
	"camera_flip_v": false,
	"track_hue_left": -1.0,
	"track_hue_right": -1.0,
	"track_tolerance": 25.0,
	"track_min_sat": 0.35,
	"track_min_val": 0.25,
	# drum calibration (camera pixel space)
	"drum_calibrated": false,
	"drum_center": Vector2(160, 150),
	"drum_left": Vector2(80, 150),
	"drum_right": Vector2(240, 150),
	"drum_near": Vector2(160, 200),
	"drum_far": Vector2(160, 100),
	"drum_don_ratio": 0.6,
	"drum_ka_outer": 1.45,
	# controllers
	"left_serial": "",
	"right_serial": "",
	"led_brightness": 1.0,
	"led_flash": true,
	"rumble": true,
	"keyboard_enabled": true,
	# audio / display
	"volume_master": 1.0,
	"volume_music": 0.8,
	"volume_sfx": 1.0,
	"fullscreen": true,
	"vsync": false,
	"max_fps": 0,
	"show_error_bar": true,
	"show_drum_monitor": true,
	"show_fps": false,
	"setup_done": false,
}

var _data: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply_audio()


func load_settings() -> void:
	_data = DEFAULTS.duplicate(true)
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for key in cf.get_section_keys("settings") if cf.has_section("settings") else []:
			_data[key] = cf.get_value("settings", key)


func save() -> void:
	var cf := ConfigFile.new()
	for key in _data:
		cf.set_value("settings", key, _data[key])
	cf.save(PATH)


func get_value(key: String, default = null):
	if _data.has(key):
		return _data[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return default


func set_value(key: String, value, save_now: bool = true) -> void:
	_data[key] = value
	if save_now:
		save()
	changed.emit(key)


func reset_to_defaults() -> void:
	_data = DEFAULTS.duplicate(true)
	save()
	changed.emit("*")


## Windows-of-time preset for the Judge.
func judge_windows(od: float) -> Dictionary:
	return Judge.windows_preset(str(get_value("judge_preset")), od)


func hit_config() -> Dictionary:
	return {
		"mode": int(get_value("hit_mode")),
		"trigger_point": int(get_value("trigger_point")),
		"threshold": float(get_value("threshold")),
		"min_peak": float(get_value("min_peak")),
		"jerk_threshold": float(get_value("jerk_threshold")),
		"refractory_ms": float(get_value("refractory_ms")),
		"rise_margin": float(get_value("rise_margin")),
		"peak_confirm_ratio": float(get_value("peak_confirm_ratio")),
	}


func apply_audio() -> void:
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(clampf(float(get_value("volume_master")), 0.0001, 1.0)))


func apply_display() -> void:
	var fs: bool = bool(get_value("fullscreen"))
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_MAXIMIZED
	if DisplayServer.window_get_mode() != mode and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value("vsync")) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("max_fps"))


## Maps a camera pixel position into normalized drum coordinates (u right, v toward the player), rim at radius 1.
func drum_uv(p: Vector2) -> Vector2:
	var c: Vector2 = get_value("drum_center")
	var a: Vector2 = (get_value("drum_right") - get_value("drum_left")) * 0.5
	var b: Vector2 = (get_value("drum_near") - get_value("drum_far")) * 0.5
	var det := a.x * b.y - a.y * b.x
	if absf(det) < 1e-3:
		return Vector2(0, 0)
	var d := p - c
	var u := (d.x * b.y - d.y * b.x) / det
	var v := (a.x * d.y - a.y * d.x) / det
	return Vector2(u, v)


## Inverse of drum_uv (for drawing the calibrated ellipse).
func drum_xy(uv: Vector2) -> Vector2:
	var c: Vector2 = get_value("drum_center")
	var a: Vector2 = (get_value("drum_right") - get_value("drum_left")) * 0.5
	var b: Vector2 = (get_value("drum_near") - get_value("drum_far")) * 0.5
	return c + a * uv.x + b * uv.y
