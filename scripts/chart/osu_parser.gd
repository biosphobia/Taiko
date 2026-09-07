class_name OsuParser
extends RefCounted
## Parser for osu! beatmaps (.osu, format v3..v14) producing a Chart.
## osu!taiko maps (Mode: 1) are read directly; other modes are converted with taiko conversion rules.

const HITSOUND_WHISTLE := 2
const HITSOUND_FINISH := 4
const HITSOUND_CLAP := 8
const TYPE_CIRCLE := 1
const TYPE_SLIDER := 2
const TYPE_SPINNER := 8
const TYPE_HOLD := 128
const BOM := "﻿"


static func difficulty_range(value: float, lo: float, mid: float, hi: float) -> float:
	if value > 5.0:
		return mid + (hi - mid) * (value - 5.0) / 5.0
	if value < 5.0:
		return mid - (mid - lo) * (5.0 - value) / 5.0
	return mid


static func parse_file(path: String) -> Chart:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("OsuParser: cannot open %s" % path)
		return null
	var text := f.get_as_text()
	f.close()
	var chart := parse_text(text, path.get_base_dir())
	if chart != null:
		chart.source_path = path
	return chart


## Reads only [General]/[Metadata]/[Difficulty]/[Events] (fast, for song lists).
static func parse_metadata(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var meta := _default_meta()
	meta["path"] = path
	var section := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with(BOM):
			line = line.substr(1)
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			if section == "TimingPoints" or section == "HitObjects":
				break
			continue
		match section:
			"General", "Metadata", "Difficulty":
				var kv := _split_kv(line)
				if not kv.is_empty():
					_apply_meta(meta, kv[0], kv[1])
			"Events":
				var bg := _parse_background(line)
				if bg != "":
					meta["background"] = bg
	f.close()
	return meta


static func _default_meta() -> Dictionary:
	return {"path": "", "audio": "", "title": "", "artist": "", "creator": "", "version": "", "mode": 1, "od": 5.0, "hp": 5.0, "preview_time": -1.0, "slider_multiplier": 1.4, "slider_tick_rate": 1.0, "title_unicode": "", "artist_unicode": "", "background": ""}


static func _split_kv(line: String) -> Array:
	var idx := line.find(":")
	if idx < 0:
		return []
	return [line.substr(0, idx).strip_edges(), line.substr(idx + 1).strip_edges()]


static func _parse_background(line: String) -> String:
	# "0,0,"bg.jpg",0,0" or "Background,0,"bg.jpg""
	var parts := line.split(",")
	if parts.size() >= 3 and (parts[0].strip_edges() == "0" or parts[0].strip_edges().to_lower() == "background"):
		var fn := parts[2].strip_edges().trim_prefix("\"").trim_suffix("\"")
		var ext := fn.get_extension().to_lower()
		if ext in ["jpg", "jpeg", "png", "bmp", "webp"]:
			return fn
	return ""


static func _apply_meta(meta: Dictionary, key: String, value: String) -> void:
	match key:
		"AudioFilename": meta["audio"] = value
		"Title": meta["title"] = value
		"TitleUnicode": meta["title_unicode"] = value
		"Artist": meta["artist"] = value
		"ArtistUnicode": meta["artist_unicode"] = value
		"Creator": meta["creator"] = value
		"Version": meta["version"] = value
		"Mode": meta["mode"] = value.to_int()
		"OverallDifficulty": meta["od"] = value.to_float()
		"HPDrainRate": meta["hp"] = value.to_float()
		"PreviewTime": meta["preview_time"] = value.to_float()
		"SliderMultiplier": meta["slider_multiplier"] = value.to_float()
		"SliderTickRate": meta["slider_tick_rate"] = value.to_float()


static func parse_text(text: String, base_dir: String) -> Chart:
	var chart := Chart.new()
	var meta := _default_meta()
	var section := ""
	var timing_lines: Array[String] = []
	var object_lines: Array[String] = []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with(BOM):
			line = line.substr(1)
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		match section:
			"General", "Metadata", "Difficulty":
				var kv := _split_kv(line)
				if not kv.is_empty():
					_apply_meta(meta, kv[0], kv[1])
			"Events":
				var bg := _parse_background(line)
				if bg != "":
					meta["background"] = bg
			"TimingPoints":
				timing_lines.append(line)
			"HitObjects":
				object_lines.append(line)
	chart.title = meta["title"]
	chart.title_unicode = meta["title_unicode"]
	chart.artist = meta["artist"]
	chart.artist_unicode = meta["artist_unicode"]
	chart.creator = meta["creator"]
	chart.version = meta["version"]
	chart.mode = int(meta["mode"])
	chart.od = float(meta["od"])
	chart.hp = float(meta["hp"])
	chart.preview_time = float(meta["preview_time"])
	chart.slider_multiplier = float(meta["slider_multiplier"])
	chart.slider_tick_rate = float(meta["slider_tick_rate"])
	if chart.slider_multiplier <= 0.0:
		chart.slider_multiplier = 1.4
	if chart.slider_tick_rate <= 0.0:
		chart.slider_tick_rate = 1.0
	chart.audio_path = base_dir.path_join(meta["audio"]) if meta["audio"] != "" else ""
	chart.background_path = base_dir.path_join(meta["background"]) if meta["background"] != "" else ""
	chart.converted = chart.mode != 1

	_parse_timing_points(chart, timing_lines)
	_parse_hit_objects(chart, object_lines)
	chart.sort_notes()
	chart.compute_main_bpm()
	chart.compute_velocities()
	return chart


static func _parse_timing_points(chart: Chart, lines: Array[String]) -> void:
	var last_uninherited_beat := 500.0
	for line in lines:
		var p := line.split(",")
		if p.size() < 2:
			continue
		var tp := Chart.TimingPoint.new()
		tp.time = p[0].strip_edges().to_float()
		var beat := p[1].strip_edges().to_float()
		tp.meter = p[2].strip_edges().to_int() if p.size() > 2 else 4
		if tp.meter <= 0:
			tp.meter = 4
		var uninherited := true
		if p.size() > 6:
			uninherited = p[6].strip_edges().to_int() != 0
		else:
			uninherited = beat > 0.0
		if p.size() > 7:
			tp.kiai = (p[7].strip_edges().to_int() & 1) != 0
		if uninherited and beat > 0.0:
			tp.uninherited = true
			tp.beat_length = beat
			last_uninherited_beat = beat
			tp.sv = 1.0
		else:
			tp.uninherited = false
			tp.beat_length = last_uninherited_beat
			tp.sv = clampf(-100.0 / beat, 0.1, 10.0) if beat < 0.0 else 1.0
		chart.timing_points.append(tp)
	chart.timing_points.sort_custom(func(a: Chart.TimingPoint, b: Chart.TimingPoint) -> bool:
		if is_equal_approx(a.time, b.time):
			return a.uninherited and not b.uninherited
		return a.time < b.time)
	if chart.timing_points.is_empty():
		var tp := Chart.TimingPoint.new()
		tp.time = 0.0
		tp.beat_length = 500.0
		chart.timing_points.append(tp)


static func _parse_hit_objects(chart: Chart, lines: Array[String]) -> void:
	var swell_multiplier := difficulty_range(chart.od, 3.0, 5.0, 7.5)
	for line in lines:
		var p := line.split(",")
		if p.size() < 5:
			continue
		var time := p[2].strip_edges().to_float()
		var type := p[3].strip_edges().to_int()
		var hitsound := p[4].strip_edges().to_int()
		var is_ka := (hitsound & (HITSOUND_WHISTLE | HITSOUND_CLAP)) != 0
		var is_big := (hitsound & HITSOUND_FINISH) != 0
		if (type & TYPE_SPINNER) != 0:
			var end_time := p[5].strip_edges().to_float() if p.size() > 5 else time + 1000.0
			var n := Chart.Note.new()
			n.time = time
			n.end_time = maxf(end_time, time + 50.0)
			n.type = Chart.NoteType.BALLOON
			n.hits_required = maxi(1, int((n.end_time - n.time) / 1000.0 * swell_multiplier))
			chart.notes.append(n)
		elif (type & TYPE_SLIDER) != 0:
			var slides := 1
			var length := 0.0
			if p.size() > 6:
				slides = maxi(1, p[6].strip_edges().to_int())
			if p.size() > 7:
				length = p[7].strip_edges().to_float()
			var beat := chart.beat_length_at(time)
			var sv := chart.sv_at(time)
			var slide_duration := length / (chart.slider_multiplier * 100.0 * sv) * beat
			var duration := slide_duration * slides
			if duration <= 0.0:
				duration = beat
			if chart.mode == 1:
				var n := Chart.Note.new()
				n.time = time
				n.end_time = time + duration
				n.type = Chart.NoteType.ROLL_BIG if is_big else Chart.NoteType.ROLL
				chart.notes.append(n)
			else:
				_convert_std_slider(chart, time, duration, is_ka, is_big, p)
		else:
			# circle (mania holds are treated as circles)
			var n := Chart.Note.new()
			n.time = time
			if is_ka:
				n.type = Chart.NoteType.KA_BIG if is_big else Chart.NoteType.KA
			else:
				n.type = Chart.NoteType.DON_BIG if is_big else Chart.NoteType.DON
			chart.notes.append(n)


## osu!standard -> taiko conversion for sliders (simplified version of osu!'s rules):
## short sliders become a run of notes on the tick grid, long sliders become drumrolls.
static func _convert_std_slider(chart: Chart, time: float, duration: float, is_ka: bool, is_big: bool, p: PackedStringArray) -> void:
	var beat := chart.beat_length_at(time)
	var sv := chart.sv_at(time)
	var speed_adjusted_beat := beat / sv
	var tick_spacing := minf(speed_adjusted_beat / chart.slider_tick_rate, duration)
	if tick_spacing > 0.0 and duration < 2.0 * speed_adjusted_beat:
		var edge_sounds: Array = []
		if p.size() > 8:
			for s in p[8].split("|"):
				edge_sounds.append(s.strip_edges().to_int())
		var t := time
		var i := 0
		while t <= time + duration + 1.0:
			var hs_ka := is_ka
			var hs_big := is_big
			if i < edge_sounds.size():
				hs_ka = (int(edge_sounds[i]) & (HITSOUND_WHISTLE | HITSOUND_CLAP)) != 0
				hs_big = (int(edge_sounds[i]) & HITSOUND_FINISH) != 0
			var n := Chart.Note.new()
			n.time = t
			if hs_ka:
				n.type = Chart.NoteType.KA_BIG if hs_big else Chart.NoteType.KA
			else:
				n.type = Chart.NoteType.DON_BIG if hs_big else Chart.NoteType.DON
			chart.notes.append(n)
			t += tick_spacing
			i += 1
			if i > 64:
				break
	else:
		var n := Chart.Note.new()
		n.time = time
		n.end_time = time + duration
		n.type = Chart.NoteType.ROLL_BIG if is_big else Chart.NoteType.ROLL
		chart.notes.append(n)
