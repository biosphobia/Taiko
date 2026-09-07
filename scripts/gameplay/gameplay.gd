extends Control
## Gameplay scene: runs a chart with the AudioClock, feeds hits into the Judge and renders the HUD.

const LEAD_IN_MIN := 2000.0

var chart: Chart
var judge := Judge.new()
var clock: AudioClock
var lane: LaneRenderer
var drum: DrumWidget
var gauge: HudGauge
var error_bar: ErrorBar
var monitor: DrumMonitor
var score_label: Label
var combo_label: Label
var acc_label: Label
var info_label: Label
var status_label: Label
var progress: ProgressBar
var pause_panel: PanelContainer
var flash_rect: ColorRect
var finished := false
var _finish_at := -1.0
var paused := false
var _input_offset := 0.0
var _auto_next_roll_hit := 0.0
var _auto_hand := 0
var _bg: ColorRect
var _bg_texture: TextureRect


func _ready() -> void:
	UiTheme.fit_scene(self)
	Hardware.gameplay_mode = true
	var diff: Dictionary = Game.selected_difficulty
	if diff.is_empty() and not OS.has_environment("TAIKO_TEST"):
		Game.goto("songs")
		return
	if not diff.is_empty():
		chart = OsuParser.parse_file(str(diff.path))
	if chart == null:
		if OS.has_environment("TAIKO_TEST"):
			return
		push_warning("Could not load chart")
		Game.goto("songs")
		return
	_build_ui()
	_start_chart()


func load_chart_for_test(p_chart: Chart, stream: AudioStream) -> void:
	chart = p_chart
	_build_ui()
	_start_chart(stream)


func _start_chart(stream: AudioStream = null) -> void:
	_input_offset = float(Settings.get_value("input_offset_ms"))
	judge.setup(chart, Settings.judge_windows(chart.od))
	error_bar.windows = judge.windows
	lane.chart = chart
	lane.bar_lines = chart.bar_lines()
	lane.scroll_speed = float(Settings.get_value("scroll_speed"))
	clock = AudioClock.new()
	add_child(clock)
	if stream == null:
		stream = SongLibrary.load_audio(chart.audio_path)
	if stream == null:
		push_warning("Audio not found: %s (playing silent)" % chart.audio_path)
	var lead_in := maxf(LEAD_IN_MIN, 2500.0 - chart.first_note_time())
	clock.setup(stream, lead_in)
	clock.start()
	Hardware.drum_hit.connect(_on_drum_hit)
	Hardware.move_button.connect(_on_move_button)
	info_label.text = "%s - %s  [%s]" % [chart.display_artist(), chart.display_title(), chart.version]
	if chart.converted:
		info_label.text += "  (converted)"


func _exit_tree() -> void:
	Hardware.gameplay_mode = false
	if Hardware.drum_hit.is_connected(_on_drum_hit):
		Hardware.drum_hit.disconnect(_on_drum_hit)
	if Hardware.move_button.is_connected(_on_move_button):
		Hardware.move_button.disconnect(_on_move_button)


