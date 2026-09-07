class_name ErrorBar
extends Control
## osu!-style hit error bar: colored windows and recent hit offsets.

var windows := {"great": 35.0, "ok": 80.0, "miss": 95.0}
var _hits: Array = [] ## {error, t}
var mean := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_error(err_ms: float) -> void:
	_hits.append({"error": err_ms, "t": Time.get_ticks_msec()})
	if _hits.size() > 40:
		_hits.pop_front()
	var s := 0.0
	for h in _hits:
		s += float(h.error)
	mean = s / _hits.size()
	queue_redraw()


func _process(_d: float) -> void:
	if not _hits.is_empty():
		queue_redraw()


func _draw() -> void:
	var cx := size.x * 0.5
	var scale := (size.x * 0.5) / maxf(float(windows.miss), 1.0)
	var h := size.y
	draw_rect(Rect2(cx - windows.miss * scale, h * 0.35, windows.miss * 2 * scale, h * 0.3), Color(0.9, 0.3, 0.3, 0.7))
	draw_rect(Rect2(cx - windows.ok * scale, h * 0.35, windows.ok * 2 * scale, h * 0.3), Color(0.9, 0.85, 0.3, 0.8))
	draw_rect(Rect2(cx - windows.great * scale, h * 0.35, windows.great * 2 * scale, h * 0.3), Color(0.4, 0.9, 1.0, 0.9))
	draw_line(Vector2(cx, 0), Vector2(cx, h), Color.WHITE, 2.0)
	var now := Time.get_ticks_msec()
	for hit in _hits:
		var age := float(now - int(hit.t))
		var a := clampf(1.0 - age / 4000.0, 0.0, 1.0)
		var x := cx + float(hit.error) * scale
		draw_line(Vector2(x, h * 0.15), Vector2(x, h * 0.85), Color(1, 1, 1, a), 2.0)
	if not _hits.is_empty():
		var mx := cx + mean * scale
		draw_line(Vector2(mx, 0), Vector2(mx, h), Color(1.0, 0.6, 0.2), 3.0)
