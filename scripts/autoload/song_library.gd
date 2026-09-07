extends Node
## Scans bundled and user songs, imports .osz / .osu files.

signal library_changed

const USER_SONGS := "user://songs"

class SongEntry:
	var key: String = ""
	var folder: String = ""
	var title: String = ""
	var artist: String = ""
	var creator: String = ""
	var audio: String = ""
	var background: String = ""
	var preview_time: float = -1.0
	var bundled: bool = false
	var difficulties: Array = [] ## [{version, path, od, mode, key}]

var songs: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_SONGS))
	rescan()


func songs_dir_global() -> String:
	return ProjectSettings.globalize_path(USER_SONGS)


func rescan() -> void:
	songs.clear()
	var groups := {}
	# bundled
	if FileAccess.file_exists("res://songs/manifest.txt"):
		for line in FileAccess.get_file_as_string("res://songs/manifest.txt").split("\n"):
			var rel := line.strip_edges()
			if rel.is_empty():
				continue
			_add_chart("res://songs/" + rel, true, groups)
	# user
	_scan_dir(USER_SONGS, groups, 0)
	for k in groups:
		songs.append(groups[k])
	songs.sort_custom(func(a: SongEntry, b: SongEntry) -> bool:
		if a.bundled != b.bundled:
			return a.bundled
		return a.title.naturalnocasecmp_to(b.title) < 0)
	library_changed.emit()


func _scan_dir(path: String, groups: Dictionary, depth: int) -> void:
	if depth > 3:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := path.path_join(name)
		if dir.current_is_dir():
			_scan_dir(full, groups, depth + 1)
		elif name.get_extension().to_lower() == "osu":
			_add_chart(full, false, groups)
		name = dir.get_next()
	dir.list_dir_end()


func _add_chart(path: String, bundled: bool, groups: Dictionary) -> void:
	var meta := OsuParser.parse_metadata(path)
	if meta.is_empty():
		return
	var folder := path.get_base_dir()
	var entry: SongEntry = groups.get(folder)
	if entry == null:
		entry = SongEntry.new()
		entry.folder = folder
		entry.key = folder.trim_prefix("res://songs/").trim_prefix("user://songs/")
		entry.title = str(meta.get("title", ""))
		entry.artist = str(meta.get("artist", ""))
		entry.creator = str(meta.get("creator", ""))
		entry.bundled = bundled
		entry.preview_time = float(meta.get("preview_time", -1.0))
		groups[folder] = entry
	if entry.audio == "" and str(meta.get("audio", "")) != "":
		entry.audio = folder.path_join(str(meta["audio"]))
	if entry.background == "" and str(meta.get("background", "")) != "":
		entry.background = folder.path_join(str(meta["background"]))
	if entry.title == "" and str(meta.get("title", "")) != "":
		entry.title = str(meta["title"])
	entry.difficulties.append({
		"version": str(meta.get("version", "")),
		"path": path,
		"od": float(meta.get("od", 5.0)),
		"mode": int(meta.get("mode", 1)),
		"key": entry.key + "|" + str(meta.get("version", "")),
	})
	entry.difficulties.sort_custom(func(a, b): return _difficulty_rank(a) < _difficulty_rank(b))


static func _difficulty_rank(d: Dictionary) -> float:
	var v := str(d.version).to_lower()
	var order := ["kantan", "easy", "futsuu", "normal", "muzukashii", "hard", "oni", "insane", "inner", "ura", "extra", "expert"]
	for i in range(order.size()):
		if v.contains(order[i]):
			return float(i) + float(d.od) * 0.01
	return 100.0 + float(d.od)


func find_song(key: String) -> SongEntry:
	for s in songs:
		if s.key == key:
			return s
	return null


## Imports a .osz archive, a .osu file (with its folder's audio) or a directory into user://songs.
func import_path(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	var result := {"ok": false, "message": "", "added": 0}
	if ext == "osz" or ext == "zip":
		result = _import_osz(path)
	elif ext == "osu":
		result = _import_folder(path.get_base_dir(), path.get_file().get_basename())
	elif DirAccess.dir_exists_absolute(path):
		result = _import_folder(path, path.get_file())
	else:
		result.message = "Unsupported file type: " + ext
	if result.ok:
		rescan()
	return result


static func _sanitize(name: String) -> String:
	var out := ""
	for ch in name:
		if ch.is_valid_identifier() or ch in " -_().[]!&,'":
			out += ch
		else:
			out += "_"
	out = out.strip_edges()
	if out.is_empty():
		out = "song"
	return out.left(80)


func _unique_dir(base_name: String) -> String:
	var name := _sanitize(base_name)
	var target := USER_SONGS.path_join(name)
	var i := 2
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)):
		target = USER_SONGS.path_join("%s (%d)" % [name, i])
		i += 1
	return target


func _import_osz(path: String) -> Dictionary:
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		return {"ok": false, "message": "Cannot open archive", "added": 0}
	var files := zr.get_files()
	var has_osu := false
	for f in files:
		if f.get_extension().to_lower() == "osu":
			has_osu = true
	if not has_osu:
		zr.close()
		return {"ok": false, "message": "No .osu charts inside the archive", "added": 0}
	var target := _unique_dir(path.get_file().get_basename())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target))
	var added := 0
	for f in files:
		if f.ends_with("/"):
			continue
		var ext := f.get_extension().to_lower()
		if not ext in ["osu", "mp3", "ogg", "wav", "jpg", "jpeg", "png", "flac"]:
			continue
		var data := zr.read_file(f)
		var out_path := target.path_join(f.get_file())
		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		if fa:
			fa.store_buffer(data)
			fa.close()
			if ext == "osu":
				added += 1
	zr.close()
	return {"ok": added > 0, "message": "Imported %d chart(s)" % added, "added": added}


func _import_folder(dir_path: String, name: String) -> Dictionary:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return {"ok": false, "message": "Cannot open folder", "added": 0}
	var target := _unique_dir(name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target))
	var added := 0
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			var ext := f.get_extension().to_lower()
			if ext in ["osu", "mp3", "ogg", "wav", "jpg", "jpeg", "png", "flac"]:
				var data := FileAccess.get_file_as_bytes(dir_path.path_join(f))
				var fa := FileAccess.open(target.path_join(f), FileAccess.WRITE)
				if fa:
					fa.store_buffer(data)
					fa.close()
					if ext == "osu":
						added += 1
		f = dir.get_next()
	dir.list_dir_end()
	return {"ok": added > 0, "message": "Imported %d chart(s)" % added, "added": added}


## Loads an audio file from res:// or user:// (mp3, ogg, wav) at runtime.
static func load_audio(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is AudioStream:
				return res
	var ext := path.get_extension().to_lower()
	if not FileAccess.file_exists(path):
		return null
	match ext:
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = FileAccess.get_file_as_bytes(path)
			return mp3
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


static func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var t = load(path)
		return t if t is Texture2D else null
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)
