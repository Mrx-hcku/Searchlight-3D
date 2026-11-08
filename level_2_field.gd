extends Node3D
# Level 2: Parchhaiyon ka maidan
# 6 yoddha (talwar wale) pehra dete hain. Chaar masal jagao (har masal par ujala badhta hai), phir Mahadev (Nataraj) ka dwar khulta hai.
# Level 1 ki script ise darwaze ke bahar nikalne par apne aap banati hai (Main.tscn badalne ki zarurat nahi).

const PORTAL_SHADER: String = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform float amount = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = sin(a * 5.0 + r * 14.0 - TIME * 3.0) * 0.5 + 0.5;
	float ring = smoothstep(1.0, 0.8, r) * smoothstep(0.30, 0.7, r);
	float hole = smoothstep(0.45, 0.25, r);
	vec3 col = mix(vec3(0.3, 0.1, 0.7), vec3(1.0, 0.8, 0.3), swirl) * ring * 2.5;
	ALBEDO = col;
	ALPHA = clamp(ring + hole, 0.0, 1.0) * amount;
}
"""

const WATER_SHADER: String = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform float glow = 0.3;
uniform vec3 tint : source_color = vec3(0.65, 0.88, 1.0);
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	float x = UV.x * 24.0;
	float c = floor(x);
	float speed = 0.5 + hash(vec2(c, 1.0)) * 0.9;
	float y = UV.y * 5.0 - TIME * speed + hash(vec2(c, 7.0)) * 5.0;
	float streak = smoothstep(0.45, 1.0, fract(y));
	float edge = smoothstep(0.0, 0.35, fract(x)) * smoothstep(1.0, 0.65, fract(x));
	float a = (0.3 + 0.7 * streak) * edge;
	a *= smoothstep(0.0, 0.04, UV.y);
	ALBEDO = tint * (0.6 + 1.6 * glow);
	ALPHA = a * (0.35 + 0.6 * glow);
}
"""

const GOLD: Color = Color(1.0, 0.8, 0.35)
const FIELD_MIN_X: float = 100.0
const FIELD_MAX_X: float = 240.0
const FIELD_HALF_Z: float = 70.0
const WALL_H: float = 34.0
const STATUE_POS: Vector3 = Vector3(231.0, 0.0, 0.0)

# ---- Tuning ----
var masal_beam_angle: float = 12.0     # masal par kiran kitni seedhi
var masal_range: float = 45.0
var masal_charge_time: float = 1.5     # masal par kitni der kiran tikani hai

var masal_positions: Array[Vector3] = [
	Vector3(128.0, 0.0, -46.0), Vector3(128.0, 0.0, 46.0),
	Vector3(205.0, 0.0, -46.0), Vector3(205.0, 0.0, 46.0)
]

class Masal:
	var flame_pos: Vector3
	var ember_mat: StandardMaterial3D
	var light: OmniLight3D
	var fire: CPUParticles3D
	var charge: float = 0.0
	var lit: bool = false

var player
var game_manager_node: Node
var magical_node: Node
var rng := RandomNumberGenerator.new()

var masals: Array[Masal] = []
var warriors: Array = []
var lit_count: int = 0
var active: bool = false
var complete: bool = false          # chaaron masal jal gayi
var statue_revealed: bool = false
var portal_open: bool = false
var finished: bool = false
var portal_age: float = 0.0

var statue_root: Node3D
var statue_light: OmniLight3D
var waterfall_mat: ShaderMaterial
var portal: MeshInstance3D
var portal_mat: ShaderMaterial
var tandav_player: AudioStreamPlayer
var hit_overlay: ColorRect
var hud_label: Label
var toast_label: Label
var _toast_tween: Tween

func _ready() -> void:
	game_manager_node = get_node_or_null("../GameManager")
	magical_node = get_node_or_null("../MagicalElements")
	player = get_node_or_null("../Player")
	rng.randomize()

	build_field()
	for pos in masal_positions:
		masals.append(build_masal(pos))
	build_waterfall()
	build_statue()
	build_portal()
	build_ui()
	build_audio()

# Level 1 ka card dikhne ke baad ye bulaya jata hai
func activate() -> void:
	active = true
	hud_label.visible = true
	update_hud()
	if player.has_method("set_combat_enabled"):
		player.set_combat_enabled(true)
	if player.has_signal("died") and not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)
	spawn_warriors()

