class_name Chart
extends RefCounted
## In-memory representation of a taiko chart (notes + timing), independent of the source format.

enum NoteType { DON, KA, DON_BIG, KA_BIG, ROLL, ROLL_BIG, BALLOON }

class Note:
	var index: int = 0
	var time: float = 0.0 ## ms
	var type: int = NoteType.DON
	var end_time: float = 0.0 ## ms, rolls and balloons
	var hits_required: int = 0 ## balloons
	var velocity: float = 1.0 ## scroll multiplier (SV * BPM factor)
	# runtime state
	var judged: bool = false
	var judgement: int = -1
	var hit_count: int = 0
	var first_hit_time: float = 0.0
	var first_hit_hand: int = -1
	var both_hands: bool = false
	var popped: bool = false
	var finished: bool = false ## rolls/balloons whose window has closed

	func is_don() -> bool:
		return type == NoteType.DON or type == NoteType.DON_BIG

	func is_ka() -> bool:
		return type == NoteType.KA or type == NoteType.KA_BIG

	func is_big() -> bool:
		return type == NoteType.DON_BIG or type == NoteType.KA_BIG or type == NoteType.ROLL_BIG

	func is_roll() -> bool:
		return type == NoteType.ROLL or type == NoteType.ROLL_BIG

	func is_balloon() -> bool:
		return type == NoteType.BALLOON

	func is_regular() -> bool:
		return type <= NoteType.KA_BIG

	func reset_runtime() -> void:
		judged = false
		judgement = -1
		hit_count = 0
		first_hit_time = 0.0
		first_hit_hand = -1
		both_hands = false
		popped = false
		finished = false


class TimingPoint:
	var time: float = 0.0
	var beat_length: float = 500.0 ## ms per beat (only meaningful when uninherited)
	var meter: int = 4
	var uninherited: bool = true
	var sv: float = 1.0 ## slider velocity multiplier (inherited points)
	var kiai: bool = false


var title: String = ""
var title_unicode: String = ""
var artist: String = ""
var artist_unicode: String = ""
var creator: String = ""
var version: String = ""
var source_path: String = ""
var audio_path: String = ""
var background_path: String = ""
var preview_time: float = -1.0
var mode: int = 1
var od: float = 5.0
var hp: float = 5.0
var slider_multiplier: float = 1.4
var slider_tick_rate: float = 1.0
var notes: Array[Note] = []
var timing_points: Array[TimingPoint] = []
var main_bpm: float = 120.0
var converted: bool = false ## true when built from a non-taiko osu! map


func reset_runtime() -> void:
	for n in notes:
		n.reset_runtime()


func regular_note_count() -> int:
	var c := 0
	for n in notes:
		if n.is_regular():
			c += 1
	return c


func first_note_time() -> float:
	if notes.is_empty():
		return 0.0
	return notes[0].time


func last_time() -> float:
	var t := 0.0
	for n in notes:
		t = maxf(t, maxf(n.time, n.end_time))
	return t


func uninherited_at(t: float) -> TimingPoint:
	var best: TimingPoint = null
	for tp in timing_points:
		if not tp.uninherited:
			continue
		if best == null or tp.time <= t + 0.001:
			best = tp
		if tp.time > t + 0.001:
			break
	return best


func beat_length_at(t: float) -> float:
	var tp := uninherited_at(t)
	return tp.beat_length if tp != null else 60000.0 / maxf(main_bpm, 1.0)


func bpm_at(t: float) -> float:
	return 60000.0 / maxf(beat_length_at(t), 1.0)


func sv_at(t: float) -> float:
	var sv := 1.0
	for tp in timing_points:
		if tp.time > t + 0.001:
			break
		if tp.uninherited:
			sv = 1.0
		else:
			sv = tp.sv
	return sv


func kiai_at(t: float) -> bool:
	var k := false
	for tp in timing_points:
		if tp.time > t + 0.001:
			break
		k = tp.kiai
	return k


## Scroll velocity multiplier relative to 120 BPM at SV 1.0 (one beat travels a fixed distance, like the arcade).
func velocity_at(t: float) -> float:
	return sv_at(t) * (bpm_at(t) / 120.0)


## Times (ms) of measure lines for rendering.
func bar_lines() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var end := last_time() + 2000.0
	var uninh: Array[TimingPoint] = []
	for tp in timing_points:
		if tp.uninherited:
			uninh.append(tp)
	for i in range(uninh.size()):
		var tp := uninh[i]
		var stop := end
		if i + 1 < uninh.size():
			stop = uninh[i + 1].time
		var step := tp.beat_length * maxf(1.0, float(tp.meter))
		if step < 50.0:
			continue
		var t := tp.time
		var guard := 0
		while t < stop - 0.5 and guard < 100000:
			out.append(t)
			t += step
			guard += 1
	return out


func sort_notes() -> void:
	notes.sort_custom(func(a: Note, b: Note) -> bool: return a.time < b.time)
	for i in range(notes.size()):
		notes[i].index = i


## Recomputes per-note scroll velocities from the timing points.
func compute_velocities() -> void:
	for n in notes:
		n.velocity = velocity_at(n.time)


## Duration weighted most common BPM.
func compute_main_bpm() -> void:
	var weights := {}
	var uninh: Array[TimingPoint] = []
	for tp in timing_points:
		if tp.uninherited:
			uninh.append(tp)
	if uninh.is_empty():
		return
	var end := last_time()
	for i in range(uninh.size()):
		var stop := end
		if i + 1 < uninh.size():
			stop = uninh[i + 1].time
		var dur := maxf(0.0, stop - uninh[i].time)
		var bpm := snappedf(60000.0 / maxf(uninh[i].beat_length, 1.0), 0.01)
		weights[bpm] = weights.get(bpm, 0.0) + dur
	var best_bpm := 0.0
	var best_w := -1.0
	for bpm in weights:
		if weights[bpm] > best_w:
			best_w = weights[bpm]
			best_bpm = bpm
	if best_bpm > 0.0:
		main_bpm = best_bpm
	else:
		main_bpm = 60000.0 / maxf(uninh[0].beat_length, 1.0)


func display_title() -> String:
	return title if title != "" else "Untitled"


func display_artist() -> String:
	return artist if artist != "" else "Unknown artist"
