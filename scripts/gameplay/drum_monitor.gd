class_name DrumMonitor
extends Control
## Shows the calibrated virtual drum (camera view) with the tracked controller positions.

var show_camera_frame := false
var _tex: ImageTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	queue_redraw()


func _cam_to_local(p: Vector2) -> Vector2:
	var cw := float(Settings.get_value("camera_width"))
	var ch := cw * 0.75
	return Vector2(p.x / cw * size.x, p.y / ch * size.y)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	if show_camera_frame and Hardware.hw != null and Hardware.camera_running():
		var img: Image = Hardware.hw.camera_get_preview()
		if img != null:
			if _tex == null:
				_tex = ImageTexture.create_from_image(img)
			else:
				_tex.update(img)
			draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	if bool(Settings.get_value("drum_calibrated")):
		var pts := PackedVector2Array()
		var inner := PackedVector2Array()
		var outer := PackedVector2Array()
		var don_r := float(Settings.get_value("drum_don_ratio"))
		var ka_r := float(Settings.get_value("drum_ka_outer"))
		for i in range(49):
			var a := TAU * i / 48.0
			var uv := Vector2(cos(a), sin(a))
			pts.append(_cam_to_local(Settings.drum_xy(uv)))
			inner.append(_cam_to_local(Settings.drum_xy(uv * don_r)))
			outer.append(_cam_to_local(Settings.drum_xy(uv * ka_r)))
		draw_polyline(outer, Color(0.25, 0.7, 0.95, 0.5), 2.0)
		draw_polyline(pts, Color(1, 1, 1, 0.8), 2.0)
		draw_polyline(inner, Color(0.95, 0.27, 0.22, 0.8), 2.0)
		var c := _cam_to_local(Settings.get_value("drum_center"))
		draw_line(c + Vector2(0, -8), c + Vector2(0, 8), Color(1, 1, 1, 0.6), 1.0)
	for hand in range(2):
		var tr := Hardware.tracking_for_hand(hand)
		if bool(tr.get("tracked", false)):
			var p := _cam_to_local(tr.get("pos", Vector2.ZERO))
			var col := Profile.led_color(hand)
			draw_circle(p, 9.0, col)
			draw_arc(p, 11.0, 0.0, TAU, 20, Color.WHITE, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.3), false, 2.0)