# ---------------- Helpers ----------------
func sfx(sfx_name: String, volume_db: float = 0.0) -> void:
	if game_manager_node and game_manager_node.has_method("play_sfx"):
		game_manager_node.play_sfx(sfx_name, volume_db)

func mat_color(c: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

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

func make_particles(pos: Vector3, amount: int, life: float, size: float, color_a: Color, color_b: Color, vmin: float, vmax: float, extents: Vector3, spread: float) -> CPUParticles3D:
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

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	fade.colors = PackedColorArray([color_a, color_b])

	var p := CPUParticles3D.new()
	p.position = pos
	p.mesh = orb
	p.amount = amount
	p.lifetime = life
	p.preprocess = life * 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(0, 1, 0)
	p.spread = spread
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.color_ramp = fade
	p.emitting = true
	return p

# ---------------- Maidan (limited, chaaro taraf chattaanein) ----------------
func build_field() -> void:
	var cx: float = (FIELD_MIN_X + FIELD_MAX_X) / 2.0
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(152.0, 150.0)
	var ground := MeshInstance3D.new()
	ground.mesh = ground_mesh
	ground.material_override = mat_color(Color(0.14, 0.16, 0.21), 0.95)
	ground.position = Vector3(cx + 2.0, 0.02, 0.0)
	add_child(ground)

	var rock := mat_color(Color(0.12, 0.13, 0.19), 1.0)
	var h: float = WALL_H
	add_box(Vector3(156, h, 6), Vector3(cx + 2.0, h / 2.0, -73), rock)
	add_box(Vector3(156, h, 6), Vector3(cx + 2.0, h / 2.0, 73), rock)
	add_box(Vector3(6, h, 152), Vector3(243, h / 2.0, 0), rock)
	# Pashchim ki deewar me beech me 20 meter ka raasta (Level 1 ke darwaze ki taraf)
	add_box(Vector3(6, h, 66), Vector3(97, h / 2.0, -43), rock)
	add_box(Vector3(6, h, 66), Vector3(97, h / 2.0, 43), rock)

	# Chhupne ke liye kuch patthar
	var rock_light := mat_color(Color(0.20, 0.21, 0.28), 1.0)
	var rr := RandomNumberGenerator.new()
	rr.seed = 7
	var placed: int = 0
	var tries: int = 0
	while placed < 12 and tries < 300:
		tries += 1
		var p := Vector3(rr.randf_range(FIELD_MIN_X + 10.0, FIELD_MAX_X - 10.0), 0.0, rr.randf_range(-FIELD_HALF_Z + 8.0, FIELD_HALF_Z - 8.0))
		if p.x < 130.0 and absf(p.z) < 16.0:
			continue
		if p.distance_to(STATUE_POS) < 22.0:
			continue
		var near_masal: bool = false
		for mp in masal_positions:
			if p.distance_to(mp) < 14.0:
				near_masal = true
		if near_masal:
			continue
		var s := Vector3(rr.randf_range(3.0, 6.0), rr.randf_range(2.5, 5.0), rr.randf_range(3.0, 6.0))
		var r := add_box(s, Vector3(p.x, s.y / 2.0, p.z), rock_light)
		r.rotation_degrees.y = rr.randf_range(0.0, 180.0)
		placed += 1

# ---------------- Masal (patthar ka stambh + sunehri aag) ----------------
func build_masal(pos: Vector3) -> Masal:
	var m := Masal.new()
	m.flame_pos = pos + Vector3(0, 5.7, 0)

	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var stone := mat_color(Color(0.24, 0.22, 0.30), 0.9)
	var iron := mat_color(Color(0.10, 0.10, 0.13), 0.6)

	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.7
	pillar_mesh.bottom_radius = 0.95
	pillar_mesh.height = 5.0
	var pillar := MeshInstance3D.new()
	pillar.mesh = pillar_mesh
	pillar.material_override = stone
	pillar.position = Vector3(0, 2.5, 0)
	root.add_child(pillar)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.95
	cyl.height = 5.0
	cs.shape = cyl
	body.add_child(cs)
	pillar.add_child(body)

	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 1.3
	bowl_mesh.bottom_radius = 0.8
	bowl_mesh.height = 0.7
	var bowl := MeshInstance3D.new()
	bowl.mesh = bowl_mesh
	bowl.material_override = iron
	bowl.position = Vector3(0, 5.35, 0)
	root.add_child(bowl)

	# Bujhi masal me halka angaara
	m.ember_mat = StandardMaterial3D.new()
	m.ember_mat.albedo_color = GOLD
	m.ember_mat.emission_enabled = true
	m.ember_mat.emission = Color(1.0, 0.65, 0.2)
	m.ember_mat.emission_energy_multiplier = 0.5
	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.5
	ember_mesh.height = 1.0
	var ember := MeshInstance3D.new()
	ember.mesh = ember_mesh
	ember.material_override = m.ember_mat
	ember.position = Vector3(0, 5.7, 0)
	root.add_child(ember)

	m.light = OmniLight3D.new()
	m.light.light_color = GOLD
	m.light.light_energy = 0.5
	m.light.omni_range = 24.0
	m.light.position = Vector3(0, 6.2, 0)
	root.add_child(m.light)

	m.fire = make_particles(Vector3(0, 5.75, 0), 45, 1.0, 0.32, Color(1.0, 0.95, 0.6, 0.95), Color(1.0, 0.35, 0.05, 0.0), 1.2, 2.6, Vector3(0.35, 0.1, 0.35), 14.0)
	m.fire.gravity = Vector3(0, 1.2, 0)
	m.fire.emitting = false
	root.add_child(m.fire)
	return m

# ---------------- Jharna aur kund ----------------
func build_waterfall() -> void:
	var shader := Shader.new()
	shader.code = WATER_SHADER
	waterfall_mat = ShaderMaterial.new()
	waterfall_mat.shader = shader
	waterfall_mat.set_shader_parameter("glow", 0.3)

	var quad := QuadMesh.new()
	quad.size = Vector2(18.0, 32.0)
	var fall := MeshInstance3D.new()
	fall.mesh = quad
	fall.material_override = waterfall_mat
	fall.position = Vector3(239.6, 16.0, 0.0)
	fall.rotation_degrees.y = -90.0
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fall)

	var pool_mat := StandardMaterial3D.new()
	pool_mat.albedo_color = Color(0.2, 0.45, 0.7, 0.55)
	pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool_mat.emission_enabled = true
	pool_mat.emission = Color(0.1, 0.3, 0.6)
	pool_mat.emission_energy_multiplier = 0.6
	var pool_mesh := CylinderMesh.new()
	pool_mesh.top_radius = 6.0
	pool_mesh.bottom_radius = 6.0
	pool_mesh.height = 0.1
	var pool := MeshInstance3D.new()
	pool.mesh = pool_mesh
	pool.material_override = pool_mat
	pool.position = Vector3(236.0, 0.08, 0.0)
	add_child(pool)

	# Jharne ke neeche dhundh
	add_child(make_particles(Vector3(238.0, 1.0, 0.0), 40, 3.0, 0.9, Color(0.8, 0.9, 1.0, 0.22), Color(0.8, 0.9, 1.0, 0.0), 0.2, 0.6, Vector3(1.5, 0.6, 7.0), 30.0))

