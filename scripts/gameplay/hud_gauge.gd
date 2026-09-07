class_name HudGauge
extends Control
## Soul gauge with the clear line.

var value := 0.0
var _shown := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_shown = lerpf(_shown, value, minf(1.0, delta * 10.0))
	queue_redraw()


func _draw() -> void:
	var t := UiTheme.theme()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	var segs := 20
	var seg_w := (size.x - 8.0) / segs
	for i in range(segs):
		var frac := float(i + 1) / segs
		var lit := _shown >= frac - 0.001
		var col: Color = (Color(1.0, 0.85, 0.2) if frac > Judge.CLEAR_GAUGE else t.accent) if lit else Color(0.2, 0.2, 0.22)
		draw_rect(Rect2(4.0 + i * seg_w, 4.0, seg_w - 3.0, size.y - 8.0), col)
	var cx := 4.0 + Judge.CLEAR_GAUGE * (size.x - 8.0)
	draw_line(Vector2(cx, 0), Vector2(cx, size.y), Color.WHITE, 3.0)
	if _shown >= Judge.CLEAR_GAUGE:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 0.6, 0.12))
