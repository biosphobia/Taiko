#!/usr/bin/env python3
"""Generates all bundled audio assets for TaikoMove: sound effects and demo songs (audio + osu!taiko charts).
Everything is synthesized, so the repository stays free of third-party audio.
Run from the repo root:  python3 tools/generate_assets.py
"""
import os, math, random
import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 44100

def env(n, attack=0.002, decay=0.1, sr=SR):
    t = np.arange(n) / sr
    a = np.minimum(1.0, t / max(attack, 1e-5))
    d = np.exp(-t / max(decay, 1e-5))
    return a * d

def kick(dur=0.25, f0=150, f1=50, amp=1.0):
    n = int(dur * SR); t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t * 30)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) * env(n, 0.001, 0.09)
    click = np.random.randn(n) * env(n, 0.0005, 0.004) * 0.4
    return amp * (x + click)

def snare(dur=0.2, amp=0.8):
    n = int(dur * SR); t = np.arange(n) / SR
    noise = np.random.randn(n) * env(n, 0.001, 0.06)
    tone = np.sin(2 * np.pi * 190 * t) * env(n, 0.001, 0.05)
    return amp * (0.7 * noise + 0.5 * tone)

def hat(dur=0.06, amp=0.3):
    n = int(dur * SR)
    noise = np.random.randn(n)
    # crude high-pass via differencing
    noise = np.diff(noise, prepend=0.0)
    return amp * noise * env(n, 0.0005, 0.02)

def tone(freq, dur, amp=0.3, wave="saw", decay=0.25):
    n = int(dur * SR); t = np.arange(n) / SR
    if wave == "saw":
        x = 2 * (t * freq - np.floor(0.5 + t * freq))
    elif wave == "square":
        x = np.sign(np.sin(2 * np.pi * freq * t))
    else:
        x = np.sin(2 * np.pi * freq * t)
    return amp * x * env(n, 0.005, decay)

def add(buf, x, at):
    i = int(at * SR)
    if i < 0: return
    end = min(len(buf), i + len(x))
    if end > i:
        buf[i:end] += x[:end - i]

def write_ogg(path, x, sr=SR):
    """libsndfile's vorbis encoder crashes on large single writes; stream it in blocks."""
    x = np.asarray(x, dtype=np.float32)
    with sf.SoundFile(path, "w", sr, 1, format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(x), 8192):
            f.write(x[i:i + 8192])