# ---------------- Nataraj ki murti (placeholder; models/nataraj.glb mile to wahi) ----------------
func build_statue() -> void:
	# Chabutra hamesha dikhta hai (khaali), murti baad me prakat hoti hai
	var base_mat := mat_color(Color(0.26, 0.24, 0.32), 0.9)
	add_box(Vector3(4.4, 1.2, 4.4), STATUE_POS + Vector3(0, 0.6, 0), base_mat)

	statue_root = Node3D.new()
	statue_root.position = STATUE_POS + Vector3(0, 1.2, 0)
	statue_root.rotation_degrees.y = -90.0   # murti ka chehra pashchim (khilaadi) ki taraf
	statue_root.visible = false
	add_child(statue_root)

	var placeholder := Node3D.new()
	statue_root.add_child(placeholder)

	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.9, 0.7, 0.25)
	gold.roughness = 0.45
	gold.emission_enabled = true
	gold.emission = Color(0.9, 0.6, 0.15)
	gold.emission_energy_multiplier = 0.35

	var fire_ring := StandardMaterial3D.new()
	fire_ring.albedo_color = GOLD
	fire_ring.emission_enabled = true
	fire_ring.emission = Color(1.0, 0.6, 0.15)
	fire_ring.emission_energy_multiplier = 2.2

	# Prabhamandala (aag ka gola)
	var torus := TorusMesh.new()
	torus.inner_radius = 2.9
	torus.outer_radius = 3.25
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = fire_ring
	ring.rotation_degrees.x = 90.0
	ring.position = Vector3(0, 3.6, -0.3)
	placeholder.add_child(ring)

	placeholder.add_child(shape_part(CapsuleMesh.new(), gold, Vector3(0, 2.9, 0), Vector3.ZERO, 0.5, 2.0))   # dhad
	var head := SphereMesh.new()
	head.radius = 0.38
	head.height = 0.76
	placeholder.add_child(part_of(head, gold, Vector3(0, 4.2, 0), Vector3.ZERO))
	var jata := CylinderMesh.new()
	jata.top_radius = 0.1
	jata.bottom_radius = 0.35
	jata.height = 0.7
	placeholder.add_child(part_of(jata, gold, Vector3(0, 4.75, 0), Vector3.ZERO))
	# Chaar bhujaayein
	placeholder.add_child(shape_part(CapsuleMesh.new(), gold, Vector3(0.95, 3.6, 0), Vector3(0, 0, -55), 0.13, 1.8))
	placeholder.add_child(shape_part(CapsuleMesh.new(), gold, Vector3(-0.95, 3.6, 0), Vector3(0, 0, 55), 0.13, 1.8))
	placeholder.add_child(shape_part(CapsuleMesh.new(), gold, Vector3(0.9, 2.9, 0.2), Vector3(0, 0, -110), 0.13, 1.8))
	placeholder.add_child(shape_part(CapsuleMesh.new(), gold, Vector3(-0.9, 2.9, 0.2), Vector3(0, 0, 110), 0.13, 1.8))
	# Do taangein (ek khadi, ek uthi hui)
	placeholder.add_child(shape_part(CapsuleMesh.new(), gold, Vector3(0.25, 1.0, 0), Vector3.ZERO, 0.2, 2.0))
	placeholder.add_child(shape_part(CapsuleMesh.new(), gold, Vector3(-0.6, 2.0, 0.4), Vector3(60, 0, 0), 0.2, 1.8))
	var lotus := CylinderMesh.new()
	lotus.top_radius = 1.1
	lotus.bottom_radius = 1.3
	lotus.height = 0.2
	placeholder.add_child(part_of(lotus, gold, Vector3(0, 0.1, 0), Vector3.ZERO))

	try_statue_model(placeholder)

	statue_light = OmniLight3D.new()
	statue_light.light_color = GOLD
	statue_light.light_energy = 0.0
	statue_light.omni_range = 24.0
	statue_light.position = STATUE_POS + Vector3(-4.0, 5.0, 0.0)
	add_child(statue_light)

