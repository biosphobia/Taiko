class_name LaneRenderer
extends Control
## Draws the note lane: scrolling notes, bar lines, the target circle and hit effects.

const HIT_X := 340.0
const LANE_Y := 280.0
const LANE_H := 170.0
const R_SMALL := 44.0
const R_BIG := 64.0
const BASE_PX_PER_MS := 0.6 ## at scroll speed 1.0 and 120 BPM one beat (500 ms) spans 300 px

var chart: Chart
var now_ms := 0.0
var scroll_speed := 1.0
var bar_lines := PackedFloat64Array()
var kiai := false
var flying: Array = [] ## {type, t0, result}
var judgements: Array = [] ## {text, color, t0}
var target_flash := 0.0
var target_flash_kind := 0
var _skin: Dictionary
var _theme: Dictionary
var _font: Font


func _ready() -> void:
	_skin = UiTheme.note_skin()
	_theme = UiTheme.theme()
	_font = UiTheme.font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func px_per_ms() -> float:
	return BASE_PX_PER_MS * scroll_speed


func note_x(t: float, velocity: float) -> float:
	return HIT_X + (t - now_ms) * px_per_ms() * velocity


func add_flying(note: Chart.Note, result: int) -> void:
	flying.append({"type": note.type, "t0": now_ms, "result": result})


func add_judgement(text: String, color: Color) -> void:
	judgements.append({"text": text, "color": color, "t0": now_ms})
	if judgements.size() > 3:
		judgements.pop_front()


func flash_target(kind: int) -> void:
	target_flash = 1.0
	target_flash_kind = kind


