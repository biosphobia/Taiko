extends Node
## Headless end-to-end test:  TAIKO_TEST=1 TAIKO_HW_HEADLESS=1 godot --headless --path . res://tests/smoke.tscn
## 1. Instantiates every UI scene to catch script errors.
## 2. Plays a bundled chart through the real pipeline (native extension -> Hardware -> Judge) using
##    virtual controllers fed with synthetic IMU strokes timed exactly on the notes, then checks the results.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		printerr("    check failed: " + msg)
		failures += 1


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("autoloads ready; hw available: %s" % str(Hardware.hw != null))
	check(Hardware.hw != null, "TaikoHW extension loaded")
	# --- scenes
	Game.last_results = {"score": 12345, "max_combo": 10, "greats": 8, "oks": 1, "misses": 1, "roll_hits": 0, "balloon_pops": 0, "big_both": 0, "accuracy": 0.85, "gauge": 0.9, "cleared": true, "rank": "B", "errors": {"mean": 12.0, "std": 8.0, "count": 9, "early": 2, "late": 7}, "full_combo": false, "title": "T", "artist": "A", "version": "V", "total_notes": 10, "reward": {"coins_earned": 10, "new_best": true, "new_unlocks": [], "achievements": []}}
	Game.last_chart = OsuParser.parse_file("res://songs/first_beat/TaikoMove - First Beat (TaikoMove) [Normal].osu")
	for scene in ["menu", "songs", "results", "settings", "shop", "setup"]:
		var packed: PackedScene = load(Game.SCENES[scene])
		var inst := packed.instantiate()
		get_tree().root.add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		if scene == "setup":
			for s in range(1, 7):
				inst._go(s)
				await get_tree().process_frame
		if scene == "shop":
			for c in ["drum", "notes", "theme", "title", "ach"]:
				inst._category = c
				inst._fill()
				await get_tree().process_frame
		inst.queue_free()
		await get_tree().process_frame
		print("  scene ok: " + scene)
	# --- gameplay with virtual controllers
	await _gameplay_test()
	print("scene_smoke: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Generates ImuSamples for a down stroke whose peak lands exactly at peak_usec (see native tests).
func _stroke_samples(peak_usec: int, peak_rad_s: float) -> Array:
	var dt := 5750
	var n := 16 # samples in the down stroke; peak at index n/2
	var out := []
	var start := peak_usec - (n / 2) * dt
	for i in range(n):
		var ph := float(i) / float(n)
		var w := -peak_rad_s * sin(ph * PI)
		out.append([start + i * dt, Vector3(0, 0.3 * absf(w) / peak_rad_s, 1.0), Vector3(w, 0, 0)])
	for i in range(n):
		var ph := float(i) / float(n)
		var w := 0.6 * peak_rad_s * sin(ph * PI)
		out.append([start + (n + i) * dt, Vector3(0, 0, 1.0), Vector3(w, 0, 0)])
	return out


func _gameplay_test() -> void:
	var hw = Hardware.hw
	if hw == null:
		return
	hw.debug_add_virtual(0)
	hw.debug_add_virtual(1)
	await get_tree().process_frame
	Hardware.refresh_hands()
	check(Hardware.slot_for_hand(0) == 0 and Hardware.slot_for_hand(1) == 1, "virtual slots mapped to hands")
	# camera drum zones: pretend a calibrated drum, controller 0 in the Don area, controller 1 on the rim
	Settings.set_value("tracking_mode", "camera", false)
	Settings.set_value("drum_calibrated", true, false)
	Settings.set_value("drum_center", Vector2(160, 150), false)
	Settings.set_value("drum_left", Vector2(80, 150), false)
	Settings.set_value("drum_right", Vector2(240, 150), false)
	Settings.set_value("drum_near", Vector2(160, 200), false)
	Settings.set_value("drum_far", Vector2(160, 100), false)
	Settings.set_value("input_offset_ms", 0.0, false)
	Settings.set_value("judge_preset", "od", false)
	check(Hardware.classify_hit(0, 0, true, Vector2(170, 150)) == 0, "center = don")
	check(Hardware.classify_hit(0, 0, true, Vector2(90, 150)) == 1, "rim = ka")
	check(Hardware.classify_hit(0, 0, true, Vector2(160, 190)) == 1, "near rim = ka")
	check(Hardware.classify_hit(0, 0, true, Vector2(160, 150 + 20)) == 0, "inside don ratio along the short axis = don")
	# rest samples so the gravity filter initializes
	var t0 := Time.get_ticks_usec()
	for slot in range(2):
		for i in range(60):
			hw.debug_inject(slot, t0 - 400000 + i * 5750, Vector3(0, 0, 1), Vector3(0, 0, 0))
	await get_tree().process_frame
	var chart := OsuParser.parse_file("res://songs/first_beat/TaikoMove - First Beat (TaikoMove) [Hard].osu")
	check(chart != null, "chart loaded")
	Game.selected_difficulty = {"path": chart.source_path, "version": chart.version, "od": chart.od, "mode": 1, "key": "test|Hard"}
	Game.selected_song = null
	Game.autoplay = false
	var packed: PackedScene = load(Game.SCENES["play"])
	var gp := packed.instantiate()
	get_tree().root.add_child(gp)
	await get_tree().process_frame
	check(gp.chart != null and gp.clock != null, "gameplay started")
	if gp.chart == null:
		return
	# Play every regular note with a synthetic stroke exactly on time; rolls/balloons get rapid hits.
	var idx := 0
	var notes: Array = gp.chart.notes
	var next_roll_hit := 0.0
	var hand_alt := 0
	var last_time: float = gp.chart.last_time()
	var start_ticks: int = Time.get_ticks_usec()
	var last_print := 0.0
	while true:
		await get_tree().process_frame
		var now: float = gp.clock.now_ms()
		if now - last_print > 10000.0:
			last_print = now
			print("  song time %.0f ms, judged greats %d misses %d" % [now, gp.judge.greats, gp.judge.misses])
		if now > last_time + 2500.0 or gp.finished:
			break
		if Time.get_ticks_usec() - start_ticks > 300 * 1000000:
			check(false, "gameplay test timed out")
			break
		while idx < notes.size() and notes[idx].time <= now + 8.0:
			var n: Chart.Note = notes[idx]
			if n.is_regular():
				var slot := 0 if n.is_don() else 1
				hw.debug_set_tracking(slot, true, Vector2(165, 150) if n.is_don() else Vector2(85, 150))
				var peak_ticks: int = gp.clock.ticks_at(n.time)
				for s in _stroke_samples(peak_ticks, 10.0):
					hw.debug_inject(slot, s[0], s[1], s[2])
				if n.is_big():
					var other := 1 - slot
					hw.debug_set_tracking(other, true, Vector2(165, 150) if n.is_don() else Vector2(235, 150))
					for s in _stroke_samples(peak_ticks + 8000, 10.0):
						hw.debug_inject(other, s[0], s[1], s[2])
				idx += 1
			else:
				if now >= n.end_time or now < n.time:
					if now >= n.end_time:
						idx += 1
					break
				if now >= next_roll_hit:
					hand_alt = 1 - hand_alt
					hw.debug_set_tracking(hand_alt, true, Vector2(165, 150))
					for s in _stroke_samples(gp.clock.ticks_at(now - 2.0), 10.0):
						hw.debug_inject(hand_alt, s[0], s[1], s[2])
					next_roll_hit = now + 100.0
				break
	# let the scene finish
	for i in range(200):
		await get_tree().process_frame
		if Game.last_results.has("greats") and Game.last_results.get("title", "") == "First Beat":
			break
	var r: Dictionary = Game.last_results
	check(r.get("title", "") == "First Beat", "results produced")
	if r.get("title", "") == "First Beat":
		var st: Dictionary = r.errors
		print("  results: greats %d oks %d misses %d  roll hits %d  pops %d  big_both %d  mean err %.2f std %.2f  score %d rank %s" % [r.greats, r.oks, r.misses, r.roll_hits, r.balloon_pops, r.big_both, st.mean, st.std, r.score, r.rank])
		check(int(r.misses) == 0, "no misses with exact strokes (misses=%d)" % int(r.misses))
		check(int(r.oks) == 0, "no OKs with exact strokes (oks=%d)" % int(r.oks))
		check(absf(float(st.mean)) < 4.0, "mean timing error below 4 ms (%.2f)" % float(st.mean))
		check(float(st.std) < 4.0, "timing jitter below 4 ms (%.2f)" % float(st.std))
		var big_count := 0
		for n in gp.chart.notes:
			if n.is_regular() and n.is_big():
				big_count += 1
		check(int(r.big_both) == big_count, "big notes completed with both hands (%d of %d)" % [int(r.big_both), big_count])
		check(bool(r.cleared) and str(r.rank) == "SS", "cleared with SS")
		check(int(r.roll_hits) > 5, "drumroll hits registered (%d)" % int(r.roll_hits))
		check(int(r.balloon_pops) >= 1, "balloon popped (%d)" % int(r.balloon_pops))
	gp.queue_free()
	await get_tree().process_frame