func part_of(mesh: Mesh, material: Material, pos: Vector3, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	return mi

func shape_part(capsule: CapsuleMesh, material: Material, pos: Vector3, rot_deg: Vector3, radius: float, height: float) -> MeshInstance3D:
	capsule.radius = radius
	capsule.height = height
	return part_of(capsule, material, pos, rot_deg)

# models/nataraj.glb (ya .gltf) ho to placeholder ki jagah wahi lagao (7 meter ooncha)
func try_statue_model(placeholder: Node3D) -> void:
	var path: String = ""
	for ext in ["glb", "gltf", "fbx", "GLB", "GLTF", "FBX"]:
		var p: String = "res://models/nataraj." + ext
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
	statue_root.add_child(model)

	var box: AABB = model_aabb(model)
	if box.size.y <= 0.001:
		model.queue_free()
		return
	model.scale = Vector3.ONE * (7.0 / box.size.y)
	box = model_aabb(model)
	var current := Vector3(box.position.x + box.size.x / 2.0, box.position.y, box.position.z + box.size.z / 2.0)
	model.position -= current
	placeholder.visible = false

func model_aabb(root: Node3D) -> AABB:
	var to_local: Transform3D = statue_root.global_transform.affine_inverse()
	var result := AABB()
	var first: bool = true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b: AABB = to_local * mi.global_transform * mi.get_aabb()
		if first:
			result = b
			first = false
		else:
			result = result.merge(b)
	return result

# ---------------- Black hole portal ----------------
func build_portal() -> void:
	var shader := Shader.new()
	shader.code = PORTAL_SHADER
	portal_mat = ShaderMaterial.new()
	portal_mat.shader = shader
	portal_mat.set_shader_parameter("amount", 0.0)

	var quad := QuadMesh.new()
	quad.size = Vector2(10.0, 10.0)
	portal = MeshInstance3D.new()
	portal.mesh = quad
	portal.material_override = portal_mat
	portal.position = STATUE_POS + Vector3(0, 4.6, 0)
	portal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	portal.visible = false
	add_child(portal)

# ---------------- UI ----------------
func build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 9
	add_child(canvas)

	hit_overlay = ColorRect.new()
	hit_overlay.color = Color(0, 0, 0, 0)
	hit_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hit_overlay)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans Devanagari", "Noto Sans", "sans-serif"])

	hud_label = make_hud_label(font, 40, 70.0, Color(1.0, 0.85, 0.4))
	hud_label.visible = false
	canvas.add_child(hud_label)

	toast_label = make_hud_label(font, 30, 130.0, Color(0.98, 0.92, 0.78))
	toast_label.modulate.a = 0.0
	canvas.add_child(toast_label)

