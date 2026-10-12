extends RefCounted
## Procedural audio for Brickfall: every sound effect and the ambient music loop are
## synthesised from sine waves and noise at startup, so the project ships no audio files.
## build_all() is slow (a few seconds), so main.gd runs it on a background thread.

const SR := 22050 # sound effects
const MUSIC_SR := 11025 # ambient loop (soft pads, so a lower rate is fine)


static func build_all() -> Dictionary:
	return {"sfx": build_sfx(), "music": build_music()}


# ---- helpers
static func to_wav(data: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	var peak := 0.0
	for v in data:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i] * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w


static func make_buf(seconds: float, rate: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(seconds * rate))
	return a


## Adds a decaying tone made of sine partials: [[ratio, amplitude], ...].
static func add_tone(b: PackedFloat32Array, rate: int, start: float, dur: float, freq: float, amp: float, decay: float, partials: Array = [[1.0, 1.0]]) -> void:
	var si := int(start * rate)
	var n := mini(int(dur * rate), b.size() - si)
	for i in n:
		var t := float(i) / rate
		var env := exp(-decay * t) * minf(1.0, t / 0.004)
		var s := 0.0
		for p in partials:
			s += p[1] * sin(TAU * freq * p[0] * t)
		b[si + i] += amp * env * s


## Adds a frequency sweep (exponential glide from f0 to f1).
static func add_sweep(b: PackedFloat32Array, rate: int, start: float, dur: float, f0: float, f1: float, amp: float, decay: float) -> void:
	var si := int(start * rate)
	var n := mini(int(dur * rate), b.size() - si)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var f := f0 * pow(f1 / f0, t / dur)
		ph += TAU * f / rate
		var env := exp(-decay * t) * minf(1.0, t / 0.004) * minf(1.0, (dur - t) / 0.02)
		b[si + i] += amp * env * (sin(ph) + 0.3 * sin(2.0 * ph))


## Adds a burst of noise. highpass=true keeps it bright and glassy.
static func add_noise(b: PackedFloat32Array, rate: int, start: float, dur: float, amp: float, decay: float, rng: RandomNumberGenerator, highpass := true) -> void:
	var si := int(start * rate)
	var n := mini(int(dur * rate), b.size() - si)
	var prev := 0.0
	for i in n:
		var t := float(i) / rate
		var x := rng.randf() * 2.0 - 1.0
		var y := x - prev if highpass else x
		prev = x
		b[si + i] += amp * y * 0.6 * exp(-decay * t)


static func arp(b: PackedFloat32Array, rate: int, notes: Array, step: float, amp: float, decay: float) -> void:
	for k in notes.size():
		add_tone(b, rate, k * step, 0.5, notes[k], amp, decay, [[1.0, 1.0], [2.0, 0.3], [3.0, 0.1]])


