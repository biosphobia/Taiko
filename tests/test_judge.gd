extends RefCounted

const RUN := preload("res://tests/run_tests.gd")


func _chart(specs: Array) -> Chart:
	var c := Chart.new()
	var tp := Chart.TimingPoint.new()
	tp.time = 0.0
	tp.beat_length = 500.0
	c.timing_points.append(tp)
	for s in specs:
		var n := Chart.Note.new()
		n.time = s[0]
		n.type = s[1]
		if s.size() > 2:
			n.end_time = s[2]
		if s.size() > 3:
			n.hits_required = s[3]
		c.notes.append(n)
	c.sort_notes()
	return c


func test_windows() -> void:
	var w := Judge.windows_from_od(5.0)
	RUN.check(is_equal_approx(w.great, 35.0) and is_equal_approx(w.ok, 80.0) and is_equal_approx(w.miss, 95.0), "OD5 windows")
	w = Judge.windows_from_od(10.0)
	RUN.check(is_equal_approx(w.great, 20.0) and is_equal_approx(w.ok, 50.0) and is_equal_approx(w.miss, 80.0), "OD10 windows")
	w = Judge.windows_from_od(0.0)
	RUN.check(is_equal_approx(w.great, 50.0) and is_equal_approx(w.ok, 120.0), "OD0 windows")


func test_basic_judgements() -> void:
	var c := _chart([[1000.0, Chart.NoteType.DON], [1500.0, Chart.NoteType.KA], [2000.0, Chart.NoteType.DON], [2500.0, Chart.NoteType.KA]])
	var j := Judge.new()
	j.setup(c, Judge.windows_from_od(5.0))
	var ev := j.process_hit(Judge.Hand.LEFT, Judge.HitKind.DON, 1010.0)
	RUN.check(ev.type == "judge" and ev.result == Judge.Result.GREAT and is_equal_approx(ev.error, 10.0), "great +10ms")
	ev = j.process_hit(Judge.Hand.RIGHT, Judge.HitKind.KA, 1440.0)
	RUN.check(ev.result == Judge.Result.OK and is_equal_approx(ev.error, -60.0), "ok -60ms")
	ev = j.process_hit(Judge.Hand.LEFT, Judge.HitKind.KA, 2005.0)
	RUN.check(ev.result == Judge.Result.MISS, "wrong color = miss")
	# too early hit is ignored
	ev = j.process_hit(Judge.Hand.LEFT, Judge.HitKind.KA, 2300.0)
	RUN.check(ev.type == "none", "too early ignored")
	ev = j.process_hit(Judge.Hand.LEFT, Judge.HitKind.KA, 2590.0)
	RUN.check(ev.result == Judge.Result.MISS, "inside miss window but outside ok = miss")
	RUN.check(j.greats == 1 and j.oks == 1 and j.misses == 2, "counts %d %d %d" % [j.greats, j.oks, j.misses])
	RUN.check(j.max_combo == 2 and j.combo == 0, "combo")
	RUN.check(j.is_finished(3000.0), "finished")
	RUN.check(is_equal_approx(j.accuracy(), (1.0 + 0.5) / 4.0), "accuracy")


func test_miss_by_time() -> void:
	var c := _chart([[1000.0, Chart.NoteType.DON], [1500.0, Chart.NoteType.DON]])
	var j := Judge.new()
	j.setup(c, Judge.windows_from_od(5.0))
	j.update(1094.0)
	RUN.check(j.misses == 0, "not yet missed")
	j.update(1096.0)
	RUN.check(j.misses == 1, "missed after window")
	# hit for second note still works
	var ev := j.process_hit(Judge.Hand.LEFT, Judge.HitKind.DON, 1500.0)
	RUN.check(ev.result == Judge.Result.GREAT, "second note judged")
	# a very late hit after missing everything -> none
	j.update(5000.0)
	RUN.check(j.process_hit(Judge.Hand.LEFT, Judge.HitKind.DON, 5000.0).type == "none", "no notes left")