def normalize(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return (x / m * peak).astype(np.float32)

# ------------------------------------------------------------------ SFX
def gen_sfx():
    out = os.path.join(ROOT, "assets", "sfx")
    os.makedirs(out, exist_ok=True)
    np.random.seed(1)
    # Don: deep taiko thump
    n = int(0.28 * SR); t = np.arange(n) / SR
    f = 55 + 140 * np.exp(-t * 35)
    don = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.11)
    don += np.random.randn(n) * env(n, 0.0005, 0.006) * 0.5
    sf.write(os.path.join(out, "don.wav"), normalize(don), SR, subtype="PCM_16")
    # Ka: rim click, bright and short
    n = int(0.14 * SR); t = np.arange(n) / SR
    ka = np.random.randn(n) * env(n, 0.0005, 0.02)
    ka = np.diff(ka, prepend=0.0)
    ka += 0.6 * np.sin(2 * np.pi * 1450 * t) * env(n, 0.0005, 0.03)
    ka += 0.3 * np.sin(2 * np.pi * 3100 * t) * env(n, 0.0005, 0.015)
    sf.write(os.path.join(out, "ka.wav"), normalize(ka), SR, subtype="PCM_16")
    # Balloon pop
    n = int(0.3 * SR); t = np.arange(n) / SR
    pop = np.random.randn(n) * env(n, 0.0005, 0.05) + np.sin(2 * np.pi * (300 + 900 * np.exp(-t * 20)) * t) * env(n, 0.001, 0.08)
    sf.write(os.path.join(out, "pop.wav"), normalize(pop), SR, subtype="PCM_16")
    # Metronome tick (calibration)
    n = int(0.05 * SR); t = np.arange(n) / SR
    tick = np.sin(2 * np.pi * 2000 * t) * env(n, 0.0005, 0.012)
    sf.write(os.path.join(out, "tick.wav"), normalize(tick), SR, subtype="PCM_16")
    n = int(0.08 * SR); t = np.arange(n) / SR
    tick2 = np.sin(2 * np.pi * 3000 * t) * env(n, 0.0005, 0.02)
    sf.write(os.path.join(out, "tick_accent.wav"), normalize(tick2), SR, subtype="PCM_16")
    # UI sounds
    n = int(0.08 * SR); t = np.arange(n) / SR
    mv = np.sin(2 * np.pi * 880 * t) * env(n, 0.001, 0.03)
    sf.write(os.path.join(out, "ui_move.wav"), normalize(mv, 0.5), SR, subtype="PCM_16")
    n = int(0.25 * SR); t = np.arange(n) / SR
    sel = (np.sin(2 * np.pi * 660 * t) + 0.5 * np.sin(2 * np.pi * 990 * t)) * env(n, 0.001, 0.09)
    sf.write(os.path.join(out, "ui_select.wav"), normalize(sel, 0.6), SR, subtype="PCM_16")
    n = int(0.6 * SR); t = np.arange(n) / SR
    clr = sum(np.sin(2 * np.pi * fr * t) * env(n, 0.002, 0.25) for fr in (523, 659, 784, 1046))
    sf.write(os.path.join(out, "clear.wav"), normalize(clr, 0.7), SR, subtype="PCM_16")
    n = int(0.5 * SR); t = np.arange(n) / SR
    fail = (np.sin(2 * np.pi * 220 * t) + np.sin(2 * np.pi * 233 * t)) * env(n, 0.002, 0.2)
    sf.write(os.path.join(out, "fail.wav"), normalize(fail, 0.6), SR, subtype="PCM_16")
    # Unlock/purchase
    n = int(0.5 * SR); t = np.arange(n) / SR
    un = sum(np.sin(2 * np.pi * fr * t) * env(n, 0.002, 0.18) * (0.6 ** k) for k, fr in enumerate((784, 1175, 1568)))
    sf.write(os.path.join(out, "unlock.wav"), normalize(un, 0.6), SR, subtype="PCM_16")

# ------------------------------------------------------------------ SONGS
SCALES = {
    "pent": [0, 2, 4, 7, 9],
    "minor": [0, 2, 3, 5, 7, 8, 10],
}

def note_hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)

