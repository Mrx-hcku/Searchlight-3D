extends Node3D

@export var maze_size: Vector2i = Vector2i(10, 10)
@export var wall_height: float = 8.0

var maze_walls = []
var active_runes_found: int = 0
var total_runes_required: int = 3
var magical_elements_node: Node

func _ready() -> void:
	generate_dark_maze()
	spawn_hidden_runes()
	
	magical_elements_node = get_node_or_null("../MagicalElements")
	
	get_tree().create_timer(2.0).timeout.connect(func():
		if magical_elements_node and magical_elements_node.has_method("trigger_hatim_scroll"):
			var puzzle_1 = "सुनो ऐ मुसाफिर! इस अंधेरी भूलभुलैया में दीवारों पर 3 गुप्त चमकते संकेत (Runes) छिपे हैं। अपनी सर्चलाइट की किरण से उन्हें ढूंढो, वरना ये गूंजती दीवारें तुम्हें कभी बाहर नहीं जाने देंगी!"
			magical_elements_node.trigger_hatim_scroll(puzzle_1)
	)

func generate_dark_maze() -> void:
	var wall_material = StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.02, 0.02, 0.04)
	wall_material.roughness = 0.95

	for x in range(maze_size.x):
		for z in range(maze_size.y):
			if (x == 0 or z == 0 or x == maze_size.x - 1 or z == maze_size.y - 1 or (x % 2 == 0 and z % 2 == 0)):
				var wall = MeshInstance3D.new()
				var box = BoxMesh.new()
				box.size = Vector3(4.0, wall_height, 4.0)
				wall.mesh = box
				wall.material_override = wall_material
				wall.position = Vector3(x * 4.0 - 20, wall_height / 2, z * 4.0 - 20)
				
				var static_body = StaticBody3D.new()
				var collision_shape = CollisionShape3D.new()
				var box_shape = BoxShape3D.new()
				box_shape.size = box.size
				collision_shape.shape = box_shape
				static_body.add_child(collision_shape)
				wall.add_child(static_body)
				
				add_child(wall)

func spawn_hidden_runes() -> void:
	var rune_positions = [
		Vector3(-12, 2.5, -8),
		Vector3(8, 2.5, 4),
		Vector3(0, 2.5, 12)
	]

	for i in range(rune_positions.size()):
		var rune_area = Area3D.new()
		var col = CollisionShape3D.new()
		var sphere = SphereShape3D.new()
		sphere.radius = 1.5
		col.shape = sphere
		rune_area.add_child(col)
		
		var rune_mesh = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(1.2, 1.2)
		rune_mesh.mesh = plane
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.6, 0.1)
		mat.emission_energy_multiplier = 4.0
		rune_mesh.material_override = mat
		rune_mesh.rotation_degrees.x = 90
		
		rune_area.add_child(rune_mesh)
		rune_area.position = rune_positions[i]
		add_child(rune_area)

		rune_area.body_entered.connect(func(body):
			if body.name == "Player":
				on_rune_activated(rune_mesh)
		)

func on_rune_activated(mesh: MeshInstance3D) -> void:
	active_runes_found += 1
	print("Rune Found! Total: ", active_runes_found, "/", total_runes_required)
	mesh.queue_free()
	
	if active_runes_found >= total_runes_required:
		unlock_maze_exit()

func unlock_maze_exit() -> void:
	print("Level 1 Cleared! The Dark Maze door opens...")
	if magical_elements_node and magical_elements_node.has_method("trigger_hatim_scroll"):
		magical_elements_node.trigger_hatim_scroll("शाबाश! तुमने पहली पहेली सुलझा ली है। अंधेरी भूलभुलैया का निकास द्वार खुल चुका है!")
