extends Node

const MIX_RATE: float = 22050.0

var ambient_player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var phase_a: float = 0.0
var phase_b: float = 0.0
var phase_lfo: float = 0.0

var sfx: Dictionary = {}
var sfx_players: Array[AudioStreamPlayer] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	setup_audio_system()
	build_sfx()

# ---------- Ambient drone ----------
func setup_audio_system() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.25

	ambient_player = AudioStreamPlayer.new()
	ambient_player.stream = generator
	ambient_player.volume_db = -14.0
	add_child(ambient_player)
	ambient_player.play()

	playback = ambient_player.get_stream_playback() as AudioStreamGeneratorPlayback
	print("Atmospheric Audio Manager Initialized for Searchlight 3D.")

func _process(_delta: float) -> void:
	if playback == null:
		return

	var frames: int = playback.get_frames_available()
	for i in range(frames):
		phase_a = fposmod(phase_a + TAU * 55.0 / MIX_RATE, TAU)
		phase_b = fposmod(phase_b + TAU * 57.5 / MIX_RATE, TAU)
		phase_lfo = fposmod(phase_lfo + TAU * 0.15 / MIX_RATE, TAU)

		var swell: float = 0.65 + 0.35 * sin(phase_lfo)
		var s: float = (sin(phase_a) * 0.5 + sin(phase_b) * 0.4) * swell * 0.6
		playback.push_frame(Vector2(s, s))

# ---------- Sound effects (code se bane) ----------
func play_sfx(sfx_name: String, volume_db: float = 0.0) -> void:
	if not sfx.has(sfx_name):
		return
	for p in sfx_players:
		if not p.playing:
			p.stream = sfx[sfx_name]
			p.volume_db = volume_db
			p.play()
			return

# Koi bhi extension chalegi (mp3 / ogg / wav). File nahi mili to bina error ke null.
# base: "res://audio/door_open_sfx" (extension likhna zaruri nahi)
const AUDIO_EXTS: Array[String] = ["mp3", "ogg", "wav", "MP3", "OGG", "WAV"]

func load_audio(base: String) -> AudioStream:
	var b: String = base
	if base.get_extension() != "":
		b = base.get_basename()
	for e in AUDIO_EXTS:
		var p: String = b + "." + e
		if ResourceLoader.exists(p):
			var res = load(p)
			if res is AudioStream:
				return res
	return null

# User ki apni sound file bajao. File mili to true, nahi to false.
# Pehle tumhari file (base naam), na mile to code wali awaaz fallback se
func play_any(base: String, fallback: String, volume_db: float = 0.0) -> void:
	if not play_file(base, volume_db):
		play_sfx(fallback, volume_db)

func play_file(base: String, volume_db: float = 0.0) -> bool:
	var stream: AudioStream = load_audio(base)
	if stream == null:
		return false
	for p in sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return true
	return false

func build_sfx() -> void:
	for i in range(6):
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)

	sfx["rune"] = make_wav(chime([660.0, 990.0, 1320.0], 1.3))
	sfx["complete"] = make_wav(arpeggio([523.0, 659.0, 784.0, 1047.0], 0.2))
	sfx["click"] = make_wav(noise_burst(0.06, 60.0, 0.6, 0.0))
	sfx["step"] = make_wav(noise_burst(0.12, 30.0, 0.08, 70.0))
	sfx["scroll"] = make_wav(whoosh(0.7))
	sfx["door"] = make_wav(rumble(2.2))
	sfx["whisper"] = make_wav(whisper(3.0))
	sfx["creak"] = make_wav(creak(2.2))
	sfx["hit"] = make_wav(noise_burst(0.35, 9.0, 0.12, 55.0))
	sfx["slash"] = make_wav(whoosh(0.25))
	sfx["water"] = make_wav(water(4.0), true)

# Level 2 ke jharne ki awaaz ke liye stream
func get_sfx_stream(sfx_name: String) -> AudioStream:
	if sfx.has(sfx_name):
		return sfx[sfx_name]
	return null

func make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

func chime(freqs: Array, dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t: float = i / MIX_RATE
		var env: float = exp(-t * 3.5) * minf(1.0, t * 200.0)
		var s := 0.0
		for f in freqs:
			s += sin(TAU * float(f) * t)
		out[i] = s / freqs.size() * env * 0.6
	return out

func arpeggio(notes: Array, step: float) -> PackedFloat32Array:
	var n := int((step * notes.size() + 1.2) * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in range(notes.size()):
		var start := int(k * step * MIX_RATE)
		for i in range(start, n):
			var t: float = (i - start) / MIX_RATE
			out[i] += sin(TAU * float(notes[k]) * t) * exp(-t * 3.0) * minf(1.0, t * 200.0) * 0.35
	return out

func noise_burst(dur: float, decay: float, lowpass: float, thump_hz: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in range(n):
		var t: float = i / MIX_RATE
		last = lerpf(last, rng.randf_range(-1.0, 1.0), lowpass)
		var env: float = exp(-t * decay)
		var s: float = last * env
		if thump_hz > 0.0:
			s += sin(TAU * thump_hz * t) * env
		out[i] = s * 0.6
	return out

func whoosh(dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in range(n):
		var t: float = i / MIX_RATE
		var k: float = t / dur
		last = lerpf(last, rng.randf_range(-1.0, 1.0), lerpf(0.03, 0.35, k))
		var env: float = pow(sin(PI * k), 2.0)
		out[i] = last * env * 0.8
	return out

func rumble(dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var brown := 0.0
	for i in range(n):
		var t: float = i / MIX_RATE
		brown = brown * 0.98 + rng.randf_range(-1.0, 1.0) * 0.1
		var env: float = sin(PI * t / dur)
		out[i] = (brown * 1.5 + sin(TAU * 38.0 * t) * 0.5) * env * 0.7
	return out

func whisper(dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in range(n):
		var t: float = i / MIX_RATE
		var nz: float = rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, nz, 0.25)
		var breath: float = nz - lp
		var syll: float = clampf(sin(TAU * 3.1 * t + sin(TAU * 0.7 * t) * 2.0), 0.0, 1.0)
		var fade: float = sin(PI * t / dur)
		out[i] = breath * syll * fade * 0.5
	return out

# Purane lakdi/loha ke darwaze ki chargharahat
func creak(dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t: float = i / MIX_RATE
		var k: float = t / dur
		var f: float = lerpf(210.0, 120.0, k) + sin(TAU * 7.0 * t) * 18.0 + rng.randf_range(-6.0, 6.0)
		phase = fposmod(phase + TAU * f / MIX_RATE, TAU)
		var saw: float = (phase / PI) - 1.0
		var env: float = sin(PI * k)
		out[i] = (saw * 0.35 + sin(phase * 2.0) * 0.15) * env * 0.6
	return out

# Jharne ki awaaz (loop): halka shor + gehri gunj
func water(dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := 0.0
	var b := 0.0
	for i in range(n):
		var nz: float = rng.randf_range(-1.0, 1.0)
		a = lerpf(a, nz, 0.30)
		b = lerpf(b, nz, 0.05)
		out[i] = (a * 0.5 + b * 1.2) * 0.5
	return out
