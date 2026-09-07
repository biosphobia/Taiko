extends Control

var _hist: Control
var _errors := PackedFloat32Array()
var _windows := {}


func _ready() -> void:
	UiTheme.fit_scene(self)
	Hardware.gameplay_mode = false
	Hardware.menu_navigation = true
	var t := UiTheme.theme()
	UiTheme.make_background(self)
	var r: Dictionary = Game.last_results
	if r.is_empty():
		Game.goto("menu")
		return
	var title := UiTheme.make_title("%s - %s  [%s]" % [str(r.artist), str(r.title), str(r.version)])
	title.add_theme_font_size_override("font_size", 36)
	title.position = Vector2(60, 30)
	add_child(title)
	var status := UiTheme.make_label("CLEAR!" if bool(r.cleared) else "FAILED", 40, Color(1, 0.9, 0.4) if bool(r.cleared) else Color(0.7, 0.7, 0.8))
	status.position = Vector2(60, 90)
	add_child(status)
	if bool(r.full_combo) and int(r.greats) + int(r.oks) > 0:
		var fc := UiTheme.make_label("FULL COMBO", 30, Color(1, 0.7, 0.2))
		fc.position = Vector2(300, 98)
		add_child(fc)

	var rank := UiTheme.make_label(str(r.rank), 200, t.accent, HORIZONTAL_ALIGNMENT_CENTER)
	rank.position = Vector2(1150, 120)
	rank.size = Vector2(380, 240)
	rank.add_theme_constant_override("outline_size", 12)
	rank.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	add_child(rank)
	var acc := UiTheme.make_label("%.2f%%" % (float(r.accuracy) * 100.0), 48, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	acc.position = Vector2(1150, 360)
	acc.size = Vector2(380, 60)
	add_child(acc)

	var panel := UiTheme.make_panel(self, Rect2(60, 160, 1040, 330))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)
	var rows := [
		["Score", str(r.score)], ["Max combo", "%d / %d" % [int(r.max_combo), int(r.total_notes)]],
		["GREAT", str(r.greats)], ["OK", str(r.oks)],
		["MISS", str(r.misses)], ["Roll hits", str(r.roll_hits)],
		["Balloons popped", str(r.balloon_pops)], ["Big notes (both hands)", str(r.big_both)],
	]
	for row in rows:
		grid.add_child(UiTheme.make_label(row[0], 24, Color(1, 1, 1, 0.7)))
		grid.add_child(UiTheme.make_label(row[1], 28))

	# timing diagnostics
	var st: Dictionary = r.errors
	var diag := UiTheme.make_panel(self, Rect2(60, 510, 1040, 230))
	var dv := VBoxContainer.new()
	diag.add_child(dv)
	dv.add_child(UiTheme.make_label("Timing accuracy", 26, t.accent))
	var txt := "Average error %+.1f ms (std %.1f ms)   early %d / late %d   from %d hits" % [float(st.mean), float(st.std), int(st.early), int(st.late), int(st.count)]
	dv.add_child(UiTheme.make_label(txt, 22))
	if Game.last_chart != null:
		for n in Game.last_chart.notes:
			pass
	_windows = Settings.judge_windows(float(Game.last_chart.od) if Game.last_chart else 5.0)
	_hist = Control.new()
	_hist.custom_minimum_size = Vector2(980, 80)
	_hist.draw.connect(_draw_hist)
	dv.add_child(_hist)
	if Game.last_chart != null:
		_collect_errors()
	if int(st.count) >= 8 and absf(float(st.mean)) >= 4.0:
		var suggested := float(Settings.get_value("input_offset_ms")) - float(st.mean)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		dv.add_child(hb)
		hb.add_child(UiTheme.make_label("Your hits were %s on average. Suggested input offset: %+.0f ms" % ["late" if float(st.mean) > 0 else "early", suggested], 20, Color(1, 0.85, 0.5)))
		var apply := UiTheme.make_button("Apply", 20)
		apply.custom_minimum_size = Vector2(120, 40)
		apply.pressed.connect(func():
			Settings.set_value("input_offset_ms", snappedf(suggested, 1.0))
			apply.text = "Applied"
			apply.disabled = true)
		hb.add_child(apply)

	# rewards
	var rw: Dictionary = r.get("reward", {})
	var reward_text := "+%d coins" % int(rw.get("coins_earned", 0))
	if bool(rw.get("new_best", false)):
		reward_text += "   NEW BEST!"
	for u in rw.get("new_unlocks", []):
		reward_text += "   Unlocked: %s" % Profile.item(str(u)).get("name", u)
	var rl := UiTheme.make_label(reward_text, 26, Color(1, 0.9, 0.5))
	rl.position = Vector2(60, 760)
	add_child(rl)

	var hb2 := HBoxContainer.new()
	hb2.position = Vector2(60, 810)
	hb2.add_theme_constant_override("separation", 16)
	add_child(hb2)
	var b_retry := UiTheme.make_button("Retry")
	b_retry.pressed.connect(func(): Game.goto("play"))
	hb2.add_child(b_retry)
	var b_songs := UiTheme.make_button("Song select")
	b_songs.pressed.connect(func(): Game.goto("songs"))
	hb2.add_child(b_songs)
	var b_menu := UiTheme.make_button("Main menu")
	b_menu.pressed.connect(func(): Game.goto("menu"))
	hb2.add_child(b_menu)
	b_songs.grab_focus()


func _collect_errors() -> void:
	_errors = PackedFloat32Array()
	for n in Game.last_chart.notes:
		if n.is_regular() and n.judged and n.judgement != Judge.Result.MISS:
			_errors.append(n.first_hit_time - n.time)
	_hist.queue_redraw()


func _draw_hist() -> void:
	var w := _hist.size.x
	var h := _hist.size.y
	var miss := float(_windows.get("miss", 95.0))
	var bins := 41
	var counts := PackedInt32Array()
	counts.resize(bins)
	var maxc := 1
	for e in _errors:
		var b := int((clampf(e, -miss, miss) + miss) / (2.0 * miss) * (bins - 1) + 0.5)
		counts[b] += 1
		maxc = maxi(maxc, counts[b])
	var bw := w / bins
	for i in range(bins):
		var center := -miss + (2.0 * miss) * i / (bins - 1)
		var col := Color(0.4, 0.9, 1.0) if absf(center) <= float(_windows.get("great", 35.0)) else (Color(0.9, 0.85, 0.3) if absf(center) <= float(_windows.get("ok", 80.0)) else Color(0.9, 0.3, 0.3))
		var bh := h * 0.9 * counts[i] / maxc
		_hist.draw_rect(Rect2(i * bw, h - bh, bw - 1.0, bh), col)
	_hist.draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Color.WHITE, 2.0)
	_hist.draw_string(UiTheme.font(), Vector2(4, 16), "-%d ms (early)" % int(miss), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	_hist.draw_string(UiTheme.font(), Vector2(w - 110, 16), "+%d ms (late)" % int(miss), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		Game.goto("songs")
