class_name Judge
extends RefCounted
## Judgement, scoring and gauge logic for one play of a Chart. Pure logic, no nodes.
## Times are song times in milliseconds (already including the player's input offset).

enum Result { GREAT = 0, OK = 1, MISS = 2 }
enum Hand { LEFT = 0, RIGHT = 1, ANY = 2 }
enum HitKind { DON = 0, KA = 1 }

const SCORE_GREAT := 1000
const SCORE_OK := 500
const SCORE_ROLL := 100
const SCORE_ROLL_BIG := 300
const SCORE_BALLOON_HIT := 100
const SCORE_BALLOON_POP := 1500
const BIG_SECOND_HIT_WINDOW := 40.0 ## ms for the other hand to complete a big note
const CLEAR_GAUGE := 0.8

var chart: Chart
var windows := {"great": 35.0, "ok": 80.0, "miss": 95.0}
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var greats: int = 0
var oks: int = 0
var misses: int = 0
var roll_hits: int = 0
var balloon_hits: int = 0
var balloon_pops: int = 0
var big_both: int = 0
var gauge: float = 0.0
var errors := PackedFloat32Array() ## signed hit error (ms) for every judged regular note that was hit
var events: Array[Dictionary] = [] ## drained by the UI
var _next: int = 0
var _last_big: Chart.Note = null
var _gain_great := 0.02
var _gain_ok := 0.01
var _loss_miss := 0.03
var _total_regular := 0


static func windows_from_od(od: float) -> Dictionary:
	return {
		"great": OsuParser.difficulty_range(od, 50.0, 35.0, 20.0),
		"ok": OsuParser.difficulty_range(od, 120.0, 80.0, 50.0),
		"miss": OsuParser.difficulty_range(od, 135.0, 95.0, 80.0),
	}


static func windows_arcade() -> Dictionary:
	return {"great": 25.0, "ok": 75.0, "miss": 108.0}


static func windows_preset(preset: String, od: float) -> Dictionary:
	match preset:
		"arcade": return windows_arcade()
		"strict": return {"great": 20.0, "ok": 50.0, "miss": 70.0}
		"lenient": return {"great": 50.0, "ok": 120.0, "miss": 135.0}
		_: return windows_from_od(od)


func setup(p_chart: Chart, p_windows: Dictionary) -> void:
	chart = p_chart
	windows = p_windows.duplicate()
	chart.reset_runtime()
	score = 0
	combo = 0
	max_combo = 0
	greats = 0
	oks = 0
	misses = 0
	roll_hits = 0
	balloon_hits = 0
	balloon_pops = 0
	big_both = 0
	gauge = 0.0
	errors = PackedFloat32Array()
	events.clear()
	_next = 0
	_last_big = null
	_total_regular = maxi(1, chart.regular_note_count())
	# Reaching the clear line takes roughly 75% GREATs; a miss costs about 1.5 GREATs.
	_gain_great = 1.0 / (_total_regular * 0.75)
	_gain_ok = _gain_great * 0.5
	_loss_miss = _gain_great * 1.5


func drain_events() -> Array[Dictionary]:
	var out := events
	events = []
	return out


func _emit(ev: Dictionary) -> void:
	events.append(ev)


func _add_combo() -> void:
	combo += 1
	max_combo = maxi(max_combo, combo)


func _judge_regular(note: Chart.Note, result: int, error: float, hand: int) -> void:
	note.judged = true
	note.judgement = result
	note.first_hit_time = note.time + error
	note.first_hit_hand = hand
	match result:
		Result.GREAT:
			greats += 1
			score += SCORE_GREAT
			gauge = clampf(gauge + _gain_great, 0.0, 1.0)
			_add_combo()
			errors.append(error)
		Result.OK:
			oks += 1
			score += SCORE_OK
			gauge = clampf(gauge + _gain_ok, 0.0, 1.0)
			_add_combo()
			errors.append(error)
		Result.MISS:
			misses += 1
			gauge = clampf(gauge - _loss_miss, 0.0, 1.0)
			combo = 0
	if note.is_big() and result != Result.MISS:
		_last_big = note
	else:
		_last_big = null
	_emit({"type": "judge", "note": note, "result": result, "error": error, "hand": hand})


## Advances the cursor past judged/finished notes. Returns the next note or null.
func _current_note(now: float) -> Chart.Note:
	while _next < chart.notes.size():
		var n := chart.notes[_next]
		if n.is_regular():
			if n.judged:
				_next += 1
				continue
			return n
		else:
			if n.finished:
				_next += 1
				continue
			return n
	return null