# ---- sound effects
static func build_sfx() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var d := {}
	var b: PackedFloat32Array

	# paddle: soft marimba thunk
	b = make_buf(0.2, SR)
	add_tone(b, SR, 0.0, 0.2, 260.0, 0.7, 16.0, [[1.0, 1.0], [2.0, 0.35], [3.0, 0.12]])
	d["paddle"] = to_wav(b, SR)

	# wall: quieter, lower tick
	b = make_buf(0.1, SR)
	add_tone(b, SR, 0.0, 0.1, 185.0, 0.5, 38.0, [[1.0, 1.0], [2.0, 0.3]])
	d["wall"] = to_wav(b, SR)

	# crystal ping: a brick that cracked but did not break
	b = make_buf(0.3, SR)
	add_tone(b, SR, 0.0, 0.3, 1760.0, 0.32, 20.0, [[1.0, 1.0], [1.5, 0.5], [2.76, 0.25]])
	add_noise(b, SR, 0.0, 0.01, 0.35, 300.0, rng)
	d["ping"] = to_wav(b, SR)

	# crystal crash: one variant per brick row, each tuned to a pentatonic note
	var bases := [988.0, 880.0, 784.0, 659.0, 587.0, 523.0]
	var ratios := [1.0, 1.125, 1.5, 1.68, 2.0, 2.5]
	for row in 6:
		b = make_buf(1.2, SR)
		add_noise(b, SR, 0.0, 0.55, 0.55, 9.0, rng)
		add_noise(b, SR, 0.0, 0.12, 0.4, 45.0, rng)
		add_tone(b, SR, 0.0, 0.25, 95.0, 0.5, 26.0)
		for k in 6:
			var f: float = bases[row] * ratios[k]
			add_tone(b, SR, k * 0.025 + rng.randf() * 0.03, 1.0, f, 0.13, 5.0 + rng.randf() * 3.0, [[1.0, 1.0], [2.76, 0.18]])
		d["shatter%d" % row] = to_wav(b, SR)

	# multi-hit brick loses a layer: glass crack with a falling chime
	b = make_buf(0.45, SR)
	add_noise(b, SR, 0.0, 0.1, 0.5, 45.0, rng)
	add_sweep(b, SR, 0.0, 0.14, 2800.0, 900.0, 0.25, 14.0)
	add_tone(b, SR, 0.0, 0.4, 2093.0, 0.22, 16.0, [[1.0, 1.0], [2.76, 0.3]])
	add_tone(b, SR, 0.03, 0.4, 3136.0, 0.14, 18.0, [[1.0, 1.0], [2.0, 0.2]])
	d["layer"] = to_wav(b, SR)

	# boss bolt: short electric zap
	b = make_buf(0.28, SR)
	add_sweep(b, SR, 0.0, 0.22, 1500.0, 260.0, 0.35, 8.0)
	add_noise(b, SR, 0.0, 0.05, 0.25, 40.0, rng)
	d["zap"] = to_wav(b, SR)

	# armored brick: dull metallic clang
	b = make_buf(0.35, SR)
	add_tone(b, SR, 0.0, 0.35, 540.0, 0.45, 14.0, [[1.0, 1.0], [2.4, 0.6], [3.9, 0.35], [5.4, 0.2]])
	add_noise(b, SR, 0.0, 0.015, 0.3, 200.0, rng)
	d["clang"] = to_wav(b, SR)

	# explosive brick: deep boom with a crackle
	b = make_buf(1.1, SR)
	add_sweep(b, SR, 0.0, 0.8, 170.0, 38.0, 0.8, 4.0)
	add_noise(b, SR, 0.0, 0.6, 0.6, 7.0, rng, false)
	add_noise(b, SR, 0.0, 0.2, 0.4, 25.0, rng)
	d["boom"] = to_wav(b, SR)

	# launch: rising whoosh
	b = make_buf(0.3, SR)
	add_sweep(b, SR, 0.0, 0.26, 280.0, 900.0, 0.35, 7.0)
	d["launch"] = to_wav(b, SR)

	# power-ups: bright arpeggios
	b = make_buf(0.8, SR)
	arp(b, SR, [523.25, 659.25, 783.99, 1046.5], 0.07, 0.3, 8.0)
	d["power_w"] = to_wav(b, SR)
	b = make_buf(0.8, SR)
	arp(b, SR, [392.0, 493.88, 587.33, 783.99, 987.77], 0.055, 0.3, 8.0)
	d["power_m"] = to_wav(b, SR)

	# lost a life: falling sweep
	b = make_buf(0.9, SR)
	add_sweep(b, SR, 0.0, 0.75, 440.0, 90.0, 0.45, 3.0)
	d["lose"] = to_wav(b, SR)

	# game over: slow falling minor line
	b = make_buf(2.6, SR)
	var go := [220.0, 174.61, 146.83, 110.0]
	for k in go.size():
		add_tone(b, SR, k * 0.45, 1.2, go[k], 0.33, 2.8, [[1.0, 1.0], [2.0, 0.4], [3.0, 0.15]])
	d["gameover"] = to_wav(b, SR)

	# level clear / win: rising arpeggio then a held chord
	b = make_buf(2.4, SR)
	arp(b, SR, [523.25, 659.25, 783.99, 1046.5, 1318.5], 0.11, 0.3, 4.0)
	for f in [523.25, 659.25, 783.99, 1046.5]:
		add_tone(b, SR, 0.6, 1.6, f, 0.14, 2.2, [[1.0, 1.0], [2.0, 0.25]])
	d["clear"] = to_wav(b, SR)

	# pause / mute: short blip
	b = make_buf(0.1, SR)
	add_tone(b, SR, 0.0, 0.1, 660.0, 0.4, 28.0, [[1.0, 1.0], [2.0, 0.3]])
	d["pause"] = to_wav(b, SR)

	return d