def gen_song(name, title, artist, bpm, beats, seed, root_midi=45, scale="pent"):
    """Synthesizes a song with drums/bass/lead on a strict beat grid and builds charts from the same grid.
    Returns (audio, charts) where charts is a dict difficulty -> list of note dicts."""
    random.seed(seed); np.random.seed(seed)
    beat = 60.0 / bpm
    lead_in = 2.0  # seconds of silence before the first beat, so the first notes are reachable
    total = lead_in + beats * beat + 2.0
    n = int(total * SR)
    audio = np.zeros(n)
    sc = SCALES[scale]
    # chord progression per 4 bars
    prog = [0, 5, 3, 4]
    events = []  # (time_s, kind) kind: 'don','ka','don_big','ka_big'
    for b in range(beats):
        t = lead_in + b * beat
        bar = b // 4
        pos = b % 4
        # drums: kick on 1 and 3, snare on 2 and 4, hats on 8ths
        if pos in (0, 2):
            add(audio, kick(), t)
            events.append((t, "don"))
        if pos in (1, 3):
            add(audio, snare(), t)
            events.append((t, "ka"))
        for h in range(2):
            add(audio, hat(), t + h * beat / 2)
        # extra kick on the "and" of 3 in every second bar
        if pos == 2 and bar % 2 == 1:
            add(audio, kick(amp=0.8), t + beat / 2)
            events.append((t + beat / 2, "don"))
        # big accent at the start of each 4-bar phrase
        if pos == 0 and bar % 4 == 0 and bar > 0:
            add(audio, kick(dur=0.4, amp=1.2), t)
            add(audio, snare(dur=0.3, amp=0.9), t)
            events.append((t, "don_big"))
        # bass
        chord_root = root_midi + sc[prog[bar % 4] % len(sc)]
        add(audio, tone(note_hz(chord_root), beat * 0.9, amp=0.25, wave="saw", decay=0.3), t)
        if pos % 2 == 1:
            add(audio, tone(note_hz(chord_root + 12), beat * 0.4, amp=0.15, wave="square", decay=0.12), t + beat / 2)
        # lead melody on 8ths in the second half of each 8-bar section
        if (bar % 8) >= 4:
            for h in range(2):
                deg = random.choice(sc)
                add(audio, tone(note_hz(root_midi + 24 + deg), beat * 0.45, amp=0.12, wave="square", decay=0.15), t + h * beat / 2)
    # final hit
    t_end = lead_in + beats * beat
    add(audio, kick(dur=0.5, amp=1.3), t_end)
    add(audio, snare(dur=0.4), t_end)
    events.append((t_end, "don_big"))
    audio = normalize(audio, 0.85)

    # Charts. Times in ms. Easy: only downbeats/backbeats subset; Normal: all events; Hard: adds 8th-note fills and rolls.
    def ms(x): return int(round(x * 1000))
    charts = {}
    events.sort()
    charts["Easy"] = [{"t": ms(t), "k": k} for (t, k) in events if abs(((t - lead_in) / beat) % 2) < 1e-6 or k.endswith("big")]
    charts["Normal"] = [{"t": ms(t), "k": k} for (t, k) in events]
    hard = [{"t": ms(t), "k": k} for (t, k) in events]
    # fills: 8th-note runs in the last bar of every 8-bar phrase, and a drumroll in bar 4 of each 16
    bars = beats // 4
    for bar in range(bars):
        if bar % 8 == 7:
            t0 = lead_in + bar * 4 * beat
            for i in range(8):
                tt = t0 + i * beat / 2
                if not any(abs(e["t"] - ms(tt)) < 5 for e in hard):
                    hard.append({"t": ms(tt), "k": "ka" if i % 2 else "don"})
        if bar % 16 == 3:
            t0 = lead_in + bar * 4 * beat + 2 * beat
            hard = [e for e in hard if not (ms(t0) <= e["t"] <= ms(t0 + 2 * beat))]
            hard.append({"t": ms(t0), "k": "roll", "end": ms(t0 + 2 * beat - beat / 4)})
        if bar % 16 == 11:
            t0 = lead_in + bar * 4 * beat
            hard = [e for e in hard if not (ms(t0) <= e["t"] <= ms(t0 + 4 * beat))]
            hard.append({"t": ms(t0), "k": "balloon", "end": ms(t0 + 4 * beat - beat / 4), "hits": 12})
    hard.sort(key=lambda e: e["t"])
    charts["Hard"] = hard
    return audio, charts, lead_in, beat

