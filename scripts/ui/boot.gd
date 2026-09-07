extends Control
## First scene: waits one frame for autoloads, then goes to the main menu (or setup on first run).


func _ready() -> void:
	var l := Label.new()
	l.text = "TaikoMove"
	l.set_anchors_preset(Control.PRESET_CENTER)
	add_child(l)
	await get_tree().process_frame
	if OS.has_environment("TAIKO_TEST"):
		return
	if not bool(Settings.get_value("setup_done")) and Hardware.hw != null:
		Game.goto("setup")
	else:
		Game.goto("menu")
