extends CharacterBody3D

@export var speed: float = 6.0
@export var touch_sensitivity: float = 0.004

var camera: Camera3D
var spot_light: SpotLight3D

# Touch Controls State for Android
var touch_screen_size: Vector2
var look_touch_index: int = -1
var move_touch_index: int = -1

var last_look_pos: Vector2 = Vector2.ZERO
var move_joystick_center: Vector2 = Vector2.ZERO
var move_direction_input: Vector2 = Vector2.ZERO
var is_torch_on: bool = true

func _ready() -> void:
	touch_screen_size = get_viewport().get_visible_rect().size

	# Collision
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	col.shape = shape
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# Camera Setup
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.8, 0)
	add_child(camera)

	# High-Intensity Android Searchlight Torch
	spot_light = SpotLight3D.new()
	spot_light.light_color = Color(0.9, 0.95, 1.0)
	spot_light.light_energy = 16.0
	spot_light.spot_range = 35.0
	spot_light.spot_angle = 35.0
	spot_light.shadow_enabled = true
	camera.add_child(spot_light)
	spot_light.position = Vector3(0, 0, 0)

	setup_touch_ui()

func setup_touch_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var torch_btn := Button.new()
	torch_btn.text = "Torch ON/OFF"
	torch_btn.custom_minimum_size = Vector2(160, 60)
	torch_btn.position = Vector2(touch_screen_size.x - 180, 40)
	torch_btn.pressed.connect(toggle_torch)
	canvas.add_child(torch_btn)

func toggle_torch() -> void:
	is_torch_on = !is_torch_on
	spot_light.visible = is_torch_on

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# Right side: look around
			if event.position.x > touch_screen_size.x / 2 and look_touch_index == -1:
				look_touch_index = event.index
				last_look_pos = event.position
			# Left side: movement joystick
			elif event.position.x <= touch_screen_size.x / 2 and move_touch_index == -1:
				move_touch_index = event.index
				move_joystick_center = event.position
		else:
			if event.index == look_touch_index:
				look_touch_index = -1
			elif event.index == move_touch_index:
				move_touch_index = -1
				move_direction_input = Vector2.ZERO

	elif event is InputEventScreenDrag:
		if event.index == look_touch_index:
			var delta_move: Vector2 = event.position - last_look_pos
			last_look_pos = event.position

			rotate_y(-delta_move.x * touch_sensitivity)
			camera.rotate_x(-delta_move.y * touch_sensitivity)
			camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

		elif event.index == move_touch_index:
			var offset: Vector2 = event.position - move_joystick_center
			move_direction_input = offset.limit_length(60.0) / 60.0

func _physics_process(delta: float) -> void:
	var direction := (transform.basis * Vector3(move_direction_input.x, 0, move_direction_input.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