func make_hud_label(font: Font, size: int, top: float, color: Color) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.offset_top = top
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

func update_hud() -> void:
	hud_label.text = "मशालें: %d / %d" % [lit_count, masals.size()]

func toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.8)

# ---------------- Audio ----------------
func build_audio() -> void:
	tandav_player = AudioStreamPlayer.new()
	tandav_player.volume_db = -40.0
	add_child(tandav_player)
	if game_manager_node and game_manager_node.has_method("load_audio"):
		var st: AudioStream = game_manager_node.load_audio("res://audio/shiv_tandav")
		if st:
			if st is AudioStreamMP3 or st is AudioStreamOggVorbis:
				st.set("loop", true)
			tandav_player.stream = st
			tandav_player.finished.connect(_on_tandav_finished)

	# Jharne ki awaaz (door se bhi halki sunayi deti hai)
	if game_manager_node and game_manager_node.has_method("get_sfx_stream"):
		var ws: AudioStream = game_manager_node.get_sfx_stream("water")
		if ws:
			var water := AudioStreamPlayer3D.new()
			water.stream = ws
			water.unit_size = 25.0
			water.max_distance = 140.0
			water.volume_db = -4.0
			water.position = Vector3(236.0, 3.0, 0.0)
			add_child(water)
			water.play()

func _on_tandav_finished() -> void:
	if statue_revealed and not finished:
		tandav_player.play()

# ---------------- Game loop ----------------
func _physics_process(delta: float) -> void:
	if player == null or player.camera == null:
		return

	if active and not complete:
		var cam: Camera3D = player.camera
		var origin: Vector3 = cam.global_position
		var forward: Vector3 = -cam.global_transform.basis.z
		var space := get_world_3d().direct_space_state
		var torch_on: bool = player.is_torch_on
		update_masals(delta, origin, forward, space, torch_on)

	if statue_revealed:
		update_statue_and_portal(delta)