def write_osu(path, title, artist, version, audio_file, bpm, lead_in_ms, notes, od):
    lines = []
    lines.append("osu file format v14")
    lines.append("")
    lines.append("[General]")
    lines.append(f"AudioFilename: {audio_file}")
    lines.append("AudioLeadIn: 0")
    lines.append(f"PreviewTime: {lead_in_ms + 8000}")
    lines.append("Countdown: 0")
    lines.append("SampleSet: Normal")
    lines.append("StackLeniency: 0.7")
    lines.append("Mode: 1")
    lines.append("LetterboxInBreaks: 0")
    lines.append("")
    lines.append("[Metadata]")
    lines.append(f"Title:{title}")
    lines.append(f"TitleUnicode:{title}")
    lines.append(f"Artist:{artist}")
    lines.append(f"ArtistUnicode:{artist}")
    lines.append("Creator:TaikoMove")
    lines.append(f"Version:{version}")
    lines.append("Source:")
    lines.append("Tags:taikomove bundled")
    lines.append("BeatmapID:0")
    lines.append("BeatmapSetID:-1")
    lines.append("")
    lines.append("[Difficulty]")
    lines.append("HPDrainRate:5")
    lines.append("CircleSize:5")
    lines.append(f"OverallDifficulty:{od}")
    lines.append("ApproachRate:5")
    lines.append("SliderMultiplier:1.4")
    lines.append("SliderTickRate:1")
    lines.append("")
    lines.append("[Events]")
    lines.append("//Background and Video events")
    lines.append("//Break Periods")
    lines.append("")
    lines.append("[TimingPoints]")
    beat_len = 60000.0 / bpm
    lines.append(f"{lead_in_ms},{beat_len:.6f},4,1,0,80,1,0")
    lines.append("")
    lines.append("[HitObjects]")
    for e in notes:
        k = e["k"]
        if k in ("don", "ka", "don_big", "ka_big"):
            hs = 0
            if k.startswith("ka"): hs |= 8
            if k.endswith("big"): hs |= 4
            lines.append(f"256,192,{e['t']},1,{hs},0:0:0:0:")
        elif k == "roll":
            # slider: duration = length / (SliderMultiplier*100*SV) * beatLength ; SV = 1 here
            dur = e["end"] - e["t"]
            length = dur / beat_len * 1.4 * 100.0
            lines.append(f"256,192,{e['t']},2,0,L|512:192,1,{length:.3f}")
        elif k == "balloon":
            lines.append(f"256,192,{e['t']},12,0,{e['end']},0:0:0:0:")
    lines.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

def gen_songs():
    songs_dir = os.path.join(ROOT, "songs")
    os.makedirs(songs_dir, exist_ok=True)
    specs = [
        ("first_beat", "First Beat", "TaikoMove", 120, 64 * 2, 11, 45, "pent"),
        ("neon_festival", "Neon Festival", "TaikoMove", 150, 64 * 2, 23, 43, "minor"),
        ("thunder_run", "Thunder Run", "TaikoMove", 180, 64 * 2, 37, 41, "pent"),
    ]
    manifest = []
    for folder, title, artist, bpm, beats, seed, root, scale in specs:
        d = os.path.join(songs_dir, folder)
        os.makedirs(d, exist_ok=True)
        audio, charts, lead_in, beat = gen_song(folder, title, artist, bpm, beats, seed, root, scale)
        write_ogg(os.path.join(d, "audio.ogg"), audio)
        for version, od in (("Easy", 4), ("Normal", 5.5), ("Hard", 7)):
            fn = f"{artist} - {title} (TaikoMove) [{version}].osu"
            write_osu(os.path.join(d, fn), title, artist, version, "audio.ogg", bpm, int(round(lead_in * 1000)), charts[version], od)
            manifest.append(f"{folder}/{fn}")
    # calibration track: 120 BPM metronome, 32 beats, accented every 4
    d = os.path.join(songs_dir, "calibration"); os.makedirs(d, exist_ok=True)
    bpm = 120; beat = 0.5; lead_in = 2.0; beats = 32
    n = int((lead_in + beats * beat + 1.0) * SR); audio = np.zeros(n)
    notes = []
    for b in range(beats):
        t = lead_in + b * beat
        nn = int(0.06 * SR); tt = np.arange(nn) / SR
        f = 3000 if b % 4 == 0 else 2000
        add(audio, np.sin(2 * np.pi * f * tt) * env(nn, 0.0005, 0.015), t)
        notes.append({"t": int(round(t * 1000)), "k": "don" if b % 4 != 3 else "ka"})
    write_ogg(os.path.join(d, "audio.ogg"), normalize(audio, 0.8))
    fn = "TaikoMove - Offset Calibration (TaikoMove) [Metronome].osu"
    write_osu(os.path.join(d, fn), "Offset Calibration", "TaikoMove", "Metronome", "audio.ogg", bpm, int(lead_in * 1000), notes, 5)
    manifest.append(f"calibration/{fn}")
    with open(os.path.join(songs_dir, "manifest.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(manifest) + "\n")

if __name__ == "__main__":
    gen_sfx()
    gen_songs()
    print("assets generated")
