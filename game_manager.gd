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
	call_deferred("_resume_game")

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

func _process(delta: float) -> void:
	autosave_timer += delta
	if autosave_timer >= 8.0:
		autosave_timer = 0.0
		save_now()

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
# Koi bhi stream pool ke khaali player me bajao
func play_stream(stream: AudioStream, volume_db: float = 0.0) -> void:
	for p in sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return

# base, base_1, base_2 ... base_5 me se jitni files hain unme se EK RANDOM bajao (na mile to code wali awaaz)
func play_variant(base: String, fallback: String, volume_db: float = 0.0) -> void:
	var cands: Array = []
	for suffix in ["", "_1", "_2", "_3", "_4", "_5"]:
		var st: AudioStream = load_audio(base + suffix)
		if st:
			cands.append(st)
	if cands.is_empty():
		play_sfx(fallback, volume_db)
		return
	play_stream(cands[randi() % cands.size()], volume_db)

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
	sfx["clash"] = make_wav(clash(0.6))
	sfx["shield"] = make_wav(shield_hit(0.5))
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

# ---------------- 3D model helpers (talwar, yoddha, etc.) ----------------
const MODEL_EXTS: Array[String] = ["fbx", "glb", "gltf", "FBX", "GLB", "GLTF"]

# models/ folder me naam se file dhoondo (capital/small dono, koi bhi extension)
func find_model_path(names: Array) -> String:
	for n in names:
		for variant in [String(n), String(n).to_lower()]:
			for e in MODEL_EXTS:
				var p: String = "res://models/" + variant + "." + e
				if ResourceLoader.exists(p):
					return p
	return ""

# Weapon file se talwar: phal +Y par, mooth origin par, lambai = length (meter).
# parent_scale: jis node ke neeche lagani hai uska scale (haddi/skeleton ka)
func make_weapon(names: Array, length: float, parent_scale: float = 1.0) -> Node3D:
	var path: String = find_model_path(names)
	if path == "":
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null
	var wrapper := Node3D.new()
	wrapper.add_child(inst)
	fit_weapon(wrapper, length, parent_scale)
	return wrapper

func fit_weapon(wrapper: Node3D, length: float, parent_scale: float, flip: bool = false) -> void:
	var size: Vector3 = aabb_of(wrapper).size
	var longest: float = maxf(size.x, maxf(size.y, size.z))
	if longest <= 0.0001:
		return
	# Sabse lambi disha ko upar (+Y) le aao
	var rot := Basis.IDENTITY
	if size.x >= size.y and size.x >= size.z:
		rot = Basis(Vector3(0, 0, 1), PI / 2.0)
	elif size.z >= size.x and size.z >= size.y:
		rot = Basis(Vector3(1, 0, 0), -PI / 2.0)
	wrapper.basis = rot
	# Mooth neeche rahe: jis chhor par cross-section badi ho wo mooth hai
	var hilt_top: bool = hilt_on_top(wrapper)
	if flip:
		hilt_top = not hilt_top   # haath se ulti dikhe to constant FLIP badlo
	if hilt_top:
		wrapper.basis = Basis(Vector3(1, 0, 0), PI) * rot
	var s: float = length / longest / maxf(parent_scale, 0.0001)
	wrapper.basis = wrapper.basis.scaled(Vector3.ONE * s)
	var box: AABB = aabb_of(wrapper, true)
	var c: Vector3 = box.get_center()
	wrapper.position = -Vector3(c.x, box.position.y, c.z)

func hilt_on_top(wrapper: Node3D) -> bool:
	var verts := PackedVector3Array()
	gather_verts(wrapper, wrapper.transform, verts)
	if verts.size() < 12:
		return false
	var min_y: float = verts[0].y
	var max_y: float = verts[0].y
	var cx: float = 0.0
	var cz: float = 0.0
	for v in verts:
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)
		cx += v.x
		cz += v.z
	cx /= verts.size()
	cz /= verts.size()
	var h: float = max_y - min_y
	if h <= 0.0001:
		return false
	# 12 patti (bin) me chaudai napo: sabse chaudi jagah (guard/mooth) jis chhor ke paas ho wahi mooth hai
	var bins: Array = []
	for b in range(12):
		bins.append(0.0)
	for v in verts:
		var idx: int = clampi(int((v.y - min_y) / h * 12.0), 0, 11)
		bins[idx] = maxf(float(bins[idx]), maxf(absf(v.x - cx), absf(v.z - cz)))
	var widest: int = 0
	for b in range(12):
		if float(bins[b]) > float(bins[widest]):
			widest = b
	if widest <= 4:
		return false      # mooth neeche
	if widest >= 7:
		return true       # mooth upar
	# Beech me ho to chhoron ki motaai se
	return float(bins[11]) + float(bins[10]) > float(bins[0]) + float(bins[1])

func gather_verts(node: Node, xform: Transform3D, out: PackedVector3Array) -> void:
	for c in node.get_children():
		if c is Node3D:
			var t: Transform3D = xform * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh:
				var faces: PackedVector3Array = (c as MeshInstance3D).mesh.get_faces()
				var step: int = maxi(1, int(faces.size() / 4000.0))
				var i: int = 0
				while i < faces.size():
					out.append(t * faces[i])
					i += step
			gather_verts(c, t, out)

func collect_boxes(node: Node, xform: Transform3D, boxes: Array) -> void:
	for c in node.get_children():
		if c is Node3D:
			var t: Transform3D = xform * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh:
				boxes.append(t * (c as MeshInstance3D).mesh.get_aabb())
			collect_boxes(c, t, boxes)

