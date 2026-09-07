extends Node
## Scene flow, shared state between scenes and low-latency sound effects.

const SCENES := {
	"boot": "res://scenes/boot.tscn",
	"menu": "res://scenes/main_menu.tscn",
	"songs": "res://scenes/song_select.tscn",
	"play": "res://scenes/gameplay.tscn",
	"results": "res://scenes/results.tscn",
	"setup": "res://scenes/setup.tscn",
	"settings": "res://scenes/settings.tscn",
	"shop": "res://scenes/shop.tscn",
}

var selected_song = null ## SongLibrary.SongEntry
var selected_difficulty: Dictionary = {}
var last_results: Dictionary = {}
var last_chart: Chart = null
var autoplay: bool = false
var _sfx: Dictionary = {}


func _ready() -> void:
	for name in ["don", "ka", "pop", "tick", "tick_accent", "ui_move", "ui_select", "clear", "fail", "unlock"]:
		var path := "res://assets/sfx/%s.wav" % name
		if ResourceLoader.exists(path):
			var p := AudioStreamPlayer.new()
			p.stream = load(path)
			p.max_polyphony = 8
			p.bus = "Master"
			add_child(p)
			_sfx[name] = p
	_apply_sfx_volume()
	Settings.changed.connect(func(k): if k.begins_with("volume") or k == "*": _apply_sfx_volume())
	call_deferred("_apply_display")


func _apply_display() -> void:
	Settings.apply_display()


func _apply_sfx_volume() -> void:
	var v := linear_to_db(clampf(float(Settings.get_value("volume_sfx")), 0.0001, 1.0))
	for k in _sfx:
		_sfx[k].volume_db = v


func play_sfx(name: String, pitch: float = 1.0) -> void:
	if _sfx.has(name):
		var p: AudioStreamPlayer = _sfx[name]
		p.pitch_scale = pitch
		p.play()


func goto(scene: String) -> void:
	var path: String = SCENES.get(scene, scene)
	get_tree().call_deferred("change_scene_to_file", path)


func start_song(song, difficulty: Dictionary, p_autoplay: bool = false) -> void:
	selected_song = song
	selected_difficulty = difficulty
	autoplay = p_autoplay
	goto("play")


static func format_ms(ms: float) -> String:
	var s := int(ms / 1000.0)
	return "%d:%02d" % [s / 60, s % 60]