func beam_hits(target: Vector3, angle_deg: float, max_dist: float, origin: Vector3, forward: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var to_t: Vector3 = target - origin
	var dist: float = to_t.length()
	if dist > max_dist or dist < 0.1:
		return false
	var dir: Vector3 = to_t / dist
	if forward.dot(dir) < cos(deg_to_rad(angle_deg)):
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [player.get_rid()]
	return space.intersect_ray(query).is_empty()

# --- Masal jagana ---
func update_masals(delta: float, origin: Vector3, forward: Vector3, space: PhysicsDirectSpaceState3D, torch_on: bool) -> void:
	for m in masals:
		if m.lit:
			continue
		var lit: bool = torch_on and beam_hits(m.flame_pos, masal_beam_angle, masal_range, origin, forward, space)
		if lit:
			m.charge += delta
		else:
			m.charge = maxf(0.0, m.charge - delta * 0.5)
		var t: float = clampf(m.charge / masal_charge_time, 0.0, 1.0)
		m.ember_mat.emission_energy_multiplier = lerpf(0.5, 5.0, t)
		m.light.light_energy = lerpf(0.5, 3.0, t)
		if m.charge >= masal_charge_time:
			ignite(m)

func ignite(m: Masal) -> void:
	m.lit = true
	lit_count += 1
	m.fire.emitting = true
	m.light.light_energy = 5.0
	m.light.omni_range = 40.0
	m.ember_mat.emission_energy_multiplier = 6.0
	# Har masal jalne par andhera kam hota jata hai
	var wg := get_node_or_null("../WorldGenerator")
	if wg and wg.has_method("set_daylight"):
		wg.set_daylight(float(lit_count) / float(masals.size()))
	sfx("rune")
	update_hud()
	if lit_count >= masals.size():
		on_all_lit()
	else:
		toast("मशाल जल उठी!")

func on_all_lit() -> void:
	complete = true
	toast("चारों मशालें जल उठीं... महादेव का द्वार प्रकट हो रहा है")
	sfx("complete")
	sfx("door", -4.0)
	reveal_statue()

func reveal_statue() -> void:
	statue_revealed = true
	statue_root.visible = true
	statue_root.scale = Vector3.ONE * 0.05
	var t := create_tween().set_parallel(true)
	t.tween_property(statue_root, "scale", Vector3.ONE, 3.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(waterfall_mat, "shader_parameter/glow", 1.0, 4.0)
	t.tween_property(statue_light, "light_energy", 2.5, 3.0)

# --- Yoddha (talwar wale pehredaar) ---
func spawn_warriors() -> void:
	var warrior_script := load("res://warrior.gd") as Script
	if warrior_script == null:
		return
	# 4 masalon ke paas ek-ek, 2 murti ke paas
	var posts: Array[Vector3] = [
		Vector3(134.0, 0.0, -38.0), Vector3(134.0, 0.0, 38.0),
		Vector3(199.0, 0.0, -38.0), Vector3(199.0, 0.0, 38.0),
		Vector3(221.0, 0.0, -7.0), Vector3(221.0, 0.0, 7.0)
	]
	for pos in posts:
		var w := CharacterBody3D.new()
		w.set_script(warrior_script)
		w.set("player", player)
		w.set("game_manager", game_manager_node)
		w.set("home", pos)
		w.position = pos + Vector3(0.0, 0.1, 0.0)
		add_child(w)
		warriors.append(w)

# Khilaadi gir jaye to maidan ke pravesh par uthta hai, bache hue yoddha apni jagah laut jate hain
func _on_player_died() -> void:
	toast("तुम गिर गए... फिर उठो")
	var t := create_tween()
	t.tween_property(hit_overlay, "color:a", 1.0, 0.7)
	await t.finished
	player.respawn_at(Vector3(110.0, 0.5, 0.0))
	for w in warriors:
		if is_instance_valid(w) and w.has_method("reset_to_home"):
			w.reset_to_home()
	await get_tree().create_timer(0.5).timeout
	create_tween().tween_property(hit_overlay, "color:a", 0.0, 0.8)

# --- Murti, Tandav aur portal ---
func update_statue_and_portal(delta: float) -> void:
	var p: Vector3 = player.global_position
	var dist: float = Vector2(p.x - STATUE_POS.x, p.z - STATUE_POS.z).length()

	# Shiv Tandav: paas jaate hi dheere se shuru
	if tandav_player.stream and not finished:
		var target: float = lerpf(-40.0, -6.0, clampf((50.0 - dist) / 35.0, 0.0, 1.0))
		if dist < 50.0 and not tandav_player.playing:
			tandav_player.play()
		tandav_player.volume_db = lerpf(tandav_player.volume_db, target, 0.05)

	if not portal_open:
		if dist < 9.0:
			open_portal()
	elif not finished:
		portal_age += delta
		portal.look_at(Vector3(p.x, portal.global_position.y, p.z), Vector3.UP)
		if portal_age > 3.0 and dist < 3.4:
			finish_level()

func open_portal() -> void:
	portal_open = true
	toast("महादेव का द्वार खुल गया... अंदर जाओ")
	sfx("door")
	sfx("complete", -4.0)
	portal.visible = true
	portal.scale = Vector3.ONE * 0.05
	var t := create_tween().set_parallel(true)
	t.tween_property(portal, "scale", Vector3.ONE, 3.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(portal_mat, "shader_parameter/amount", 1.0, 2.5)
	t.tween_property(statue_root, "scale", Vector3.ONE * 0.01, 2.0).set_delay(0.5)

func finish_level() -> void:
	finished = true
	print("LEVEL 2 COMPLETE")
	var t := create_tween()
	t.tween_property(hit_overlay, "color", Color(0, 0, 0, 1), 1.6)
	await t.finished
	player.set_physics_process(false)
	if tandav_player.playing:
		create_tween().tween_property(tandav_player, "volume_db", -40.0, 3.0)
	if magical_node and magical_node.has_method("trigger_hatim_scroll"):
		magical_node.trigger_hatim_scroll("द्वार पार हो गया, मुसाफिर... सातों पहेलियों का सफ़र अभी बाकी है। अगला लेवल जल्द ही आ रहा है।", "")