func _process(delta: float) -> void:
	target_flash = maxf(0.0, target_flash - delta * 8.0)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	# lane background
	var lane_rect := Rect2(0, LANE_Y - LANE_H * 0.5, w, LANE_H)
	draw_rect(lane_rect, _theme.lane)
	var edge: Color = _theme.kiai if kiai else _theme.lane_edge
	draw_line(Vector2(0, lane_rect.position.y), Vector2(w, lane_rect.position.y), edge, 4.0)
	draw_line(Vector2(0, lane_rect.end.y), Vector2(w, lane_rect.end.y), edge, 4.0)
	if kiai:
		draw_rect(lane_rect, Color(_theme.kiai.r, _theme.kiai.g, _theme.kiai.b, 0.08))
	# bar lines
	if chart != null:
		var ppm := px_per_ms()
		for t in bar_lines:
			var v := chart.velocity_at(t)
			var x := HIT_X + (t - now_ms) * ppm * v
			if x < HIT_X - 100.0 or x > w + 10.0:
				continue
			draw_line(Vector2(x, lane_rect.position.y + 4), Vector2(x, lane_rect.end.y - 4), Color(1, 1, 1, 0.35), 2.0)
	# target
	var tcol := Color(1, 1, 1, 0.55)
	if target_flash > 0.0:
		var fc: Color = _skin.don if target_flash_kind == 0 else _skin.ka
		draw_circle(Vector2(HIT_X, LANE_Y), R_BIG + 8.0, Color(fc.r, fc.g, fc.b, 0.35 * target_flash))
	draw_arc(Vector2(HIT_X, LANE_Y), R_SMALL + 6.0, 0.0, TAU, 48, tcol, 5.0)
	draw_arc(Vector2(HIT_X, LANE_Y), R_BIG + 4.0, 0.0, TAU, 64, Color(1, 1, 1, 0.22), 3.0)
	# notes (draw later notes first so earlier notes are on top)
	if chart != null:
		var visible: Array = []
		var ppm := px_per_ms()
		var n := chart.notes.size()
		var i := 0
		# skip notes whose window is long gone
		while i < n and chart.notes[i].judged and (chart.notes[i].judgement != Judge.Result.MISS or chart.notes[i].time < now_ms - 600.0) and (not chart.notes[i].is_roll() or chart.notes[i].end_time < now_ms - 600.0):
			i += 1
		var count := 0
		while i < n and count < 600:
			var note := chart.notes[i]
			i += 1
			count += 1
			if note.is_regular() and note.judged and note.judgement != Judge.Result.MISS:
				continue
			if note.is_balloon() and note.popped:
				continue
			var x := note_x(note.time, note.velocity)
			var x_end := x
			if note.is_roll() or note.is_balloon():
				x_end = note_x(note.end_time, note.velocity)
				if note.is_balloon():
					x = maxf(x, HIT_X) if now_ms >= note.time and now_ms <= note.end_time else x
			if x_end < -R_BIG - 20.0:
				continue
			if x > w + R_BIG + 400.0:
				if x - w > 4000.0:
					break
				continue
			visible.append(note)
		for k in range(visible.size() - 1, -1, -1):
			_draw_note(visible[k])
	# flying notes
	for f in flying:
		var age: float = now_ms - float(f.t0)
		if age < 0.0 or age > 320.0:
			continue
		var p := age / 320.0
		var pos := Vector2(HIT_X + p * 380.0, LANE_Y - 260.0 * sin(p * PI) - p * 40.0)
		var col: Color = _skin.don if f.type in [Chart.NoteType.DON, Chart.NoteType.DON_BIG] else _skin.ka
		var r := R_BIG if f.type in [Chart.NoteType.DON_BIG, Chart.NoteType.KA_BIG] else R_SMALL
		col.a = 1.0 - p * 0.8
		draw_circle(pos, r * (1.0 - p * 0.35), col)
	flying = flying.filter(func(f): return now_ms - float(f.t0) <= 340.0)
	# judgement text
	for j in judgements:
		var age: float = now_ms - float(j.t0)
		if age < 0.0 or age > 500.0:
			continue
		var p := age / 500.0
		var col: Color = j.color
		col.a = 1.0 - p
		var sz := int(44.0 + 10.0 * (1.0 - minf(1.0, age / 80.0)))
		var text: String = j.text
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, sz).x
		draw_string(_font, Vector2(HIT_X - tw * 0.5 + 2, LANE_Y - LANE_H * 0.5 - 24.0 - p * 30.0 + 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, col.a * 0.7))
		draw_string(_font, Vector2(HIT_X - tw * 0.5, LANE_Y - LANE_H * 0.5 - 24.0 - p * 30.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
	judgements = judgements.filter(func(j): return now_ms - float(j.t0) <= 520.0)


func _draw_note(note: Chart.Note) -> void:
	var outline: Color = _skin.outline
	var ow: float = _skin.outline_width
	var center := Vector2(note_x(note.time, note.velocity), LANE_Y)
	var missed := note.judged and note.judgement == Judge.Result.MISS
	var alpha := 1.0
	if missed:
		alpha = clampf(1.0 - (now_ms - note.time - 100.0) / 500.0, 0.0, 1.0) * 0.6
	match note.type:
		Chart.NoteType.DON, Chart.NoteType.DON_BIG:
			var r := R_BIG if note.type == Chart.NoteType.DON_BIG else R_SMALL
			_circle_note(center, r, _skin.don, outline, ow, alpha)
		Chart.NoteType.KA, Chart.NoteType.KA_BIG:
			var r := R_BIG if note.type == Chart.NoteType.KA_BIG else R_SMALL
			_circle_note(center, r, _skin.ka, outline, ow, alpha)
			draw_arc(center, r * 0.55, 0.0, TAU, 32, Color(1, 1, 1, 0.5 * alpha), 3.0)
		Chart.NoteType.ROLL, Chart.NoteType.ROLL_BIG:
			var r := R_BIG if note.type == Chart.NoteType.ROLL_BIG else R_SMALL
			var x2 := note_x(note.end_time, note.velocity)
			var body := Rect2(center.x, center.y - r * 0.7, maxf(0.0, x2 - center.x), r * 1.4)
			var col: Color = _skin.roll
			col.a = alpha
			draw_rect(body, col)
			draw_rect(Rect2(body.position + Vector2(0, -ow * 0.5), Vector2(body.size.x, ow)), Color(outline, alpha))
			draw_rect(Rect2(Vector2(body.position.x, body.end.y - ow * 0.5), Vector2(body.size.x, ow)), Color(outline, alpha))
			draw_circle(Vector2(x2, center.y), r * 0.7, col)
			draw_arc(Vector2(x2, center.y), r * 0.7, -PI * 0.5, PI * 0.5, 24, Color(outline, alpha), ow)
			_circle_note(center, r, _skin.roll, outline, ow, alpha)
			if now_ms >= note.time - 50.0 and now_ms <= note.end_time + 50.0 and note.hit_count > 0:
				_draw_counter(Vector2(HIT_X, LANE_Y - LANE_H * 0.5 - 70.0), str(note.hit_count), _skin.roll)
		Chart.NoteType.BALLOON:
			var col: Color = _skin.balloon
			var active := now_ms >= note.time and now_ms <= note.end_time + 50.0
			var pos := Vector2(HIT_X, LANE_Y) if active else center
			if now_ms > note.end_time + 50.0:
				pos = center
				alpha *= 0.5
			_circle_note(pos, R_SMALL, col, outline, ow, alpha)
			draw_circle(pos + Vector2(0, R_SMALL + 8), 6.0, Color(col, alpha))
			var remaining := maxi(0, note.hits_required - note.hit_count)
			if active:
				_draw_counter(Vector2(HIT_X, LANE_Y - LANE_H * 0.5 - 70.0), str(remaining), col)
			else:
				var s := str(note.hits_required)
				var tw := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, 28).x
				draw_string(_font, pos + Vector2(-tw * 0.5, 10), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.1, 0.05, 0, alpha))


func _circle_note(center: Vector2, r: float, fill: Color, outline: Color, ow: float, alpha: float) -> void:
	draw_circle(center, r + ow, Color(outline, alpha))
	draw_circle(center, r, Color(fill, alpha))
	draw_circle(center + Vector2(-r * 0.3, -r * 0.3), r * 0.22, Color(1, 1, 1, 0.35 * alpha))


func _draw_counter(pos: Vector2, text: String, col: Color) -> void:
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 54).x
	draw_circle(pos, 46.0, Color(0, 0, 0, 0.6))
	draw_arc(pos, 46.0, 0.0, TAU, 32, col, 4.0)
	draw_string(_font, pos + Vector2(-tw * 0.5, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color.WHITE)
