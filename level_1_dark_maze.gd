extends Node3D

# Aasman ki jaadui lehrein (aurora): chamakta, lahraata, additive shader
const AURORA_SHADER: String = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 color_a : source_color = vec4(0.2, 1.0, 0.8, 1.0);
uniform vec4 color_b : source_color = vec4(0.6, 0.3, 1.0, 1.0);
uniform float fade = 0.0;
void fragment() {
	float wave = sin(UV.x * 7.0 + TIME * 0.6) * 0.5 + 0.5;
	float wave2 = sin(UV.x * 3.0 - TIME * 0.35) * 0.5 + 0.5;
	float v = smoothstep(0.0, 0.5, UV.y) * (1.0 - smoothstep(0.5, 1.0, UV.y));
	vec3 col = mix(color_a.rgb, color_b.rgb, wave);
	ALBEDO = col;
	ALPHA = v * (0.25 + 0.4 * wave2) * fade;
}
"""

@export var maze_size: Vector2i = Vector2i(10, 10)
@export var wall_height: float = 8.0
@export var beam_angle_deg: float = 12.0   # torch ki kiran kitni seedhi honi chahiye
@export var beam_range: float = 25.0
@export var charge_time: float = 1.0       # rune par kitni der kiran tikani hai

class Rune:
	var id: int = 0
	var node: MeshInstance3D
	var mat: StandardMaterial3D
	var normal: Vector3
	var charge: float = 0.0

var runes: Array[Rune] = []
var total_runes_required: int = 0
var active_runes_found: int = 0

var magical_elements_node: Node
var game_manager_node: Node
var player
var door_pivot: Node3D
var door_mat: StandardMaterial3D
var door_panel: Node3D        # simple box wala darwaza (collision ke liye bhi)
var door_light: OmniLight3D
var door_anim: AnimationPlayer
var door_anim_name: String = ""
var runes_complete: bool = false   # teeno runes mil gaye
var door_opened: bool = false      # player darwaze ke paas gaya, darwaza khul gaya
var door_center: Vector3 = Vector3.ZERO
var level_complete: bool = false
var intro_shown: bool = false
var skip_intro: bool = false

func _ready() -> void:
	magical_elements_node = get_node_or_null("../MagicalElements")
	game_manager_node = get_node_or_null("../GameManager")
	player = get_node_or_null("../Player")

	generate_dark_maze()
	spawn_hidden_runes()
	create_exit_trigger()

	await get_tree().create_timer(2.0).timeout
	if skip_intro:
		return
	intro_shown = true
	show_scroll("सुनो ऐ मुसाफिर! इस अंधेरी भूलभुलैया में दीवारों पर 3 हिडन चमकते संकेत (रून्स) छिपे हैं। अपनी सर्चलाइट की किरणें रून्स पर फोकस करो, तभी भूलभुलैया का दरवाज़ा खुलेगा, वरना ये गूंजती दीवारें तुम्हें कभी बाहर नहीं जाने देंगी!", "res://audio/intro")

func show_scroll(text: String, voice_path: String = "") -> void:
	if magical_elements_node and magical_elements_node.has_method("trigger_hatim_scroll"):
		magical_elements_node.trigger_hatim_scroll(text, voice_path)

func save_game() -> void:
	if game_manager_node and game_manager_node.has_method("save_now"):
		game_manager_node.save_now()

func play_file(base: String) -> bool:
	if game_manager_node and game_manager_node.has_method("play_file"):
		return game_manager_node.play_file(base)
	return false

func sfx(sfx_name: String) -> void:
	if game_manager_node and game_manager_node.has_method("play_sfx"):
		game_manager_node.play_sfx(sfx_name)

# ---------- Maze ----------
func generate_dark_maze() -> void:
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.24, 0.24, 0.32)
	wall_material.roughness = 0.95

	var exit_cell := Vector2i(maze_size.x - 1, int(maze_size.y / 2.0))

	for x in range(maze_size.x):
		for z in range(maze_size.y):
			var is_border: bool = (x == 0 or z == 0 or x == maze_size.x - 1 or z == maze_size.y - 1)
			var is_pillar: bool = (x % 2 == 0 and z % 2 == 0)
			if not (is_border or is_pillar):
				continue

			if Vector2i(x, z) == exit_cell:
				build_exit_door(x, z, wall_material)
			else:
				make_block(x, z, wall_material)

func add_box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size

	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = pos

	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	mesh.add_child(body)

	add_child(mesh)
	return mesh

func make_block(x: int, z: int, material: Material) -> Node3D:
	return add_box(Vector3(4.0, wall_height, 4.0), Vector3(x * 4.0 - 20.0, wall_height / 2.0, z * 4.0 - 20.0), material)

# Asli darwaza: chaukhat (frame) + lakdi-loha ka panel jo kabje (hinge) par ghoomta hai
func build_exit_door(x: int, z: int, wall_material: Material) -> void:
	var cx: float = x * 4.0 - 20.0
	var cz: float = z * 4.0 - 20.0
	door_center = Vector3(cx, 1.0, cz)
	var opening: float = 3.2
	var door_h: float = 6.0
	var post_w: float = (4.0 - opening) / 2.0

	# Chaukhat: do side posts + upar patti
	add_box(Vector3(4.0, wall_height, post_w), Vector3(cx, wall_height / 2.0, cz - (opening + post_w) / 2.0), wall_material)
	add_box(Vector3(4.0, wall_height, post_w), Vector3(cx, wall_height / 2.0, cz + (opening + post_w) / 2.0), wall_material)
	add_box(Vector3(4.0, wall_height - door_h, opening), Vector3(cx, door_h + (wall_height - door_h) / 2.0, cz), wall_material)

	# Darwaze ka panel (lakdi) + loha ki patti, band hone par laal chamak
	door_mat = StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.22, 0.12, 0.06)
	door_mat.roughness = 0.8
	door_mat.emission_enabled = true
	door_mat.emission = Color(1.0, 0.1, 0.1)
	door_mat.emission_energy_multiplier = 0.9

	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.12, 0.14)
	iron.roughness = 0.6

	# Pivot kabje par: darwaze ke ek kone par
	door_pivot = Node3D.new()
	door_pivot.position = Vector3(cx, 0.0, cz - opening / 2.0)
	add_child(door_pivot)

	var panel_size := Vector3(0.4, door_h, opening)
	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = panel_size
	panel.mesh = panel_mesh
	panel.material_override = door_mat
	panel.position = Vector3(0.0, door_h / 2.0, opening / 2.0)

	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = panel_size
	shape_node.shape = shape
	body.add_child(shape_node)
	panel.add_child(body)
	door_pivot.add_child(panel)

	for band_y in [-2.0, 0.0, 2.0]:
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.55, 0.28, opening + 0.1)
		band.mesh = band_mesh
		band.material_override = iron
		band.position = Vector3(0.0, band_y, 0.0)
		panel.add_child(band)

	door_panel = panel

	# Asli 3D darwaze ka model (models/door.glb) mile to wahi dikhega
	try_attach_door_model(opening, door_h)

	# Darwaze ke paas chhoti laal roshni (runes milne par sunehri ho jati hai)
	door_light = OmniLight3D.new()
	door_light.light_color = Color(1.0, 0.15, 0.1)
	door_light.light_energy = 1.6
	door_light.omni_range = 9.0
	door_light.position = Vector3(cx - 2.5, 3.5, cz)
	add_child(door_light)

# models/door.glb (ya .gltf) ho to use darwaze ki jagah lagao: size/disha apne aap set hoti hai.
# Model me "open" naam ki animation ho to wahi chalegi, warna darwaza kabje par ghoomega.
func try_attach_door_model(opening: float, door_h: float) -> void:
	var path: String = ""
	for ext in ["glb", "gltf", "GLB", "GLTF"]:
		var p: String = "res://models/door." + ext
		if ResourceLoader.exists(p):
			path = p
			break
	if path == "":
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var model := scene.instantiate() as Node3D
	if model == null:
		return

	var wrapper := Node3D.new()
	door_pivot.add_child(wrapper)
	wrapper.add_child(model)

	var box: AABB = model_aabb(wrapper)
	if box.size.y <= 0.001:
		wrapper.queue_free()
		return

	# Darwaze ki chaurai z axis par chahiye; model x par ho to 90 degree ghumao
	if box.size.x > box.size.z:
		wrapper.rotation_degrees.y = 90.0
		box = model_aabb(wrapper)

	# Size: height 6 aur chaurai 3.2 me fit
	var fit: float = minf(door_h / box.size.y, opening / maxf(box.size.z, 0.001))
	wrapper.scale = Vector3.ONE * fit
	box = model_aabb(wrapper)

	# Neeche-beech ko kabje ke paas wali jagah par rakho
	var current := Vector3(box.position.x + box.size.x / 2.0, box.position.y, box.position.z + box.size.z / 2.0)
	wrapper.position += Vector3(0.0, 0.0, opening / 2.0) - current

	# Simple box wala darwaza chhupao (collision bani rahegi)
	for child in door_panel.get_children():
		if child is MeshInstance3D:
			child.visible = false
	(door_panel as MeshInstance3D).visible = false

	# Model ki apni "open" animation
	door_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if door_anim:
		for n in door_anim.get_animation_list():
			if String(n).to_lower().contains("open"):
				door_anim_name = String(n)
				break

# wrapper ke andar ke saare meshes ka milakar AABB (door_pivot ki space me)
func model_aabb(root: Node3D) -> AABB:
	var to_pivot: Transform3D = door_pivot.global_transform.affine_inverse()
	var result := AABB()
	var first: bool = true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b: AABB = to_pivot * mi.global_transform * mi.get_aabb()
		if first:
			result = b
			first = false
		else:
			result = result.merge(b)
	return result

func release_door_collision() -> void:
	if is_instance_valid(door_panel):
		door_panel.queue_free()

# ---------- Runes (deewaron par chhipe, torch se jagte hain) ----------
func spawn_hidden_runes() -> void:
	# [position (pillar ki deewar par), normal (deewar kis taraf dekh rahi hai)]
	var defs := [
		[Vector3(-12, 1.6, -9.97), Vector3(0, 0, 1)],
		[Vector3(1.97, 1.6, -4), Vector3(-1, 0, 0)],
		[Vector3(-4, 1.6, 9.97), Vector3(0, 0, -1)]
	]
	total_runes_required = defs.size()

	for d in defs:
		var pos: Vector3 = d[0]
		var normal: Vector3 = d[1]

		var plane := PlaneMesh.new()
		plane.size = Vector2(1.6, 1.6)
		plane.orientation = PlaneMesh.FACE_X if absf(normal.x) > 0.5 else PlaneMesh.FACE_Z

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.6, 0.1)
		mat.emission_energy_multiplier = 0.6
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED

		var mesh := MeshInstance3D.new()
		mesh.mesh = plane
		mesh.material_override = mat
		mesh.position = pos
		add_child(mesh)

		var r := Rune.new()
		r.node = mesh
		r.mat = mat
		r.normal = normal
		r.id = runes.size()
		runes.append(r)

func _physics_process(delta: float) -> void:
	if player == null or player.camera == null:
		return

	check_door_proximity()

	if runes.is_empty():
		return

	var cam: Camera3D = player.camera
	var torch_on: bool = player.is_torch_on
	var origin := cam.global_position
	var forward := -cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state

	for r in runes.duplicate():
		var lit: bool = torch_on and is_rune_lit(r, origin, forward, space)

		if lit:
			r.charge += delta
		else:
			r.charge = maxf(0.0, r.charge - delta * 0.5)

		var t: float = clampf(r.charge / charge_time, 0.0, 1.0)
		r.mat.emission_energy_multiplier = lerpf(0.6, 6.0, t)

		if r.charge >= charge_time:
			on_rune_activated(r)

func is_rune_lit(r: Rune, origin: Vector3, forward: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var target := r.node.global_position
	var to_rune := target - origin
	var dist := to_rune.length()
	if dist > beam_range or dist < 0.1:
		return false

	var dir := to_rune / dist
	if forward.dot(dir) < cos(deg_to_rad(beam_angle_deg)):
		return false
	if dir.dot(r.normal) > 0.0:
		return false # deewar ke peeche se

	# Beech me deewar to nahi?
	var query := PhysicsRayQueryParameters3D.create(origin, target + r.normal * 0.2)
	query.exclude = [player.get_rid()]
	return space.intersect_ray(query).is_empty()

func on_rune_activated(r: Rune) -> void:
	runes.erase(r)
	r.node.queue_free()
	active_runes_found += 1
	print("Rune Found! Total: ", active_runes_found, "/", total_runes_required)
	sfx("rune")
	save_game()

	if active_runes_found >= total_runes_required:
		unlock_maze_exit()
	else:
		var msgs: Array[String] = [
			"पहला संकेत जाग उठा... बाकी दो अभी भी अंधेरे में छिपे हैं, मुसाफिर।",
			"दूसरा संकेत भी रोशन हुआ! बस एक और, फिर राह खुलेगी।"
		]
		show_scroll(msgs[mini(active_runes_found, msgs.size()) - 1], "res://audio/rune_%d" % active_runes_found)

# ---------- Exit ----------
# Teeno runes mil gaye: darwaza sunehri jagta hai, par khulta tab hai jab player uske paas jaye
func unlock_maze_exit() -> void:
	if runes_complete:
		return
	runes_complete = true
	print("All runes found. Darwaze ke paas jao.")

	var glow := create_tween().set_parallel(true)
	if door_mat:
		glow.tween_property(door_mat, "emission", Color(1.0, 0.8, 0.3), 0.8)
	if door_light:
		glow.tween_property(door_light, "light_color", Color(1.0, 0.8, 0.3), 0.8)

	show_scroll("तीनों संकेत जाग चुके हैं! अब भूलभुलैया के दरवाज़े के पास जाओ... वो तुम्हारा इंतज़ार कर रहा है।", "res://audio/runes_done")

func check_door_proximity() -> void:
	if not runes_complete or door_opened:
		return
	var p: Vector3 = player.global_position
	var d: float = Vector2(p.x - door_center.x, p.z - door_center.z).length()
	if d <= 6.0:
		open_exit_door()

func open_exit_door() -> void:
	door_opened = true
	save_game()
	print("Darwaza khul raha hai...")

	# Darwaza utni der me khulega jitni lambi tumhari sound file hai (2 se 6 second)
	var open_time: float = 2.2
	if game_manager_node and game_manager_node.has_method("load_audio"):
		var stream: AudioStream = game_manager_node.load_audio("res://audio/door_open_sfx")
		if stream:
			open_time = clampf(stream.get_length(), 2.2, 6.0)

	# Tumhari apni sound file (audio/door_open_sfx, koi bhi mp3/ogg/wav). Na mile to code wali awaaz.
	if not play_file("res://audio/door_open_sfx"):
		sfx("door")
		sfx("creak")

	if door_light:
		create_tween().tween_property(door_light, "light_energy", 0.4, open_time)

	if door_anim and door_anim_name != "":
		# Model ki apni animation chalao, usi samay me poori ho
		var anim: Animation = door_anim.get_animation(door_anim_name)
		if anim and anim.length > 0.0:
			door_anim.speed_scale = anim.length / open_time
		door_anim.play(door_anim_name)
		# Animation wale darwaze me box ki collision khulte hi hata do
		get_tree().create_timer(open_time * 0.6).timeout.connect(release_door_collision)
	elif is_instance_valid(door_pivot):
		var tween := create_tween()
		tween.tween_property(door_pivot, "rotation_degrees:y", 100.0, open_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func create_exit_trigger() -> void:
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 4, 8)
	col.shape = shape
	area.add_child(col)
	area.position = Vector3(20.5, 2, 0) # darwaze ke theek bahar
	add_child(area)
	area.body_entered.connect(_on_exit_entered)

func _on_exit_entered(body: Node3D) -> void:
	if body.name != "Player" or not door_opened or level_complete:
		return
	level_complete = true
	save_game()
	print("LEVEL 1 COMPLETE")

	# Card nahi, sirf awaaz: tumhari welcome voice (audio/welcome_shadow_world)
	var welcome_len: float = 0.0
	if game_manager_node and game_manager_node.has_method("load_audio"):
		var st: AudioStream = game_manager_node.load_audio("res://audio/welcome_shadow_world")
		if st:
			welcome_len = st.get_length()
	if game_manager_node and game_manager_node.has_method("play_file"):
		game_manager_node.play_file("res://audio/welcome_shadow_world", 3.0)
	if game_manager_node and game_manager_node.has_method("play_sfx"):
		game_manager_node.play_sfx("complete", -6.0)

	start_magical_world()
	start_level_two(welcome_len)

func create_level_two() -> Node3D:
	var script := load("res://level_2_field.gd") as Script
	if script == null:
		return null
	if door_light:
		door_light.visible = false # roshni ki ginti kam rakhne ke liye
	var l2 := Node3D.new()
	l2.name = "Level2Field"
	l2.set_script(script)
	get_parent().add_child(l2)
	return l2

# ---------------- Save / Resume ----------------
func get_save_data() -> Dictionary:
	var remaining: Array = []
	for r in runes:
		remaining.append(r.id)
	var found: Array = []
	for i in range(total_runes_required):
		if not remaining.has(i):
			found.append(i)
	return {
		"intro_shown": intro_shown,
		"found_runes": found,
		"runes_complete": runes_complete,
		"door_opened": door_opened,
		"level_complete": level_complete
	}

func apply_save_data(d: Dictionary, l2_data: Dictionary) -> void:
	intro_shown = bool(d.get("intro_shown", false))
	skip_intro = intro_shown
	for id in d.get("found_runes", []):
		for r in runes.duplicate():
			if r.id == int(id):
				runes.erase(r)
				r.node.queue_free()
				active_runes_found += 1
	if bool(d.get("runes_complete", false)):
		runes_complete = true
		if door_mat:
			door_mat.emission = Color(1.0, 0.8, 0.3)
		if door_light:
			door_light.light_color = Color(1.0, 0.8, 0.3)
	if bool(d.get("door_opened", false)):
		open_door_instant()
	if bool(d.get("level_complete", false)):
		level_complete = true
		start_magical_world()
		var l2: Node3D = create_level_two()
		if l2:
			l2.activate()
			l2.apply_save_data(l2_data)

func open_door_instant() -> void:
	door_opened = true
	if door_anim and door_anim_name != "":
		door_anim.play(door_anim_name)
		var anim: Animation = door_anim.get_animation(door_anim_name)
		if anim:
			door_anim.seek(anim.length, true)
		release_door_collision()
	elif is_instance_valid(door_pivot):
		door_pivot.rotation_degrees.y = 100.0
	if door_light:
		door_light.light_energy = 0.4

# Level 2 ka maidan banao; welcome awaaz khatam hone ke baad uske instructions ka card aata hai
func start_level_two(wait: float) -> void:
	var l2: Node3D = create_level_two()
	if l2 == null:
		return

	await get_tree().create_timer(wait + 0.8).timeout
	show_scroll("मुसाफिर, यह परछाइयों का मैदान है... पराग ज्योतिषपुर का रास्ता यहीं से गुज़रता है। मैदान के चारों कोनों पर पत्थर की मशालें खड़ी हैं। अपनी सर्चलाइट की किरण टिकाकर उन्हें जगाओ। अँधेरे से परछाइयाँ तुम्हारी ओर बढ़ेंगी... उन पर रोशनी डालो, वे राख हो जाएँगी। जब चारों मशालें जल उठेंगी, तब महादेव का द्वार प्रकट होगा।", "res://audio/level2_intro")
	if is_instance_valid(l2) and l2.has_method("activate"):
		l2.activate()

# ---------- Jaadui duniya (darwaze ke bahar) ----------
func start_magical_world() -> void:
	# Aasman aur roshni ka rang dheere dheere jaadui ho jata hai
	var world_gen := get_node_or_null("../WorldGenerator")
	if world_gen and world_gen.has_method("enter_magical_world"):
		world_gen.enter_magical_world()

	# 1) Aasman me aurora ki lehrein (3 disha me)
	var shader := Shader.new()
	shader.code = AURORA_SHADER
	var specs := [
		[Vector3(95, 62, 0), -90.0, Color(0.2, 1.0, 0.8), Color(0.6, 0.3, 1.0)],
		[Vector3(70, 66, -70), -45.0, Color(0.4, 0.6, 1.0), Color(1.0, 0.3, 0.8)],
		[Vector3(70, 66, 70), -135.0, Color(1.0, 0.7, 0.3), Color(0.3, 1.0, 0.7)]
	]
	var fade_tween := create_tween().set_parallel(true)
	for spec in specs:
		var quad := QuadMesh.new()
		quad.size = Vector2(150, 44)

		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("color_a", spec[2])
		mat.set_shader_parameter("color_b", spec[3])
		mat.set_shader_parameter("fade", 0.0)

		var ribbon := MeshInstance3D.new()
		ribbon.mesh = quad
		ribbon.material_override = mat
		ribbon.position = spec[0]
		ribbon.rotation_degrees.y = spec[1]
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ribbon)

		fade_tween.tween_method(func(v: float): mat.set_shader_parameter("fade", v), 0.0, 1.0, 5.0)

	# 2) Tairti hui rangeen roshniyan (jaadui orbs) darwaze ke bahar ke maidan me
	add_child(make_light_particles(Vector3(32, 9, 0), Vector3(30, 8, 30), 90, 10.0, 0.14, 0.4, 1.2))
	# 3) Aasman me chamakte sitare / roshni ke kan
	add_child(make_light_particles(Vector3(30, 75, 0), Vector3(70, 20, 70), 160, 6.0, 0.35, 0.05, 0.3))

func make_light_particles(pos: Vector3, half_extents: Vector3, amount: int, life: float, size: float, vmin: float, vmax: float) -> CPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var orb := SphereMesh.new()
	orb.radius = size
	orb.height = size * 2.0
	orb.radial_segments = 8
	orb.rings = 4
	orb.material = mat

	# Har kan ka rang: cyan / gulabi / sunehri / neela mein se kuch bhi
	var color_pick := Gradient.new()
	color_pick.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	color_pick.colors = PackedColorArray([Color(0.3, 1.0, 0.9), Color(1.0, 0.4, 0.9), Color(1.0, 0.85, 0.4), Color(0.5, 0.6, 1.0)])

	# Umar ke saath dheere dikhna aur dheere gayab hona
	var life_fade := Gradient.new()
	life_fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	life_fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])

	var p := CPUParticles3D.new()
	p.position = pos
	p.mesh = orb
	p.amount = amount
	p.lifetime = life
	p.preprocess = life * 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = half_extents
	p.direction = Vector3(0, 1, 0)
	p.spread = 60.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	p.color_initial_ramp = color_pick
	p.color_ramp = life_fade
	p.emitting = true
	return p
