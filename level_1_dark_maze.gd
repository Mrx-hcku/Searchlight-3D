extends Node3D

@export var maze_size: Vector2i = Vector2i(10, 10)
@export var wall_height: float = 8.0
@export var beam_angle_deg: float = 12.0   # torch ki kiran kitni seedhi honi chahiye
@export var beam_range: float = 25.0
@export var charge_time: float = 1.0       # rune par kitni der kiran tikani hai

class Rune:
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
var exit_door: Node3D
var exit_unlocked: bool = false
var level_complete: bool = false

func _ready() -> void:
	magical_elements_node = get_node_or_null("../MagicalElements")
	game_manager_node = get_node_or_null("../GameManager")
	player = get_node_or_null("../Player")

	generate_dark_maze()
	spawn_hidden_runes()
	create_exit_trigger()

	await get_tree().create_timer(2.0).timeout
	show_scroll("सुनो ऐ मुसाफिर! इस अंधेरी भूलभुलैया में दीवारों पर 3 गुप्त चमकते संकेत (Runes) छिपे हैं। अपनी सर्चलाइट की किरण को संकेत पर कुछ पल टिकाए रखो, वरना ये गूंजती दीवारें तुम्हें कभी बाहर नहीं जाने देंगी!")

func show_scroll(text: String) -> void:
	if magical_elements_node and magical_elements_node.has_method("trigger_hatim_scroll"):
		magical_elements_node.trigger_hatim_scroll(text)

func sfx(sfx_name: String) -> void:
	if game_manager_node and game_manager_node.has_method("play_sfx"):
		game_manager_node.play_sfx(sfx_name)

# ---------- Maze ----------
func generate_dark_maze() -> void:
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.16, 0.16, 0.22)
	wall_material.roughness = 0.95

	# Exit darwaza: laal chamakta block
	var door_material := StandardMaterial3D.new()
	door_material.albedo_color = Color(0.3, 0.02, 0.02)
	door_material.emission_enabled = true
	door_material.emission = Color(1.0, 0.1, 0.1)
	door_material.emission_energy_multiplier = 1.5

	var exit_cell := Vector2i(maze_size.x - 1, int(maze_size.y / 2.0))

	for x in range(maze_size.x):
		for z in range(maze_size.y):
			var is_border: bool = (x == 0 or z == 0 or x == maze_size.x - 1 or z == maze_size.y - 1)
			var is_pillar: bool = (x % 2 == 0 and z % 2 == 0)
			if not (is_border or is_pillar):
				continue

			if Vector2i(x, z) == exit_cell:
				exit_door = make_block(x, z, door_material)
			else:
				make_block(x, z, wall_material)

func make_block(x: int, z: int, material: Material) -> Node3D:
	var box := BoxMesh.new()
	box.size = Vector3(4.0, wall_height, 4.0)

	var wall := MeshInstance3D.new()
	wall.mesh = box
	wall.material_override = material
	wall.position = Vector3(x * 4.0 - 20.0, wall_height / 2.0, z * 4.0 - 20.0)

	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	collision_shape.shape = box_shape
	static_body.add_child(collision_shape)
	wall.add_child(static_body)

	add_child(wall)
	return wall

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
		runes.append(r)

func _physics_process(delta: float) -> void:
	if runes.is_empty() or player == null or player.camera == null:
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

	if active_runes_found >= total_runes_required:
		unlock_maze_exit()
	else:
		show_scroll("एक संकेत जाग उठा! (%d/%d)" % [active_runes_found, total_runes_required])

# ---------- Exit ----------
func unlock_maze_exit() -> void:
	if exit_unlocked:
		return
	exit_unlocked = true
	print("Level 1 Cleared! The Dark Maze door opens...")
	sfx("door")

	if is_instance_valid(exit_door):
		var tween := create_tween()
		tween.tween_property(exit_door, "position:y", -wall_height, 1.5)
		tween.tween_callback(exit_door.queue_free)

	show_scroll("शाबाश! तुमने पहली पहेली सुलझा ली है। अंधेरी भूलभुलैया का लाल चमकता निकास द्वार खुल चुका है!")

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
	if body.name != "Player" or not exit_unlocked or level_complete:
		return
	level_complete = true
	print("LEVEL 1 COMPLETE")
	sfx("complete")
	show_scroll("बधाई हो मुसाफिर! अंधेरी भूलभुलैया पार हो गई। अगली पहेली परछाइयों के शाही कक्ष में तुम्हारा इंतज़ार कर रही है... (जल्द आ रहा है)")