# ---- ambient music loop (24 s, four chords, soft pads with a slow bell melody)
static func build_music() -> AudioStreamWAV:
	var rate := MUSIC_SR
	var chord_len := 6.0
	var loop_len := chord_len * 4.0
	var n := int(loop_len * rate)
	var b := PackedFloat32Array()
	b.resize(n)

	# Am9 - Fmaj7 - Cmaj7 - G6 (MIDI note numbers)
	var chords := [[45, 52, 59, 64], [41, 48, 57, 64], [48, 55, 59, 64], [43, 50, 59, 67]]
	for ci in chords.size():
		for m in chords[ci]:
			var f := 440.0 * pow(2.0, (float(m) - 69.0) / 12.0)
			var amp := 0.05 if m < 50 else 0.034
			add_pad(b, rate, ci * chord_len, chord_len, f, amp)

	# bells: a pentatonic melody that fits over every chord, each with two soft echoes
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var pent := [69, 72, 74, 76, 79, 81]
	for k in 12:
		var t0 := k * 2.0 + rng.randf() * 0.9
		var m: int = pent[rng.randi() % pent.size()]
		var f := 440.0 * pow(2.0, (float(m) - 69.0) / 12.0)
		for e in 3:
			add_bell(b, rate, t0 + e * 0.52, f, 0.05 * pow(0.45, e))

	# gentle one-pole low-pass (two passes so the loop seam is smooth)
	var y := 0.0
	var peak := 0.0
	for pass_i in 2:
		for i in n:
			y += 0.4 * (b[i] - y)
			b[i] = y
			peak = maxf(peak, absf(y))
	var g := 0.5 / maxf(peak, 0.001)
	for i in n:
		b[i] *= g
	return to_wav(b, rate, true)


static func add_pad(b: PackedFloat32Array, rate: int, start: float, hold: float, freq: float, amp: float) -> void:
	var n := b.size()
	var release := 2.6
	var total := int((hold + release) * rate)
	var si := int(start * rate)
	var w1 := TAU * freq / rate
	var w2 := TAU * freq * 1.004 / rate
	var p1 := 0.0
	var p2 := 0.7
	for i in total:
		var t := float(i) / rate
		var a := clampf(t / 1.8, 0.0, 1.0)
		a = a * a * (3.0 - 2.0 * a)
		var r := 1.0
		if t > hold:
			r = clampf(1.0 - (t - hold) / release, 0.0, 1.0)
			r *= r
		p1 += w1
		p2 += w2
		b[(si + i) % n] += amp * a * r * (sin(p1) + 0.6 * sin(p2)) * (1.0 + 0.15 * sin(TAU * 0.17 * t))


static func add_bell(b: PackedFloat32Array, rate: int, start: float, freq: float, amp: float) -> void:
	var n := b.size()
	var si := int(start * rate) % n
	var len := int(2.4 * rate)
	for i in len:
		var t := float(i) / rate
		var env := exp(-1.9 * t) * minf(1.0, t / 0.006)
		var s := sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.76 * t) * exp(-2.0 * t)
		b[(si + i) % n] += amp * env * s