## Processes a drum hit. kind: HitKind, hand: Hand. Returns the event produced (or {"type": "none"}).
func process_hit(hand: int, kind: int, t: float) -> Dictionary:
	# Second hand completing a big note?
	if _last_big != null and _last_big.first_hit_hand != hand and not _last_big.both_hands:
		var same_kind := (kind == HitKind.DON and _last_big.is_don()) or (kind == HitKind.KA and _last_big.is_ka())
		if same_kind and absf(t - _last_big.first_hit_time) <= BIG_SECOND_HIT_WINDOW:
			_last_big.both_hands = true
			big_both += 1
			score += SCORE_GREAT if _last_big.judgement == Result.GREAT else SCORE_OK
			var ev := {"type": "big_both", "note": _last_big, "hand": hand}
			_emit(ev)
			_last_big = null
			return ev
	_expire(t)
	var note := _current_note(t)
	if note == null:
		return {"type": "none"}
	if note.is_roll():
		if t >= note.time - windows.ok and t <= note.end_time + windows.ok:
			note.hit_count += 1
			roll_hits += 1
			score += SCORE_ROLL_BIG if note.type == Chart.NoteType.ROLL_BIG else SCORE_ROLL
			var ev := {"type": "roll_hit", "note": note, "hand": hand, "kind": kind}
			_emit(ev)
			return ev
		if t < note.time - windows.ok:
			return {"type": "none"}
		return {"type": "none"}
	if note.is_balloon():
		if t >= note.time - windows.ok and t <= note.end_time + windows.ok:
			if kind != HitKind.DON:
				return {"type": "none"}
			note.hit_count += 1
			balloon_hits += 1
			score += SCORE_BALLOON_HIT
			if note.hit_count >= note.hits_required:
				note.popped = true
				note.finished = true
				note.judged = true
				balloon_pops += 1
				score += SCORE_BALLOON_POP
				var ev := {"type": "balloon_pop", "note": note, "hand": hand}
				_emit(ev)
				return ev
			var ev2 := {"type": "balloon_hit", "note": note, "hand": hand, "remaining": note.hits_required - note.hit_count}
			_emit(ev2)
			return ev2
		return {"type": "none"}
	# regular note
	var delta := t - note.time
	if delta < -windows.miss:
		return {"type": "none"}
	var expected_don := note.is_don()
	var correct := (kind == HitKind.DON) == expected_don
	var result := Result.MISS
	var ad := absf(delta)
	if correct:
		if ad <= windows.great:
			result = Result.GREAT
		elif ad <= windows.ok:
			result = Result.OK
	_judge_regular(note, result, delta, hand)
	return events[events.size() - 1]


## Marks notes whose window closed without a hit. Call every frame with the current song time.
func update(now: float) -> void:
	_expire(now)


func _expire(now: float) -> void:
	while _next < chart.notes.size():
		var n := chart.notes[_next]
		if n.is_regular():
			if n.judged:
				_next += 1
				continue
			if now - n.time > windows.miss:
				_judge_regular(n, Result.MISS, windows.miss + 1.0, Hand.ANY)
				_next += 1
				continue
			break
		else:
			if n.finished:
				_next += 1
				continue
			if now > n.end_time + windows.ok:
				n.finished = true
				n.judged = true
				_emit({"type": "roll_end" if n.is_roll() else "balloon_end", "note": n, "hits": n.hit_count})
				_next += 1
				continue
			break


func is_finished(now: float) -> bool:
	if chart.notes.is_empty():
		return true
	_expire(now)
	return _next >= chart.notes.size()


func accuracy() -> float:
	var total := greats + oks + misses
	if total == 0:
		return 1.0
	return float(greats + 0.5 * oks) / float(total)


func cleared() -> bool:
	return gauge >= CLEAR_GAUGE


func rank() -> String:
	var acc := accuracy()
	if misses == 0 and oks == 0 and greats > 0:
		return "SS"
	if acc >= 0.95:
		return "S"
	if acc >= 0.90:
		return "A"
	if acc >= 0.80:
		return "B"
	if acc >= 0.70:
		return "C"
	return "D"


func error_stats() -> Dictionary:
	var n := errors.size()
	if n == 0:
		return {"mean": 0.0, "std": 0.0, "count": 0, "early": 0, "late": 0}
	var sum := 0.0
	var early := 0
	var late := 0
	for e in errors:
		sum += e
		if e < -1.0:
			early += 1
		elif e > 1.0:
			late += 1
	var mean := sum / n
	var var_sum := 0.0
	for e in errors:
		var_sum += (e - mean) * (e - mean)
	return {"mean": mean, "std": sqrt(var_sum / n), "count": n, "early": early, "late": late}


func results() -> Dictionary:
	return {
		"score": score,
		"max_combo": max_combo,
		"greats": greats,
		"oks": oks,
		"misses": misses,
		"roll_hits": roll_hits,
		"balloon_pops": balloon_pops,
		"big_both": big_both,
		"accuracy": accuracy(),
		"gauge": gauge,
		"cleared": cleared(),
		"rank": rank(),
		"errors": error_stats(),
		"full_combo": misses == 0,
	}
