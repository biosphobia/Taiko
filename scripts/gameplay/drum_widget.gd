class_name DrumWidget
extends Control
## The taiko drum on the left of the lane; flashes where the player hit.

var _flash: Array = [0.0, 0.0, 0.0, 0.0] ## left don, right don, left ka, right ka
var _skin: Dictionary


func _ready() -> void:
	_skin = UiTheme.drum_skin()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 220)


func flash(hand: int, kind: int) -> void:
	_flash[kind * 2 + hand] = 1.0


func _process(delta: float) -> void:
	for i in range(4):
		_flash[i] = maxf(0.0, _flash[i] - delta * 7.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	draw_circle(c, r + 8.0, _skin.rope)
	draw_circle(c, r, _skin.rim)
	draw_circle(c, r * 0.78, _skin.face)
	# rim (ka) halves
	if _flash[2] > 0.0:
		draw_arc(c, r * 0.9, PI * 0.5, PI * 1.5, 40, Color(0.25, 0.7, 0.95, _flash[2]), r * 0.24)
	if _flash[3] > 0.0:
		draw_arc(c, r * 0.9, -PI * 0.5, PI * 0.5, 40, Color(0.25, 0.7, 0.95, _flash[3]), r * 0.24)
	# face (don) halves
	if _flash[0] > 0.0:
		_half_disc(c, r * 0.76, true, Color(0.95, 0.27, 0.22, _flash[0]))
	if _flash[1] > 0.0:
		_half_disc(c, r * 0.76, false, Color(0.95, 0.27, 0.22, _flash[1]))
	draw_line(c + Vector2(0, -r * 0.76), c + Vector2(0, r * 0.76), Color(0, 0, 0, 0.25), 2.0)
	for i in range(8):
		var a := TAU * i / 8.0
		draw_circle(c + Vector2(cos(a), sin(a)) * (r + 2.0), 6.0, Color(0.1, 0.08, 0.06))


func _half_disc(c: Vector2, r: float, left: bool, col: Color) -> void:
	var pts := PackedVector2Array()
	var a0 := PI * 0.5 if left else -PI * 0.5
	for i in range(25):
		var a := a0 + PI * i / 24.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
