extends RefCounted

const RUN := preload("res://tests/run_tests.gd")

const SAMPLE := """osu file format v14

[General]
AudioFilename: audio.mp3
PreviewTime: 12000
Mode: 1

[Metadata]
Title:Test Song
Artist:Someone
Creator:Mapper
Version:Oni

[Difficulty]
HPDrainRate:6
OverallDifficulty:6
SliderMultiplier:1.4
SliderTickRate:1

[Events]
0,0,"bg.jpg",0,0

[TimingPoints]
1000,500,4,1,0,80,1,0
9000,-50,4,1,0,80,0,1
17000,300,4,1,0,80,1,0

[HitObjects]
256,192,1000,1,0,0:0:0:0:
256,192,1500,1,8,0:0:0:0:
256,192,2000,1,4,0:0:0:0:
256,192,2500,1,12,0:0:0:0:
256,192,3000,2,0,L|512:192,1,140
256,192,5000,12,0,7000,0:0:0:0:
256,192,9000,2,4,L|512:192,2,140
256,192,17000,1,0,0:0:0:0:
"""


func test_parse_basic() -> void:
	var c := OsuParser.parse_text(SAMPLE, "/songs/x")
	RUN.check(c != null, "chart parsed")
	RUN.check(c.title == "Test Song" and c.artist == "Someone" and c.version == "Oni", "metadata")
	RUN.check(c.audio_path == "/songs/x/audio.mp3", "audio path: " + c.audio_path)
	RUN.check(c.background_path == "/songs/x/bg.jpg", "background path")
	RUN.check(is_equal_approx(c.od, 6.0), "OD")
	RUN.check(c.notes.size() == 8, "note count %d" % c.notes.size())
	RUN.check(c.notes[0].type == Chart.NoteType.DON, "don")
	RUN.check(c.notes[1].type == Chart.NoteType.KA, "ka (clap)")
	RUN.check(c.notes[2].type == Chart.NoteType.DON_BIG, "big don (finish)")
	RUN.check(c.notes[3].type == Chart.NoteType.KA_BIG, "big ka (finish+clap)")
	# slider: length 140 / (1.4*100*1) * 500 = 500 ms
	RUN.check(c.notes[4].type == Chart.NoteType.ROLL and is_equal_approx(c.notes[4].end_time, 3500.0), "roll duration %f" % c.notes[4].end_time)
	# spinner: 2 s, OD 6 -> multiplier 5.5 -> 11 hits
	RUN.check(c.notes[5].type == Chart.NoteType.BALLOON and c.notes[5].hits_required == 11, "balloon hits %d" % c.notes[5].hits_required)
	# slider at 9000 under SV 2.0 (beat -50), 2 slides: 140/(1.4*100*2)*500 = 250 ms per slide -> 500 ms, big
	RUN.check(c.notes[6].type == Chart.NoteType.ROLL_BIG and is_equal_approx(c.notes[6].end_time, 9500.0), "big roll with SV: %f" % c.notes[6].end_time)
	RUN.check(is_equal_approx(c.main_bpm, 120.0), "main bpm %f" % c.main_bpm)
	RUN.check(is_equal_approx(c.bpm_at(17000.0), 200.0), "bpm change")
	RUN.check(is_equal_approx(c.sv_at(9000.0), 2.0) and is_equal_approx(c.sv_at(17000.0), 1.0), "sv reset by uninherited point")
	RUN.check(c.kiai_at(9500.0) and not c.kiai_at(1500.0), "kiai")
	RUN.check(is_equal_approx(c.notes[6].velocity, 2.0), "velocity sv*bpm: %f" % c.notes[6].velocity)
	RUN.check(is_equal_approx(c.notes[7].velocity, 200.0 / 120.0), "velocity at 200bpm: %f" % c.notes[7].velocity)
	var bars := c.bar_lines()
	RUN.check(bars.size() > 4 and is_equal_approx(bars[0], 1000.0) and is_equal_approx(bars[1], 3000.0), "bar lines")


func test_parse_bundled_songs() -> void:
	var manifest := FileAccess.get_file_as_string("res://songs/manifest.txt")
	var count := 0
	for line in manifest.split("\n"):
		if line.strip_edges().is_empty():
			continue
		var c := OsuParser.parse_file("res://songs/" + line.strip_edges())
		RUN.check(c != null and c.notes.size() > 10, "bundled chart parses: " + line)
		if c != null:
			RUN.check(FileAccess.file_exists(c.audio_path), "audio exists for " + line)
			count += 1
	RUN.check(count == 10, "10 bundled charts")


func test_std_conversion() -> void:
	var txt := SAMPLE.replace("Mode: 1", "Mode: 0")
	var c := OsuParser.parse_text(txt, "/x")
	RUN.check(c.converted, "converted flag")
	# first slider (500 ms < 2 beats) becomes notes on ticks (3000, 3500); the SV2 slider at 9000 lasts
	# exactly 2 speed-adjusted beats and therefore stays a drumroll.
	var rolls := 0
	var at_3500 := false
	for n in c.notes:
		if n.is_roll():
			rolls += 1
		if is_equal_approx(n.time, 3500.0):
			at_3500 = true
	RUN.check(rolls == 1 and at_3500 and c.notes.size() == 9, "short slider converted to notes (rolls=%d, notes=%d)" % [rolls, c.notes.size()])


func test_metadata_only() -> void:
	var path := "user://_test_meta.osu"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(SAMPLE)
	f.close()
	var m := OsuParser.parse_metadata(path)
	RUN.check(m["title"] == "Test Song" and m["version"] == "Oni" and int(m["mode"]) == 1, "metadata parse")
	RUN.check(m["background"] == "bg.jpg", "metadata background")
	DirAccess.remove_absolute(path)