func _build_ui() -> void:
	var t := UiTheme.theme()
	_bg = UiTheme.make_background(self)
	if chart != null and chart.background_path != "":
		var tex := SongLibrary.load_texture(chart.background_path)
		if tex:
			_bg_texture = TextureRect.new()
			_bg_texture.texture = tex
			_bg_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
			_bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_bg_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			_bg_texture.modulate = Color(0.45, 0.45, 0.45)
			_bg_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_bg_texture)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_rect)

	lane = LaneRenderer.new()
	lane.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(lane)

	# drum + combo on the left
	var drum_bg := ColorRect.new()
	drum_bg.color = Color(t.panel.r, t.panel.g, t.panel.b, 0.9)
	drum_bg.position = Vector2(0, LaneRenderer.LANE_Y - LaneRenderer.LANE_H * 0.5 - 2)
	drum_bg.size = Vector2(250, LaneRenderer.LANE_H + 4)
	drum_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drum_bg)
	drum = DrumWidget.new()
	drum.position = Vector2(20, LaneRenderer.LANE_Y - 80)
	drum.size = Vector2(160, 160)
	add_child(drum)
	combo_label = UiTheme.make_label("0", 60, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	combo_label.position = Vector2(0, LaneRenderer.LANE_Y + LaneRenderer.LANE_H * 0.5 + 6)
	combo_label.size = Vector2(250, 70)
	combo_label.add_theme_constant_override("outline_size", 8)
	combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(combo_label)
	var combo_caption := UiTheme.make_label("COMBO", 18, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	combo_caption.position = Vector2(0, LaneRenderer.LANE_Y + LaneRenderer.LANE_H * 0.5 + 70)
	combo_caption.size = Vector2(250, 24)
	add_child(combo_caption)

	# top bar
	info_label = UiTheme.make_label("", 26)
	info_label.position = Vector2(24, 16)
	info_label.size = Vector2(1000, 36)
	add_child(info_label)
	score_label = UiTheme.make_label("0", 44, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	score_label.position = Vector2(1100, 8)
	score_label.size = Vector2(476, 56)
	add_child(score_label)
	gauge = HudGauge.new()
	gauge.position = Vector2(1000, 70)
	gauge.size = Vector2(576, 34)
	add_child(gauge)
	acc_label = UiTheme.make_label("100.00%", 22, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_RIGHT)
	acc_label.position = Vector2(1100, 110)
	acc_label.size = Vector2(476, 30)
	add_child(acc_label)
	progress = ProgressBar.new()
	progress.position = Vector2(24, 60)
	progress.size = Vector2(700, 10)
	progress.show_percentage = false
	progress.max_value = 1.0
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(progress)

	# bottom
	error_bar = ErrorBar.new()
	error_bar.position = Vector2(500, 800)
	error_bar.size = Vector2(600, 40)
	error_bar.visible = bool(Settings.get_value("show_error_bar"))
	add_child(error_bar)
	status_label = UiTheme.make_label("", 18, Color(1, 1, 1, 0.7))
	status_label.position = Vector2(24, 850)
	status_label.size = Vector2(900, 30)
	add_child(status_label)
	monitor = DrumMonitor.new()
	monitor.position = Vector2(1350, 640)
	monitor.size = Vector2(226, 170)
	monitor.visible = bool(Settings.get_value("show_drum_monitor")) and Hardware.camera_running()
	add_child(monitor)

	# pause overlay
	pause_panel = UiTheme.make_panel(self, Rect2(600, 300, 400, 300))
	pause_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pause_panel.add_child(vb)
	vb.add_child(UiTheme.make_label("PAUSED", 36, t.accent, HORIZONTAL_ALIGNMENT_CENTER))
	var b_resume := UiTheme.make_button("Resume")
	b_resume.pressed.connect(_toggle_pause)
	vb.add_child(b_resume)
	var b_retry := UiTheme.make_button("Retry")
	b_retry.pressed.connect(func(): Game.goto("play"))
	vb.add_child(b_retry)
	var b_quit := UiTheme.make_button("Quit to song select")
	b_quit.pressed.connect(func(): Game.goto("songs"))
	vb.add_child(b_quit)


func _on_move_button(_slot: int, _buttons: int, pressed: int, _released: int) -> void:
	if pressed & Hardware.BTN_START and not finished:
		_toggle_pause()


func _unhandled_input(event: InputEvent) -> void:
	if finished:
		return
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	paused = not paused
	pause_panel.visible = paused
	Hardware.menu_navigation = paused
	if paused:
		clock.pause()
		pause_panel.get_child(0).get_child(1).grab_focus()
	else:
		clock.resume()


func _on_drum_hit(hand: int, kind: int, t_usec: int, strength: float, source: String) -> void:
	if finished or paused or chart == null or clock == null:
		return
	Game.play_sfx("don" if kind == Hardware.Kind.DON else "ka")
	drum.flash(hand, kind)
	lane.flash_target(kind)
	var t := clock.song_time_at(t_usec) + _input_offset
	judge.process_hit(hand, kind, t)


func _autoplay(now: float) -> void:
	for n in chart.notes:
		if n.judged and not (n.is_roll() and not n.finished):
			continue
		if n.time > now:
			break
		if n.is_regular():
			_auto_hand = 1 - _auto_hand
			var kind := Hardware.Kind.DON if n.is_don() else Hardware.Kind.KA
			judge.process_hit(_auto_hand, kind, n.time)
			Game.play_sfx("don" if kind == 0 else "ka")
			drum.flash(_auto_hand, kind)
			if n.is_big():
				judge.process_hit(1 - _auto_hand, kind, n.time + 5.0)
		elif now <= n.end_time and now >= _auto_next_roll_hit:
			_auto_hand = 1 - _auto_hand
			judge.process_hit(_auto_hand, Hardware.Kind.DON, now)
			Game.play_sfx("don")
			drum.flash(_auto_hand, 0)
			_auto_next_roll_hit = now + 90.0
		if not n.is_regular():
			break


func _process(delta: float) -> void:
	if chart == null or clock == null:
		return
	var now := clock.now_ms()
	var jt := now + _input_offset # judged time: same clock the hits are converted with
	lane.now_ms = now
	lane.kiai = chart.kiai_at(now)
	if not paused and not finished:
		if Game.autoplay:
			_autoplay(jt)
		judge.update(jt)
	for ev in judge.drain_events():
		_handle_event(ev)
	score_label.text = str(judge.score)
	combo_label.text = str(judge.combo)
	acc_label.text = "%.2f%%" % (judge.accuracy() * 100.0)
	gauge.value = judge.gauge
	var total := maxf(1.0, chart.last_time())
	progress.value = clampf(now / total, 0.0, 1.0)
	var st := "Offset %+.0f ms" % _input_offset
	if Hardware.hw != null:
		st += "   " + Hardware.status_text()
	if bool(Settings.get_value("show_fps")):
		st += "   %d fps" % Engine.get_frames_per_second()
	if clock != null and clock.audio_started:
		st += "   drift %+.1f ms" % clock.drift_ms
	status_label.text = st
	flash_rect.color.a = maxf(0.0, flash_rect.color.a - delta * 3.0)
	if not finished and not paused:
		var done := judge.is_finished(jt) and now > chart.last_time() + 1200.0
		if done or (clock.audio_finished() and now > chart.last_time()):
			finished = true
			_finish_at = now + 1200.0
	if finished and _finish_at >= 0.0 and now >= _finish_at:
		_finish_at = -1.0
		_finish()


func _handle_event(ev: Dictionary) -> void:
	match str(ev.type):
		"judge":
			var note: Chart.Note = ev.note
			match int(ev.result):
				Judge.Result.GREAT:
					lane.add_judgement("GREAT", Color(1.0, 0.85, 0.3))
					lane.add_flying(note, Judge.Result.GREAT)
					error_bar.add_error(float(ev.error))
				Judge.Result.OK:
					lane.add_judgement("OK", Color(0.9, 0.9, 0.9))
					lane.add_flying(note, Judge.Result.OK)
					error_bar.add_error(float(ev.error))
				Judge.Result.MISS:
					lane.add_judgement("MISS", Color(0.5, 0.6, 1.0))
		"big_both":
			flash_rect.color = Color(1, 1, 1, 0.25)
		"balloon_pop":
			Game.play_sfx("pop")
			flash_rect.color = Color(1, 0.8, 0.4, 0.3)
		"roll_end":
			pass


func _finish() -> void:
	Hardware.gameplay_mode = false
	var r := judge.results()
	r["title"] = chart.display_title()
	r["artist"] = chart.display_artist()
	r["version"] = chart.version
	r["total_notes"] = chart.regular_note_count()
	var diff: Dictionary = Game.selected_difficulty
	var key: String = str(diff.get("key", chart.source_path))
	var bundled: bool = Game.selected_song != null and Game.selected_song.bundled
	if not Game.autoplay:
		r["reward"] = Profile.record_result(key, chart.version, bundled, r)
	else:
		r["reward"] = {"coins_earned": 0, "new_best": false, "new_unlocks": [], "achievements": []}
	Game.last_results = r
	Game.last_chart = chart
	Game.play_sfx("clear" if bool(r.cleared) else "fail")
	if OS.has_environment("TAIKO_TEST"):
		return
	Game.goto("results")