func test_big_note_both_hands() -> void:
	var c := _chart([[1000.0, Chart.NoteType.DON_BIG], [2000.0, Chart.NoteType.KA_BIG], [3000.0, Chart.NoteType.DON]])
	var j := Judge.new()
	j.setup(c, Judge.windows_from_od(5.0))
	var ev := j.process_hit(Judge.Hand.LEFT, Judge.HitKind.DON, 1000.0)
	RUN.check(ev.result == Judge.Result.GREAT, "big first hit")
	ev = j.process_hit(Judge.Hand.RIGHT, Judge.HitKind.DON, 1020.0)
	RUN.check(ev.type == "big_both", "second hand completes big note")
	RUN.check(j.score == 2 * Judge.SCORE_GREAT, "double score")
	# same hand twice does not count as both
	ev = j.process_hit(Judge.Hand.LEFT, Judge.HitKind.KA, 2000.0)
	ev = j.process_hit(Judge.Hand.LEFT, Judge.HitKind.KA, 2010.0)
	RUN.check(ev.type == "none", "same hand ignored")
	# too late second hand
	ev = j.process_hit(Judge.Hand.RIGHT, Judge.HitKind.KA, 2100.0)
	RUN.check(ev.type == "none", "second hand outside window ignored (and not applied to the next note)")
	RUN.check(j.big_both == 1 and j.combo == 2, "big both count")


func test_roll_and_balloon() -> void:
	var c := _chart([[1000.0, Chart.NoteType.ROLL, 2000.0], [3000.0, Chart.NoteType.BALLOON, 4000.0, 3], [5000.0, Chart.NoteType.DON]])
	var j := Judge.new()
	j.setup(c, Judge.windows_from_od(5.0))
	RUN.check(j.process_hit(0, 0, 800.0).type == "none", "before roll ignored")
	var n := 0
	for t in [1000.0, 1100.0, 1200.0, 1900.0, 2050.0]:
		if j.process_hit(0, 1, t).type == "roll_hit":
			n += 1
	RUN.check(n == 5, "roll hits %d" % n)
	RUN.check(j.process_hit(0, 0, 2200.0).type == "none", "after roll window ignored")
	j.update(2500.0)
	RUN.check(j.drain_events().size() >= 6, "roll end event")
	RUN.check(j.process_hit(0, 1, 3000.0).type == "none", "ka does not hit balloon")
	RUN.check(j.process_hit(0, 0, 3000.0).type == "balloon_hit", "balloon hit 1")
	RUN.check(j.process_hit(1, 0, 3100.0).type == "balloon_hit", "balloon hit 2")
	RUN.check(j.process_hit(0, 0, 3200.0).type == "balloon_pop", "balloon pop")
	RUN.check(j.process_hit(0, 0, 3300.0).type == "none", "popped balloon ignores hits (next note too early)")
	RUN.check(j.process_hit(0, 0, 5000.0).result == Judge.Result.GREAT, "note after balloon")
	RUN.check(j.combo == 1 and j.misses == 0, "rolls/balloons don't affect combo")
	RUN.check(j.balloon_pops == 1 and j.roll_hits == 5, "stats")


func test_gauge_and_rank() -> void:
	var specs := []
	for i in range(100):
		specs.append([1000.0 + i * 200.0, Chart.NoteType.DON])
	var c := _chart(specs)
	var j := Judge.new()
	j.setup(c, Judge.windows_from_od(5.0))
	for i in range(100):
		j.process_hit(0, 0, 1000.0 + i * 200.0 + (i % 5))
	RUN.check(j.cleared() and j.rank() == "SS" and j.results()["full_combo"], "all great clears with SS")
	var st := j.error_stats()
	RUN.check(st.count == 100 and st.mean > 1.5 and st.mean < 2.5, "error stats mean %f" % st.mean)
	j.setup(c, Judge.windows_from_od(5.0))
	for i in range(100):
		if i % 4 == 0:
			j.update(1000.0 + i * 200.0 + 100.0)
		else:
			j.process_hit(0, 0, 1000.0 + i * 200.0)
	RUN.check(j.misses == 25 and j.greats == 75, "25% missed")
	RUN.check(is_equal_approx(j.accuracy(), 0.75), "accuracy 75%%")
	RUN.check(j.rank() == "C", "rank C")
