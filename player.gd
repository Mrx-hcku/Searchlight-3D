extends CharacterBody3D

@export var speed: float = 6.0
@export var mouse_sensitivity: float = 0.003

var camera: Camera3D
var spot_light: SpotLight3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.8, 0)
	add_child(camera)
	
	spot_light = SpotLight3D.new()
	spot_light.light_color = Color(0.9, 0.95, 1.0)
	spot_light.light_energy = 16.0
	spot_light.spot_range = 35.0
	spot_light.spot_angle = 35.0
	spot_light.shadow_enabled = true
	camera.add_child(spot_light)
	spot_light.position = Vector3(0, 0, 0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.clamp(Vector3(deg_to_rad(-80), 0, 0), Vector3(deg_to_rad(80), 0, 0))

func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		
	move_and_slide()
