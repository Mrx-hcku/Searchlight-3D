extends CharacterBody3D

@export var speed: float = 5.0
@export var mouse_sensitivity: float = 0.003

@onready var camera = $Camera3D

func _ready():
	# माउस को स्क्रीन के बीच में लॉक करने के लिए
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		# कैमरे (टॉर्च) को घुमाने के लिए
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.clamp(deg_to_rad(-89), deg_to_rad(89))

func _physics_process(delta):
	# कीबोर्ड से इनपुट (W, A, S, D) लेना
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
