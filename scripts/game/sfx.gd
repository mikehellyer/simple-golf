class_name Sfx
extends Node
## Sound effects synthesised at startup, so there are no audio files to ship.

const RATE := 22050
const VOICES := 10

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _birds: AudioStreamPlayer
var _birds_on := false
var _next_bird := 0.0
## Seconds between occasional birdsong, and how quietly it plays.
const BIRD_GAP := Vector2(25.0, 60.0)
const BIRD_VOLUME := -20.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1991
	_streams = {
		swing = _wav(_swing()),
		hit_wood = _wav(_hit(180.0, 0.16, 0.0)),
		hit_iron = _wav(_hit(240.0, 0.12, 2300.0)),
		putt = _wav(_putt()),
		bounce_grass = _wav(_thud(110.0, 0.09, 900.0)),
		bounce_green = _wav(_thud(160.0, 0.06, 1400.0)),
		bunker = _wav(_sand()),
		tree = _wav(_rustle()),
		splash = _wav(_splash()),
		cup = _wav(_cup()),
		lip = _wav(_ping(2600.0, 0.05, 0.4)),
		tick = _wav(_ping(1800.0, 0.015, 0.25)),
		applause = _wav(_applause(3.5, 90.0)),
		polite = _wav(_applause(2.0, 25.0)),
	}
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in 3:
		_streams["bird%d" % i] = _wav(_chirp(i))
	_birds = AudioStreamPlayer.new()
	_birds.volume_db = BIRD_VOLUME
	add_child(_birds)


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Outdoors, a bird sings now and then; indoors (the clubhouse) it's quiet.
func set_birds(on: bool) -> void:
	_birds_on = on
	_next_bird = _rng.randf_range(BIRD_GAP.x * 0.3, BIRD_GAP.y * 0.5)


func _process(delta: float) -> void:
	if not _birds_on:
		return
	_next_bird -= delta
	if _next_bird <= 0.0:
		_next_bird = _rng.randf_range(BIRD_GAP.x, BIRD_GAP.y)
		_birds.stream = _streams["bird%d" % _rng.randi_range(0, 2)]
		_birds.pitch_scale = _rng.randf_range(0.9, 1.1)
		_birds.play()


func toggle_mute() -> bool:
	var muted := not AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, muted)
	return muted


# --- Synthesis -------------------------------------------------------------

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


static func _lp_coeff(cutoff: float) -> float:
	return 1.0 - exp(-TAU * cutoff / RATE)


## Air rushing past the club: noise through a lowpass that opens and closes.
func _swing() -> PackedFloat32Array:
	var b := _buffer(0.4)
	var y := 0.0
	for i in b.size():
		var t := float(i) / b.size()
		var env := sin(t * PI) ** 2
		y += _lp_coeff(300.0 + 2500.0 * env) * (_rng.randf_range(-1.0, 1.0) - y)
		b[i] = y * env * 1.6
	return b


## Club on ball: a sharp click, a body thump and (for irons) a metallic ring.
func _hit(body_hz: float, length: float, ring_hz: float) -> PackedFloat32Array:
	var b := _buffer(length)
	for i in b.size():
		var t := float(i) / RATE
		var s := _rng.randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.9
		s += sin(TAU * body_hz * t) * exp(-t * 40.0) * 0.6
		if ring_hz > 0.0:
			s += sin(TAU * ring_hz * t) * exp(-t * 60.0) * 0.25
		b[i] = s
	return b


func _putt() -> PackedFloat32Array:
	var b := _buffer(0.08)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 950.0 * t) * exp(-t * 90.0) * 0.5 \
				+ _rng.randf_range(-1.0, 1.0) * exp(-t * 600.0) * 0.3
	return b


func _thud(body_hz: float, length: float, cutoff: float) -> PackedFloat32Array:
	var b := _buffer(length)
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y += _lp_coeff(cutoff) * (_rng.randf_range(-1.0, 1.0) - y)
		b[i] = (y * 1.5 + sin(TAU * body_hz * t) * 0.5) * exp(-t * 45.0)
	return b


