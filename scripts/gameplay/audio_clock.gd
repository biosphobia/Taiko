class_name AudioClock
extends Node
## Song clock based on the monotonic system clock, drift-corrected against the audio output position.
## Any timestamped hit (Time.get_ticks_usec) can be converted to a song time without frame quantization.

var player: AudioStreamPlayer
var started := false
var audio_started := false
var paused := false
var lead_in_ms := 2000.0
var _start_ticks := 0
var _offset_ms := 0.0 ## drift correction added to the model
var _pause_ticks := 0
var _stream_length_ms := 0.0
var _last_measured := 0.0
var drift_ms := 0.0 ## last measured audio-vs-model difference (for diagnostics)


func _ready() -> void:
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = "MusicPlayer"
		add_child(player)
	player.bus = "Master"
	set_process(true)


func setup(stream: AudioStream, p_lead_in_ms: float) -> void:
	player.stream = stream
	lead_in_ms = maxf(0.0, p_lead_in_ms)
	_stream_length_ms = stream.get_length() * 1000.0 if stream else 0.0
	player.volume_db = linear_to_db(clampf(float(Settings.get_value("volume_music")), 0.0001, 1.0))


func start() -> void:
	_start_ticks = Time.get_ticks_usec()
	_offset_ms = 0.0
	started = true
	audio_started = false
	paused = false


func stop() -> void:
	started = false
	audio_started = false
	if player.playing:
		player.stop()


## Song time (ms) at a given monotonic timestamp (usec).
func song_time_at(ticks_usec: int) -> float:
	if not started:
		return -lead_in_ms
	var ref := _pause_ticks if paused else ticks_usec
	return float(ref - _start_ticks) / 1000.0 - lead_in_ms + _offset_ms


func now_ms() -> float:
	return song_time_at(Time.get_ticks_usec())


## Inverse of song_time_at: the monotonic timestamp (usec) at which the song time equals ms.
func ticks_at(ms: float) -> int:
	return _start_ticks + int((ms + lead_in_ms - _offset_ms) * 1000.0)


func pause() -> void:
	if not started or paused:
		return
	paused = true
	_pause_ticks = Time.get_ticks_usec()
	if audio_started:
		player.stream_paused = true


func resume() -> void:
	if not paused:
		return
	var now := Time.get_ticks_usec()
	_start_ticks += now - _pause_ticks
	paused = false
	if audio_started:
		player.stream_paused = false


func audio_finished() -> bool:
	return audio_started and not player.playing and not paused


func _process(_delta: float) -> void:
	if not started or paused or player.stream == null:
		return
	var model := now_ms()
	if not audio_started:
		if model >= 0.0:
			# Start playback exactly at the model time so the frame quantization does not matter.
			player.play(model / 1000.0)
			audio_started = true
		return
	if not player.playing:
		return
	var measured := (player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * 1000.0
	if measured <= 0.0 or absf(measured - _last_measured) < 0.0001:
		return
	_last_measured = measured
	var diff := measured - model
	drift_ms = diff
	if absf(diff) > 60.0:
		_offset_ms += diff # snap on large discrepancies (stalls)
	else:
		_offset_ms += diff * 0.03 # slow PLL keeps the model locked to the audio clock without jitter
