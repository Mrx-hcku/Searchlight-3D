extends Node3D

@export var world_size: int = 50

func _ready() -> void:
	generate_procedural_environment()

func generate_procedural_environment() -> void:
	var ground_mesh = PlaneMesh.new()
	ground_mesh.size = Vector2(200, 200)
	
	var ground_instance = MeshInstance3D.new()
	ground_instance.mesh = ground_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.03, 0.03, 0.05)
	material.roughness = 0.8
	material.metallic = 0.2
	ground_instance.material_override = material
	
	add_child(ground_instance)
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for i in range(30):
		var p_pillar = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(rng.randf_range(3, 8), rng.randf_range(15, 30), rng.randf_range(3, 8))
		p_pillar.mesh = box
		
		var pillar_mat = StandardMaterial3D.new()
		pillar_mat.albedo_color = Color(0.02, 0.02, 0.03)
		pillar_mat.roughness = 0.9
		p_pillar.material_override = pillar_mat
		
		var x_pos = rng.randf_range(-80, 80)
		var z_pos = rng.randf_range(-80, 80)
		if abs(x_pos) > 10 or abs(z_pos) > 10:
			p_pillar.position = Vector3(x_pos, box.size.y / 2, z_pos)
			add_child(p_pillar)
			
	print("Procedural Dark Environment & Structures Generated Successfully.")