func _sand() -> PackedFloat32Array:
	var b := _buffer(0.3)
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y += _lp_coeff(2500.0) * (_rng.randf_range(-1.0, 1.0) - y)
		b[i] = y * minf(t * 200.0, 1.0) * exp(-t * 12.0) * 1.2
	return b


## Leaves: bursts of crackle, plus a knock if it hit wood.
func _rustle() -> PackedFloat32Array:
	var b := _buffer(0.6)
	var gate := 0.0
	var prev := 0.0
	for i in b.size():
		var t := float(i) / RATE
		if i % 220 == 0:
			gate = _rng.randf() * exp(-t * 5.0)
		var n := _rng.randf_range(-1.0, 1.0)
		var hp := n - prev
		prev = n
		b[i] = hp * gate * 0.45 + sin(TAU * 420.0 * t) * exp(-t * 35.0) * 0.35
	return b


func _splash() -> PackedFloat32Array:
	var b := _buffer(0.9)
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y += _lp_coeff(3500.0 * exp(-t * 3.0) + 300.0) * (_rng.randf_range(-1.0, 1.0) - y)
		b[i] = y * minf(t * 150.0, 1.0) * exp(-t * 4.0) * 1.8
	return b


## Ball dropping in: a couple of rattles off the cup and a hollow thunk.
func _cup() -> PackedFloat32Array:
	var b := _buffer(0.35)
	var strikes := [[0.0, 1300.0, 0.5], [0.055, 900.0, 0.35], [0.1, 700.0, 0.25]]
	for i in b.size():
		var t := float(i) / RATE
		var s := 0.0
		for st in strikes:
			var dt: float = t - st[0]
			if dt >= 0.0:
				s += sin(TAU * st[1] * dt) * exp(-dt * 70.0) * st[2]
		if t > 0.12:
			s += sin(TAU * 140.0 * (t - 0.12)) * exp(-(t - 0.12) * 25.0) * 0.5
		b[i] = s
	return b


func _ping(hz: float, length: float, level: float) -> PackedFloat32Array:
	var b := _buffer(length)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * hz * t) * exp(-t * 5.0 / length) * level
	return b


## Many people clapping: short band-limited noise bursts at random times.
func _applause(seconds: float, claps_per_second: float) -> PackedFloat32Array:
	var b := _buffer(seconds)
	var clap := PackedFloat32Array()
	clap.resize(int(0.012 * RATE))
	var y := 0.0
	var prev := 0.0
	for i in clap.size():
		var n := _rng.randf_range(-1.0, 1.0)
		y += _lp_coeff(4000.0) * (n - y)
		clap[i] = (y - prev) * 6.0 * exp(-float(i) / clap.size() * 4.0)
		prev = y
	var count := int(seconds * claps_per_second)
	for c in count:
		var start := _rng.randi_range(0, b.size() - clap.size() - 1)
		var t := float(start) / b.size()
		# Swells quickly, then fades.
		var env := minf(t * 8.0, 1.0) * (1.0 - t) ** 1.5 * _rng.randf_range(0.3, 1.0)
		var pitch := _rng.randf_range(0.7, 1.3)
		for k in clap.size():
			var idx := start + int(k * pitch)
			if idx < b.size():
				b[idx] += clap[k] * env * 0.3
	return b


## A short birdsong phrase: a few quick whistled notes.
func _chirp(variant: int) -> PackedFloat32Array:
	var b := _buffer(0.7)
	var base: float = [3300.0, 2800.0, 3900.0][variant]
	var notes: int = [3, 4, 2][variant]
	for n in notes:
		var t0 := n * 0.13
		var phase := 0.0
		var length := int(0.09 * RATE)
		for i in length:
			var idx := int(t0 * RATE) + i
			if idx >= b.size():
				break
			var u := float(i) / length
			# Each note sweeps up then down a little, like a whistle.
			phase += TAU * base * (1.0 + 0.2 * sin(u * PI) - 0.05 * n) / RATE
			b[idx] += sin(phase) * sin(u * PI) * 0.35
	return b