# Tree me hone ki zarurat nahi: root ke bachchon ka milakar AABB
func aabb_of(root: Node3D, include_root_transform: bool = false) -> AABB:
	var boxes: Array = []
	collect_boxes(root, root.transform if include_root_transform else Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var result: AABB = boxes[0]
	for i in range(1, boxes.size()):
		result = result.merge(boxes[i])
	return result

# Talwar takrane ki dhaatu jaisi awaaz (tumhari sword_clash file na ho to)
func clash(dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var freqs: Array = [820.0, 1310.0, 2240.0, 3170.0]
	for i in range(n):
		var t: float = i / MIX_RATE
		var s: float = 0.0
		for f in freqs:
			s += sin(TAU * float(f) * t + sin(t * 40.0) * 0.3)
		var burst: float = rng.randf_range(-1.0, 1.0) * exp(-t * 80.0)
		out[i] = (s / freqs.size() * 0.55 + burst * 0.5) * exp(-t * 9.0)
	return out

# Dhaal par vaar ki bhaari thud + halki gunj (tumhari shield_clash file na ho to)
func shield_hit(dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var freqs: Array = [180.0, 340.0, 520.0]
	var lp: float = 0.0
	for i in range(n):
		var t: float = i / MIX_RATE
		var s: float = 0.0
		for f in freqs:
			s += sin(TAU * float(f) * t)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.2)
		out[i] = (s / freqs.size() * 0.5 + lp * exp(-t * 60.0) * 0.8) * exp(-t * 11.0)
	return out

# ---------------- Sword pack (swords.glb) se ek talwar ----------------
# Pack me 4 talwarein ek hi file me hoti hain: unke tukde (meshes) position ke hisaab se 4 jhund me baant kar
# index wali talwar banai jati hai (phal +Y par, mooth origin par, lambai = length meter)
func make_pack_weapon(index: int, length: float, parent_scale: float = 1.0, flip: bool = false) -> Node3D:
	var path: String = find_model_path(["swords", "sword_pack", "neptunia"])
	if path == "":
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null
	var groups: Array = split_pack(inst)
	if groups.is_empty():
		inst.free()
		return null
	var group: Array = groups[index % groups.size()]
	var wrapper := Node3D.new()
	for it in group:
		var mi: MeshInstance3D = it["mi"]
		var ni := MeshInstance3D.new()
		ni.mesh = mi.mesh
		ni.transform = it["t"]
		for s in range(mi.mesh.get_surface_count()):
			var m: Material = mi.get_active_material(s)
			if m:
				ni.set_surface_override_material(s, m)
		wrapper.add_child(ni)
	inst.free()
	fit_weapon(wrapper, length, parent_scale, flip)
	return wrapper

func collect_meshes(node: Node, xform: Transform3D, out: Array) -> void:
	for c in node.get_children():
		if c is Node3D:
			var t: Transform3D = xform * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh:
				var mi := c as MeshInstance3D
				out.append({"mi": mi, "t": t, "c": (t * mi.mesh.get_aabb()).get_center()})
			collect_meshes(c, t, out)

func split_pack(inst: Node3D) -> Array:
	var items: Array = []
	collect_meshes(inst, Transform3D.IDENTITY, items)
	if items.is_empty():
		return []
	var minv: Vector3 = items[0]["c"]
	var maxv: Vector3 = items[0]["c"]
	for it in items:
		minv = minv.min(it["c"])
		maxv = maxv.max(it["c"])
	var spread: Vector3 = maxv - minv
	var axis: int = 0
	if spread.y >= spread.x and spread.y >= spread.z:
		axis = 1
	elif spread.z >= spread.x and spread.z >= spread.y:
		axis = 2
	items.sort_custom(func(a, b): return a["c"][axis] < b["c"][axis])
	var gaps: Array = []
	for i in range(items.size() - 1):
		gaps.append({"gap": items[i + 1]["c"][axis] - items[i]["c"][axis], "i": i})
	gaps.sort_custom(func(a, b): return a["gap"] > b["gap"])
	var cuts: Array = []
	for k in range(mini(3, gaps.size())):
		cuts.append(gaps[k]["i"])
	cuts.sort()
	var groups: Array = []
	var start: int = 0
	for c in cuts:
		groups.append(items.slice(start, int(c) + 1))
		start = int(c) + 1
	groups.append(items.slice(start))
	return groups

# ---------------- Save / Resume ----------------
# App band karke dobara kholne par game wahin se shuru hota hai (user://searchlight_save.json)
const SAVE_PATH: String = "user://searchlight_save.json"
var save_enabled: bool = false
var autosave_timer: float = 0.0

func build_save() -> Dictionary:
	var data: Dictionary = {"version": 1}
	var player = get_node_or_null("../Player")
	if player and player.has_method("get_save_data"):
		data["player"] = player.get_save_data()
	var l1 = get_node_or_null("../Level1Maze")
	if l1 and l1.has_method("get_save_data"):
		data["level1"] = l1.get_save_data()
	var l2 = get_node_or_null("../Level2Field")
	if l2 and l2.has_method("get_save_data"):
		data["level2"] = l2.get_save_data()
	return data

func save_now() -> void:
	if not save_enabled:
		return
	var player = get_node_or_null("../Player")
	if player and player.get("dead"):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(build_save()))
		f.close()

func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}

# Saare nodes ready hone ke baad (deferred) purani progress wapas lagao
func _resume_game() -> void:
	var data: Dictionary = load_save()
	if not data.is_empty():
		var l1 = get_node_or_null("../Level1Maze")
		if l1 and data.has("level1") and l1.has_method("apply_save_data"):
			l1.apply_save_data(data["level1"], data.get("level2", {}))
		var player = get_node_or_null("../Player")
		if player and data.has("player") and player.has_method("apply_save_data"):
			player.apply_save_data(data["player"])
	save_enabled = true

# Android par home dabane / app band karne par turant save
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()
