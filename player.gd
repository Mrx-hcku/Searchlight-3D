extends CharacterBody3D

@export var speed: float = 6.0
@export var touch_sensitivity: float = 0.004

var camera: Camera3D
var spot_light: SpotLight3D
var game_manager: Node

# Touch Controls State for Android
var touch_screen_size: Vector2
var look_touch_index: int = -1
var move_touch_index: int = -1

var last_look_pos: Vector2 = Vector2.ZERO
var move_joystick_center: Vector2 = Vector2.ZERO
var move_direction_input: Vector2 = Vector2.ZERO
var is_torch_on: bool = true
var step_timer: float = 0.0

var torch_btn: Button
var joy_base: Panel
var joy_knob: Panel

func _ready() -> void:
	touch_screen_size = get_viewport().get_visible_rect().size
	game_manager = get_node_or_null("../GameManager")

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

func play_sfx(sfx_name: String) -> void:
	if game_manager and game_manager.has_method("play_sfx"):
		game_manager.play_sfx(sfx_name)

func setup_touch_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var w: float = touch_screen_size.x
	var h: float = touch_screen_size.y

	# Free Fire style gol Torch button (neeche right me, anguthe ki pahunch me)
	torch_btn = Button.new()
	torch_btn.custom_minimum_size = Vector2(120, 120)
	torch_btn.size = Vector2(120, 120)
	torch_btn.position = Vector2(w - 170, h - 400)
	torch_btn.focus_mode = Control.FOCUS_NONE
	torch_btn.add_theme_font_size_override("font_size", 22)
	torch_btn.pressed.connect(toggle_torch)
	canvas.add_child(torch_btn)
	update_torch_button()

	# Chhota crosshair (beech me)
	var dot := make_circle(10.0, Color(1, 1, 1, 0.5))
	dot.position = Vector2(w / 2.0 - 5.0, h / 2.0 - 5.0)
	dot.visible = true
	canvas.add_child(dot)

	# Visible joystick (touch karne par dikhta hai)
	joy_base = make_circle(180.0, Color(1, 1, 1, 0.12))
	joy_knob = make_circle(80.0, Color(1, 1, 1, 0.35))
	canvas.add_child(joy_base)
	canvas.add_child(joy_knob)

func update_torch_button() -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(60)
	sb.set_border_width_all(3)
	if is_torch_on:
		sb.bg_color = Color(1.0, 0.85, 0.3, 0.35)
		sb.border_color = Color(1.0, 0.9, 0.5, 0.9)
		torch_btn.text = "TORCH\nON"
	else:
		sb.bg_color = Color(0.1, 0.1, 0.1, 0.35)
		sb.border_color = Color(1, 1, 1, 0.4)
		torch_btn.text = "TORCH\nOFF"
	for state in ["normal", "hover", "pressed", "focus"]:
		torch_btn.add_theme_stylebox_override(state, sb)

func toggle_torch() -> void:
	is_torch_on = !is_torch_on
	spot_light.visible = is_torch_on
	update_torch_button()
	play_sfx("click")

func make_circle(diameter: float, color: Color) -> Panel:
	var p := Panel.new()
	p.size = Vector2(diameter, diameter)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(diameter / 2.0))
	sb.border_color = Color(1, 1, 1, 0.4)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	return p

func _process(_delta: float) -> void:
	var active: bool = move_touch_index != -1
	joy_base.visible = active
	joy_knob.visible = active
	if active:
		joy_base.position = move_joystick_center - joy_base.size / 2.0
		joy_knob.position = move_joystick_center + move_direction_input * 60.0 - joy_knob.size / 2.0

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# Torch button par touch ko movement/look na samjho
			if torch_btn.get_global_rect().has_point(event.position):
				return
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
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	var direction := (transform.basis * Vector3(move_direction_input.x, 0, move_direction_input.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

	# Footsteps
	var moving: bool = direction != Vector3.ZERO and is_on_floor()
	if moving:
		step_timer += delta
		if step_timer >= 0.42:
			step_timer = 0.0
			play_sfx("step")
	else:
		step_timer = 0.3
