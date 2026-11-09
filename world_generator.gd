extends Node3D

@export var world_size: int = 50

var env: Environment

func _ready() -> void:
	setup_environment()
	generate_procedural_environment()

# Halki ambient roshni taaki andhere me bhi aas-paas thoda dikhe
func setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.85)
	env.ambient_light_energy = 2.0

	# Professional look: filmic tonemap (safed jalna band), halka rang-sudhaar aur door ki dhundh
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.02, 0.05)
	env.fog_density = 0.008
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Chandni: Main.tscn ki directional light ko thoda tez kar do
	var moon := get_node_or_null("../DirectionalLight3D") as DirectionalLight3D
	if moon:
		moon.light_color = Color(0.5, 0.55, 0.85)
		moon.light_energy = 0.9

func generate_procedural_environment() -> void:
	# Ground (visual)
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(200, 200)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.15, 0.20)
	material.roughness = 0.8
	material.metallic = 0.0

	var ground_instance := MeshInstance3D.new()
	ground_instance.mesh = ground_mesh
	ground_instance.material_override = material
	add_child(ground_instance)

	# Ground (collision) - y=0 par infinite floor
	var ground_body := StaticBody3D.new()
	var ground_col := CollisionShape3D.new()
	ground_col.shape = WorldBoundaryShape3D.new()
	ground_body.add_child(ground_col)
	add_child(ground_body)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.17, 0.17, 0.23)
	pillar_mat.roughness = 0.9

	for i in range(30):
		var box := BoxMesh.new()
		box.size = Vector3(rng.randf_range(3, 8), rng.randf_range(15, 30), rng.randf_range(3, 8))

		var x_pos := rng.randf_range(-45, 45)
		var z_pos := rng.randf_range(-45, 45)

		# Maze (x,z: -22 se 18) ke andar pillar nahi
		if x_pos > -30 and x_pos < 26 and z_pos > -30 and z_pos < 26:
			continue

		var p_pillar := MeshInstance3D.new()
		p_pillar.mesh = box
		p_pillar.material_override = pillar_mat
		p_pillar.position = Vector3(x_pos, box.size.y / 2.0, z_pos)

		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		col.shape = shape
		body.add_child(col)
		p_pillar.add_child(body)

		add_child(p_pillar)

	print("Procedural Dark Environment & Structures Generated Successfully.")

# Darwaze ke bahar nikalte hi duniya jaadui ho jaati hai (level script isse bulati hai)
func enter_magical_world() -> void:
	if env == null:
		return
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1

	var t := create_tween().set_parallel(true)
	t.tween_property(env, "background_color", Color(0.07, 0.03, 0.16), 4.0)
	t.tween_property(env, "ambient_light_color", Color(0.62, 0.58, 0.92), 4.0)
	t.tween_property(env, "ambient_light_energy", 2.0, 4.0)
	t.tween_property(env, "fog_light_color", Color(0.07, 0.03, 0.16), 4.0)
	t.tween_property(env, "fog_density", 0.004, 4.0)
	var moon := get_node_or_null("../DirectionalLight3D") as DirectionalLight3D
	if moon:
		t.tween_property(moon, "light_color", Color(0.60, 0.45, 0.95), 4.0)

# Level 2: har masal jalne par ujala badhta hai (t: 0 = jaadui andhera, 1 = lagbhag din jaisa)
func set_daylight(t: float, duration: float = 2.5) -> void:
	if env == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(env, "ambient_light_energy", lerpf(2.0, 3.4, t), duration)
	tw.tween_property(env, "ambient_light_color", Color(0.62, 0.58, 0.92).lerp(Color(1.0, 0.93, 0.78), t), duration)
	tw.tween_property(env, "fog_light_color", Color(0.07, 0.03, 0.16).lerp(Color(0.55, 0.42, 0.50), t), duration)
	tw.tween_property(env, "background_color", Color(0.07, 0.03, 0.16).lerp(Color(0.60, 0.45, 0.55), t), duration)
	var moon := get_node_or_null("../DirectionalLight3D") as DirectionalLight3D
	if moon:
		tw.tween_property(moon, "light_energy", lerpf(0.9, 1.7, t), duration)
		tw.tween_property(moon, "light_color", Color(0.60, 0.45, 0.95).lerp(Color(1.0, 0.9, 0.75), t), duration)
