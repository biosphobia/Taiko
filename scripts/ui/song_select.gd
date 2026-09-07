extends Control

var _list: ItemList
var _info_title: Label
var _info_meta: Label
var _diff_box: VBoxContainer
var _preview: AudioStreamPlayer
var _current: SongLibrary.SongEntry = null
var _message: Label
var _file_dialog: FileDialog
var _dir_dialog: FileDialog
var _autoplay_check: CheckButton


func _ready() -> void:
	UiTheme.fit_scene(self)
	Hardware.gameplay_mode = false
	Hardware.menu_navigation = true
	var t := UiTheme.theme()
	UiTheme.make_background(self)
	var title := UiTheme.make_title("Select a song")
	title.position = Vector2(60, 30)
	add_child(title)

	_list = ItemList.new()
	_list.position = Vector2(60, 110)
	_list.size = Vector2(640, 640)
	_list.add_theme_font_size_override("font_size", 24)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i): _focus_difficulties())
	add_child(_list)

	var panel := UiTheme.make_panel(self, Rect2(740, 110, 800, 640))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	_info_title = UiTheme.make_label("", 34, t.accent)
	_info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_info_title)
	_info_meta = UiTheme.make_label("", 20)
	_info_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_info_meta)
	vb.add_child(UiTheme.make_label("Difficulties", 22, Color(1, 1, 1, 0.7)))
	_diff_box = VBoxContainer.new()
	_diff_box.add_theme_constant_override("separation", 8)
	vb.add_child(_diff_box)

	var hb := HBoxContainer.new()
	hb.position = Vector2(60, 770)
	hb.add_theme_constant_override("separation", 12)
	add_child(hb)
	var b_import := UiTheme.make_button("Import .osz / .osu", 22)
	b_import.custom_minimum_size = Vector2(260, 50)
	b_import.pressed.connect(func(): _file_dialog.popup_centered_ratio(0.8))
	hb.add_child(b_import)
	var b_folder := UiTheme.make_button("Import folder", 22)
	b_folder.custom_minimum_size = Vector2(200, 50)
	b_folder.pressed.connect(func(): _dir_dialog.popup_centered_ratio(0.8))
	hb.add_child(b_folder)
	var b_open := UiTheme.make_button("Open songs folder", 22)
	b_open.custom_minimum_size = Vector2(240, 50)
	b_open.pressed.connect(func(): OS.shell_open(SongLibrary.songs_dir_global()))
	hb.add_child(b_open)
	var b_rescan := UiTheme.make_button("Rescan", 22)
	b_rescan.custom_minimum_size = Vector2(140, 50)
	b_rescan.pressed.connect(func():
		SongLibrary.rescan()
		_fill_list())
	hb.add_child(b_rescan)
	_autoplay_check = CheckButton.new()
	_autoplay_check.text = "Autoplay (demo)"
	_autoplay_check.add_theme_font_size_override("font_size", 20)
	hb.add_child(_autoplay_check)
	var b_back := UiTheme.make_button("Back", 22)
	b_back.custom_minimum_size = Vector2(140, 50)
	b_back.pressed.connect(func(): Game.goto("menu"))
	hb.add_child(b_back)

	_message = UiTheme.make_label("Drop .osz files here or use Import. Songs folder: " + SongLibrary.songs_dir_global(), 16, Color(1, 1, 1, 0.6))
	_message.position = Vector2(60, 835)
	_message.size = Vector2(1480, 40)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)

	_preview = AudioStreamPlayer.new()
	_preview.bus = "Master"
	add_child(_preview)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.filters = PackedStringArray(["*.osz ; osu! beatmap package", "*.osu ; osu! chart", "*.zip ; zip archive"])
	_file_dialog.use_native_dialog = true
	_file_dialog.title = "Import osu!taiko maps"
	_file_dialog.files_selected.connect(_import_files)
	add_child(_file_dialog)
	_dir_dialog = FileDialog.new()
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.use_native_dialog = true
	_dir_dialog.title = "Import a folder containing .osu files"
	_dir_dialog.dir_selected.connect(func(d): _import_files(PackedStringArray([d])))
	add_child(_dir_dialog)
	get_window().files_dropped.connect(_import_files)

	_fill_list()
	_list.grab_focus()


func _exit_tree() -> void:
	if get_window().files_dropped.is_connected(_import_files):
		get_window().files_dropped.disconnect(_import_files)


func _import_files(files: PackedStringArray) -> void:
	var added := 0
	var msgs := []
	for f in files:
		var r := SongLibrary.import_path(f)
		added += int(r.added)
		if not r.ok:
			msgs.append("%s: %s" % [f.get_file(), r.message])
	_fill_list()
	if added > 0:
		Game.play_sfx("unlock")
	_message.text = "Imported %d chart(s). %s" % [added, "  ".join(msgs)]


func _fill_list() -> void:
	_list.clear()
	for s in SongLibrary.songs:
		var label := "%s - %s" % [s.artist, s.title]
		if s.bundled:
			label += "  (bundled)"
		_list.add_item(label)
	if _list.item_count > 0:
		var idx := 0
		if Game.selected_song != null:
			for i in range(SongLibrary.songs.size()):
				if SongLibrary.songs[i].key == Game.selected_song.key:
					idx = i
		_list.select(idx)
		_on_selected(idx)


func _on_selected(idx: int) -> void:
	if idx < 0 or idx >= SongLibrary.songs.size():
		return
	_current = SongLibrary.songs[idx]
	_info_title.text = "%s\n%s" % [_current.title, _current.artist]
	var meta := "Mapped by %s" % _current.creator
	_info_meta.text = meta
	for c in _diff_box.get_children():
		c.queue_free()
	for d in _current.difficulties:
		var best: Dictionary = Profile.best_for(str(d.key))
		var txt := "%s   (OD %.1f)" % [d.version, float(d.od)]
		if int(d.mode) != 1:
			txt += "  [converted]"
		if not best.is_empty():
			txt += "   best: %d  %s  %.2f%%%s" % [int(best.score), str(best.rank), float(best.accuracy) * 100.0, "  FC" if bool(best.get("full_combo", false)) else ""]
		var b := UiTheme.make_button(txt, 22)
		b.custom_minimum_size = Vector2(740, 52)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			Game.play_sfx("ui_select")
			_preview.stop()
			Game.start_song(_current, d, _autoplay_check.button_pressed))
		_diff_box.add_child(b)
	_start_preview()


func _focus_difficulties() -> void:
	if _diff_box.get_child_count() > 0:
		_diff_box.get_child(0).grab_focus()


func _start_preview() -> void:
	_preview.stop()
	if _current == null or _current.audio == "":
		return
	var stream := SongLibrary.load_audio(_current.audio)
	if stream == null:
		return
	_preview.stream = stream
	_preview.volume_db = linear_to_db(clampf(float(Settings.get_value("volume_music")) * 0.7, 0.0001, 1.0))
	var from := maxf(0.0, _current.preview_time / 1000.0)
	if from >= stream.get_length():
		from = 0.0
	_preview.play(from)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		if _list.has_focus():
			Game.goto("menu")
		else:
			_list.grab_focus()
		get_viewport().set_input_as_handled()
